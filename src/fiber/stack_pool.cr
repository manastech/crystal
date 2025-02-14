require "crystal/system/fiber"

class Fiber
  # :nodoc:
  class StackPool
    STACK_SIZE = 8 * 1024 * 1024

    {% if flag?(:execution_context) %}
      # must explicitly declare the variable because of the macro in #initialize
      @lock = uninitialized Crystal::SpinLock
    {% end %}

    # If *protect* is true, guards all top pages (pages with the lowest address
    # values) in the allocated stacks; accessing them triggers an error
    # condition, allowing stack overflows on non-main fibers to be detected.
    #
    # Interpreter stacks grow upwards (pushing values increases the stack
    # pointer value) rather than downwards, so *protect* must be false.
    def initialize(@protect : Bool = true)
      @deque = Deque(Stack).new

      {% if flag?(:execution_context) %}
        @lock = Crystal::SpinLock.new
      {% end %}
    end

    def finalize
      @deque.each do |stack|
        Crystal::System::Fiber.free_stack(stack.pointer, STACK_SIZE)
      end
    end

    # Removes and frees at most *count* stacks from the top of the pool,
    # returning memory to the operating system.
    def collect(count = lazy_size // 2) : Nil
      count.times do
        if stack = shift?
          Crystal::System::Fiber.free_stack(stack.pointer, STACK_SIZE)
        else
          return
        end
      end
    end

    def collect_loop(every = 5.seconds) : Nil
      loop do
        sleep every
        collect
      end
    end

    # Removes a stack from the bottom of the pool, or allocates a new one.
    def checkout : Stack
      if stack = pop?
        Crystal::System::Fiber.reset_stack(stack.pointer, STACK_SIZE, @protect)
        stack
      else
        pointer = Crystal::System::Fiber.allocate_stack(STACK_SIZE, @protect)
        Stack.new(pointer, pointer + STACK_SIZE, reusable: true)
      end
    end

    # Appends a stack to the bottom of the pool.
    def release(stack : Stack) : Nil
      return unless stack.reusable?

      {% if flag?(:execution_context) %}
        @lock.sync { @deque.push(stack) }
      {% else %}
        @deque.push(stack)
      {% end %}
    end

    # Returns the approximated size of the pool. It may be equal or slightly
    # bigger or smaller than the actual size.
    def lazy_size : Int32
      @deque.size
    end

    private def shift?
      {% if flag?(:execution_context) %}
        @lock.sync { @deque.shift? } unless @deque.empty?
      {% else %}
        @deque.shift?
      {% end %}
    end

    private def pop?
      {% if flag?(:execution_context) %}
        if (stack = Thread.current.dead_fiber_stack?) && stack.reusable?
          stack
        else
          @lock.sync { @deque.pop? } unless @deque.empty?
        end
      {% else %}
        @deque.pop?
      {% end %}
    end
  end
end
