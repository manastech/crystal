require "../unix/file_descriptor"

# :nodoc:
module Crystal::System::FileDescriptor
  def self.from_stdio(fd)
    IO::FileDescriptor.new(fd).tap(&.flush_on_newline=(true))
  end

  def self.pipe(read_blocking, write_blocking)
    raise NotImplementedError.new "Crystal::System::FileDescriptor.pipe"
  end

  private def system_reopen(other : IO::FileDescriptor)
    raise NotImplementedError.new "Crystal::System::FileDescriptor.system_reopen"
  end
end
