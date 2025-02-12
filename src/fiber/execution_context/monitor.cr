module Fiber::ExecutionContext
  class Monitor
    struct Timer
      def initialize(@every : Time::Span)
        @last = Time.monotonic
      end

      def elapsed?(now)
        ret = @last + @every <= now
        @last = now if ret
        ret
      end
    end

    DEFAULT_EVERY                = 10.milliseconds
    DEFAULT_COLLECT_STACKS_EVERY = 5.seconds

    def initialize(
      @every = DEFAULT_EVERY,
      collect_stacks_every = DEFAULT_COLLECT_STACKS_EVERY,
    )
      @collect_stacks_timer = Timer.new(collect_stacks_every)

      # FIXME: should be an ExecutionContext::Isolated instead of bare Thread?
      # it might print to STDERR (requires evloop) for example; it may also
      # allocate memory, for example to raise an exception (gc can run in the
      # thread, running finalizers) which is probably not an issue.
      @thread = uninitialized Thread
      @thread = Thread.new(name: "SYSMON") { run_loop }
    end

    # TODO: slow parallelism: instead of actively trying to wakeup, which can be
    # expensive and a source of contention leading to waste more time than
    # running the enqueued fiber(s) directly, the monitor thread could check the
    # queues of MT schedulers and decide to start/wake threads, it could also
    # complain that a fiber has been asked to yield numerous times.
    #
    # TODO: detect schedulers that have been stuck running the same fiber since
    # the previous iteration (check current fiber & scheduler tick to avoid ABA
    # issues), then mark the fiber to trigger a cooperative yield, for example,
    # `Fiber.maybe_yield` could be called at potential cancellation points that
    # would otherwise not need to block now (IO, mutexes, schedulers, manually
    # called in loops, ...) which could lead fiber execution time be more fair.
    #
    # TODO: if an execution context didn't have the opportunity to run its
    # event-loop since the previous iteration, then the monitor thread may
    # choose to run it; it would avoid a set of fibers to always resume
    # themselves at the expense of pending events.
    #
    # TODO: run the GC on low application activity?
    private def run_loop : Nil
      every do |now|
        collect_stacks if @collect_stacks_timer.elapsed?(now)
      end
    end

    # Executes the block at exact intervals (depending on the OS scheduler
    # precision and overall OS load), without counting the time to execute the
    # block.
    #
    # OPTIMIZE: exponential backoff (and/or park) when all schedulers are
    # pending to reduce CPU usage; thread wake up would have to signal the
    # monitor thread.
    private def every(&)
      remaining = @every

      loop do
        Thread.sleep(remaining)
        now = Time.monotonic
        yield(now)
        remaining = (now + @every - Time.monotonic).clamp(Time::Span.zero..)
      rescue exception
        Crystal.print_error_buffered("BUG: %s#every crashed",
          self.class.name, exception: exception)
      end
    end

    # Iterates each ExecutionContext and collects unused Fiber stacks.
    #
    # OPTIMIZE: should maybe happen during GC collections (?)
    private def collect_stacks
      Crystal.trace :sched, "collect_stacks" do
        ExecutionContext.each(&.stack_pool?.try(&.collect))
      end
    end
  end
end
