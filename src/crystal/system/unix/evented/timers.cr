# NOTE: this is a struct because it only wraps a const pointer to a deque
# allocated in the heap
struct Crystal::Evented::Timers
  def initialize
    @list = Deque(Evented::Event*).new
  end

  def empty? : Bool
    @list.empty?
  end

  def next_ready? : Time::Span?
    @list.first?.try(&.value.wake_at)
  end

  def dequeue_ready(&) : Nil
    return if @list.empty?

    now = Time.monotonic
    n = 0

    @list.each do |event|
      break if event.value.wake_at > now
      yield event
      n += 1
    end

    n.times { @list.shift }
  end

  def add(event : Evented::Event*) : Nil
    if @list.empty?
      @list << event
    elsif index = lookup(event.value.wake_at)
      @list.insert(index, event)
    else
      @list.push(event)
    end
  end

  def delete(event : Evented::Event*) : Nil
    @list.delete(event)
  end

  private def lookup(wake_at)
    @list.each_with_index do |event, index|
      return index if event.value.wake_at >= wake_at
    end
  end
end
