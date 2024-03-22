require "c/signal"
require "c/stdlib"
require "c/sys/resource"
require "c/unistd"
require "file/error"

struct Crystal::System::Process
  getter pid : LibC::PidT

  def initialize(@pid : LibC::PidT)
    @channel = Crystal::System::SignalChildHandler.wait(@pid)
  end

  def release
  end

  def wait
    {% if flag?(:interpreted) %}
      exit_code = uninitialized Int32
      loop do
        r_pid = LibC.waitpid(pid, pointerof(exit_code), LibC::WNOHANG)
        case r_pid
        when 0
          sleep 1
        when -1
          raise RuntimeError.from_errno("waitpid") unless Errno.value == Errno::ECHILD
          sleep 1
        else
          break
        end
      end

      @channel.send(exit_code)
      @channel.close
    {% end %}
    @channel.receive
  end

  def exists?
    !@channel.closed? && Crystal::System::Process.exists?(@pid)
  end

  def terminate(*, graceful)
    Crystal::System::Process.signal(@pid, graceful ? LibC::SIGTERM : LibC::SIGKILL)
  end

  def self.exit(status)
    LibC.exit(status)
  end

  def self.pid
    LibC.getpid
  end

  def self.pgid
    ret = LibC.getpgid(0)
    raise RuntimeError.from_errno("getpgid") if ret < 0
    ret
  end

  def self.pgid(pid)
    # Disallow users from depending on ppid(0) instead of `pgid`
    raise RuntimeError.from_os_error("getpgid", Errno::EINVAL) if pid == 0

    ret = LibC.getpgid(pid)
    raise RuntimeError.from_errno("getpgid") if ret < 0
    ret
  end

  def self.ppid
    LibC.getppid
  end

  def self.signal(pid, signal)
    ret = LibC.kill(pid, signal)
    raise RuntimeError.from_errno("kill") if ret < 0
  end

  @[Deprecated("Use `#on_terminate` instead")]
  def self.on_interrupt(&handler : ->) : Nil
    ::Signal::INT.trap { |_signal| handler.call }
  end

  def self.on_terminate(&handler : ::Process::ExitReason ->) : Nil
    sig_handler = Proc(::Signal, Nil).new do |signal|
      int_type = case signal
                 when .int?
                   ::Process::ExitReason::Interrupted
                 when .hup?
                   ::Process::ExitReason::TerminalDisconnected
                 when .term?
                   ::Process::ExitReason::SessionEnded
                 else
                   ::Process::ExitReason::Interrupted
                 end
      handler.call int_type

      # ignore prevents system defaults and clears registered interrupts
      # hence we need to re-register
      signal.ignore
      Process.on_terminate &handler
    end
    ::Signal::INT.trap &sig_handler
    ::Signal::HUP.trap &sig_handler
    ::Signal::TERM.trap &sig_handler
  end

  def self.ignore_interrupts! : Nil
    ::Signal::INT.ignore
  end

  def self.restore_interrupts! : Nil
    ::Signal::INT.reset
  end

  def self.start_interrupt_loop : Nil
    # do nothing; `Crystal::System::Signal.start_loop` takes care of this
  end

  def self.exists?(pid)
    ret = LibC.kill(pid, 0)
    if ret == 0
      true
    else
      case Errno.value
      when Errno::EPERM
        true
      when Errno::ESRCH
        false
      else
        raise RuntimeError.from_errno("kill")
      end
    end
  end

  def self.times
    LibC.getrusage(LibC::RUSAGE_SELF, out usage)
    LibC.getrusage(LibC::RUSAGE_CHILDREN, out child)

    ::Process::Tms.new(
      usage.ru_utime.tv_sec.to_f64 + usage.ru_utime.tv_usec.to_f64 / 1e6,
      usage.ru_stime.tv_sec.to_f64 + usage.ru_stime.tv_usec.to_f64 / 1e6,
      child.ru_utime.tv_sec.to_f64 + child.ru_utime.tv_usec.to_f64 / 1e6,
      child.ru_stime.tv_sec.to_f64 + child.ru_stime.tv_usec.to_f64 / 1e6,
    )
  end

  def self.fork(*, will_exec = false)
    newmask = uninitialized LibC::SigsetT
    oldmask = uninitialized LibC::SigsetT

    LibC.sigfillset(pointerof(newmask))
    ret = LibC.pthread_sigmask(LibC::SIG_SETMASK, pointerof(newmask), pointerof(oldmask))
    raise RuntimeError.from_errno("Failed to disable signals") unless ret == 0

    case pid = LibC.fork
    when 0
      # child:
      pid = nil
      if will_exec
        # reset signal handlers, then sigmask (inherited on exec):
        Crystal::System::Signal.after_fork_before_exec
        LibC.sigemptyset(pointerof(newmask))
        LibC.pthread_sigmask(LibC::SIG_SETMASK, pointerof(newmask), nil)
      else
        {% unless flag?(:preview_mt) %}
          ::Process.after_fork_child_callbacks.each(&.call)
        {% end %}
        LibC.pthread_sigmask(LibC::SIG_SETMASK, pointerof(oldmask), nil)
      end
    when -1
      # error:
      errno = Errno.value
      LibC.pthread_sigmask(LibC::SIG_SETMASK, pointerof(oldmask), nil)
      raise RuntimeError.from_os_error("fork", errno)
    else
      # parent:
      LibC.pthread_sigmask(LibC::SIG_SETMASK, pointerof(oldmask), nil)
    end

    pid
  end

  # Duplicates the current process.
  # Returns a `Process` representing the new child process in the current process
  # and `nil` inside the new child process.
  def self.fork(&)
    {% raise("Process fork is unsupported with multithreaded mode") if flag?(:preview_mt) %}

    if pid = fork
      return pid
    end

    begin
      yield
      LibC._exit 0
    rescue ex
      ex.inspect_with_backtrace STDERR
      STDERR.flush
      LibC._exit 1
    ensure
      LibC._exit 254 # not reached
    end
  end

  def self.spawn(command_args, env, clear_env, input, output, error, chdir)
    reader_pipe, writer_pipe = IO.pipe

    pid = self.fork(will_exec: true)
    if !pid
      begin
        reader_pipe.close
        writer_pipe.close_on_exec = true
        self.try_replace(command_args, env, clear_env, input, output, error, chdir)
        writer_pipe.write_byte(1)
        writer_pipe.write_bytes(Errno.value.to_i)
      rescue ex
        writer_pipe.write_byte(0)
        writer_pipe.write_bytes(ex.message.try(&.bytesize) || 0)
        writer_pipe << ex.message
        writer_pipe.close
      ensure
        LibC._exit 127
      end
    end

    writer_pipe.close
    begin
      case reader_pipe.read_byte
      when nil
        # Pipe was closed, no error
      when 0
        # Error message coming
        message_size = reader_pipe.read_bytes(Int32)
        if message_size > 0
          message = String.build(message_size) { |io| IO.copy(reader_pipe, io, message_size) }
        end
        reader_pipe.close
        raise RuntimeError.new("Error executing process: '#{command_args[0]}': #{message}")
      when 1
        # Errno coming
        errno = Errno.new(reader_pipe.read_bytes(Int32))
        self.raise_exception_from_errno(command_args[0], errno)
      else
        raise RuntimeError.new("BUG: Invalid error response received from subprocess")
      end
    ensure
      reader_pipe.close
    end

    pid
  end

  def self.prepare_args(command : String, args : Enumerable(String)?, shell : Bool) : Array(String)
    if shell
      command = %(#{command} "${@}") unless command.includes?(' ')
      shell_args = ["/bin/sh", "-c", command, "sh"]

      if args
        unless command.includes?(%("${@}"))
          raise ArgumentError.new(%(Can't specify arguments in both command and args without including "${@}" into your command))
        end

        shell_args.concat(args)
      end

      shell_args
    else
      command_args = [command]
      command_args.concat(args) if args
      command_args
    end
  end

  private def self.try_replace(command_args, env, clear_env, input, output, error, chdir)
    reopen_io(input, ORIGINAL_STDIN)
    reopen_io(output, ORIGINAL_STDOUT)
    reopen_io(error, ORIGINAL_STDERR)

    ENV.clear if clear_env
    env.try &.each do |key, val|
      if val
        ENV[key] = val
      else
        ENV.delete key
      end
    end

    ::Dir.cd(chdir) if chdir

    command = command_args[0]
    argv = command_args.map &.check_no_null_byte.to_unsafe
    argv << Pointer(UInt8).null

    LibC.execvp(command, argv)
  end

  def self.replace(command_args, env, clear_env, input, output, error, chdir)
    try_replace(command_args, env, clear_env, input, output, error, chdir)
    raise_exception_from_errno(command_args[0])
  end

  private def self.raise_exception_from_errno(command, errno = Errno.value)
    case errno
    when Errno::EACCES, Errno::ENOENT, Errno::ENOEXEC
      raise ::File::Error.from_os_error("Error executing process", errno, file: command)
    else
      raise IO::Error.from_os_error("Error executing process: '#{command}'", errno)
    end
  end

  private def self.reopen_io(src_io : IO::FileDescriptor, dst_io : IO::FileDescriptor)
    src_io = to_real_fd(src_io)

    dst_io.reopen(src_io)
    dst_io.blocking = true
    dst_io.close_on_exec = false
  end

  private def self.to_real_fd(fd : IO::FileDescriptor)
    case fd
    when STDIN  then ORIGINAL_STDIN
    when STDOUT then ORIGINAL_STDOUT
    when STDERR then ORIGINAL_STDERR
    else             fd
    end
  end

  def self.chroot(path)
    path.check_no_null_byte
    if LibC.chroot(path) != 0
      raise RuntimeError.from_errno("Failed to chroot")
    end

    if LibC.chdir("/") != 0
      errno = RuntimeError.from_errno("chdir after chroot failed")
      errno.callstack = Exception::CallStack.new
      errno.inspect_with_backtrace(STDERR)
      abort("Unresolvable state, exiting...")
    end
  end
end
