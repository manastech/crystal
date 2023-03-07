require "c/fcntl"
require "io/evented"
require "termios"

# :nodoc:
module Crystal::System::FileDescriptor
  include IO::Evented

  @volatile_fd : Atomic(Int32)

  private def unbuffered_read(slice : Bytes)
    evented_read(slice, "Error reading file") do
      LibC.read(fd, slice, slice.size).tap do |return_code|
        if return_code == -1 && Errno.value == Errno::EBADF
          raise IO::Error.new "File not open for reading"
        end
      end
    end
  end

  private def unbuffered_write(slice : Bytes)
    evented_write(slice, "Error writing file") do |slice|
      LibC.write(fd, slice, slice.size).tap do |return_code|
        if return_code == -1 && Errno.value == Errno::EBADF
          raise IO::Error.new "File not open for writing"
        end
      end
    end
  end

  private def system_blocking?
    flags = fcntl(LibC::F_GETFL)
    !flags.bits_set? LibC::O_NONBLOCK
  end

  private def system_blocking=(value)
    current_flags = fcntl(LibC::F_GETFL)
    new_flags = current_flags
    if value
      new_flags &= ~LibC::O_NONBLOCK
    else
      new_flags |= LibC::O_NONBLOCK
    end
    fcntl(LibC::F_SETFL, new_flags) unless new_flags == current_flags
  end

  private def system_close_on_exec?
    flags = fcntl(LibC::F_GETFD)
    flags.bits_set? LibC::FD_CLOEXEC
  end

  private def system_close_on_exec=(arg : Bool)
    fcntl(LibC::F_SETFD, arg ? LibC::FD_CLOEXEC : 0)
    arg
  end

  private def system_closed?
    LibC.fcntl(fd, LibC::F_GETFL) == -1
  end

  def self.fcntl(fd, cmd, arg = 0)
    r = LibC.fcntl(fd, cmd, arg)
    raise IO::Error.from_errno("fcntl() failed") if r == -1
    r
  end

  def self.system_info(fd)
    stat = uninitialized LibC::Stat
    ret = File.fstat(fd, pointerof(stat))

    if ret != 0
      raise IO::Error.from_errno("Unable to get info")
    end

    ::File::Info.new(stat)
  end

  private def system_info
    FileDescriptor.system_info fd
  end

  private def system_seek(offset, whence : IO::Seek) : Nil
    seek_value = LibC.lseek(fd, offset, whence)

    if seek_value == -1
      raise IO::Error.from_errno "Unable to seek"
    end
  end

  private def system_pos
    pos = LibC.lseek(fd, 0, IO::Seek::Current).to_i64
    raise IO::Error.from_errno "Unable to tell" if pos == -1
    pos
  end

  private def system_tty?
    LibC.isatty(fd) == 1
  end

  private def system_reopen(other : IO::FileDescriptor)
    {% if LibC.has_method?("dup3") %}
      # dup doesn't copy the CLOEXEC flag, so copy it manually using dup3
      flags = other.close_on_exec? ? LibC::O_CLOEXEC : 0
      if LibC.dup3(other.fd, fd, flags) == -1
        raise IO::Error.from_errno("Could not reopen file descriptor")
      end
    {% else %}
      # dup doesn't copy the CLOEXEC flag, copy it manually to the new
      if LibC.dup2(other.fd, fd) == -1
        raise IO::Error.from_errno("Could not reopen file descriptor")
      end

      if other.close_on_exec?
        self.close_on_exec = true
      end
    {% end %}

    # Mark the handle open, since we had to have dup'd a live handle.
    @closed = false

    evented_reopen
  end

  private def system_close
    # Perform libevent cleanup before LibC.close.
    # Using a file descriptor after it has been closed is never defined and can
    # always lead to undefined results. This is not specific to libevent.
    evented_close

    file_descriptor_close
  end

  def file_descriptor_close : Nil
    # Clear the @volatile_fd before actually closing it in order to
    # reduce the chance of reading an outdated fd value
    _fd = @volatile_fd.swap(-1)

    if LibC.close(_fd) != 0
      case Errno.value
      when Errno::EINTR, Errno::EINPROGRESS
        # ignore
      else
        raise IO::Error.from_errno("Error closing file")
      end
    end
  end

  def self.pipe(read_blocking, write_blocking) : {IO::FileDescriptor, IO::FileDescriptor}
    pipe_fds = uninitialized StaticArray(LibC::Int, 2)
    if LibC.pipe(pipe_fds) != 0
      raise IO::Error.from_errno("Could not create pipe")
    end

    r = IO::FileDescriptor.new(pipe_fds[0], read_blocking)
    w = IO::FileDescriptor.new(pipe_fds[1], write_blocking)
    r.close_on_exec = true
    w.close_on_exec = true
    w.sync = true

    {r, w}
  end

  def self.pread(fd, buffer, offset)
    bytes_read = LibC.pread(fd, buffer, buffer.size, offset).to_i64

    if bytes_read == -1
      raise IO::Error.from_errno "Error reading file"
    end

    bytes_read
  end

  def self.from_stdio(fd)
    # If we have a TTY for stdin/out/err, it is possibly a shared terminal.
    # We need to reopen it to use O_NONBLOCK without causing other programs to break

    # Figure out the terminal TTY name. If ttyname fails we have a non-tty, or something strange.
    # For non-tty we set flush_on_newline to true for reasons described in STDOUT and STDERR docs.
    path = uninitialized UInt8[256]
    ret = LibC.ttyname_r(fd, path, 256)
    return IO::FileDescriptor.new(fd).tap(&.flush_on_newline=(true)) unless ret == 0

    clone_fd = LibC.open(path, LibC::O_RDWR)
    return IO::FileDescriptor.new(fd).tap(&.flush_on_newline=(true)) if clone_fd == -1

    # We don't buffer output for TTY devices to see their output right away
    io = IO::FileDescriptor.new(clone_fd)
    io.close_on_exec = true
    io.sync = true
    io
  end

  private def system_echo(enable : Bool, & : ->)
    system_console_mode do |mode|
      flags = LibC::ECHO | LibC::ECHOE | LibC::ECHOK | LibC::ECHONL
      mode.c_lflag = enable ? (mode.c_lflag | flags) : (mode.c_lflag & ~flags)
      if LibC.tcsetattr(fd, LibC::TCSANOW, pointerof(mode)) != 0
        raise IO::Error.from_errno("tcsetattr")
      end
      yield
    end
  end

  private def system_raw(enable : Bool, & : ->)
    system_console_mode do |mode|
      if enable
        LibC.cfmakeraw(pointerof(mode))
      else
        mode.c_iflag |= LibC::BRKINT | LibC::ISTRIP | LibC::ICRNL | LibC::IXON
        mode.c_oflag |= LibC::OPOST
        mode.c_lflag |= LibC::ECHO | LibC::ECHOE | LibC::ECHOK | LibC::ECHONL | LibC::ICANON | LibC::ISIG | LibC::IEXTEN
      end
      if LibC.tcsetattr(fd, LibC::TCSANOW, pointerof(mode)) != 0
        raise IO::Error.from_errno("tcsetattr")
      end
      yield
    end
  end

  @[AlwaysInline]
  private def system_console_mode(&)
    if LibC.tcgetattr(fd, out mode) != 0
      raise IO::Error.from_errno("tcgetattr")
    end

    before = mode
    ret = yield mode
    LibC.tcsetattr(fd, LibC::TCSANOW, pointerof(before))
    ret
  end
end
