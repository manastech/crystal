require "./scheduler"
require "../list"

module Fiber::ExecutionContext
  # ST scheduler. Owns a single thread running a single fiber.
  #
  # Concurrency is disabled: calls to `#spawn` will create fibers in another
  # execution context (defaults to `ExecutionContext.default`). Any calls that
  # result in waiting (e.g. sleep, or socket read/write) will block the thread
  # since there are no other fibers to switch to.
  #
  # The fiber will still run in parallel to other fibers running in other
  # execution contexts.
  #
  # Isolated fibers can still communicate with other fibers running in other
  # execution contexts using standard means, such as `Channel(T)`, `WaitGroup`
  # or `Mutex`. They can also execute IO operations or sleep just like any other
  # fiber.
  #
  # Example:
  #
  # ```
  # ExecutionContext::Isolated.new("Gtk") { Gtk.main }
  # ```
  class Isolated
    include ExecutionContext
    include ExecutionContext::Scheduler

    getter name : String

    @mutex : Thread::Mutex
    protected getter thread : Thread
    @main_fiber : Fiber

    getter event_loop : Crystal::EventLoop = Crystal::EventLoop.create

    getter? running : Bool = true
    @enqueued = false
    @waiting = false

    def initialize(@name : String, @spawn_context = ExecutionContext.default, &@func : ->)
      @mutex = Thread::Mutex.new
      @thread = uninitialized Thread
      @main_fiber = uninitialized Fiber
      @thread = start_thread
      ExecutionContext.execution_contexts.push(self)
    end

    private def start_thread : Thread
      Thread.new(name: @name) do |thread|
        @thread = thread
        thread.execution_context = self
        thread.scheduler = self
        thread.main_fiber.name = @name
        @main_fiber = thread.main_fiber
        run
      end
    end

    # :nodoc:
    @[AlwaysInline]
    def execution_context : Isolated
      self
    end

    # :nodoc:
    def stack_pool : Fiber::StackPool
      raise RuntimeError.new("No stack pool for isolated contexts")
    end

    # :nodoc:
    def stack_pool? : Fiber::StackPool?
    end

    @[AlwaysInline]
    def spawn(*, name : String? = nil, &block : ->) : Fiber
      @spawn_context.spawn(name: name, &block)
    end

    # :nodoc:
    @[AlwaysInline]
    def spawn(*, name : String? = nil, same_thread : Bool, &block : ->) : Fiber
      raise ArgumentError.new("#{self.class.name}#spawn doesn't support same_thread:true") if same_thread
      @spawn_context.spawn(name: name, &block)
    end

    def enqueue(fiber : Fiber) : Nil
      Crystal.trace :sched, "enqueue", fiber: fiber, context: self

      unless fiber == @main_fiber
        raise RuntimeError.new("Concurrency is disabled in isolated contexts")
      end

      @mutex.synchronize do
        @enqueued = true

        if @waiting
          # wake up the blocked thread
          @waiting = false
          @event_loop.interrupt
        else
          # race: enqueued before the other thread started waiting
        end
      end
    end

    protected def reschedule : Nil
      Crystal.trace :sched, "reschedule"

      loop do
        @mutex.synchronize do
          # race: another thread already re-enqueued the fiber
          if @enqueued
            Crystal.trace :sched, "resume"
            @enqueued = false
            @waiting = false
            return
          end
          @waiting = true
        end

        # wait on the event loop
        list = Fiber::List.new
        @event_loop.run(pointerof(list), blocking: true)

        if fiber = list.pop?
          break if fiber == @main_fiber && list.empty?
          raise RuntimeError.new("Concurrency is disabled in isolated contexts")
        end

        # the evloop got interrupted: restart
      end

      # cleanup
      @mutex.synchronize do
        @waiting = false
        @enqueued = false
      end

      Crystal.trace :sched, "resume"
    end

    protected def resume(fiber : Fiber) : Nil
      # in theory we could resume @main_fiber, but this method may only be
      # called from the current execution context, which is @main_fiber; it
      # doesn't make any sense for a fiber to resume itself
      raise RuntimeError.new("Can't resume #{fiber} in #{self}")
    end

    private def run
      Crystal.trace :sched, "started"
      @func.call
    ensure
      @running = false
      ExecutionContext.execution_contexts.delete(self)
    end

    @[AlwaysInline]
    def join : Nil
      @thread.join
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
      if @waiting
        "event-loop"
      elsif @running
        "running"
      else
        "shutdown"
      end
    end
  end
end
