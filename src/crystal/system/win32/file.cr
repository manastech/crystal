require "c/io"
require "c/fcntl"
require "c/fileapi"
require "c/sys/utime"
require "c/sys/stat"
require "c/winbase"
require "c/handleapi"
require "c/ntifs"
require "c/winioctl"

module Crystal::System::File
  def self.open(filename : String, mode : String, perm : Int32 | ::File::Permissions) : LibC::Int
    perm = ::File::Permissions.new(perm) if perm.is_a? Int32
    # Only the owner writable bit is used, since windows only supports
    # the read only attribute.
    if perm.owner_write?
      perm = LibC::S_IREAD | LibC::S_IWRITE
    else
      perm = LibC::S_IREAD
    end

    fd, errno = open(filename, open_flag(mode), ::File::Permissions.new(perm))
    unless errno.none?
      raise ::File::Error.from_os_error("Error opening file with mode '#{mode}'", errno, file: filename)
    end

    fd
  end

  def self.open(filename : String, flags : Int32, perm : ::File::Permissions) : {LibC::Int, Errno}
    access, disposition, attributes = self.posix_to_open_opts flags, perm

    handle = LibC.CreateFileW(
      System.to_wstr(filename),
      access,
      LibC::DEFAULT_SHARE_MODE, # UNIX semantics
      nil,
      disposition,
      attributes,
      LibC::HANDLE.null
    )

    if handle == LibC::INVALID_HANDLE_VALUE
      return {-1, WinError.value.to_errno}
    end

    fd = LibC._open_osfhandle handle, flags

    if fd == -1
      return {-1, Errno.value}
    end

    # Only binary mode is supported
    LibC._setmode fd, LibC::O_BINARY

    {fd, Errno::NONE}
  end

  private def self.posix_to_open_opts(flags : Int32, perm : ::File::Permissions)
    access = if flags.bits_set? LibC::O_WRONLY
               LibC::ACCESS_MASK::GENERIC_WRITE
             elsif flags.bits_set? LibC::O_RDWR
               LibC::ACCESS_MASK::GENERIC_READ | LibC::ACCESS_MASK::GENERIC_WRITE
             else
               LibC::ACCESS_MASK::GENERIC_READ
             end

    if flags.bits_set? LibC::O_APPEND
      access |= LibC::ACCESS_MASK::FILE_APPEND_DATA
    end

    if flags.bits_set? LibC::O_TRUNC
      if flags.bits_set? LibC::O_CREAT
        disposition = LibC::CREATE_ALWAYS
      else
        disposition = LibC::TRUNCATE_EXISTING
      end
    elsif flags.bits_set? LibC::O_CREAT
      if flags.bits_set? LibC::O_EXCL
        disposition = LibC::CREATE_NEW
      else
        disposition = LibC::OPEN_ALWAYS
      end
    else
      disposition = LibC::OPEN_EXISTING
    end

    attributes = LibC::FILE_ATTRIBUTE_NORMAL
    unless perm.owner_write?
      attributes |= LibC::FILE_ATTRIBUTE_READONLY
    end

    if flags.bits_set? LibC::O_TEMPORARY
      attributes |= LibC::FILE_FLAG_DELETE_ON_CLOSE | LibC::FILE_ATTRIBUTE_TEMPORARY
      access |= LibC::ACCESS_MASK::DELETE
    end

    if flags.bits_set? LibC::O_SHORT_LIVED
      attributes |= LibC::FILE_ATTRIBUTE_TEMPORARY
    end

    if flags.bits_set? LibC::O_SEQUENTIAL
      attributes |= LibC::FILE_FLAG_SEQUENTIAL_SCAN
    elsif flags.bits_set? LibC::O_RANDOM
      attributes |= LibC::FILE_FLAG_RANDOM_ACCESS
    end

    {access, disposition, attributes}
  end

  NOT_FOUND_ERRORS = {
    WinError::ERROR_FILE_NOT_FOUND,
    WinError::ERROR_PATH_NOT_FOUND,
    WinError::ERROR_INVALID_NAME,
  }

  def self.check_not_found_error(message, path)
    error = WinError.value
    if NOT_FOUND_ERRORS.includes? error
      nil
    else
      raise ::File::Error.from_os_error(message, error, file: path)
    end
  end

  def self.info?(path : String, follow_symlinks : Bool) : ::File::Info?
    winpath = System.to_wstr(path)

    unless follow_symlinks
      # First try using GetFileAttributes to check if it's a reparse point
      file_attributes = uninitialized LibC::WIN32_FILE_ATTRIBUTE_DATA
      ret = LibC.GetFileAttributesExW(
        winpath,
        LibC::GET_FILEEX_INFO_LEVELS::GetFileExInfoStandard,
        pointerof(file_attributes)
      )
      return check_not_found_error("Unable to get file info", path) if ret == 0

      if file_attributes.dwFileAttributes.bits_set? LibC::FILE_ATTRIBUTE_REPARSE_POINT
        # Could be a symlink, retrieve its reparse tag
        handle = LibC.CreateFileW(
          winpath,
          LibC::ACCESS_MASK::FILE_READ_ATTRIBUTES | LibC::ACCESS_MASK::READ_CONTROL,
          LibC::DEFAULT_SHARE_MODE,
          nil,
          LibC::OPEN_EXISTING,
          LibC::FILE_FLAG_BACKUP_SEMANTICS | LibC::FILE_FLAG_OPEN_REPARSE_POINT,
          LibC::HANDLE.null
        )
        return check_not_found_error("Unable to get file info", path) if handle == LibC::INVALID_HANDLE_VALUE

        begin
          with_reparse_data_buffer do |buf, size|
            if LibC.DeviceIoControl(handle, LibC::FSCTL_GET_REPARSE_POINT, nil, 0, buf, size, out _, nil) != 0
              reparse_data = buf.as(LibC::REPARSE_DATA_BUFFER*)
              reparse_tag = reparse_data.value.reparseTag
              if reparse_tag == LibC::IO_REPARSE_TAG_SYMLINK
                return FileDescriptor.system_info(handle, LibC::FILE_TYPE_DISK, reparse_tag)
              end
            end
          end
        ensure
          LibC.CloseHandle(handle)
        end
      end
    end

    handle = LibC.CreateFileW(
      winpath,
      LibC::ACCESS_MASK::FILE_READ_ATTRIBUTES | LibC::ACCESS_MASK::READ_CONTROL,
      LibC::DEFAULT_SHARE_MODE,
      nil,
      LibC::OPEN_EXISTING,
      LibC::FILE_FLAG_BACKUP_SEMANTICS,
      LibC::HANDLE.null
    )

    return check_not_found_error("Unable to get file info", path) if handle == LibC::INVALID_HANDLE_VALUE

    begin
      FileDescriptor.system_info(handle)
    ensure
      LibC.CloseHandle(handle)
    end
  end

  def self.info(path, follow_symlinks)
    info?(path, follow_symlinks) || raise ::File::Error.from_winerror("Unable to get file info", file: path)
  end

  def self.exists?(path, *, follow_symlinks = true)
    if follow_symlinks
      path = realpath?(path) || return false
    end
    accessible?(path, 0)
  end

  def self.readable?(path) : Bool
    check_rw_access(path, false)
  end

  def self.writable?(path) : Bool
    check_rw_access(path, true)
  end

  def self.executable?(path) : Bool
    LibC.GetBinaryTypeW(System.to_wstr(path), out result) != 0
  end

  private def self.check_rw_access(path, write = false)
    winpath = System.to_wstr(path)

    handle = LibC.CreateFileW(
      winpath,
      LibC::ACCESS_MASK::FILE_READ_ATTRIBUTES | LibC::ACCESS_MASK::READ_CONTROL,
      LibC::DEFAULT_SHARE_MODE,
      nil,
      LibC::OPEN_EXISTING,
      LibC::FILE_FLAG_BACKUP_SEMANTICS,
      LibC::HANDLE.null
    )
    return false if handle == LibC::INVALID_HANDLE_VALUE

    begin
      if write
        attributes = LibC.GetFileAttributesW(winpath)
        return false if attributes == LibC::INVALID_FILE_ATTRIBUTES
        return false if attributes.bits_set?(LibC::FILE_ATTRIBUTE_READONLY)
      end

      status = LibC.GetSecurityInfo(handle, LibC::SE_OBJECT_TYPE::FILE_OBJECT, LibC::DACL_SECURITY_INFORMATION, nil, nil, out dacl, nil, out security_descriptor)
      raise IO::Error.from_os_error("GetSecurityInfo", WinError.new(status)) unless status == 0

      begin
        LibC.BuildTrusteeWithSidW(out trustee, process_sid)
        if LibC.GetEffectiveRightsFromAclW(dacl, pointerof(trustee), out access_rights) != 0
          raise RuntimeError.from_winerror("GetEffectiveRightsFromAclW")
        end
        access_rights.includes?(write ? LibC::ACCESS_MASK::FILE_GENERIC_WRITE : LibC::ACCESS_MASK::FILE_GENERIC_READ)
      ensure
        LibC.LocalFree(security_descriptor)
      end
    ensure
      LibC.CloseHandle(handle)
    end
  end

  private class_getter process_sid : LibC::SID* do
    LibC.GetTokenInformation(LibC::GetCurrentProcessToken, LibC::TOKEN_INFORMATION_CLASS::TokenOwner, nil, 0, out byte_size)
    buf = Pointer(UInt8).malloc(byte_size).as(LibC::TOKEN_OWNER*)
    LibC.GetTokenInformation(LibC::GetCurrentProcessToken, LibC::TOKEN_INFORMATION_CLASS::TokenOwner, buf, byte_size, out _)
    buf.value.owner
  end

  private def self.accessible?(path, mode)
    LibC._waccess_s(System.to_wstr(path), mode) == 0
  end

  def self.chown(path : String, uid : Int32, gid : Int32, follow_symlinks : Bool) : Nil
    raise NotImplementedError.new("File.chown")
  end

  def self.fchown(path : String, fd : Int, uid : Int32, gid : Int32) : Nil
    raise NotImplementedError.new("File#chown")
  end

  def self.chmod(path : String, mode : Int32 | ::File::Permissions) : Nil
    mode = ::File::Permissions.new(mode) unless mode.is_a? ::File::Permissions

    unless exists?(path, follow_symlinks: false)
      raise ::File::Error.from_os_error("Error changing permissions", Errno::ENOENT, file: path)
    end

    path = realpath(path)

    attributes = LibC.GetFileAttributesW(System.to_wstr(path))
    if attributes == LibC::INVALID_FILE_ATTRIBUTES
      raise ::File::Error.from_winerror("Error changing permissions", file: path)
    end

    # Only the owner writable bit is used, since windows only supports
    # the read only attribute.
    if mode.owner_write?
      attributes &= ~LibC::FILE_ATTRIBUTE_READONLY
    else
      attributes |= LibC::FILE_ATTRIBUTE_READONLY
    end

    if LibC.SetFileAttributesW(System.to_wstr(path), attributes) == 0
      raise ::File::Error.from_winerror("Error changing permissions", file: path)
    end
  end

  def self.fchmod(path : String, fd : Int, mode : Int32 | ::File::Permissions) : Nil
    # TODO: use fd instead of path
    chmod path, mode
  end

  def self.delete(path : String, *, raise_on_missing : Bool) : Bool
    win_path = System.to_wstr(path)

    attributes = LibC.GetFileAttributesW(win_path)
    if attributes == LibC::INVALID_FILE_ATTRIBUTES
      check_not_found_error("Error deleting file", path)
      raise ::File::Error.from_os_error("Error deleting file", Errno::ENOENT, file: path) if raise_on_missing
      return false
    end

    # Windows cannot delete read-only files, so we unset the attribute here, but
    # restore it afterwards if deletion still failed
    read_only_removed = false
    if attributes.bits_set?(LibC::FILE_ATTRIBUTE_READONLY)
      if LibC.SetFileAttributesW(win_path, attributes & ~LibC::FILE_ATTRIBUTE_READONLY) != 0
        read_only_removed = true
      end
    end

    # all reparse point directories should be deleted like a directory, not just
    # symbolic links, so we don't care about the reparse tag here
    is_reparse_dir = attributes.bits_set?(LibC::FILE_ATTRIBUTE_REPARSE_POINT) && attributes.bits_set?(LibC::FILE_ATTRIBUTE_DIRECTORY)
    result = is_reparse_dir ? LibC._wrmdir(win_path) : LibC._wunlink(win_path)
    return true if result == 0
    LibC.SetFileAttributesW(win_path, attributes) if read_only_removed
    raise ::File::Error.from_errno("Error deleting file", file: path)
  end

  private REALPATH_SYMLINK_LIMIT = 100

  private def self.realpath?(path : String) : String?
    REALPATH_SYMLINK_LIMIT.times do
      win_path = System.to_wstr(path)

      realpath = System.retry_wstr_buffer do |buffer, small_buf|
        len = LibC.GetFullPathNameW(win_path, buffer.size, buffer, nil)
        if 0 < len < buffer.size
          break String.from_utf16(buffer[0, len])
        elsif small_buf && len > 0
          next len
        else
          raise ::File::Error.from_winerror("Error resolving real path", file: path)
        end
      end

      if symlink_info = symlink_info?(realpath)
        new_path, is_relative = symlink_info
        path = is_relative ? ::File.expand_path(new_path, ::File.dirname(realpath)) : new_path
        next
      end

      return exists?(realpath, follow_symlinks: false) ? realpath : nil
    end

    raise ::File::Error.from_os_error("Too many symbolic links", Errno::ELOOP, file: path)
  end

  def self.realpath(path : String) : String
    realpath?(path) || raise ::File::Error.from_os_error("Error resolving real path", Errno::ENOENT, file: path)
  end

  def self.link(old_path : String, new_path : String) : Nil
    if LibC.CreateHardLinkW(System.to_wstr(new_path), System.to_wstr(old_path), nil) == 0
      raise ::File::Error.from_winerror("Error creating link", file: old_path, other: new_path)
    end
  end

  def self.symlink(old_path : String, new_path : String) : Nil
    win_old_path = System.to_wstr(old_path)
    win_new_path = System.to_wstr(new_path)
    info = info?(old_path, true)
    flags = info.try(&.type.directory?) ? LibC::SYMBOLIC_LINK_FLAG_DIRECTORY : 0

    # Symlink on Windows required the SeCreateSymbolicLink privilege. But in the Windows 10
    # Creators Update (1703), Microsoft added the SYMBOLIC_LINK_FLAG_ALLOW_UNPRIVILEGED_CREATE
    # flag, that allows creation symlink without SeCreateSymbolicLink privilege if the computer
    # is in Developer Mode.
    result = LibC.CreateSymbolicLinkW(win_new_path, win_old_path, flags | LibC::SYMBOLIC_LINK_FLAG_ALLOW_UNPRIVILEGED_CREATE)

    # If we get an error like ERROR_INVALID_PARAMETER, it means that we have an
    # older Windows. Retry without SYMBOLIC_LINK_FLAG_ALLOW_UNPRIVILEGED_CREATE
    # flag.
    if result == 0 && WinError.value == WinError::ERROR_INVALID_PARAMETER
      result = LibC.CreateSymbolicLinkW(win_new_path, win_old_path, flags)
    end

    if result == 0
      raise ::File::Error.from_winerror("Error creating symlink", file: old_path, other: new_path)
    end
  end

  private def self.symlink_info?(path)
    handle = LibC.CreateFileW(
      System.to_wstr(path),
      LibC::ACCESS_MASK::FILE_READ_ATTRIBUTES,
      LibC::DEFAULT_SHARE_MODE,
      nil,
      LibC::OPEN_EXISTING,
      LibC::FILE_FLAG_BACKUP_SEMANTICS | LibC::FILE_FLAG_OPEN_REPARSE_POINT,
      LibC::HANDLE.null
    )

    return nil if handle == LibC::INVALID_HANDLE_VALUE

    begin
      with_reparse_data_buffer do |buf, size|
        if LibC.DeviceIoControl(handle, LibC::FSCTL_GET_REPARSE_POINT, nil, 0, buf, size, out _, nil) != 0
          reparse_data = buf.as(LibC::REPARSE_DATA_BUFFER*)
          if reparse_data.value.reparseTag == LibC::IO_REPARSE_TAG_SYMLINK
            symlink_data = reparse_data.value.dummyUnionName.symbolicLinkReparseBuffer
            path_buffer = reparse_data.value.dummyUnionName.symbolicLinkReparseBuffer.pathBuffer.to_unsafe.as(UInt8*)
            is_relative = symlink_data.flags.bits_set?(LibC::SYMLINK_FLAG_RELATIVE)

            # the print name is not necessarily set; fall back to substitute
            # name if unavailable
            if (name_len = symlink_data.printNameLength) > 0
              name_ptr = path_buffer + symlink_data.printNameOffset
              name = String.from_utf16(Slice.new(name_ptr, name_len).unsafe_slice_of(UInt16))
              return {name, is_relative}
            end

            name_len = symlink_data.substituteNameLength
            name_ptr = path_buffer + symlink_data.substituteNameOffset
            name = String.from_utf16(Slice.new(name_ptr, name_len).unsafe_slice_of(UInt16))
            # remove the internal prefix for NT paths which shows up when  e.g.
            # creating a symbolic link with an absolute source
            # TODO: support the other possible paths, for example see
            # https://github.com/golang/go/blob/ab28b834c4a38bd2295ee43eca4f9e38c28d54a2/src/os/file_windows.go#L362
            if name.starts_with?(%q(\??\)) && name[5]? == ':'
              name = name[4..]
            end
            return {name, is_relative}
          else
            raise ::File::Error.new("Not a symlink", file: path)
          end
        end
      end
    ensure
      LibC.CloseHandle(handle)
    end
  end

  private def self.with_reparse_data_buffer(&)
    size = 0x40
    buf = Pointer(UInt8).malloc(size)

    while true
      yield buf, size
      return nil if WinError.value != WinError::ERROR_MORE_DATA || size == LibC::MAXIMUM_REPARSE_DATA_BUFFER_SIZE
      size *= 2
      buf = buf.realloc(size)
    end
  end

  def self.readlink(path) : String
    info = symlink_info?(path) || raise ::File::Error.new("Cannot read link", file: path)
    path, _is_relative = info
    path
  end

  def self.rename(old_path : String, new_path : String) : ::File::Error?
    if LibC.MoveFileExW(System.to_wstr(old_path), System.to_wstr(new_path), LibC::MOVEFILE_REPLACE_EXISTING) == 0
      ::File::Error.from_winerror("Error renaming file", file: old_path, other: new_path)
    end
  end

  def self.utime(access_time : ::Time, modification_time : ::Time, path : String) : Nil
    atime = Crystal::System::Time.to_filetime(access_time)
    mtime = Crystal::System::Time.to_filetime(modification_time)
    handle = LibC.CreateFileW(
      System.to_wstr(path),
      LibC::ACCESS_MASK::FILE_WRITE_ATTRIBUTES,
      LibC::FILE_SHARE_READ | LibC::FILE_SHARE_WRITE | LibC::FILE_SHARE_DELETE,
      nil,
      LibC::OPEN_EXISTING,
      LibC::FILE_FLAG_BACKUP_SEMANTICS,
      LibC::HANDLE.null
    )
    if handle == LibC::INVALID_HANDLE_VALUE
      raise ::File::Error.from_winerror("Error setting time on file", file: path)
    end
    begin
      if LibC.SetFileTime(handle, nil, pointerof(atime), pointerof(mtime)) == 0
        raise ::File::Error.from_winerror("Error setting time on file", file: path)
      end
    ensure
      LibC.CloseHandle(handle)
    end
  end

  def self.futimens(path : String, fd : Int, access_time : ::Time, modification_time : ::Time) : Nil
    # TODO: use fd instead of path
    utime access_time, modification_time, path
  end

  private def system_truncate(size : Int) : Nil
    if LibC._chsize_s(fd, size) != 0
      raise ::File::Error.from_errno("Error truncating file", file: path)
    end
  end

  private def system_flock_shared(blocking : Bool) : Nil
    flock(false, blocking)
  end

  private def system_flock_exclusive(blocking : Bool) : Nil
    flock(true, blocking)
  end

  private def system_flock_unlock : Nil
    unlock_file(windows_handle)
  end

  private def flock(exclusive, retry)
    flags = LibC::LOCKFILE_FAIL_IMMEDIATELY
    flags |= LibC::LOCKFILE_EXCLUSIVE_LOCK if exclusive

    handle = windows_handle
    if retry
      until lock_file(handle, flags)
        sleep 0.1
      end
    else
      lock_file(handle, flags) || raise IO::Error.from_winerror("Error applying file lock: file is already locked")
    end
  end

  private def lock_file(handle, flags)
    # lpOverlapped must be provided despite the synchronous use of this method.
    overlapped = LibC::OVERLAPPED.new
    # lock the entire file with offset 0 in overlapped and number of bytes set to max value
    if 0 != LibC.LockFileEx(handle, flags, 0, 0xFFFF_FFFF, 0xFFFF_FFFF, pointerof(overlapped))
      true
    else
      winerror = WinError.value
      if winerror == WinError::ERROR_LOCK_VIOLATION
        false
      else
        raise IO::Error.from_os_error("LockFileEx", winerror)
      end
    end
  end

  private def unlock_file(handle)
    # lpOverlapped must be provided despite the synchronous use of this method.
    overlapped = LibC::OVERLAPPED.new
    # unlock the entire file with offset 0 in overlapped and number of bytes set to max value
    if 0 == LibC.UnlockFileEx(handle, 0, 0xFFFF_FFFF, 0xFFFF_FFFF, pointerof(overlapped))
      raise IO::Error.from_winerror("UnLockFileEx")
    end
  end

  private def system_fsync(flush_metadata = true) : Nil
    if LibC._commit(fd) != 0
      raise IO::Error.from_errno("Error syncing file")
    end
  end
end
