# :nodoc:
module Crystal::System::Thread
  # alias Handle

  # def self.init : Nil

  # def self.new_handle(thread_obj : ::Thread) : Handle

  # def self.current_handle : Handle

  # def self.yield_current : Nil

  # def self.current_thread : ::Thread

  # def self.current_thread? : ::Thread?

  # def self.current_thread=(thread : ::Thread)

  # def self.sleep(time : ::Time::Span) : Nil

  # private def system_join : Exception?

  # private def system_close

  # private def stack_address : Void*

  # private def system_name=(String) : String

  # def self.init_suspend_resume : Nil

  # private def system_suspend : Nil

  # private def system_wait_suspended : Nil

  # private def system_resume : Nil
end

{% if flag?(:wasi) %}
  require "./wasi/thread"
{% elsif flag?(:unix) %}
  require "./unix/pthread"
{% elsif flag?(:win32) %}
  require "./win32/thread"
{% else %}
  {% raise "Thread not supported" %}
{% end %}

# :nodoc:
class Thread
  include Crystal::System::Thread

  # all thread objects, so the GC can see them (it doesn't scan thread locals)
  @@threads = uninitialized Thread::LinkedList(Thread)

  protected def self.threads : Thread::LinkedList(Thread)
    @@threads
  end

  def self.init : Nil
    @@threads = Thread::LinkedList(Thread).new
    Crystal::System::Thread.init
  end

  @system_handle : Crystal::System::Thread::Handle
  @exception : Exception?
  @detached = Atomic::Flag.new

  # Returns the Fiber representing the thread's main stack.
  getter! main_fiber : Fiber

  # Returns the Fiber currently running on the thread.
  property! current_fiber : Fiber

  # :nodoc:
  property next : Thread?

  # :nodoc:
  property previous : Thread?

  getter name : String?

  {% if flag?(:execution_context) %}
    # :nodoc:
    getter! execution_context : Fiber::ExecutionContext

    # :nodoc:
    property! scheduler : Fiber::ExecutionContext::Scheduler

    # :nodoc:
    def execution_context=(@execution_context : Fiber::ExecutionContext) : Fiber::ExecutionContext
      main_fiber.execution_context = execution_context
    end

    # When a fiber terminates we can't release its stack until we swap context
    # to another fiber. We can't free/unmap nor push it to a shared stack pool,
    # that would result in a segfault.
    @dead_fiber_stack : Fiber::Stack?

    # :nodoc:
    def dying_fiber(fiber : Fiber) : Fiber::Stack?
      stack = @dead_fiber_stack
      @dead_fiber_stack = fiber.@stack
      stack
    end

    # :nodoc:
    def dead_fiber_stack? : Fiber::Stack?
      if stack = @dead_fiber_stack
        @dead_fiber_stack = nil
        stack
      end
    end
  {% else %}
    # :nodoc:
    getter scheduler : Crystal::Scheduler { Crystal::Scheduler.new(self) }

    # :nodoc:
    def scheduler? : ::Crystal::Scheduler?
      @scheduler
    end
  {% end %}

  def self.unsafe_each(&)
    # nothing to iterate when @@threads is nil + don't lazily allocate in a
    # method called from a GC collection callback!
    @@threads.try(&.unsafe_each { |thread| yield thread })
  end

  def self.each(&)
    threads.each { |thread| yield thread }
  end

  def self.lock : Nil
    threads.@mutex.lock
  end

  def self.unlock : Nil
    threads.@mutex.unlock
  end

  # Creates and starts a new system thread.
  def initialize(@name : String? = nil, &@func : Thread ->)
    @system_handle = uninitialized Crystal::System::Thread::Handle
    init_handle
  end

  # Used once to initialize the thread object representing the main thread of
  # the process (that already exists).
  def initialize
    @func = ->(t : Thread) { }
    @system_handle = Crystal::System::Thread.current_handle
    @current_fiber = @main_fiber = Fiber.new(stack_address, self)

    Thread.threads.push(self)
  end

  private def detach(&)
    if @detached.test_and_set
      yield
    end
  end

  # Suspends the current thread until this thread terminates.
  def join : Nil
    detach do
      if ex = system_join
        @exception ||= ex
      end
    end

    if exception = @exception
      raise exception
    end
  end

  # Blocks the current thread for the duration of *time*. Clock precision is
  # dependent on the operating system and hardware.
  def self.sleep(time : Time::Span) : Nil
    Crystal::System::Thread.sleep(time)
  end

  # Returns the Thread object associated to the running system thread.
  def self.current : Thread
    Crystal::System::Thread.current_thread
  end

  # :nodoc:
  def self.current? : Thread?
    Crystal::System::Thread.current_thread?
  end

  # Associates the Thread object to the running system thread.
  protected def self.current=(current : Thread) : Thread
    Crystal::System::Thread.current_thread = current
    current
  end

  # Yields the currently running thread.
  def self.yield : Nil
    Crystal::System::Thread.yield_current
  end

  # Changes the name of the current thread.
  def self.name=(name : String) : String
    thread = Thread.current
    thread.name = name
  end

  protected def start
    Thread.threads.push(self)
    Thread.current = self
    @current_fiber = @main_fiber = fiber = Fiber.new(stack_address, self)

    if name = @name
      self.system_name = name
    end

    begin
      @func.call(self)
    rescue ex
      @exception = ex
    ensure
      Thread.threads.delete(self)
      Fiber.inactive(fiber)
      detach { system_close }
    end
  end

  protected def name=(@name : String)
    self.system_name = name
  end

  # Changes the Thread#name property but doesn't update the system name. Useful
  # on the main thread where we'd change the process name (e.g. top, ps, ...).
  def internal_name=(@name : String)
  end

  # Holds the GC thread handler
  property gc_thread_handler : Void* = Pointer(Void).null

  def suspend : Nil
    system_suspend
  end

  def wait_suspended : Nil
    system_wait_suspended
  end

  def resume : Nil
    system_resume
  end

  def self.stop_world : Nil
    GC.stop_world
  end

  def self.start_world : Nil
    GC.start_world
  end
end

require "./thread_linked_list"
require "./thread_condition_variable"
