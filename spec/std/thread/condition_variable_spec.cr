require "../spec_helper"
require "../../support/thread"

# interpreter doesn't support threads yet (#14287)
pending_interpreted describe: Thread::ConditionVariable do
  it "signals" do
    mutex = Thread::Mutex.new
    cond = Thread::ConditionVariable.new

    mutex.synchronize do
      new_thread do
        mutex.synchronize { cond.signal }
      end

      cond.wait(mutex)
    end
  end

  it "signals & broadcasts" do
    mutex = Thread::Mutex.new
    cv1 = Thread::ConditionVariable.new
    cv2 = Thread::ConditionVariable.new
    waiting = 0

    5.times do
      new_thread do
        mutex.synchronize do
          waiting += 1
          cv1.wait(mutex)

          waiting -= 1
          cv2.signal
        end
      end
    end

    # wait for all threads to have acquired the mutex and be waiting on the
    # condition variable, otherwise the main thread could acquire the lock
    # first, and signal into the void.
    #
    # since increments to waiting are synchronized, at least 4 threads are
    # guaranteed to be waiting when waiting is 5, which is enough for further
    # tests to never hangup.
    until waiting == 5
      Thread.yield
    end

    # wakes up at least 1 thread:
    mutex.synchronize do
      cv1.signal
      cv2.wait(mutex)
    end
    waiting.should be < 5

    # wakes up all waiting threads:
    mutex.synchronize do
      cv1.broadcast

      until waiting == 0
        cv2.wait(mutex, 1.second) { raise "unexpected wait timeout" }
      end
    end
  end

  it "timeouts" do
    timedout = false
    mutex = Thread::Mutex.new
    cond = Thread::ConditionVariable.new

    mutex.synchronize do
      cond.wait(mutex, 1.microsecond) { timedout = true }
    end
    timedout.should be_true
  end

  it "resumes before timeout" do
    timedout = false
    mutex = Thread::Mutex.new
    cond = Thread::ConditionVariable.new

    mutex.synchronize do
      new_thread do
        mutex.synchronize { cond.signal }
      end

      cond.wait(mutex, 1.second) { timedout = true }
    end

    timedout.should be_false
  end
end
