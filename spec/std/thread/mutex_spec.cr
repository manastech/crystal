require "../spec_helper"
require "../../support/thread"

# interpreter doesn't support threads yet (#14287)
pending_interpreted describe: Thread::Mutex do
  it "synchronizes" do
    a = 0
    mutex = Thread::Mutex.new

    threads = Array.new(10) do
      new_thread do
        mutex.synchronize { a += 1 }
      end
    end

    threads.each(&.join)
    a.should eq(10)
  end

  it "won't lock recursively" do
    mutex = Thread::Mutex.new
    mutex.try_lock.should be_true
    mutex.try_lock.should be_false
    expect_raises(RuntimeError) { mutex.lock }
    mutex.unlock
    new_thread { mutex.synchronize { } }.join
  end

  it "won't unlock from another thread" do
    mutex = Thread::Mutex.new
    mutex.lock

    expect_raises(RuntimeError) do
      new_thread { mutex.unlock }.join
    end

    mutex.unlock
  end
end
