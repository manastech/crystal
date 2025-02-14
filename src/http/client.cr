{% if !flag?(:without_openssl) %}
  require "openssl"
{% end %}

# An HTTP Client.
#
# NOTE: To use `Client`, you must explicitly import it with `require "http/client"`
#
# ### One-shot usage
#
# Without a block, an `HTTP::Client::Response` is returned and the response's body
# is available as a `String` by invoking `HTTP::Client::Response#body`.
#
# ```
# require "http/client"
#
# response = HTTP::Client.get "http://www.example.com"
# response.status_code      # => 200
# response.body.lines.first # => "<!doctype html>"
# ```
#
# ### Parameters
#
# Parameters can be added to any request with the `URI::Params.encode` method, which
# converts a `Hash` or `NamedTuple` to a URL encoded HTTP query.
#
# ```
# require "http/client"
#
# params = URI::Params.encode({"author" => "John Doe", "offset" => "20"}) # => "author=John+Doe&offset=20"
# response = HTTP::Client.get URI.new("http", "www.example.com", query: params)
# response.status_code # => 200
# ```
#
# ### Streaming
#
# With a block, an `HTTP::Client::Response` body is returned and the response's body
# is available as an `IO` by invoking `HTTP::Client::Response#body_io`.
#
# ```
# require "http/client"
#
# HTTP::Client.get("http://www.example.com") do |response|
#   response.status_code  # => 200
#   response.body_io.gets # => "<!doctype html>"
# end
# ```
#
# ### Reusing a connection
#
# Similar to the above cases, but creating an instance of an `HTTP::Client`.
#
# ```
# require "http/client"
#
# client = HTTP::Client.new "www.example.com"
# response = client.get "/"
# response.status_code      # => 200
# response.body.lines.first # => "<!doctype html>"
# client.close
# ```
#
# WARNING: A single `HTTP::Client` instance is not safe for concurrent use by multiple fibers.
#
# ### Compression
#
# If `compress` isn't set to `false`, and no `Accept-Encoding` header is explicitly specified,
# an HTTP::Client will add an `"Accept-Encoding": "gzip, deflate"` header, and automatically decompress
# the response body/body_io.
#
# ### Encoding
#
# If a response has a `Content-Type` header with a charset, that charset is set as the encoding
# of the returned IO (or used for creating a String for the body). Invalid bytes in the given encoding
# are silently ignored when reading text content.
class HTTP::Client
  # The set of possible valid body types.
  alias BodyType = String | Bytes | IO | Nil
  alias ProxyURL = String | URI | Nil

  # HTTP Proxy URL. Empty string equates to no proxy.
  #
  # Order of usage is instance -> class -> proxy environment variables
  class_property proxy : ProxyURL

  # HTTP Proxy URL. Emoty string equates to no proxy.
  #
  # Order of usage is instance -> class -> proxy environment variables
  property proxy : ProxyURL

  # Returns the target host.
  #
  # ```
  # require "http/client"
  #
  # client = HTTP::Client.new "www.example.com"
  # client.host # => "www.example.com"
  # ```
  getter host : String

  # Returns the target port.
  #
  # ```
  # require "http/client"
  #
  # client = HTTP::Client.new "www.example.com"
  # client.port # => 80
  # ```
  getter port : Int32

  # If this client uses TLS, returns its `OpenSSL::SSL::Context::Client`, raises otherwise.
  #
  # Changes made after the initial request will have no effect.
  #
  # ```
  # require "http/client"
  #
  # client = HTTP::Client.new "www.example.com", tls: true
  # client.tls # => #<OpenSSL::SSL::Context::Client ...>
  # ```
  {% if flag?(:without_openssl) %}
    getter! tls : Nil
    alias TLSContext = Bool | Nil
  {% else %}
    getter! tls : OpenSSL::SSL::Context::Client | Bool
    alias TLSContext = OpenSSL::SSL::Context::Client | Bool | Nil
  {% end %}

  # Whether automatic compression/decompression is enabled.
  property? compress : Bool = true

  @io : IO?
  @reconnect = true

  # Creates a new HTTP client with the given *host*, *port* and *tls*
  # configurations. If no port is given, the default one will
  # be used depending on the *tls* arguments: 80 for if *tls* is `false`,
  # 443 if *tls* is truthy. If *tls* is `true` a new `OpenSSL::SSL::Context::Client` will
  # be used, else the given one. In any case the active context can be accessed through `tls`.
  def initialize(@host : String, port = nil, @tls : TLSContext = nil)
    check_host_only(@host)

    @port = (port || (@tls ? 443 : 80)).to_i
  end

  # Creates a new HTTP client bound to an existing `IO`.
  # *host* and *port* can be specified and they will be used
  # to conform the `Host` header on each request.
  # Instances created with this constructor cannot be reconnected. Once
  # `close` is called explicitly or if the connection doesn't support keep-alive,
  # the next call to make a request will raise an exception.
  def initialize(@io : IO, @host = "", @port = 80)
    @reconnect = false
  end

  private def check_host_only(string : String)
    # When parsing a URI with just a host
    # we end up with a URI with just a path
    uri = URI.parse(string)
    if uri.scheme || uri.host || uri.port || uri.query || uri.user || uri.password || uri.path.includes?('/')
      raise_invalid_host(string)
    end
  rescue URI::Error
    raise_invalid_host(string)
  end

  private def raise_invalid_host(string : String)
    raise ArgumentError.new("The string passed to create an HTTP::Client must be just a host, not #{string.inspect}")
  end

  # Creates a new HTTP client from a URI. Parses the *host*, *port*,
  # and *tls* configuration from the URI provided. Port defaults to
  # 80 if not specified unless using the https protocol, which defaults
  # to port 443 and sets tls to `true`.
  #
  # ```
  # require "http/client"
  # require "uri"
  #
  # uri = URI.parse("https://secure.example.com")
  # client = HTTP::Client.new(uri)
  #
  # client.tls? # => #<OpenSSL::SSL::Context::Client>
  # client.get("/")
  # ```
  # This constructor will *ignore* any path or query segments in the URI
  # as those will need to be passed to the client when a request is made.
  #
  # If *tls* is given it will be used, if not a new TLS context will be created.
  # If *tls* is given and *uri* is a HTTP URI, `ArgumentError` is raised.
  # In any case the active context can be accessed through `tls`.
  #
  # This constructor will raise an exception if any scheme but HTTP or HTTPS
  # is used.
  def self.new(uri : URI, tls : TLSContext = nil)
    tls = tls_flag(uri, tls)
    host = validate_host(uri)
    new(host, uri.port, tls)
  end

  # Creates a new HTTP client from a URI, yields it to the block and closes the
  # client afterwards. Parses the *host*, *port*, and *tls* configuration from
  # the URI provided. Port defaults to 80 if not specified unless using the
  # https protocol, which defaults to port 443 and sets tls to `true`.
  #
  # ```
  # require "http/client"
  # require "uri"
  #
  # uri = URI.parse("https://secure.example.com")
  # HTTP::Client.new(uri) do |client|
  #   client.tls? # => #<OpenSSL::SSL::Context::Client>
  #   client.get("/")
  # end
  # ```
  # This constructor will *ignore* any path or query segments in the URI
  # as those will need to be passed to the client when a request is made.
  #
  # If *tls* is given it will be used, if not a new TLS context will be created.
  # If *tls* is given and *uri* is a HTTP URI, `ArgumentError` is raised.
  # In any case the active context can be accessed through `tls`.
  #
  # This constructor will raise an exception if any scheme but HTTP or HTTPS
  # is used.
  def self.new(uri : URI, tls : TLSContext = nil, &)
    tls = tls_flag(uri, tls)
    host = validate_host(uri)
    client = new(host, uri.port, tls)
    begin
      yield client
    ensure
      client.close
    end
  end

  # Creates a new HTTP client, yields it to the block, and closes
  # the client afterwards.
  #
  # ```
  # require "http/client"
  #
  # HTTP::Client.new("www.example.com") do |client|
  #   client.get "/"
  # end
  # ```
  def self.new(host : String, port = nil, tls : TLSContext = nil, &)
    client = new(host, port, tls)
    begin
      yield client
    ensure
      client.close
    end
  end

  # Configures this client to perform basic authentication in every
  # request.
  def basic_auth(username, password) : Nil
    header = "Basic #{Base64.strict_encode("#{username}:#{password}")}"
    before_request do |request|
      request.headers["Authorization"] = header
    end
  end

  # Sets the number of seconds to wait when reading before raising an `IO::TimeoutError`.
  #
  # ```
  # require "http/client"
  #
  # client = HTTP::Client.new("example.org")
  # client.read_timeout = 1.5
  # begin
  #   response = client.get("/")
  # rescue IO::TimeoutError
  #   puts "Timeout!"
  # end
  # ```
  @[Deprecated("Use `#read_timeout=(Time::Span)` instead")]
  def read_timeout=(read_timeout : Number)
    self.read_timeout = read_timeout.seconds
  end

  # Sets the read timeout with a `Time::Span`, to wait when reading before raising an `IO::TimeoutError`.
  #
  # ```
  # require "http/client"
  #
  # client = HTTP::Client.new("example.org")
  # client.read_timeout = 5.minutes
  # begin
  #   response = client.get("/")
  # rescue IO::TimeoutError
  #   puts "Timeout!"
  # end
  # ```
  setter read_timeout : Time::Span?

  # Sets the write timeout - if any chunk of request is not written
  # within the number of seconds provided, `IO::TimeoutError` exception is raised.
  @[Deprecated("Use `#write_timeout=(Time::Span)` instead")]
  def write_timeout=(write_timeout : Number)
    self.write_timeout = write_timeout.seconds
  end

  # Sets the write timeout - if any chunk of request is not written
  # within the provided `Time::Span`,  `IO::TimeoutError` exception is raised.
  setter write_timeout : Time::Span?

  # Sets the number of seconds to wait when connecting, before raising an `IO::TimeoutError`.
  #
  # ```
  # require "http/client"
  #
  # client = HTTP::Client.new("example.org")
  # client.connect_timeout = 1.5
  # begin
  #   response = client.get("/")
  # rescue IO::TimeoutError
  #   puts "Timeout!"
  # end
  # ```
  @[Deprecated("Use `#connect_timeout=(Time::Span)` instead")]
  def connect_timeout=(connect_timeout : Number)
    self.connect_timeout = connect_timeout.seconds
  end

  # Sets the open timeout with a `Time::Span` to wait when connecting, before raising an `IO::TimeoutError`.
  #
  # ```
  # require "http/client"
  #
  # client = HTTP::Client.new("example.org")
  # client.connect_timeout = 5.minutes
  # begin
  #   response = client.get("/")
  # rescue IO::TimeoutError
  #   puts "Timeout!"
  # end
  # ```
  setter connect_timeout : Time::Span?

  # Sets the number of seconds to wait when resolving a name, before raising an `IO::TimeoutError`.
  #
  # NOTE: *dns_timeout* is currently only supported on Windows.
  #
  # ```
  # require "http/client"
  #
  # client = HTTP::Client.new("example.org")
  # client.dns_timeout = 1.5
  # begin
  #   response = client.get("/")
  # rescue IO::TimeoutError
  #   puts "Timeout!"
  # end
  # ```
  @[Deprecated("Use `#dns_timeout=(Time::Span)` instead")]
  def dns_timeout=(dns_timeout : Number)
    self.dns_timeout = dns_timeout.seconds
  end

  # Sets the number of seconds to wait when resolving a name with a `Time::Span`, before raising an `IO::TimeoutError`.
  #
  # NOTE: *dns_timeout* is currently only supported on Windows.
  #
  # ```
  # require "http/client"
  #
  # client = HTTP::Client.new("example.org")
  # client.dns_timeout = 1.5.seconds
  # begin
  #   response = client.get("/")
  # rescue IO::TimeoutError
  #   puts "Timeout!"
  # end
  # ```
  setter dns_timeout : Time::Span?

  # Adds a callback to execute before each request. This is usually
  # used to set an authorization header. Any number of callbacks
  # can be added.
  #
  #
  # ```
  # require "http/client"
  #
  # client = HTTP::Client.new("www.example.com")
  # client.before_request do |request|
  #   request.headers["Authorization"] = "XYZ123"
  # end
  # client.get "/"
  # ```
  def before_request(&callback : HTTP::Request ->) : Nil
    before_request = @before_request ||= [] of (HTTP::Request ->)
    before_request << callback
  end

  {% for method in %w(get post put head delete patch options) %}
    # Executes a {{method.id.upcase}} request.
    # The response will have its body as a `String`, accessed via `HTTP::Client::Response#body`.
    #
    # ```
    # require "http/client"
    #
    # client = HTTP::Client.new("www.example.com")
    # response = client.{{method.id}}("/", headers: HTTP::Headers{"User-Agent" => "AwesomeApp"}, body: "Hello!")
    # response.body #=> "..."
    # ```
    def {{method.id}}(path, headers : HTTP::Headers? = nil, body : BodyType = nil) : HTTP::Client::Response
      exec {{method.upcase}}, path, headers, body
    end

    # Executes a {{method.id.upcase}} request and yields the response to the block.
    # The response will have its body as an `IO` accessed via `HTTP::Client::Response#body_io`.
    #
    # ```
    # require "http/client"
    #
    # client = HTTP::Client.new("www.example.com")
    # client.{{method.id}}("/", headers: HTTP::Headers{"User-Agent" => "AwesomeApp"}, body: "Hello!") do |response|
    #   response.body_io.gets #=> "..."
    # end
    # ```
    def {{method.id}}(path, headers : HTTP::Headers? = nil, body : BodyType = nil)
      exec {{method.upcase}}, path, headers, body do |response|
        yield response
      end
    end

    # Executes a {{method.id.upcase}} request.
    # The response will have its body as a `String`, accessed via `HTTP::Client::Response#body`.
    #
    # ```
    # require "http/client"
    #
    # response = HTTP::Client.{{method.id}}("/", headers: HTTP::Headers{"User-Agent" => "AwesomeApp"}, body: "Hello!")
    # response.body #=> "..."
    # ```
    def self.{{method.id}}(url : String | URI, headers : HTTP::Headers? = nil, body : BodyType = nil, tls : TLSContext = nil) : HTTP::Client::Response
      exec {{method.upcase}}, url, headers, body, tls
    end

    # Executes a {{method.id.upcase}} request and yields the response to the block.
    # The response will have its body as an `IO` accessed via `HTTP::Client::Response#body_io`.
    #
    # ```
    # require "http/client"
    #
    # HTTP::Client.{{method.id}}("/", headers: HTTP::Headers{"User-Agent" => "AwesomeApp"}, body: "Hello!") do |response|
    #   response.body_io.gets #=> "..."
    # end
    # ```
    def self.{{method.id}}(url : String | URI, headers : HTTP::Headers? = nil, body : BodyType = nil, tls : TLSContext = nil)
      exec {{method.upcase}}, url, headers, body, tls do |response|
        yield response
      end
    end

    # Executes a {{method.id.upcase}} request with form data and returns a `Response`. The "Content-Type" header is set
    # to "application/x-www-form-urlencoded".
    #
    # ```
    # require "http/client"
    #
    # client = HTTP::Client.new "www.example.com"
    # response = client.{{method.id}} "/", form: "foo=bar"
    # ```
    def {{method.id}}(path, headers : HTTP::Headers? = nil, *, form : String | IO) : HTTP::Client::Response
      request = new_request({{method.upcase}}, path, headers, form)
      request.headers["Content-Type"] = "application/x-www-form-urlencoded"
      exec request
    end

    # Executes a {{method.id.upcase}} request with form data and yields the response to the block.
    # The response will have its body as an `IO` accessed via `HTTP::Client::Response#body_io`.
    # The "Content-Type" header is set to "application/x-www-form-urlencoded".
    #
    # ```
    # require "http/client"
    #
    # client = HTTP::Client.new "www.example.com"
    # client.{{method.id}}("/", form: "foo=bar") do |response|
    #   response.body_io.gets
    # end
    # ```
    def {{method.id}}(path, headers : HTTP::Headers? = nil, *, form : String | IO)
      request = new_request({{method.upcase}}, path, headers, form)
      request.headers["Content-Type"] = "application/x-www-form-urlencoded"
      exec(request) do |response|
        yield response
      end
    end

    # Executes a {{method.id.upcase}} request with form data and returns a `Response`. The "Content-Type" header is set
    # to "application/x-www-form-urlencoded".
    #
    # ```
    # require "http/client"
    #
    # client = HTTP::Client.new "www.example.com"
    # response = client.{{method.id}} "/", form: {"foo" => "bar"}
    # ```
    def {{method.id}}(path, headers : HTTP::Headers? = nil, *, form : Hash(String, String) | NamedTuple) : HTTP::Client::Response
      body = URI::Params.encode(form)
      {{method.id}} path, form: body, headers: headers
    end

    # Executes a {{method.id.upcase}} request with form data and yields the response to the block.
    # The response will have its body as an `IO` accessed via `HTTP::Client::Response#body_io`.
    # The "Content-type" header is set to "application/x-www-form-urlencoded".
    #
    # ```
    # require "http/client"
    #
    # client = HTTP::Client.new "www.example.com"
    # client.{{method.id}}("/", form: {"foo" => "bar"}) do |response|
    #   response.body_io.gets
    # end
    # ```
    def {{method.id}}(path, headers : HTTP::Headers? = nil, *, form : Hash(String, String) | NamedTuple)
      body = URI::Params.encode(form)
      {{method.id}}(path, form: body, headers: headers) do |response|
        yield response
      end
    end

    # Executes a {{method.id.upcase}} request with form data and returns a `Response`. The "Content-Type" header is set
    # to "application/x-www-form-urlencoded".
    #
    # ```
    # require "http/client"
    #
    # response = HTTP::Client.{{method.id}} "http://www.example.com", form: "foo=bar"
    # ```
    def self.{{method.id}}(url, headers : HTTP::Headers? = nil, tls : TLSContext = nil, *, form : String | IO | Hash) : HTTP::Client::Response
      exec(url, tls) do |client, path|
        client.{{method.id}}(path, form: form, headers: headers)
      end
    end

    # Executes a {{method.id.upcase}} request with form data and yields the response to the block.
    # The response will have its body as an `IO` accessed via `HTTP::Client::Response#body_io`.
    # The "Content-Type" header is set to "application/x-www-form-urlencoded".
    #
    # ```
    # require "http/client"
    #
    # HTTP::Client.{{method.id}}("http://www.example.com", form: "foo=bar") do |response|
    #   response.body_io.gets
    # end
    # ```
    def self.{{method.id}}(url, headers : HTTP::Headers? = nil, tls : TLSContext = nil, *, form : String | IO | Hash)
      exec(url, tls) do |client, path|
        client.{{method.id}}(path, form: form, headers: headers) do |response|
          yield response
        end
      end
    end
  {% end %}

  # Executes a request.
  # The response will have its body as a `String`, accessed via `HTTP::Client::Response#body`.
  #
  # ```
  # require "http/client"
  #
  # client = HTTP::Client.new "www.example.com"
  # response = client.exec HTTP::Request.new("GET", "/")
  # response.body # => "..."
  # ```
  def exec(request : HTTP::Request) : HTTP::Client::Response
    around_exec(request) do
      exec_internal(request)
    end
  end

  private def exec_internal(request)
    implicit_compression = implicit_compression?(request)
    begin
      response = exec_internal_single(request, implicit_compression: implicit_compression)
    rescue exc : IO::Error
      raise exc if @io.nil? # do not retry if client was closed
      response = nil
    end
    return handle_response(response) if response

    # Server probably closed the connection, so retry once
    close
    request.body.try &.rewind
    response = exec_internal_single(request, implicit_compression: implicit_compression)
    return handle_response(response) if response

    raise IO::EOFError.new("Unexpected end of http response")
  end

  private def exec_internal_single(request, implicit_compression = false)
    send_request(request)
    HTTP::Client::Response.from_io?(io, ignore_body: request.ignore_body?, decompress: implicit_compression)
  end

  private def handle_response(response)
    close unless response.keep_alive?
    response
  end

  # Executes a request and yields an `HTTP::Client::Response` to the block.
  # The response will have its body as an `IO` accessed via `HTTP::Client::Response#body_io`.
  #
  # ```
  # require "http/client"
  #
  # client = HTTP::Client.new "www.example.com"
  # client.exec(HTTP::Request.new("GET", "/")) do |response|
  #   response.body_io.gets # => "..."
  # end
  # ```
  def exec(request : HTTP::Request, &block)
    around_exec(request) do
      exec_internal(request) do |response|
        yield response
      end
    end
  end

  private def exec_internal(request, &block : Response -> T) : T forall T
    implicit_compression = implicit_compression?(request)
    exec_internal_single(request, ignore_io_error: true, implicit_compression: implicit_compression) do |response|
      if response
        return handle_response(response) { yield response }
      end
    end

    # Server probably closed the connection, so retry once
    close
    request.body.try &.rewind
    exec_internal_single(request, implicit_compression: implicit_compression) do |response|
      if response
        return handle_response(response) { yield response }
      end
    end
    raise IO::EOFError.new("Unexpected end of http response")
  end

  private def exec_internal_single(request, ignore_io_error = false, implicit_compression = false, &)
    begin
      send_request(request)
    rescue ex : IO::Error
      return yield nil if ignore_io_error && !@io.nil? # ignore_io_error only if client was not closed
      raise ex
    end
    HTTP::Client::Response.from_io?(io, ignore_body: request.ignore_body?, decompress: implicit_compression) do |response|
      yield response
    end
  end

  private def handle_response(response, &)
    yield
  ensure
    response.body_io?.try &.close
    close unless response.keep_alive?
  end

  private def send_request(request)
    set_defaults request
    run_before_request_callbacks(request)
    request.to_io(io)
    io.flush
  end

  private def set_defaults(request)
    request.headers["Host"] ||= host_header
    request.headers["User-Agent"] ||= "Crystal"

    if implicit_compression?(request)
      request.headers["Accept-Encoding"] = "gzip, deflate"
    end
  end

  private def implicit_compression?(request)
    {% if flag?(:without_zlib) %}
      false
    {% else %}
      compress? && !request.headers.has_key?("Accept-Encoding")
    {% end %}
  end

  # For one-shot headers we don't want keep-alive (might delay closing the response)
  private def self.default_one_shot_headers(headers)
    headers ||= HTTP::Headers.new
    headers["Connection"] ||= "close"
    headers
  end

  private def run_before_request_callbacks(request)
    @before_request.try &.each &.call(request)
  end

  # Executes a request.
  # The response will have its body as a `String`, accessed via `HTTP::Client::Response#body`.
  #
  # ```
  # require "http/client"
  #
  # client = HTTP::Client.new "www.example.com"
  # response = client.exec "GET", "/"
  # response.body # => "..."
  # ```
  def exec(method : String, path, headers : HTTP::Headers? = nil, body : BodyType = nil) : HTTP::Client::Response
    exec new_request method, path, headers, body
  end

  # Executes a request.
  # The response will have its body as an `IO` accessed via `HTTP::Client::Response#body_io`.
  #
  # ```
  # require "http/client"
  #
  # client = HTTP::Client.new "www.example.com"
  # client.exec("GET", "/") do |response|
  #   response.body_io.gets # => "..."
  # end
  # ```
  def exec(method : String, path, headers : HTTP::Headers? = nil, body : BodyType = nil, &)
    exec(new_request(method, path, headers, body)) do |response|
      yield response
    end
  end

  # Executes a request.
  # The response will have its body as an `IO` accessed via `HTTP::Client::Response#body_io`.
  #
  # ```
  # require "http/client"
  #
  # response = HTTP::Client.exec "GET", "http://www.example.com"
  # response.body # => "..."
  # ```
  def self.exec(method, url : String | URI, headers : HTTP::Headers? = nil, body : BodyType = nil, tls : TLSContext = nil) : HTTP::Client::Response
    headers = default_one_shot_headers(headers)
    exec(url, tls) do |client, path|
      client.exec method, path, headers, body
    end
  end

  # Executes a request.
  # The response will have its body as an `IO` accessed via `HTTP::Client::Response#body_io`.
  #
  # ```
  # require "http/client"
  #
  # HTTP::Client.exec("GET", "http://www.example.com") do |response|
  #   response.body_io.gets # => "..."
  # end
  # ```
  def self.exec(method, url : String | URI, headers : HTTP::Headers? = nil, body : BodyType = nil, tls : TLSContext = nil, &)
    headers = default_one_shot_headers(headers)
    exec(url, tls) do |client, path|
      client.exec(method, path, headers, body) do |response|
        yield response
      end
    end
  end

  # Closes this client. If used again, a new connection will be opened.
  def close : Nil
    @io.try &.close
  rescue IO::Error
    nil
  ensure
    @io = nil
  end

  private def new_request(method, path, headers, body : BodyType)
    HTTP::Request.new(method, path, headers, body)
  end

  private def io
    io = @io
    return io if io
    unless @reconnect
      raise "This HTTP::Client cannot be reconnected"
    end

    @io = create_proxy_io || create_io(host, port, @tls)
  end

  private def create_io(host, port, tls)
    hostname = host.starts_with?('[') && host.ends_with?(']') ? host[1..-2] : host
    io = TCPSocket.new hostname, port, @dns_timeout, @connect_timeout
    io.read_timeout = @read_timeout if @read_timeout
    io.write_timeout = @write_timeout if @write_timeout
    io.sync = false
    tls ? create_tls(io, host, tls) : io
  end

  private def create_proxy_io
    return unless proxy = find_proxy

    tls = HTTP::Client.tls_flag(proxy, nil)
    proxy_port = proxy.port || (tls ? 443 : 80)
    host = HTTP::Client.validate_host(proxy)

    io = create_io(host, proxy_port, tls)

    return io unless @tls

    send_connect_request(io)
    create_tls(io, @host, @tls)
  end

  private def create_tls(io, host, tls)
    {% if flag?(:without_openssl) %}
      raise "HTTP::Client TLS is disabled because `-D without_openssl` was passed at compile time"
    {% else %}
      tcp_socket = io
      begin
        tls = tls.is_a?(OpenSSL::SSL::Context::Client) ? tls : OpenSSL::SSL::Context::Client.new
        OpenSSL::SSL::Socket::Client.new(tcp_socket, context: tls, sync_close: true, hostname: host.rchop('.'))
      rescue exc
        # don't leak the TCP socket when the SSL connection failed
        tcp_socket.close
        raise exc
      end
    {% end %}
  end

  private def find_proxy : URI | Nil
    # Order of lookup is class -> instance -> environment
    # Both class and instance properties will stop on empty strings.

    case proxy
    when ""
      return nil
    when String
      return URI.parse(proxy.as(String))
    when URI
      return proxy.as(URI)
    end

    case self.class.proxy
    when ""
      return nil
    when String
      return URI.parse(self.class.proxy.as(String))
    when URI
      return self.class.proxy.as(URI)
    end

    # Find an appropriate environment variable
    type = @tls ? "https_proxy" : "http_proxy"
    key = if ENV.has_key?(type)
            type
          elsif @tls && ENV.has_key?("HTTPS_PROXY")
            "HTTPS_PROXY"
          elsif ENV.has_key?("all_proxy")
            "all_proxy"
          elsif ENV.has_key?("ALL_PROXY")
            "ALL_PROXY"
          end
    return URI.parse(ENV[key]) if key
  end

  private def send_connect_request(io)
    io << "CONNECT #{@host}:#{@port} HTTP/1.1\r\n"
    io << "Host: #{@host}:#{@port}\r\n"
    io << "\r\n"
    io.flush

    resp = HTTP::Client::Response.from_io(io, ignore_body: true)

    unless resp.success?
      io.close
      raise IO::Error.new("Unable to connect to https proxy")
    end
  end

  private def host_header
    if (@tls && @port != 443) || (!@tls && @port != 80)
      "#{@host}:#{@port}"
    else
      @host
    end
  end

  private def self.exec(string : String, tls : TLSContext = nil, &)
    uri = URI.parse(string)

    unless uri.scheme && uri.host
      # Assume http if no scheme and host are specified
      uri = URI.parse("http://#{string}")
    end

    exec(uri, tls) do |client, path|
      yield client, path
    end
  end

  protected def self.tls_flag(uri, context : TLSContext) : TLSContext
    scheme = uri.scheme
    raise ArgumentError.new("Missing scheme: #{uri}") if !scheme
    {% if flag?(:without_openssl) %}
      case scheme
      when "http"  then false
      when "https" then true
      else              raise ArgumentError.new "Unsupported scheme: #{scheme}"
      end
    {% else %}
      case {scheme, context}
      when {"http", false}, {"http", nil}
        false
      when {"http", OpenSSL::SSL::Context::Client}
        raise ArgumentError.new("TLS context given for HTTP URI")
      when {"https", true}, {"https", nil}
        true
      when {"https", OpenSSL::SSL::Context::Client}
        context
      else
        raise ArgumentError.new "Unsupported scheme: #{scheme}"
      end
    {% end %}
  end

  protected def self.validate_host(uri)
    host = uri.host.presence
    return host if host

    raise ArgumentError.new "Request URI must have host (URI is: #{uri})"
  end

  private def self.exec(uri : URI, tls : TLSContext = nil, &)
    tls = tls_flag(uri, tls)
    host = validate_host(uri)

    port = uri.port
    path = uri.request_target
    user = uri.user
    password = uri.password

    new(host, port, tls) do |client|
      if user && password
        client.basic_auth(user, password)
      end
      yield client, path
    end
  end

  # This method is called when executing the request. Although it can be
  # redefined, it is recommended to use the `def_around_exec` macro to be
  # able to add new behaviors without losing prior existing ones.
  protected def around_exec(request, &)
    yield
  end

  # This macro allows injecting code to be run before and after the execution
  # of the request. It should return the yielded value. It must be called with 1
  # block argument that will be used to pass the `HTTP::Request`.
  #
  # ```
  # class HTTP::Client
  #   def_around_exec do |request|
  #     # do something before exec
  #     res = yield
  #     # do something after exec
  #     res
  #   end
  # end
  # ```
  macro def_around_exec(&block)
    protected def around_exec(%request)
      previous_def do
        {% if block.args.size != 1 %}
          {% raise "Wrong number of block parameters for macro 'def_around_exec' (given #{block.args.size}, expected 1)" %}
        {% end %}

        {{ block.args.first.id }} = %request
        {{ block.body }}
      end
    end
  end
end

require "socket"
require "uri"
require "base64"
require "./common"
