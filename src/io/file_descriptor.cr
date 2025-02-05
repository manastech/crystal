require "crystal/system/file_descriptor"

# An `IO` over a file descriptor.
class IO::FileDescriptor < IO
  include Crystal::System::FileDescriptor
  include IO::Buffered

  @volatile_fd : Atomic(Handle)

  # Returns the raw file-descriptor handle. Its type is platform-specific.
  def fd : Handle
    @volatile_fd.get
  end

  # Whether or not to close the file descriptor when this object is finalized.
  # Disabling this is useful in order to create an IO wrapper over a file
  # descriptor returned from a C API that keeps ownership of the descriptor. Do
  # note that, if the fd is closed by its owner at any point, any IO operations
  # will then fail.
  property? close_on_finalize : Bool

  # The time to wait when reading before raising an `IO::TimeoutError`.
  property read_timeout : Time::Span?

  # Sets the number of seconds to wait when reading before raising an `IO::TimeoutError`.
  @[Deprecated("Use `#read_timeout=(Time::Span?)` instead.")]
  def read_timeout=(read_timeout : Number) : Number
    self.read_timeout = read_timeout.seconds
    read_timeout
  end

  # Sets the time to wait when writing before raising an `IO::TimeoutError`.
  property write_timeout : Time::Span?

  # Sets the number of seconds to wait when writing before raising an `IO::TimeoutError`.
  @[Deprecated("Use `#write_timeout=(Time::Span?)` instead.")]
  def write_timeout=(write_timeout : Number) : Number
    self.write_timeout = write_timeout.seconds
    write_timeout
  end

  def initialize(fd : Handle, blocking = nil, *, @close_on_finalize = true)
    @volatile_fd = Atomic.new(fd)
    @closed = true # This is necessary so we can reference `self` in `system_closed?` (in case of an exception)

    # TODO: Refactor to avoid calling `GetFileType` twice on Windows (once in `system_closed?` and once in `system_info`)
    @closed = system_closed?

    return if @closed

    if blocking.nil?
      blocking =
        case system_info.type
        when .pipe?, .socket?, .character_device?
          false
        else
          true
        end
    end

    system_blocking_init(blocking)
  end

  # :nodoc:
  def self.from_stdio(fd : Handle) : self
    Crystal::System::FileDescriptor.from_stdio(fd)
  end

  # Returns whether I/O operations on this file descriptor block the current
  # thread. If false, operations might opt to suspend the current fiber instead.
  #
  # This might be different from the internal file descriptor. For example, when
  # `STDIN` is a terminal on Windows, this returns `false` since the underlying
  # blocking reads are done on a completely separate thread.
  def blocking
    emulated = emulated_blocking?
    return emulated unless emulated.nil?
    system_blocking?
  end

  def blocking=(value)
    self.system_blocking = value
  end

  def close_on_exec? : Bool
    system_close_on_exec?
  end

  def close_on_exec=(value : Bool)
    self.system_close_on_exec = value
  end

  def self.fcntl(fd, cmd, arg = 0)
    Crystal::System::FileDescriptor.fcntl(fd, cmd, arg)
  end

  def fcntl(cmd, arg = 0)
    Crystal::System::FileDescriptor.fcntl(fd, cmd, arg)
  end

  # Returns a `File::Info` object for this file descriptor, or raises
  # `IO::Error` in case of an error.
  #
  # Certain fields like the file size may not be updated until an explicit
  # flush.
  #
  # ```
  # File.write("testfile", "abc")
  #
  # file = File.new("testfile", "a")
  # file.info.size # => 3
  # file << "defgh"
  # file.info.size # => 3
  # file.flush
  # file.info.size # => 8
  # ```
  #
  # Use `File.info` if the file is not open and a path to the file is available.
  def info : File::Info
    system_info
  end

  # Seeks to a given *offset* (in bytes) according to the *whence* argument.
  # Returns `self`.
  #
  # ```
  # File.write("testfile", "abc")
  #
  # file = File.new("testfile")
  # file.gets(3) # => "abc"
  # file.seek(1, IO::Seek::Set)
  # file.gets(2) # => "bc"
  # file.seek(-1, IO::Seek::Current)
  # file.gets(1) # => "c"
  # ```
  def seek(offset, whence : Seek = Seek::Set)
    check_open

    flush
    offset -= @in_buffer_rem.size if whence.current?

    system_seek(offset, whence)

    @in_buffer_rem = Bytes.empty

    self
  end

  # Same as `seek` but yields to the block after seeking and eventually seeks
  # back to the original position when the block returns.
  def seek(offset, whence : Seek = Seek::Set, &)
    original_pos = tell
    begin
      seek(offset, whence)
      yield
    ensure
      seek(original_pos)
    end
  end

  # Returns the current position (in bytes) in this `IO`.
  #
  # ```
  # File.write("testfile", "hello")
  #
  # file = File.new("testfile")
  # file.pos     # => 0
  # file.gets(2) # => "he"
  # file.pos     # => 2
  # ```
  protected def unbuffered_pos : Int64
    check_open

    system_pos
  end

  # Sets the current position (in bytes) in this `IO`.
  #
  # ```
  # File.write("testfile", "hello")
  #
  # file = File.new("testfile")
  # file.pos = 3
  # file.gets_to_end # => "lo"
  # ```
  def pos=(value)
    seek value
    value
  end

  # Flushes all data written to this File Descriptor to the disk device so that
  # all changed information can be retrieved even if the system
  # crashes or is rebooted. The call blocks until the device reports that
  # the transfer has completed.
  # To reduce disk activity the *flush_metadata* parameter can be set to false,
  # then the syscall *fdatasync* will be used and only data required for
  # subsequent data retrieval is flushed. Metadata such as modified time and
  # access time is not written.
  #
  # NOTE: Metadata is flushed even when *flush_metadata* is false on Windows
  # and DragonFly BSD.
  def fsync(flush_metadata = true) : Nil
    flush
    system_fsync(flush_metadata)
  end

  # TODO: use fcntl/lockf instead of flock (which doesn't lock over NFS)

  def flock_shared(blocking = true, &)
    flock_shared blocking
    begin
      yield
    ensure
      flock_unlock
    end
  end

  # Places a shared advisory lock. More than one process may hold a shared lock for a given file descriptor at a given time.
  # `IO::Error` is raised if *blocking* is set to `false` and an existing exclusive lock is set.
  def flock_shared(blocking = true) : Nil
    system_flock_shared(blocking)
  end

  def flock_exclusive(blocking = true, &)
    flock_exclusive blocking
    begin
      yield
    ensure
      flock_unlock
    end
  end

  # Places an exclusive advisory lock. Only one process may hold an exclusive lock for a given file descriptor at a given time.
  # `IO::Error` is raised if *blocking* is set to `false` and any existing lock is set.
  def flock_exclusive(blocking = true) : Nil
    system_flock_exclusive(blocking)
  end

  # Removes an existing advisory lock held by this process.
  def flock_unlock : Nil
    system_flock_unlock
  end

  # Finalizes the file descriptor resource.
  #
  # This involves releasing the handle to the operating system, i.e. closing it.
  # It does *not* implicitly call `#flush`, so data waiting in the buffer may be
  # lost.
  # It's recommended to always close the file descriptor explicitly via `#close`
  # (or implicitly using the `.open` constructor).
  #
  # Resource release can be disabled with `close_on_finalize = false`.
  #
  # This method is a no-op if the file descriptor has already been closed.
  def finalize
    return if closed? || !close_on_finalize?

    Crystal::EventLoop.remove(self)
    file_descriptor_close { } # ignore error
  end

  def closed? : Bool
    @closed
  end

  def tty? : Bool
    system_tty?
  end

  def reopen(other : IO::FileDescriptor)
    return other if self.fd == other.fd
    system_reopen(other)

    other
  end

  def inspect(io : IO) : Nil
    io << "#<IO::FileDescriptor:"
    if closed?
      io << "(closed)"
    else
      io << " fd=" << fd
    end
    io << '>'
  end

  def pretty_print(pp)
    pp.text inspect
  end

  private def unbuffered_read(slice : Bytes) : Int32
    system_read(slice)
  end

  private def unbuffered_write(slice : Bytes) : Nil
    until slice.empty?
      slice += system_write(slice)
    end
  end

  private def unbuffered_rewind : Nil
    self.pos = 0
  end

  private def unbuffered_close : Nil
    return if @closed

    # Set before the @closed state so the pending
    # IO::Evented readers and writers can be cancelled
    # knowing the IO is in a closed state.
    @closed = true
    system_close
  end

  private def unbuffered_flush : Nil
    # Nothing
  end

  # Blocks the current fiber until the socket is ready for read. Raises
  # `TimeoutError` when the configured `#read_timeout` has elapsed, otherwise
  # returns normally.
  def wait_readable : Nil
    system_wait_readable
  end

  # Blocks the current fiber until the socket is ready for write. Raises
  # `TimeoutError` when the configured `#write_timeout` has elapsed, otherwise
  # returns normally.
  def wait_writable : Nil
    system_wait_writable
  end
end
