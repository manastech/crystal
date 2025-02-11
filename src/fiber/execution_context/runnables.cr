# The queue is a port of Go's `runq*` functions, distributed under a BSD-like
# license: <https://cs.opensource.google/go/go/+/release-branch.go1.23:LICENSE>
#
# The queue derivates from the chase-lev lock-free queue with adaptations:
#
# - single ring buffer (per scheduler);
# - on overflow: bulk push half the ring to `GlobalQueue`;
# - on empty: bulk grab up to half the ring from `GlobalQueue`;
# - bulk push operation;

require "../list"
require "./global_queue"

module Fiber::ExecutionContext
  # :nodoc:
  #
  # Local queue or runnable fibers for schedulers.
  # Bounded.
  # First-in, first-out semantics (FIFO).
  # Single producer, multiple consumers thread safety.
  #
  # Private to an execution context scheduler, except for stealing methods that
  # can be called from any thread in the execution context.
  class Runnables(N)
    def initialize(@global_queue : GlobalQueue)
      # head is an index to the buffer where the next fiber to dequeue is.
      #
      # tail is an index to the buffer where the next fiber to enqueue will be
      # (on the next push).
      #
      # head is always behind tail (not empty) or equal (empty) but never after
      # tail (the queue would have a negative size => bug).
      @head = Atomic(UInt32).new(0)
      @tail = Atomic(UInt32).new(0)
      @buffer = uninitialized Fiber[N]
    end

    @[AlwaysInline]
    def capacity : Int32
      N
    end

    # Tries to push fiber on the local runnable queue. If the run queue is full,
    # pushes fiber on the global queue, which will grab the global lock.
    #
    # Executed only by the owner.
    def push(fiber : Fiber) : Nil
      # ported from Go: runqput
      loop do
        head = @head.get(:acquire) # sync with consumers
        tail = @tail.get(:relaxed)

        if (tail &- head) < N
          # put fiber to local queue
          @buffer.to_unsafe[tail % N] = fiber

          # make the fiber available for consumption
          @tail.set(tail &+ 1, :release)
          return
        end

        if push_slow(fiber, head, tail)
          return
        end

        # failed to advance head (another scheduler stole fibers),
        # the queue isn't full, now the push above must succeed
      end
    end

    private def push_slow(fiber : Fiber, head : UInt32, tail : UInt32) : Bool
      # ported from Go: runqputslow
      n = (tail &- head) // 2
      raise "BUG: queue is not full" if n != N // 2

      # first, try to grab half of the fibers from local queue
      batch = uninitialized Fiber[N] # actually N // 2 + 1 but that doesn't compile
      n.times do |i|
        batch.to_unsafe[i] = @buffer.to_unsafe[(head &+ i) % N]
      end
      _, success = @head.compare_and_set(head, head &+ n, :acquire_release, :acquire)
      return false unless success

      # append fiber to the batch
      batch.to_unsafe[n] = fiber

      # link the fibers
      n.times do |i|
        batch.to_unsafe[i].list_next = batch.to_unsafe[i &+ 1]
      end
      list = Fiber::List.new(batch.to_unsafe[0], batch.to_unsafe[n], size: (n &+ 1).to_i32)

      # now put the batch on global queue (grabs the global lock)
      @global_queue.bulk_push(pointerof(list))

      true
    end

    # Tries to enqueue all the fibers in *list* into the local queue. If the
    # local queue is full, the overflow will be pushed to the global queue; in
    # that case this will temporarily acquire the global queue lock.
    #
    # Executed only by the owner.
    def bulk_push(list : Fiber::List*) : Nil
      # ported from Go: runqputbatch
      head = @head.get(:acquire) # sync with other consumers
      tail = @tail.get(:relaxed)

      while !list.value.empty? && (tail &- head) < N
        fiber = list.value.pop
        @buffer.to_unsafe[tail % N] = fiber
        tail &+= 1
      end

      # make the fibers available for consumption
      @tail.set(tail, :release)

      # put any overflow on global queue
      @global_queue.bulk_push(list) unless list.value.empty?
    end

    # Dequeues the next runnable fiber from the local queue.
    #
    # Executed only by the owner.
    def shift? : Fiber?
      # ported from Go: runqget

      head = @head.get(:acquire) # sync with other consumers
      loop do
        tail = @tail.get(:relaxed)
        return if tail == head

        fiber = @buffer.to_unsafe[head % N]
        head, success = @head.compare_and_set(head, head &+ 1, :acquire_release, :acquire)
        return fiber if success
      end
    end

    # Steals half the fibers from the local queue of `src` and puts them onto
    # the local queue. Returns one of the stolen fibers, or `nil` on failure.
    #
    # Executed only by the owner (when the local queue is empty).
    def steal_from(src : Runnables(N)) : Fiber?
      # ported from Go: runqsteal

      tail = @tail.get(:relaxed)
      n = src.grab(@buffer.to_unsafe, tail)
      return if n == 0

      # 'dequeue' last fiber from @buffer
      n &-= 1
      fiber = @buffer.to_unsafe[(tail &+ n) % N]
      return fiber if n == 0

      head = @head.get(:acquire) # sync with consumers
      if tail &- head &+ n >= N
        raise "BUG: local queue overflow"
      end

      # make the fibers available for consumption
      @tail.set(tail &+ n, :release)

      fiber
    end

    # Grabs a batch of fibers from local queue into `buffer` of size N (normally
    # the ring buffer of another `Runnables`) starting at `buffer_head`. Returns
    # number of grabbed fibers.
    #
    # Can be executed by any scheduler.
    protected def grab(buffer : Fiber*, buffer_head : UInt32) : UInt32
      # ported from Go: runqgrab

      head = @head.get(:acquire) # sync with other consumers
      loop do
        tail = @tail.get(:acquire) # sync with the producer

        n = tail &- head
        n -= n // 2
        return 0_u32 if n == 0 # queue is empty

        if n > N // 2
          # read inconsistent head and tail
          head = @head.get(:acquire)
          next
        end

        n.times do |i|
          fiber = @buffer.to_unsafe[(head &+ i) % N]
          buffer[(buffer_head &+ i) % N] = fiber
        end

        # try to mark the fiber as consumed
        head, success = @head.compare_and_set(head, head &+ n, :acquire_release, :acquire)
        return n if success
      end
    end

    @[AlwaysInline]
    def empty? : Bool
      @head.get(:relaxed) == @tail.get(:relaxed)
    end

    @[AlwaysInline]
    def size : UInt32
      @tail.get(:relaxed) &- @head.get(:relaxed)
    end
  end
end
