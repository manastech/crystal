{% if flag?(:win32) %}
  require "c/ntstatus"
{% end %}

# The reason why a process terminated.
#
# This enum provides a platform-independent way to query any exceptions that
# occurred upon a process's termination, via `Process::Status#exit_reason`.
enum Process::ExitReason
  # The process exited normally.
  #
  # * On Unix-like systems, this implies `Process::Status#normal_exit?` is true.
  # * On Windows, only exit statuses less than `0x40000000` are assumed to be
  #   reserved for normal exits.
  Normal

  # The process terminated due to an abort request.
  #
  # * On Unix-like systems, this corresponds to `Signal::ABRT`, `Signal::KILL`,
  #   and `Signal::QUIT`.
  # * On Windows, this corresponds to the `NTSTATUS` value
  #   `STATUS_FATAL_APP_EXIT`.
  Aborted

  # The process exited due to an interrupt request.
  #
  # * On Unix-like systems, this corresponds to `Signal::INT`.
  # * On Windows, this corresponds to the <kbd>Ctrl</kbd> + <kbd>C</kbd> and
  #   <kbd>Ctrl</kbd> + <kbd>Break</kbd> signals for console applications.
  Interrupted

  # The process reached a debugger breakpoint, but no debugger was attached.
  #
  # * On Unix-like systems, this corresponds to `Signal::TRAP`.
  # * On Windows, this corresponds to the `NTSTATUS` value
  #   `STATUS_BREAKPOINT`.
  Breakpoint

  # The process tried to access a memory address where a read or write was not
  # allowed.
  #
  # * On Unix-like systems, this corresponds to `Signal::SEGV`.
  # * On Windows, this corresponds to the `NTSTATUS` values
  #   `STATUS_ACCESS_VIOLATION` and `STATUS_STACK_OVERFLOW`.
  AccessViolation

  # The process tried to access an invalid memory address.
  #
  # * On Unix-like systems, this corresponds to `Signal::BUS`.
  # * On Windows, this corresponds to the `NTSTATUS` value
  #   `STATUS_DATATYPE_MISALIGNMENT`.
  BadMemoryAccess

  # The process tried to execute an invalid instruction.
  #
  # * On Unix-like systems, this corresponds to `Signal::ILL`.
  # * On Windows, this corresponds to the `NTSTATUS` values
  #   `STATUS_ILLEGAL_INSTRUCTION` and `STATUS_PRIVILEGED_INSTRUCTION`.
  BadInstruction

  # A hardware floating-point exception occurred.
  #
  # * On Unix-like systems, this corresponds to `Signal::FPE`.
  # * On Windows, this corresponds to the `NTSTATUS` values
  #   `STATUS_FLOAT_DIVIDE_BY_ZERO`, `STATUS_FLOAT_INEXACT_RESULT`,
  #   `STATUS_FLOAT_INVALID_OPERATION`, `STATUS_FLOAT_OVERFLOW`, and
  #   `STATUS_FLOAT_UNDERFLOW`.
  FloatException

  # The process exited due to a POSIX signal.
  #
  # Only applies to signals without a more specific exit reason. Unused on
  # Windows.
  Signal

  # The process exited in a way that cannot be represented by any other
  # `ExitReason`s.
  #
  # A `Process::Status` that maps to `Unknown` may map to a different value if
  # new enum members are added to `ExitReason`.
  Unknown

  # The process exited due to the user closing the terminal window or ending an ssh session.
  #
  # * On Unix-like systems, this corresponds to `Signal::HUP`.
  # * On Windows, this corresponds to the `CTRL_CLOSE_EVENT` message.
  TerminalDisconnected

  # The process exited due to the user logging off or shutting down the OS.
  #
  # * On Unix-like systems, this corresponds to `Signal::TERM`.
  # * On Windows, this corresponds to the `CTRL_LOGOFF_EVENT` and `CTRL_SHUTDOWN_EVENT` messages.
  SessionEnded

  # Returns `true` if the process exited abnormally.
  #
  # This includes all values except `Normal`.
  def abnormal?
    !normal?
  end

  # Returns a textual description of this exit reason.
  #
  # ```
  # Process::ExitReason::Normal.description  # => "Process exited normally"
  # Process::ExitReason::Aborted.description # => "Process terminated abnormally"
  # ```
  #
  # `Status#description` provides more detail for a specific process status.
  def description
    case self
    in .normal?
      "Process exited normally"
    in .aborted?, .session_ended?, .terminal_disconnected?
      "Process terminated abnormally"
    in .interrupted?
      "Process was interrupted"
    in .breakpoint?
      "Process hit a breakpoint and no debugger was attached"
    in .access_violation?, .bad_memory_access?
      "Process terminated because of an invalid memory access"
    in .bad_instruction?
      "Process terminated because of an invalid instruction"
    in .float_exception?
      "Process terminated because of a floating-point system exception"
    in .signal?
      Status::SIGNAL_REASON_DESCRIPTION
    in .unknown?
      "Process terminated abnormally, the cause is unknown"
    end
  end
