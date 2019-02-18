require "fiber"
require "crystal/mutex"
require "crystal/condition_variable"
require "./mt_select"

abstract class Channel(T)
  enum State
    Opened = 0
    Closing = 1
    Closed = 2
  end

  class ClosedError < Exception
    def initialize(msg = "Channel is closed")
      super(msg)
    end
  end

  def initialize
    @state = State::Opened
    @mutex = Crystal::Mutex.new
    @senders = Crystal::ConditionVariable.new
    @receivers = Crystal::ConditionVariable.new
  end

  def self.new : Unbuffered(T)
    Unbuffered(T).new
  end

  def self.new(capacity) : Buffered(T)
    Buffered(T).new(capacity)
  end

  def close : Nil
    raise_if_closed

    @mutex.lock

    # close immediately or delay until the channel queue is emptied:
    if empty?
      @state = State::Closed
    else
      @state = State::Closing
    end

    # wakeup pending fibers:
    @senders.broadcast
    @receivers.broadcast

    # done
    @mutex.unlock
  end

  def closed? : Bool
    !@state.opened?
  end

  def receive : T
    receive_impl { raise ClosedError.new }.first
  end

  def receive? : T?
    receive_impl { return nil }.first
  end

  protected def receive_nonblock : {T, Bool}
    receive_impl(should_block: false) do
      value = uninitialized T
      return value, false
    end
  end

  def inspect(io : IO) : Nil
    to_s(io)
  end

  def pretty_print(pp)
    pp.text inspect
  end

  #private macro debug(msg)
  #  {% if flag?(:DEBUG) || flag?(:DEBUG1) || flag?(:DEBUG2) %}
  #    LibC.dprintf 2, "Fiber@0x%x %s@0x%x: %s\n", Fiber.current.object_id, self.class.name, object_id, {{msg}}
  #  {% end %}
  #end

  protected def wait_for_receive
    @receivers.wait(@mutex)
  end

  protected def unwait_for_receive
    @receivers.delete
  end

  protected def wait_for_send
    @senders.wait(@mutex)
  end

  protected def unwait_for_send
    @senders.delete
  end

  protected def raise_if_closed
    raise ClosedError.new if closed?
  end

  def self.receive_first(*channels)
    receive_first(channels)
  end

  def self.receive_first(channels : Tuple | Array)
    self.select(channels.map(&.receive_select_action))[1]
  end

  def self.send_first(value, *channels)
    send_first(value, channels)
  end

  def self.send_first(value, channels : Tuple | Array) : Nil
    self.select(channels.map(&.send_select_action(value)))
  end
end

class Channel::Buffered(T) < Channel(T)
  def initialize(@capacity = 32)
    @size = 0
    @start = 0
    @buf = Pointer(T).malloc(@capacity)
    super()
  end

  def full? : Bool
    @size >= @capacity
  end

  def empty? : Bool
    @size == 0
  end

  def send(value : T) : self
    raise_if_closed

    @mutex.lock

    # wait until the channel queue has some room for a value:
    while full?
      if closed?
        @mutex.unlock
        raise ClosedError.new
      end
      @senders.wait(@mutex)
    end

    # enqueue item:
    index = @start + @size
    index -= @capacity if index >= @capacity
    @buf[index] = value
    @size += 1

    # wakeup one waiting receiver:
    @receivers.signal

    # done:
    @mutex.unlock

    self
  end

  private def receive_impl(should_block = true) : {T, Bool}
    # closed & empty: nothing left to receive
    yield if @state.closed? && empty?

    @mutex.lock

    # wait until the channel queue has a value:
    while empty?
      if closed?
        @mutex.unlock
        yield
      end

      unless should_block
        @mutex.unlock
        value = uninitialized T
        return {value, false}
      end

      @receivers.wait(@mutex)
    end

    # dequeue item:
    value = @buf[@start]
    @size -= 1
    @start += 1
    @start -= @capacity if @start >= @capacity

    if @state.closing?
      # close the channel once it's empty:
      @state = State::Closed if empty?
    else
      # wakeup a waiting sender:
      @senders.signal
    end

    # done
    @mutex.unlock
    {value, true}
  end
end

class Channel::Unbuffered(T) < Channel(T)
  def initialize
    @has_value = false
    @value = uninitialized T
    @sender = uninitialized Fiber

    super
  end

  def full? : Bool
    @has_value
  end

  def empty? : Bool
    !@has_value
  end

  def send(value : T) : self
    raise_if_closed

    @mutex.lock

    # wait until we can deliver the value:
    while @has_value
      if closed?
        @mutex.unlock
        raise ClosedError.new
      end

      @senders.wait(@mutex)
    end

    # set the value:
    @value = value
    @sender = Fiber.current
    @has_value = true

    # wakeup one pending receiver (if any):
    @receivers.signal

    # done
    @mutex.unlock

    # synchronous: suspend until a receiver got the value
    Crystal::Scheduler.reschedule

    self
  end

  private def receive_impl(should_block = true) : {T, Bool}
    # closed & empty: nothing left to receive
    yield if @state.closed? && empty?

    @mutex.lock

    # wait until a value is set:
    until @has_value
      if closed?
        @mutex.unlock
        yield
      end

      unless should_block
        @mutex.unlock
        value = uninitialized T
        return {value, false}
      end

      @receivers.wait(@mutex)
    end

    # get the value:
    value = @value
    sender = @sender
    @has_value = false

    if @state.closing?
      # close the channel once it's empty
      @state = State::Closed
    else
      # wakeup a waiting sender:
      @senders.signal
    end

    @mutex.unlock

    # synchronous: wakeup pending sender
    Crystal::Scheduler.enqueue(sender)

    {value, true}
  end

  def close
    super

    # don't lock the mutex unless there is a pending sender (fast path):
    return unless @has_value

    # then check again for a pending sender inside a lock:
    @mutex.lock
    Crystal::Scheduler.enqueue(@sender) if @has_value
    @mutex.unlock
  end
end
