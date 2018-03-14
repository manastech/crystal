{% if !flag?(:without_openssl) %}
  require "openssl"
{% end %}
require "socket"
require "./server/context"
require "./server/handler"
require "./server/response"
require "./common"

# An HTTP server.
#
# A server is given a handler that receives an `HTTP::Server::Context` that holds
# the `HTTP::Request` to process and must in turn configure and write to an `HTTP::Server::Response`.
#
# The `HTTP::Server::Response` object has `status` and `headers` properties that can be
# configured before writing the response body. Once response output is written,
# changing the `status` and `headers` properties has no effect.
#
# The `HTTP::Server::Response` is also a write-only `IO`, so all `IO` methods are available
# in it.
#
# The handler given to a server can simply be a block that receives an `HTTP::Server::Context`,
# or it can be an `HTTP::Handler`. An `HTTP::Handler` has an optional `next` handler,
# so handlers can be chained. For example, an initial handler may handle exceptions
# in a subsequent handler and return a 500 status code (see `HTTP::ErrorHandler`),
# the next handler might log the incoming request (see `HTTP::LogHandler`), and
# the final handler deals with routing and application logic.
#
# ### Simple Setup
#
# A handler is given with a block.
#
# ```
# require "http/server"
#
# server = HTTP::Server.new do |context|
#   context.response.content_type = "text/plain"
#   context.response.print "Hello world!"
# end
#
# server.bind 8080
# puts "Listening on http://127.0.0.1:8080"
# server.listen
# ```
#
# ### With non-localhost bind address
#
# ```
# require "http/server"
#
# server = HTTP::Server.new do |context|
#   context.response.content_type = "text/plain"
#   context.response.print "Hello world!"
# end
#
# server.bind "0.0.0.0", 8080
# puts "Listening on http://0.0.0.0:8080"
# server.listen
# ```
#
# ### Add handlers
#
# A series of handlers are chained.
#
# ```
# require "http/server"
#
# server = HTTP::Server.new([
#   HTTP::ErrorHandler.new,
#   HTTP::LogHandler.new,
#   HTTP::CompressHandler.new,
#   HTTP::StaticFileHandler.new("."),
# ])
#
# server.bind "127.0.0.1", 8080
# server.listen
# ```
#
# ### Add handlers and block
#
# A series of handlers is chained, the last one being the given block.
#
# ```
# require "http/server"
#
# server = HTTP::Server.new([
#   HTTP::ErrorHandler.new,
#   HTTP::LogHandler.new,
# ]) do |context|
#   context.response.content_type = "text/plain"
#   context.response.print "Hello world!"
# end
#
# server.bind "0.0.0.0", 8080
# server.listen
# ```
class HTTP::Server
  {% if !flag?(:without_openssl) %}
    property tls : OpenSSL::SSL::Context::Server?
  {% end %}

  @wants_close = false
  @sockets = [] of Socket::Server

  # Creates a new HTTP server with the given block as handler.
  def self.new(&handler : HTTP::Handler::Proc) : self
    new(handler)
  end

  # Creates a new HTTP server with a handler chain constructed from the *handlers*
  # array and the given block.
  def self.new(handlers : Array(HTTP::Handler), &handler : HTTP::Handler::Proc) : self
    new(HTTP::Server.build_middleware(handlers, handler))
  end

  # Creates a new HTTP server with the *handlers* array as handler chain.
  def self.new(handlers : Array(HTTP::Handler)) : self
    new(HTTP::Server.build_middleware(handlers))
  end

  # Creates a new HTTP server with the given *handler*.
  def initialize(handler : HTTP::Handler | HTTP::Handler::Proc)
    @processor = RequestProcessor.new(handler)
  end

  # Returns the TCP port of the first socket the server is bound to.
  #
  # For example you may let the system choose a port, then report it:
  # ```
  # server = HTTP::Server.new { }
  # server.bind 0
  # server.port # => 12345
  # ```
  def port : Int32?
    @sockets.each do |socket|
      if socket.is_a?(TCPServer)
        return socket.local_address.port.to_i
      end
    end
  end

  # Creates a `TCPServer` and adds it as a socket, returning the local address
  # and port the server listens on.
  #
  # If *port* is `0`, a random, free port will be chosen.
  #
  # You may set *reuse_port* to `true` to enable the `SO_REUSEPORT` socket option,
  # which allows multiple processes to bind to the same port.
  def bind(host : String, port : Int32, reuse_port : Bool = false) : Socket::IPAddress
    tcp_server = TCPServer.new(host, port, reuse_port: reuse_port)
    bind(tcp_server)
    tcp_server.local_address
  end

  # Creates a `TCPServer` listenting on `127.0.0.1` and adds it as a socket,
  # returning the local address and port the server listens on.
  #
  # If *port* is `0`, a random, free port will be chosen.
  #
  # You may set *reuse_port* to true to enable the `SO_REUSEPORT` socket option,
  # which allows multiple processes to bind to the same port.
  def bind(port : Int32, reuse_port : Bool = false) : Socket::IPAddress
    bind "127.0.0.1", port, reuse_port
  end

  # Adds a `Socket::Server` *socket* to this server.
  def bind(socket : Socket::Server) : Socket::Server
    @sockets << socket

    socket
  end

  # Starts the server. Blocks until the server is closed.
  def listen
    raise "Can't start server with not sockets to listen to" if @sockets.empty?

    done = Channel(Nil).new

    @sockets.each do |socket|
      spawn do
        until @wants_close
          spawn handle_client(socket.accept? || break)
        end

        done.send nil
      end
    end

    @sockets.size.times { done.receive }
  end

  # Gracefully terminates the server. It will process currently accepted
  # requests, but it won't accept new connections.
  def close
    @wants_close = true
    @processor.close

    @sockets.each do |socket|
      socket.close
    rescue
      # ignore exception on close
    end

    @sockets.clear
  end

  private def handle_client(io : IO)
    io.sync = false

    {% if !flag?(:without_openssl) %}
      if tls = @tls
        io = OpenSSL::SSL::Socket::Server.new(io, tls, sync_close: true)
      end
    {% end %}

    @processor.process(io, io)
  end

  # Builds all handlers as the middleware for `HTTP::Server`.
  def self.build_middleware(handlers, last_handler : (Context ->)? = nil)
    raise ArgumentError.new "You must specify at least one HTTP Handler." if handlers.empty?
    0.upto(handlers.size - 2) { |i| handlers[i].next = handlers[i + 1] }
    handlers.last.next = last_handler if last_handler
    handlers.first
  end
end
