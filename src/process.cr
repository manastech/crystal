require "crystal/system/process"

class Process
  # Terminate the current process immediately. All open files, pipes and sockets
  # are flushed and closed, all child processes are inherited by PID 1. This does
  # not run any handlers registered with `at_exit`, use `::exit` for that.
  #
  # *status* is the exit status of the current process.
  def self.exit(status = 0) : NoReturn
    exit_system(status)
  end

  # Returns the process identifier of the current process.
  def self.pid : Int64
    pid_system
  end

  {% if flag?(:unix) || flag?(:docs) %}
    # Returns the process group identifier of the current process.
    def self.pgid : Int64
      pgid(0)
    end

    # Returns the process group identifier of the process identified by *pid*.
    def self.pgid(pid : Int64) : Int64
      Process.pgid_system(pid)
    end
  {% end %}

  # Returns the process identifier of the parent process of the current process.
  def self.ppid : Int64
    ppid_system
  end

  # Sends a *signal* to the processes identified by the given *pids*.
  def self.kill(signal : Signal, *pids : Int64) : Nil
    pids.each do |pid|
      Process.new(pid).kill(signal)
    end
  end

  # Returns `true` if the process identified by *pid* is valid for
  # a currently registered process, `false` otherwise. Note that this
  # returns `true` for a process in the zombie or similar state.
  def self.exists?(pid : Int) : Bool
    Process.exists_system?(pid)
  end

  # A struct representing the CPU current times of the process,
  # in fractions of seconds.
  #
  # * *utime*: CPU time a process spent in userland.
  # * *stime*: CPU time a process spent in the kernel.
  # * *cutime*: CPU time a processes terminated children (and their terminated children) spent in the userland.
  # * *cstime*: CPU time a processes terminated children (and their terminated children) spent in the kernel.
  record Tms, utime : Float64, stime : Float64, cutime : Float64, cstime : Float64

  # Returns a `Tms` for the current process. For the children times, only those
  # of terminated children are returned.
  def self.times : Tms
    times_system
  end

  {% if flag?(:unix) || flag?(:docs) %}
    # Runs the given block inside a new process and
    # returns a `Process` representing the new child process.
    #
    # Available only on Unix-like operating systems.
    def self.fork : Process
      fork_system { yield }
    end

    # Duplicates the current process.
    # Returns a `Process` representing the new child process in the current process
    # and `nil` inside the new child process.
    #
    # Available only on Unix-like operating systems.
    def self.fork : Process?
      fork_system
    end
  {% end %}

  # How to redirect the standard input, output and error IO of a process.
  enum Redirect
    # Pipe the IO so the parent process can read (or write) to the process IO
    # through `#input`, `#output` or `#error`.
    Pipe

    # Discards the IO.
    Close

    # Use the IO of the parent process.
    Inherit
  end

  # The standard `IO` configuration of a process.
  alias Stdio = Redirect | IO
  alias ExecStdio = Redirect | IO::FileDescriptor
  alias Env = Nil | Hash(String, Nil) | Hash(String, String?) | Hash(String, String)

  # Executes a process and waits for it to complete.
  #
  # By default the process is configured without input, output or error.
  def self.run(command : String, args = nil, env : Env = nil, clear_env : Bool = false, shell : Bool = false,
               input : Stdio = Redirect::Close, output : Stdio = Redirect::Close, error : Stdio = Redirect::Close, chdir : String? = nil) : Process::Status
    status = new(command, args, env, clear_env, shell, input, output, error, chdir).wait
    $? = status
    status
  end

  # Executes a process, yields the block, and then waits for it to finish.
  #
  # By default the process is configured to use pipes for input, output and error. These
  # will be closed automatically at the end of the block.
  #
  # Returns the block's value.
  def self.run(command : String, args = nil, env : Env = nil, clear_env : Bool = false, shell : Bool = false,
               input : Stdio = Redirect::Pipe, output : Stdio = Redirect::Pipe, error : Stdio = Redirect::Pipe, chdir : String? = nil, &block : Process ->)
    process = new(command, args, env, clear_env, shell, input, output, error, chdir)
    begin
      value = yield process
      $? = process.wait
      value
    rescue ex
      process.terminate
      raise ex
    end
  end

  # Replaces the current process with a new one. This function never returns.
  def self.exec(command : String, args = nil, env : Env = nil, clear_env : Bool = false, shell : Bool = false,
                input : ExecStdio = Redirect::Inherit, output : ExecStdio = Redirect::Inherit, error : ExecStdio = Redirect::Inherit, chdir : String? = nil)
    command, args = prepare_args(command, args, shell)

    input = exec_stdio_to_fd(input, for: STDIN)
    output = exec_stdio_to_fd(output, for: STDOUT)
    error = exec_stdio_to_fd(error, for: STDERR)

    exec_internal(command, args, env, clear_env, input, output, error, chdir)
  end

  private def self.exec_stdio_to_fd(stdio : ExecStdio, for dst_io : IO::FileDescriptor) : IO::FileDescriptor
    case stdio
    when IO::FileDescriptor
      stdio
    when Redirect::Pipe
      raise "Cannot use Process::Redirect::Pipe for Process.exec"
    when Redirect::Inherit
      dst_io
    when Redirect::Close
      if dst_io == STDIN
        File.open(File::NULL, "r")
      else
        File.open(File::NULL, "w")
      end
    else
      raise "BUG: impossible type in ExecStdio #{stdio.class}"
    end
  end

  getter pid : Int64 = 0

  # A pipe to this process's input. Raises if a pipe wasn't asked when creating the process.
  getter! input : IO::FileDescriptor

  # A pipe to this process's output. Raises if a pipe wasn't asked when creating the process.
  getter! output : IO::FileDescriptor

  # A pipe to this process's error. Raises if a pipe wasn't asked when creating the process.
  getter! error : IO::FileDescriptor

  # channel of process exit code
  @waitpid : Channel(Int32) = Channel(Int32).new(1)
  @wait_count = 0

  # Creates a process, executes it, but doesn't wait for it to complete.
  #
  # To wait for it to finish, invoke `wait`.
  #
  # By default the process is configured without input, output or error.
  def initialize(command : String, args = nil, env : Env = nil, clear_env : Bool = false, shell : Bool = false,
                 input : Stdio = Redirect::Close, output : Stdio = Redirect::Close, error : Stdio = Redirect::Close, chdir : String? = nil)
    command, args = Process.prepare_args(command, args, shell)

    fork_input = stdio_to_fd(input, for: STDIN)
    fork_output = stdio_to_fd(output, for: STDOUT)
    fork_error = stdio_to_fd(error, for: STDERR)

    @pid = create_and_exec(command, args, env, clear_env, fork_input, fork_output, fork_error, chdir)
    @waitpid = wait_system
    fork_input.close unless fork_input == input || fork_input == STDIN
    fork_output.close unless fork_output == output || fork_output == STDOUT
    fork_error.close unless fork_error == error || fork_error == STDERR
  end

  private def stdio_to_fd(stdio : Stdio, for dst_io : IO::FileDescriptor) : IO::FileDescriptor
    case stdio
    when IO::FileDescriptor
      stdio
    when IO
      if dst_io == STDIN
        fork_io, process_io = IO.pipe(read_blocking: true)

        @wait_count += 1
        ensure_channel
        spawn { copy_io(stdio, process_io, channel, close_dst: true) }
      else
        process_io, fork_io = IO.pipe(write_blocking: true)

        @wait_count += 1
        ensure_channel
        spawn { copy_io(process_io, stdio, channel, close_src: true) }
      end

      fork_io
    when Redirect::Pipe
      case dst_io
      when STDIN
        fork_io, @input = IO.pipe(read_blocking: true)
      when STDOUT
        @output, fork_io = IO.pipe(write_blocking: true)
      when STDERR
        @error, fork_io = IO.pipe(write_blocking: true)
      else
        raise "BUG: unknown destination io #{dst_io}"
      end

      fork_io
    when Redirect::Inherit
      dst_io
    when Redirect::Close
      if dst_io == STDIN
        File.open(File::NULL, "r")
      else
        File.open(File::NULL, "w")
      end
    else
      raise "BUG: impossible type in stdio #{stdio.class}"
    end
  end

  protected def initialize(@pid)
    wait_system
    @wait_count = 0
  end

  # See also: `Process.kill`
  def kill(sig = Signal::TERM)
    signal_system sig
  end

  # Waits for this process to complete and closes any pipes.
  def wait : Process::Status
    close_io @input # only closed when a pipe was created but not managed by copy_io
    @wait_count.times do
      ex = channel.receive
      raise ex if ex
    end
    @wait_count = 0
    Process::Status.new(@waitpid.receive)
  ensure
    close
  end

  # Whether the process is still registered in the system.
  # Note that this returns `true` for processes in the zombie or similar state.
  def exists?
    !terminated?
  end

  # Whether this process is already terminated.
  def terminated?
    @waitpid.closed? || !exists_system?
  end

  # Closes any system resources held for the process.
  def close
    close_io
    close_system
  end

  # Closes any pipes to the child process.
  def close_io
    close_io @input
    close_io @output
    close_io @error
  end

  # :nodoc:
  protected def self.prepare_args(command : String, args, shell)
    if shell
      prepare_shell_system(command, args)
    else
      {command, args}
    end
  end

  private def channel
    if channel = @channel
      channel
    else
      raise "BUG: Notification channel was not initialized for this process"
    end
  end

  private def ensure_channel
    @channel ||= Channel(Exception?).new
  end

  private def needs_pipe?(io)
    (io == Redirect::Pipe) || (io.is_a?(IO) && !io.is_a?(IO::FileDescriptor))
  end

  private def copy_io(src, dst, channel, close_src = false, close_dst = false)
    return unless src.is_a?(IO) && dst.is_a?(IO)

    begin
      IO.copy(src, dst)

      # close is called here to trigger exceptions
      # close must be called before channel.send or the process may deadlock
      src.close if close_src
      close_src = false
      dst.close if close_dst
      close_dst = false

      channel.send nil
    rescue ex
      channel.send ex
    ensure
      # any exceptions are silently ignored because of spawn
      src.close if close_src
      dst.close if close_dst
    end
  end

  private def close_io(io)
    io.close if io
  end

  {% if flag?(:unix) || flag?(:docs) %}
    # Changes the root directory and the current working directory for the current
    # process.
    #
    # Available only on Unix-like operating systems.
    #
    # Security: `chroot` on its own is not an effective means of mitigation. At minimum
    # the process needs to also drop privileges as soon as feasible after the `chroot`.
    # Changes to the directory hierarchy or file descriptors passed via `recvmsg(2)` from
    # outside the `chroot` jail may allow a restricted process to escape, even if it is
    # unprivileged.
    #
    # ```
    # Process.chroot("/var/empty")
    # ```
    def self.chroot(path : String) : Nil
      chroot_system(path)
    end
  {% end %}
