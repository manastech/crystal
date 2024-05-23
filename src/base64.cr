# The `Base64` module provides for the encoding (`encode`, `strict_encode`,
# `urlsafe_encode`) and decoding (`decode`)
# of binary data using a base64 representation.
#
# ### Example
#
# A simple encoding and decoding.
#
# ```
# require "base64"
#
# enc = Base64.encode("Send reinforcements") # => "U2VuZCByZWluZm9yY2VtZW50cw==\n"
# plain = Base64.decode_string(enc)          # => "Send reinforcements"
# ```
#
# The purpose of using base64 to encode data is that it translates any binary
# data into purely printable characters.
module Base64
  extend self

  class Error < Exception; end

  private CHARS_STD  = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
  private CHARS_SAFE = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
  private LINE_SIZE  = 60
  private LINE_PAIRS = LINE_SIZE // 4
  private LINE_BYTES = LINE_PAIRS * 3
  private PAD        = '='.ord.to_u8
  private NL         = '\n'.ord.to_u8
  private NR         = '\r'.ord.to_u8

  {% begin %}
    private STREAM_MAX_INPUT_BUFFER_SIZE = {{ IO::DEFAULT_BUFFER_SIZE // (LINE_SIZE + 1) * (LINE_SIZE // 4 * 3) }}
  {% end %}

  # Returns the base64-encoded version of *data*.
  # This method complies with [RFC 2045](https://tools.ietf.org/html/rfc2045).
  # Line feeds are added to every 60 encoded characters.
  #
  # ```
  # puts Base64.encode("Now is the time for all good coders\nto learn Crystal")
  # ```
  #
  # Generates:
  #
  # ```text
  # Tm93IGlzIHRoZSB0aW1lIGZvciBhbGwgZ29vZCBjb2RlcnMKdG8gbGVhcm4g
  # Q3J5c3RhbA==
  # ```
  def encode(data) : String
    slice = data.to_slice
    String.new(encode_size(slice.size, new_lines: true)) do |buf|
      bytes_written = encode_base64_buffer_internal(slice.to_unsafe, slice.size, buf, CHARS_STD.to_unsafe, newlines: true, pad: true)
      {bytes_written, bytes_written}
    end
  end

  # Returns the base64-encoded version of *data* with no newlines.
  # This method complies with [RFC 4648](https://tools.ietf.org/html/rfc4648).
  #
  # ```
  # puts Base64.strict_encode("Now is the time for all good coders\nto learn Crystal")
  # ```
  #
  # Generates:
  #
  # ```text
  # Tm93IGlzIHRoZSB0aW1lIGZvciBhbGwgZ29vZCBjb2RlcnMKdG8gbGVhcm4gQ3J5c3RhbA==
  # ```
  def strict_encode(data) : String
    slice = data.to_slice
    String.new(encode_size(slice.size)) do |buf|
      written_bytes = encode_base64_buffer_internal(slice.to_unsafe, slice.size, buf, CHARS_STD.to_unsafe, pad: true)
      {written_bytes, written_bytes}
    end
  end

  # Returns the base64-encoded version of *data* using a urlsafe alphabet.
  # This method complies with "Base 64 Encoding with URL and Filename Safe
  # Alphabet" in [RFC 4648](https://tools.ietf.org/html/rfc4648).
  #
  # The alphabet uses `'-'` instead of `'+'` and `'_'` instead of `'/'`.
  #
  # The *padding* parameter defaults to `true`. When `false`, enough `=` characters
  # are not added to make the output divisible by 4.
  def urlsafe_encode(data, padding = true) : String
    slice = data.to_slice
    String.new(encode_size(slice.size)) do |buf|
      bytes_written = encode_base64_buffer_internal(slice.to_unsafe, slice.size, buf, CHARS_SAFE.to_unsafe, pad: padding)
      {bytes_written, bytes_written}
    end
  end

  # Writes the base64-encoded version of *data* to *io*.
  # This method complies with [RFC 2045](https://tools.ietf.org/html/rfc2045).
  # Line feeds are added to every 60 encoded characters.
  #
  # ```
  # Base64.encode("Now is the time for all good coders\nto learn Crystal", STDOUT)
  # ```
  def encode(data, io : IO) : Int32
    slice = data.to_slice
    encode_base64_chunked_internal(slice.to_unsafe, slice.size, CHARS_STD.to_unsafe, newlines: true, pad: true) do |buf|
      io.write_string(buf)
    end.tap { io.flush }
  end

  # Writes the base64-encoded version of *data* with no newlines to *io*.
  # This method complies with [RFC 4648](https://tools.ietf.org/html/rfc4648).
  #
  # ```
  # Base64.strict_encode("Now is the time for all good coders\nto learn Crystal", STDOUT)
  # ```
  def strict_encode(data, io : IO) : Int32
    slice = data.to_slice
    encode_base64_chunked_internal(slice.to_unsafe, slice.size, CHARS_STD.to_unsafe, pad: true) do |buf|
      io.write_string(buf)
    end.tap { io.flush }
  end

  # Writes the base64-encoded version of *data* using a urlsafe alphabet to *io*.
  # This method complies with "Base 64 Encoding with URL and Filename Safe
  # Alphabet" in [RFC 4648](https://tools.ietf.org/html/rfc4648).
  #
  # The alphabet uses `'-'` instead of `'+'` and `'_'` instead of `'/'`.
  def urlsafe_encode(data, io : IO, padding = true) : Int32
    slice = data.to_slice
    encode_base64_chunked_internal(slice.to_unsafe, slice.size, CHARS_SAFE.to_unsafe, pad: padding) do |buf|
      io.write_string(buf)
    end.tap { io.flush }
  end

  # :nodoc:
  def encode(data : IO, io : IO) : Int64
    encode_base64_stream_internal(data, io, CHARS_STD.to_unsafe, newlines: true, pad: true)
  end

  # :nodoc:
  def strict_encode(data : IO, io : IO) : Int64
    encode_base64_stream_internal(data, io, CHARS_STD.to_unsafe, pad: true)
  end

  # :nodoc:
  def urlsafe_encode(data : IO, io : IO, padding = true) : Int64
    encode_base64_stream_internal(data, io, CHARS_SAFE.to_unsafe, pad: padding)
  end

  # Returns the base64-decoded version of *data* as a `Bytes`.
  # This will decode either the normal or urlsafe alphabets.
  def decode(data) : Bytes
    slice = data.to_slice
    buf = Pointer(UInt8).malloc(decode_size(slice.size))
    appender = buf.appender
    from_base64(slice) { |byte| appender << byte }
    Slice.new(buf, appender.size.to_i32)
  end

  # Writes the base64-decoded version of *data* to *io*.
  # This will decode either the normal or urlsafe alphabets.
  def decode(data, io : IO)
    count = 0
    from_base64(data.to_slice) do |byte|
      io.write_byte byte
      count += 1
    end
    io.flush
    count
  end

  # Returns the base64-decoded version of *data* as a string.
  # This will decode either the normal or urlsafe alphabets.
  def decode_string(data) : String
    slice = data.to_slice
    String.new(decode_size(slice.size)) do |buf|
      appender = buf.appender
      from_base64(slice) { |byte| appender << byte }
      {appender.size, 0}
    end
  end

  private def encode_size(str_size, new_lines = false)
    size = (str_size * 4 / 3.0).to_i + 4
    size += size // LINE_SIZE if new_lines
    size
  end

  private def decode_size(str_size)
    (str_size * 3 / 4.0).to_i + 4
  end

  # Internal method for encoding bytes from one stream as base64 into another one.
  # Returns the amount of bytes written into output.
  private def encode_base64_stream_internal(input : IO, output : IO, chars : UInt8*, *, newlines : Bool = false, pad : Bool = false) : Int64
    input_buffer = uninitialized UInt8[STREAM_MAX_INPUT_BUFFER_SIZE]
    output_buffer = uninitialized UInt8[IO::DEFAULT_BUFFER_SIZE]

    input_slice = input_buffer.to_slice

    required_bytes = newlines ? LINE_BYTES : 3
    total_written = 0_i64

    while true
      unprocessable_bytes = 0
      read_bytes = input.read(input_slice)

      input_slice += read_bytes
      available_bytes = (input_buffer.size &- input_slice.size)

      if read_bytes != 0
        next if available_bytes < required_bytes
        unprocessable_bytes = available_bytes % required_bytes
      end

      written = encode_base64_buffer_internal(input_buffer.to_unsafe, available_bytes &- unprocessable_bytes, output_buffer.to_unsafe, chars, newlines: newlines, pad: pad)
      total_written += written
      output.write_string(output_buffer.to_slice[0, written])

      break if read_bytes == 0

      # Move unprocessed bytes to the beginning of input_buffer
      Intrinsics.memmove(input_buffer.to_unsafe, input_buffer.to_unsafe + unprocessable_bytes, unprocessable_bytes, is_volatile: false) unless unprocessable_bytes == 0
      input_slice = input_buffer.to_slice + unprocessable_bytes
    end

    total_written
  end

  # Internal method for encoding bytes from one buffer as base64, using chunks allocated by this method.
  # Returns the amount of bytes written into output.
  private def encode_base64_chunked_internal(
    input : UInt8*, input_size : Int32, chars : UInt8*, *, newlines : Bool = false, pad : Bool = false, & : Bytes -> Nil
  ) : Int32
    total_written_bytes = 0

    # Make sure output's size is a multiple of (LINE_SIZE + 1) and 4,
    # so we never cut-off pairs/lines in the middle of the output.
    output = uninitialized UInt8[IO::DEFAULT_BUFFER_SIZE]

    while input_size > 0
      process_bytes = Math.min(STREAM_MAX_INPUT_BUFFER_SIZE, input_size)
      written_bytes = encode_base64_buffer_internal(input, process_bytes, output.to_unsafe, chars, newlines: newlines, pad: pad)

      input += process_bytes
      input_size &-= process_bytes

      yield output.to_slice[0, written_bytes]
      total_written_bytes &+= written_bytes
    end

    total_written_bytes
  end

  # Internal method for encoding bytes from one buffer as base64 into another one (backend of *every* encoding method).
  # Returns the amount of bytes written into output.
  private def encode_base64_buffer_internal(input : UInt8*, input_size : Int32, output : UInt8*, chars : UInt8*, *, newlines : Bool = false, pad : Bool = false) : Int32
    initial_output = output

    if newlines
      while input_size > LINE_BYTES
        encode_base64_full_pairs_internal(input, output, LINE_PAIRS, chars)

        input += LINE_BYTES
        input_size &-= LINE_BYTES
        output += LINE_SIZE
        output.value = NL
        output += 1
      end
    end

    return (output.address &- initial_output.address).to_i32! if input_size <= 0
    pairs, remaining_bytes = input_size.divmod(3)

    encode_base64_full_pairs_internal(input, output, pairs, chars)
    output += pairs &* 4

    if remaining_bytes > 0
      output += encode_base64_final_pair_internal(input + (pairs &* 3), remaining_bytes, output, chars, pad: pad)
    end

    if newlines
      output.value = NL
      output += 1
    end

    (output.address &- initial_output.address).to_i32!
  end

  # Internal method for encoding *pairs* times full 3-byte data pairs into 4-byte base64 pairs, without padding.
  #
  # *input* must have at least `pairs * 3` bytes available to process,
  # while *output* must have at least `pairs * 4` bytes of storage available.
  private def encode_base64_full_pairs_internal(input : UInt8*, output : UInt8*, pairs : Int32, chars : UInt8*) : Nil
    while pairs >= 8
      i = 8
      while i != 0
        value = 0_u32
        Intrinsics.memmove(pointerof(value), input, 4, is_volatile: false)
        input += 3

        value = value.byte_swap

        output[0] = chars[(value >> 26) & 63]
        output[1] = chars[(value >> 20) & 63]
        output[2] = chars[(value >> 14) & 63]
        output[3] = chars[(value >> 8) & 63]
        output += 4
        i &-= 1
      end
      pairs &-= 8
    end

    while pairs > 0
      value = 0_u32
      Intrinsics.memmove(pointerof(value), input, 3, is_volatile: false)
      input += 3

      value = value.byte_swap

      output[0] = chars[(value >> 26) & 63]
      output[1] = chars[(value >> 20) & 63]
      output[2] = chars[(value >> 14) & 63]
      output[3] = chars[(value >> 8) & 63]
      output += 4
      pairs &-= 1
    end
  end

  # Internal method for encoding the final 1-2 bytes of an input to base64 with or without padding.
  # Returns the amount of bytes written into output.
  #
  # This method assumes that `1 <= input_size <= 2`.
  # Otherwise, the method's behaviour is undefined.
  #
  # If `pad == `true`, exactly 4 bytes will be written to *output*.
  # Otherwise, `(input_size + 1)` bytes will be written to *output*.
  private def encode_base64_final_pair_internal(input : UInt8*, input_size : Int32, output : UInt8*, chars : UInt8*, *, pad : Bool = false) : Int32
    in0 = input[0]
    output[0] = chars[in0 >> 2]

    if input_size == 1
      output[1] = chars[in0 << 6 >> 2]
      return 2 unless pad

      output[2] = PAD
      output[3] = PAD
    else
      in1 = input[1]
      output[1] = chars[(in0 << 6 >> 2) | (in1 >> 4)]
      output[2] = chars[(in1 << 4 >> 2)]
      return 3 unless pad

      output[3] = PAD
    end

    4
  end

  # Processes the given data and yields each byte.
  private def from_base64(data : Bytes, &block : UInt8 -> Nil)
    size = data.size
    bytes = data.to_unsafe
    bytes_begin = bytes

    # Get the position of the last valid base64 character (rstrip '\n', '\r' and '=')
    while (size > 0) && (sym = bytes[size - 1]) && sym.in?(NL, NR, PAD)
      size -= 1
    end

    # Process combinations of four characters until there aren't any left
    fin = bytes + size - 4
    while true
      break if bytes > fin

      # Move the pointer by one byte until there is a valid base64 character
      while bytes.value.in?(NL, NR)
        bytes += 1
      end
      break if bytes > fin

      yield_decoded_chunk_bytes(bytes[0], bytes[1], bytes[2], bytes[3], chunk_pos: bytes - bytes_begin)
      bytes += 4
    end

    # Move the pointer by one byte until there is a valid base64 character or the end of `bytes` was reached
    while (bytes < fin + 4) && bytes.value.in?(NL, NR)
      bytes += 1
    end

    # If the amount of base64 characters is not divisible by 4, the remainder of the previous loop is handled here
    unread_bytes = (fin - bytes) % 4
    case unread_bytes
    when 1
      raise Base64::Error.new("Wrong size")
    when 2
      yield_decoded_chunk_bytes(bytes[0], bytes[1], chunk_pos: bytes - bytes_begin)
    when 3
      yield_decoded_chunk_bytes(bytes[0], bytes[1], bytes[2], chunk_pos: bytes - bytes_begin)
    end
  end

  # This macro decodes the given chunk of (2-4) base64 characters.
  # The argument chunk_pos is only used for the resulting error message.
  # The resulting bytes are then each yielded.
  private macro yield_decoded_chunk_bytes(*bytes, chunk_pos)
    %buffer = 0_u32
    {% for byte, i in bytes %}
      %decoded = DECODE_TABLE.unsafe_fetch({{byte}})
      %buffer = (%buffer << 6) + %decoded
      raise Base64::Error.new("Unexpected byte 0x#{{{byte}}.to_s(16)} at #{{{chunk_pos}} + {{i}}}") if %decoded == 255_u8
    {% end %}

    # Each byte in the buffer is shifted to rightmost position of the buffer, then casted to a UInt8
    {% for i in 2..(bytes.size) %}
      yield (%buffer >> {{ (4 - bytes.size) * 2 + (8 * (bytes.size - i)) }}).to_u8!
    {% end %}
  end

  private DECODE_TABLE = Array(UInt8).new(size: 256) do |i|
    case i.unsafe_chr
    when 'A'..'Z' then (i - 0x41).to_u8!
    when 'a'..'z' then (i - 0x47).to_u8!
    when '0'..'9' then (i + 0x04).to_u8!
    when '+', '-' then 0x3E_u8
    when '/', '_' then 0x3F_u8
    else               255_u8
    end
  end
end
