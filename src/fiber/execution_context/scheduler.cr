module Fiber::ExecutionContext
  # :nodoc:
  module Scheduler
    @[AlwaysInline]
    def self.current : Scheduler
      Thread.current.scheduler
    end

    protected abstract def thread : Thread
    protected abstract def execution_context : ExecutionContext

    # Instantiates a fiber and enqueues it into the scheduler's local queue.
    def spawn(*, name : String? = nil, &block : ->) : Fiber
      fiber = Fiber.new(name, execution_context, &block)
      enqueue(fiber)
      fiber
    end

    # Legacy support for the *same_thread* argument. Each execution context may
    # decide to support it or not (e.g. a single threaded context can accept it).
    abstract def spawn(*, name : String? = nil, same_thread : Bool, &block : ->) : Fiber

    # Suspends the current fiber and resumes *fiber* instead.
    # The current fiber will never be resumed; you're responsible to reenqueue it.
    #
    # Unsafe. Must only be called on `ExecutionContext.current`. Prefer
    # `ExecutionContext.enqueue` instead.
    protected abstract def enqueue(fiber : Fiber) : Nil

    # Suspends the execution of the current fiber and resumes the next runnable
    # fiber.
    #
    # Unsafe. Must only be called on `ExecutionContext.current`. Prefer
    # `ExecutionContext.reschedule` instead.
    protected abstract def reschedule : Nil

    # Suspends the execution of the current fiber and resumes *fiber*.
    #
    # The current fiber will never be resumed; you're responsible to reenqueue
    # it.
    #
    # Unsafe. Must only be called on `ExecutionContext.current`. Prefer
    # `ExecutionContext.resume` instead.
    protected abstract def resume(fiber : Fiber) : Nil

    # Switches the thread from running the current fiber to run *fiber* instead.
    #
    # Handles thread safety around fiber stacks by locking the GC, so it won't
    # start a GC collection while we're switching context.
    #
    # Unsafe. Must only be called by the current scheduler. The caller must
    # ensure that the fiber indeed belongs to the current execution context and
    # that the fiber can indeed be resumed.
    #
    # WARNING: after switching context you can't trust *self* anymore (it is the
    # scheduler that resumed *fiber* which may not be the one that suspended
    # *fiber*) or instance variables; local variables however are the ones from
    # before swapping context.
    protected def swapcontext(fiber : Fiber) : Nil
      current_fiber = thread.current_fiber

      GC.lock_read
      thread.current_fiber = fiber
      Fiber.swapcontext(pointerof(current_fiber.@context), pointerof(fiber.@context))
      GC.unlock_read
    end

    # Returns the current status of the scheduler. For example `"running"`,
    # `"event-loop"` or `"parked"`.
    abstract def status : String
  end
end
