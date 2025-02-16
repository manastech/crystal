require "fiber"
require "crystal/spin_lock"
require "crystal/pointer_linked_list"
require "channel/select"

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
#
# NOTE: Although a `Channel(Nil)` or any other nilable types like `Channel(Int32?)` are valid
# they are discouraged since from certain methods or constructs it receiving a `nil` as data
# will be indistinguishable from a closed channel.
#
class Channel(T)
  @lock = Crystal::SpinLock.new
  @queue : Deque(T)?

  # :nodoc:
  record UseDefault

  class ClosedError < Exception
    def initialize(msg = "Channel is closed")
      super(msg)
    end
  end

  private module SenderReceiverCloseAction
    def close
      self.state = DeliveryState::Closed
      _select_context = self.select_context
      if _select_context.nil? || _select_context.try_trigger
        self.fiber.enqueue
      end
    end
  end

  private struct Sender(T)
    include Crystal::PointerLinkedList::Node
    include SenderReceiverCloseAction

    property fiber : Fiber
    property data : T
    property state : DeliveryState
    property select_context : SelectContext(Nil)?

    def initialize
      @fiber = uninitialized Fiber
      @data = uninitialized T
      @state = DeliveryState::None
    end
  end

  private struct Receiver(T)
    include Crystal::PointerLinkedList::Node
    include SenderReceiverCloseAction

    property fiber : Fiber
    property data : T
    property state : DeliveryState
    property select_context : SelectContext(T)?

    def initialize
      @fiber = uninitialized Fiber
      @data = uninitialized T
      @state = DeliveryState::None
    end
  end

  def initialize(@capacity = 0)
    @closed = false

    @senders = Crystal::PointerLinkedList(Sender(T)).new
    @receivers = Crystal::PointerLinkedList(Receiver(T)).new

    if capacity > 0
      @queue = Deque(T).new
    end
  end

  # Closes the channel.
  # The method prevents any new value from being sent to / received from the channel.
  # All fibers blocked in `send` or `receive` will be awakened with `Channel::ClosedError`
  #
  # Both awaiting and subsequent calls to `#send` will consider the channel closed.
  # All items successfully sent to the channel can be received, before `#receive` considers the channel closed.
  # Calling `#close` on a closed channel does not have any effect.
  #
  # It returns `true` when the channel was successfully closed, or `false` if it was already closed.
  def close : Bool
    sender_list = Crystal::PointerLinkedList(Sender(T)).new
    receiver_list = Crystal::PointerLinkedList(Receiver(T)).new

    @lock.sync do
      return false if @closed
      @closed = true

      @senders, sender_list = sender_list, @senders
      @receivers, receiver_list = receiver_list, @receivers
    end

    sender_list.each(&.value.close)
    receiver_list.each(&.value.close)
    true
  end

  def closed? : Bool
    @closed
  end

  # Sends a value to the channel.
  # If the channel has spare capacity, then the method returns immediately.
  # Otherwise, this method blocks the calling fiber until another fiber calls `#receive` on the channel.
  #
  # Raises `ClosedError` if the channel is closed or closes while waiting on a full channel.
  def send(value : T) : self
    sender = Sender(T).new

    @lock.lock

    case send_internal(value)
    in .delivered?
      @lock.unlock
    in .closed?
      @lock.unlock
      raise ClosedError.new
    in .none?
      sender.fiber = Fiber.current
      sender.data = value
      @senders.push pointerof(sender)
      @lock.unlock

      Fiber.suspend

      case sender.state
      in .delivered?
        # ignore
      in .closed?
        raise ClosedError.new
      in .none?
        raise "BUG: Fiber was awaken without channel delivery state set"
      end
    end

    self
  end

  protected def send_internal(value : T)
    if @closed
      DeliveryState::Closed
    elsif receiver_ptr = dequeue_receiver
      receiver_ptr.value.data = value
      receiver_ptr.value.state = DeliveryState::Delivered
      receiver_ptr.value.fiber.enqueue

      DeliveryState::Delivered
    elsif (queue = @queue) && queue.size < @capacity
      queue << value

      DeliveryState::Delivered
    else
      DeliveryState::None
    end
  end

  # Receives a value from the channel.
  # If there is a value waiting, then it is returned immediately. Otherwise, this method blocks until a value is sent to the channel.
  #
  # Raises `ClosedError` if the channel is closed or closes while waiting for receive.
  #
  # ```
  # channel = Channel(Int32).new
  # spawn do
  #   channel.send(1)
  # end
  # channel.receive # => 1
  # ```
  def receive : T
    receive_impl { raise ClosedError.new }
  end

  # Receives a value from the channel.
  # If there is a value waiting, it is returned immediately. Otherwise, this method blocks until a value is sent to the channel.
  #
  # Returns `nil` if the channel is closed or closes while waiting for receive.
  def receive? : T?
    receive_impl { return nil }
  end

  private def receive_impl(&)
    receiver = Receiver(T).new

    @lock.lock

    state, value = receive_internal

    case state
    in .delivered?
      @lock.unlock
      raise "BUG: Unexpected UseDefault value for delivered receive" if value.is_a?(UseDefault)
      value
    in .closed?
      @lock.unlock
      yield
    in .none?
      receiver.fiber = Fiber.current
      @receivers.push pointerof(receiver)
      @lock.unlock

      Fiber.suspend

      case receiver.state
      in .delivered?
        receiver.data
      in .closed?
        yield
      in .none?
        raise "BUG: Fiber was awaken without channel delivery state set"
      end
    end
  end

  protected def receive_internal
    if (queue = @queue) && !queue.empty?
      deque_value = queue.shift
      if sender_ptr = dequeue_sender
        queue << sender_ptr.value.data
        sender_ptr.value.state = DeliveryState::Delivered
        sender_ptr.value.fiber.enqueue
      end

      {DeliveryState::Delivered, deque_value}
    elsif sender_ptr = dequeue_sender
      value = sender_ptr.value.data
      sender_ptr.value.state = DeliveryState::Delivered
      sender_ptr.value.fiber.enqueue

      {DeliveryState::Delivered, value}
    elsif @closed
      {DeliveryState::Closed, UseDefault.new}
    else
      {DeliveryState::None, UseDefault.new}
    end
  end

  private def dequeue_receiver
    while receiver_ptr = @receivers.shift?
      select_context = receiver_ptr.value.select_context
      if select_context && !select_context.try_trigger
        receiver_ptr.value.state = DeliveryState::Delivered
        next
      end

      break
    end

    receiver_ptr
  end

  private def dequeue_sender
    while sender_ptr = @senders.shift?
      select_context = sender_ptr.value.select_context
      if select_context && !select_context.try_trigger
        sender_ptr.value.state = DeliveryState::Delivered
        next
      end

      break
    end

    sender_ptr
  end

  def inspect(io : IO) : Nil
    to_s(io)
  end

  def pretty_print(pp)
    pp.text inspect
  end

  def self.receive_first(*channels)
    receive_first channels
  end

  def self.receive_first(channels : Enumerable(Channel))
    _, value = self.select(channels.map(&.receive_select_action))
    value
  end

  def self.send_first(value, *channels) : Nil
    send_first value, channels
  end

  def self.send_first(value, channels : Enumerable(Channel)) : Nil
    self.select(channels.map(&.send_select_action(value)))
    nil
  end

  # :nodoc:
  def send_select_action(value : T)
    SendAction.new(self, value)
  end

  # :nodoc:
  def receive_select_action
    StrictReceiveAction.new(self)
  end

  # :nodoc:
  def receive_select_action?
    LooseReceiveAction.new(self)
  end

  private class StrictReceiveAction(T)
    include SelectAction(T)
    property receiver : Receiver(T)

    def initialize(@channel : Channel(T))
      @receiver = Receiver(T).new
    end

    def execute : DeliveryState
      state, value = @channel.receive_internal

      if state.delivered?
        @receiver.data = value.as(T)
      end

      state
    end

    def result : T
      @receiver.data
    end

    def wait(context : SelectContext(T)) : Nil
      @receiver.fiber = Fiber.current
      @receiver.select_context = context
      @channel.@receivers.push pointerof(@receiver)
    end

    def wait_result_impl(context : SelectContext(T))
      case @receiver.state
      in .delivered?
        context.action.result
      in .closed?
        raise ClosedError.new
      in .none?
        raise "BUG: StrictReceiveAction.wait_result_impl called with DeliveryState::None"
      end
    end

    def unwait_impl(context : SelectContext(T))
      if !@channel.closed? && @receiver.state.none?
        @channel.@receivers.delete pointerof(@receiver)
      end
    end

    def lock_object_id : UInt64
      @channel.object_id
    end

    def lock : Nil
      @channel.@lock.lock
    end

    def unlock : Nil
      @channel.@lock.unlock
    end

    def default_result
      raise ClosedError.new
    end
  end

  private class LooseReceiveAction(T)
    include SelectAction(T)
    property receiver : Receiver(T)

    def initialize(@channel : Channel(T))
      @receiver = Receiver(T).new
    end

    def execute : DeliveryState
      state, value = @channel.receive_internal

      if state.delivered?
        @receiver.data = value.as(T)
      end

      state
    end

    def result : T
      @receiver.data
    end

    def wait(context : SelectContext(T)) : Nil
      @receiver.fiber = Fiber.current
      @receiver.select_context = context
      @channel.@receivers.push pointerof(@receiver)
    end

    def wait_result_impl(context : SelectContext(T))
      case @receiver.state
      in .delivered?
        context.action.result
      in .closed?
        nil
      in .none?
        raise "BUG: LooseReceiveAction.wait_result_impl called with DeliveryState::None"
      end
    end

    def unwait_impl(context : SelectContext(T))
      if !@channel.closed? && @receiver.state.none?
        @channel.@receivers.delete pointerof(@receiver)
      end
    end

    def lock_object_id : UInt64
      @channel.object_id
    end

    def lock : Nil
      @channel.@lock.lock
    end

    def unlock : Nil
      @channel.@lock.unlock
    end

    def default_result
      nil
    end
  end

  private class SendAction(T)
    include SelectAction(Nil)
    property sender : Sender(T)

    def initialize(@channel : Channel(T), value : T)
      @sender = Sender(T).new
      @sender.data = value
    end

    def execute : DeliveryState
      @channel.send_internal(@sender.data)
    end

    def result : Nil
      nil
    end

    def wait(context : SelectContext(Nil)) : Nil
      @sender.fiber = Fiber.current
      @sender.select_context = context
      @channel.@senders.push pointerof(@sender)
    end

    def wait_result_impl(context : SelectContext(Nil))
      case @sender.state
      in .delivered?
        context.action.result
      in .closed?
        raise ClosedError.new
      in .none?
        raise "BUG: SendAction.wait_result_impl called with DeliveryState::None"
      end
    end

    def unwait_impl(context : SelectContext(Nil))
      if !@channel.closed? && @sender.state.none?
        @channel.@senders.delete pointerof(@sender)
      end
    end

    def lock_object_id : UInt64
      @channel.object_id
    end

    def lock : Nil
      @channel.@lock.lock
    end

    def unlock : Nil
      @channel.@lock.unlock
    end

    def default_result
      raise ClosedError.new
    end
  end
end