end

# Executes the given command in a subshell.
# Standard input, output and error are inherited.
# Returns `true` if the command gives zero exit code, `false` otherwise.
# The special `$?` variable is set to a `Process::Status` associated with this execution.
#
# If *command* contains no spaces and *args* is given, it will become
# its argument list.
#
# If *command* contains spaces and *args* is given, *command* must include
# `"${@}"` (including the quotes) to receive the argument list.
#
# No shell interpretation is done in *args*.
#
# Example:
#
# ```
# system("echo *")
# ```
#
# Produces:
#
# ```text
# LICENSE shard.yml Readme.md spec src
# ```
def system(command : String, args = nil) : Bool
  status = Process.run(command, args, shell: true, input: Process::Redirect::Inherit, output: Process::Redirect::Inherit, error: Process::Redirect::Inherit)
  $? = status
  status.success?
end

# Returns the standard output of executing *command* in a subshell.
# Standard input, and error are inherited.
# The special `$?` variable is set to a `Process::Status` associated with this execution.
#
# Example:
#
# ```
# `echo hi` # => "hi\n"
# ```
def `(command) : String
  process = Process.new(command, shell: true, input: Process::Redirect::Inherit, output: Process::Redirect::Pipe, error: Process::Redirect::Inherit)
  output = process.output.gets_to_end
  status = process.wait
  $? = status
  output
end

{% if flag?(:unix) || flag?(:docs) %}
  # See also: `Process.fork`
  #
  # Available only on Unix-like operating systems.
  def fork
    ::Process.fork { yield }
  end

  # See also: `Process.fork`
  #
  # Available only on Unix-like operating systems.
  def fork
    ::Process.fork
  end
{% end %}

require "./process/*"
