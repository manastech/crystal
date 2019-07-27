require "fiber"

# A `Channel` enables concurrent communication between fibers.
#
# They allow communicating data between fibers without sharing memory and without having to worry about locks, semaphores or other special structures.
#
# ```
# channel = Channel(Int32).new
#
# spawn do
#   channel.send(0)
#   channel.send(1)
# end
#
# channel.receive # => 0
# channel.receive # => 1
# ```
abstract class Channel(T)
  module SelectAction
    abstract def ready?
    abstract def execute
    abstract def wait
    abstract def unwait
  end

  class ClosedError < Exception
    def initialize(msg = "Channel is closed")
      super(msg)
    end
  end

  def initialize
    @closed = false
    @senders = Deque(Fiber).new
    @receivers = Deque(Fiber).new
  end

  def self.new : Unbuffered(T)
    Unbuffered(T).new
  end

  def self.new(capacity) : Buffered(T)
    Buffered(T).new(capacity)
  end

  def close
    @closed = true
    Crystal::Scheduler.enqueue @senders
    @senders.clear
    Crystal::Scheduler.enqueue @receivers
    @receivers.clear
    nil
  end

  def closed?
    @closed
  end

  # Receives a value from the channel.
  # If there is a value waiting, it is returned immediately. Otherwise, this method blocks until a value is sent to the channel.
  #
  # Raises `ClosedError` if the channel is closed or closes while waiting for receive.
  #
  # ```
  # channel = Channel(Int32).new
  # channel.send(1)
  # channel.receive # => 1
  # ```
  def receive
    receive_impl { raise ClosedError.new }
  end

  # Receives a value from the channel.
  # If there is a value waiting, it is returned immediately. Otherwise, this method blocks until a value is sent to the channel.
  #
  # Returns `nil` if the channel is closed or closes while waiting for receive.
  def receive?
    receive_impl { return nil }
  end

  def inspect(io : IO) : Nil
    to_s(io)
  end

  def pretty_print(pp)
    pp.text inspect
  end

  protected def wait_for_receive
    @receivers << Fiber.current
  end

  protected def unwait_for_receive
    @receivers.delete Fiber.current
  end

  protected def wait_for_send
    @senders << Fiber.current
  end

  protected def unwait_for_send
    @senders.delete Fiber.current
  end

  protected def raise_if_closed
    raise ClosedError.new if @closed
  end

  def self.receive_first(*channels)
    receive_first channels
  end

  def self.receive_first(channels : Tuple | Array)
    self.select(channels.map(&.receive_select_action))[1]
  end

  def self.send_first(value, *channels)
    send_first value, channels
  end

  def self.send_first(value, channels : Tuple | Array)
    self.select(channels.map(&.send_select_action(value)))
    nil
  end

  def self.select(*ops : SelectAction)
    self.select ops
  end

  def self.select(ops : Tuple | Array, has_else = false)
    loop do
      ops.each_with_index do |op, index|
        if op.ready?
          result = op.execute
          return index, result
        end
      end

      if has_else
        return ops.size, nil
      end

      ops.each &.wait
      Crystal::Scheduler.reschedule
      ops.each &.unwait
    end
  end

  # :nodoc:
  def send_select_action(value : T)
    SendAction.new(self, value)
  end

  # :nodoc:
  def receive_select_action
    ReceiveAction.new(self)
  end

  # :nodoc:
  struct ReceiveAction(C)
    include SelectAction

    def initialize(@channel : C)
    end

    def ready?
      !@channel.empty?
    end

    def execute
      @channel.receive
    end

    def wait
      @channel.wait_for_receive
    end

    def unwait
      @channel.unwait_for_receive
    end
  end

  # :nodoc:
  struct SendAction(C, T)
    include SelectAction

    def initialize(@channel : C, @value : T)
    end

    def ready?
      !@channel.full?
    end

    def execute
      @channel.send(@value)
    end

    def wait
      @channel.wait_for_send
    end

    def unwait
      @channel.unwait_for_send
    end
  end
end

# Buffered channel, using a queue.
class Channel::Buffered(T) < Channel(T)
  def initialize(@capacity = 32)
    @queue = Deque(T).new(@capacity)
    super()
  end

  # Send a value to the channel.
  def send(value : T)
    while full?
      raise_if_closed
      @senders << Fiber.current
      Crystal::Scheduler.reschedule
    end

    raise_if_closed

    @queue << value
    if receiver = @receivers.shift?
      Crystal::Scheduler.enqueue receiver
    end

    self
  end

  private def receive_impl
    while empty?
      yield if @closed
      @receivers << Fiber.current
      Crystal::Scheduler.reschedule
    end

    @queue.shift.tap do
      if sender = @senders.shift?
        Crystal::Scheduler.enqueue sender
      end
    end
  end

  def full?
    @queue.size >= @capacity
  end

  def empty?
    @queue.empty?
  end
end

# Unbuffered channel.
class Channel::Unbuffered(T) < Channel(T)
  @sender : Fiber?

  def initialize
    @has_value = false
    @value = uninitialized T
    super
  end

  # Send a value to the channel.
  def send(value : T)
    while @has_value
      raise_if_closed
      @senders << Fiber.current
      Crystal::Scheduler.reschedule
    end

    raise_if_closed

    @value = value
    @has_value = true
    @sender = Fiber.current

    if receiver = @receivers.shift?
      receiver.resume
    else
      Crystal::Scheduler.reschedule
    end
  end

  private def receive_impl
    until @has_value
      yield if @closed
      @receivers << Fiber.current
      if sender = @senders.shift?
        sender.resume
      else
        Crystal::Scheduler.reschedule
      end
    end

    yield if @closed

    @value.tap do
      @has_value = false
      Crystal::Scheduler.enqueue @sender.not_nil!
      @sender = nil
    end
  end

  def empty?
    !@has_value && @senders.empty?
  end

  def full?
    @has_value || @receivers.empty?
  end

  def close
    super
    if sender = @sender
      Crystal::Scheduler.enqueue sender
      @sender = nil
    end
  end
end
