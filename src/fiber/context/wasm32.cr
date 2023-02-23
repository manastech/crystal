{% skip_file unless flag?(:wasm32) %}

# WebAssembly as built by LLVM has 3 stacks:
# - A value stack for low level operations. Wasm is a stack machine. For example: to write data to
#   memory you first push the target address, then the value, then perform the 'store' instruction.
# - A stack with private frames. Each function has access to a stack frame accessed with the local.get
#   and local.set instructions. These frames are private and can't be manipulated outside of the function.
# - A shadow stack in the main memory. It is controlled by a stack_pointer global and grows down. This
#   is not a feature of WebAssembly, just a convention that LLVM uses.
#
# There is a proposal to add stack switching to WebAssembly, but as of this writing it is not standardized
# and isn't implemented by any runtime. See details at https://github.com/WebAssembly/stack-switching.
#
# Here we use an alternative implementation on top of Binaryen's Asyncify pass. It is a static transformation
# on the WebAssembly file that must be performed after the Crystal program is compiled. It rewrites every
# relevant function so that it writes its stack frame to memory and rewinds to the caller, as well as
# recovering the stack from memory. It is all controlled by a global state variable.
# Please read more details at https://github.com/WebAssembly/binaryen/blob/main/src/passes/Asyncify.cpp.
#
# Stack switching is accomplished by the cooperation between two functions: Fiber.swapcontext and
# Fiber.wrap_with_fibers. Before they are explained, the memory layout must be understood:
#
# +--------+--------+------------------+----------------
# | Unused | Data   | Main stack       | Heap ...
# +--------+--------+------------------+----------------
# |        |        |                  |
# 0    __data_start |              __heap_base
#              __data_end        __stack_pointer
#
# The first 1024 bytes of memory are unused (but they are usable, including the address 0!). Follows
# the static data like constant strings. This would be read only data on other platforms, but here it
# is writable. The special symbols `__data_start` and `__data_end` are generated by LLVM to mark this
# region. Then follows the main stack. A `__heap_base` symbol points to the bottom of this stack. The
# global `__stack_pointer` starts at this position and is moved by the program during execution.
# After that, the rest of the memory follows, used mainly by malloc. It is important to note that
# during execution everything is just memory, there is no real difference between those sections.
#
# For our implementation of stack switching we manage this memory layout on every stack:
#
# +--------+---------------------------+------------------------+
# | Header | Asyncify buffer =>        |               <= Stack |
# +--------+---------------------------+------------------------+
#
# The header stores 4 pointers as metadata:
#  - [0] => A function pointer to fiber_main
#  - [1] => A pointer to the Fiber instance
#  - [2] => The current position on the asyncify buffer (starts after the header, grows up)
#  - [4] => The end position on the asyncify buffer (the current stack top)
# On the main stack all of them are guaranteed to start null.
#
# Stack switching should happens as follows:
#
# 1. CrystalMain should call Fiber.wrap_with_fibers, passing a proc to the main function.
# 2. Fiber.wrap_with_fibers will call this proc immediately.
# 3. At some point a new Fiber will be created and Fiber.swapcontext will be called. It will:
#    a. store the new context at Fiber.@@next_context.
#    b. store the current stack_pointer global on context.stack_top.
#    c. update the current position of the asyncify buffer to be just after the header
#    d. update the end position  of the asyncify buffer to be the current stack top
#    e. mark Fiber.is_manipulating_stack_with_asyncify = true
#    f. begin stack unwinding with LibAsyncify.start_unwind() and returns.
# 4. As a consequence of the Asyncify transformation, all functions behave differently and instead
#    of executing, they will write their local stack to the Asyncify buffer and return.
# 5. At some point execution will arrive at Fiber.wrap_with_fibers again. We know that we are
#    unwinding as Fiber.is_manipulating_stack_with_asyncify is marked. This means we have to either
#    start a new fiber or rewind into a previously running fiber. If there is a asyncify buffer, then
#    setup the rewinding process. Then call into the fiber main function. If it's null, then this is
#    the main fiber, just call the original block.

