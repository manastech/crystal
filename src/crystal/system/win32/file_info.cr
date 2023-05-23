module Crystal::System::FileInfo
  protected getter file_attributes

  def initialize(@file_attributes : LibC::BY_HANDLE_FILE_INFORMATION, @file_type : LibC::DWORD, @reparse_tag : LibC::DWORD, @system_permissions : ::File::Permissions)
    if @file_attributes.dwFileAttributes.bits_set? LibC::FILE_ATTRIBUTE_READONLY
      @system_permissions &= ::File::Permissions.new(0o333)
    end
  end

  def initialize(@file_type : LibC::DWORD)
    @file_attributes = LibC::BY_HANDLE_FILE_INFORMATION.new
    @reparse_tag = LibC::DWORD.new(0)
    @system_permissions = ::File::Permissions.new(0o666)
  end

  def system_size : Int64
    ((@file_attributes.nFileSizeHigh.to_u64 << 32) | @file_attributes.nFileSizeLow.to_u64).to_i64
  end

  getter system_permissions : ::File::Permissions

  def system_type : ::File::Type
    case @file_type
    when LibC::FILE_TYPE_PIPE
      ::File::Type::Pipe
    when LibC::FILE_TYPE_CHAR
      ::File::Type::CharacterDevice
    when LibC::FILE_TYPE_DISK
      # See: https://msdn.microsoft.com/en-us/library/windows/desktop/aa365511(v=vs.85).aspx
      if @file_attributes.dwFileAttributes.bits_set?(LibC::FILE_ATTRIBUTE_REPARSE_POINT) &&
         @reparse_tag == LibC::IO_REPARSE_TAG_SYMLINK
        ::File::Type::Symlink
      elsif @file_attributes.dwFileAttributes.bits_set? LibC::FILE_ATTRIBUTE_DIRECTORY
        ::File::Type::Directory
      else
        ::File::Type::File
      end
    else
      ::File::Type::Unknown
    end
  end

  def system_flags : ::File::Flags
    ::File::Flags::None
  end

  def system_modification_time : ::Time
    Time.from_filetime(@file_attributes.ftLastWriteTime)
  end

  def system_owner_id : String
    "0"
  end

  def system_group_id : String
    "0"
  end

  def system_same_file?(other : self) : Bool
    return false if type.symlink? || type.pipe? || type.character_device?

    @file_attributes.dwVolumeSerialNumber == other.file_attributes.dwVolumeSerialNumber &&
      @file_attributes.nFileIndexHigh == other.file_attributes.nFileIndexHigh &&
      @file_attributes.nFileIndexLow == other.file_attributes.nFileIndexLow
  end
end
