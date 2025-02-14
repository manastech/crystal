require "mime/media_type"
{% if !flag?(:without_zlib) %}
  require "compress/deflate"
  require "compress/gzip"
{% end %}

module HTTP
  # Default maximum permitted size (in bytes) of the request line in an HTTP request.
  MAX_REQUEST_LINE_SIZE = 8192 # 8 KB

  # Default maximum permitted combined size (in bytes) of the headers in an HTTP request.
  MAX_HEADERS_SIZE = 16_384 # 16 KB

  # :nodoc:
  enum BodyType
    OnDemand
    Prohibited
    Mandatory
  end

  SUPPORTED_VERSIONS = {"HTTP/1.0", "HTTP/1.1"}

  # :nodoc:
  record EndOfRequest
  # :nodoc:
  record HeaderLine, name : String, value : String, bytesize : Int32

  # :nodoc:
  def self.parse_headers_and_body(io, body_type : BodyType = BodyType::OnDemand, decompress = true, *, max_headers_size : Int32 = MAX_HEADERS_SIZE, &) : HTTP::Status?
    headers = Headers.new

    max_size = max_headers_size
    while header_line = read_header_line(io, max_size)
      case header_line
      when EndOfRequest
        body = nil

        if body_type.prohibited?
          body = nil
        elsif content_length = content_length(headers)
          body = FixedLengthContent.new(io, content_length)
        elsif headers["Transfer-Encoding"]? == "chunked"
          body = ChunkedContent.new(io)
        elsif body_type.mandatory?
          body = UnknownLengthContent.new(io)
        end

        if body.is_a?(Content) && expect_continue?(headers)
          body.expects_continue = true
        end

        if decompress && body
          encoding = headers["Content-Encoding"]?
          {% if flag?(:without_zlib) %}
            case encoding
            when "gzip", "deflate"
              raise "Can't decompress because `-D without_zlib` was passed at compile time"
            else
              # not a format we support
            end
          {% else %}
            case encoding
            when "gzip"
              body = Compress::Gzip::Reader.new(body, sync_close: true)
              headers.delete("Content-Encoding")
              headers.delete("Content-Length")
            when "deflate"
              body = Compress::Deflate::Reader.new(body, sync_close: true)
              headers.delete("Content-Encoding")
              headers.delete("Content-Length")
            else
              # not a format we support
            end
          {% end %}
        end

        check_content_type_charset(body, headers)

        yield headers, body
        return
      else # HeaderLine
        max_size -= header_line.bytesize
        return HTTP::Status::REQUEST_HEADER_FIELDS_TOO_LARGE if max_size < 0

        return HTTP::Status::BAD_REQUEST unless headers.add?(header_line.name, header_line.value)
      end
    end
  end

  private def self.read_header_line(io, max_size) : HeaderLine | EndOfRequest | Nil
    # Optimization: check if we have a peek buffer
    if peek = io.peek
      # peek.empty? means EOF (so bad request)
      return nil if peek.empty?

      # See if we can find \n
      index = peek.index('\n'.ord.to_u8)
      if index
        end_index = index

        # Also check (and discard) \r before that
        if index > 0 && peek[index - 1] == '\r'.ord.to_u8
          end_index -= 1
        end

        # Check if we just have "\n" or "\r\n" (so end of request)
        if end_index == 0
          io.skip(index + 1)
          return EndOfRequest.new
        end

        return HeaderLine.new name: "", value: "", bytesize: index + 1 if index > max_size

        name, value = parse_header(peek[0, end_index])
        io.skip(index + 1) # Must skip until after \n
        return HeaderLine.new name: name, value: value, bytesize: index + 1
      end
    end

    line = io.gets(max_size + 1, chomp: true)
    return nil unless line
    if line.bytesize > max_size
      return HeaderLine.new name: "", value: "", bytesize: max_size
    end

    if line.empty?
      return EndOfRequest.new
    end

    name, value = parse_header(line)
    HeaderLine.new name: name, value: value, bytesize: line.bytesize
  end

  private def self.check_content_type_charset(body, headers)
    return unless body

    content_type = headers["Content-Type"]?
    return unless content_type

    mime_type = MIME::MediaType.parse?(content_type)
    return unless mime_type

    charset = mime_type["charset"]?
    return if !charset || charset == "utf-8"

    body.set_encoding(charset, invalid: :skip)
  end

  # :nodoc:
  def self.parse_header(line : String) : {String, String}
    parse_header(line.to_slice)
  end

  # :nodoc:
  def self.parse_header(slice : Bytes) : {String, String}
    # This is basically
    #
    # ```
    # line = "Server: nginx"
    # name, value = line.split ':', 2
    # {name, value.lstrip} # => {"Server", "nginx"}
    # ```
    #
    # except that it's faster because we only create 2 strings
    # instead of 3 (two from the split and one for the lstrip),
    # and there's no need for the array returned by split.

    cstr = slice.to_unsafe
    bytesize = slice.size

    # Get the colon index and name
    colon_index = slice.index(':'.ord.to_u8) || 0
    name = header_name(slice[0, colon_index])

    # Get where the header value starts (skip space)
    middle_index = colon_index + 1
    while middle_index < bytesize && cstr[middle_index].unsafe_chr.ascii_whitespace?
      middle_index += 1
    end

    # Get where the header value ends (chomp line)
    right_index = bytesize
    if middle_index >= right_index
      return {name, ""}
    elsif right_index > 1 && cstr[right_index - 2] == '\r'.ord.to_u8 && cstr[right_index - 1] == '\n'.ord.to_u8
      right_index -= 2
    elsif right_index > 0 && cstr[right_index - 1] == '\n'.ord.to_u8
      right_index -= 1
    end

    value = String.new(slice[middle_index, right_index - middle_index])

    {name, value}
  end

  private COMMON_HEADERS = %w(
    Accept-Encoding
    Accept-Language
    Accept-encoding
    Accept-language
    Allow
    Cache-Control
    Cache-control
    Connection
    Content-Disposition
    Content-Encoding
    Content-Language
    Content-Length
    Content-Type
    Content-disposition
    Content-encoding
    Content-language
    Content-length
    Content-type
    ETag
    Etag
    Expires
    Host
    Last-Modified
    Last-modified
    Location
    Referer
    User-Agent
    User-agent
    accept-encoding
    accept-language
    allow
    cache-control
    connection
    content-disposition
    content-encoding
    content-language
    content-length
    content-type
    etag
    expires
    host
    last-modified
    location
    referer
    user-agent
  )
    .to_h { |header| {header.to_slice, header} }

  # :nodoc:
  def self.header_name(slice : Bytes) : String
    # Check if the header name is a common one.
    # If so we avoid having to allocate a string for it.
    if slice.size < 20 && (name = COMMON_HEADERS[slice]?)
      name
    else
      String.new(slice)
    end
  end

  # :nodoc:
  def self.serialize_headers_and_body(io, headers, body, body_io, version)
    if body
      serialize_headers_and_string_body(io, headers, body)
    elsif body_io
      content_length = content_length(headers)
      if content_length
        headers.serialize(io)
        io << "\r\n"
        copied = IO.copy(body_io, io)
        if copied != content_length
          raise ArgumentError.new("Content-Length header is #{content_length} but body had #{copied} bytes")
        end
      elsif Client::Response.supports_chunked?(version)
        headers["Transfer-Encoding"] = "chunked"
        headers.serialize(io)
        io << "\r\n"
        serialize_chunked_body(io, body_io)
      else
        body = body_io.gets_to_end
        serialize_headers_and_string_body(io, headers, body)
      end
    else
      headers.serialize(io)
      io << "\r\n"
    end
  end

  def self.serialize_headers_and_string_body(io, headers, body)
    headers["Content-Length"] = body.bytesize.to_s
    headers.serialize(io)
    io << "\r\n"
    io << body
  end

  @[Deprecated("Use `HTTP::Headers#serialize` instead.")]
  def self.serialize_headers(io, headers)
    headers.serialize(io)
    io << "\r\n"
  end

  def self.serialize_chunked_body(io, body)
    buf = uninitialized UInt8[8192]
    while (buf_length = body.read(buf.to_slice)) > 0
      buf_length.to_s(io, 16)
      io << "\r\n"
      io.write(buf.to_slice[0, buf_length])
      io << "\r\n"
    end
    io << "0\r\n\r\n"
  end

  # :nodoc:
  def self.content_length(headers) : UInt64?
    length_headers = headers.get? "Content-Length"
    return nil unless length_headers
    first_header = length_headers[0]
    if length_headers.size > 1 && length_headers.any? { |header| header != first_header }
      raise ArgumentError.new("Multiple Content-Length headers received did not match: #{length_headers}")
    end
    first_header.to_u64
  end

  # :nodoc:
  def self.keep_alive?(message) : Bool
    case message.headers["Connection"]?.try &.downcase
    when "keep-alive"
      true
    when "close", "upgrade"
      false
    else
      case message.version
      when "HTTP/1.0"
        false
      else
        true
      end
    end
  end

  def self.expect_continue?(headers) : Bool
    headers["Expect"]?.try(&.downcase) == "100-continue"
  end

  # Parse a time string using the formats specified by [RFC 2616](https://tools.ietf.org/html/rfc2616#section-3.3.1)
  #
  # ```
  # require "http"
  #
  # HTTP.parse_time("Sun, 14 Feb 2016 21:00:00 GMT")  # => "2016-02-14 21:00:00 UTC"
  # HTTP.parse_time("Sunday, 14-Feb-16 21:00:00 GMT") # => "2016-02-14 21:00:00 UTC"
  # HTTP.parse_time("Sun Feb 14 21:00:00 2016")       # => "2016-02-14 21:00:00 UTC"
  # ```
  #
  # Uses `Time::Format::HTTP_DATE` as parser.
  def self.parse_time(time_str : String) : Time?
    Time::Format::HTTP_DATE.parse(time_str)
  rescue Time::Format::Error
  end

  # Format a `Time` object as a `String` using the format specified as `sane-cookie-date`
  # by [RFC 6265](https://tools.ietf.org/html/rfc6265#section-4.1.1) which is
  # according to [RFC 2616](https://tools.ietf.org/html/rfc2616#section-3.3.1) a
  # [RFC 1123](https://tools.ietf.org/html/rfc1123#page-55) format with explicit
  # timezone `GMT` (interpreted as `UTC`).
  #
  # ```
  # require "http"
  #
  # HTTP.format_time(Time.utc(2016, 2, 15)) # => "Mon, 15 Feb 2016 00:00:00 GMT"
  # ```
  #
  # Uses `Time::Format::HTTP_DATE` as formatter.
  def self.format_time(time : Time) : String
    Time::Format::HTTP_DATE.format(time)
  end

  # Dequotes an [RFC 2616](https://tools.ietf.org/html/rfc2616#page-17)
  # quoted-string.
  #
  # ```
  # require "http"
  #
  # quoted = %q(\"foo\\bar\")
  # HTTP.dequote_string(quoted) # => %q("foo\bar")
  # ```
  def self.dequote_string(str) : String
    data = str.to_slice
    quoted_pair_index = data.index('\\'.ord)
    return str unless quoted_pair_index

    String.build do |io|
      while quoted_pair_index
        io.write(data[0, quoted_pair_index])
        io << data[quoted_pair_index + 1].unsafe_chr

        data += quoted_pair_index + 2
        quoted_pair_index = data.index('\\'.ord)
      end
      io.write(data)
    end
  end

  # Encodes a string to an [RFC 2616](https://tools.ietf.org/html/rfc2616#page-17)
  # quoted-string. Encoded string is written to *io*. May raise when *string*
  # contains an invalid character.
  #
  # ```
  # require "http"
  #
  # string = %q("foo\ bar")
  # io = IO::Memory.new
  # HTTP.quote_string(string, io)
  # io.rewind
  # io.gets_to_end # => %q(\"foo\\\ bar\")
  # ```
  def self.quote_string(string, io) : Nil
    # Escaping rules: https://evolvis.org/pipermail/evolvis-platfrm-discuss/2014-November/000675.html

    string.each_char do |char|
      case char
      when '\t', ' ', '"', '\\'
        io << '\\'
      when '\u{00}'..'\u{1F}', '\u{7F}'
        raise ArgumentError.new("String contained invalid character #{char.inspect}")
      else
        # output byte as is
      end
      io << char
    end
  end

  # Encodes a string to an [RFC 2616](https://tools.ietf.org/html/rfc2616#page-17)
  # quoted-string. May raise when *string* contains an invalid character.
  #
  # ```
  # require "http"
  #
  # string = %q("foo\ bar")
  # HTTP.quote_string(string) # => %q(\"foo\\\ bar\")
  # ```
  def self.quote_string(string) : String
    String.build do |io|
      quote_string(string, io)
    end
  end
end

require "./status"
require "./request"
require "./client/response"
require "./headers"
require "./content"
require "./cookie"
require "./formdata"
