require "c/winreg"
require "c/regapix"

module Crystal::System::WindowsRegistry
  # Opens a subkey at path *name* and returns the new key handle or `nil` if it
  # does not exist.
  #
  # Users need to ensure the opened key will be closed after usage (see `#close`).
  # *sam* specifies desired access rights to the key to be opened.
  def self.open?(handle : LibC::HKEY, name : Slice(UInt16), sam = LibC::REGSAM::KEY_READ)
    status = LibC.RegOpenKeyExW(handle, name, 0, sam, out sub_handle)
    status = WinError.new(status)

    case status
    when .error_success?
      sub_handle
    when .error_file_not_found?
      # key does not exist
      nil
    else
      raise RuntimeError.from_os_error("RegOpenKeyExW", status)
    end
  end

  def self.open?(handle : LibC::HKEY, name : Slice(UInt16), sam = LibC::REGSAM::KEY_READ, &)
    key_handle = open?(handle, name, sam)

    return unless key_handle

    begin
      yield key_handle
    ensure
      close key_handle
    end
  end

  # Closes the handle.
  def self.close(handle : LibC::HKEY) : Nil
    status = LibC.RegCloseKey(handle)
    status = WinError.new(status)

    unless status.error_success? || status.error_invalid_handle?
      raise RuntimeError.from_os_error("RegCloseKey", status)
    end
  end

  # Iterates all value names in this key and yields them to the block.
  def self.each_name(handle : LibC::HKEY, &block : Slice(UInt16) -> Nil) : Nil
    status = LibC.RegQueryInfoKeyW(handle, nil, nil, nil, out sub_key_count, out max_sub_key_length, nil, nil, nil, nil, nil, nil)
    status = WinError.new(status)

    return unless status.error_success?

    buffer = Slice(UInt16).new(max_sub_key_length + 1)

    sub_key_count.times do |i|
      length = buffer.size.to_u32
      status = LibC.RegEnumKeyExW(handle, i, buffer, pointerof(length), nil, nil, nil, nil)
      status = WinError.new(status)

      case status
      when .error_success?
        yield buffer[0, length]
      when .error_no_more_items?
        break
      else
        raise RuntimeError.from_os_error("RegEnumValueW", status)
      end
    end
  end

  # Reads a raw value into a buffer and creates a string from it.
  def self.get_string(handle : LibC::HKEY, name : Slice(UInt16))
    Crystal::System.retry_wstr_buffer do |buffer, small_buf|
      raw = get_raw(handle, name, buffer.to_unsafe_bytes) || return
      _, length = raw

      if 0 <= length <= buffer.size
        return String.from_utf16(buffer[0, length // 2 - 1])
      elsif small_buf && length > 0
        next length
      else
        raise RuntimeError.new("RegQueryValueExW retry buffer")
      end
    end
  end

  # Reads a raw value into a buffer.
  def self.get_raw(handle : LibC::HKEY, name : Slice(UInt16), buffer : Slice(UInt8))
    length = buffer.size.to_u32
    status = LibC.RegQueryValueExW(handle, name, nil, out valtype, buffer, pointerof(length))
    status = WinError.new(status)
    case status
    when .error_success?
      {valtype, length}
    when .error_file_not_found?
      nil
    when .error_more_data?
      {valtype, length}
    else
      raise RuntimeError.from_os_error("RegQueryValueExW", status)
    end
  end
end
