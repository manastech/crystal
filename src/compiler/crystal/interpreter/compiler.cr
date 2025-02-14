require "./repl"
require "./instructions"

# The compiler is in charge of turning Crystal AST into bytecode,
# which is just a stream of bytes that tells the interpreter what to do.
class Crystal::Repl::Compiler < Crystal::Visitor
  # The name we use for the variable where we store the
  # `with ... yield` scope of calls without an `obj`.
  WITH_SCOPE = ".with_scope"

  # A block that's being compiled: what's the block,
  # and which def will invoke it.
  record CompilingBlock, block : Block, target_def : Def

  # A local variable: the index in the stack where it's located, and its type
  record LocalVar, index : Int32, type : Type

  # A closured variable: the array of indexes to traverse the closure context,
  # and possibly parent context, to reach the variable with the given type.
  record ClosuredVar, indexes : Array(Int32), type : Type

  # What's `self` when compiling a node.
  private getter scope : Type

  # The method that's being compiled, if any
  # (if `nil`, the node happens at the top-level)
  private getter def : Def?

  # The block we are in, if any.
  # This is different than `compiling_block`. Consider this code:
  #
  # ```
  # def foo(&)
  #   # When this is called from the top-level, `compiled_block`
  #   # will be the block given to `foo`, but `compiling_block`
  #   # will be `nil` because we are not compiling a block.
  #
  #   bar do
  #     # Now we are compiling `bar`, so `compiling_block` will
  #     # have this block and `bar` as a value.
  #     # And also, `compiled_block` is still the block given to `foo`.
  #     # This is the point where you can see their difference.
  #     yield
  #   end
  # end
  #
  # def bar(&)
  #   yield
  # end
  #
  # # Here `compiling_block` and `compiled_block` are `nil`.
  #
  # foo do
  #   # When this block is compiled, `compiling_block` will have
  #   # the block and `foo`.
  #   a = 1
  # end
  # ```
  property compiled_block : CompiledBlock?

  @compiling_block : CompilingBlock?

  # The instructions that are being generated.
  getter instructions : CompiledInstructions

  # In which block level we are in.
  # Right when we enter a def we are at block level 0.
  # When entering a block, the block level is incremented.
  #
  # This is useful to distinguish a same variable in multiple
  # scopes, for example:
  #
  # ```
  # a = 0      # has block_level = 0
  # foo do |a| # <- this is a different variable, has block_level = 1
  # end
  # ```
  property block_level = 0

  property closure_context : ClosureContext?

  # An ASTNode to override the node associated with an instruction.
  # This is useful when values are inlined. For example if we have a constant
  # like:
  #
  #     TWO = 2
  #
  # When the constant is referenced in code:
  #
  #     x = TWO
  #
  # we simply produce a value of 2 (the constant isn't actually stored anywhere.)
  # But we don't want the debugger to jump to that "2".
  # Instead, we make it so that the location of that "2" is the location
  # of the mention of TWO.
  #
  # We do the same thing when inlining a method that only returns an instance variable.
  @node_override : ASTNode?

  def initialize(
    @context : Context,
    @local_vars : LocalVars,
    @instructions : CompiledInstructions = CompiledInstructions.new,
    scope : Type? = nil,
    @def = nil,
    @top_level = true,
  )
    @scope = scope || @context.program

    # Do we want to push a value to the stack?
    # This value is false for nodes whose value is not needed.
    # For example, consider this code:
    #
    # ```
    # a = 1
    # 2
    # a
    # ```
    #
    # The value of the second node, `2`, is not needed at all
    # and so it's not even pushed to the stack.
    #
    # And, actually, the value of `a = 1` is not needed either
    # (it's not assigned to anything else after `a`).
    #
    # An alternative way to have done this is to push every
    # node to the stack, and pop afterwards if not needed
    # (this is in intermediary nodes of `Expressions`) but
    # this is less efficient.
    @wants_value = true

    # Stack of ensures that will be inlined when a `return`
    # is done inside an ensure.
    @ensure_stack = [] of ASTNode
  end

  def self.new(
    context : Context,
    compiled_def : CompiledDef,
    top_level : Bool,
    scope : Type = compiled_def.owner,
  )
    new(
      context: context,
      local_vars: compiled_def.local_vars,
      instructions: compiled_def.instructions,
      scope: scope,
      def: compiled_def.def,
      top_level: top_level,
    )
  end

  # Compile bytecode instructions for the given node.
  def compile(node : ASTNode) : Nil
    # If at the top-level, check if there's closure data
    prepare_closure_context(@context.program) unless @def

    node.accept self

    # Use a dummy node so that pry stops at `end`
    leave aligned_sizeof_type(node), node: Nop.new.at(node.end_location)
  end

  # Compile bytecode instructions for the given block, where `target_def`
  # is the method that will yield to the block.
  def compile_block(compiled_block : CompiledBlock, target_def : Def, parent_closure_context : ClosureContext?) : Nil
    node = compiled_block.block

    prepare_closure_context(node, parent_closure_context: parent_closure_context)

    @compiling_block = CompilingBlock.new(node, target_def)

    # Right when we enter a block we have the block arguments in the stack:
    # we need to copy the values to the respective block arguments, which
    # are really local variables inside the enclosing method.
    # And we have to do them starting from the end because it's a stack.
    node.args.reverse_each do |arg|
      block_var = node.vars.not_nil![arg.name]

      # If any block argument is closured, we need to store it in the closure
      if block_var.closure_in?(node)
        closured_var = lookup_closured_var(arg.name)
        assign_to_closured_var(closured_var, node: nil)
      else
        index = @local_vars.name_to_index(block_var.name, @block_level)
        # Don't use location so we don't pry break on a block arg (useless)
        set_local index, aligned_sizeof_type(block_var), node: nil
      end
    end

    # If it's `with ... yield` we pass the "with" scope
    # as the first block argument... which is the last thing we want to pop.
    with_scope = node.scope
    if with_scope
      index = @local_vars.name_to_index(WITH_SCOPE, @block_level)
      set_local index, aligned_sizeof_type(with_scope), node: nil
    end

    node.body.accept self

    if node.type.no_return?
      # Nothing to do, the body never returns so there's nothing to upcast
    else
      upcast node.body, node.body.type, node.type
    end

    # Use a dummy node so that pry stops at `end`
    leave aligned_sizeof_type(node), node: Nop.new.at(node.end_location)

    # Keep a copy of the local vars before exiting the block.
    # Otherwise we'll lose reference to the block's vars (useful for pry)
    compiled_block.local_vars = @local_vars.dup
    compiled_block.closure_context = @closure_context
  end

  # Compile bytecode instructions for the given method.
  def compile_def(compiled_def : CompiledDef, parent_closure_context : ClosureContext? = nil, closure_owner = compiled_def.def) : Nil
    node = compiled_def.def

    prepare_closure_context(
      node,
      closure_owner: closure_owner,
      parent_closure_context: parent_closure_context,
    )

    # If any def argument is closured, we need to store it in the closure
    node.args.each do |arg|
      move_arg_to_closure_if_closured(node, arg.name)
    end

    # Same for the block arg
    if node.uses_block_arg?
      move_arg_to_closure_if_closured(node, node.block_arg.not_nil!.name)
    end

    # Compiled Crystal supports a def's body being nil:
    # it treats it as NoReturn. Here we do the same thing.
    # In reality we should fix the compiler to avoid having
    # nil in types, but that's a larger change and we can do
    # it later. For now we just handle this specific case in
    # the interpreter.
    node.body.accept self

    final_type = node.type

    compiled_block = @compiled_block
    if compiled_block
      final_type = merge_block_break_type(final_type, compiled_block.block)
    end

    if final_type.nil_type?
      # Cast whatever was returned to Nil, which means just popping it from the stack
      if node.body.type?
        pop aligned_sizeof_type(node.body), node: nil
      else
        # Nothing to do, there's no body type which probably means
        # the last expression in the body is unreachable, and given
        # that this already returns nil, the value was already "casted" to nil
      end
    elsif final_type.no_return?
      # Nothing to do, the body never returns so there's nothing to upcast
    elsif node.body.type?
      upcast node.body, node.body.type, final_type
    else
      # Nothing to do, the body has no type
    end

    # Use a dummy node so that pry stops at `end`
    leave aligned_sizeof_type(final_type), node: Nop.new.at(node.end_location)

    compiled_def.closure_context = @closure_context

    @instructions
  end

  private def move_arg_to_closure_if_closured(node : Def, arg_name : String)
    var = node.vars.not_nil![arg_name]
    return unless var.type?
    return unless var.closure_in?(node)

    local_var = lookup_local_var(closured_arg_name(var.name))
    closured_var = lookup_closured_var(var.name)

    get_local local_var.index, aligned_sizeof_type(local_var.type), node: nil
    assign_to_closured_var(closured_var, node: nil)
  end

  private def inside_method?
    return false if @top_level

    !!@def
  end

  def visit(node : Nop)
    return false unless @wants_value

    put_nil node: node
    false
  end

  def visit(node : NilLiteral)
    return false unless @wants_value

    put_nil node: node
    false
  end

  def visit(node : BoolLiteral)
    return false unless @wants_value

    if node.value
      put_true node: node
    else
      put_false node: node
    end

    false
  end

  def visit(node : NumberLiteral)
    return false unless @wants_value

    compile_number(node, node.kind, node.value)

    false
  end

  private def compile_number(node, kind, value)
    case kind
    in .i8?
      put_i8 value.to_i8, node: node
    in .u8?
      put_u8 value.to_u8, node: node
    in .i16?
      put_i16 value.to_i16, node: node
    in .u16?
      put_u16 value.to_u16, node: node
    in .i32?
      put_i32 value.to_i32, node: node
    in .u32?
      put_u32 value.to_u32, node: node
    in .i64?
      put_i64 value.to_i64, node: node
    in .u64?
      put_u64 value.to_u64, node: node
    in .i128?
      put_i128 value.to_i128, node: node
    in .u128?
      put_u128 value.to_u128, node: node
    in .f32?
      put_i32 value.to_f32.unsafe_as(Int32), node: node
    in .f64?
      put_i64 value.to_f64.unsafe_as(Int64), node: node
    end
  end

  def visit(node : CharLiteral)
    return false unless @wants_value

    put_i32 node.value.ord, node: node
    false
  end

  def visit(node : StringLiteral)
    return false unless @wants_value

    put_string node.value, node: node

    false
  end

  def visit(node : SymbolLiteral)
    return false unless @wants_value

    index = @context.symbol_index(node.value)

    put_i32 index, node: node
    false
  end

  def visit(node : TupleLiteral)
    unless @wants_value
      node.elements.each do |element|
        discard_value element
      end

      return false
    end

    type = node.type.as(TupleInstanceType)

    # The elements inside a tuple do not follow the stack alignment.
    # Each element expression is stack-aligned, so we must adjust that:
    # if the value in the stack has more bytes than needed, we pop
    # the extra ones; if it has less bytes that needed we pad the value
    # with zeros.
    current_offset = 0
    node.elements.each_with_index do |element, i|
      element.accept self
      aligned_size = aligned_sizeof_type(element)
      next_offset =
        if i == node.elements.size - 1
          aligned_sizeof_type(type)
        else
          @context.offset_of(type, i + 1)
        end

      difference = next_offset - (current_offset + aligned_size)
      if difference > 0
        push_zeros(difference, node: nil)
      elsif difference < 0
        pop(-difference, node: nil)
      end

      current_offset = next_offset
    end

    false
  end

  def visit(node : NamedTupleLiteral)
    unless @wants_value
      node.entries.each do |entry|
        discard_value entry.value
      end

      return false
    end

    type = node.type.as(NamedTupleInstanceType)

    # This logic is similar to TupleLiteral.
    current_offset = 0
    node.entries.each_with_index do |entry, i|
      entry.value.accept self
      aligned_size = aligned_sizeof_type(entry.value)
      next_offset =
        if i == node.entries.size - 1
          aligned_sizeof_type(type)
        else
          @context.offset_of(type, i + 1)
        end

      difference = next_offset - (current_offset + aligned_size)
      if difference > 0
        push_zeros(difference, node: nil)
      elsif difference < 0
        pop(-difference, node: nil)
      end

      current_offset = next_offset
    end

    false
  end

  def visit(node : ExceptionHandler)
    # TODO: rescues, else, etc.
    rescues = node.rescues
    node_ensure = node.ensure
    node_else = node.else

    # Accept the body, recording where it starts and ends
    body_start_index = instructions_index

    @ensure_stack.push node_ensure if node_ensure

    if node_else
      discard_value node.body
    else
      node.body.accept self
      upcast node.body, node.body.type, node.type if @wants_value
    end

    @ensure_stack.pop if node_ensure

    body_end_index = instructions_index

    # Now we'll write the catch tables so we want to skip this
    jump 0, node: nil
    jump_location = patch_location

    # Assume we have only rescue for now
    rescue_jump_locations = [] of Int32
    rescue_indexes = [] of {Int32, Int32}

    rescues.try &.each do |a_rescue|
      rescue_start_index = instructions_index

      name = a_rescue.name
      types = a_rescue.types
      if types
        exception_types = types.map(&.type.instance_type)
      else
        exception_types = [@context.program.exception] of Type
      end

      instructions.add_rescue(
        body_start_index,
        body_end_index,
        exception_types,
        jump_index: rescue_start_index)

      if name
        # The exception is in the stack, so we copy it to the corresponding local variable
        name_type = @context.program.type_merge_union_of(exception_types).not_nil!

        assign_to_var(name, name_type, node: a_rescue)
      else
        # The exception is in the stack but we don't use it
        pop sizeof(Void*), node: nil
      end

      a_rescue.body.accept self
      upcast a_rescue.body, a_rescue.body.type, node.type if @wants_value

      rescue_end_index = instructions_index
      rescue_indexes << {rescue_start_index, rescue_end_index}

      jump 0, node: nil
      rescue_jump_locations << patch_location
    end

    if node_ensure
      # If there's an ensure block we also generate another ensure
      # clause to be executed when an exception is raised inside the body
      # or any of the rescue clauses, which does the ensure, then reraises
      ensure_index = instructions_index

      instructions.add_ensure(
        body_start_index,
        body_end_index,
        jump_index: ensure_index,
      )

      rescue_indexes.each do |rescue_start_index, rescue_end_index|
        instructions.add_ensure(
          rescue_start_index,
          rescue_end_index,
          jump_index: ensure_index,
        )
      end

      # temp_var_index = temp_var_index.not_nil!

      # set_local temp_var_index, sizeof(Interpreter::ThrowValue), node: nil

      discard_value node_ensure

      # get_local temp_var_index, sizeof(Interpreter::ThrowValue), node: nil

      throw node: nil
    end

    # Now we are at the exit
    patch_jump(jump_location)

    # If there's an else, do it now
    if node_else
      else_start_index = instructions_index

      node_else.accept self
      upcast node_else, node_else.type, node.type if @wants_value

      if ensure_index
        instructions.add_ensure(
          else_start_index,
          instructions_index,
          jump_index: ensure_index,
        )
      end
    end

    # Now comes the ensure part.
    # We jump here from all the rescue blocks.
    rescue_jump_locations.each do |location|
      patch_jump(location)
    end

    discard_value node_ensure if node_ensure

    false
  end

  def visit(node : Expressions)
    old_wants_value = @wants_value

    node.expressions.each_with_index do |expression, i|
      @wants_value = old_wants_value && i == node.expressions.size - 1
      expression.accept self
    end

    @wants_value = old_wants_value

    false
  end

  def visit(node : Assign)
    target = node.target
    case target
    when Var
      compile_assign_to_var(node, target, node.value)
    when InstanceVar
      if inside_method?
        request_value(node.value)

        # Why we dup: check the Var case (it's similar)
        if @wants_value
          dup(aligned_sizeof_type(node.value), node: nil)
        end

        closure_self = lookup_closured_var?("self")
        if closure_self
          if closure_self.type.passed_by_value?
            ivar_offset, ivar_size = get_closured_self_pointer(closure_self, target.name, node: node)
            pointer_set ivar_size, node: node
          else
            ivar_offset = ivar_offset(closure_self.type, target.name)
            ivar = closure_self.type.lookup_instance_var(target.name)
            ivar_size = inner_sizeof_type(ivar.type)

            upcast node.value, node.value.type, ivar.type

            # Read self pointer
            read_from_closured_var(closure_self, node: nil)

            # Now offset it to reach the instance var
            if ivar_offset > 0
              pointer_add_constant ivar_offset, node: nil
            end

            # Finally set it
            pointer_set ivar_size, node: nil
          end
        else
          ivar_offset = ivar_offset(scope, target.name)
          ivar = scope.lookup_instance_var(target.name)
          ivar_size = inner_sizeof_type(ivar.type)

          upcast node.value, node.value.type, ivar.type

          set_self_ivar ivar_offset, ivar_size, node: node
        end
      else
        node.type = @context.program.nil_type
        put_nil node: nil if @wants_value
      end
    when ClassVar
      if inside_method?
        dispatch_class_var(target) do |class_var|
          index, compiled_def = class_var_index_and_compiled_def(class_var, node: target)

          if compiled_def
            initialize_class_var_if_needed(class_var, index, compiled_def)
          end

          request_value(node.value)

          # Why we dup: check the Var case (it's similar)
          if @wants_value
            dup(aligned_sizeof_type(node.value), node: nil)
          end

          upcast node.value, node.value.type, class_var.type

          set_class_var index, aligned_sizeof_type(class_var), node: node
        end
      else
        # TODO: eagerly initialize the class var?
        node.type = @context.program.nil_type
        put_nil node: nil if @wants_value
      end
    when Underscore
      node.value.accept self
    when Path
      const = target.target_const.not_nil!

      # We inline simple constants.
      if const.value.simple_literal?
        put_nil node: node

        # Not all non-trivial constants have a corresponding def:
        # for example ARGV_UNSAFE.
      elsif const.fake_def
        index, compiled_def = get_const_index_and_compiled_def const

        # This will initialize the constant
        const_initialized index, node: nil
        pop(sizeof(Pointer(Void)), node: nil) # pop the bool value

        call compiled_def, node: nil

        # Why we dup: check the Var case (it's similar)
        dup(aligned_sizeof_type(const.value.type), node: nil) if @wants_value
        set_const index, aligned_sizeof_type(const.value), node: nil
      elsif @wants_value
        # This is probably the last constant defined in a file, and it's a throw-away value
        put_nil node: node
      end
    else
      node.raise "BUG: missing interpret for #{node.class} with target #{node.target.class}"
    end
    false
  end

  def compile_assign_to_var(node : ASTNode, target : ASTNode, value : ASTNode)
    request_value(value)

    # If it's the case of `x = a = 1` then we need to preserve the value
    # of 1 in the stack because it will be assigned to `x` too
    # (set_local removes the value from the stack)
    if @wants_value
      dup(aligned_sizeof_type(value), node: nil)
    end

    if target.special_var?
      # We need to assign through the special var pointer
      var = lookup_local_var("#{target.name}*")
      var_type = var.type.as(PointerInstanceType).element_type

      upcast value, value.type, var_type

      get_local var.index, sizeof(Void*), node: node
      pointer_set inner_sizeof_type(var_type), node: node
    else
      assign_to_var(target.name, value.type, node: node)
    end
  end

  private def assign_to_var(name : String, value_type : Type, *, node : ASTNode?)
    var = lookup_local_var_or_closured_var(name)

    # Before assigning to the var we must potentially box inside a union
    upcast node, value_type, var.type

    case var
    in LocalVar
      set_local var.index, aligned_sizeof_type(var.type), node: node
    in ClosuredVar
      assign_to_closured_var(var, node: node)
    end
  end

  def visit(node : TypeDeclaration)
    var = node.var
    return false unless var.is_a?(Var)

    value = node.value
    return false unless value

    compile_assign_to_var(node, var, value)

    false
  end

  def visit(node : Var)
    return false unless @wants_value

    is_self = node.name == "self"

    # This is the case of "self" that refers to a metaclass,
    # particularly when outside of a method.
    if is_self && !scope.is_a?(Program) && !scope.passed_as_self?
      put_type scope, node: node
      return false
    end

    local_var = lookup_local_var_or_closured_var(node.name)
    case local_var
    in LocalVar
      index, type = local_var.index, local_var.type

      if is_self && type.passed_by_value?
        if in_multidispatch?
          # Inside a multidispatch "self" is already a pointer
          get_local index, sizeof(Void*), node: node
          pointer_get aligned_sizeof_type(type), node: node
        else
          # Load the entire self from the pointer that's self
          get_self_ivar 0, aligned_sizeof_type(type), node: node
        end
      else
        get_local index, aligned_sizeof_type(type), node: node
      end

      downcast node, type, node.type?
    in ClosuredVar
      read_from_closured_var(local_var, node: node)
    end

    false
  end

  def lookup_local_var_or_closured_var(name : String) : LocalVar | ClosuredVar
    lookup_local_var?(name) ||
      lookup_closured_var?(name) ||
      raise("BUG: can't find closured var or local var #{name}")
  end

  def lookup_local_var(name : String) : LocalVar
    lookup_local_var?(name) || raise("BUG: can't find local var #{name}")
  end

  def lookup_local_var?(name : String) : LocalVar?
    block_level = @block_level
    while block_level >= 0
      index = @local_vars.name_to_index?(name, block_level)
      if index
        type = @local_vars.type(name, block_level)
        return LocalVar.new(index, type)
      end

      block_level -= 1
    end

    nil
  end

  def lookup_closured_var(name : String) : ClosuredVar
    lookup_closured_var?(name) || raise("BUG: can't find closured var #{name}")
  end

  def lookup_closured_var?(name : String) : ClosuredVar?
    closure_context = @closure_context
    return unless closure_context

    indexes = [] of Int32

    type = lookup_closured_var?(name, closure_context, indexes)

    return nil if indexes.empty? || !type

    ClosuredVar.new(indexes, type)
  end

  def lookup_closured_var?(name : String, closure_context : ClosureContext, indexes : Array(Int32))
    if name == "self" && (closure_self_type = closure_context.self_type)
      indexes << closure_context.bytesize - aligned_sizeof_type(closure_self_type)
      return closure_self_type
    end

    closured_var = closure_context.vars[name]?
    if closured_var
      indexes << closured_var[0]
      return closured_var[1]
    end

    parent_context = closure_context.parent
    return nil unless parent_context

    indexes << closure_context.bytesize - sizeof(Void*)
    lookup_closured_var?(name, parent_context, indexes)
  end

  private def prepare_closure_context(vars_owner, closure_owner = vars_owner, parent_closure_context = nil)
    closure_self_type = nil
    if closure_owner.is_a?(Def) && closure_owner.self_closured?
      closure_self_type = closure_owner.owner
    end

    closured_vars, closured_vars_bytesize = compute_closured_vars(vars_owner.vars, closure_owner)

    # If there's no closure in this context, we might still have a closure
    # if the parent formed a closure
    if closured_vars.empty? && !closure_self_type
      @closure_context = parent_closure_context
      return
    end

    if parent_closure_context
      closured_vars_bytesize += sizeof(Void*)
    end

    if closure_self_type
      closured_vars_bytesize += aligned_sizeof_type(closure_self_type)
    end

    closure_context = ClosureContext.new(
      vars: closured_vars,
      parent: parent_closure_context,
      self_type: closure_self_type,
      bytesize: closured_vars_bytesize,
    )
    @closure_context = closure_context

    # Allocate closure heap memory
    put_i32 closure_context.bytesize, node: nil
    pointer_malloc 1, node: nil

    # Store the pointer in the closure context local variable
    index = @local_vars.name_to_index(Closure::VAR_NAME, @block_level)
    set_local index, sizeof(Void*), node: nil

    # If there's a closured self type, store it now
    if closure_self_type
      # Load self
      # (pointer_set expects the value to come before the pointer)
      local_self_index = @local_vars.name_to_index("self", 0)
      if closure_self_type.passed_by_value?
        # First load the pointer to self
        get_local local_self_index, sizeof(Pointer(Void)), node: nil

        # Then load the entire self
        pointer_get aligned_sizeof_type(closure_self_type), node: nil
      else
        get_local local_self_index, aligned_sizeof_type(closure_self_type), node: nil
      end

      # Get the closure pointer
      get_local index, sizeof(Void*), node: nil

      # Offset pointer to reach self pointer
      closure_self_index = closure_context.bytesize - aligned_sizeof_type(closure_self_type)
      if closure_self_index > 0
        pointer_add_constant closure_self_index, node: nil
      end

      # Store self in closure
      pointer_set aligned_sizeof_type(closure_self_type), node: nil
    end

    if parent_closure_context
      # Find the closest parent closure
      block_level = @block_level
      while true
        # Only at block level 0 we have a proc closure data
        if block_level == 0
          parent_index = @local_vars.name_to_index?(Closure::ARG_NAME, block_level)
          break if parent_index
        end

        block_level -= 1
        break if block_level < 0

        parent_index = @local_vars.name_to_index?(Closure::VAR_NAME, block_level)
        break if parent_index
      end

      unless parent_index
        raise "Can't find parent closure index"
      end

      get_local parent_index, sizeof(Void*), node: nil
      read_closured_var_pointer ClosuredVar.new(
        indexes: [closured_vars_bytesize - sizeof(Void*)] of Int32,
        type: @context.program.pointer_of(@context.program.void),
      ), node: nil
      pointer_set(sizeof(Void*), node: nil)
    end
  end

  private def compute_closured_vars(vars, closure_owner)
    closured_vars = {} of String => {Int32, Type}
    closure_var_index = 0

    vars.try &.each do |name, var|
      if var.type? && var.closure_in?(closure_owner)
        closured_vars[name] = {closure_var_index, var.type}
        closure_var_index += aligned_sizeof_type(var)
      end
    end

    {closured_vars, closure_var_index}
  end

  private def assign_to_closured_var(closured_var : ClosuredVar, *, node : ASTNode?)
    read_closured_var_pointer(closured_var, node: nil)

    # Now we have the value in the stack, and the pointer.
    # This is the correct order for pointer_set
    pointer_set(aligned_sizeof_type(closured_var.type), node: node)
  end

  private def read_from_closured_var(closured_var : ClosuredVar, *, node : ASTNode?)
    read_closured_var_pointer(closured_var, node: nil)

    # Now read from the pointer
    pointer_get inner_sizeof_type(closured_var.type), node: node
  end

  private def read_closured_var_pointer(closured_var : ClosuredVar, *, node : ASTNode?)
    indexes = closured_var.indexes

    # First load the closure pointer
    closure_var_index = get_closure_var_index
    get_local closure_var_index, sizeof(Void*), node: nil

    # Now find the var through the pointer
    indexes.each_with_index do |index, i|
      if i == indexes.size - 1
        # We reached the context where the var is.
        # No need to offset if index is 0
        if index > 0
          pointer_add_constant index, node: nil
        end
      else
        # The var is in the parent context, so load that first
        pointer_add_constant index, node: nil
        pointer_get sizeof(Void*), node: nil
      end
    end
  end

  private def pointerof_local_var_or_closured_var(var : LocalVar | ClosuredVar, *, node : ASTNode?)
    case var
    in LocalVar
      pointerof_var(var.index, node: node)
    in ClosuredVar
      read_closured_var_pointer(var, node: node)
    end
  end

  private def get_closure_var_index
    # It might be that there's no closure in the current block,
    # so we must search in parent blocks or the enclosing method
    block_level = @block_level
    while block_level >= 0
      closure_var_index = @local_vars.name_to_index?(Closure::VAR_NAME, block_level)
      return closure_var_index if closure_var_index

      block_level -= 1
    end

    raise "BUG: can't find closure var index starting from block level #{@block_level}"
  end

  def visit(node : InstanceVar)
    compile_instance_var(node)
  end

  private def compile_instance_var(node : InstanceVar)
    return false unless @wants_value

    closured_self = lookup_closured_var?("self")
    if closured_self
      ivar_offset, ivar_size = get_closured_self_pointer(closured_self, node.name, node: node)
      pointer_get ivar_size, node: node
    else
      ivar_offset = ivar_offset(scope, node.name)
      ivar_size = inner_sizeof_type(scope.lookup_instance_var(node.name))

      get_self_ivar ivar_offset, ivar_size, node: node
    end

    false
  end

  private def get_closured_self_pointer(closured_self : ClosuredVar, name : String, *, node : ASTNode?)
    ivar_offset = ivar_offset(closured_self.type, name)
    ivar_size = inner_sizeof_type(closured_self.type.lookup_instance_var(name))

    if closured_self.type.passed_by_value?
      # Read self pointer from closured self
      closured_var = lookup_closured_var("self")
      read_closured_var_pointer(closured_var, node: node)
    else
      # Read self pointer
      read_from_closured_var(closured_self, node: node)
    end

    # Now offset it to reach the instance var
    if ivar_offset > 0
      pointer_add_constant ivar_offset, node: node
    end

    {ivar_offset, ivar_size}
  end

  def visit(node : ClassVar)
    return false unless @wants_value

    dispatch_class_var(node) do |class_var|
      index, compiled_def = class_var_index_and_compiled_def(class_var, node: node)

      if compiled_def
        initialize_class_var_if_needed(class_var, index, compiled_def)
      end

      get_class_var index, aligned_sizeof_type(class_var), node: node
    end

    false
  end

  private def dispatch_class_var(node : ClassVar, &)
    var = node.var
    owner = var.owner

    case owner
    when VirtualType
      dispatch_class_var(owner.base_type, metaclass: false, node: node) do |var|
        yield var
      end
    when VirtualMetaclassType
      dispatch_class_var(owner.base_type.instance_type, metaclass: true, node: node) do |var|
        yield var
      end
    else
      yield var
    end
  end

  private def dispatch_class_var(owner : Type, metaclass : Bool, node : ASTNode, &)
    types = owner.all_subclasses.select { |t| t.is_a?(ClassVarContainer) }
    types.push(owner)
    types.sort_by! { |type| -type.depth }

    last_patch_location = nil
    jump_locations = [] of Int32

    types.each do |type|
      patch_jump(last_patch_location) if last_patch_location

      put_self node: node
      is_a(node, scope, metaclass ? type.metaclass : type)
      branch_unless 0, node: node
      last_patch_location = patch_location

      yield type.lookup_class_var(node.name)

      jump 0, node: node
      jump_locations << patch_location
    end

    patch_jump(last_patch_location.not_nil!)
    unreachable "BUG: didn't find class var type match", node: node

    jump_locations.each do |jump_location|
      patch_jump(jump_location)
    end
  end

  private def class_var_index_and_compiled_def(var : MetaTypeVar, *, node : ASTNode) : {Int32, CompiledDef?}
    case var.owner
    when VirtualType
      node.raise "BUG: shouldn't be calling this method with a virtual type"
    when VirtualMetaclassType
      node.raise "BUG: shouldn't be calling this method with a virtual metaclass type"
    end

    index_and_compiled_def = @context.class_var_index_and_compiled_def(var.owner, var.name)
    return index_and_compiled_def if index_and_compiled_def

    initializer = var.initializer
    if initializer
      value = initializer.node

      # It seems class variables initializers aren't cleaned up...
      value = @context.program.cleanup(value)

      def_name = "#{var.owner}::#{var.name}"

      fake_def = Def.new(def_name)
      fake_def.owner = var.owner.metaclass
      fake_def.vars = initializer.meta_vars

      # Check if we need to upcast the value to the class var's type
      fake_def.body =
        if value.type? == var.type
          value
        else
          cast = Cast.new(value, TypeNode.new(var.type))
          cast.upcast = true
          cast.type = var.type
          cast
        end

      fake_def.bind_to(fake_def.body)

      compiled_def = CompiledDef.new(@context, fake_def, fake_def.owner, 0)

      # TODO: it's wrong that class variable initializer variables go to the
      # program, but this needs to be fixed in the main compiler first
      declare_local_vars(fake_def, compiled_def.local_vars, @context.program)

      compiler = Compiler.new(@context, compiled_def, scope: fake_def.owner, top_level: true)
      compiler.compile_def(compiled_def, closure_owner: @context.program)

      {% if Debug::DECOMPILE %}
        puts "=== #{def_name} ==="
        puts Disassembler.disassemble(@context, compiled_def)
        puts "=== #{def_name} ==="
      {% end %}
    end

    index = @context.declare_class_var(var.owner, var.name, var.type, compiled_def)

    {index, compiled_def}
  end

  def visit(node : ReadInstanceVar)
    compile_read_instance_var(node, node.obj, node.name)
  end

  private def compile_read_instance_var(node, obj, name, owner = obj.type)
    unless @wants_value
      discard_value(obj)
      return false
    end

    ivar = owner.lookup_instance_var(name)
    ivar_offset = ivar_offset(owner, name)
    ivar_size = inner_sizeof_type(ivar)

    obj.accept self

    if owner.passed_by_value?
      # We have the struct in the stack, now we need to keep a part of it

      # If it's an extern struct with a Proc field, we need to convert
      # the FFI::Closure object into a Crystal Proc
      if owner.extern? && ivar.type.proc?
        get_struct_ivar ivar_offset, sizeof(Void*), aligned_sizeof_type(obj), node: node
        c_fun_to_proc node: node
      else
        get_struct_ivar ivar_offset, ivar_size, aligned_sizeof_type(obj), node: node
      end
    else
      get_class_ivar ivar_offset, ivar_size, node: node
    end

    false
  end

  private def compile_pointerof_read_instance_var(obj, obj_type, name)
    ivar = obj_type.lookup_instance_var(name)
    ivar_offset = ivar_offset(obj_type, name)
    ivar_size = inner_sizeof_type(ivar)

    # Get a pointer to the object
    if obj_type.passed_by_value?
      compile_pointerof_node(obj, obj_type)
    else
      request_value(obj)
    end

    # Now offset it
    pointer_add_constant ivar_offset, node: nil

    false
  end

  def visit(node : UninitializedVar)
    case var = node.var
    when Var
      var.accept self
    when InstanceVar
      # Nothing to do
    when ClassVar
      # TODO: declare the class var (though it will be declared later on)
    else
      node.raise "BUG: missing interpret UninitializedVar for #{var.class}"
    end

    false
  end

  def visit(node : If)
    # Compiled Crystal supports an if's type being nil:
    # it treats it as NoReturn. Here we do the same thing.
    # In reality we should fix the compiler to avoid having
    # nil in types, but that's a larger change and we can do
    # it later. For now we just handle this specific case in
    # the interpreter.
    node.type = @context.program.no_return unless node.type?

    if node.truthy?
      discard_value(node.cond)
      node.then.accept self
      return false unless @wants_value

      upcast node.then, node.then.type, node.type
      return false
    elsif node.falsey?
      discard_value(node.cond)
      node.else.accept self
      return false unless @wants_value

      upcast node.else, node.else.type, node.type
      return false
    end

    request_value(node.cond)

    value_to_bool(node.cond, node.cond.type)

    branch_unless 0, node: nil
    cond_jump_location = patch_location

    node.then.accept self

    # TODO: for some reason the semantic pass might leave this as nil
    if @wants_value && (then_type = node.then.type?)
      upcast node.then, then_type, node.type
    end

    jump 0, node: nil
    then_jump_location = patch_location

    patch_jump(cond_jump_location)

    node.else.accept self

    # TODO: for some reason the semantic pass might leave this as nil
    if @wants_value && (else_type = node.else.type?)
      upcast node.else, else_type, node.type
    end

    patch_jump(then_jump_location)

    false
  end

  def visit(node : While)
    # Jump directly to the condition
    jump 0, node: nil
    cond_jump_location = patch_location

    body_index = instructions_index

    old_while = @while
    old_while_breaks = @while_breaks
    old_while_nexts = @while_nexts

    @while = node
    while_breaks = @while_breaks = [] of Int32
    while_nexts = @while_nexts = [] of Int32

    # Now write the body
    discard_value(node.body)

    # Here starts the condition.
    # Any `next` that happened leads us here.
    while_nexts.each do |while_next|
      patch_jump(while_next)
    end

    patch_jump(cond_jump_location)
    request_value(node.cond)
    value_to_bool(node.cond, node.cond.type)

    # If the condition holds, jump back to the body
    branch_if body_index, node: nil

    # Here we are at the point where the condition didn't hold anymore.
    # We must convert `nil` to whatever while's type is.
    upcast node.body, @context.program.nil_type, node.type

    # Otherwise we are at the end of the while.
    # Any `break` that happened leads us here
    while_breaks.each do |while_break|
      patch_jump(while_break)
    end

    unless @wants_value
      pop aligned_sizeof_type(node), node: nil
    end

    @while = old_while
    @while_breaks = old_while_breaks
    @while_nexts = old_while_nexts

    false
  end

  def visit(node : Return)
    compile_return(node, node.exp)
  end

  def compile_return(node, exp)
    exp_type =
      if exp
        request_value(exp)
        exp.type?
      else
        put_nil node: node
        @context.program.nil_type
      end

    def_type = @def.not_nil!.type

    compiled_block = @compiled_block
    if compiled_block
      def_type = merge_block_break_type(def_type, compiled_block.block)
    end

    # Check if it's an explicit Nil return
    if def_type.nil_type?
      # In that case we don't need the return value, so we just pop it
      pop aligned_sizeof_type(exp_type), node: node
    else
      upcast node, exp_type, def_type
    end

    if @compiling_block
      leave_def aligned_sizeof_type(def_type), node: node
    else
      # If this return happens inside a begin/ensure block,
      # inline any ensure right now.
      @ensure_stack.reverse_each do |an_ensure|
        discard_value(an_ensure)
      end

      leave aligned_sizeof_type(def_type), node: node
    end

    false
  end

  def visit(node : TypeOf)
    return false unless @wants_value

    put_type node.type, node: node
    false
  end

  def visit(node : SizeOf)
    return false unless @wants_value

    put_i32 inner_sizeof_type(node.exp), node: node

    false
  end

  def visit(node : InstanceSizeOf)
    return false unless @wants_value

    put_i32 inner_instance_sizeof_type(node.exp), node: node

    false
  end

  def visit(node : AlignOf)
    return false unless @wants_value

    put_i32 inner_alignof_type(node.exp), node: node

    false
  end

  def visit(node : InstanceAlignOf)
    return false unless @wants_value

    put_i32 inner_instance_alignof_type(node.exp), node: node

    false
  end

  def visit(node : TypeNode)
    return false unless @wants_value

    put_type node.type, node: node
    false
  end

  def visit(node : Path)
    return false unless @wants_value

    if const = node.target_const
      if const.value.simple_literal?
        with_node_override(node) do
          const.value.accept self
        end
      elsif const == @context.program.argc
        argc_unsafe(node: node)
      elsif const == @context.program.argv
        argv_unsafe(node: node)
      else
        index = initialize_const_if_needed(const)
        get_const index, aligned_sizeof_type(const.value), node: node
      end
    elsif replacement = node.syntax_replacement
      replacement.accept self
    else
      put_type node.type, node: node
    end
    false
  end

  private def get_const_index_and_compiled_def(const : Const) : {Int32, CompiledDef}
    index_and_compiled_def = @context.const_index_and_compiled_def?(const)
    return index_and_compiled_def if index_and_compiled_def

    value = const.value
    value = @context.program.cleanup(value)

    fake_def = const.fake_def.not_nil!
    fake_def.owner = const.namespace.metaclass
    fake_def.body = value
    fake_def.bind_to(value)

    compiled_def = CompiledDef.new(@context, fake_def, fake_def.owner, 0)

    declare_local_vars(fake_def, compiled_def.local_vars)

    compiler = Compiler.new(@context, compiled_def, top_level: true)
    compiler.compile_def(compiled_def)

    {% if Debug::DECOMPILE %}
      puts "=== #{const} ==="
      puts Disassembler.disassemble(@context, compiled_def)
      puts "=== #{const} ==="
    {% end %}

    {@context.declare_const(const, compiled_def), compiled_def}
  end

  def visit(node : Generic)
    return false unless @wants_value

    put_type node.type, node: node
    false
  end

  def visit(node : PointerOf)
    return false unless @wants_value

    exp = node.exp
    case exp
    when Var
      compile_pointerof_var(node, exp.name)
    when InstanceVar
      compile_pointerof_ivar(node, exp.name)
    when ClassVar
      compile_pointerof_class_var(node, exp)
    when ReadInstanceVar
      compile_pointerof_read_instance_var(exp.obj, exp.obj.type, exp.name)
    when Call
      # lib external var
      external = exp.dependencies.first.as(External)
      fn = @context.c_function(external.real_name)

      # Put the symbol address, which is a pointer
      put_u64 fn.address, node: node
    else
      node.raise "BUG: missing interpret for PointerOf with exp #{exp.class}"
    end
    false
  end

  private def compile_pointerof_var(node : ASTNode, name : String)
    var = lookup_local_var_or_closured_var(name)
    case var
    in LocalVar
      index, type = var.index, var.type
      pointerof_var(index, node: node)
    in ClosuredVar
      read_closured_var_pointer(var, node: node)
    end
  end

  private def compile_pointerof_ivar(node : ASTNode, name : String)
    closure_self = lookup_closured_var?("self")
    if closure_self
      get_closured_self_pointer(closure_self, name, node: node)
      return
    end

    index = scope.index_of_instance_var(name).not_nil!
    offset = if scope.struct?
               @context.offset_of(scope, index)
             else
               @context.instance_offset_of(scope, index)
             end
    pointerof_ivar(offset, node: node)
  end

  private def compile_pointerof_class_var(node : ASTNode, exp : ClassVar)
    dispatch_class_var(exp) do |class_var|
      index, compiled_def = class_var_index_and_compiled_def(class_var, node: node)
      initialize_class_var_if_needed(class_var, index, compiled_def) if compiled_def
      pointerof_class_var(index, node: node)
    end
  end

  def visit(node : Not)
    node.type = @context.program.no_return unless node.type?

    exp = node.exp
    exp.accept self
    return false unless @wants_value

    value_to_bool(exp, exp.type)
    logical_not node: node

    false
  end

  def visit(node : Cast)
    request_value node.obj

    # TODO: check @wants_value in these branches

    obj_type = node.obj.type
    to_type = node.to.type.virtual_type

    # TODO: check the proper conditions in codegen
    if obj_type == to_type
      # TODO: not tested
      nop
    elsif obj_type.pointer? && to_type.pointer?
      # Cast between pointers is nop
      nop
    elsif obj_type.nil_type? && to_type.pointer?
      # Cast from nil to Void* produces a null pointer
      if @wants_value
        pop aligned_sizeof_type(obj_type), node: nil
        put_i64 0, node: nil
      end
    elsif obj_type.pointer? && to_type.reference_like?
      # Cast from pointer to reference is nop
      nop
    elsif obj_type.reference_like? && to_type.is_a?(PointerInstanceType)
      # Cast from reference to pointer is nop
      nop
    elsif node.upcast?
      upcast node, obj_type, to_type
    else
      # Check if obj is a `to_type`
      dup aligned_sizeof_type(node.obj), node: nil
      filtered_type = is_a(node, obj_type, to_type)

      # If so, branch
      branch_if 0, node: nil
      cond_jump_location = patch_location

      # Otherwise we need to raise
      put_string to_type.devirtualize.to_s, node: nil
      put_string node.location.to_s, node: nil

      call = Call.new(
        nil,
        "__crystal_raise_cast_failed",
        [
          TypeNode.new(obj_type),
          TypeNode.new(@context.program.string),
          TypeNode.new(@context.program.string),
        ] of ASTNode,
        global: true,
      )
      @context.program.semantic(call)

      target_def = call.target_def

      compiled_def = @context.defs[target_def]? ||
                     begin
                       create_compiled_def(call, target_def)
                     rescue ex : Crystal::TypeException
                       node.raise ex.message, inner: ex
                     end
      call compiled_def, node: node

      patch_jump(cond_jump_location)

      if @wants_value
        downcast node.obj, obj_type, filtered_type
      else
        pop aligned_sizeof_type(obj_type), node: nil
      end
    end

    false
  end

  def visit(node : NilableCast)
    obj_type = node.obj.type
    to_type = node.to.type.virtual_type

    # TODO: check the proper conditions in codegen
    if obj_type == to_type
      node.obj.accept self

      return false
    end

    filtered_type = obj_type.filter_by(to_type)
    unless filtered_type
      # If .as?(...) has no resulting type we must cast
      # whatever type we have to nil.
      discard_value node.obj
      upcast node.obj, @context.program.nil_type, node.type
      return false
    end

    node.obj.accept self

    if node.upcast?
      upcast node.obj, obj_type, node.non_nilable_type
      upcast node.obj, node.non_nilable_type, node.type
      return false
    end

    # Check if obj is a `to_type`
    dup aligned_sizeof_type(node.obj), node: nil
    filter_type(node, obj_type, filtered_type)

    # If so, branch
    branch_if 0, node: nil
    cond_jump_location = patch_location

    # Otherwise it's nil
    put_nil node: nil
    pop aligned_sizeof_type(node.obj), node: nil
    upcast node.obj, @context.program.nil_type, node.type
    jump 0, node: nil
    otherwise_jump_location = patch_location

    patch_jump(cond_jump_location)
    downcast node.obj, obj_type, node.non_nilable_type
    upcast node.obj, node.non_nilable_type, node.type

    patch_jump(otherwise_jump_location)

    false
  end

  def visit(node : IsA)
    node.obj.accept self
    return false unless @wants_value

    obj_type = node.obj.type
    const_type = node.const.type

    is_a(node, obj_type, const_type)

    false
  end

  def visit(node : RespondsTo)
    node.obj.accept self
    return false unless @wants_value

    obj_type = node.obj.type

    responds_to(node, obj_type, node.name)

    false
  end

  private def is_a(node : ASTNode, type : Type, target_type : Type)
    type = type.remove_indirection
    filtered_type = type.filter_by(target_type).not_nil!

    filter_type(node, type, filtered_type)

    filtered_type
  end

  private def responds_to(node : ASTNode, type : Type, name : String)
    type = type.remove_indirection
    filtered_type = type.filter_by_responds_to(name).not_nil!

    filter_type(node, type, filtered_type)
  end

  private def filter_type(node : ASTNode, type : Type, filtered_type : Type)
    if type == filtered_type
      # TODO: not tested
      pop aligned_sizeof_type(type), node: nil
      put_true node: nil
      return
    end

    case type
    when VirtualType
      reference_is_a(type_id(filtered_type), node: node)
    when MixedUnionType
      union_is_a(aligned_sizeof_type(type), type_id(filtered_type), node: node)
    when NilableReferenceType
      if filtered_type.nil_type?
        pointer_is_null(node: node)
      else
        pointer_is_not_null(node: node)
      end
    when NilableReferenceUnionType
      if filtered_type.nil_type?
        # TODO: not tested
        pointer_is_null(node: node)
      else
        # TODO: maybe missing checking against another reference union type?
        reference_is_a(type_id(filtered_type), node: node)
      end
    when NilableProcType
      # Remove the closure data
      pop sizeof(Void*), node: nil

      if filtered_type.nil_type?
        pointer_is_null(node: node)
      else
        pointer_is_not_null(node: node)
      end
    when ReferenceUnionType
      case filtered_type
      when NonGenericClassType
        reference_is_a(type_id(filtered_type), node: node)
      when GenericClassInstanceType
        # TODO: not tested
        reference_is_a(type_id(filtered_type), node: node)
      when VirtualType
        # TODO: not tested
        reference_is_a(type_id(filtered_type), node: node)
      when ReferenceUnionType
        # TODO: not tested
        reference_is_a(type_id(filtered_type), node: node)
      else
        node.raise "BUG: missing filter type from #{type} to #{filtered_type} (#{type.class} to #{filtered_type.class})"
      end
    when VirtualMetaclassType
      case filtered_type
      when MetaclassType, VirtualMetaclassType, GenericClassInstanceMetaclassType, GenericModuleInstanceMetaclassType
        metaclass_is_a(type_id(filtered_type), node: node)
      else
        node.raise "BUG: missing filter type from #{type} to #{filtered_type} (#{type.class} to #{filtered_type.class})"
      end
    else
      node.raise "BUG: missing filter type from #{type} to #{filtered_type} (#{type.class} to #{filtered_type.class})"
    end
  end

  def visit(node : Call)
    obj = node.obj
    with_scope = node.with_scope

    if !obj && with_scope && node.uses_with_scope?
      obj = Var.new(WITH_SCOPE, with_scope)
    end

    target_defs = node.target_defs
    unless target_defs
      node.raise "BUG: no target defs"
    end

    if target_defs.size == 1
      target_def = target_defs.first
    else
      target_def = Multidispatch.create_def(@context, node, target_defs)
    end

    body = target_def.body
    if body.is_a?(Primitive)
      visit_primitive(node, body, target_def)
      return false
    end

    if body.is_a?(InstanceVar)
      # Inline the call, so that it also works fine when wanting to take a pointer through things
      # (this is how compiled Crystal works too
      with_node_override(node) do
        if obj
          compile_read_instance_var(node, obj, body.name, owner: target_def.owner)
        else
          compile_instance_var(body)
        end
      end

      # We still have to accept the call arguments, but discard their values
      node.args.each { |arg| discard_value(arg) }

      return false
    end

    if body.is_a?(Var) && body.name == "self"
      # We also inline calls that simply return "self"

      if @wants_value
        if obj
          request_value(obj)
        else
          if scope.struct? && scope.passed_by_value?
            # Load the entire self from the pointer that's self
            get_self_ivar 0, aligned_sizeof_type(scope), node: node
          else
            put_self(node: node)
          end
        end
      end

      # We still have to accept the call arguments, but discard their values
      node.args.each { |arg| discard_value(arg) }

      return false
    end

    if obj.try(&.type).is_a?(LibType)
      compile_lib_call(node)
      return false
    end

    # First compile the call args, then compile the def.
    # The reason is that compiling the call args might introduce
    # new temporary local variables, and if want to have those
    # in place before compiling any block (otherwise the block
    # variables' space would conflict with the temporary space)
    compile_call_args(node, target_def)

    compiled_def = @context.defs[target_def]? ||
                   begin
                     create_compiled_def(node, target_def)
                   rescue ex : Crystal::TypeException
                     node.raise ex.message, inner: ex
                   end

    if (block = node.block) && !block.fun_literal
      call_with_block compiled_def, node: node
    else
      call compiled_def, node: node
    end

    unless @wants_value
      pop aligned_sizeof_type(node), node: nil
    end

    false
  end

  private def compile_lib_call(node : Call)
    target_def = node.target_def
    external = target_def.as(External)

    args_bytesizes = [] of Int32
    args_ffi_types = [] of FFI::Type

    node.args.each_with_index do |arg, i|
      arg_type = arg.type

      case arg_type
      when NilType
        # Nil is used to mean Pointer.null
        discard_value(arg)
        put_i64 0, node: arg
      when StaticArrayInstanceType
        # Static arrays are passed as pointers to C
        compile_pointerof_node(arg, arg_type)
      else
        request_value(arg)
      end
      # TODO: upcast?

      case arg_type
      when NilType
        args_bytesizes << sizeof(Pointer(Void))
        args_ffi_types << FFI::Type.pointer
      when ProcInstanceType
        external_arg = external.args[i]
        args_bytesizes << sizeof(Void*)
        args_ffi_types << FFI::Type.pointer

        proc_to_c_fun external_arg.type.as(ProcInstanceType).ffi_call_interface, node: nil
      when StaticArrayInstanceType
        # Static arrays are passed as pointers to C
        args_bytesizes << sizeof(Void*)
        args_ffi_types << FFI::Type.pointer
      else
        case arg
        when Out
          # TODO: this out handling is bad. Why is out's type not a pointer already?
          args_bytesizes << sizeof(Pointer(Void))
          args_ffi_types << FFI::Type.pointer
        else
          if external.varargs?
            # Apply default promotions to certain types used as variadic arguments in C function calls.

            # Resolve EnumType to its base type because that's the type that gets promoted
            if arg_type.is_a?(EnumType)
              arg_type = arg_type.base_type
            end

            if arg_type.is_a?(FloatType) && arg_type.bytes < 8
              # Arguments of type float are promoted to double
              promoted_type = @context.program.float64
              primitive_convert node, arg_type, promoted_type, true

              arg_type = promoted_type
            elsif arg_type.is_a?(IntegerType) && arg_type.bytes < 4
              # Integer argument types smaller than 4 bytes are promoted to 4 bytes
              promoted_type = arg_type.signed? ? @context.program.int32 : @context.program.uint32
              primitive_convert node, arg_type, promoted_type, true

              arg_type = promoted_type
            end
          end

          args_bytesizes << aligned_sizeof_type(arg_type)
          args_ffi_types << arg_type.ffi_arg_type
        end
      end
    end

    if external.varargs?
      lib_function = LibFunction.new(
        def: external,
        symbol: @context.c_function(external.real_name),
        call_interface: FFI::CallInterface.variadic(
          external.type.ffi_type,
          args_ffi_types,
          fixed_args: external.args.size
        ),
        args_bytesizes: args_bytesizes,
      )
      @context.add_gc_reference(lib_function)
    else
      lib_function = @context.lib_functions[external] ||= LibFunction.new(
        def: external,
        symbol: @context.c_function(external.real_name),
        call_interface: FFI::CallInterface.new(
          external.type.ffi_type,
          args_ffi_types
        ),
        args_bytesizes: args_bytesizes,
      )
    end

    lib_call(lib_function, node: node)

    unless @wants_value
      pop aligned_sizeof_type(node), node: nil
    end

    false
  end

  private def create_compiled_def(node : Call, target_def : Def)
    block = node.block
    block = nil if block && !block.visited? && !block.fun_literal

    # Compile the block too if there's one
    if block && !block.fun_literal
      compiled_block = create_compiled_block(block, target_def)
    end

    args_bytesize = 0

    obj = node.obj
    args = node.args
    obj_type = obj.try(&.type) || target_def.owner

    # TODO: should this use `Type#passed_as_self?` instead?
    if obj_type == @context.program || obj_type.is_a?(FileModule)
      # Nothing
    elsif obj_type.passed_by_value?
      args_bytesize += sizeof(Pointer(UInt8))
    else
      args_bytesize += aligned_sizeof_type(obj_type)
    end

    multidispatch_self = target_def.args.first?.try &.name == "self"

    i = 0

    # This is the case of a multidispatch with an explicit "self" being passed
    i += 1 if multidispatch_self

    args.each do
      target_def_arg = target_def.args[i]
      target_def_var_type = target_def.vars.not_nil![target_def_arg.name].type
      args_bytesize += aligned_sizeof_type(target_def_var_type)

      i += 1
    end

    node_args_size = node.args.size

    # Don't count "self" arg in multidispatch
    node_args_size += 1 if multidispatch_self

    # Also take magic constants into account.
    # Every magic constant is either an int or a string, and that's
    # always 8 bytes when aligned.
    args_bytesize += 8 * (target_def.args.size - node_args_size)

    # Also consider special vars
    special_vars = target_def.special_vars
    if special_vars
      # Each special var argument is a hidden pointer
      args_bytesize += special_vars.size * sizeof(Void*)
    end

    # If the block is captured there's an extra argument
    if block && block.fun_literal
      args_bytesize += sizeof(Proc(Void))
    end

    # See line 19 in codegen call
    owner = node.super? ? node.scope : target_def.owner

    compiled_def = CompiledDef.new(@context, target_def, owner, args_bytesize)

    # We don't cache defs that yield because we inline the block's contents
    if block && !block.fun_literal
      @context.add_gc_reference(compiled_def)
    else
      @context.defs[target_def] = compiled_def
    end

    declare_local_vars(target_def, compiled_def.local_vars)

    compiler = Compiler.new(@context, compiled_def, top_level: false)
    compiler.compiled_block = compiled_block

    begin
      compiler.compile_def(compiled_def)
    rescue ex : Crystal::CodeError
      node.raise "compiling #{node}", inner: ex
    end

    {% if Debug::DECOMPILE %}
      puts "=== #{target_def.owner}##{target_def.name} ==="
      puts compiled_def.local_vars
      puts Disassembler.disassemble(@context, compiled_def)
      puts "=== #{target_def.owner}##{target_def.name} ==="
    {% end %}

    compiled_def
  end

  private def create_compiled_block(block : Block, target_def : Def)
    rewrite_block_with_splat(block)

    bytesize_before_block_local_vars = @local_vars.current_bytesize

    @local_vars.push_block

    begin
      needs_closure_context = false

      # If it's `with ... yield` we pass the "with" scope
      # as the first block argument.
      with_scope = block.scope
      if with_scope
        @local_vars.declare(WITH_SCOPE, with_scope)
      end

      block.vars.try &.each do |name, var|
        # Special vars don't have scopes like regular block vars do
        next if var.special_var?

        var_type = var.type?
        var_type ||= @context.program.nil_type

        if var.closure_in?(block)
          needs_closure_context = true
          next
        end

        next if var.context != block

        @local_vars.declare(name, var_type)
      end

      if needs_closure_context
        @local_vars.declare(Closure::VAR_NAME, @context.program.pointer_of(@context.program.void))
      end

      bytesize_after_block_local_vars = @local_vars.current_bytesize

      block_args_bytesize = block.args.sum { |arg| aligned_sizeof_type(arg) }

      # If it's `with ... yield` we pass the "with" scope
      # as the first block argument, so we must count it too
      # for the total blocks_args_bytesize.
      if with_scope
        block_args_bytesize += aligned_sizeof_type(with_scope)
      end

      compiled_block = CompiledBlock.new(block,
        args_bytesize: block_args_bytesize,
        locals_bytesize_start: bytesize_before_block_local_vars,
        locals_bytesize_end: bytesize_after_block_local_vars,
      )

      # Store it so the GC doesn't collect it (it's in the instructions but it might not be aligned)
      @context.add_gc_reference(compiled_block)

      compiler = Compiler.new(@context, @local_vars,
        instructions: compiled_block.instructions,
        scope: @scope, def: @def, top_level: false)
      compiler.compiled_block = @compiled_block
      compiler.block_level = block_level + 1

      compiler.compile_block(compiled_block, target_def, @closure_context)

      # Keep a copy of the local vars before exiting the block.
      # Otherwise we'll lose reference to the block's vars (useful for pry)
      compiled_block.local_vars = @local_vars.dup

      {% if Debug::DECOMPILE %}
        puts "=== #{target_def.owner}##{target_def.name}#block ==="
        puts compiled_block.local_vars
        puts Disassembler.disassemble(@context, compiled_block.instructions, @local_vars)
        puts "=== #{target_def.owner}##{target_def.name}#block ==="
      {% end %}
    ensure
      @local_vars.pop_block
    end

    compiled_block
  end

  private def rewrite_block_with_splat(node : Block)
    splat_index = node.splat_index
    return unless splat_index

    # If the block has a splat index, we rewrite it to something simpler.
    #
    # For example, assuming `y` is a tuple of 3 elements, we rewrite:
    #
    # ```
    # foo do |x, *y, z|
    #   p! x, y, z
    # end
    # ```
    #
    # to:
    #
    # ```
    # foo do |x, temp1, temp2, temp3, z|
    #   y = {temp1, temp2, temp3}
    #   p! x, y, z
    # end
    # ```
    #
    # TODO: consider doing this in CleanupTransformer to also simplify
    # compiled Crystal and any other future backend.
    splat_arg = node.args[splat_index]
    tuple_type = splat_arg.type.as(TupleInstanceType)

    temp_var_names = tuple_type.tuple_types.map do
      @context.program.new_temp_var_name
    end

    # Go from |x, *y, z| to |x, temp1, temp2, temp3|
    node.args[splat_index..splat_index] = temp_var_names.map_with_index do |temp_var_name, i|
      Var.new(temp_var_name, type: tuple_type.tuple_types[i])
    end

    # Create y = {temp1, temp2, temp3}
    assign_var = Var.new(splat_arg.name, type: tuple_type)
    tuple_vars = temp_var_names.map_with_index do |temp_var_name, i|
      Var.new(temp_var_name, type: tuple_type.tuple_types[i]).as(ASTNode)
    end
    tuple_literal = TupleLiteral.new(tuple_vars)
    tuple_literal.type = tuple_type

    assign = Assign.new(assign_var, tuple_literal)
    assign.type = tuple_type

    # Replace the block body
    block_body = node.body
    unless block_body
      block_body = NilLiteral.new
      block_body.type = @context.program.nil_type
    end

    exps = Expressions.new([assign, block_body] of ASTNode)
    exps.type = block_body.type
    node.body = exps

    # Remove the fact that the block has a splat
    node.splat_index = nil

    # We also need to declare the vars in the block
    temp_var_names.each_with_index do |temp_var_name, i|
      meta_var = MetaVar.new(temp_var_name, tuple_type.tuple_types[i])
      meta_var.context = node
      node.vars.not_nil![temp_var_name] = meta_var
    end
  end

  private def compile_call_args(node : Call, target_def : Def) : Nil
    obj = node.obj
    with_scope = node.with_scope

    if !obj && with_scope && node.uses_with_scope?
      obj = Var.new(WITH_SCOPE, with_scope)
    end

    if obj
      if obj.type.passed_by_value?
        compile_pointerof_node(obj, target_def.owner)
      else
        request_value(obj)
      end
    else
      # Pass implicit self if needed
      case target_def.owner
      when Program, FileModule
        # These types aren't passed as self
      else
        put_self(node: node)
      end
    end

    target_def_args = target_def.args
    multidispatch_self = target_def_args.first?.try &.name == "self"

    i = 0

    # This is the case of a multidispatch with an explicit "self" being passed
    i += 1 if multidispatch_self

    node.args.each do |arg|
      arg_type = arg.type
      target_def_arg = target_def_args[i]
      target_def_var_type = target_def.vars.not_nil![target_def_arg.name].type

      compile_call_arg(arg, arg_type, target_def_arg.type, target_def_var_type)

      i += 1
    end

    # Then magic constants (__LINE__, __FILE__, __DIR__)
    node_args_size = node.args.size

    # Then special vars
    special_vars = target_def.special_vars
    if special_vars
      special_vars.each do |special_var|
        var = lookup_local_var(special_var)
        pointerof_var(var.index, node: nil)
      end
    end

    # Don't count "self" arg in multidispatch
    node_args_size += 1 if multidispatch_self

    node_args_size.upto(target_def.args.size - 1) do |index|
      arg = target_def.args[index]
      default_value = arg.default_value.as(MagicConstant)
      location = node.location
      end_location = node.end_location
      case default_value.name
      when .magic_line?
        put_i32 MagicConstant.expand_line(location), node: node
      when .magic_end_line?
        # TODO: not tested
        put_i32 MagicConstant.expand_line(end_location), node: node
      when .magic_file?
        # TODO: not tested
        put_string MagicConstant.expand_file(location), node: node
      when .magic_dir?
        # TODO: not tested
        put_string MagicConstant.expand_dir(location), node: node
      else
        default_value.raise "BUG: unknown magic constant: #{default_value.name}"
      end
    end

    if fun_literal = node.block.try(&.fun_literal)
      request_value fun_literal
    end
  end

  private def compile_call_arg(arg, arg_type, target_def_arg_type, target_def_var_type)
    # Check autocasting from symbol to enum
    if arg.is_a?(SymbolLiteral) && target_def_var_type.is_a?(EnumType)
      symbol_name = arg.value.underscore
      target_def_var_type.types.each do |enum_name, enum_value|
        if enum_name.underscore == symbol_name
          request_value(enum_value.as(Const).value)
          return
        end
      end
    end

    if arg_type != target_def_var_type && arg.is_a?(NumberLiteral)
      case target_def_var_type
      when IntegerType
        # Autocast to integer
        compile_number(arg, target_def_var_type.kind, arg.value)
        return
      when FloatType
        # Autocast to float
        compile_number(arg, target_def_var_type.kind, arg.value)
        return
      end
    end

    request_value(arg)

    # Check number autocast but for non-literals
    if arg_type != target_def_arg_type && arg_type.is_a?(IntegerType | FloatType) && target_def_arg_type.is_a?(IntegerType | FloatType)
      primitive_convert(arg, arg_type, target_def_arg_type, checked: false)
    else
      # We first cast the argument to the def's arg type,
      # which is the external methods' type.
      downcast arg, arg_type, target_def_arg_type
    end

    # Then we need to cast the argument to the target_def variable
    # corresponding to the argument. If for example we have this:
    #
    # ```
    # def foo(x : Int32)
    #   x = nil
    # end
    #
    # foo(1)
    # ```
    #
    # Then the actual type of `x` inside `foo` is (Int32 | Nil),
    # and we must cast `1` to it.
    upcast arg, target_def_arg_type, target_def_var_type
  end

  private def compile_pointerof_node(obj : Var, owner : Type) : Nil
    if obj.name == "self"
      self_type = @def.not_nil!.vars.not_nil!["self"].type
      if self_type.passed_by_value? && in_multidispatch?
        # Inside a multidispatch "self" is already a pointer.
        get_local 0, sizeof(Void*), node: obj

        # If the self that we need to pass is a union but the actual type of `obj`
        # is not a union, we need to reach the union's value.
        if self_type.remove_indirection.is_a?(MixedUnionType) && !obj.type.remove_indirection.is_a?(MixedUnionType)
          pointer_add_constant 8, node: obj
        end
      elsif self_type == owner
        put_self(node: obj)
      else
        assign_to_temporary_and_return_pointer(obj)
      end
      return
    end

    var = lookup_local_var_or_closured_var(obj.name)
    var_type = var.type

    if obj.type == var_type
      pointerof_local_var_or_closured_var(var, node: obj)
    elsif var_type.is_a?(MixedUnionType) && obj.type.struct?
      # Get pointer of var
      pointerof_local_var_or_closured_var(var, node: obj)

      # Add 8 to it, to reach the union value
      pointer_add_constant 8, node: obj
    elsif var_type.is_a?(MixedUnionType) && obj.type.is_a?(MixedUnionType)
      pointerof_local_var_or_closured_var(var, node: obj)
    elsif var_type.is_a?(VirtualType) && var_type.struct? && var_type.abstract?
      if obj.type.is_a?(MixedUnionType)
        # If downcasting to a mix of the subtypes, it's a union type and it
        # has the same representation as the virtual type
        pointerof_local_var_or_closured_var(var, node: obj)
      else
        # A virtual struct is represented like {type_id, value}, and if we need
        # to downcast to one of the struct types we need to skip the type_id header,
        # which is 8 bytes.

        # Get pointer of var
        pointerof_local_var_or_closured_var(var, node: obj)

        # Add 8 to it, to reach the value
        pointer_add_constant 8, node: obj
      end
    else
      obj.raise "BUG: missing call receiver by value cast from #{var_type} to #{obj.type} (#{var_type.class} to #{obj.type.class})"
    end
  end

  private def compile_pointerof_node(obj : InstanceVar, owner : Type) : Nil
    compile_pointerof_ivar(obj, obj.name)
  end

  private def compile_pointerof_node(obj : ClassVar, owner : Type) : Nil
    compile_pointerof_class_var(obj, obj)
  end

  private def compile_pointerof_node(obj : Path, owner : Type) : Nil
    const = obj.target_const.not_nil!
    index = initialize_const_if_needed(const)
    get_const_pointer index, node: obj
  end

  private def compile_pointerof_node(obj : ReadInstanceVar, owner : Type) : Nil
    compile_pointerof_read_instance_var(obj.obj, obj.obj.type, obj.name)
  end

  private def compile_pointerof_node(call : Call, owner : Type) : Nil
    call_obj = call.obj
    with_scope = call.with_scope

    if !call_obj && with_scope && call.uses_with_scope?
      call_obj = Var.new(WITH_SCOPE, with_scope)
    end

    target_defs = call.target_defs
    unless target_defs
      call.raise "BUG: no target defs"
    end

    unless target_defs.size == 1
      assign_to_temporary_and_return_pointer(call)
      return
    end

    target_def = target_defs.first
    body = target_def.body

    if body.is_a?(Primitive) && body.name == "pointer_get"
      # We don't want pointer.value to return a copy of something
      # if we are calling through it
      call_obj = call_obj.not_nil!
      request_value(call_obj)
      return
    end

    if body.is_a?(InstanceVar)
      # Inline the call, so that it also works fine when wanting to
      # take a pointer through things (this is how compiled Crystal works too
      if call_obj
        compile_pointerof_read_instance_var(call_obj, target_def.owner, body.name)
      else
        compile_pointerof_ivar(body, body.name)
      end

      # We still have to accept the call arguments, but discard their values
      call.args.each { |arg| discard_value(arg) }
      return
    end

    if body.is_a?(Var) && body.name == "self"
      # We also inline calls that simply return "self"
      if call_obj
        compile_pointerof_node(call_obj, owner)
      else
        put_self(node: call)
      end

      # We still have to accept the call arguments, but discard their values
      call.args.each { |arg| discard_value(arg) }
      return
    end

    assign_to_temporary_and_return_pointer(call)
  end

  private def compile_pointerof_node(obj : ASTNode, owner : Type) : Nil
    assign_to_temporary_and_return_pointer(obj)
  end

  # Assigns the object's value to a temporary
  # local variable, and then produces a pointer to that local variable.
  # In this way we make sure that the memory the pointer is pointing
  # to remains available, at least in this call frame.
  private def assign_to_temporary_and_return_pointer(obj : ASTNode)
    temp_var_name = @context.program.new_temp_var_name
    temp_var_index = @local_vars.declare(temp_var_name, obj.type).not_nil!

    request_value(obj)

    set_local temp_var_index, aligned_sizeof_type(obj), node: obj
    pointerof_var(temp_var_index, node: obj)
  end

  private def declare_local_vars(vars_owner, local_vars : LocalVars, owner = vars_owner)
    needs_closure_context = false
    special_vars = owner.is_a?(Def) ? owner.special_vars : nil

    # First declare self, if there is one
    self_var = vars_owner.vars.try &.["self"]?
    if self_var
      local_vars.declare("self", self_var.type)
    end

    # Then define def arguments because those will come in order from calls
    if owner.is_a?(Def)
      owner.args.each do |arg|
        var = owner.vars.not_nil![arg.name]
        var_type = var.type?
        next unless var_type

        # The self arg can appear if it's a multidispatch, and we don't want
        # to declare it twice.
        next if arg.name == "self"

        if var.closure_in?(owner)
          needs_closure_context = true

          # Declare a local variable with a different name because
          # we don't want to find it when doing local var lookups,
          # but we'll need to copy it from the def args to the closure
          local_vars.declare(closured_arg_name(arg.name), var_type)
          next
        end

        local_vars.declare(var.name, var_type)
      end

      # We also need to declare the block arg with a different name
      # if it's closured.
      if owner.uses_block_arg?
        block_arg = owner.block_arg.not_nil!

        var = owner.vars.not_nil![block_arg.name]
        var_type = var.type?
        if var_type && var.closure_in?(owner)
          needs_closure_context = true

          # Declare a local variable with a different name because
          # we don't want to find it when doing local var lookups,
          # but we'll need to copy it from the def args to the closure
          local_vars.declare(closured_arg_name(block_arg.name), var_type)
        end
      end
    end

    # Now declare special vars, if any
    if owner.is_a?(Def) && (special_vars = owner.special_vars)
      special_vars.each do |special_var|
        var = vars_owner.vars.not_nil![special_var]
        local_vars.declare("#{var.name}*", @context.program.pointer_of(var.type))
      end
    end

    # Next declare all remaining variables
    vars_owner.vars.try &.each do |name, var|
      var_type = var.type?
      next unless var_type

      # Skip if the var was already declared because it's also an argument
      next if name == "self"
      next if owner.is_a?(Def) && owner.args.any? { |arg| arg.name == name }

      # TODO (optimization): don't declare local var if it's closured,
      # but we need to be careful to support def args being closured
      if var.closure_in?(owner)
        needs_closure_context = true
        next
      end

      local_vars.declare(name, var_type)
    end

    needs_closure_context ||= owner.is_a?(Def) && owner.self_closured?

    if needs_closure_context
      local_vars.declare(Closure::VAR_NAME, @context.program.pointer_of(@context.program.void))
    end
  end

  private def closured_arg_name(name : String)
    "^#{name}"
  end

  private def initialize_const_if_needed(const)
    index, compiled_def = get_const_index_and_compiled_def const

    # Do this:
    #
    # ```
    # unless const_initialized(index)
    #   call const_initializer
    #   set_const index
    # end
    # ```

    # This is `unless const_initialized(index)`
    const_initialized index, node: nil
    branch_if 0, node: nil
    cond_jump_location = patch_location

    # Now we are on the `then` branch
    call compiled_def, node: nil
    set_const index, aligned_sizeof_type(const.value), node: nil

    # Here we are outside of the unless
    patch_jump(cond_jump_location)

    index
  end

  private def initialize_class_var_if_needed(var, index, compiled_def)
    # Do this:
    #
    # ```
    # unless class_var_initialized(index)
    #   call class_var_initializer
    #   set_class_var index
    # end
    # ```

    # This is `unless class_var_initialized(index)`
    class_var_initialized index, node: nil
    branch_if 0, node: nil
    cond_jump_location = patch_location

    # Now we are on the `then` branch
    call compiled_def, node: nil
    set_class_var index, aligned_sizeof_type(var), node: nil

    # Here we are outside of the unless
    patch_jump(cond_jump_location)

    index
  end

  private def accept_call_members(node : Call)
    if obj = node.obj
      obj.accept(self)
    else
      put_self(node: node) unless scope.is_a?(Program)
    end

    node.args.each &.accept(self)
  end

  def visit(node : Out)
    case exp = node.exp
    when Var
      local_var = lookup_local_var_or_closured_var(exp.name)
      case local_var
      in LocalVar
        pointerof_var(local_var.index, node: node)
      in ClosuredVar
        node.raise "BUG: missing interpreter out closured var"
      end
    when InstanceVar
      compile_pointerof_ivar(node, exp.name)
    when Underscore
      # Allocate a temporary variable just for the underscore, then get a pointer to it
      temp_var_name = @context.program.new_temp_var_name
      temp_var_index = @local_vars.declare(temp_var_name, node.type).not_nil!

      pointerof_var temp_var_index, node: node
    else
      node.raise "BUG: unexpected out exp: #{exp}"
    end

    false
  end

  def visit(node : ProcLiteral)
    is_closure = node.def.closure?

    # TODO: This was copied from Codegen. Why is it not in CleanupTransformer?
    # If we don't care about a proc literal's return type then we mark the associated
    # def as returning void. This can't be done in the type inference phase because
    # of bindings and type propagation.
    if node.force_nil?
      node.def.set_type @context.program.nil
    else
      # Use proc literal's type, which might have a broader type then the body
      # (for example, return type: Int32 | String, body: String)
      node.def.set_type node.return_type
    end

    target_def = node.def
    target_def.owner = @context.program
    args = target_def.args

    # 1. Compile def
    args_bytesize = args.sum { |arg| aligned_sizeof_type(arg) }
    args_bytesize += sizeof(Void*) if is_closure

    compiled_def = CompiledDef.new(@context, target_def, target_def.owner, args_bytesize)

    # 2. Store it in context
    @context.add_gc_reference(compiled_def)

    # Declare local variables for the newly compiled function

    # First declare the proc arguments, so that the order matches the call
    target_def.args.each do |arg|
      var = target_def.vars.not_nil![arg.name]
      var_type = var.type?
      next unless var_type

      if var.closure_in?(target_def)
        # Declare a local variable with a different name because
        # we don't want to find it when doing local var lookups,
        # but we'll need to copy it from the def args to the closure
        compiled_def.local_vars.declare(closured_arg_name(arg.name), var_type)
        next
      end

      compiled_def.local_vars.declare(arg.name, var_type)
    end

    needs_closure_context = (target_def.vars.try &.any? { |name, var| var.type? && var.closure_in?(target_def) })

    # Declare the closure context arg and var, if any
    if is_closure || needs_closure_context
      if is_closure && needs_closure_context
        compiled_def.local_vars.declare(Closure::ARG_NAME, @context.program.pointer_of(@context.program.void))
      end

      compiled_def.local_vars.declare(Closure::VAR_NAME, @context.program.pointer_of(@context.program.void))
    end

    # Then declare all variables
    target_def.vars.try &.each do |name, var|
      var_type = var.type?
      next unless var_type

      if var.closure_in?(target_def)
        needs_closure_context = true
        next
      end

      # Skip arg because it was already declared above
      next if target_def.args.any? { |arg| arg.name == name }

      # TODO: closures!
      next if var.context != target_def

      compiled_def.local_vars.declare(name, var_type)
    end

    compiler = Compiler.new(@context, compiled_def, scope: scope, top_level: false)
    begin
      compiler.compile_def(compiled_def, is_closure ? @closure_context : nil)
    rescue ex : Crystal::CodeError
      node.raise "compiling #{node}", inner: ex
    end

    {% if Debug::DECOMPILE %}
      puts "=== ProcLiteral ==="
      puts compiled_def.local_vars
      puts Disassembler.disassemble(@context, compiled_def)
      puts "=== ProcLiteral ==="
    {% end %}

    # 3. Push compiled_def id to stack
    put_i64 compiled_def.object_id.to_i64!, node: node

    # 4. Push closure context to stack
    if is_closure
      # If it's a closure, we push the pointer that holds the closure data
      closure_var_index = get_closure_var_index
      get_local closure_var_index, sizeof(Void*), node: node
    else
      # Otherwise, it's a null pointer
      put_i64 0, node: node
    end

    false
  end

  def visit(node : Break)
    exp = node.exp

    exp_type =
      if exp
        request_value(exp)
        exp.type
      else
        put_nil node: node

        @context.program.nil_type
      end

    if target_while = @while
      target_while = @while.not_nil!

      upcast node, exp_type, target_while.type

      jump 0, node: nil
      @while_breaks.not_nil! << patch_location
    elsif compiling_block = @compiling_block
      block = compiling_block.block
      target_def = compiling_block.target_def

      final_type = merge_block_break_type(target_def.type, block)

      upcast node, exp_type, final_type

      break_block aligned_sizeof_type(final_type), node: node
    else
      node.raise "BUG: break without target while or block"
    end

    false
  end

  def visit(node : Next)
    exp = node.exp

    if @while
      if exp
        discard_value(exp)
      else
        put_nil node: node
      end

      jump 0, node: nil
      @while_nexts.not_nil! << patch_location
    elsif compiling_block = @compiling_block
      exp_type =
        if exp
          request_value(exp)
          exp.type
        else
          put_nil node: node
          @context.program.nil_type
        end

      upcast node, exp_type, compiling_block.block.type
      leave aligned_sizeof_type(compiling_block.block.type), node: node
    else
      if @def.try(&.captured_block?)
        # next inside a proc or captured block is like doing return
        compile_return(node, exp)
      else
        node.raise "BUG: next without target while, block, and not inside captured_block"
      end
    end

    false
  end

  def visit(node : Yield)
    compiled_block = @compiled_block.not_nil!
    block = compiled_block.block

    splat_index = block.splat_index
    if splat_index
      node.raise "BUG: block with splat should have been rewritten to one withone one"
    end

    with_scope = node.scope
    if with_scope
      request_value(with_scope)
    end

    pop_obj = nil

    # Check if tuple unpacking is needed.
    # This happens when a yield has only one expression that's a tuple
    # type, and the block arguments are more than one.
    #
    # For example:
    #
    #     def foo
    #       yield({1, 2})
    #     end
    #
    #     foo do |x, y|
    #     end
    #
    # If the first yield argument is a splat then no tuple unpacking is done:
    #
    #     def foo
    #       yield(*{1, 2}) # no unpacking
    #     end
    #
    #     foo do |x, y|
    #     end
    #
    # Unless... the tuple has a single tuple inside it:
    #
    #     def foo
    #       yield(*{ {1, 2} }) # unpacking 1 into x and 2 into y
    #     end
    #
    #     foo do |x, y|
    #     end
    #
    # That's all expressed in the logic below:
    if node.exps.size == 1 &&
       (exp = node.exps.first) &&
       (tuple_type = exp.type).is_a?(TupleInstanceType) &&
       (!exp.is_a?(Splat) || (
         exp.is_a?(Splat) &&
         tuple_type.tuple_types.size == 1 &&
         tuple_type.tuple_types.first.is_a?(TupleInstanceType)
       )) &&
       block.args.size > 1
      # This is the case of `yield(*{ {1, 2}})`
      if exp.is_a?(Splat)
        exp = exp.exp
        tuple_type = tuple_type.tuple_types.first.as(TupleInstanceType)
      end

      # Accept the tuple
      request_value exp

      # We need to cast to the block var, not arg
      # (the var might have more types in it if it's assigned other values)
      block_var_types = block.args.map do |arg|
        block.vars.not_nil![arg.name].type
      end

      unpack_tuple exp, tuple_type, block_var_types

      # We need to discard the tuple value that comes before the unpacked values
      pop_obj = tuple_type
    else
      block_arg_index = 0

      node.exps.each do |exp|
        if exp.is_a?(Splat)
          tuple_type = exp.exp.type.as(TupleInstanceType)

          # First accept the tuple
          request_value(exp.exp)

          # Compute which block var types we need to unpack to,
          # and what's their total size
          block_var_types = [] of Type
          block_var_types_size = 0

          tuple_element_index = 0
          while block_arg_index < block.args.size && tuple_element_index < tuple_type.tuple_types.size
            block_arg = block.args[block_arg_index]
            block_var = block.vars.not_nil![block_arg.name]
            block_var_type = block_var.type

            block_var_types << block_var_type
            block_var_types_size += aligned_sizeof_type(block_var_type)

            block_arg_index += 1
            tuple_element_index += 1
          end

          unpack_tuple exp, tuple_type, block_var_types

          # Now we need to pop the tuple
          pop_from_offset aligned_sizeof_type(tuple_type), block_var_types_size, node: nil
        else
          if block_arg_index < block.args.size
            request_value(exp)

            # We need to cast to the block var, not arg
            # (the var might have more types in it if it's assigned other values)
            block_arg = block.args[block_arg_index]
            block_var = block.vars.not_nil![block_arg.name]

            upcast exp, exp.type, block_var.type
          else
            discard_value(exp)
          end

          block_arg_index += 1
        end
      end
    end

    call_block compiled_block, node: node

    if @wants_value
      pop_from_offset aligned_sizeof_type(pop_obj), aligned_sizeof_type(node), node: nil if pop_obj
    else
      if pop_obj
        pop aligned_sizeof_type(node) + aligned_sizeof_type(pop_obj), node: nil
      else
        pop aligned_sizeof_type(node), node: nil
      end
    end

    false
  end

  def visit(node : ClassDef)
    with_scope(node.resolved_type.metaclass) do
      discard_value node.body
    end

    return false unless @wants_value

    put_nil(node: node)
    false
  end

  def visit(node : ModuleDef)
    with_scope(node.resolved_type.metaclass) do
      discard_value node.body
    end

    return false unless @wants_value

    put_nil(node: node)
    false
  end

  private def with_scope(scope : Type, &)
    old_scope = @scope
    @scope = scope
    begin
      yield
    ensure
      @scope = old_scope
    end
  end

  def visit(node : EnumDef)
    # TODO: visit body?
    false
  end

  def visit(node : Def)
    false
  end

  def visit(node : FunDef)
    false
  end

  def visit(node : LibDef)
    false
  end

  def visit(node : Macro)
    false
  end

  def visit(node : VisibilityModifier)
    node.exp.accept self
    false
  end

  def visit(node : Annotation)
    false
  end

  def visit(node : AnnotationDef)
    false
  end

  def visit(node : Alias)
    false
  end

  def visit(node : Include)
    false
  end

  def visit(node : Extend)
    false
  end

  def visit(node : Unreachable)
    unreachable("Reached the unreachable", node: node)

    false
  end

  def visit(node : FileNode)
    file_module = @context.program.file_module(node.filename)

    a_def = Def.new(node.filename)
    a_def.body = node.node
    a_def.owner = @context.program
    a_def.type = @context.program.nil_type
    a_def.vars = file_module.vars

    compiled_def = CompiledDef.new(@context, a_def, a_def.owner, 0)

    declare_local_vars(file_module, compiled_def.local_vars)

    compiler = Compiler.new(@context, compiled_def, top_level: true)
    compiler.compile_def(compiled_def, closure_owner: file_module)

    @context.add_gc_reference(compiled_def)

    {% if Debug::DECOMPILE %}
      puts "=== #{node.filename} ==="
      puts Disassembler.disassemble(@context, compiled_def)
      puts "=== #{node.filename} ==="
    {% end %}

    call compiled_def, node: node
    false
  end

  def visit(node : ASTNode)
    node.raise "BUG: missing interpret for #{node.class}"
  end

  # This is where we define one method per instruction/opcode.
  {% for name, instruction in Crystal::Repl::Instructions %}
    {% operands = instruction[:operands] || [] of Nil %}

    def {{name.id}}(
      {{operands.splat(", ")}}*, node : ASTNode?
    ) : Nil
      node = @node_override || node
      @instructions.nodes[instructions_index] = node if node

      append OpCode::{{ name.id.upcase }}
      {% for operand in operands %}
        append {{operand.var}}
      {% end %}
    end
  {% end %}

  private def request_value(node : ASTNode)
    accept_with_wants_value node, true
  end

  private def discard_value(node : ASTNode)
    accept_with_wants_value node, false
  end

  private def accept_with_wants_value(node : ASTNode, wants_value)
    old_wants_value = @wants_value
    @wants_value = wants_value
    node.accept self
    @wants_value = old_wants_value
  end

  # TODO: block.break shouldn't exist: the type should be merged in target_def
  private def merge_block_break_type(def_type : Type, block : Block)
    block_break_type = block.break.type?
    if block_break_type
      @context.program.type_merge([def_type, block_break_type] of Type) ||
        @context.program.no_return
    else
      def_type
    end
  end

  private def put_true(*, node : ASTNode?)
    put_i64 1_i64, node: node
  end

  private def put_false(*, node : ASTNode?)
    put_i64 0_i64, node: node
  end

  private def put_i8(value : Int8, *, node : ASTNode?)
    put_i64 value.to_i64!, node: node
  end

  private def put_u8(value : UInt8, *, node : ASTNode?)
    put_i64 value.to_u64!.to_i64!, node: node
  end

  private def put_i16(value : Int16, *, node : ASTNode?)
    put_i64 value.to_i64!, node: node
  end

  private def put_u16(value : UInt16, *, node : ASTNode?)
    put_i64 value.to_u64!.to_i64!, node: node
  end

  private def put_i32(value : Int32, *, node : ASTNode?)
    put_i64 value.to_i64!, node: node
  end

  private def put_u32(value : UInt32, *, node : ASTNode?)
    put_i64 value.to_u64!.to_i64!, node: node
  end

  private def put_u64(value : UInt64, *, node : ASTNode?)
    put_i64 value.to_i64!, node: node
  end

  private def put_u128(value : UInt128, *, node : ASTNode?)
    put_i128 value.to_i128!, node: node
  end

  private def put_string(value : String, *, node : ASTNode?)
    cached_string = @context.program.string_pool.get(value)

    # Compute size so that it's also available on the program.
    # TODO: maybe we shouldn't use these strings for the interpreted
    # program and instead put memory for them somehow that would
    # match their actual memory representation (for example the TYPE_ID
    # might not match)
    cached_string.size

    put_i64 cached_string.object_id.unsafe_as(Int64), node: node
  end

  private def put_type(type : Type, *, node : ASTNode?)
    put_i32 type_id(type), node: node
  end

  private def put_def(a_def : Def)
  end

  private def put_self(*, node : ASTNode)
    closured_self = lookup_closured_var?("self")
    if closured_self
      read_from_closured_var(closured_self, node: node)
      return
    end

    if scope.struct?
      if scope.passed_by_value?
        get_local 0, sizeof(Pointer(UInt8)), node: node
      else
        get_local 0, aligned_sizeof_type(scope), node: node
      end
    else
      get_local 0, sizeof(Pointer(UInt8)), node: node
    end
  end

  private def pointer_add_constant(bytes : Int32, *, node : ASTNode?)
    put_i32 bytes, node: node
    pointer_add 1, node: node
  end

  private def append(op_code : OpCode)
    append op_code.value
  end

  private def append(a_def : CompiledDef)
    append(a_def.object_id.unsafe_as(Int64))
  end

  private def append(a_block : CompiledBlock)
    append(a_block.object_id.unsafe_as(Int64))
  end

  private def append(lib_function : LibFunction)
    append(lib_function.object_id.unsafe_as(Int64))
  end

  private def append(ffi_call_interface : FFI::CallInterface)
    append(ffi_call_interface.to_unsafe.unsafe_as(Int64))
  end

  private def append(call : Call)
    append(call.object_id.unsafe_as(Int64))
  end

  private def append(string : String)
    append(string.object_id.unsafe_as(Int64))
  end

  private def append(value : Int128)
    value.unsafe_as(StaticArray(UInt8, 16)).each do |byte|
      append byte
    end
  end

  private def append(value : Int64)
    value.unsafe_as(StaticArray(UInt8, 8)).each do |byte|
      append byte
    end
  end

  private def append(value : Int32)
    value.unsafe_as(StaticArray(UInt8, 4)).each do |byte|
      append byte
    end
  end

  private def append(value : Int16)
    value.unsafe_as(StaticArray(UInt8, 2)).each do |byte|
      append byte
    end
  end

  private def append(value : UInt16)
    value.unsafe_as(StaticArray(UInt8, 2)).each do |byte|
      append byte
    end
  end

  private def append(value : Int8)
    append value.to_u8!
  end

  private def append(value : Symbol)
    value.unsafe_as(StaticArray(UInt8, 4)).each do |byte|
      append byte
    end
  end

  private def append(value : Bool)
    append(value ? 1_u8 : 0_u8)
  end

  private def append(value : UInt8)
    @instructions.instructions << value
  end

  private def append(value : Enum)
    append(value.value)
  end

  # Many times we need to jump or branch to an instruction for which we don't
  # know the offset/index yet.
  # In those cases we generate a jump to zero, but remember where that "zero"
  # is in the bytecode. Once we know where we have to jump, we modify the
  # bytecode to patch it with the correct jump offset.
  private def patch_jump(offset : Int32)
    (@instructions.instructions.to_unsafe + offset).as(Int32*).value = instructions_index
  end

  # After we emit bytecode for a branch or jump, the last four bytes
  # are always for the jump offset.
  private def patch_location
    instructions_index - 4
  end

  private def instructions_index
    @instructions.instructions.size
  end

  private delegate inner_sizeof_type, inner_alignof_type, aligned_sizeof_type,
    inner_instance_sizeof_type, inner_instance_alignof_type, aligned_instance_sizeof_type,
    to: @context

  private def ivar_offset(type : Type, name : String) : Int32
    if type.extern_union?
      0
    else
      @context.ivar_offset(type, name)
    end
  end

  private def type_id(type : Type)
    @context.type_id(type)
  end

  private def in_multidispatch?
    a_def = @def
    return false unless a_def

    first_arg = a_def.args.first?
    return false unless first_arg

    first_arg.name == "self"
  end

  private macro nop
  end

  private def with_node_override(node_override : ASTNode, &)
    old_node_override = @node_override
    @node_override = node_override
    value = yield
    @node_override = old_node_override
    value
  end
end
