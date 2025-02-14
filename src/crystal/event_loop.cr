abstract class Crystal::EventLoop
  def self.backend_class
    {% if flag?(:wasi) %}
      Crystal::EventLoop::Wasi
    {% elsif flag?(:unix) %}
      # TODO: enable more targets by default (need manual tests or fixes)
      {% if flag?("evloop=libevent") %}
        Crystal::EventLoop::LibEvent
      {% elsif flag?("evloop=epoll") || flag?(:android) || flag?(:linux) %}
        Crystal::EventLoop::Epoll
      {% elsif flag?("evloop=kqueue") || flag?(:darwin) || flag?(:freebsd) %}
        Crystal::EventLoop::Kqueue
      {% else %}
        Crystal::EventLoop::LibEvent
      {% end %}
    {% elsif flag?(:win32) %}
      Crystal::EventLoop::IOCP
    {% else %}
      {% raise "Event loop not supported" %}
    {% end %}
  end

  # Creates an event loop instance
  def self.create : self
    backend_class.new
  end

  @[AlwaysInline]
  def self.current : self
    {% if flag?(:execution_context) %}
      Fiber::ExecutionContext.current.event_loop
    {% else %}
      Crystal::Scheduler.event_loop
    {% end %}
  end

  @[AlwaysInline]
  def self.current? : self | Nil
    {% if flag?(:execution_context) %}
      Fiber::ExecutionContext.current.event_loop
    {% else %}
      Crystal::Scheduler.event_loop?
    {% end %}
  end

  # Runs the loop.
  #
  # Returns immediately if events are activable. Set `blocking` to false to
  # return immediately if there are no activable events; set it to true to wait
  # for activable events, which will block the current thread until then.
  #
  # Returns `true` on normal returns (e.g. has activated events, has pending
  # events but blocking was false) and `false` when there are no registered
  # events.
  abstract def run(blocking : Bool) : Bool

  {% if flag?(:execution_context) %}
    # Same as `#run` but collects runnable fibers into *queue* instead of
    # enqueueing in parallel, so the caller is responsible and in control for
    # when and how the fibers will be enqueued.
    abstract def run(queue : Fiber::List*, blocking : Bool) : Nil
  {% end %}

  # Tells a blocking run loop to no longer wait for events to activate. It may
  # for example enqueue a NOOP event with an immediate (or past) timeout. Having
  # activated an event, the loop shall return, allowing the blocked thread to
  # continue.
  #
  # Should be a NOOP when the loop isn't running or is running in a nonblocking
  # mode.
  #
  # NOTE: we assume that multiple threads won't run the event loop at the same
  #       time in parallel, but this assumption may change in the future!
  abstract def interrupt : Nil

  # Create a new resume event for a fiber.
  abstract def create_resume_event(fiber : Fiber) : Event

  # Creates a timeout_event.
  abstract def create_timeout_event(fiber : Fiber) : Event

  module Event
    # Frees the event.
    abstract def free : Nil

    # Adds a new timeout to this event.
    abstract def add(timeout : Time::Span) : Nil
  end
end

require "./event_loop/file_descriptor"

abstract class Crystal::EventLoop
  # The FileDescriptor interface is always needed, so we include it right in
  # the main interface.
  include FileDescriptor

  # The socket module is empty by default and filled with abstract defs when
  # crystal/system/socket.cr is required.
  module Socket
  end

  include Socket
end

{% if flag?(:wasi) %}
  require "./event_loop/wasi"
{% elsif flag?(:unix) %}
  {% if flag?("evloop=libevent") %}
    require "./event_loop/libevent"
  {% elsif flag?("evloop=epoll") || flag?(:android) || flag?(:linux) %}
    require "./event_loop/epoll"
  {% elsif flag?("evloop=kqueue") || flag?(:darwin) || flag?(:freebsd) %}
    require "./event_loop/kqueue"
  {% else %}
    require "./event_loop/libevent"
  {% end %}
{% elsif flag?(:win32) %}
  require "./event_loop/iocp"
{% else %}
  {% raise "Event loop not supported" %}
{% end %}
