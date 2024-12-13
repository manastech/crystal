require "./spec_helper"
require "../../../support/thread"

describe Fiber::ExecutionContext::Runnables do
  it "#initialize" do
    g = Fiber::ExecutionContext::GlobalQueue.new(Thread::Mutex.new)
    r = Fiber::ExecutionContext::Runnables(16).new(g)
    r.capacity.should eq(16)
  end

  describe "#push" do
    it "enqueues the fiber in local queue" do
      fibers = 4.times.map { |i| new_fake_fiber("f#{i}") }.to_a

      # local enqueue
      g = Fiber::ExecutionContext::GlobalQueue.new(Thread::Mutex.new)
      r = Fiber::ExecutionContext::Runnables(4).new(g)
      fibers.each { |f| r.push(f) }

      # local dequeue
      fibers.each { |f| r.shift?.should be(f) }
      r.shift?.should be_nil

      # didn't push to global queue
      g.pop?.should be_nil
    end

    it "moves half the local queue to the global queue on overflow" do
      fibers = 5.times.map { |i| new_fake_fiber("f#{i}") }.to_a

      # local enqueue + overflow
      g = Fiber::ExecutionContext::GlobalQueue.new(Thread::Mutex.new)
      r = Fiber::ExecutionContext::Runnables(4).new(g)
      fibers.each { |f| r.push(f) }

      # kept half of local queue
      r.shift?.should be(fibers[2])
      r.shift?.should be(fibers[3])

      # moved half of local queue + last push to global queue
      g.pop?.should eq(fibers[0])
      g.pop?.should eq(fibers[1])
      g.pop?.should eq(fibers[4])
    end

    it "can always push up to capacity" do
      g = Fiber::ExecutionContext::GlobalQueue.new(Thread::Mutex.new)
      r = Fiber::ExecutionContext::Runnables(4).new(g)

      4.times do
        # local
        4.times { r.push(new_fake_fiber) }
        2.times { r.shift? }
        2.times { r.push(new_fake_fiber) }

        # overflow (2+1 fibers are sent to global queue + 1 local)
        2.times { r.push(new_fake_fiber) }

        # clear
        3.times { r.shift? }
      end

      # on each iteration we pushed 2+1 fibers to the global queue
      g.size.should eq(12)

      # grab fibers back from the global queue
      fiber = g.unsafe_grab?(r, divisor: 1)
      fiber.should_not be_nil
      r.shift?.should_not be_nil
      r.shift?.should be_nil
    end
  end

  describe "#bulk_push" do
    it "fills the local queue" do
      l = Fiber::List.new
      fibers = 4.times.map { |i| new_fake_fiber("f#{i}") }.to_a
      fibers.each { |f| l.push(f) }

      # local enqueue
      g = Fiber::ExecutionContext::GlobalQueue.new(Thread::Mutex.new)
      r = Fiber::ExecutionContext::Runnables(4).new(g)
      r.bulk_push(pointerof(l))

      fibers.reverse_each { |f| r.shift?.should be(f) }
      g.empty?.should be_true
    end

    it "pushes the overflow to the global queue" do
      l = Fiber::List.new
      fibers = 7.times.map { |i| new_fake_fiber("f#{i}") }.to_a
      fibers.each { |f| l.push(f) }

      # local enqueue + overflow
      g = Fiber::ExecutionContext::GlobalQueue.new(Thread::Mutex.new)
      r = Fiber::ExecutionContext::Runnables(4).new(g)
      r.bulk_push(pointerof(l))

      # filled the local queue
      r.shift?.should eq(fibers[6])
      r.shift?.should eq(fibers[5])
      r.shift?.should be(fibers[4])
      r.shift?.should be(fibers[3])

      # moved the rest to the global queue
      g.pop?.should eq(fibers[2])
      g.pop?.should eq(fibers[1])
      g.pop?.should eq(fibers[0])
    end
  end

  describe "#shift?" do
    # TODO: need specific tests (though we already use it in the above tests?)
  end

  describe "#steal_from" do
    it "steals from another runnables" do
      g = Fiber::ExecutionContext::GlobalQueue.new(Thread::Mutex.new)
      fibers = 6.times.map { |i| new_fake_fiber("f#{i}") }.to_a

      # fill the source queue
      r1 = Fiber::ExecutionContext::Runnables(16).new(g)
      fibers.each { |f| r1.push(f) }

      # steal from source queue
      r2 = Fiber::ExecutionContext::Runnables(16).new(g)
      fiber = r2.steal_from(r1)

      # stole half of the runnable fibers
      fiber.should be(fibers[2])
      r2.shift?.should be(fibers[0])
      r2.shift?.should be(fibers[1])
      r2.shift?.should be_nil

      # left the other half
      r1.shift?.should be(fibers[3])
      r1.shift?.should be(fibers[4])
      r1.shift?.should be(fibers[5])
      r1.shift?.should be_nil

      # global queue is left untouched
      g.empty?.should be_true
    end

    it "steals the last fiber" do
      g = Fiber::ExecutionContext::GlobalQueue.new(Thread::Mutex.new)
      lone = new_fake_fiber("lone")

      # fill the source queue
      r1 = Fiber::ExecutionContext::Runnables(16).new(g)
      r1.push(lone)

      # steal from source queue
      r2 = Fiber::ExecutionContext::Runnables(16).new(g)
      fiber = r2.steal_from(r1)

      # stole the fiber & local queue is still empty
      fiber.should be(lone)
      r2.shift?.should be_nil

      # left nothing in original queue
      r1.shift?.should be_nil

      # global queue is left untouched
      g.empty?.should be_true
    end

    it "steals nothing" do
      g = Fiber::ExecutionContext::GlobalQueue.new(Thread::Mutex.new)
      r1 = Fiber::ExecutionContext::Runnables(16).new(g)
      r2 = Fiber::ExecutionContext::Runnables(16).new(g)

      fiber = r2.steal_from(r1)
      fiber.should be_nil
      r2.shift?.should be_nil
      r1.shift?.should be_nil
    end
  end

  # interpreter doesn't support threads yet (#14287)
  pending_interpreted describe: "thread safety" do
    it "stress test" do
      n = 7
      increments = 7919

      # less fibers than space in runnables (so threads can starve)
      # 54 is roughly half of 16 × 7 and can be divided by 9 (for batch enqueues below)
      fibers = Array(Fiber::ExecutionContext::FiberCounter).new(54) do |i|
        Fiber::ExecutionContext::FiberCounter.new(new_fake_fiber("f#{i}"))
      end

      global_queue = Fiber::ExecutionContext::GlobalQueue.new(Thread::Mutex.new)
      ready = Thread::WaitGroup.new(n)
      threads = Array(Thread).new(n)

      all_runnables = Array(Fiber::ExecutionContext::Runnables(16)).new(n) do
        Fiber::ExecutionContext::Runnables(16).new(global_queue)
      end

      n.times do |i|
        threads << new_thread("RUN-#{i}") do
          runnables = all_runnables[i]
          slept = 0

          execute = ->(fiber : Fiber) {
            fc = fibers.find { |x| x.@fiber == fiber }.not_nil!
            runnables.push(fiber) if fc.increment < increments
          }

          ready.done

          loop do
            # dequeue from local queue
            if fiber = runnables.shift?
              execute.call(fiber)
              slept = 0
              next
            end

            # steal from another queue
            while (r = all_runnables.sample) == runnables
            end
            if fiber = runnables.steal_from(r)
              execute.call(fiber)
              slept = 0
              next
            end

            # dequeue from global queue
            if fiber = global_queue.grab?(runnables, n)
              execute.call(fiber)
              slept = 0
              next
            end

            if slept >= 100
              break
            end

            slept += 1
            Thread.sleep(1.nanosecond) # don't burn CPU
          end
        end
      end
      ready.wait

      # enqueue in batches
      0.step(to: fibers.size - 1, by: 9) do |i|
        list = Fiber::List.new
        9.times { |j| list.push(fibers[i + j].@fiber) }
        global_queue.bulk_push(pointerof(list))
        Thread.sleep(10.nanoseconds) if i % 2 == 1
      end

      threads.map(&.join)

      # must have dequeued each fiber exactly X times (no less, no more)
      fibers.each { |fc| fc.counter.should eq(increments) }
    end
  end
end
