require "c/io"
require "c/accctrl"
require "c/aclapi"
require "c/consoleapi"
require "c/consoleapi2"
require "c/securitybaseapi"
require "c/winnls"
require "io/overlapped"

module Crystal::System::FileDescriptor
  include IO::Overlapped

  @volatile_fd : Atomic(LibC::Int)
  @system_blocking = true

  private def unbuffered_read(slice : Bytes)
    if system_blocking?
      bytes_read = LibC._read(fd, slice, slice.size)
      if bytes_read == -1
        if Errno.value == Errno::EBADF
          raise IO::Error.new "File not open for reading"
        else
          raise IO::Error.from_errno("Error reading file")
        end
      end
      bytes_read
    else
      handle = windows_handle
      overlapped_operation(handle, "ReadFile", read_timeout) do |overlapped|
        ret = LibC.ReadFile(handle, slice, slice.size, out byte_count, overlapped)
        {ret, byte_count}
      end
    end
  end

  private def unbuffered_write(slice : Bytes)
    until slice.empty?
      if system_blocking?
        bytes_written = LibC._write(fd, slice, slice.size)
        if bytes_written == -1
          if Errno.value == Errno::EBADF
            raise IO::Error.new "File not open for writing"
          else
            raise IO::Error.from_errno("Error writing file")
          end
        end
      else
        handle = windows_handle
        bytes_written = overlapped_operation(handle, "WriteFile", write_timeout, writing: true) do |overlapped|
          ret = LibC.WriteFile(handle, slice, slice.size, out byte_count, overlapped)
          {ret, byte_count}
        end
      end

      slice += bytes_written
    end
  end

  private def system_blocking?
    @system_blocking
  end

  private def system_blocking=(blocking)
    unless blocking == @system_blocking
      raise IO::Error.new("Cannot reconfigure `IO::FileDescriptor#blocking` after creation")
    end
  end

  private def system_blocking_init(value)
    @system_blocking = value
  end

  private def system_close_on_exec?
    false
  end

  private def system_close_on_exec=(close_on_exec)
    raise NotImplementedError.new("Crystal::System::FileDescriptor#system_close_on_exec=") if close_on_exec
  end

  private def system_closed?
    false
  end

  private def windows_handle
    FileDescriptor.windows_handle!(fd)
  end

  def self.windows_handle(fd)
    ret = LibC._get_osfhandle(fd)
    return LibC::INVALID_HANDLE_VALUE if ret == -1 || ret == -2
    LibC::HANDLE.new(ret)
  end

  def self.windows_handle!(fd)
    ret = LibC._get_osfhandle(fd)
    raise RuntimeError.from_errno("_get_osfhandle") if ret == -1
    raise RuntimeError.new("_get_osfhandle returned -2") if ret == -2
    LibC::HANDLE.new(ret)
  end

  def self.system_info(handle, file_type = nil, reparse_tag = LibC::DWORD.zero)
    unless file_type
      file_type = LibC.GetFileType(handle)

      if file_type == LibC::FILE_TYPE_UNKNOWN
        error = WinError.value
        raise IO::Error.from_os_error("Unable to get info", error) unless error == WinError::ERROR_SUCCESS
      end
    end

    if file_type == LibC::FILE_TYPE_DISK
      if LibC.GetFileInformationByHandle(handle, out file_info) == 0
        raise IO::Error.from_winerror("Unable to get info")
      end

      permissions = file_permissions(handle)
      ::File::Info.new(file_info, file_type, reparse_tag, permissions)
    else
      ::File::Info.new(file_type)
    end
  end

  def self.file_permissions(handle)
    status = LibC.GetSecurityInfo(
      handle,
      LibC::SE_OBJECT_TYPE::FILE_OBJECT,
      LibC::OWNER_SECURITY_INFORMATION | LibC::GROUP_SECURITY_INFORMATION | LibC::DACL_SECURITY_INFORMATION,
      out owner_sid,
      out group_sid,
      out dacl,
      nil,
      out security_descriptor,
    )
    raise IO::Error.from_os_error("GetSecurityInfo", WinError.new(status)) unless status == 0

    begin
      ::File::Permissions.new(
        permissions_from_dacl(dacl, owner_sid) << 6 |
        permissions_from_dacl(dacl, group_sid) << 3 |
        permissions_from_dacl(dacl, world_sid)
      )
    ensure
      LibC.LocalFree(security_descriptor)
    end
  end

  private def self.permissions_from_dacl(dacl, sid)
    LibC.BuildTrusteeWithSidW(out trustee, sid)
    if LibC.GetEffectiveRightsFromAclW(dacl, pointerof(trustee), out access_rights) != 0
      raise RuntimeError.from_winerror("GetEffectiveRightsFromAclW")
    end

    permissions = 0_i16
    permissions |= 1 if access_rights.includes?(LibC::ACCESS_MASK::FILE_GENERIC_EXECUTE)
    permissions |= 2 if access_rights.includes?(LibC::ACCESS_MASK::FILE_GENERIC_WRITE)
    permissions |= 4 if access_rights.includes?(LibC::ACCESS_MASK::FILE_GENERIC_READ)
    permissions
  end

  private class_getter world_sid : LibC::SID* do
    sid = Pointer(UInt8).malloc(LibC::SECURITY_MAX_SID_SIZE).as(LibC::SID*)
    size = LibC::DWORD.new!(LibC::SECURITY_MAX_SID_SIZE)
    if LibC.CreateWellKnownSid(LibC::WELL_KNOWN_SID_TYPE::WinWorldSid, nil, sid, pointerof(size)) == 0
      raise RuntimeError.from_winerror("CreateWellKnownSid")
    end
    sid
  end

  private def system_info
    FileDescriptor.system_info windows_handle
  end

  private def system_seek(offset, whence : IO::Seek) : Nil
    seek_value = LibC._lseeki64(fd, offset, whence)

    if seek_value == -1
      raise IO::Error.from_errno "Unable to seek"
    end
  end

  private def system_pos
    pos = LibC._lseeki64(fd, 0, IO::Seek::Current)
    raise IO::Error.from_errno "Unable to tell" if pos == -1
    pos
  end

  private def system_tty?
    LibC._isatty(fd) != 0
  end

  private def system_reopen(other : IO::FileDescriptor)
    # Windows doesn't implement the CLOEXEC flag
    if LibC._dup2(other.fd, self.fd) == -1
      raise IO::Error.from_errno("Could not reopen file descriptor")
    end

    # Mark the handle open, since we had to have dup'd a live handle.
    @closed = false
  end

  private def system_close
    LibC.CancelIoEx(windows_handle, nil) unless system_blocking?

    file_descriptor_close
  end

  def file_descriptor_close
    if LibC._close(fd) != 0
      case Errno.value
      when Errno::EINTR
        # ignore
      else
        raise IO::Error.from_errno("Error closing file")
      end
    end
  end

  private PIPE_BUFFER_SIZE = 8192

  def self.pipe(read_blocking, write_blocking)
    pipe_name = ::Path.windows(::File.tempname("crystal", nil, dir: %q(\\.\pipe))).normalize.to_s
    pipe_mode = 0 # PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT

    w_pipe_flags = LibC::PIPE_ACCESS_OUTBOUND | LibC::FILE_FLAG_FIRST_PIPE_INSTANCE
    w_pipe_flags |= LibC::FILE_FLAG_OVERLAPPED unless write_blocking
    w_pipe = LibC.CreateNamedPipeA(pipe_name, w_pipe_flags, pipe_mode, 1, PIPE_BUFFER_SIZE, PIPE_BUFFER_SIZE, 0, nil)
    raise IO::Error.from_winerror("CreateNamedPipeA") if w_pipe == LibC::INVALID_HANDLE_VALUE
    Crystal::Scheduler.event_loop.create_completion_port(w_pipe) unless write_blocking

    r_pipe_flags = LibC::FILE_FLAG_NO_BUFFERING
    r_pipe_flags |= LibC::FILE_FLAG_OVERLAPPED unless read_blocking
    r_pipe = LibC.CreateFileW(System.to_wstr(pipe_name), LibC::ACCESS_MASK::GENERIC_READ | LibC::ACCESS_MASK::FILE_WRITE_ATTRIBUTES, 0, nil, LibC::OPEN_EXISTING, r_pipe_flags, nil)
    raise IO::Error.from_winerror("CreateFileW") if r_pipe == LibC::INVALID_HANDLE_VALUE
    Crystal::Scheduler.event_loop.create_completion_port(r_pipe) unless read_blocking

    r = IO::FileDescriptor.new(LibC._open_osfhandle(r_pipe, 0), read_blocking)
    w = IO::FileDescriptor.new(LibC._open_osfhandle(w_pipe, 0), write_blocking)
    w.sync = true

    {r, w}
  end

  def self.pread(fd, buffer, offset)
    handle = windows_handle!(fd)

    overlapped = LibC::OVERLAPPED.new
    overlapped.union.offset.offset = LibC::DWORD.new(offset)
    overlapped.union.offset.offsetHigh = LibC::DWORD.new(offset >> 32)
    if LibC.ReadFile(handle, buffer, buffer.size, out bytes_read, pointerof(overlapped)) == 0
      error = WinError.value
      return 0_i64 if error == WinError::ERROR_HANDLE_EOF
      raise IO::Error.from_os_error "Error reading file", error
    end

    bytes_read.to_i64
  end

  def self.from_stdio(fd)
    console_handle = false
    handle = windows_handle(fd)
    if handle != LibC::INVALID_HANDLE_VALUE
      LibC._setmode fd, LibC::O_BINARY
      # TODO: use `out old_mode` after implementing interpreter out closured var
      old_mode = uninitialized LibC::DWORD
      if LibC.GetConsoleMode(handle, pointerof(old_mode)) != 0
        console_handle = true
        if fd == 1 || fd == 2 # STDOUT or STDERR
          if LibC.SetConsoleMode(handle, old_mode | LibC::ENABLE_VIRTUAL_TERMINAL_PROCESSING) != 0
            at_exit { LibC.SetConsoleMode(handle, old_mode) }
          end
        end
      end
    end

    io = IO::FileDescriptor.new(fd, blocking: true)
    # Set sync or flush_on_newline as described in STDOUT and STDERR docs.
    # See https://crystal-lang.org/api/toplevel.html#STDERR
    if console_handle
      io.sync = true
    else
      io.flush_on_newline = true
    end
    io
  end

  private def system_echo(enable : Bool, & : ->)
    system_console_mode(enable, LibC::ENABLE_ECHO_INPUT, 0) { yield }
  end

  private def system_raw(enable : Bool, & : ->)
    system_console_mode(enable, LibC::ENABLE_VIRTUAL_TERMINAL_INPUT, LibC::ENABLE_PROCESSED_INPUT | LibC::ENABLE_LINE_INPUT | LibC::ENABLE_ECHO_INPUT) { yield }
  end

  @[AlwaysInline]
  private def system_console_mode(enable, on_mask, off_mask, &)
    windows_handle = self.windows_handle
    if LibC.GetConsoleMode(windows_handle, out old_mode) == 0
      raise IO::Error.from_winerror("GetConsoleMode")
    end

    old_on_bits = old_mode & on_mask
    old_off_bits = old_mode & off_mask
    if enable
      return yield if old_on_bits == on_mask && old_off_bits == 0
      new_mode = (old_mode | on_mask) & ~off_mask
    else
      return yield if old_on_bits == 0 && old_off_bits == off_mask
      new_mode = (old_mode | off_mask) & ~on_mask
    end

    if LibC.SetConsoleMode(windows_handle, new_mode) == 0
      raise IO::Error.from_winerror("SetConsoleMode")
    end

    ret = yield
    if LibC.GetConsoleMode(windows_handle, pointerof(old_mode)) != 0
      new_mode = (old_mode & ~on_mask & ~off_mask) | old_on_bits | old_off_bits
      LibC.SetConsoleMode(windows_handle, new_mode)
    end
    ret
  end
end

# Enable UTF-8 console I/O for the duration of program execution
if LibC.IsValidCodePage(LibC::CP_UTF8) != 0
  old_input_cp = LibC.GetConsoleCP
  if LibC.SetConsoleCP(LibC::CP_UTF8) != 0
    at_exit { LibC.SetConsoleCP(old_input_cp) }
  end

  old_output_cp = LibC.GetConsoleOutputCP
  if LibC.SetConsoleOutputCP(LibC::CP_UTF8) != 0
    at_exit { LibC.SetConsoleOutputCP(old_output_cp) }
  end
end
