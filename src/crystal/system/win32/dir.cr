require "crystal/system/windows"
require "c/winbase"
require "c/direct"
require "c/handleapi"
require "c/processenv"

module Crystal::System::Dir
  private class DirHandle
    property iter_handle : LibC::HANDLE
    property file_handle : LibC::HANDLE = LibC::INVALID_HANDLE_VALUE
    getter query : LibC::LPWSTR

    def initialize(@iter_handle, @query)
    end
  end

  def self.open(path : String) : DirHandle
    unless ::Dir.exists? path
      raise ::File::Error.from_os_error("Error opening directory", Errno::ENOENT, file: path)
    end

    DirHandle.new(LibC::INVALID_HANDLE_VALUE, System.to_wstr(path + "\\*"))
  end

  def self.next_entry(dir : DirHandle, path : String) : Entry?
    if dir.iter_handle == LibC::INVALID_HANDLE_VALUE
      # Directory is at start, use FindFirstFile
      handle = LibC.FindFirstFileW(dir.query, out data)
      if handle != LibC::INVALID_HANDLE_VALUE
        dir.iter_handle = handle
        data_to_entry(data)
      else
        error = WinError.value
        if error == WinError::ERROR_FILE_NOT_FOUND
          nil
        else
          raise ::File::Error.from_os_error("Error reading directory entries", error, file: path)
        end
      end
    else
      # Use FindNextFile
      if LibC.FindNextFileW(dir.iter_handle, out data_) != 0
        data_to_entry(data_)
      else
        error = WinError.value
        if error == WinError::ERROR_NO_MORE_FILES
          nil
        else
          raise ::File::Error.from_os_error("Error reading directory entries", error, file: path)
        end
      end
    end
  end

  def self.data_to_entry(data)
    name = String.from_utf16(data.cFileName.to_unsafe)[0]
    unless data.dwFileAttributes.bits_set?(LibC::FILE_ATTRIBUTE_REPARSE_POINT) && data.dwReserved0 == LibC::IO_REPARSE_TAG_SYMLINK
      dir = (data.dwFileAttributes & LibC::FILE_ATTRIBUTE_DIRECTORY) != 0
    end
    Entry.new(name, dir)
  end

  def self.rewind(dir : DirHandle) : Nil
    close(dir)
  end

  def self.info(dir : DirHandle, path) : ::File::Info
    if dir.file_handle == LibC::INVALID_HANDLE_VALUE
      handle = LibC.CreateFileW(
        System.to_wstr(path),
        LibC::ACCESS_MASK::FILE_READ_ATTRIBUTES | LibC::ACCESS_MASK::READ_CONTROL,
        LibC::FILE_SHARE_READ | LibC::FILE_SHARE_WRITE | LibC::FILE_SHARE_DELETE,
        nil,
        LibC::OPEN_EXISTING,
        LibC::FILE_FLAG_BACKUP_SEMANTICS,
        LibC::HANDLE.null,
      )

      if handle == LibC::INVALID_HANDLE_VALUE
        raise ::File::Error.from_winerror("Unable to get directory info", file: path)
      end

      dir.file_handle = handle
    end

    Crystal::System::FileDescriptor.system_info dir.file_handle, LibC::FILE_TYPE_DISK
  end

  def self.close(dir : DirHandle, path : String) : Nil
    close_iter(dir.iter_handle, path)
    close_file(dir.file_handle, path)
    dir.iter_handle = dir.file_handle = LibC::INVALID_HANDLE_VALUE
  end

  private def self.close_iter(handle : LibC::HANDLE, path : String) : Nil
    return if handle == LibC::INVALID_HANDLE_VALUE

    if LibC.FindClose(handle) == 0
      raise ::File::Error.from_winerror("Error closing directory", file: path)
    end
  end

  private def self.close_file(handle : LibC::HANDLE, path : String) : Nil
    return if handle == LibC::INVALID_HANDLE_VALUE

    if LibC.CloseHandle(handle) == 0
      raise ::File::Error.from_winerror("CloseHandle", file: path)
    end
  end

  def self.current : String
    System.retry_wstr_buffer do |buffer, small_buf|
      len = LibC.GetCurrentDirectoryW(buffer.size, buffer)
      if 0 < len < buffer.size
        return String.from_utf16(buffer[0, len])
      elsif small_buf && len > 0
        next len
      else
        raise ::File::Error.from_winerror("Error getting current directory", file: "./")
      end
    end
  end

  def self.current=(path : String) : String
    if LibC.SetCurrentDirectoryW(System.to_wstr(path)) == 0
      raise ::File::Error.from_winerror("Error while changing directory", file: path)
    end

    path
  end

  def self.tempdir : String
    tmpdir = System.retry_wstr_buffer do |buffer, small_buf|
      len = LibC.GetTempPathW(buffer.size, buffer)
      if 0 < len < buffer.size
        break String.from_utf16(buffer[0, len])
      elsif small_buf && len > 0
        next len
      else
        raise RuntimeError.from_winerror("Error getting temporary directory")
      end
    end

    tmpdir.rchop("\\")
  end

  def self.create(path : String, mode : Int32) : Nil
    if LibC._wmkdir(System.to_wstr(path)) == -1
      raise ::File::Error.from_errno("Unable to create directory", file: path)
    end
  end

  def self.delete(path : String, *, raise_on_missing : Bool) : Bool
    win_path = System.to_wstr(path)

    attributes = LibC.GetFileAttributesW(win_path)
    if attributes == LibC::INVALID_FILE_ATTRIBUTES
      File.check_not_found_error("Unable to remove directory", path)
      raise ::File::Error.from_os_error("Unable to remove directory", Errno::ENOENT, file: path) if raise_on_missing
      return false
    end

    # all reparse point directories should be deleted like a directory, not just
    # symbolic links, so we don't care about the reparse tag here
    if attributes.bits_set?(LibC::FILE_ATTRIBUTE_REPARSE_POINT) && attributes.bits_set?(LibC::FILE_ATTRIBUTE_DIRECTORY)
      # maintain consistency with POSIX, and treat all reparse points (including
      # symbolic links) as non-directories
      raise ::File::Error.new("Cannot remove directory that is a reparse point: '#{path.inspect_unquoted}'", file: path)
    end

    return true if LibC._wrmdir(win_path) == 0
    raise ::File::Error.from_errno("Unable to remove directory", file: path)
  end
end
