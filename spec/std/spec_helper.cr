require "spec"
require "../support/tempfile"
require "../support/fibers"
require "../support/win32"
require "../support/wasm32"

def datapath(*components)
  File.join("spec", "std", "data", *components)
end

private class Witness
  @checked = false

  def check
    @checked = true
  end

  def checked?
    @checked
  end
end

def spawn_and_wait(before : Proc(_), file = __FILE__, line = __LINE__, &block)
  spawn_and_check(before, file, line) do |w|
    block.call
    w.check
  end
end

def spawn_and_check(before : Proc(_), file = __FILE__, line = __LINE__, &block : Witness -> _)
  done = Channel(Exception?).new
  w = Witness.new

  # State of the "before" filter:
  # 0 - not started
  # 1 - started
  # 2 - completed
  x = Atomic(Int32).new(0)

  before_fiber = spawn do
    x.set(1)

    # This is a workaround to ensure the "before" fiber
    # is unscheduled. Otherwise it might stay alive running the event loop
    spawn(same_thread: true) do
      while x.get != 2
        Fiber.yield
      end
    end

    before.call
    x.set(2)
  end

  spawn do
    begin
      # Wait until the "before" fiber starts
      while x.get == 0
        Fiber.yield
      end

      # Now wait until the "before" fiber is blocked
      wait_until_blocked before_fiber
      block.call w

      done.send nil
    rescue e
      done.send e
    end
  end

  ex = done.receive
  raise ex if ex
  unless w.checked?
    fail "Failed to stress expected path", file, line
  end
end

def compile_file(source_file, *, bin_name = "executable_file", flags = %w(), file = __FILE__, &)
  with_temp_executable(bin_name, file: file) do |executable_file|
    compiler = ENV["CRYSTAL_SPEC_COMPILER_BIN"]? || "bin/crystal"
    args = ["build"] + flags + ["-o", executable_file, source_file]
    output = IO::Memory.new
    status = Process.run(compiler, args, env: {
      "CRYSTAL_PATH"          => Crystal::PATH,
      "CRYSTAL_LIBRARY_PATH"  => Crystal::LIBRARY_PATH,
      "CRYSTAL_LIBRARY_RPATH" => Crystal::LIBRARY_RPATH,
      "CRYSTAL_CACHE_DIR"     => Crystal::CACHE_DIR,
    }, output: output, error: output)

    unless status.success?
      fail "Compiler command `#{compiler} #{args.join(" ")}` failed with status #{status}.#{"\n" if output}#{output}"
    end

    File.exists?(executable_file).should be_true

    yield executable_file
  end
end

def compile_source(source, flags = %w(), file = __FILE__, &)
  with_tempfile("source_file", file: file) do |source_file|
    File.write(source_file, source)
    compile_file(source_file, flags: flags, file: file) do |executable_file|
      yield executable_file
    end
  end
end

def compile_and_run_file(source_file, flags = %w(), runtime_args = %w(), file = __FILE__)
  status, output, error = Process::Status.new(0), IO::Memory.new, IO::Memory.new
  {% if flag?(:interpreted) %}
    compiler = ENV["CRYSTAL_SPEC_COMPILER_BIN"]? || "bin/crystal"
    args = ["i", source_file, "--", *runtime_args]
    status = Process.run compiler, args: args, output: output, error: error
  {% else %}
    compile_file(source_file, flags: flags, file: file) do |executable_file|
      status = Process.run executable_file, args: runtime_args, output: output, error: error
    end
  {% end %}
  {status, output.to_s, error.to_s}
end

def compile_and_run_source(source, flags = %w(), runtime_args = %w(), file = __FILE__)
  with_tempfile("source_file", file: file) do |source_file|
    File.write(source_file, source)
    compile_and_run_file(source_file, flags, runtime_args, file: file)
  end
end

def compile_and_run_source_with_c(c_code, crystal_code, flags = %w(--debug), file = __FILE__, &)
  with_temp_c_object_file(c_code, file: file) do |o_filename|
    yield compile_and_run_source(%(
    require "prelude"

    @[Link(ldflags: #{o_filename.inspect})]
    #{crystal_code}
    ))
  end
end
