require "./repl"
require "../ffi"
require "colorize"
require "../../../crystal/syntax_highlighter/colorize"

# The ones that understands Crystal bytecode.
class Crystal::Repl::Interpreter
  record CallFrame,
    # The CompiledDef related to this call frame
    compiled_def : CompiledDef,
    # The CompiledBlock related to this call frame, if any
    compiled_block : CompiledBlock?,
    # Instructions for this frame
    instructions : CompiledInstructions,
    # The pointer to the current instruction for this call frame.
    # This value changes as the program goes, and when a call is made
    # this value is useful to know where we need to continue after
    # the call returns.
    ip : Pointer(UInt8),
    # What's the frame's stack.
    # This value changes as the program goes, and when a call is made
    # this value is useful to know what values in the stack we need
    # to have when the call returns.
    stack : Pointer(UInt8),
    # What's the frame's stack bottom. After this position come the
    # def's local variables.
    stack_bottom : Pointer(UInt8),
    # The index of the frame that called a block.
    # This is useful to know because when a `yield` happens,
    # we more or less create a new stack frame that has the same
    # local variables as this frame, because the block will need
    # to access that frame's variables.
    # It's -1 if the value is not present.
    block_caller_frame_index : Int32,
    # When a `yield` happens we copy the frame pointed by
    # `block_caller_frame_index`. If a `return` happens inside
    # that block we need to return from that frame (the `def`s one.)
    # With `real_frame_index` we know where that frame is actually
    # in the call stack (the original, not the copy) and we can
    # go back to just before that frame when a `return` happens.
    real_frame_index : Int32,
    # This is a bit hacky, but...
    # Right now, when we produce an OverflowError we do it directly
    # in the instruction that potentially produces the overflow.
    # When we do that, the backtrace that is produced in that case
    # is incorrect because the backtrace computing logic assumes
    # an all call frames are, well, calls. But in this case it could
    # be an `add_i32` instruction which has a different layout.
    # To solve this, we have an optional `overflow_offset` that
    # we put on a frame to indicate that the caller frame must
    # add to get the correct backtrace location.
    overflow_offset : Int32

  getter context : Context

  # Are we in pry mode?
  getter? pry : Bool = false

  # What's the last node we went over pry? This is useful to know
  # because when doing `next` or `step` we want to stop at a node
  # that has a different file/line number than this node
  @pry_node : ASTNode?

  # What's the maximum call stack frame index we want to stop at
  # when doing `next`, `step` or `finish`:
  # - when doing `next`, we want to continue in the same frame, or
  #   the one above us (we don't want to go deeper)
  # - when doing `step`, there's no maximum frame
  # - when doing `finish`, we'd like to exit the current frame
  @pry_max_target_frame : Int32?

  # The input reader for the pry interface, it's stored here notably to hold the history.
  @pry_reader : PryReader

  # The set of local variables for interpreting code.
  getter local_vars : LocalVars

  # Memory for the stack.
  getter stack : Pointer(UInt8)

  # Values for `argv`, set when using `crystal i file.cr arg1 arg2 ...`.
  property argv : Array(String)

  SMALL_RETURN_VALUE_MAX_SIZE = 48

  # This is a value that's being returned from inside a block.
  # The tricky part here is that we need to return from a method, but we also
  # need to execute any ensures. So, we store the returned value in this struct
  # and start going up the call stack.
  # `target_frame_index` is the frame index where we must stop.
  alias ReturnedValue = SmallReturnedValue | BigReturnedValue

  # This is a returned value that fits in 48 bytes.
  # Most return values will fit here, so we avoid allocating memory for this.
  record SmallReturnedValue, value : StaticArray(UInt8, SMALL_RETURN_VALUE_MAX_SIZE), size : Int32, target_frame_index : Int32 do
    def pointer
      @value.to_unsafe
    end
  end

  # When the return value is bigger than 48 bytes we use this struct.
  record BigReturnedValue, pointer : Pointer(UInt8), size : Int32, target_frame_index : Int32

  # This is an exception that's being raised.
  # Here we also need to go up the call stack.
  record RaisedException, exception : Pointer(UInt8)

  # An alias for either a returned value or a raised exception.
  # When an ensure handler is executed because an exception was raised
  # or because a value was returned, we abstract any of those in this type.
  alias ThrowValue = ReturnedValue | RaisedException

  def initialize(
    @context : Context,
    # TODO: what if the stack is exhausted?
    @stack : UInt8* = Pointer(Void).malloc(8 * 1024 * 1024).as(UInt8*),
  )
    @local_vars = LocalVars.new(@context)
    @argv = [] of String

    @instructions = CompiledInstructions.new

    @call_stack = [] of CallFrame
    @call_stack_leave_index = 0

    @block_level = 0

    @compiled_def = nil

    @pry_reader = PryReader.new
    @pry_reader.color = @context.program.color?
  end

  def self.new(interpreter : Interpreter, compiled_def : CompiledDef, stack : Pointer(UInt8), block_level : Int32)
    new(interpreter, compiled_def, compiled_def.local_vars, compiled_def.closure_context, stack, block_level)
  end

  def initialize(interpreter : Interpreter, compiled_def : CompiledDef, local_vars : LocalVars, @closure_context : ClosureContext?, stack : Pointer(UInt8), @block_level : Int32)
    @context = interpreter.context
    @local_vars = local_vars.dup
    @argv = interpreter.@argv

    @instructions = CompiledInstructions.new

    @stack = stack
    @call_stack = interpreter.@call_stack.dup
    @call_stack_leave_index = @call_stack.size

    @compiled_def = compiled_def

    @pry_reader = PryReader.new
    @pry_reader.color = @context.program.color?
  end

  # Interprets the give node under the given context.
  # Yields the interpreter stack to potentially fill out any values in
  # it before execution.
  def self.interpret(context : Context, node : ASTNode, & : UInt8* -> _) : Repl::Value
    context.checkout_stack do |stack|
      interpreter = Interpreter.new(context, stack)

      yield stack

      main_visitor = MainVisitor.new(context.program, meta_vars: MetaVars.new)

      node = context.program.normalize(node)
      node = context.program.semantic(node, main_visitor: main_visitor)

      interpreter.interpret(node, main_visitor.meta_vars)
    end
  end

  # compiles the given code to bytecode, then interprets it by assuming the local variables
  # are defined in `meta_vars`.
  def interpret(node : ASTNode, meta_vars : MetaVars, scope : Type? = nil, in_pry : Bool = false) : Value
    compiled_def = @compiled_def

    # Declare or migrate local variables
    # TODO: we should also migrate variables if we are outside of a block
    # in a pry session, but that's tricky so we'll leave it for later.
    if !compiled_def || in_pry
      migrate_local_vars(@local_vars, meta_vars) if @local_vars.block_level == 0

      # TODO: is it okay to assume this is always the program? Probably not.
      # Check if we need a local variable for the closure context
      if !in_pry && @context.program.vars.try &.any? { |name, var| var.type? && var.closure_in?(@context.program) }
        # The closure context is always a pointer to some memory
        @local_vars.declare(Closure::VAR_NAME, @context.program.pointer_of(@context.program.void))
      end

      meta_vars.each do |name, meta_var|
        meta_var_type = meta_var.type?

        # A meta var might end up without a type if it's assigned a value
        # in a branch that's never executed/typed, and never read afterwards
        next unless meta_var_type

        # Closured vars don't belong in the local variables table
        next if meta_var.closured?

        # Check if the var already exists from the current block upwards
        existing_type = nil
        @local_vars.block_level.downto(0) do |level|
          existing_type = @local_vars.type?(name, level)
          break if existing_type
        end

        if existing_type
          if existing_type != meta_var.type
            raise "BUG: can't change type of local variable #{name} from #{existing_type} to #{meta_var.type} yet"
          end
        else
          @local_vars.declare(name, meta_var_type)
        end
      end
    end

    finished_hooks = @context.program.finished_hooks.dup
    @context.program.finished_hooks.clear

    # TODO: top_level or not
    compiler =
      if compiled_def
        Compiler.new(@context, @local_vars, scope: scope || compiled_def.owner, def: compiled_def.def)
      elsif scope
        Compiler.new(@context, @local_vars, scope: scope)
      else
        Compiler.new(@context, @local_vars)
      end
    compiler.block_level = @block_level
    compiler.closure_context = @closure_context
    compiler.compile(node)

    @instructions = compiler.instructions

    {% if Debug::DECOMPILE %}
      if compiled_def
        puts "=== #{compiled_def.owner}##{compiled_def.def.name} ==="
      else
        puts "=== top-level ==="
      end
      puts @local_vars
      puts Disassembler.disassemble(@context, @instructions, @local_vars)

      if compiled_def
        puts "=== #{compiled_def.owner}##{compiled_def.def.name} ==="
      else
        puts "=== top-level ==="
      end
    {% end %}

    value = interpret(node, node.type)

    finished_hooks.each do |finished_hook|
      interpret(finished_hook.node, meta_vars, finished_hook.scope.metaclass)
    end

    value
  end

  private def interpret(node : ASTNode, node_type : Type) : Value
    # The stack is used like this:
    #
    # [.........., ...........]
    # ^----------^ ^----------^
    #  local vars   other data
    #
    # That is, there's a space right at the beginning where local variables
    # are stored (local variables live in the stack.)

    # This is the true beginning of the stack, and a reference to where local
    # variables for the current call frame begin.
    stack_bottom = @stack

    # Shift stack to leave room for local vars.
    # Previous runs that wrote to local vars would have those values
    # written to @stack already (or property migrated thanks to `migrate_local_vars`)
    stack_bottom_after_local_vars = stack_bottom + @local_vars.max_bytesize
    stack = stack_bottom_after_local_vars

    # Reserve space for constants (there might be new constants now)
    @context.constants_memory = @context.constants_memory.realloc(@context.constants.bytesize)

    # Reserve space for class vars (there might be new class vars now)
    @context.class_vars_memory = @context.class_vars_memory.realloc(@context.class_vars.bytesize)

    # Class variables that don't have an initializer are trivially initialized (with `nil`)
    @context.class_vars.each_initialized_index do |index|
      @context.class_vars_memory[index] = 1_u8
    end

    instructions = @instructions
    ip = instructions.instructions.to_unsafe
    return_value = Pointer(UInt8).null

    compiled_def = @compiled_def
    if compiled_def
      a_def = compiled_def.def
    else
      a_def = Def.new("<top-level>", body: node)
      a_def.owner = program
      a_def.vars = program.vars
    end

    # Push an initial call frame
    @call_stack << CallFrame.new(
      compiled_def: CompiledDef.new(
        context: @context,
        def: a_def,
        owner: compiled_def.try(&.owner) || a_def.owner,
        args_bytesize: 0,
        instructions: instructions,
        local_vars: @local_vars,
      ),
      compiled_block: nil,
      instructions: instructions,
      ip: ip,
      stack: stack,
      stack_bottom: stack_bottom,
      block_caller_frame_index: -1,
      real_frame_index: 0,
      overflow_offset: 0,
    )

    while true
      {% if Debug::TRACE %}
        puts "-" * 80

        call_frame = @call_stack.last
        a_def = call_frame.compiled_def.def
        offset = (ip - instructions.instructions.to_unsafe).to_i32
        puts "In: #{a_def.owner}##{a_def.name}"
        node = instructions.nodes[offset]?
        puts "Node: #{node}" if node
        puts Slice.new(@stack, stack - @stack).hexdump

        Disassembler.disassemble_one(@context, instructions, offset, current_local_vars, STDOUT)
        puts
      {% end %}

      if @pry
        pry_max_target_frame = @pry_max_target_frame
        if !pry_max_target_frame || @call_stack.last.real_frame_index <= pry_max_target_frame
          pry(ip, instructions, stack_bottom, stack)
        end
      end

      # This is the main interpreter logic:
      # 1. Read the next opcode
      op_code = next_instruction OpCode

      # 2. Do something depending on the opcode.
      #    The code for each opcode is defined in Crystal::Repl::Instructions
      {% begin %}
        case op_code
          {% for name, instruction in Crystal::Repl::Instructions %}
            {% operands = instruction[:operands] || [] of Nil %}
            {% pop_values = instruction[:pop_values] || [] of Nil %}

            in .{{name.id}}?
              # Read operands for this instruction
              {% for operand in operands %}
                {{operand.var}} = next_instruction {{operand.type}}
              {% end %}

              # Pop any values
              {% for pop_value, i in pop_values %}
                {% pop = pop_values[pop_values.size - i - 1] %}
                {{ pop.var }} = stack_pop({{pop.type}})
              {% end %}

              begin
                {% if instruction[:overflow] %}
                  {{ "begin".id }}
                {% end %}

                # Execute the instruction and push the value to the stack, if needed
                {% if instruction[:push] %}
                  stack_push({{instruction[:code]}})
                {% else %}
                  {{instruction[:code]}}
                {% end %}

                {% if instruction[:overflow] %}
                  {{ "rescue OverflowError".id }}
                    # Compute the overflow offset to make it look like a call
                    overflow_offset = 0
                    {% for operand in operands %}
                      overflow_offset -= sizeof({{operand.type}})
                    {% end %}
                    overflow_offset += sizeof(Void*)

                    # On overflow, directly call __crystal_raise_overflow
                    call(@context.crystal_raise_overflow_compiled_def, overflow_offset: overflow_offset)
                  {{ "end".id }}
                {% end %}
              rescue escaping_exception : EscapingException
                raise escaping_exception
              rescue exception : Exception
                {% for operand in operands %}
                  ip -= sizeof({{operand.type}})
                {% end %}
                ip -= sizeof(OpCode)

                call_frame = @call_stack.last
                a_def = call_frame.compiled_def.def
                offset = (ip - instructions.instructions.to_unsafe).to_i32
                puts "In: #{a_def.owner}##{a_def.name}"
                node = instructions.nodes[offset]?
                puts "Node: #{node}" if node

                raise exception
              end
          {% end %}
        end
      {% end %}

      {% if Debug::TRACE %}
        puts Slice.new(@stack, stack - @stack).hexdump
      {% end %}
    end

    if stack != stack_bottom_after_local_vars
      raise "BUG: data left on stack (#{stack - stack_bottom_after_local_vars} bytes): #{Slice.new(@stack, stack - @stack)}"
    end

    Value.new(self, return_value, node_type)
  end

  private def migrate_local_vars(current_local_vars, next_meta_vars)
    # Check if any existing local variable type changed.
    # If so, it means we need to put them inside a union,
    # or make the union bigger.
    current_names = current_local_vars.names_at_block_level_zero

    needs_migration = current_names.any? do |current_name|
      next_meta_var = next_meta_vars[current_name]?

      # This can happen because the interpreter might declare temporary variables
      # exclusive to it, not visible to the semantic phase (MainVisitor), specifically
      # in `Compiler#assign_to_temporary_and_return_pointer`. In that case there's
      # nothing to migrate.
      next unless next_meta_var

      current_type = current_local_vars.type(current_name, 0)
      next_type = next_meta_vars[current_name].type
      current_type != next_type
    end

    return unless needs_migration

    # Always start with fresh variables, because union types might have changed
    @local_vars = LocalVars.new(@context)

    current_memory = Pointer(UInt8).malloc(current_local_vars.current_bytesize)
    @stack.copy_to(current_memory, current_local_vars.current_bytesize)

    stack = @stack
    current_names.each do |current_name|
      current_type = current_local_vars.type(current_name, 0)
      next_meta_var = next_meta_vars[current_name]?

      # Same as before: the next meta var might not exist.
      # In that case, to simplify things, we make it so the next type
      # is the same as the current type, which means "doesn't need a migration"
      next_type = next_meta_var.try(&.type) || current_type

      current_type_size = aligned_sizeof_type(current_type)
      next_type_size = aligned_sizeof_type(next_type)

      if current_type_size == next_type_size
        # Doesn't need a migration, so we copy it as-is
        stack.copy_from(current_memory, current_type_size)
      else
        # Needs a migration
        case next_type
        when MixedUnionType
          case current_type
          when PrimitiveType, NonGenericClassType, GenericClassInstanceType
            stack.as(Int32*).value = type_id(current_type)
            (stack + type_id_bytesize).copy_from(current_memory, current_type_size)
          when ReferenceUnionType, NilableReferenceUnionType, VirtualType
            reference = stack.as(UInt8**).value
            if reference.null?
              stack.clear(next_type_size)
            else
              stack.as(Int32*).value = reference.as(Int32*).value
              (stack + type_id_bytesize).copy_from(current_memory, current_type_size)
            end
          when MixedUnionType
            # Copy the union type id
            stack.as(Int32*).value = current_memory.as(Int32*).value

            # Copy the value
            (stack + type_id_bytesize).copy_from(current_memory + type_id_bytesize, current_type_size)
          else
            # There might not be other cases to handle, but just in case...
            raise "BUG: missing local var migration from #{current_type} to #{next_type} (#{current_type.class} to #{next_type.class})"
          end
        else
          # I don't this a migration is ever needed unless the target type is a MixedUnionType,
          # but just in case...
          raise "BUG: missing local var migration from #{current_type} to #{next_type}"
        end
      end

      stack += next_type_size
      current_memory += current_type_size
    end
  end

  private def current_local_vars
    if call_frame = @call_stack.last?
      call_frame.compiled_def.local_vars
    else
      @local_vars
    end
  end

  # All of these are helper functions called from the interpreter
  # or from Crystal::Repl::Instructions.
  #
  # Most of these are macros because the stack, instructions, etc.
  # are all local variables inside the interpreter loop.
  #
  # TODO: I'm not sure all of these need to be local variables.
  # I think for example Ruby invokes a different function per opcode and
  # passes some data to these functions, for example the stack pointer, etc.,
  # not sure.

  private macro call(compiled_def,
                     block_caller_frame_index = -1,
                     overflow_offset = 0)
    # At the point of a call like:
    #
    #     foo(x, y)
    #
    # x and y will already be in the stack, ready to be used
    # as the function arguments in the target def.
    #
    # After the call, we want the stack to be at the point
    # where it doesn't have the call args, ready to push
    # return call's return value.
    %stack_before_call_args = stack - {{compiled_def}}.args_bytesize

    # Clear the portion after the call args and up to the def local vars
    # because it might contain garbage data from previous block calls or
    # method calls.
    %size_to_clear = {{compiled_def}}.local_vars.max_bytesize - {{compiled_def}}.args_bytesize
    if %size_to_clear < 0
      raise "OH NO, size to clear DEF is: #{ %size_to_clear }"
    end

    stack.clear(%size_to_clear)

    @call_stack[-1] = @call_stack.last.copy_with(
      ip: ip,
      stack: %stack_before_call_args,
    )

    %call_frame = CallFrame.new(
      compiled_def: {{compiled_def}},
      compiled_block: nil,
      instructions: {{compiled_def}}.instructions,
      ip: {{compiled_def}}.instructions.instructions.to_unsafe,
      # We need to adjust the call stack to start right
      # after the target def's local variables.
      stack: %stack_before_call_args + {{compiled_def}}.local_vars.max_bytesize,
      stack_bottom: %stack_before_call_args,
      block_caller_frame_index: {{block_caller_frame_index}},
      real_frame_index: @call_stack.size,
      overflow_offset: {{overflow_offset}},
    )

    @call_stack << %call_frame

    instructions = %call_frame.compiled_def.instructions
    ip = %call_frame.ip
    stack = %call_frame.stack
    stack_bottom = %call_frame.stack_bottom
  end

  private macro call_with_block(compiled_def)
    call({{compiled_def}}, block_caller_frame_index: @call_stack.size - 1)
  end

  private macro call_block(compiled_block)
    # At this point the stack has the yield expressions, so after the call
    # we must go back to before the yield expressions
    %stack_before_call_args = stack - {{compiled_block}}.args_bytesize
    @call_stack[-1] = @call_stack.last.copy_with(
      ip: ip,
      stack: %stack_before_call_args,
    )

    %block_caller_frame_index = @call_stack.last.block_caller_frame_index

    copied_call_frame = @call_stack[%block_caller_frame_index].copy_with(
      compiled_block: {{compiled_block}},
      instructions: {{compiled_block}}.instructions,
      ip: {{compiled_block}}.instructions.instructions.to_unsafe,
      stack: stack,
    )
    @call_stack << copied_call_frame

    instructions = copied_call_frame.instructions
    ip = copied_call_frame.ip
    stack_bottom = copied_call_frame.stack_bottom

    %size_to_clear = {{compiled_block}}.locals_bytesize_end - {{compiled_block}}.locals_bytesize_start - {{compiled_block}}.args_bytesize

    # The size to clear might not always be greater than zero.
    # For example, if all block variables are closured then the only
    # block var is the closure itself.
    if %size_to_clear > 0
      %offset_to_clear = {{compiled_block}}.locals_bytesize_start + {{compiled_block}}.args_bytesize

      # Clear the portion after the block args and up to the block local vars
      # because it might contain garbage data from previous block calls or
      # method calls.
      #
      # stack ... locals ... locals_bytesize_start ... args_bytesize ... locals_bytesize_end
      #                                                            [ ..................... ]
      #                                                                   delete this
      (stack_bottom + %offset_to_clear).clear(%size_to_clear)
    end
  end

  private macro lib_call(lib_function)
    %target_def = lib_function.def
    %cif = lib_function.call_interface
    %fn = lib_function.symbol
    %args_bytesizes = lib_function.args_bytesizes

    # Assume C calls don't have more than 100 arguments
    # TODO: use the stack for this?
    %pointers = uninitialized StaticArray(Pointer(Void), 100)
    %offset = 0

    %i = %args_bytesizes.size - 1
    %args_bytesizes.reverse_each do |arg_bytesize|
      %pointers[%i] = (stack - %offset - arg_bytesize).as(Void*)
      %offset += arg_bytesize
      %i -= 1
    end

    begin
      %cif.call(%fn, %pointers.to_unsafe, stack.as(Void*))
    rescue ex : EscapingException
      raise_exception(ex.exception_pointer)
    else
      %return_bytesize = inner_sizeof_type(%target_def.type)
      %aligned_return_bytesize = align(%return_bytesize)

      (stack - %offset).move_from(stack, %return_bytesize)
      stack = stack - %offset + %return_bytesize

      stack_grow_by(%aligned_return_bytesize - %return_bytesize)
    end
  end

  private macro leave(size)
    # Remember the point the stack reached
    %old_stack = stack
    %previous_call_frame = @call_stack.pop

    leave_after_pop_call_frame(%old_stack, %previous_call_frame, {{size}})
  end

  private macro leave_def(size)
    %throw_value = new_returned_value(stack, {{size}}, @call_stack.last.real_frame_index)
    throw_value(%throw_value)
  end

  private macro break_block(size)
    %throw_value = new_returned_value(
      stack,
      {{size}},
      # Exiting the current frame... (-1)
      # ...we'll find the method that was given a block (-2)
      # We go to the call frame that called the block (+1)
      @call_stack[-2].block_caller_frame_index + 1,
    )
    throw_value(%throw_value)
  end

  private def new_returned_value(stack, size, target_frame_index)
    if size <= SMALL_RETURN_VALUE_MAX_SIZE
      static_array = StaticArray(UInt8, SMALL_RETURN_VALUE_MAX_SIZE).new(0)
      static_array.to_unsafe.copy_from(stack - size, size)
      SmallReturnedValue.new(static_array, size, target_frame_index)
    else
      pointer = Pointer(Void).malloc(size).as(UInt8*)
      pointer.copy_from(stack - size, size)
      BigReturnedValue.new(pointer, size, target_frame_index)
    end
  end

  private macro leave_after_pop_call_frame(old_stack, previous_call_frame, size)
    if @call_stack.size == @call_stack_leave_index
      return_value = Pointer(Void).malloc({{size}}).as(UInt8*)
      return_value.copy_from(stack_bottom_after_local_vars, {{size}})
      stack_shrink_by({{size}})
      break
    else
      %old_stack = {{old_stack}}
      %previous_call_frame = {{previous_call_frame}}
      %call_frame = @call_stack.last

      # Restore ip, instructions and stack bottom
      instructions = %call_frame.instructions
      ip = %call_frame.ip
      stack_bottom = %call_frame.stack_bottom
      stack = %call_frame.stack

      # Ccopy the return value
      stack_move_from(%old_stack - {{size}}, {{size}})

      # TODO: clean up stack
    end
  end

  private macro backtrace
    # Note: this won't work if Array's internal representation is changed,
    # but that's unlikely to happen.
    %bt = [] of String

    @call_stack.each_with_index do |call_frame, index|
      call_frame_instructions = call_frame.instructions.instructions
      call_frame_nodes = call_frame.instructions.nodes

      # All calls have 1 byte for the opcode and sizeof(Void*) bytes
      # for the target call, so we go back to that point to find the relevant node.
      # However, we don't need to do that for the top-most call frame.
      call_frame_ip =
        if index == @call_stack.size - sizeof(OpCode)
          call_frame.ip
        else
          call_frame.ip - sizeof(Void*) - sizeof(OpCode)
        end

      if index < @call_stack.size - 1
        # Add any overflow offset if necessary
        call_frame_ip += @call_stack[index + 1].overflow_offset
      end

      call_frame_index = call_frame_ip - call_frame_instructions.to_unsafe
      node = call_frame_nodes[call_frame_index]?
      if node && (location = node.location)
        location = location.macro_location || location
        def_name = call_frame.compiled_def.def.name
        filename = location.filename
        line_number = location.line_number
        column_number = location.column_number

        # We could devise a way to encode this information more efficiently,
        # but for now this works.
        %bt << "#{def_name}|#{line_number}|#{column_number}|#{filename}"
      end
    end

    %bt.reverse!

    # Make sure the type ID of the returned array is the same
    # as the one in the interpreted program.
    # This is totally unsafe, but this value won't be used anymore in this program,
    # only in the interpreted program.
    %bt.as(Int32*).value = @context.type_id(@context.program.array_of(@context.program.string))

    %bt
  end

  private macro raise_exception(exception)
    %exception = {{exception}}

    while true
      %handlers = instructions.exception_handlers
      %found_handler = false

      if %handlers
        %index = ip - instructions.instructions.to_unsafe

        # Go back one byte because otherwise we are right at the
        # beginning of the next instructions, which isn't where the
        # exception was raised.
        %index -= 1

        %exception_type_id = %exception.as(Int32*).value
        %exception_type = @context.type_from_id(%exception_type_id)

        # Check if any handler should handle the current exception
        %handlers.each do |handler|
          %exception_types = handler.exception_types

          # That is, if the instruction index/offset is within the handler's range,
          # and if there are no specific exception types to rescue (this is an ensure clause)
          # or if the raised exception is any of the exceptions to handle.
          if handler.start_index <= %index < handler.end_index &&
            (!%exception_types || %exception_types.any? { |ex_type| %exception_type.implements?(ex_type) })
            # Push the exception so that it can be assigned to the rescue variable,
            # or thrown in an ensure handler.
            if %exception_types
              stack_push(%exception)
            else
              # In the case of an ensure we make the exception be a ThrowValue,
              # because ensure work both for exceptions and returned values.
              %throw_value = RaisedException.new(%exception).as(ThrowValue)
              stack_push(%throw_value)
            end

            # Jump to the handler's logic
            set_ip(handler.jump_index)

            %found_handler = true
            break
          end
        end
      end

      break if %found_handler

      %old_stack = stack
      %previous_call_frame = @call_stack.pop

      if @call_stack.size == @call_stack_leave_index
        raise EscapingException.new(self, %exception)
      end

      leave_after_pop_call_frame(%old_stack, %previous_call_frame, 0)
    end
  end

  private macro throw_value(throw_value)
    %throw_value = {{throw_value}}

    while true
      %handlers = instructions.exception_handlers
      %found_handler = false

      if %handlers
        %index = ip - instructions.instructions.to_unsafe

        # Go back one byte because otherwise we are right at the
        # beginning of the next instructions, which isn't where the
        # exception was raised.
        %index -= 1

        # Check if any handler should handle the current exception
        %handlers.each do |handler|
          next if handler.exception_types

          # That is, if it's an ensure handler (no exceptions)
          # and the instruction index/offset is within the handler's range
          if !handler.exception_types && handler.start_index <= %index < handler.end_index
            stack_push(%throw_value.as(ThrowValue))

            # Jump to the handler's logic
            set_ip(handler.jump_index)

            %found_handler = true
            break
          end
        end
      end

      break if %found_handler

      %old_stack = stack
      %previous_call_frame = @call_stack.pop

      if @call_stack.size == %throw_value.target_frame_index
        %old_stack.copy_from(%throw_value.pointer, %throw_value.size)
        %old_stack += %throw_value.size
        leave_after_pop_call_frame(%old_stack, %previous_call_frame, %throw_value.size)
        break
      else
        leave_after_pop_call_frame(%old_stack, %previous_call_frame, 0)
      end
    end
  end

  private macro throw
    %throw_value = stack_pop(ThrowValue)
    case %throw_value
    in ReturnedValue
      throw_value(%throw_value)
    in RaisedException
      raise_exception(%throw_value.exception)
    end
  end

  private macro set_ip(ip)
    ip = instructions.instructions.to_unsafe + {{ip}}
  end

  private macro set_local_var(index, size)
    stack_move_to(stack_bottom + {{index}}, {{size}})
  end

  private macro get_local_var(index, size)
    stack_move_from(stack_bottom + {{index}}, {{size}})
  end

  private macro get_local_var_pointer(index)
    stack_bottom + {{index}}
  end

  private macro get_ivar_pointer(offset)
    self_class_pointer + offset
  end

  private macro const_initialized?(index)
    # TODO: make this atomic
    %initialized = @context.constants_memory[{{index}}]
    if %initialized == 1_u8
      true
    else
      @context.constants_memory[{{index}}] = 1_u8
      false
    end
  end

  private macro get_const(index, size)
    stack_move_from(get_const_pointer(index), {{size}})
  end

  private macro get_const_pointer(index)
    @context.constants_memory + {{index}} + Constants::OFFSET_FROM_INITIALIZED
  end

  private macro set_const(index, size)
    stack_move_to(get_const_pointer(index), {{size}})
  end

  private macro class_var_initialized?(index)
    # TODO: make this atomic
    %initialized = @context.class_vars_memory[{{index}}]
    if %initialized == 1_u8
      true
    else
      @context.class_vars_memory[{{index}}] = 1_u8
      false
    end
  end

  private macro get_class_var(index, size)
    stack_move_from(get_class_var_pointer(index), {{size}})
  end

  private macro set_class_var(index, size)
    stack_move_to(get_class_var_pointer(index), {{size}})
  end

  private macro get_class_var_pointer(index)
    @context.class_vars_memory + {{index}} + ClassVars::OFFSET_FROM_INITIALIZED
  end

  private macro atomicrmw_op(op)
    case element_size
    when 1
      i8 = Atomic::Ops.atomicrmw({{op}}, ptr, value.to_u8!, :sequentially_consistent, false)
      stack_push(i8)
    when 2
      i16 = Atomic::Ops.atomicrmw({{op}}, ptr.as(UInt16*), value.to_u16!, :sequentially_consistent, false)
      stack_push(i16)
    when 4
      i32 = Atomic::Ops.atomicrmw({{op}}, ptr.as(UInt32*), value.to_u32!, :sequentially_consistent, false)
      stack_push(i32)
    when 8
      i64 = Atomic::Ops.atomicrmw({{op}}, ptr.as(UInt64*), value.to_u64!, :sequentially_consistent, false)
      stack_push(i64)
    else
      raise "BUG: unhandled element size for store_atomic instruction: #{element_size}"
    end
  end

  private macro pry
    self.pry = true
  end

  def pry=(@pry)
    @pry = pry

    unless pry
      @pry_node = nil
      @pry_max_target_frame = nil
    end
  end

  private macro next_instruction(t)
    value = ip.as({{t}}*).value
    ip += sizeof({{t}})
    value
  end

  private macro self_class_pointer
    get_local_var_pointer(0).as(Pointer(Pointer(UInt8))).value
  end

  private macro stack_pop(t)
    %aligned_size = align(sizeof({{t}}))
    %value = uninitialized {{t}}
    (stack - %aligned_size).copy_to(pointerof(%value).as(UInt8*), sizeof(typeof(%value)))
    stack_shrink_by(%aligned_size)
    %value
  end

  private macro stack_push(value)
    %temp = {{value}}
    %size = sizeof(typeof(%temp))

    stack.copy_from(pointerof(%temp).as(UInt8*), %size)
    %aligned_size = align(%size)
    stack += %size
    stack_grow_by(%aligned_size - %size)
  end

  private macro stack_copy_to(pointer, size)
    (stack - {{size}}).copy_to({{pointer}}, {{size}})
  end

  private macro stack_move_to(pointer, size)
    %size = {{size}}
    %aligned_size = align(%size)
    (stack - %aligned_size).copy_to({{pointer}}, %size)
    stack_shrink_by(%aligned_size)
  end

  private macro stack_move_from(pointer, size)
    %size = {{size}}
    %aligned_size = align(%size)

    stack.copy_from({{pointer}}, %size)
    stack += %size
    stack_grow_by(%aligned_size - %size)
  end

  private macro stack_grow_by(size)
    stack_clear({{size}})
    stack += {{size}}
  end

  private macro stack_shrink_by(size)
    stack -= {{size}}
    stack_clear({{size}})
  end

  private macro stack_clear(size)
    # TODO: clearing the stack after every step is very slow!
    stack.clear({{size}})
  end

  def aligned_sizeof_type(type : Type) : Int32
    @context.aligned_sizeof_type(type)
  end

  def inner_sizeof_type(type : Type) : Int32
    @context.inner_sizeof_type(type)
  end

  private def type_id(type : Type) : Int32
    @context.type_id(type)
  end

  private def type_from_type_id(id : Int32) : Type
    @context.type_from_id(id)
  end

  # How many bytes the `type_id` portion of a union type occupy.
  private macro type_id_bytesize
    8
  end

  private def align(value : Int32)
    @context.align(value)
  end

  private def program
    @context.program
  end

  private def argc_unsafe
    argv.size + 1
  end

  @argv_unsafe = Pointer(Pointer(UInt8)).null

  private def argv_unsafe
    @argv_unsafe ||= begin
      pointers = Pointer(Pointer(UInt8)).malloc(argc_unsafe)
      # The program name
      pointers[0] = "icr".to_unsafe

      argv.each_with_index do |arg, i|
        pointers[i + 1] = arg.to_unsafe
      end

      pointers
    end
  end

  private def spawn_interpreter(fiber : Void*, fiber_main : Void*) : Void*
    spawned_fiber = Fiber.new do
      # `fiber_main` is the pointer type of a `Proc(Fiber, Nil)`.
      # `fiber` is the fiber that we need to pass `fiber_main` to kick off the fiber.
      #
      # To make it work, we construct a call like this:
      #
      # ```
      # fiber_main = uninitialized Proc(Fiber, Nil)
      # fiber = uninitialized Fiber
      # fiber_main.call(fiber)
      # ```
      #
      # And we inject their values in the stack.

      fiber_type = @context.program.types["Fiber"]
      nil_type = @context.program.nil_type
      proc_type = @context.program.proc_of([fiber_type, nil_type] of Type)

      fiber_main_decl = UninitializedVar.new(Var.new("fiber_main"), TypeNode.new(proc_type))
      fiber_decl = UninitializedVar.new(Var.new("fiber"), TypeNode.new(fiber_type))
      call = Call.new(Var.new("fiber_main"), "call", Var.new("fiber"))
      exps = Expressions.new([fiber_main_decl, fiber_decl, call] of ASTNode)

      meta_vars = MetaVars.new

      main_visitor = MainVisitor.new(@context.program, vars: meta_vars, meta_vars: meta_vars)
      exps.accept main_visitor

      @context.checkout_stack do |stack|
        interpreter = Interpreter.new(@context, stack)

        # We need to put the data for `fiber_main` and `fiber` on the stack.

        # Here comes `fiber_main`
        # Put the proc pointer first
        stack.as(Void**).value = fiber_main
        stack += sizeof(Void*)

        # Put the closure data, which is nil
        stack.as(Void**).value = Pointer(Void).null
        stack += sizeof(Void*)

        # Now comes `fiber`
        stack.as(Void**).value = fiber

        begin
          interpreter.interpret(exps, main_visitor.meta_vars)
        rescue ex : EscapingException
          print "Unhandled exception in spawn: "
          print ex
        end

        nil
      end
    end
    spawned_fiber.@context.resumable = 1
    spawned_fiber.as(Void*)
  end

  private def swapcontext(current_context : Void*, new_context : Void*)
    # current_fiber = current_context.as(Fiber*).value
    new_fiber = new_context.as(Fiber*).value

    # delegates the context switch to the interpreter's scheduler, so we update
    # the current fiber reference, set the GC stack bottom, and so on (aka
    # there's more to switching context than `Fiber.swapcontext`):
    new_fiber.resume
  end

  private def fiber_resumable(context : Void*) : LibC::Long
    fiber = context.as(Fiber*).value
    fiber.@context.resumable
  end

  private def signal_descriptor(fd : Int32) : Nil
    {% if flag?(:unix) %}
      # replace the interpreter's signal writer so that the interpreted code
      # will receive signals from now on
      writer = IO::FileDescriptor.new(fd)
      writer.sync = true
      Crystal::System::Signal.writer = writer
    {% else %}
      raise "BUG: interpreter doesn't support signals on this target"
    {% end %}
  end

  private def signal(signum : Int32, handler : Int32) : Nil
    {% if flag?(:unix) %}
      signal = ::Signal.new(signum)
      case handler
      when 0
        signal.reset
      when 1
        signal.ignore
      else
        # register the signal for the OS so the process will receive them;
        # registers a fake handler since the interpreter won't handle the signal:
        # the interpreted code will receive it and will execute the interpreted
        # handler
        signal.trap { }
      end
    {% else %}
      raise "BUG: interpreter doesn't support signals on this target"
    {% end %}
  end

  private def pry(ip, instructions, stack_bottom, stack)
    offset = (ip - instructions.instructions.to_unsafe).to_i32
    node = instructions.nodes[offset]?
    pry_node = @pry_node

    return unless node

    location = node.location
    return unless location

    return unless different_node_line?(node, pry_node)

    call_frame = @call_stack.last
    compiled_def = call_frame.compiled_def
    compiled_block = call_frame.compiled_block
    local_vars = compiled_block.try(&.local_vars) || compiled_def.local_vars

    a_def = compiled_def.def

    whereami(a_def, location)

    # puts
    # puts Slice.new(stack_bottom, stack - stack_bottom).hexdump
    # puts

    # Remember the portion from stack_bottom + local_vars.max_bytesize up to stack
    # because it might happen that the child interpreter will overwrite some
    # of that if we already have some values in the stack past the local vars
    original_local_vars_max_bytesize = local_vars.max_bytesize
    data_size = stack - (stack_bottom + original_local_vars_max_bytesize)
    data = Pointer(Void).malloc(data_size).as(UInt8*)
    data.copy_from(stack_bottom + original_local_vars_max_bytesize, data_size)

    gatherer = LocalVarsGatherer.new(location, a_def)
    gatherer.gather
    meta_vars = gatherer.meta_vars

    # Freeze the type of existing variables because they can't
    # change during a pry session.
    meta_vars.each do |name, var|
      var_type = var.type?
      var.freeze_type = var_type if var_type
    end

    block_level = local_vars.block_level
    owner = compiled_def.owner

    closure_context =
      if compiled_block
        compiled_block.closure_context
      else
        compiled_def.closure_context
      end

    closure_context.try &.vars.each do |name, (index, type)|
      meta_vars[name] = MetaVar.new(name, type)
    end

    main_visitor = MainVisitor.new(
      @context.program,
      vars: meta_vars,
      meta_vars: meta_vars,
      typed_def: a_def)

    # Scope is used for instance types, never for Program
    unless owner.is_a?(Program)
      main_visitor.scope = owner
    end

    main_visitor.path_lookup = owner

    interpreter = Interpreter.new(self, compiled_def, local_vars, closure_context, stack_bottom, block_level)

    while @pry
      @pry_reader.prompt_info = String.build do |io|
        unless owner.is_a?(Program)
          if owner.metaclass?
            io.print owner.instance_type
            io.print '.'
          else
            io.print owner
            io.print '#'
          end
        end
        io.print compiled_def.def.name
      end

      input = @pry_reader.read_next
      unless input
        self.pry = false
        break
      end

      case input
      when "continue"
        self.pry = false
        break
      when "step"
        @pry_node = node
        @pry_max_target_frame = nil
        break
      when "next"
        @pry_node = node
        @pry_max_target_frame = @call_stack.last.real_frame_index
        break
      when "finish"
        @pry_node = node
        @pry_max_target_frame = @call_stack.last.real_frame_index - 1
        break
      when "whereami"
        whereami(a_def, location)
        next
      when "*d"
        puts local_vars
        puts Disassembler.disassemble(@context, compiled_block || compiled_def)
        next
      when "*s"
        puts Slice.new(@stack, stack - @stack).hexdump
        next
      end

      begin
        parser = Parser.new(
          input,
          string_pool: @context.program.string_pool,
          var_scopes: [meta_vars.keys.to_set],
        )
        line_node = parser.parse

        next unless line_node

        main_visitor = MainVisitor.new(from_main_visitor: main_visitor)

        vars_size_before_semantic = main_visitor.vars.size

        line_node = @context.program.normalize(line_node)
        line_node = @context.program.semantic(line_node, main_visitor: main_visitor)

        vars_size_after_semantic = main_visitor.vars.size

        if vars_size_after_semantic > vars_size_before_semantic
          # These are all temporary variables created by MainVisitor.
          # Let's add them to local vars.
          main_visitor.vars.each_with_index do |(name, var), index|
            next unless index >= vars_size_before_semantic

            interpreter.local_vars.declare(name, var.type)
          end
        end

        value = interpreter.interpret(line_node, meta_vars, in_pry: true)

        # New local variables might have been declared during a pry session.
        # Remember them by asking them from the interpreter
        # (the interpreter will keep adding those, or migrate new ones
        # to their new type)
        local_vars = interpreter.local_vars

        print " => "
        puts SyntaxHighlighter::Colorize.highlight!(value.to_s)
      rescue ex : EscapingException
        print "Unhandled exception: "
        print ex
      rescue ex : Crystal::CodeError
        ex.color = true
        ex.error_trace = true
        puts ex
        next
      rescue ex : Exception
        ex.inspect_with_backtrace(STDOUT)
        next
      end
    end

    # Restore the stack data in case it tas overwritten
    (stack_bottom + original_local_vars_max_bytesize).copy_from(data, data_size)
  end

  private def whereami(a_def : Def, location : Location)
    filename = location.filename
    line_number = location.line_number
    column_number = location.column_number

    if filename.is_a?(String)
      puts "From: #{Crystal.relative_filename(filename)}:#{line_number}:#{column_number} #{a_def.owner}##{a_def.name}:"
    else
      puts "From: #{location} #{a_def.owner}##{a_def.name}:"
    end

    puts

    source =
      case filename
      in String
        File.read(filename)
      in VirtualFile
        filename.source
      in Nil
        nil
      end

    return unless source

    if @context.program.color?
      begin
        # We highlight the entire file. We could try highlighting each
        # individual line but that won't work well for heredocs and other
        # constructs. Also, highlighting is pretty fast so it won't be noticeable.
        #
        # TODO: in reality if the heredoc starts way before the lines we show,
        # we lose the command that flips the color on. We should probably do
        # something better here, but for now this is good enough.
        source = Crystal::SyntaxHighlighter::Colorize.highlight(source)
      rescue
        # Ignore highlight errors
      end
    end

    lines = source.lines

    min_line_number = {location.line_number - 5, 1}.max
    max_line_number = {location.line_number + 5, lines.size}.min

    max_line_number_size = max_line_number.to_s.size

    min_line_number.upto(max_line_number) do |line_number|
      line = lines[line_number - 1]
      if line_number == location.line_number
        print " => "
      else
        print "    "
      end

      # Pad line number if needed
      line_number_size = line_number.to_s.size
      (max_line_number_size - line_number_size).times do
        print ' '
      end

      print @context.program.colorize(line_number).blue
      print ": "
      puts line
    end
    puts
  end

  private def different_node_line?(node : ASTNode, previous_node : ASTNode?)
    return true unless previous_node
    return true if node.location.not_nil!.filename != previous_node.location.not_nil!.filename

    node.location.not_nil!.line_number != previous_node.location.not_nil!.line_number
  end
end
