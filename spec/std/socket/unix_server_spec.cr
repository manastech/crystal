require "../spec_helper"
require "socket"
require "../../support/fibers"
require "../../support/channel"
require "../../support/tempfile"

# TODO: Windows networking in the interpreter requires #12495
{% if flag?(:interpreted) && flag?(:win32) %}
  pending UNIXServer
  {% skip_file %}
{% end %}

describe UNIXServer do
  describe ".new" do
    it "raises when path is too long" do
      with_tempfile("unix_server-too_long-#{("a" * 2048)}.sock") do |path|
        expect_raises(ArgumentError, "Path size exceeds the maximum size") do
          UNIXServer.new(path)
        end

        File.exists?(path).should be_false
      end
    end

    it "creates the socket file" do
      with_tempfile("unix_server.sock") do |path|
        UNIXServer.open(path) do
          File.exists?(path).should be_true
          File.info(path).type.socket?.should be_true
        end

        File.exists?(path).should be_false
      end
    end

    it "creates the socket file from `Path`" do
      with_tempfile("unix_server.sock") do |path|
        path = Path.new(path)
        UNIXServer.open(path) do
          File.exists?(path).should be_true
          File.info(path).type.socket?.should be_true
        end

        File.exists?(path).should be_false
      end
    end

    it "deletes socket file on close" do
      with_tempfile("unix_server-close.sock") do |path|
        server = UNIXServer.new(path)
        server.close

        File.exists?(path).should be_false
      end
    end

    it "raises when socket file already exists" do
      with_tempfile("unix_server-twice.sock") do |path|
        server = UNIXServer.new(path)

        begin
          expect_raises(Socket::BindError) do
            UNIXServer.new(path)
          end
        ensure
          server.close
        end
      end
    end

    it "won't delete existing file on bind failure" do
      with_tempfile("unix_server-exist.sock") do |path|
        File.write(path, "")
        File.exists?(path).should be_true

        expect_raises(Socket::BindError) do
          UNIXServer.new(path)
        end

        File.exists?(path).should be_true
      end
    end
  end

  describe "accept" do
    it "returns the client UNIXSocket" do
      with_tempfile("unix_server-accept.sock") do |path|
        UNIXServer.open(path) do |server|
          UNIXSocket.open(path) do |_|
            client = server.accept
            client.should be_a(UNIXSocket)
            client.close
          end
        end
      end
    end

    it "raises when server is closed" do
      with_tempfile("unix_server-closed.sock") do |path|
        server = UNIXServer.new(path)
        ch = Channel(SpecChannelStatus).new(1)
        exception = nil

        schedule_timeout ch

        f = spawn do
          begin
            ch.send(:begin)
            server.accept
          rescue ex
            exception = ex
          end
          ch.send(:end)
        end

        ch.receive.should eq SpecChannelStatus::Begin

        # wait for the server to call accept
        wait_until_blocked f

        server.close
        ch.receive.should eq SpecChannelStatus::End

        exception.should be_a(IO::Error)
        exception.try(&.message).should eq("Closed stream")
      end
    end
  end

  describe "accept?" do
    it "returns the client UNIXSocket" do
      with_tempfile("unix_server-accept_.sock") do |path|
        UNIXServer.open(path) do |server|
          UNIXSocket.open(path) do |_|
            client = server.accept?.not_nil!
            client.should be_a(UNIXSocket)
            client.close
          end
        end
      end
    end

    it "returns nil when server is closed" do
      with_tempfile("unix_server-accept2.sock") do |path|
        server = UNIXServer.new(path)
        ch = Channel(SpecChannelStatus).new(1)
        ret = "initial"

        schedule_timeout ch

        f = spawn do
          ch.send :begin
          ret = server.accept?
          ch.send :end
        end

        ch.receive.should eq SpecChannelStatus::Begin

        # wait for the server to call accept
        wait_until_blocked f

        server.close
        ch.receive.should eq SpecChannelStatus::End

        ret.should be_nil
      end
    end

    it "sets close on exec flag" do
      with_tempfile("unix_socket-accept.sock") do |path|
        UNIXServer.open(path) do |server|
          UNIXSocket.open(path) do |client|
            server.accept? do |sock|
              sock.close_on_exec?.should eq CLOSE_ON_EXEC_AVAILABLE
            end
          end
        end
      end
    end
  end

  # Datagram socket type is not supported on Windows yet:
  # https://devblogs.microsoft.com/commandline/af_unix-comes-to-windows/#unsupportedunavailable
  # https://github.com/microsoft/WSL/issues/5272
  {% unless flag?(:win32) %}
    describe "datagrams" do
      it "can send and receive datagrams" do
        with_tempfile("unix_dgram_server.sock") do |path|
          UNIXServer.open(path, Socket::Type::DGRAM) do |s|
            UNIXSocket.open(path, Socket::Type::DGRAM) do |c|
              c.send("foobar")
              msg, _addr = s.receive(512)
              msg.should eq "foobar"
            end
          end
        end
      end
    end
  {% end %}
end
