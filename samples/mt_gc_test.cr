# Experiment to stress the GC with multi-threading.
# The experiment manually allocates multiple times a queue of fibers
# on a list of worker threads. The main thread does the orchestration.
# The fibers will grow and shrink their stack size by doing recursion.
# In each level of the stack an amount of dummy objects are allocated.
# These objects will be released by the GC eventually.

require "option_parser"
require "benchmark"

lib LibC
  fun fflush(b : Void*)
end

class Foo
  @@collections = Atomic(Int32).new(0)

  @data = StaticArray(Int32, 8).new(0)

  def finalize
    @@collections.add(1)
  end

  def self.collections
    @@collections.get
  end
end

class Context
  enum State
    Wait
    Run
  end

  property expected_depth : Int32 = 0
  @worker_fibers = Array(Fiber).new(0)

  def initialize(@fibers : Int32, @threads : Int32, @log : Bool)
    @fibers_reached = Atomic(Int32).new(0)
    @threads_reached = Atomic(Int32).new(0)
    @fiber_depths = Array(Int32).new(@fibers, 0)
    @pending_fibers_queues = Array(Array(Fiber)).new(@threads) { Array(Fiber).new }
    @threads_state = Atomic(State).new(State::Wait)

    # Create worker fibers but do not start them yet.
    # Each fiber will try to reach the `expected_depth` value
    # by increasing or decreasing its callstack.
    @fibers.times do |index|
      @worker_fibers << Fiber.new("f:#{index}") do
        Context.fiber_run(self, index, 1)
      end
    end

    # Create worker threads.
    # they will perform operations when `@threads_state == :run`
    # otherwise they will remain in a tight busy loop.
    # See Context#create_thread
    @threads.times { |index| create_thread(index) }
  end

  def self.fiber_run(context, fiber_index, depth)
    context.set_fiber_depth(fiber_index, depth)

    # allocate a bunch of objects in the stack
    # some should be released fast
    10.times do
      foo = Foo.new
    end
    foo = Foo.new

    # increase/decrease stack depending on the expected_depth
    # when reached, notify and yield control
    while true
      if context.expected_depth < depth
        return
      elsif context.expected_depth > depth
        fiber_run(context, fiber_index, depth + 1)
      else
        context.notify_depth_reached
        context.yield
      end
    end
  end

  def set_fiber_depth(index, depth)
    @fiber_depths[index] = depth
  end

  def run_until_depth(phase, depth)
    # make all fibers reach a specific depth
    log "#{phase}: expected_depth: #{depth}"

    @expected_depth = depth
    @fibers_reached.set(0)
    @threads_reached.set(0)

    # allocate fibers on each thread queue.
    @pending_fibers_queues.each &.clear
    @worker_fibers.dup.shuffle!.each_with_index do |f, index|
      @pending_fibers_queues[index % @threads] << f
    end

    @threads_state.set(State::Run)

    # spin wait for all fibers to finish
    while @fibers_reached.get < @fibers
    end
    log "All fibers_reached!"

    @threads_state.set(State::Wait)

    # spin wait for threads to finish the round
    while @threads_reached.get < @threads
    end
    log "All threads_reached!"
  end

  def notify_depth_reached
    @fibers_reached.add(1)
  end

  def yield
    Thread.current.main_fiber.resume
  end

  def pick_and_resume_fiber(queue_index)
    fiber = @pending_fibers_queues[queue_index].shift?

    if fiber
      fiber.resume
      true
    else
      false
    end
  end

  def gc_stats
    log "GC.stats: #{GC.stats}"
    log "Foo.collections: #{Foo.collections}"
  end

  def create_thread(queue_index)
    Thread.new do
      # this loop will iterate once per #run_until_depth
      while true
        # wait for queues to be ready
        while @threads_state.get != State::Run
        end

        # consume the queue until empty
        while pick_and_resume_fiber(queue_index)
        end

        # wait for all worker threads to finish
        while @threads_state.get != State::Wait
        end

        # sync all workers threads end of loop
        @threads_reached.add(1)
      end
    end
  end

  def log(s)
    if @log
      t = Thread.current.to_s rescue "Unknown"
      f = Fiber.current.to_s rescue "Unknown"
      LibC.printf("%s::%s >>> %s\n", t, f, s)
      LibC.fflush(nil)
    end
    s
  end
end

def run(threads_num, fibers_num, loops_num, log)
  # Specify the number of fibers and threads to use
  context = Context.new(fibers: fibers_num, threads: threads_num, log: log)

  (1..loops_num).each do |i|
    context.run_until_depth "Phase #{i}.1", 40
    context.run_until_depth "Phase #{i}.2", 5

    context.gc_stats

    context.run_until_depth "Phase #{i}.3", 50
    context.run_until_depth "Phase #{i}.4", 5

    context.gc_stats

    context.run_until_depth "Phase #{i}.5", 10

    context.gc_stats
  end

  context.log "Done"
end

enum Mode
  Run
  Ips
  Measure
end

threads_num = 4
fibers_num = 1_000
loops_num = 20
mode = Mode::Run

OptionParser.parse do |parser|
  parser.on("-i", "--ips", "Benchmark with ips") { mode = Mode::Ips }
  parser.on("-m", "--measure", "Benchmark with measure") { mode = Mode::Measure }
  parser.on("-f FIBERS", "--fibers=FIBERS", "Specifies the number of fibers") { |v| fibers_num = v.to_i }
  parser.on("-t THREADS", "--threads=THREADS", "Specifies the number of threads") { |v| threads_num = v.to_i }
  parser.on("-l LOOPS", "--loops=LOOPS", "Specifies the number of loops") { |v| loops_num = v.to_i }
  parser.on("-h", "--help", "Show this help") {
    puts parser
    exit(0)
  }
  parser.invalid_option do |flag|
    STDERR.puts "ERROR: #{flag} is not a valid option."
    STDERR.puts parser
    exit(1)
  end
end

case mode
when .run?
  run(threads_num, fibers_num, loops_num, true)
when .ips?
  Benchmark.ips do |x|
    x.report("run") { run(threads_num, fibers_num, loops_num, false) }
  end
when .measure?
  puts Benchmark.measure { run(threads_num, fibers_num, loops_num, false) }
end
