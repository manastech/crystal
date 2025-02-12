{% skip_file if flag?(:execution_context) %}

require "crystal/event_loop"
require "crystal/system/print_error"
require "fiber"
require "fiber/stack_pool"
require "crystal/system/thread"

# :nodoc:
#
# Schedulers are tied to a thread, and must only ever be accessed from within
# this thread.
#
# Only the class methods are public and safe to use. Instance methods are
# protected and must never be called directly.
class Crystal::Scheduler
  @event_loop = Crystal::EventLoop.create
  @stack_pool = Fiber::StackPool.new

  def self.stack_pool : Fiber::StackPool
    Thread.current.scheduler.@stack_pool
  end

  def self.event_loop
    Thread.current.scheduler.@event_loop
  end

  def self.event_loop?
    if scheduler = Thread.current?.try(&.scheduler?)
      scheduler.@event_loop
    end
  end

  def self.enqueue(fiber : Fiber) : Nil
    Crystal.trace :sched, "enqueue", fiber: fiber do
      thread = Thread.current
      scheduler = thread.scheduler

      {% if flag?(:preview_mt) %}
        th = fiber.get_current_thread
        th ||= fiber.set_current_thread(scheduler.find_target_thread)

        if th == thread
          scheduler.enqueue(fiber)
        else
          th.scheduler.send_fiber(fiber)
        end
      {% else %}
        scheduler.enqueue(fiber)
      {% end %}
    end
  end

  def self.enqueue(fibers : Enumerable(Fiber)) : Nil
    fibers.each do |fiber|
      enqueue(fiber)
    end
  end

  def self.reschedule : Nil
    Crystal.trace :sched, "reschedule"
    Thread.current.scheduler.reschedule
  end

  def self.resume(fiber : Fiber) : Nil
    validate_running_thread(fiber)
    Thread.current.scheduler.resume(fiber)
  end

  def self.sleep(time : Time::Span) : Nil
    Thread.current.scheduler.sleep(time)
  end

  def self.yield : Nil
    Crystal.trace :sched, "yield"

    # TODO: Fiber switching and libevent for wasm32
    {% unless flag?(:wasm32) %}
      Thread.current.scheduler.sleep(0.seconds)
    {% end %}
  end

  def self.yield(fiber : Fiber) : Nil
    validate_running_thread(fiber)
    Thread.current.scheduler.yield(fiber)
  end

  private def self.validate_running_thread(fiber : Fiber) : Nil
    {% if flag?(:preview_mt) %}
      if th = fiber.get_current_thread
        unless th == Thread.current
          raise "BUG: tried to manually resume #{fiber} on #{Thread.current} instead of #{th}"
        end
      else
        fiber.set_current_thread
      end
    {% end %}
  end

  @main : Fiber
  @lock = Crystal::SpinLock.new
  @sleeping = false

  # :nodoc:
  def initialize(@thread : Thread)
    @main = thread.main_fiber
    {% if flag?(:preview_mt) %} @main.set_current_thread(thread) {% end %}
    @runnables = Deque(Fiber).new
  end

  protected def enqueue(fiber : Fiber) : Nil
    @lock.sync { @runnables << fiber }
  end

  protected def enqueue(fibers : Enumerable(Fiber)) : Nil
    @lock.sync { @runnables.concat fibers }
  end

  protected def resume(fiber : Fiber) : Nil
    Crystal.trace :sched, "resume", fiber: fiber
    validate_resumable(fiber)

    {% if flag?(:preview_mt) %}
      GC.lock_read
    {% elsif flag?(:interpreted) %}
      # No need to change the stack bottom!
    {% else %}
      GC.set_stackbottom(fiber.@stack.bottom)
    {% end %}

    current, @thread.current_fiber = @thread.current_fiber, fiber
    Fiber.swapcontext(pointerof(current.@context), pointerof(fiber.@context))

    {% if flag?(:preview_mt) %}
      GC.unlock_read
    {% end %}
  end

  private def validate_resumable(fiber)
    return if fiber.resumable?

    if fiber.dead?
      fatal_resume_error(fiber, "tried to resume a dead fiber")
    else
      fatal_resume_error(fiber, "can't resume a running fiber")
    end
  end

  private def fatal_resume_error(fiber, message)
    Crystal::System.print_error "\nFATAL: %s: %s\n", message, fiber.to_s
    caller.each { |line| Crystal::System.print_error "  from %s\n", line }
    exit 1
  end

  protected def reschedule : Nil
    loop do
      if runnable = @lock.sync { @runnables.shift? }
        resume(runnable) unless runnable == @thread.current_fiber
        break
      else
        Crystal.trace :sched, "event_loop" do
          @event_loop.run(blocking: true)
        end
      end
    end
  end

  protected def sleep(time : Time::Span) : Nil
    @thread.current_fiber.resume_event.add(time)
    reschedule
  end

  protected def yield(fiber : Fiber) : Nil
    @thread.current_fiber.resume_event.add(0.seconds)
    resume(fiber)
  end

  {% if flag?(:preview_mt) %}
    private getter! worker_fiber : Fiber
    @rr_target = 0

    protected def find_target_thread
      if workers = @@workers
        @rr_target &+= 1
        workers[@rr_target % workers.size]
      else
        Thread.current
      end
    end

    def run_loop
      @worker_fiber = Fiber.current

      spawn_stack_pool_collector

      loop do
        @lock.lock

        if runnable = @runnables.shift?
          @runnables << worker_fiber
          @lock.unlock
          resume(runnable)
        else
          @sleeping = true
          @lock.unlock
          Crystal.trace :sched, "mt:sleeping"
          Crystal.trace(:sched, "mt:slept") { ::Fiber.suspend }
        end
      end
    end

    def send_fiber(fiber : Fiber)
      @lock.lock
      @runnables << fiber

      if @sleeping
        @sleeping = false
        @runnables << worker_fiber
        @event_loop.interrupt
      end
      @lock.unlock
    end

    def self.init : Nil
      count = worker_count
      pending = Atomic(Int32).new(count - 1)
      @@workers = Array(Thread).new(count) do |i|
        if i == 0
          worker_loop = Fiber.new(name: "worker-loop") { Thread.current.scheduler.run_loop }
          worker_loop.set_current_thread
          Thread.current.scheduler.enqueue worker_loop
          Thread.current
        else
          Thread.new(name: "CRYSTAL-MT-#{i}") do
            scheduler = Thread.current.scheduler
            pending.sub(1)
            scheduler.run_loop
          end
        end
      end

      # Wait for all worker threads to be fully ready to be used
      while pending.get > 0
        Fiber.yield
      end
    end

    private def self.worker_count
      env_workers = ENV["CRYSTAL_WORKERS"]?

      if env_workers && !env_workers.empty?
        workers = env_workers.to_i?
        if !workers || workers < 1
          Crystal::System.print_error "FATAL: Invalid value for CRYSTAL_WORKERS: %s\n", env_workers
          exit 1
        end

        workers
      else
        # TODO: default worker count, currently hardcoded to 4 that seems to be something
        # that is beneficial for many scenarios without adding too much contention.
        # In the future we could use the number of cores or something associated to it.
        4
      end
    end
  {% else %}
    def self.init : Nil
      {% unless flag?(:interpreted) %}
        Thread.current.scheduler.spawn_stack_pool_collector
      {% end %}
    end
  {% end %}

  # Background loop to cleanup unused fiber stacks.
  def spawn_stack_pool_collector
    fiber = Fiber.new(name: "stack-pool-collector", &->@stack_pool.collect_loop)
    {% if flag?(:preview_mt) %} fiber.set_current_thread {% end %}
    enqueue(fiber)
  end
end
