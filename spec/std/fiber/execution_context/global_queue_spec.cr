require "./spec_helper"

describe Fiber::ExecutionContext::GlobalQueue do
  it "#initialize" do
    q = Fiber::ExecutionContext::GlobalQueue.new(Thread::Mutex.new)
    q.empty?.should be_true
  end

  it "#unsafe_push and #unsafe_pop" do
    f1 = new_fake_fiber("f1")
    f2 = new_fake_fiber("f2")
    f3 = new_fake_fiber("f3")

    q = Fiber::ExecutionContext::GlobalQueue.new(Thread::Mutex.new)
    q.unsafe_push(f1)
    q.size.should eq(1)

    q.unsafe_push(f2)
    q.unsafe_push(f3)
    q.size.should eq(3)

    q.unsafe_pop?.should be(f3)
    q.size.should eq(2)

    q.unsafe_pop?.should be(f2)
    q.unsafe_pop?.should be(f1)
    q.unsafe_pop?.should be_nil
    q.size.should eq(0)
    q.empty?.should be_true
  end

  describe "#unsafe_grab?" do
    it "can't grab from empty queue" do
      q = Fiber::ExecutionContext::GlobalQueue.new(Thread::Mutex.new)
      runnables = Fiber::ExecutionContext::Runnables(6).new(q)
      q.unsafe_grab?(runnables, 4).should be_nil
    end

    it "grabs fibers" do
      q = Fiber::ExecutionContext::GlobalQueue.new(Thread::Mutex.new)
      fibers = 10.times.map { |i| new_fake_fiber("f#{i}") }.to_a
      fibers.each { |f| q.unsafe_push(f) }

      runnables = Fiber::ExecutionContext::Runnables(6).new(q)
      fiber = q.unsafe_grab?(runnables, 4)

      # returned the last enqueued fiber
      fiber.should be(fibers[9])

      # enqueued the next 2 fibers
      runnables.size.should eq(2)
      runnables.shift?.should be(fibers[8])
      runnables.shift?.should be(fibers[7])

      # the remaining fibers are still there:
      6.downto(0).each do |i|
        q.unsafe_pop?.should be(fibers[i])
      end
    end

    it "can't grab more than available" do
      f = new_fake_fiber
      q = Fiber::ExecutionContext::GlobalQueue.new(Thread::Mutex.new)
      q.unsafe_push(f)

      # dequeues the unique fiber
      runnables = Fiber::ExecutionContext::Runnables(6).new(q)
      fiber = q.unsafe_grab?(runnables, 4)
      fiber.should be(f)

      # had nothing left to dequeue
      runnables.size.should eq(0)
    end

    it "clamps divisor to 1" do
      f = new_fake_fiber
      q = Fiber::ExecutionContext::GlobalQueue.new(Thread::Mutex.new)
      q.unsafe_push(f)

      # dequeues the unique fiber
      runnables = Fiber::ExecutionContext::Runnables(6).new(q)
      fiber = q.unsafe_grab?(runnables, 0)
      fiber.should be(f)

      # had nothing left to dequeue
      runnables.size.should eq(0)
    end
  end

  # interpreter doesn't support threads yet (#14287)
  pending_interpreted describe: "thread safety" do
    it "one by one" do
      fibers = StaticArray(Fiber::ExecutionContext::FiberCounter, 763).new do |i|
        Fiber::ExecutionContext::FiberCounter.new(new_fake_fiber("f#{i}"))
      end

      n = 7
      increments = 15
      queue = Fiber::ExecutionContext::GlobalQueue.new(Thread::Mutex.new)
      ready = Thread::WaitGroup.new(n)
      shutdown = Thread::WaitGroup.new(n)

      n.times do |i|
        Thread.new("ONE-#{i}") do |thread|
          slept = 0
          ready.done

          loop do
            if fiber = queue.pop?
              fc = fibers.find { |x| x.@fiber == fiber }.not_nil!
              queue.push(fiber) if fc.increment < increments
              slept = 0
            elsif slept < 100
              slept += 1
              Thread.sleep(1.nanosecond) # don't burn CPU
            else
              break
            end
          end
        rescue exception
          Crystal::System.print_error "\nthread: #{thread.name}: exception: #{exception}"
        ensure
          shutdown.done
        end
      end
      ready.wait

      fibers.each_with_index do |fc, i|
        queue.push(fc.@fiber)
        Thread.sleep(10.nanoseconds) if i % 10 == 9
      end

      shutdown.wait

      # must have dequeued each fiber exactly X times
      fibers.each { |fc| fc.counter.should eq(increments) }
    end

    it "bulk operations" do
      n = 7
      increments = 15

      fibers = StaticArray(Fiber::ExecutionContext::FiberCounter, 765).new do |i| # 765 can be divided by 3 and 5
        Fiber::ExecutionContext::FiberCounter.new(new_fake_fiber("f#{i}"))
      end

      queue = Fiber::ExecutionContext::GlobalQueue.new(Thread::Mutex.new)
      ready = Thread::WaitGroup.new(n)
      shutdown = Thread::WaitGroup.new(n)

      n.times do |i|
        Thread.new("BULK-#{i}") do |thread|
          slept = 0

          r = Fiber::ExecutionContext::Runnables(3).new(queue)

          batch = Fiber::List.new
          size = 0

          reenqueue = -> {
            if size > 0
              queue.bulk_push(pointerof(batch))
              names = [] of String?
              batch.each { |f| names << f.name }
              batch.clear
              size = 0
            end
          }

          execute = ->(fiber : Fiber) {
            fc = fibers.find { |x| x.@fiber == fiber }.not_nil!

            if fc.increment < increments
              batch.push(fc.@fiber)
              size += 1
            end
          }

          ready.done

          loop do
            if fiber = r.shift?
              execute.call(fiber)
              slept = 0
              next
            end

            if fiber = queue.grab?(r, 1)
              reenqueue.call
              execute.call(fiber)
              slept = 0
              next
            end

            if slept >= 100
              break
            end

            reenqueue.call
            slept += 1
            Thread.sleep(1.nanosecond) # don't burn CPU
          end
        rescue exception
          Crystal::System.print_error "\nthread #{thread.name} raised: #{exception}"
        ensure
          shutdown.done
        end
      end
      ready.wait

      # enqueue in batches of 5
      0.step(to: fibers.size - 1, by: 5) do |i|
        list = Fiber::List.new
        5.times { |j| list.push(fibers[i + j].@fiber) }
        queue.bulk_push(pointerof(list))
        Thread.sleep(10.nanoseconds) if i % 4 == 3
      end

      shutdown.wait

      # must have dequeued each fiber exactly X times (no less, no more)
      fibers.each { |fc| fc.counter.should eq(increments) }
    end
  end
end
