require "c/sys/file"
require "file/error"

# :nodoc:
module Crystal::System::File
  def self.open(filename, mode, perm)
    oflag = open_flag(mode) | LibC::O_CLOEXEC

    fd = LibC.open(filename.check_no_null_byte, oflag, perm)
    if fd < 0
      raise ::File::Error.from_errno("Error opening file with mode '#{mode}'", file: filename)
    end
    fd
  end

  def self.mktemp(prefix, suffix, dir) : {LibC::Int, String}
    prefix.try &.check_no_null_byte
    suffix.try &.check_no_null_byte
    dir.check_no_null_byte

    dir = dir + ::File::SEPARATOR
    path = "#{dir}#{prefix}.XXXXXX#{suffix}"

    if suffix
      fd = LibC.mkstemps(path, suffix.bytesize)
    else
      fd = LibC.mkstemp(path)
    end

    raise ::File::Error.from_errno("Error creating temporary file", file: path) if fd == -1
    {fd, path}
  end

  def self.info?(path : String, follow_symlinks : Bool) : ::File::Info?
    stat = uninitialized LibC::Stat
    if follow_symlinks
      ret = stat(path.check_no_null_byte, pointerof(stat))
    else
      ret = lstat(path.check_no_null_byte, pointerof(stat))
    end

    if ret == 0
      ::File::Info.new(stat)
    else
      if Errno.value.in?(Errno::ENOENT, Errno::ENOTDIR)
        nil
      else
        raise ::File::Error.from_errno("Unable to get file info", file: path)
      end
    end
  end

  # On some systems, the symbols `stat`, `fstat` and `lstat` are not part of the GNU
  # shared library `libc.so` and instead provided by `libc_noshared.a`.
  # That makes them unavailable for dynamic runtime symbol lookup via `dlsym`
  # which we use for interpreted mode.
  # See https://github.com/crystal-lang/crystal/issues/11157#issuecomment-949640034 for details.
  # Linking against the internal counterparts `__xstat`, `__fxstat` and `__lxstat` directly
  # should work in both interpreted and compiled mode.

  def self.stat(path, stat)
    {% if LibC.has_method?(:__xstat) %}
      LibC.__xstat(LibC::STAT_VER, path, stat)
    {% else %}
      LibC.stat(path, stat)
    {% end %}
  end

  def self.fstat(path, stat)
    {% if LibC.has_method?(:__fxstat) %}
      LibC.__fxstat(LibC::STAT_VER, path, stat)
    {% else %}
      LibC.fstat(path, stat)
    {% end %}
  end

  def self.lstat(path, stat)
    {% if LibC.has_method?(:__lxstat) %}
      LibC.__lxstat(LibC::STAT_VER, path, stat)
    {% else %}
      LibC.lstat(path, stat)
    {% end %}
  end

  def self.info(path, follow_symlinks)
    info?(path, follow_symlinks) || raise ::File::Error.from_errno("Unable to get file info", file: path)
  end

  def self.exists?(path)
    accessible?(path, LibC::F_OK)
  end

  def self.readable?(path) : Bool
    accessible?(path, LibC::R_OK)
  end

  def self.writable?(path) : Bool
    accessible?(path, LibC::W_OK)
  end

  def self.executable?(path) : Bool
    accessible?(path, LibC::X_OK)
  end

  private def self.accessible?(path, flag)
    LibC.access(path.check_no_null_byte, flag) == 0
  end

  def self.chown(path, uid : Int, gid : Int, follow_symlinks)
    ret = if follow_symlinks
            LibC.chown(path, uid, gid)
          else
            LibC.lchown(path, uid, gid)
          end
    raise ::File::Error.from_errno("Error changing owner", file: path) if ret == -1
  end

  def self.fchown(path, fd, uid : Int, gid : Int)
    ret = LibC.fchown(fd, uid, gid)
    raise ::File::Error.from_errno("Error changing owner", file: path) if ret == -1
  end

  def self.chmod(path, mode)
    if LibC.chmod(path, mode) == -1
      raise ::File::Error.from_errno("Error changing permissions", file: path)
    end
  end

  def self.fchmod(path, fd, mode)
    if LibC.fchmod(fd, mode) == -1
      raise ::File::Error.from_errno("Error changing permissions", file: path)
    end
  end

  def self.delete(path, *, raise_on_missing : Bool) : Bool
    err = LibC.unlink(path.check_no_null_byte)
    if err != -1
      true
    elsif !raise_on_missing && Errno.value == Errno::ENOENT
      false
    else
      raise ::File::Error.from_errno("Error deleting file", file: path)
    end
  end

  def self.realpath(path)
    realpath_ptr = LibC.realpath(path, nil)
    raise ::File::Error.from_errno("Error resolving real path", file: path) unless realpath_ptr
    String.new(realpath_ptr).tap { LibC.free(realpath_ptr.as(Void*)) }
  end

  def self.link(old_path, new_path)
    ret = LibC.link(old_path.check_no_null_byte, new_path.check_no_null_byte)
    raise ::File::Error.from_errno("Error creating link", file: old_path, other: new_path) if ret != 0
    ret
  end

  def self.symlink(old_path, new_path)
    ret = LibC.symlink(old_path.check_no_null_byte, new_path.check_no_null_byte)
    raise ::File::Error.from_errno("Error creating symlink", file: old_path, other: new_path) if ret != 0
    ret
  end

  def self.readlink(path) : String
    buf = Bytes.new 256
    # First pass at 256 bytes handles all normal occurrences in 1 system call.
    # Second pass at 1024 bytes handles outliers?
    # Third pass is the max or double what Linux/MacOS can store.
    3.times do |iter|
      bytesize = LibC.readlink(path, buf, buf.bytesize)
      if bytesize == -1
        raise ::File::Error.from_errno("Cannot read link", file: path)
      elsif bytesize == buf.bytesize
        break if iter >= 2
        buf = Bytes.new(buf.bytesize * 4)
      else
        return String.new(buf.to_unsafe, bytesize)
      end
    end

    raise ::File::Error.from_os_error("Cannot read link", Errno::ENAMETOOLONG, file: path)
  end

  def self.rename(old_filename, new_filename) : ::File::Error?
    code = LibC.rename(old_filename.check_no_null_byte, new_filename.check_no_null_byte)
    if code != 0
      ::File::Error.from_errno("Error renaming file", file: old_filename, other: new_filename)
    end
  end

  def self.utime(atime : ::Time, mtime : ::Time, filename : String) : Nil
    timevals = uninitialized LibC::Timeval[2]
    timevals[0] = to_timeval(atime)
    timevals[1] = to_timeval(mtime)
    ret = LibC.utimes(filename, timevals)
    if ret != 0
      raise ::File::Error.from_errno("Error setting time on file", file: filename)
    end
  end

  def self.futimens(filename : String, fd : Int, atime : ::Time, mtime : ::Time) : Nil
    ret = {% if LibC.has_method?("futimens") %}
            timespecs = uninitialized LibC::Timespec[2]
            timespecs[0] = to_timespec(atime)
            timespecs[1] = to_timespec(mtime)
            LibC.futimens(fd, timespecs)
          {% elsif LibC.has_method?("futimes") %}
            timevals = uninitialized LibC::Timeval[2]
            timevals[0] = to_timeval(atime)
            timevals[1] = to_timeval(mtime)
            LibC.futimes(fd, timevals)
          {% else %}
            {% raise "Missing futimens & futimes" %}
          {% end %}

    if ret != 0
      raise ::File::Error.from_errno("Error setting time on file", file: filename)
    end
  end

  private def self.to_timespec(time : ::Time)
    t = uninitialized LibC::Timespec
    t.tv_sec = typeof(t.tv_sec).new(time.to_unix)
    t.tv_nsec = typeof(t.tv_nsec).new(time.nanosecond)
    t
  end

  private def self.to_timeval(time : ::Time)
    t = uninitialized LibC::Timeval
    t.tv_sec = typeof(t.tv_sec).new(time.to_unix)
    t.tv_usec = typeof(t.tv_usec).new(time.nanosecond // ::Time::NANOSECONDS_PER_MICROSECOND)
    t
  end

  private def system_truncate(size) : Nil
    flush
    code = LibC.ftruncate(fd, size)
    if code != 0
      raise ::File::Error.from_errno("Error truncating file", file: path)
    end
  end

  private def system_flock_shared(blocking)
    flock LibC::FlockOp::SH, blocking
  end

  private def system_flock_exclusive(blocking)
    flock LibC::FlockOp::EX, blocking
  end

  private def system_flock_unlock
    flock LibC::FlockOp::UN
  end

  private def flock(op : LibC::FlockOp, retry : Bool) : Nil
    op |= LibC::FlockOp::NB

    if retry
      until flock(op)
        ::Fiber.yield
      end
    else
      flock(op) || raise IO::Error.from_errno("Error applying file lock: file is already locked")
    end
  end

  private def flock(op) : Bool
    if 0 == LibC.flock(fd, op)
      true
    else
      errno = Errno.value
      if errno.in?(Errno::EAGAIN, Errno::EWOULDBLOCK)
        false
      else
        raise IO::Error.from_os_error("Error applying or removing file lock", errno)
      end
    end
  end

  private def system_fsync(flush_metadata = true) : Nil
    ret =
      if flush_metadata
        LibC.fsync(fd)
      else
        {% if flag?(:dragonfly) %}
          LibC.fsync(fd)
        {% else %}
          LibC.fdatasync(fd)
        {% end %}
      end

    if ret != 0
      raise IO::Error.from_errno("Error syncing file")
    end
  end
end
