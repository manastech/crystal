require "./global_queue"
require "./multi_threaded/scheduler"

module Fiber::ExecutionContext
  # MT scheduler.
  #
  # Owns multiple threads and starts a scheduler in each one. The number of
  # threads is dynamic. Setting the minimum and maximum to the same value will
  # start a fixed number of threads.
  #
  # Fully concurrent, fully parallel: fibers running in this context can be
  # resumed by any thread in the context; fibers can run concurrently and in
  # parallel to each other, in addition to running in parallel to every other
  # fibers running in other contexts.
  class MultiThreaded
    include ExecutionContext

    getter name : String

    @mutex : Thread::Mutex
    @condition : Thread::ConditionVariable
    protected getter global_queue : GlobalQueue

    getter stack_pool : Fiber::StackPool = Fiber::StackPool.new
    getter event_loop : Crystal::EventLoop = Crystal::EventLoop.create
    @event_loop_lock = Atomic(Bool).new(false)

    @parked = Atomic(Int32).new(0)
    @spinning = Atomic(Int32).new(0)

    # :nodoc:
    protected def self.default(size : Int32) : self
      new("DEFAULT", 1..size, hijack: true)
    end

    # Starts a context with a maximum number of threads. Threads aren't started
    # right away, but will be started as needed to increase parallelism up to
    # the configured maximum.
    def self.new(name : String, size : Int32) : self
      new(name, 0..size, hijack: false)
    end

    # Starts a context with a maximum number of threads. Threads aren't started
    # right away, but will be started as needed to increase parallelism up to
    # the configured maximum.
    def self.new(name : String, size : Range(Nil, Int32)) : self
      new(name, 0..size.end, hijack: false)
    end

    # Starts a context with a minimum and a maximum number of threads. The
    # minimum number of threads will be started right away, then threads will be
    # started as needed to increase parallelism up to the configured maximum.
    def self.new(name : String, size : Range(Int32, Int32)) : self
      new(name, size, hijack: false)
    end

    protected def initialize(@name : String, @size : Range(Int32, Int32), hijack : Bool)
      raise ArgumentError.new("#{self.class.name} needs at least one thread") if @size.end < 1

      @mutex = Thread::Mutex.new
      @condition = Thread::ConditionVariable.new

      @global_queue = GlobalQueue.new(@mutex)
      @schedulers = Array(Scheduler).new(@size.end)
      @threads = Array(Thread).new(@size.end)

      @rng = Random::PCG32.new

      start_schedulers(hijack)
      start_initial_threads(hijack)

      ExecutionContext.execution_contexts.push(self)
    end

    # The number of threads that have been started.
    def size : Int32
      @threads.size
    end

    # The maximum number of threads that can be started.
    def capacity : Int32
      @size.end
    end

    def stack_pool? : Fiber::StackPool?
      @stack_pool
    end

    private def start_schedulers(hijack)
      @size.end.times do |index|
        @schedulers << Scheduler.new(self, "#{@name}-#{index}")
      end
    end

    private def start_initial_threads(hijack)
      @size.begin.times do |index|
        scheduler = @schedulers[index]

        if hijack && index == 0
          @threads << hijack_current_thread(scheduler, index)
        else
          @threads << start_thread(scheduler, index)
        end
      end
    end

    # Attaches *scheduler* to the current `Thread`, usually the executable's
    # main thread. Starts a `Fiber` to run the scheduler loop.
    private def hijack_current_thread(scheduler, index) : Thread
      thread = Thread.current
      thread.internal_name = scheduler.name
      thread.execution_context = self
      thread.scheduler = scheduler

      scheduler.thread = thread
      scheduler.main_fiber = Fiber.new("#{scheduler.name}:loop", self) do
        scheduler.run_loop
      end

      thread
    end

    # Start a new `Thread` and attaches *scheduler*. Runs the scheduler loop
    # directly in the thread's main `Fiber`.
    private def start_thread(scheduler, index) : Thread
      Thread.new(name: scheduler.name) do |thread|
        thread.execution_context = self
        thread.scheduler = scheduler

        scheduler.thread = thread
        scheduler.main_fiber = thread.main_fiber
        scheduler.main_fiber.name = "#{scheduler.name}:loop"
        scheduler.run_loop
      end
    end

    def spawn(*, name : String? = nil, same_thread : Bool, &block : ->) : Fiber
      raise ArgumentError.new("#{self.class.name}#spawn doesn't support same_thread:true") if same_thread
      self.spawn(name: name, &block)
    end

    def enqueue(fiber : Fiber) : Nil
      if ExecutionContext.current == self
        # local enqueue: push to local queue of current scheduler
        ExecutionContext::Scheduler.current.enqueue(fiber)
      else
        # cross context: push to global queue
        Crystal.trace :sched, "enqueue", fiber: fiber, to_context: self
        @global_queue.push(fiber)
        wake_scheduler
      end
    end

    # Pick a scheduler at random then iterate all schedulers to try to steal
    # fibers from.
    protected def steal(& : Scheduler ->) : Nil
      return if size == 1

      i = @rng.next_int
      n = @schedulers.size

      n.times do |j|
        if scheduler = @schedulers[(i &+ j) % n]?
          yield scheduler
        end
      end
    end

    protected def park_thread(&) : Fiber?
      @mutex.synchronize do
        # avoid races by checking queues again
        if fiber = yield
          return fiber
        end

        Crystal.trace :sched, "park"
        @parked.add(1, :acquire_release)

        @condition.wait(@mutex)

        # we don't decrement @parked because #wake_scheduler did
        Crystal.trace :sched, "wakeup"
      end

      nil
    end

    # This method always runs in parallel!
    #
    # This can be called from any thread in the context but can also be called
    # from external execution contexts, in which case the context may have its
    # last thread about to park itself, and we must prevent the last thread from
    # parking when there is a parallel cross context enqueue!
    #
    # OPTIMIZE: instead of blindly spending time (blocking progress on the
    # current thread) to unpark a thread / start a new thread we could move the
    # responsibility to an external OBSERVER to increase parallelism in a MT
    # context when it detects pending work.
    protected def wake_scheduler : Nil
      # another thread is spinning: nothing to do (it shall notice the enqueue)
      if @spinning.get(:relaxed) > 0
        return
      end

      # interrupt a thread waiting on the event loop
      if @event_loop_lock.get(:relaxed)
        @event_loop.interrupt
        return
      end

      # we can check @parked without locking the mutex because we can't push to
      # the global queue _and_ park the thread at the same time, so either the
      # thread is already parked (and we must awake it) or it noticed (or will
      # notice) the fiber in the global queue;
      #
      # we still rely on an atomic to make sure the actual value is visible by
      # the current thread
      if @parked.get(:acquire) > 0
        @mutex.synchronize do
          # avoid race conditions
          return if @parked.get(:relaxed) == 0
          return if @spinning.get(:relaxed) > 0

          # increase the number of spinning threads _now_ to avoid multiple
          # threads from trying to wakeup multiple threads at the same time
          #
          # we must also decrement the number of parked threads because another
          # thread could lock the mutex and increment @spinning again before the
          # signaled thread is resumed
          spinning = @spinning.add(1, :acquire_release)
          parked = @parked.sub(1, :acquire_release)

          @condition.signal
        end
        return
      end

      # check if we can start another thread; no need for atomics, the values
      # shall be rather stable over time and we check them again inside the
      # mutex
      return if @threads.size == @size.end

      @mutex.synchronize do
        index = @threads.size
        return if index == @size.end # check again

        @threads << start_thread(@schedulers[index], index)
      end
    end

    # Only one thread is allowed to run the event loop. Yields then returns true
    # if the lock was acquired, otherwise returns false immediately.
    protected def lock_evloop?(&) : Bool
      if @event_loop_lock.swap(true, :acquire) == false
        begin
          yield
        ensure
          @event_loop_lock.set(false, :release)
        end
        true
      else
        false
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
  end
end