end

# The status of a terminated process. Returned by `Process#wait`.
class Process::Status
  # Platform-specific exit status code, which usually contains either the exit code or a termination signal.
  # The other `Process::Status` methods extract the values from `exit_status`.
  @[Deprecated("Use `#exit_reason`, `#exit_code`, or `#system_exit_status` instead")]
  def exit_status : Int32
    @exit_status.to_i32!
  end

  # Returns the exit status as indicated by the operating system.
  #
  # It can encode exit codes and termination signals and is platform-specific.
  def system_exit_status : UInt32
    @exit_status.to_u32!
  end

  {% if flag?(:win32) %}
    # :nodoc:
    def initialize(@exit_status : UInt32)
    end
  {% else %}
    # :nodoc:
    def initialize(@exit_status : Int32)
    end
  {% end %}

  # Returns a platform-independent reason why the process terminated.
  def exit_reason : ExitReason
    {% if flag?(:win32) %}
      # TODO: perhaps this should cover everything that SEH can handle?
      # https://learn.microsoft.com/en-us/windows/win32/debug/getexceptioncode
      case @exit_status
      when LibC::STATUS_FATAL_APP_EXIT
        ExitReason::Aborted
      when LibC::STATUS_CONTROL_C_EXIT
        ExitReason::Interrupted
      when LibC::STATUS_BREAKPOINT
        ExitReason::Breakpoint
      when LibC::STATUS_ACCESS_VIOLATION, LibC::STATUS_STACK_OVERFLOW
        ExitReason::AccessViolation
      when LibC::STATUS_DATATYPE_MISALIGNMENT
        ExitReason::BadMemoryAccess
      when LibC::STATUS_ILLEGAL_INSTRUCTION, LibC::STATUS_PRIVILEGED_INSTRUCTION
        ExitReason::BadInstruction
      when LibC::STATUS_FLOAT_DIVIDE_BY_ZERO, LibC::STATUS_FLOAT_INEXACT_RESULT, LibC::STATUS_FLOAT_INVALID_OPERATION, LibC::STATUS_FLOAT_OVERFLOW, LibC::STATUS_FLOAT_UNDERFLOW
        ExitReason::FloatException
      else
        @exit_status & 0xC0000000_u32 == 0 ? ExitReason::Normal : ExitReason::Unknown
      end
    {% elsif flag?(:unix) && !flag?(:wasm32) %}
      case exit_signal?
      when Nil
        ExitReason::Normal
      when .abrt?, .kill?, .quit?
        ExitReason::Aborted
      when .hup?
        ExitReason::TerminalDisconnected
      when .term?
        ExitReason::SessionEnded
      when .int?
        ExitReason::Interrupted
      when .trap?
        ExitReason::Breakpoint
      when .segv?
        ExitReason::AccessViolation
      when .bus?
        ExitReason::BadMemoryAccess
      when .ill?
        ExitReason::BadInstruction
      when .fpe?
        ExitReason::FloatException
      else
        # TODO: stop / continue
        ExitReason::Signal
      end
    {% else %}
      raise NotImplementedError.new("Process::Status#exit_reason")
    {% end %}
  end

  # Returns `true` if the process was terminated by a signal.
  #
  # NOTE: In contrast to `WIFSIGNALED` in glibc, the status code `0x7E` (`SIGSTOP`)
  # is considered a signal.
  #
  # * `#abnormal_exit?` is a more portable alternative.
  # * `#exit_signal?` provides more information about the signal.
  def signal_exit? : Bool
    !!exit_signal?
  end

  # Returns `true` if the process terminated normally.
  #
  # Equivalent to `ExitReason::Normal`
  #
  # * `#exit_reason` provides more insights into other exit reasons.
  # * `#abnormal_exit?` returns the inverse.
  def normal_exit? : Bool
    exit_reason.normal?
  end

  # Returns `true` if the process terminated abnormally.
  #
  # Equivalent to `ExitReason#abnormal?`
  #
  # * `#exit_reason` provides more insights into the specific exit reason.
  # * `#normal_exit?` returns the inverse.
  def abnormal_exit? : Bool
    exit_reason.abnormal?
  end

  # If `signal_exit?` is `true`, returns the *Signal* the process
  # received and didn't handle. Will raise if `signal_exit?` is `false`.
  #
  # Available only on Unix-like operating systems.
  #
  # NOTE: `#exit_reason` is preferred over this method as a portable alternative
  # which also works on Windows.
  def exit_signal : Signal
    {% if flag?(:unix) && !flag?(:wasm32) %}
      Signal.new(signal_code)
    {% else %}
      raise NotImplementedError.new("Process::Status#exit_signal")
    {% end %}
  end

  # Returns the exit `Signal` or `nil` if there is none.
  #
  # On Windows returns always `nil`.
  #
  # * `#exit_reason` is a portable alternative.
  def exit_signal? : Signal?
    {% if flag?(:unix) && !flag?(:wasm32) %}
      code = signal_code
      unless code.zero?
        Signal.new(code)
      end
    {% end %}
  end

  # Returns the exit code of the process if it exited normally (`#normal_exit?`).
  #
  # Raises `RuntimeError` if the status describes an abnormal exit.
  #
  # ```
  # Process.run("true").exit_code                                # => 0
  # Process.run("exit 123", shell: true).exit_code               # => 123
  # Process.new("sleep", ["10"]).tap(&.terminate).wait.exit_code # RuntimeError: Abnormal exit has no exit code
  # ```
  def exit_code : Int32
    exit_code? || raise RuntimeError.new("Abnormal exit has no exit code")
  end

  # Returns the exit code of the process if it exited normally.
  #
  # Returns `nil` if the status describes an abnormal exit.
  #
  # ```
  # Process.run("true").exit_code?                                # => 0
  # Process.run("exit 123", shell: true).exit_code?               # => 123
  # Process.new("sleep", ["10"]).tap(&.terminate).wait.exit_code? # => nil
  # ```
  def exit_code? : Int32?
    return unless normal_exit?

    {% if flag?(:unix) %}
      # define __WEXITSTATUS(status) (((status) & 0xff00) >> 8)
      (@exit_status & 0xff00) >> 8
    {% else %}
      @exit_status.to_i32!
    {% end %}
  end

  # Returns `true` if the process exited normally with an exit code of `0`.
  def success? : Bool
    exit_code? == 0
  end

  private def signal_code
    # define __WTERMSIG(status) ((status) & 0x7f)
    @exit_status & 0x7f
  end

  def_equals_and_hash @exit_status

  # Prints a textual representation of the process status to *io*.
  #
  # The result is similar to `#to_s`, but prefixed by the type name,
  # delimited by square brackets, and constants use full paths:
  # `Process::Status[0]`, `Process::Status[1]`, `Process::Status[Signal::HUP]`,
  # `Process::Status[LibC::STATUS_CONTROL_C_EXIT]`.
  def inspect(io : IO) : Nil
    io << "Process::Status["
    {% if flag?(:win32) %}
      if name = name_for_win32_exit_status
        io << "LibC::" << name
      else
        stringify_exit_status_windows(io)
      end
    {% else %}
      if signal = exit_signal?
        signal.inspect(io)
      else
        exit_code.inspect(io)
      end
    {% end %}
    io << "]"
  end

  private def name_for_win32_exit_status
    case @exit_status
    # Ignoring LibC::STATUS_SUCCESS here because we prefer its numerical representation `0`
    when LibC::STATUS_FATAL_APP_EXIT          then "STATUS_FATAL_APP_EXIT"
    when LibC::STATUS_DATATYPE_MISALIGNMENT   then "STATUS_DATATYPE_MISALIGNMENT"
    when LibC::STATUS_BREAKPOINT              then "STATUS_BREAKPOINT"
    when LibC::STATUS_ACCESS_VIOLATION        then "STATUS_ACCESS_VIOLATION"
    when LibC::STATUS_ILLEGAL_INSTRUCTION     then "STATUS_ILLEGAL_INSTRUCTION"
    when LibC::STATUS_FLOAT_DIVIDE_BY_ZERO    then "STATUS_FLOAT_DIVIDE_BY_ZERO"
    when LibC::STATUS_FLOAT_INEXACT_RESULT    then "STATUS_FLOAT_INEXACT_RESULT"
    when LibC::STATUS_FLOAT_INVALID_OPERATION then "STATUS_FLOAT_INVALID_OPERATION"
    when LibC::STATUS_FLOAT_OVERFLOW          then "STATUS_FLOAT_OVERFLOW"
    when LibC::STATUS_FLOAT_UNDERFLOW         then "STATUS_FLOAT_UNDERFLOW"
    when LibC::STATUS_PRIVILEGED_INSTRUCTION  then "STATUS_PRIVILEGED_INSTRUCTION"
    when LibC::STATUS_STACK_OVERFLOW          then "STATUS_STACK_OVERFLOW"
    when LibC::STATUS_CANCELLED               then "STATUS_CANCELLED"
    when LibC::STATUS_CONTROL_C_EXIT          then "STATUS_CONTROL_C_EXIT"
    end
  end

  # Prints a textual representation of the process status to *io*.
  #
  # A normal exit status prints the numerical value (`0`, `1` etc) or a named
  # status (e.g. `STATUS_CONTROL_C_EXIT` on Windows).
  # A signal exit status prints the name of the `Signal` member (`HUP`, `INT`, etc.).
  def to_s(io : IO) : Nil
    {% if flag?(:win32) %}
      if name = name_for_win32_exit_status
        io << name
      else
        stringify_exit_status_windows(io)
      end
    {% else %}
      if signal = exit_signal?
        if name = signal.member_name
          io << name
        else
          signal.inspect(io)
        end
      else
        io << exit_code
      end
    {% end %}
  end

  # Returns a textual representation of the process status.
  #
  # A normal exit status prints the numerical value (`0`, `1` etc) or a named
  # status (e.g. `STATUS_CONTROL_C_EXIT` on Windows).
  # A signal exit status prints the name of the `Signal` member (`HUP`, `INT`, etc.).
  def to_s : String
    {% if flag?(:win32) %}
      name_for_win32_exit_status || String.build { |io| stringify_exit_status_windows(io) }
    {% else %}
      if signal = exit_signal?
        signal.member_name || signal.inspect
      else
        exit_code.to_s
      end
    {% end %}
  end

  # Returns a textual description of this process status.
  #
  # ```
  # Process::Status.new(0).description                             # => "Process exited normally"
  # Process.new("sleep", ["10"]).tap(&.terminate).wait.description # => "Process received and didn't handle signal TERM (15)"
  # ```
  #
  # `ExitReason#description` provides the specific messages for non-signal exits.
  def description
    description = exit_reason.description

    if description.same?(SIGNAL_REASON_DESCRIPTION) && (signal = exit_signal?)
      if signal.kill?
        "Process was killed"
      else
        "Process received and didn't handle signal #{signal}"
      end
    else
      description
    end
  end

  # :nodoc:
  SIGNAL_REASON_DESCRIPTION = "Process terminated because of an unhandled signal"

  private def stringify_exit_status_windows(io)
    # On Windows large status codes are typically expressed in hexadecimal
    if @exit_status >= UInt16::MAX
      io << "0x"
      @exit_status.to_s(base: 16, upcase: true).rjust(io, 8, '0')
    else
      @exit_status.to_s(io)
    end
  end
end
