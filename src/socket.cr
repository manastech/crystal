require "crystal/system/socket"

class Socket < IO
  include IO::Buffered
  include Crystal::System::Socket

  # :nodoc:
  SOMAXCONN = 128

  @volatile_fd : Atomic(Handle)

  # Returns the handle associated with this socket from the operating system.
  #
  # * on POSIX platforms, this is a file descriptor (`Int32`)
  # * on Windows, this is a SOCKET handle (`LibC::SOCKET`)
  def fd
    @volatile_fd.get
  end

  @closed : Bool

  getter family : Family
  getter type : Type
  getter protocol : Protocol

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

  # Creates a TCP socket. Consider using `TCPSocket` or `TCPServer` unless you
  # need full control over the socket.
  def self.tcp(family : Family, blocking = false) : self
    new(family, Type::STREAM, Protocol::TCP, blocking)
  end

  # Creates an UDP socket. Consider using `UDPSocket` unless you need full
  # control over the socket.
  def self.udp(family : Family, blocking = false)
    new(family, Type::DGRAM, Protocol::UDP, blocking)
  end

  # Creates an UNIX socket. Consider using `UNIXSocket` or `UNIXServer` unless
  # you need full control over the socket.
  def self.unix(type : Type = Type::STREAM, blocking = false) : self
    new(Family::UNIX, type, blocking: blocking)
  end

  def initialize(family : Family, type : Type, protocol : Protocol = Protocol::IP, blocking = false)
    # This method is `#initialize` instead of `.new` because it is used as super
    # constructor from subclasses.

    fd = create_handle(family, type, protocol, blocking)
    initialize(fd, family, type, protocol, blocking)
  end

  # Creates a Socket from an existing socket file descriptor / handle.
  def initialize(fd, @family : Family, @type : Type, @protocol : Protocol = Protocol::IP, blocking = false)
    @volatile_fd = Atomic.new(fd)
    @closed = false
    initialize_handle(fd)

    self.sync = true
    unless blocking
      self.blocking = false
    end
  end

  # Connects the socket to a remote host:port.
  #
  # ```
  # require "socket"
  #
  # sock = Socket.tcp(Socket::Family::INET)
  # sock.connect "crystal-lang.org", 80
  # ```
  def connect(host : String, port : Int, connect_timeout = nil) : Nil
    Addrinfo.resolve(host, port, @family, @type, @protocol) do |addrinfo|
      connect(addrinfo, timeout: connect_timeout)
    end
  end

  # Connects the socket to a remote address. Raises if the connection failed.
  #
  # ```
  # require "socket"
  #
  # sock = Socket.unix
  # sock.connect Socket::UNIXAddress.new("/tmp/service.sock")
  # ```
  def connect(addr, timeout = nil) : Nil
    connect(addr, timeout) { |error| raise error }
  end

  # Tries to connect to a remote address. Yields an `IO::TimeoutError` or an
  # `Socket::ConnectError` error if the connection failed.
  def connect(addr, timeout = nil, &)
    timeout = timeout.seconds unless timeout.is_a?(::Time::Span?)
    result = system_connect(addr, timeout)
    yield result if result.is_a?(Exception)
  end

  # Binds the socket to a local address.
  #
  # ```
  # require "socket"
  #
  # sock = Socket.tcp(Socket::Family::INET)
  # sock.bind "localhost", 1234
  # ```
  def bind(host : String, port : Int) : Nil
    Addrinfo.resolve(host, port, @family, @type, @protocol) do |addrinfo|
      system_bind(addrinfo, "#{host}:#{port}") { |errno| errno }
    end
  end

  # Binds the socket on *port* to all local interfaces.
  #
  # ```
  # require "socket"
  #
  # sock = Socket.tcp(Socket::Family::INET6)
  # sock.bind 1234
  # ```
  def bind(port : Int)
    if family.inet?
      address = "0.0.0.0"
      address_and_port = "0.0.0.0:#{port}"
    else
      address = "::"
      address_and_port = "[::]:#{port}"
    end

    Addrinfo.resolve(address, port, @family, @type, @protocol) do |addrinfo|
      system_bind(addrinfo, address_and_port) { |errno| errno }
    end
  end

  # Binds the socket to a local address.
  #
  # ```
  # require "socket"
  #
  # sock = Socket.udp(Socket::Family::INET)
  # sock.bind Socket::IPAddress.new("192.168.1.25", 80)
  # ```
  def bind(addr : Socket::Address) : Nil
    system_bind(addr, addr.to_s) { |errno| raise errno }
  end

  # Tells the previously bound socket to listen for incoming connections.
  def listen(backlog : Int = SOMAXCONN) : Nil
    listen(backlog) { |errno| raise errno }
  end

  # Tries to listen for connections on the previously bound socket.
  # Yields an `Socket::Error` on failure.
  def listen(backlog : Int = SOMAXCONN, &)
    system_listen(backlog) { |err| yield err }
  end

  # Accepts an incoming connection.
  #
  # Returns the client socket. Raises an `IO::Error` (closed stream) exception
  # if the server is closed after invoking this method.
  #
  # ```
  # require "socket"
  #
  # server = TCPServer.new(2202)
  # socket = server.accept
  # socket.puts Time.utc
  # socket.close
  # ```
  def accept : Socket
    accept? || raise Socket::Error.new("Closed stream")
  end

  # Accepts an incoming connection.
  #
  # Returns the client `Socket` or `nil` if the server is closed after invoking
  # this method.
  #
  # ```
  # require "socket"
  #
  # server = TCPServer.new(2202)
  # if socket = server.accept?
  #   socket.puts Time.utc
  #   socket.close
  # end
  # ```
  def accept? : Socket?
    if client_fd = system_accept
      sock = Socket.new(client_fd, family, type, protocol, blocking)
      sock.sync = sync?
      sock
    end
  end

  # Sends a message to a previously connected remote address.
  # Returns the number of bytes sent.
  # Does not guarantee that the entire message is sent. That's only the case
  # when the return value is equivalent to `message.bytesize`.
  # `#write` ensures the entire message is sent.
  #
  # ```
  # require "socket"
  #
  # sock = Socket.udp(Socket::Family::INET)
  # sock.connect("example.com", 2000)
  # sock.send("text message")
  #
  # sock = Socket.unix(Socket::Type::DGRAM)
  # sock.connect Socket::UNIXAddress.new("/tmp/service.sock")
  # sock.send(Bytes[0])
  # ```
  def send(message) : Int32
    system_write(message.to_slice)
  end

  # Sends a message to the specified remote address.
  # Returns the number of bytes sent.
  # Does not guarantee that the entire message is sent. That's only the case
  # when the return value is equivalent to `message.bytesize`.
  # `#write` ensures the entire message is sent but it requires an established connection.
  #
  # ```
  # require "socket"
  #
  # server = Socket::IPAddress.new("10.0.3.1", 2022)
  # sock = Socket.udp(Socket::Family::INET)
  # sock.connect("example.com", 2000)
  # sock.send("text query", to: server)
  # ```
  def send(message, to addr : Address) : Int32
    system_send_to(message.to_slice, addr)
  end

  # Receives a text message from the previously bound address.
  #
  # ```
  # require "socket"
  #
  # server = Socket.udp(Socket::Family::INET)
  # server.bind("localhost", 1234)
  #
  # message, client_addr = server.receive
  # ```
  def receive(max_message_size = 512) : {String, Address}
    address = nil
    message = String.new(max_message_size) do |buffer|
      bytes_read, address = system_receive_from(Slice.new(buffer, max_message_size))
      {bytes_read, 0}
    end
    {message, address.as(Address)}
  end

  # Receives a binary message from the previously bound address.
  #
  # ```
  # require "socket"
  #
  # server = Socket.udp(Socket::Family::INET)
  # server.bind("localhost", 1234)
  #
  # message = Bytes.new(32)
  # bytes_read, client_addr = server.receive(message)
  # ```
  def receive(message : Bytes) : {Int32, Address}
    system_receive_from(message)
  end

  # Calls `shutdown(2)` with `SHUT_RD`
  def close_read
    system_close_read
  end

  # Calls `shutdown(2)` with `SHUT_WR`
  def close_write
    system_close_write
  end

  def inspect(io : IO) : Nil
    io << "#<#{self.class}:fd #{fd}>"
  end

  def send_buffer_size : Int32
    system_send_buffer_size
  end

  def send_buffer_size=(val : Int32)
    self.system_send_buffer_size = val
    val
  end

  def recv_buffer_size : Int32
    system_recv_buffer_size
  end

  def recv_buffer_size=(val : Int32)
    self.system_recv_buffer_size = val
    val
  end

  def reuse_address? : Bool
    system_reuse_address?
  end

  def reuse_address=(val : Bool)
    self.system_reuse_address = val
    val
  end

  def reuse_port? : Bool
    system_reuse_port?
  end

  def reuse_port=(val : Bool)
    self.system_reuse_port = val
    val
  end

  def broadcast? : Bool
    system_broadcast?
  end

  def broadcast=(val : Bool)
    self.system_broadcast = val
    val
  end

  def keepalive?
    system_keepalive?
  end

  def keepalive=(val : Bool)
    self.system_keepalive = val
    val
  end

  def linger
    system_linger
  end

  # WARNING: The behavior of `SO_LINGER` is platform specific.
  # Bad things may happen especially with nonblocking sockets.
  # See [Cross-Platform Testing of SO_LINGER by Nybek](https://www.nybek.com/blog/2015/04/29/so_linger-on-non-blocking-sockets/)
  # for more information.
  #
  # * `nil`: disable `SO_LINGER`
  # * `Int`: enable `SO_LINGER` and set timeout to `Int` seconds
  #   * `0`: abort on close (socket buffer is discarded and RST sent to peer). Depends on platform and whether `shutdown()` was called first.
  #   * `>=1`: abort after `Int` seconds on close. Linux and Cygwin may block on close.
  def linger=(val : Int?)
    self.system_linger = val
  end

  # Returns the modified *optval*.
  protected def getsockopt(optname, optval, level = LibC::SOL_SOCKET)
    system_getsockopt(fd, optname, optval, level)
  end

  protected def getsockopt(optname, optval, level = LibC::SOL_SOCKET, &)
    system_getsockopt(fd, optname, optval, level) { |value| yield value }
  end

  protected def setsockopt(optname, optval, level = LibC::SOL_SOCKET)
    system_setsockopt(fd, optname, optval, level)
  end

  private def getsockopt_bool(optname, level = LibC::SOL_SOCKET)
    ret = getsockopt optname, 0, level
    ret != 0
  end

  private def setsockopt_bool(optname, optval : Bool, level = LibC::SOL_SOCKET)
    v = optval ? 1 : 0
    setsockopt optname, v, level
    optval
  end

  def blocking
    system_blocking?
  end

  def blocking=(value)
    self.system_blocking = value
  end

  def close_on_exec?
    system_close_on_exec?
  end

  def close_on_exec=(arg : Bool)
    self.system_close_on_exec = arg
  end

  def self.fcntl(fd, cmd, arg = 0)
    Crystal::System::Socket.fcntl(fd, cmd, arg)
  end

  def fcntl(cmd, arg = 0)
    self.class.fcntl fd, cmd, arg
  end

  # Finalizes the socket resource.
  #
  # This involves releasing the handle to the operating system, i.e. closing it.
  # It does *not* implicitly call `#flush`, so data waiting in the buffer may be
  # lost. By default write buffering is disabled, though (`sync? == true`).
  # It's recommended to always close the socket explicitly via `#close`.
  #
  # This method is a no-op if the file descriptor has already been closed.
  def finalize
    return if closed?

    Crystal::EventLoop.remove(self)
    socket_close { } # ignore error
  end

  def closed? : Bool
    @closed
  end

  def tty?
    system_tty?
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
    raise Socket::Error.new("Can't rewind")
  end

  private def unbuffered_close : Nil
    return if @closed

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

require "./socket/*"
