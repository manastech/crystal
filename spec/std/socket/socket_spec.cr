require "./spec_helper"
require "../../support/tempfile"
require "../../support/win32"

# TODO: Windows networking in the interpreter requires #12495
{% if flag?(:interpreted) && flag?(:win32) %}
  pending Socket
  {% skip_file %}
{% end %}

describe Socket, tags: "network" do
  describe ".unix" do
    it "creates a unix socket" do
      sock = Socket.unix
      sock.should be_a(Socket)
      sock.family.should eq(Socket::Family::UNIX)
      sock.type.should eq(Socket::Type::STREAM)

      # Datagram socket type is not supported on Windows yet:
      # https://devblogs.microsoft.com/commandline/af_unix-comes-to-windows/#unsupportedunavailable
      # https://github.com/microsoft/WSL/issues/5272
      {% unless flag?(:win32) %}
        sock = Socket.unix(Socket::Type::DGRAM)
        sock.type.should eq(Socket::Type::DGRAM)
      {% end %}

      {% unless flag?(:freebsd) %}
        # for some reason this doesn't fail on freebsd
        error = expect_raises(Socket::Error) do
          TCPSocket.new(family: :unix)
        end
        error.os_error.should eq({% if flag?(:win32) %}
          WinError::WSAEPROTONOSUPPORT
        {% elsif flag?(:wasi) %}
          WasiError::PROTONOSUPPORT
        {% else %}
          Errno.new(LibC::EPROTONOSUPPORT)
        {% end %})
      {% end %}
    end
  end

  describe "#tty?" do
    it "with non TTY" do
      Socket.new(Socket::Family::INET, Socket::Type::STREAM, Socket::Protocol::TCP).tty?.should be_false
    end
  end

  it ".accept" do
    client_done = Channel(Nil).new
    server = Socket.new(Socket::Family::INET, Socket::Type::STREAM, Socket::Protocol::TCP)

    begin
      port = unused_local_port
      server.bind("0.0.0.0", port)
      server.listen

      spawn do
        TCPSocket.new("127.0.0.1", port).close
      ensure
        client_done.send nil
      end

      client = server.accept
      begin
        client.family.should eq(Socket::Family::INET)
        client.type.should eq(Socket::Type::STREAM)
        client.protocol.should eq(Socket::Protocol::TCP)
        client.close_on_exec?.should eq CLOSE_ON_EXEC_AVAILABLE
      ensure
        client.close
      end
    ensure
      server.close
      client_done.receive
    end
  end

  it "accept raises timeout error if read_timeout is specified" do
    server = Socket.new(Socket::Family::INET, Socket::Type::STREAM, Socket::Protocol::TCP)
    port = unused_local_port
    server.bind("0.0.0.0", port)
    server.read_timeout = 0.1.seconds
    server.listen

    expect_raises(IO::TimeoutError) { server.accept }
    expect_raises(IO::TimeoutError) { server.accept? }
  ensure
    server.try &.close
  end

  it "sends messages" do
    port = unused_local_port
    server = Socket.tcp(Socket::Family::INET)
    server.bind("127.0.0.1", port)
    server.listen
    address = Socket::IPAddress.new("127.0.0.1", port)
    spawn do
      client = server.not_nil!.accept
      client.gets.should eq "foo"
      client.puts "bar"
    ensure
      client.try &.close
    end
    socket = Socket.tcp(Socket::Family::INET)
    socket.connect(address)
    socket.puts "foo"
    socket.gets.should eq "bar"
  ensure
    socket.try &.close
    server.try &.close
  end

  # Datagram socket type is not supported on Windows yet
  {% unless flag?(:win32) %}
    it "sends datagram over unix socket" do
      with_tempfile("datagram_unix") do |path|
        server = Socket.unix(Socket::Type::DGRAM)
        server.bind Socket::UNIXAddress.new(path)

        client = Socket.unix(Socket::Type::DGRAM)
        client.connect Socket::UNIXAddress.new(path)
        client.send "foo"

        message, _ = server.receive
        message.should eq "foo"
      end
    end
  {% end %}

  describe "#bind" do
    each_ip_family do |family, _, any_address|
      it "binds to port" do
        socket = TCPSocket.new family
        socket.bind(any_address, 0)
        socket.listen

        address = socket.local_address.as(Socket::IPAddress)
        address.address.should eq(any_address)
        address.port.should be > 0
      ensure
        socket.try &.close
      end

      it "binds to port using Socket::IPAddress" do
        socket = TCPSocket.new family
        socket.bind Socket::IPAddress.new(any_address, 0)
        socket.listen

        address = socket.local_address.as(Socket::IPAddress)
        address.address.should eq(any_address)
        address.port.should be > 0
      ensure
        socket.try &.close
      end

      it "binds to port using default IP" do
        socket = TCPSocket.new family
        socket.bind unused_local_port
        socket.listen

        address = socket.local_address.as(Socket::IPAddress)
        address.address.should eq(any_address)
        address.port.should be > 0

        socket.close

        socket = UDPSocket.new family
        socket.bind unused_local_port
        socket.close
      end
    end
  end

  it "closes on exec by default" do
    socket = Socket.new(Socket::Family::INET, Socket::Type::STREAM, Socket::Protocol::TCP)
    socket.close_on_exec?.should eq CLOSE_ON_EXEC_AVAILABLE
  end

  describe "#finalize" do
    it "does not flush" do
      port = unused_local_port
      server = Socket.tcp(Socket::Family::INET)
      server.bind("127.0.0.1", port)
      server.listen

      spawn do
        client = server.not_nil!.accept
        client.sync = false
        client << "foo"
        client.flush
        client << "bar"
        client.finalize
      ensure
        client.try(&.close) rescue nil
      end

      socket = Socket.tcp(Socket::Family::INET)
      socket.connect(Socket::IPAddress.new("127.0.0.1", port))

      socket.gets.should eq "foo"
    ensure
      socket.try &.close
      server.try &.close
    end
  end
end
