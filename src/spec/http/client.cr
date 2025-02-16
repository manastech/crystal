require "http/client"

module Spec
  module HTTP
    class Client(T) < ::HTTP::Client
      # These ivars are required by HTTP::Client but we don't need them so we set
      # them to whatever.
      @host = ""
      @port = -1

      def self.new(ignore_body = false, decompress = true, &block : -> T)
        new block, ignore_body, decompress
      end

      def initialize(@app : T, @ignore_body = false, @decompress = true)
      end

      def exec_internal(request : ::HTTP::Request) : ::HTTP::Client::Response
        buffer = IO::Memory.new
        response = ::HTTP::Server::Response.new(buffer)
        context = ::HTTP::Server::Context.new(request, response)

        @app.call(context)
        response.close

        ::HTTP::Client::Response.from_io(buffer.rewind, @ignore_body, @decompress)
      end
    end
  end
end
