require "./global_queue"
require "./runnables"
require "./scheduler"

module Fiber::ExecutionContext
  # ST scheduler. Owns a single thread.
  #
  # Fully concurrent, limited parallelism: concurrency is limited to that
  # thread; fibers running in this context will thus never run in parallel to
  # each other, but they may still run in parallel to fibers running in other
  # contexts (thus on another thread).
  class SingleThreaded
    include ExecutionContext
    include ExecutionContext::Scheduler

    getter name : String

    protected getter thread : Thread
    @main_fiber : Fiber

    @mutex : Thread::Mutex
    @global_queue : GlobalQueue
    @runnables : Runnables(256)

    getter stack_pool : Fiber::StackPool = Fiber::StackPool.new
    getter event_loop : Crystal::EventLoop = Crystal::EventLoop.create

    @waiting = Atomic(Bool).new(false)
    @parked = Atomic(Bool).new(false)
    @spinning = Atomic(Bool).new(false)
    @tick : Int32 = 0

    # :nodoc:
    protected def self.default : self
      new("DEFAULT", hijack: true)
    end

    def self.new(name : String) : self
      new(name, hijack: false)
    end

    protected def initialize(@name : String, hijack : Bool)
      @mutex = Thread::Mutex.new
      @global_queue = GlobalQueue.new(@mutex)
      @runnables = Runnables(256).new(@global_queue)

      @thread = uninitialized Thread
      @main_fiber = uninitialized Fiber
      @thread = hijack ? hijack_current_thread : start_thread

      ExecutionContext.execution_contexts.push(self)
    end

    # :nodoc:
    def execution_context : self
      self
    end

    def stack_pool? : Fiber::StackPool?
      @stack_pool
    end

    # Initializes the scheduler on the current thread (usually the executable's
    # main thread).
    private def hijack_current_thread : Thread
      thread = Thread.current
      thread.internal_name = @name
      thread.execution_context = self
      thread.scheduler = self
      @main_fiber = Fiber.new("#{@name}:loop", self) { run_loop }
      thread
    end

    # Creates a new thread to initialize the scheduler.
    private def start_thread : Thread
      Thread.new(name: @name) do |thread|
        thread.execution_context = self
        thread.scheduler = self
        @main_fiber = thread.main_fiber
        @main_fiber.name = "#{@name}:loop"
        run_loop
      end
    end

    # :nodoc:
    def spawn(*, name : String? = nil, same_thread : Bool, &block : ->) : Fiber
      # whatever the value of same_thread: the fibers will always run on the
      # same thread
      self.spawn(name: name, &block)
    end

    def enqueue(fiber : Fiber) : Nil
      if ExecutionContext.current == self
        # local enqueue
        Crystal.trace :sched, "enqueue", fiber: fiber
        @runnables.push(fiber)
      else
        # cross context enqueue
        Crystal.trace :sched, "enqueue", fiber: fiber, to_context: self
        @global_queue.push(fiber)
        wake_scheduler
      end
    end

    # Enqueue a list of fibers in a single operation and returns a fiber to
    # resume immediately.
    #
    # This is called after running the event loop for example.
    private def enqueue_many(list : Fiber::List*) : Fiber?
      if fiber = list.value.pop?
        @runnables.bulk_push(list) unless list.value.empty?
        fiber
      end
    end

    protected def reschedule : Nil
      Crystal.trace :sched, "reschedule"
      if fiber = quick_dequeue?
        resume fiber unless fiber == @thread.current_fiber
      else
        # nothing to do: switch back to the main loop to spin/park
        resume @main_fiber
      end
    end

    protected def resume(fiber : Fiber) : Nil
      unless fiber.resumable?
        if fiber.dead?
          raise "BUG: tried to resume dead fiber #{fiber} (#{inspect})"
        else
          raise "BUG: can't resume running fiber #{fiber} (#{inspect})"
        end
      end
      swapcontext(fiber)
    end

    @[AlwaysInline]
    private def quick_dequeue? : Fiber?
      # every once in a while: dequeue from global queue to avoid two fibers
      # constantly respawing each other to completely occupy the local queue
      if (@tick &+= 1) % 61 == 0
        if fiber = @global_queue.pop?
          return fiber
        end
      end

      # try local queue
      if fiber = @runnables.shift?
        return fiber
      end

      # try to refill local queue
      if fiber = @global_queue.grab?(@runnables, divisor: 1)
        return fiber
      end

      # run the event loop to see if any event is activable
      list = Fiber::List.new
      @event_loop.run(pointerof(list), blocking: false)
      return enqueue_many(pointerof(list))
    end

    private def run_loop : Nil
      Crystal.trace :sched, "started"

      loop do
        if fiber = find_next_runnable
          spin_stop if @spinning.get(:relaxed)
          resume fiber
        else
          # the event loop enqueued a fiber (or was interrupted) or the
          # scheduler was unparked: go for the next iteration
        end
      rescue exception
        Crystal.print_error_buffered("BUG: %s#run_loop [%s] crashed",
          self.class.name, @name, exception: exception)
      end
    end

    private def find_next_runnable : Fiber?
      find_next_runnable do |fiber|
        return fiber if fiber
      end
    end

    private def find_next_runnable(&) : Nil
      list = Fiber::List.new

      # nothing to do: start spinning
      spinning do
        yield @global_queue.grab?(@runnables, divisor: 1)

        @event_loop.run(pointerof(list), blocking: false)
        yield enqueue_many(pointerof(list))
      end

      # block on the event loop, waiting for pending event(s) to activate
      waiting do
        # there is a time window between stop spinning and start waiting during
        # which another context may have enqueued a fiber, check again before
        # waiting on the event loop to avoid missing a runnable fiber which (may
        # block for a long time):
        yield @global_queue.grab?(@runnables, divisor: 1)

        @event_loop.run(pointerof(list), blocking: true)
        yield enqueue_many(pointerof(list))

        # the event loop was interrupted: restart the loop
        return
      end
    end

    private def spinning(&)
      spin_start

      4.times do |iter|
        spin_backoff(iter) unless iter == 0
        yield
      end

      spin_stop
    end

    private def spin_start : Nil
      @spinning.set(true, :release)
    end

    private def spin_stop : Nil
      @spinning.set(false, :release)
    end

    @[AlwaysInline]
    private def spin_backoff(iter)
      # OPTIMIZE: consider exponential backoff, but beware of latency to notice
      #           cross context enqueues
      Thread.yield
    end

    @[AlwaysInline]
    private def waiting(&)
      @waiting.set(true, :release)
      begin
        yield
      ensure
        @waiting.set(false, :release)
      end
    end

    # This method runs in parallel to the rest of the ST scheduler!
    #
    # This is called from another context _after_ enqueueing into the global
    # queue to try and wakeup the ST thread running in parallel that may be
    # running, spinning or waiting on the event loop.
    private def wake_scheduler : Nil
      if @spinning.get(:acquire)
        return
      end

      if @waiting.get(:acquire)
        @event_loop.interrupt
      end
    end

    @[AlwaysInline]
    def inspect(io : IO) : Nil
      to_s(io)
    end

    def to_s(io : IO) : Nil
      io << "#<" << self.class.name << ":0x"
      object_id.to_s(io, 16)
      io << ' ' << name << '>'
    end

    def status : String
      if @spinning.get(:relaxed)
        "spinning"
      elsif @waiting.get(:relaxed)
        "event-loop"
      else
        "running"
      end
    end
  end
end
