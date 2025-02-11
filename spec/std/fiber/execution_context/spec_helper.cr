require "../../spec_helper"
require "../../../support/fibers"
require "crystal/system/thread_wait_group"
require "fiber/execution_context/runnables"
require "fiber/execution_context/global_queue"

module Fiber::ExecutionContext
  class FiberCounter
    def initialize(@fiber : Fiber)
      @counter = Atomic(Int32).new(0)
    end

    # fetch and add
    def increment
      @counter.add(1, :relaxed) + 1
    end

    def counter
      @counter.get(:relaxed)
    end
  end
end
