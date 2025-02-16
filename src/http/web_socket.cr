require "./client"
require "./headers"

# NOTE: To use `WebSocket`, you must explicitly import it with `require "http/web_socket"`
class HTTP::WebSocket
  getter? closed = false

  # :nodoc:
  def initialize(io : IO, sync_close = true)
    initialize(Protocol.new(io, sync_close: sync_close))
  end

  # :nodoc:
  def initialize(@ws : Protocol)
    @buffer = Bytes.new(4096)
    @current_message = IO::Memory.new
  end

  # Opens a new websocket using the information provided by the URI. This will also handle the handshake
  # and will raise an exception if the handshake did not complete successfully. This method will also raise
  # an exception if the URI is missing the host and/or the path.
  #
  # Please note that the scheme will only be used to identify if TLS should be used or not. Therefore, schemes
  # apart from `wss` and `https` will be treated as the default which is `ws`.
  #
  # ```
  # require "http/web_socket"
  #
  # HTTP::WebSocket.new(URI.parse("ws://websocket.example.com/chat"))        # Creates a new WebSocket to `websocket.example.com`
  # HTTP::WebSocket.new(URI.parse("wss://websocket.example.com/chat"))       # Creates a new WebSocket with TLS to `websocket.example.com`
  # HTTP::WebSocket.new(URI.parse("http://websocket.example.com:8080/chat")) # Creates a new WebSocket to `websocket.example.com` on port `8080`
  # HTTP::WebSocket.new(URI.parse("ws://websocket.example.com/chat"),        # Creates a new WebSocket to `websocket.example.com` with an Authorization header
  #   HTTP::Headers{"Authorization" => "Bearer authtoken"})
  # HTTP::WebSocket.new(
  #   URI.parse("ws://user:password@websocket.example.com/chat")) # Creates a new WebSocket to `websocket.example.com` with an HTTP basic auth Authorization header
  # ```
  def self.new(uri : URI | String, headers = HTTP::Headers.new)
    new(Protocol.new(uri, headers: headers))
  end

  # Opens a new websocket to the target host. This will also handle the handshake
  # and will raise an exception if the handshake did not complete successfully.
  #
  # ```
  # require "http/web_socket"
  #
  # HTTP::WebSocket.new("websocket.example.com", "/chat")            # Creates a new WebSocket to `websocket.example.com`
  # HTTP::WebSocket.new("websocket.example.com", "/chat", tls: true) # Creates a new WebSocket with TLS to `ẁebsocket.example.com`
  # ```
  def self.new(host : String, path : String, port = nil, tls : HTTP::Client::TLSContext = nil, headers = HTTP::Headers.new)
    new(Protocol.new(host, path, port, tls, headers))
  end

  # Called when a PING frame is received.
  def on_ping(&@on_ping : String ->)
  end

  # Called when a PONG frame is received.
  #
  # An unsolicited PONG frame should not be responded to.
  def on_pong(&@on_pong : String ->)
  end

  # Called when a text message is received.
  def on_message(&@on_message : String ->)
  end

  # Called when a binary message is received.
  def on_binary(&@on_binary : Bytes ->)
  end

  # Called when the connection is closed by the other party.
  def on_close(&@on_close : CloseCode, String ->)
  end

  protected def check_open
    raise IO::Error.new "Closed socket" if closed?
  end

  # Sends a message payload (message).
  def send(message) : Nil
    check_open
    @ws.send(message)
  end

  # Sends a PING frame. Received pings will call `#on_ping`.
  #
  # The receiving party must respond with a PONG.
  def ping(message = nil)
    check_open
    @ws.ping(message)
  end

  # Sends a PONG frame, which must be in response to a previously received PING frame from `#on_ping`.
  def pong(message = nil) : Nil
    check_open
    @ws.pong(message)
  end

  # Streams data into io until the io is flushed and sent as a message.
  #
  # The method accepts a block with an `io` argument.
  # The io object can call on `IO#write` and `IO#flush` method.
  # The `write` method accepts `Bytes` (`Slice(UInt8)`) and sends the data in chunks of *frame_size* bytes. The `flush` method sends all the data in io and resets it.
  # The remaining data in it is sent as a message when the block is finished executing.
  # For further information, see the `HTTP::WebSocket::Protocol::StreamIO` class.
  #
  # ```
  # # Open websocket connection
  # ws = HTTP::WebSocket.new("websocket.example.com", "/chat")
  #
  # # Open stream
  # ws.stream(false) do |io|
  #   io.write "Hello, ".encode("UTF-8") # Sends "Hello, " to io
  #   io.flush                           # Sends "Hello, " to the socket
  #   io.write "world!".encode("UTF-8")  # Sends "world!" to io
  # end
  # # Sends "world!" to the socket
  # ```
  def stream(binary = true, frame_size = 1024, &)
    check_open
    @ws.stream(binary: binary, frame_size: frame_size) do |io|
      yield io
    end
  end

  # Sends a close frame, and closes the connection.
  # The close frame may contain a body (message) that indicates the reason for closing.
  def close(code : CloseCode | Int? = nil, message = nil) : Nil
    return if closed?
    @closed = true
    @ws.close(code, message)
  end

  # Continuously receives messages and calls previously set callbacks until the websocket is closed.
  # Ping and pong messages are automatically handled.
  #
  # ```
  # # Open websocket connection
  # ws = HTTP::WebSocket.new("websocket.example.com", "/chat")
  #
  # # Set callback
  # ws.on_message do |msg|
  #   ws.send "response"
  # end
  #
  # # Start infinite loop
  # ws.run
  # ```
  def run : Nil
    loop do
      begin
        info = @ws.receive(@buffer)
      rescue
        @on_close.try &.call(CloseCode::AbnormalClosure, "")
        @closed = true
        break
      end

      case info.opcode
      in .ping?
        @current_message.write @buffer[0, info.size]
        if info.final
          message = @current_message.to_s
          @on_ping.try &.call(message)
          pong(message) unless closed?
          @current_message.clear
        end
      in .pong?
        @current_message.write @buffer[0, info.size]
        if info.final
          @on_pong.try &.call(@current_message.to_s)
          @current_message.clear
        end
      in .text?
        @current_message.write @buffer[0, info.size]
        if info.final
          @on_message.try &.call(@current_message.to_s)
          @current_message.clear
        end
      in .binary?
        @current_message.write @buffer[0, info.size]
        if info.final
          @on_binary.try &.call(@current_message.to_slice)
          @current_message.clear
        end
      in .close?
        @current_message.write @buffer[0, info.size]
        if info.final
          @current_message.rewind

          if @current_message.size >= 2
            code = @current_message.read_bytes(UInt16, IO::ByteFormat::NetworkEndian).to_i
            code = CloseCode.new(code)
          else
            code = CloseCode::NoStatusReceived
          end
          message = @current_message.gets_to_end

          @on_close.try &.call(code, message)
          close

          @current_message.clear
          break
        end
      in .continuation?
        # TODO: (asterite) I think this is good, but this case wasn't originally handled
      end
    end
  end

  record Ping
  record Pong
  record Close

  def read : Slice(UInt8) | String | Close | Ping | Pong | Nil
    begin
      info = @ws.receive(@buffer)
    rescue IO::EOFError
      close
      return nil
    end

    case info.opcode
    when Protocol::Opcode::PING
      @current_message.write @buffer[0, info.size]
      if info.final
        message = @current_message.to_s
        @on_ping.try &.call(message)
        pong(message) unless closed?
        @current_message.clear
      end
      return Ping.new
    when Protocol::Opcode::PONG
      @current_message.write @buffer[0, info.size]
      if info.final
        @on_pong.try &.call(@current_message.to_s)
        @current_message.clear
      end
      return Pong.new
    when Protocol::Opcode::TEXT
      message = @buffer[0, info.size]
      @current_message.write message
      if info.final
        @on_message.try &.call(@current_message.to_s)
        @current_message.clear
      end
      return String.new message
    when Protocol::Opcode::BINARY
      message = @buffer[0, info.size]
      @current_message.write message
      if info.final
        @on_binary.try &.call(@current_message.to_slice)
        @current_message.clear
      end
      return message
    when Protocol::Opcode::CLOSE
      @current_message.write @buffer[0, info.size]
      if info.final
        message = @current_message.to_s
        @on_close.try &.call(message)
        close(message) unless closed?
        @current_message.clear
      end
      return Close.new
    end
  end
end

require "./web_socket/*"
