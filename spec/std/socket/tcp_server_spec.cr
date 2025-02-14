{% skip_file if flag?(:wasm32) %}

require "./spec_helper"

describe TCPServer, tags: "network" do
  describe ".new" do
    each_ip_family do |family, address|
      it "listens on local address" do
        port = unused_local_port

        server = TCPServer.new(address, port)

        server.reuse_port?.should be_false
        server.reuse_address?.should be_true

        local_address = Socket::IPAddress.new(address, port)
        server.local_address.should eq local_address

        server.closed?.should be_false

        server.close

        server.closed?.should be_true
        expect_raises(Socket::Error, "getsockname: ") do
          server.local_address
        end
      end

      it "binds to port 0" do
        server = TCPServer.new(address, 0)

        begin
          server.local_address.address.should eq(address)
          server.local_address.port.should be > 0
        ensure
          server.close
        end
      end

      it "raises when port is negative" do
        error = expect_raises(Socket::Addrinfo::Error) do
          TCPServer.new(address, -12)
        end
        error.os_error.should eq({% if flag?(:win32) %}
          WinError::WSATYPE_NOT_FOUND
        {% elsif (flag?(:linux) && !flag?(:android)) || flag?(:openbsd) %}
          Errno.new(LibC::EAI_SERVICE)
        {% else %}
          Errno.new(LibC::EAI_NONAME)
        {% end %})
      end

      describe "reuse_port" do
        it "raises when port is in use" do
          TCPServer.open(address, 0) do |server|
            expect_raises(Socket::BindError, "Could not bind to '#{address}:#{server.local_address.port}': ") do
              TCPServer.open(address, server.local_address.port) { }
            end
          end
        end

        it "raises when not binding with reuse_port" do
          TCPServer.open(address, 0, reuse_port: true) do |server|
            expect_raises(Socket::BindError) do
              TCPServer.open(address, server.local_address.port) { }
            end
          end
        end

        it "raises when port is not ready to be reused" do
          TCPServer.open(address, 0) do |server|
            expect_raises(Socket::BindError) do
              TCPServer.open(address, server.local_address.port, reuse_port: true) { }
            end
          end
        end

        it "binds to used port with reuse_port = true" do
          TCPServer.open(address, 0, reuse_port: true) do |server|
            TCPServer.open(address, server.local_address.port, reuse_port: true) { }
          end
        end
      end
    end

    describe "address resolution" do
      it "binds to localhost" do
        server = TCPServer.new("localhost", unused_local_port)
        server.close
      end

      it "raises when host doesn't exist" do
        err = expect_raises(Socket::Error, "Hostname lookup for doesnotexist.example.org. failed") do
          TCPServer.new("doesnotexist.example.org.", 12345)
        end
        # FIXME: Resolve special handling for win32. The error code handling should be identical.
        {% if flag?(:win32) %}
          [WinError::WSAHOST_NOT_FOUND, WinError::WSATRY_AGAIN].should contain err.os_error
        {% elsif flag?(:android) || flag?(:netbsd) || flag?(:openbsd) %}
          err.os_error.should eq(Errno.new(LibC::EAI_NODATA))
        {% else %}
          [Errno.new(LibC::EAI_NONAME), Errno.new(LibC::EAI_AGAIN)].should contain err.os_error
        {% end %}
      end

      it "raises (rather than segfault on darwin) when host doesn't exist and port is 0" do
        err = expect_raises(Socket::Error, "Hostname lookup for doesnotexist.example.org. failed") do
          TCPServer.new("doesnotexist.example.org.", 0)
        end
        # FIXME: Resolve special handling for win32. The error code handling should be identical.
        {% if flag?(:win32) %}
          [WinError::WSAHOST_NOT_FOUND, WinError::WSATRY_AGAIN].should contain err.os_error
        {% elsif flag?(:android) || flag?(:netbsd) || flag?(:openbsd) %}
          err.os_error.should eq(Errno.new(LibC::EAI_NODATA))
        {% else %}
          [Errno.new(LibC::EAI_NONAME), Errno.new(LibC::EAI_AGAIN)].should contain err.os_error
        {% end %}
      end
    end

    it "binds to all interfaces" do
      port = unused_local_port
      TCPServer.open(Socket::IPAddress::UNSPECIFIED, port) do |server|
        server.local_address.port.should eq port
      end
    end
  end

  {% if flag?(:linux) || flag?(:solaris) %}
    pending "settings"
  {% else %}
    it "settings" do
      TCPServer.open("::", unused_local_port) do |server|
        (server.recv_buffer_size = 42).should eq 42
        server.recv_buffer_size.should eq 42
      end
    end
  {% end %}

  describe "accept" do
    it "sets close on exec flag" do
      TCPServer.open("localhost", 0) do |server|
        TCPSocket.open("localhost", server.local_address.port) do |client|
          server.accept? do |sock|
            sock.close_on_exec?.should eq CLOSE_ON_EXEC_AVAILABLE
          end
        end
      end
    end
  end
end
