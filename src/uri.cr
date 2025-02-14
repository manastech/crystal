require "./uri/uri_parser"
require "./uri/encoding"
require "./uri/params"

# This class represents a URI reference as defined by [RFC 3986: Uniform Resource Identifier
# (URI): Generic Syntax](https://www.ietf.org/rfc/rfc3986.txt).
#
# This class provides constructors for creating URI instances from
# their components or by parsing their string forms and methods for accessing the various
# components of an instance.
#
# NOTE: To use `URI`, you must explicitly import it with `require "uri"`
#
# Basic example:
#
# ```
# require "uri"
#
# uri = URI.parse "http://foo.com/posts?id=30&limit=5#time=1305298413"
# # => #<URI:0x1003f1e40 @scheme="http", @host="foo.com", @port=nil, @path="/posts", @query="id=30&limit=5", ... >
# uri.scheme # => "http"
# uri.host   # => "foo.com"
# uri.query  # => "id=30&limit=5"
# uri.to_s   # => "http://foo.com/posts?id=30&limit=5#time=1305298413"
# ```
#
# ## Resolution and Relativization
#
# *Resolution* is the process of resolving one URI against another, *base* URI.
# The resulting URI is constructed from components of both URIs in the manner specified by
# [RFC 3986 section 5.2](https://tools.ietf.org/html/rfc3986#section-5.2.2), taking components
# from the base URI for those not specified in the original.
# For hierarchical URIs, the path of the original is resolved against the path of the base
# and then normalized. See `#resolve` for examples.
#
# *Relativization* is the inverse of resolution as that it procures an URI that
# resolves to the original when resolved against the base.
#
# For normalized URIs, the following is true:
#
# ```
# a.relativize(a.resolve(b)) # => b
# a.resolve(a.relativize(b)) # => b
# ```
#
# This operation is often useful when constructing a document containing URIs that must
# be made relative to the base URI of the document wherever possible.
#
# # URL Encoding
#
# This class provides a number of methods for encoding and decoding strings using
# URL Encoding (also known as Percent Encoding) as defined in [RFC 3986](https://www.ietf.org/rfc/rfc3986.txt)
# as well as [`x-www-form-urlencoded`](https://url.spec.whatwg.org/#urlencoded-serializing).
#
# Each method has two variants, one returns a string, the other writes directly
# to an IO.
#
# * `.decode(string : String, *, plus_to_space : Bool = false) : String`: Decodes a URL-encoded string.
# * `.decode(string : String, io : IO, *, plus_to_space : Bool = false) : Nil`: Decodes a URL-encoded string to an IO.
# * `.encode_path(string : String) : String`: URL-encodes a string.
# * `.encode_path(string : String, io : IO) : Nil`: URL-encodes a string to an IO.
# * `.encode_path_segment(string : String) : String`: URL-encodes a string, escaping `/`.
# * `.encode_path_segment(string : String, io : IO) : Nil`: URL-encodes a string to an IO, escaping `/`.
# * `.decode_www_form(string : String, *, plus_to_space : Bool = true) : String`: Decodes an `x-www-form-urlencoded` string component.
# * `.decode_www_form(string : String, io : IO, *, plus_to_space : Bool = true) : Nil`: Decodes an `x-www-form-urlencoded` string component to an IO.
# * `.encode_www_form(string : String, *, space_to_plus : Bool = true) : String`: Encodes a string as a `x-www-form-urlencoded` component.
# * `.encode_www_form(string : String, io : IO, *, space_to_plus : Bool = true) : Nil`: Encodes a string as a `x-www-form-urlencoded` component to an IO.
#
# `.encode_www_form` encodes white space (` `) as `+`, while `.encode_path`
# and `.encode_path_segment` encode it as `%20`. The decode methods differ regarding
# the handling of `+` characters, respectively.
#
# NOTE: `URI::Params` provides a higher-level API for handling `x-www-form-urlencoded`
# serialized data.
class URI
  class Error < Exception
  end

  # Returns the scheme component of the URI.
  #
  # ```
  # require "uri"
  #
  # URI.parse("http://foo.com").scheme           # => "http"
  # URI.parse("mailto:alice@example.com").scheme # => "mailto"
  # ```
  getter scheme : String?

  # Sets the scheme component of the URI.
  setter scheme : String?

  # Returns the host component of the URI.
  #
  # ```
  # require "uri"
  #
  # URI.parse("http://foo.com").host # => "foo.com"
  # ```
  getter host : String?

  # Sets the host component of the URI.
  def host=(@host : String?)
    validate_path
  end

  # Returns the port component of the URI.
  #
  # ```
  # require "uri"
  #
  # URI.parse("http://foo.com:5432").port # => 5432
  # ```
  getter port : Int32?

  # Sets the port component of the URI.
  def port=(@port : Int32?)
    validate_path
  end

  # Returns the path component of the URI.
  #
  # ```
  # require "uri"
  #
  # URI.parse("http://foo.com/bar").path # => "/bar"
  # ```
  getter path : String

  # Sets the path component of the URI.
  def path=(@path : String)
    validate_path
  end

  # Returns the query component of the URI.
  #
  # ```
  # require "uri"
  #
  # URI.parse("http://foo.com/bar?q=1").query # => "q=1"
  # ```
  getter query : String?

  # Sets the query component of the URI.
  setter query : String?

  # Returns the user component of the URI.
  #
  # ```
  # require "uri"
  #
  # URI.parse("http://admin:password@foo.com").user # => "admin"
  # ```
  getter user : String?

  # Sets the user component of the URI.
  setter user : String?

  # Returns the password component of the URI.
  #
  # ```
  # require "uri"
  #
  # URI.parse("http://admin:password@foo.com").password # => "password"
  # ```
  getter password : String?

  # Sets the password component of the URI.
  setter password : String?

  # Returns the fragment component of the URI.
  #
  # ```
  # require "uri"
  #
  # URI.parse("http://foo.com/bar#section1").fragment # => "section1"
  # ```
  getter fragment : String?

  # Sets the fragment component of the URI.
  setter fragment : String?

  def_equals_and_hash scheme, host, port, path, query, user, password, fragment

  def initialize(@scheme = nil, @host = nil, @port = nil, @path = "", query : String | Params | Nil = nil, @user = nil, @password = nil, @fragment = nil)
    @query = query.try(&.to_s)
    validate_path
  end

  private def validate_path
    if has_authority?
      unless path.empty? || path.starts_with?("/")
        raise ArgumentError.new("Invalid URI component: when there is an authority component, path must start with a slash (`/`) or be empty")
      end
    else
      if path.starts_with?("//")
        raise ArgumentError.new("Invalid URI component: when there is no authority component, path may not start with a double slash (`//`)")
      end
    end
  end

  private def has_authority?
    @host || @user || @port
  end

  # Returns the host part of the URI and unwrap brackets for IPv6 addresses.
  #
  # ```
  # require "uri"
  #
  # URI.parse("http://[::1]/bar").hostname # => "::1"
  # URI.parse("http://[::1]/bar").host     # => "[::1]"
  # ```
  def hostname : String?
    host.try { |host| self.class.unwrap_ipv6(host) }
  end

  # Unwraps IPv6 address wrapped in square brackets.
  #
  # Everything that is not wrapped in square brackets is returned unchanged.
  #
  # ```
  # URI.unwrap_ipv6("[::1]")       # => "::1"
  # URI.unwrap_ipv6("127.0.0.1")   # => "127.0.0.1"
  # URI.unwrap_ipv6("example.com") # => "example.com"
  # ```
  def self.unwrap_ipv6(host) : String
    if host.starts_with?('[') && host.ends_with?(']')
      host.byte_slice(1, host.bytesize - 2)
    else
      host
    end
  end

  # Returns the concatenation of `path` and `query` as it would be used as a
  # request target in an HTTP request.
  #
  # If `path` is empty in an hierarchical URI, `"/"` is used.
  #
  # ```
  # require "uri"
  #
  # uri = URI.parse "http://example.com/posts?id=30&limit=5#time=1305298413"
  # uri.request_target # => "/posts?id=30&limit=5"
  #
  # uri = URI.new(path: "", query: "foo=bar")
  # uri.request_target # => "/?foo=bar"
  # ```
  def request_target : String
    # Minimal size is 1 for an empty path (`"/"`)
    string_size = @path.empty? ? 1 : @path.bytesize
    if query = @query
      # Add 1 for the query designator (`?`)
      string_size += query.bytesize + 1
    end

    String.build(string_size) do |str|
      if @path.empty?
        str << "/" unless opaque?
      else
        str << @path
      end

      if (query = @query) && !query.empty?
        str << '?' << query
      end
    end
  end

  # Returns `true` if URI has a *scheme* specified.
  def absolute? : Bool
    @scheme ? true : false
  end

  # Returns `true` if URI does not have a *scheme* specified.
  def relative? : Bool
    !absolute?
  end

  # Returns `true` if this URI is opaque.
  #
  # A URI is considered opaque if it has a `scheme` but no hierarchical part,
  # i.e. no `host` and the first character of `path` is not a slash (`/`).
  def opaque? : Bool
    !@scheme.nil? && @host.nil? && !@path.starts_with?('/')
  end

  # Returns a `URI::Params` of the URI#query.
  #
  # ```
  # require "uri"
  #
  # uri = URI.parse "http://foo.com?id=30&limit=5#time=1305298413"
  # uri.query_params # => URI::Params{"id" => ["30"], "limit" => ["5"]}
  # ```
  def query_params : URI::Params
    URI::Params.parse(@query || "")
  end

  # Sets `query` to stringified *params*.
  #
  # ```
  # require "uri"
  #
  # uri = URI.new
  # uri.query_params = URI::Params.parse("foo=bar&foo=baz")
  # uri.to_s # => "?foo=bar&foo=baz"
  # ```
  def query_params=(params : URI::Params)
    self.query = params.to_s
  end

  # Yields the value of `#query_params` commits any modifications of the `URI::Params` instance to self.
  # Returns the modified `URI::Params`
  #
  # ```
  # require "uri"
  # uri = URI.parse("http://foo.com?id=30&limit=5#time=1305298413")
  # uri.update_query_params { |params| params.delete_all("limit") } # => URI::Params{"id" => ["30"]}
  #
  # puts uri.to_s # => "http://foo.com?id=30#time=1305298413"
  # ```
  def update_query_params(& : URI::Params -> _) : URI
    params = query_params

    yield params

    self.query_params = params

    self
  end

  # Returns the authority component of this URI.
  # It is formatted as `user:pass@host:port` with missing parts being omitted.
  #
  # If the URI does not have any authority information, the result is `nil`.
  #
  # ```
  # uri = URI.parse "http://user:pass@example.com:80/path?query"
  # uri.authority # => "user:pass@example.com:80"
  #
  # uri = URI.parse("/relative")
  # uri.authority # => nil
  # ```
  def authority : String?
    return unless @host || @user || @port

    String.build do |io|
      authority(io)
    end
  end

  # :ditto:
  def authority(io : IO) : Nil
    if user = @user
      userinfo(user, io)
      io << '@'
    end

    if host = @host
      # https://datatracker.ietf.org/doc/html/rfc3986#section-3.2.2
      #
      # host        = IP-literal / IPv4address / reg-name
      #
      # The valid characters include unreserved, sub-delims, ':', '[', ']' (IPv6-Address)
      URI.encode(host, io) { |byte| URI.unreserved?(byte) || URI.sub_delim?(byte) || byte.unsafe_chr.in?(':', '[', ']') }
    end

    if port = @port
      io << ':' << port
    end
  end

  def to_s(io : IO) : Nil
    if scheme
      io << scheme
      io << ':'
    end

    io << "//" if has_authority?
    authority(io)

    io << @path

    if query
      io << '?'
      io << query
    end
    if fragment
      io << '#'
      io << fragment
    end
  end

  # Returns a normalized copy of this URI.
  #
  # See `#normalize!` for details.
  def normalize : URI
    dup.normalize!
  end

  # Normalizes this URI instance.
  #
  # The following normalizations are applied to the individual components (if available):
  #
  # * `scheme` is lowercased.
  # * `host` is lowercased.
  # * `port` is removed if it is the `.default_port?` of the scheme.
  # * `path` is resolved to a minimal, semantic equivalent representation removing
  #    dot segments `/.` and `/..`.
  #
  # ```
  # uri = URI.parse("HTTP://example.COM:80/./foo/../bar/")
  # uri.normalize!
  # uri # => "http://example.com/bar/"
  # ```
  def normalize! : URI
    @scheme = @scheme.try &.downcase
    @host = @host.try &.downcase
    @port = nil if default_port?
    @path = remove_dot_segments(path)

    self
  end

  # Resolves *uri* against this URI.
  #
  # If *uri* is `absolute?`, or if this URI is `opaque?`, then an exact copy of *uri* is returned.
  #
  # Otherwise the URI is resolved according to the specifications in [RFC 3986 section 5.2](https://tools.ietf.org/html/rfc3986#section-5.2.2).
  #
  # ```
  # URI.parse("http://foo.com/bar/baz").resolve("../quux")         # => "http://foo.com/quux"
  # URI.parse("http://foo.com/bar/baz").resolve("/quux")           # => "http://foo.com/quux"
  # URI.parse("http://foo.com/bar/baz").resolve("http://quux.com") # => "http://quux.com"
  # URI.parse("http://foo.com/bar/baz").resolve("#quux")           # => "http://foo.com/bar/baz#quux"
  # ```
  #
  # This method is the inverse operation to `#relativize` (see [Resolution and Relativization](#Resolution and Relativization)).
  def resolve(uri : URI | String) : URI
    if uri.is_a?(URI)
      target = uri.dup
    else
      target = URI.parse(uri)
    end

    if target.absolute? || opaque?
      return target
    end

    target.scheme = scheme

    unless target.host || target.user
      if target.path.empty?
        target.path = remove_dot_segments(path)
        target.query ||= query
      else
        base = path
        if base.empty? && target.absolute?
          base = "/"
        end
        target.path = resolve_path(target.path, base: base)
      end
      target.host = host
      target.port = port
      target.user = user
      target.password = password
    end

    target
  end

  private def resolve_path(path : String, base : String) : String
    unless path.starts_with?('/')
      if path.empty?
        path = base
      elsif !base.empty?
        out_base = base.ends_with?('/') ? base : base[0..base.rindex('/')]
        path = String.interpolation(out_base, path)
      end
    end
    remove_dot_segments(path)
  end

  # Relativizes *uri* against this URI.
  #
  # An exact copy of *uri* is returned if
  # * this URI or *uri* are `opaque?`, or
  # * the scheme and authority (`host`, `port`, `user`, `password`) components are not identical.
  #
  # Otherwise a new relative hierarchical URI is constructed with `query` and `fragment` components
  # from *uri* and with a path component that describes a minimum-difference relative
  # path from `#path` to *uri*'s path.
  #
  # ```
  # URI.parse("http://foo.com/bar/baz").relativize("http://foo.com/quux")         # => "../quux"
  # URI.parse("http://foo.com/bar/baz").relativize("http://foo.com/bar/quux")     # => "quux"
  # URI.parse("http://foo.com/bar/baz").relativize("http://quux.com")             # => "http://quux.com"
  # URI.parse("http://foo.com/bar/baz").relativize("http://foo.com/bar/baz#quux") # => "#quux"
  # ```
  #
  # This method is the inverse operation to `#resolve` (see [Resolution and Relativization](#Resolution and Relativization)).
  def relativize(uri : URI | String) : URI
    if uri.is_a?(URI)
      uri = uri.dup
    else
      uri = URI.parse(uri)
    end

    if uri.opaque? || opaque? || uri.scheme.try &.downcase != @scheme.try &.downcase ||
       uri.host.try &.downcase != @host.try &.downcase || uri.port != @port || uri.user != @user ||
       uri.password != @password
      return uri
    end

    query = uri.query
    query = nil if query == @query

    path = relativize_path(@path, uri.path)

    URI.new(path: path, query: query, fragment: uri.fragment)
  end

  private def relativize_path(base : String, dst : String) : String
    return "" if base == dst

    if base =~ %r{(?:\A|/)\.\.?(?:/|\z)} && dst.starts_with?('/')
      # dst has abnormal absolute path,
      # like "/./", "/../", "/x/../", ...
      return dst
    end

    base_path = base.split('/', remove_empty: true)
    dst_path = dst.split('/', remove_empty: true)

    dst_path << "" if dst.ends_with?('/')
    base_path.pop? unless base.ends_with?('/')

    # discard same parts
    while !dst_path.empty? && !base_path.empty?
      dst = dst_path.first
      base = base_path.first
      if dst == base
        base_path.shift
        dst_path.shift
      elsif dst == "."
        dst_path.shift
      elsif base == "."
        base_path.shift
      else
        break
      end
    end

    # calculate
    if base_path.empty?
      if dst_path.empty?
        "./"
      elsif dst_path.first.includes?(':') # (see RFC2396 Section 5)
        string_size = 1 + dst_path.sum(&.bytesize) + dst_path.size
        String.build(string_size) do |io|
          io << "./"
          dst_path.join(io, '/')
        end
      else
        if dst_path.empty? || dst_path.first.empty?
          "./"
        else
          dst_path.join('/')
        end
      end
    else
      string_size = 3 * base_path.size + dst_path.sum(&.bytesize) + dst_path.size - 1
      String.build(string_size) do |io|
        base_path.size.times { io << "../" }
        dst_path.join(io, '/')
      end
    end
  end

  # Parses the given *raw_url* into an URI. The *raw_url* may be relative or absolute.
  #
  # ```
  # require "uri"
  #
  # uri = URI.parse("http://crystal-lang.org") # => #<URI:0x1068a7e40 @scheme="http", @host="crystal-lang.org", ... >
  # uri.scheme                                 # => "http"
  # uri.host                                   # => "crystal-lang.org"
  # ```
  def self.parse(raw_url : String) : URI
    URI::Parser.new(raw_url).run.uri
  end

  # Returns the user-information component containing
  # the provided username and password.
  #
  # ```
  # require "uri"
  #
  # uri = URI.parse "http://admin:password@foo.com"
  # uri.userinfo # => "admin:password"
  # ```
  #
  # The return value is URL encoded (see `#encode_www_form`).
  def userinfo : String?
    if user = @user
      String.build { |io| userinfo(user, io) }
    end
  end

  private def userinfo(user, io)
    URI.encode_www_form(user, io)
    if password = @password
      io << ':'
      URI.encode_www_form(password, io)
    end
  end

  # [RFC 3986 6.2.2.3](https://tools.ietf.org/html/rfc3986#section-5.2.4)
  private def remove_dot_segments(path : String)
    result = [] of String
    while path.size > 0
      # A.  If the input buffer begins with a prefix of "../" or "./",
      #     then remove that prefix from the input buffer; otherwise,
      if path.starts_with?("../")
        path = path[3..-1]
      elsif path.starts_with?("./")
        path = path[2..-1]
        # B.  if the input buffer begins with a prefix of "/./" or "/.",
        #     where "." is a complete path segment, then replace that
        #     prefix with "/" in the input buffer; otherwise,
      elsif path.starts_with?("/./")
        path = "/" + path[3..-1]
      elsif path == "/."
        path = "/" + path[2..-1]
        # C.  if the input buffer begins with a prefix of "/../" or "/..",
        #     where ".." is a complete path segment, then replace that
        #     prefix with "/" in the input buffer and remove the last
        #     segment and its preceding "/" (if any) from the output
        #     buffer; otherwise,
      elsif path.starts_with?("/../")
        path = "/" + path[4..-1]
        result.pop if result.size > 0
      elsif path == "/.."
        path = "/" + path[3..-1]
        result.pop if result.size > 0
        # D.  if the input buffer consists only of "." or "..", then remove
        #     that from the input buffer; otherwise,
      elsif path.in?("..", ".")
        path = ""
        # E.  move the first path segment in the input buffer to the end of
        #     the output buffer, including the initial "/" character (if
        #     any) and any subsequent characters up to, but not including,
        #     the next "/" character or the end of the input buffer.
      else
        slash_search_idx = path[0] == '/' ? 1 : 0
        segment_end_idx = path.index("/", slash_search_idx)
        segment_end_idx ||= path.size
        result << path[0...segment_end_idx]
        path = path[segment_end_idx..-1]
      end
    end
    first = result.first?
    if first && !first.starts_with?('/') && first.includes?(':')
      result.unshift "./"
    end

    result.join
  end

  # A map of schemes and their respective default ports, seeded
  # with some well-known schemes sourced from the IANA [Uniform
  # Resource Identifier (URI) Schemes][1] and [Service Name and
  # Transport Protocol Port Number Registry][2] via Mahmoud
  # Hashemi's [scheme_port_map.json][3].
  #
  # [1]: https://www.iana.org/assignments/uri-schemes/uri-schemes.xhtml
  # [2]: https://www.iana.org/assignments/service-names-port-numbers/service-names-port-numbers.xhtml
  # [3]: https://gist.github.com/mahmoud/2fe281a8daaff26cfe9c15d2c5bf5c8b
  @@default_ports = {
    "acap"     => 674,
    "afp"      => 548,
    "dict"     => 2628,
    "dns"      => 53,
    "ftp"      => 21,
    "ftps"     => 990,
    "git"      => 9418,
    "gopher"   => 70,
    "http"     => 80,
    "https"    => 443,
    "imap"     => 143,
    "ipp"      => 631,
    "ipps"     => 631,
    "irc"      => 194,
    "ircs"     => 6697,
    "ldap"     => 389,
    "ldaps"    => 636,
    "mms"      => 1755,
    "msrp"     => 2855,
    "mtqp"     => 1038,
    "nfs"      => 111,
    "nntp"     => 119,
    "nntps"    => 563,
    "pop"      => 110,
    "prospero" => 1525,
    "redis"    => 6379,
    "rsync"    => 873,
    "rtsp"     => 554,
    "rtsps"    => 322,
    "rtspu"    => 5005,
    "scp"      => 22,
    "sftp"     => 22,
    "smb"      => 445,
    "snmp"     => 161,
    "ssh"      => 22,
    "svn"      => 3690,
    "telnet"   => 23,
    "ventrilo" => 3784,
    "vnc"      => 5900,
    "wais"     => 210,
    "ws"       => 80,
    "wss"      => 443,
  }

  # Returns the default port for the given *scheme* if known,
  # otherwise returns `nil`.
  #
  # ```
  # require "uri"
  #
  # URI.default_port "http"  # => 80
  # URI.default_port "ponzi" # => nil
  # ```
  def self.default_port(scheme : String) : Int32?
    @@default_ports[scheme.downcase]?
  end

  # Registers the default port for the given *scheme*.
  #
  # If *port* is `nil`, the existing default port for the
  # *scheme*, if any, will be unregistered.
  #
  # ```
  # require "uri"
  #
  # URI.set_default_port "ponzi", 9999
  # ```
  def self.set_default_port(scheme : String, port : Int32?) : Nil
    if port
      @@default_ports[scheme.downcase] = port
    else
      @@default_ports.delete scheme.downcase
    end
  end

  # Returns `true` if this URI's *port* is the default port for
  # its *scheme*.
  private def default_port?
    if (scheme = @scheme) && (port = @port)
      port == URI.default_port(scheme)
    else
      false
    end
  end
end
