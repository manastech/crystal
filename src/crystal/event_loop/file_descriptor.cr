abstract class Crystal::EventLoop
  module FileDescriptor
    # Reads at least one byte from the file descriptor into *slice*.
    #
    # Blocks the current fiber if no data is available for reading, continuing
    # when available. Otherwise returns immediately.
    #
    # Returns the number of bytes read (up to `slice.size`).
    # Returns 0 when EOF is reached.
    abstract def read(file_descriptor : Crystal::System::FileDescriptor, slice : Bytes) : Int32

    # Blocks the current fiber until the file descriptor is ready for read.
    abstract def wait_readable(file_descriptor : Crystal::System::FileDescriptor) : Nil

    # Writes at least one byte from *slice* to the file descriptor.
    #
    # Blocks the current fiber if the file descriptor isn't ready for writing,
    # continuing when ready. Otherwise returns immediately.
    #
    # Returns the number of bytes written (up to `slice.size`).
    abstract def write(file_descriptor : Crystal::System::FileDescriptor, slice : Bytes) : Int32

    # Blocks the current fiber until the file descriptor is ready for write.
    abstract def wait_writable(file_descriptor : Crystal::System::FileDescriptor) : Nil

    # Closes the file descriptor resource.
    abstract def close(file_descriptor : Crystal::System::FileDescriptor) : Nil
  end

  # Removes the file descriptor from the event loop. Can be used to free up
  # memory resources associated with the file descriptor, as well as removing
  # the file descriptor from kernel data structures.
  #
  # Called by `::IO::FileDescriptor#finalize` before closing the file
  # descriptor. Errors shall be silently ignored.
  def self.remove(file_descriptor : Crystal::System::FileDescriptor) : Nil
    backend_class.remove_impl(file_descriptor)
  end

  # Actual implementation for `.remove`. Must be implemented on a subclass of
  # `Crystal::EventLoop` when needed.
  protected def self.remove_impl(file_descriptor : Crystal::System::FileDescriptor) : Nil
  end
end
