require "crystal/event_loop"

{% skip_file unless flag?(:wasi) || Crystal::EventLoop.has_constant?(:LibEvent) %}

require "crystal/thread_local_value"

# :nodoc:
module IO::Evented
  @read_timed_out = false
  @write_timed_out = false

  @readers = Crystal::ThreadLocalValue(Deque(Fiber)).new
  @writers = Crystal::ThreadLocalValue(Deque(Fiber)).new

  @read_event = Crystal::ThreadLocalValue(Crystal::EventLoop::Event).new
  @write_event = Crystal::ThreadLocalValue(Crystal::EventLoop::Event).new

  # :nodoc:
  def resume_read(timed_out = false) : Nil
    @read_timed_out = timed_out

    if reader = @readers.get?.try &.shift?
      reader.enqueue
    end
  end

  # :nodoc:
  def resume_write(timed_out = false) : Nil
    @write_timed_out = timed_out

    if writer = @writers.get?.try &.shift?
      writer.enqueue
    end
  end

  # :nodoc:
  def evented_wait_readable(timeout = @read_timeout, *, raise_if_closed = true, &) : Nil
    readers = @readers.get { Deque(Fiber).new }
    readers << Fiber.current
    add_read_event(timeout)
    Fiber.suspend

    if @read_timed_out
      @read_timed_out = false
      yield
    end

    check_open if raise_if_closed
  end

  private def add_read_event(timeout = @read_timeout) : Nil
    event = @read_event.get { Crystal::EventLoop.current.create_fd_read_event(self) }
    event.add timeout
  end

  # :nodoc:
  def evented_wait_writable(timeout = @write_timeout, &) : Nil
    writers = @writers.get { Deque(Fiber).new }
    writers << Fiber.current
    add_write_event(timeout)
    Fiber.suspend

    if @write_timed_out
      @write_timed_out = false
      yield
    end

    check_open
  end

  private def add_write_event(timeout = @write_timeout) : Nil
    event = @write_event.get { Crystal::EventLoop.current.create_fd_write_event(self) }
    event.add timeout
  end

  def evented_close : Nil
    @read_event.consume_each &.free

    @write_event.consume_each &.free

    @readers.consume_each do |readers|
      Crystal::Scheduler.enqueue readers
    end

    @writers.consume_each do |writers|
      Crystal::Scheduler.enqueue writers
    end
  end

  # :nodoc:
  def evented_resume_pending_readers
    if (readers = @readers.get?) && !readers.empty?
      add_read_event
    end
  end

  # :nodoc:
  def evented_resume_pending_writers
    if (writers = @writers.get?) && !writers.empty?
      add_write_event
    end
  end
end
