# :nodoc:
class Crystal::EventLoop::Wasi < Crystal::EventLoop
  # Runs the event loop.
  def run(blocking : Bool) : Bool
    raise NotImplementedError.new("Crystal::Wasi::EventLoop.run")
  end

  def interrupt : Nil
    raise NotImplementedError.new("Crystal::Wasi::EventLoop.interrupt")
  end

  # Create a new resume event for a fiber.
  def create_resume_event(fiber : Fiber) : Crystal::EventLoop::Event
    raise NotImplementedError.new("Crystal::Wasi::EventLoop.create_resume_event")
  end

  # Creates a timeout_event.
  def create_timeout_event(fiber) : Crystal::EventLoop::Event
    raise NotImplementedError.new("Crystal::Wasi::EventLoop.create_timeout_event")
  end

  # Creates a write event for a file descriptor.
  def create_fd_write_event(io : IO::Evented, edge_triggered : Bool = false) : Crystal::EventLoop::Event
    raise NotImplementedError.new("Crystal::Wasi::EventLoop.create_fd_write_event")
  end

  # Creates a read event for a file descriptor.
  def create_fd_read_event(io : IO::Evented, edge_triggered : Bool = false) : Crystal::EventLoop::Event
    raise NotImplementedError.new("Crystal::Wasi::EventLoop.create_fd_read_event")
  end

  def read(file_descriptor : Crystal::System::FileDescriptor, slice : Bytes) : Int32
    evented_read(file_descriptor, "Error reading file_descriptor") do
      LibC.read(file_descriptor.fd, slice, slice.size).tap do |return_code|
        if return_code == -1 && Errno.value == Errno::EBADF
          raise IO::Error.new "File not open for reading", target: file_descriptor
        end
      end
    end
  end

  def wait_readable(file_descriptor : Crystal::System::FileDescriptor) : Nil
    file_descriptor.evented_wait_readable(raise_if_closed: false) do
      raise IO::TimeoutError.new("Read timed out")
    end
  end

  def write(file_descriptor : Crystal::System::FileDescriptor, slice : Bytes) : Int32
    evented_write(file_descriptor, "Error writing file_descriptor") do
      LibC.write(file_descriptor.fd, slice, slice.size).tap do |return_code|
        if return_code == -1 && Errno.value == Errno::EBADF
          raise IO::Error.new "File not open for writing", target: file_descriptor
        end
      end
    end
  end

  def wait_writable(file_descriptor : Crystal::System::FileDescriptor) : Nil
    file_descriptor.evented_wait_writable(raise_if_closed: false) do
      raise IO::TimeoutError.new("Write timed out")
    end
  end

  def close(file_descriptor : Crystal::System::FileDescriptor) : Nil
    file_descriptor.evented_close
  end

  def read(socket : ::Socket, slice : Bytes) : Int32
    evented_read(socket, "Error reading socket") do
      LibC.recv(socket.fd, slice, slice.size, 0).to_i32
    end
  end

  def wait_readable(socket : ::Socket) : Nil
    socket.evented_wait_readable do
      raise IO::TimeoutError.new("Read timed out")
    end
  end

  def write(socket : ::Socket, slice : Bytes) : Int32
    evented_write(socket, "Error writing to socket") do
      LibC.send(socket.fd, slice, slice.size, 0)
    end
  end

  def wait_writable(socket : ::Socket) : Nil
    socket.evented_wait_writable do
      raise IO::TimeoutError.new("Write timed out")
    end
  end

  def receive_from(socket : ::Socket, slice : Bytes) : Tuple(Int32, ::Socket::Address)
    raise NotImplementedError.new "Crystal::Wasi::EventLoop#receive_from"
  end

  def send_to(socket : ::Socket, slice : Bytes, address : ::Socket::Address) : Int32
    raise NotImplementedError.new "Crystal::Wasi::EventLoop#send_to"
  end

  def connect(socket : ::Socket, address : ::Socket::Addrinfo | ::Socket::Address, timeout : ::Time::Span | ::Nil) : IO::Error?
    raise NotImplementedError.new "Crystal::Wasi::EventLoop#connect"
  end

  def accept(socket : ::Socket) : ::Socket::Handle?
    raise NotImplementedError.new "Crystal::Wasi::EventLoop#accept"
  end

  def close(socket : ::Socket) : Nil
    socket.evented_close
  end

  def evented_read(target, errno_msg : String, &) : Int32
    loop do
      bytes_read = yield
      if bytes_read != -1
        # `to_i32` is acceptable because `Slice#size` is an Int32
        return bytes_read.to_i32
      end

      if Errno.value == Errno::EAGAIN
        target.wait_readable
      else
        raise IO::Error.from_errno(errno_msg, target: target)
      end
    end
  ensure
    target.evented_resume_pending_readers
  end

  def evented_write(target, errno_msg : String, &) : Int32
    begin
      loop do
        bytes_written = yield
        if bytes_written != -1
          return bytes_written.to_i32
        end

        if Errno.value == Errno::EAGAIN
          target.wait_writable
        else
          raise IO::Error.from_errno(errno_msg, target: target)
        end
      end
    ensure
      target.evented_resume_pending_writers
    end
  end
end

struct Crystal::EventLoop::Wasi::Event
  include Crystal::EventLoop::Event

  def add(timeout : Time::Span) : Nil
  end

  def add(timeout : Nil) : Nil
  end

  def free : Nil
  end

  def delete
  end
end