lib LibC
  $__data_end : UInt8
end

@[Link(wasm_import_module: "asyncify")]
lib LibAsyncify
  struct Data
    current_location : Void*
    end_location : Void*
  end

  fun start_unwind(data : Data*)
  fun stop_unwind
  fun start_rewind(data : Data*)
  fun stop_rewind
end

private def get_stack_pointer
  stack_pointer = uninitialized Void*
  asm("
    .globaltype __stack_pointer, i32
    global.get __stack_pointer
    local.set $0
  " : "=r"(stack_pointer))

  stack_pointer
end

private def set_stack_pointer(stack_pointer)
  asm("
    .globaltype __stack_pointer, i32
    local.get $0
    global.set __stack_pointer
  " :: "r"(stack_pointer))
end

private def get_main_stack_low
  pointerof(LibC.__data_end).as(Void*)
end

class Fiber
  # :nodoc:
  class_property next_context : Context*?

  # :nodoc:
  class_property is_manipulating_stack_with_asyncify = false

  struct Context
    property stack_low : Void* = get_main_stack_low
  end

  # :nodoc:
  def makecontext(stack_ptr : Void**, fiber_main : Fiber ->)
    @context.stack_top = stack_ptr.as(Void*)
    @context.stack_low = (stack_ptr.as(UInt8*) - StackPool::STACK_SIZE + 32).as(Void*)
    @context.resumable = 1

    ctx_data_ptr = @context.stack_low.as(Void**)
    ctx_data_ptr[0] = fiber_main.pointer
    ctx_data_ptr[1] = self.as(Void*)
    ctx_data_ptr[2] = Pointer(Void).null
    ctx_data_ptr[3] = Pointer(Void).null
  end

  # :nodoc:
  @[NoInline]
  def self.swapcontext(current_context, new_context) : Nil
    if Fiber.is_manipulating_stack_with_asyncify
      Fiber.is_manipulating_stack_with_asyncify = false
      LibAsyncify.stop_rewind
      return
    end

    new_context.value.resumable = 0
    current_context.value.resumable = 1
    Fiber.next_context = new_context

    current_context.value.stack_top = get_stack_pointer

    ctx_data_ptr = current_context.value.stack_low.as(Void**)
    ctx_data_ptr[2] = (ctx_data_ptr + 4).as(Void*)
    ctx_data_ptr[3] = current_context.value.stack_top

    asyncify_data_ptr = (ctx_data_ptr + 2).as(LibAsyncify::Data*)
    Fiber.is_manipulating_stack_with_asyncify = true
    LibAsyncify.start_unwind(asyncify_data_ptr)
  end

  # :nodoc:
  @[NoInline]
  def self.wrap_with_fibers(&block : -> T) : T forall T
    result = block.call

    while Fiber.is_manipulating_stack_with_asyncify
      Fiber.is_manipulating_stack_with_asyncify = false
      LibAsyncify.stop_unwind

      next_context = Fiber.next_context.not_nil!
      ctx_data_ptr = next_context.value.stack_low.as(Void**)

      set_stack_pointer next_context.value.stack_top

      asyncify_data_ptr = (ctx_data_ptr + 2).as(LibAsyncify::Data*)
      unless asyncify_data_ptr.value.current_location == Pointer(Void).null
        Fiber.is_manipulating_stack_with_asyncify = true
        LibAsyncify.start_rewind(asyncify_data_ptr)
      end

      if ctx_data_ptr[0].null?
        result = block.call
      else
        fiber_main = Proc(Fiber, Void).new(ctx_data_ptr[0], Pointer(Void).null)
        fiber = ctx_data_ptr[1].as(Fiber)
        fiber_main.call(fiber)
      end
    end

    return result
  end
end
