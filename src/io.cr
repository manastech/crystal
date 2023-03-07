require "c/stdio"
require "c/errno"
{% unless flag?(:win32) %}
  require "c/unistd"
{% end %}

# The `IO` class is the basis for all input and output in Crystal.
#
# This class is inherited by types like `File`, `Socket` and `IO::Memory` and
# provides many useful methods for reading from and writing to an IO, like `print`, `puts`,
# `gets` and `printf`.
#
# The only requirement for a type including the `IO` module is to define
# these two methods:
#
# * `read(slice : Bytes)`: read at most *slice.size* bytes from IO into *slice* and return the number of bytes read
# * `write(slice : Bytes)`: write the whole *slice* into the IO
#
# For example, this is a simple `IO` on top of a `Bytes`:
#
# ```
# class SimpleSliceIO < IO
#   def initialize(@slice : Bytes)
#   end
#
#   def read(slice : Bytes)
#     slice.size.times { |i| slice[i] = @slice[i] }
#     @slice += slice.size
#     slice.size
#   end
#
#   def write(slice : Bytes) : Nil
#     slice.size.times { |i| @slice[i] = slice[i] }
#     @slice += slice.size
#   end
# end
#
# slice = Slice.new(9) { |i| ('a'.ord + i).to_u8 }
# String.new(slice) # => "abcdefghi"
#
# io = SimpleSliceIO.new(slice)
# io.gets(3) # => "abc"
# io.print "xyz"
# String.new(slice) # => "abcxyzghi"
# ```
#
# ### Encoding
#
# An `IO` can be set an encoding with the `#set_encoding` method. When this is
# set, all string operations (`gets`, `gets_to_end`, `read_char`, `<<`, `print`, `puts`
# `printf`) will write in the given encoding, and read from the given encoding.
# Byte operations (`read`, `write`, `read_byte`, `write_byte`, `getb_to_end`) never do
# encoding/decoding operations.
#
# If an encoding is not set, the default one is UTF-8.
#
# Mixing string and byte operations might not give correct results and should be
# avoided, as string operations might need to read extra bytes in order to get characters
# in the given encoding.
abstract class IO
  # Default size used for generic stream buffers.
  DEFAULT_BUFFER_SIZE = 32768

  # Argument to a `seek` operation.
  enum Seek
    # Seeks to an absolute location
    Set = 0

    # Seeks to a location relative to the current location
    # in the stream
    Current = 1

    # Seeks to a location relative to the end of the stream
    # (you probably want a negative value for the amount)
    End = 2
  end

  @encoding : EncodingOptions?
  @encoder : Encoder?
  @decoder : Decoder?

  # Reads at most *slice.size* bytes from this `IO` into *slice*.
  # Returns the number of bytes read, which is 0 if and only if there is no
  # more data to read (so checking for 0 is the way to detect end of file).
  #
  # ```
  # io = IO::Memory.new "hello"
  # slice = Bytes.new(4)
  # io.read(slice) # => 4
  # slice          # => Bytes[104, 101, 108, 108]
  # io.read(slice) # => 1
  # slice          # => Bytes[111, 101, 108, 108]
  # io.read(slice) # => 0
  # ```
  abstract def read(slice : Bytes)

  # Writes the contents of *slice* into this `IO`.
  #
  # ```
  # io = IO::Memory.new
  # slice = Bytes.new(4) { |i| ('a'.ord + i).to_u8 }
  # io.write(slice)
  # io.to_s # => "abcd"
  # ```
  abstract def write(slice : Bytes) : Nil

  # Closes this `IO`.
  #
  # `IO` defines this is a no-op method, but including types may override.
  def close
  end

  # Returns `true` if this `IO` is closed.
  #
  # `IO` defines returns `false`, but including types may override.
  def closed? : Bool
    false
  end

  protected def check_open
    raise IO::Error.new "Closed stream" if closed?
  end

  # Flushes buffered data, if any.
  #
  # `IO` defines this is a no-op method, but including types may override.
  def flush
  end

  # Creates a pair of pipe endpoints (connected to each other)
  # and returns them as a two-element `Tuple`.
  #
  # ```
  # reader, writer = IO.pipe
  # writer.puts "hello"
  # writer.puts "world"
  # reader.gets # => "hello"
  # reader.gets # => "world"
  # ```
  def self.pipe(read_blocking = false, write_blocking = false) : {IO, IO}
    pipe = Pipe.new(read_blocking: read_blocking, write_blocking: write_blocking)
    {pipe.reader, pipe.writer}
  end

  # Creates a pair of pipe endpoints (connected to each other) and passes them
  # to the given block. Both endpoints are closed after the block.
  #
  # ```
  # IO.pipe do |reader, writer|
  #   writer.puts "hello"
  #   writer.puts "world"
  #   reader.gets # => "hello"
  #   reader.gets # => "world"
  # end
  # ```
  def self.pipe(read_blocking = false, write_blocking = false, &)
    r, w = IO.pipe(read_blocking, write_blocking)
    begin
      yield r, w
    ensure
      w.flush
      r.close
      w.close
    end
  end

  # Writes the given object into this `IO`.
  # This ends up calling `to_s(io)` on the object.
  #
  # ```
  # io = IO::Memory.new
  # io << 1
  # io << '-'
  # io << "Crystal"
  # io.to_s # => "1-Crystal"
  # ```
  def <<(obj) : self
    obj.to_s self
    self
  end

  # Same as `<<`.
  #
  # ```
  # io = IO::Memory.new
  # io.print 1
  # io.print '-'
  # io.print "Crystal"
  # io.to_s # => "1-Crystal"
  # ```
  def print(obj : _) : Nil
    self << obj
    nil
  end

  # Writes the given objects into this `IO` by invoking `to_s(io)`
  # on each of the objects.
  #
  # ```
  # io = IO::Memory.new
  # io.print 1, '-', "Crystal"
  # io.to_s # => "1-Crystal"
  # ```
  def print(*objects : _) : Nil
    objects.each do |obj|
      print obj
    end
    nil
  end

  # Writes *string* to this `IO`, followed by a newline character
  # unless the string already ends with one.
  #
  # ```
  # io = IO::Memory.new
  # io.puts "hello\n"
  # io.puts "world"
  # io.to_s # => "hello\nworld\n"
  # ```
  def puts(string : String) : Nil
    self << string
    puts unless string.ends_with?('\n')
    nil
  end

  # Writes *obj* to this `IO`, followed by a newline character.
  #
  # ```
  # io = IO::Memory.new
  # io.puts 1
  # io.puts "Crystal"
  # io.to_s # => "1\nCrystal\n"
  # ```
  def puts(obj : _) : Nil
    self << obj
    puts
  end

  # Writes a newline character.
  #
  # ```
  # io = IO::Memory.new
  # io.puts
  # io.to_s # => "\n"
  # ```
  def puts : Nil
    print '\n'
    nil
  end

  # Writes *objects* to this `IO`, each followed by a newline character unless
  # the object is a `String` and already ends with a newline.
  #
  # ```
  # io = IO::Memory.new
  # io.puts 1, '-', "Crystal"
  # io.to_s # => "1\n-\nCrystal\n"
  # ```
  def puts(*objects : _) : Nil
    objects.each do |obj|
      puts obj
    end
    nil
  end

  # Writes a formatted string to this IO.
  # For details on the format string, see top-level `::printf`.
  def printf(format_string, *args) : Nil
    printf format_string, args
  end

  # :ditto:
  def printf(format_string, args : Array | Tuple) : Nil
    String::Formatter(typeof(args)).new(format_string, args, self).format
  end

  # Reads a single byte from this `IO`. Returns `nil` if there is no more
  # data to read.
  #
  # ```
  # io = IO::Memory.new "a"
  # io.read_byte # => 97
  # io.read_byte # => nil
  # ```
  def read_byte : UInt8?
    byte = uninitialized UInt8
    if read(Slice.new(pointerof(byte), 1)) == 1
      byte
    else
      nil
    end
  end

  # Reads a single `Char` from this `IO`. Returns `nil` if there is no
  # more data to read.
  #
  # ```
  # io = IO::Memory.new "あ"
  # io.read_char # => 'あ'
  # io.read_char # => nil
  # ```
  def read_char : Char?
    peek = self.peek unless decoder
    info = read_char_with_bytesize(peek)
    info ? info[0] : nil
  end

  # :nodoc:
  # See also: `Char::Reader#decode_char_at`.
  private def read_char_with_bytesize(peek = nil)
    first = peek_or_read_utf8(peek, 0)
    return nil unless first
    first = first.to_u32

    if first < 0x80
      return first.unsafe_chr, 1
    end

    if first < 0xc2
      raise InvalidByteSequenceError.new("Unexpected byte 0x#{first.to_s(16)} in UTF-8 byte sequence")
    end

    second = peek_or_read_utf8_masked(peek, 1)

    if first < 0xe0
      return ((first << 6) &+ (second &- 0x3080)).unsafe_chr, 2
    end

    third = peek_or_read_utf8_masked(peek, 2)

    if first < 0xf0
      if first == 0xe0 && second < 0xa0
        raise InvalidByteSequenceError.new("Overlong UTF-8 encoding")
      end

      if first == 0xed && second >= 0xa0
        raise InvalidByteSequenceError.new("Invalid UTF-8 codepoint")
      end

      return ((first << 12) &+ (second << 6) &+ (third &- 0xE2080)).unsafe_chr, 3
    end

    if first < 0xf5
      if first == 0xf0 && second < 0x90
        raise InvalidByteSequenceError.new("Overlong UTF-8 encoding")
      end

      if first == 0xf4 && second >= 0x90
        raise InvalidByteSequenceError.new("Invalid UTF-8 codepoint")
      end

      fourth = peek_or_read_utf8_masked(peek, 3)
      return ((first << 18) &+ (second << 12) &+ (third << 6) &+ (fourth &- 0x3C82080)).unsafe_chr, 4
    end

    raise InvalidByteSequenceError.new("Unexpected byte 0x#{first.to_s(16)} in UTF-8 byte sequence")
  end

  private def peek_or_read_utf8(peek, index)
    if peek && (byte = peek[index]?)
      skip(1)
      byte
    else
      read_utf8_byte
    end
  end

  private def peek_or_read_utf8_masked(peek, index)
    byte = peek_or_read_utf8(peek, index) || raise InvalidByteSequenceError.new("Incomplete UTF-8 byte sequence")
    if (byte & 0xc0) != 0x80
      raise InvalidByteSequenceError.new("Unexpected continuation byte 0x#{byte.to_s(16)} in UTF-8 byte sequence")
    end
    byte.to_u32
  end

  # Reads a single decoded UTF-8 byte from this `IO`.
  # Returns `nil` if there is no more data to read.
  #
  # If no encoding is set, this is the same as `#read_byte`.
  #
  # ```
  # bytes = "你".encode("GB2312") # => Bytes[196, 227]
  #
  # io = IO::Memory.new(bytes)
  # io.set_encoding("GB2312")
  # io.read_utf8_byte # => 228
  # io.read_utf8_byte # => 189
  # io.read_utf8_byte # => 160
  # io.read_utf8_byte # => nil
  #
  # "你".bytes # => [228, 189, 160]
  # ```
  def read_utf8_byte : UInt8?
    if decoder = decoder()
      decoder.read_byte(self)
    else
      read_byte
    end
  end

  # Reads UTF-8 decoded bytes into the given *slice*.
  # Returns the number of UTF-8 bytes read.
  #
  # If no encoding is set, this is the same as `#read(slice)`.
  #
  # ```
  # bytes = "你".encode("GB2312") # => Bytes[196, 227]
  #
  # io = IO::Memory.new(bytes)
  # io.set_encoding("GB2312")
  #
  # buffer = uninitialized UInt8[1024]
  # bytes_read = io.read_utf8(buffer.to_slice) # => 3
  # buffer.to_slice[0, bytes_read]             # => Bytes[228, 189, 160]
  #
  # "你".bytes # => [228, 189, 160]
  # ```
  def read_utf8(slice : Bytes)
    if decoder = decoder()
      decoder.read_utf8(self, slice)
    else
      read(slice)
    end
  end

  # Reads an UTF-8 encoded string of exactly *bytesize* bytes.
  # Raises `EOFError` if there are not enough bytes to build
  # the string.
  #
  # ```
  # io = IO::Memory.new("hello world")
  # io.read_string(5) # => "hello"
  # io.read_string(1) # => " "
  # io.read_string(6) # raises IO::EOFError
  # ```
  def read_string(bytesize : Int) : String
    String.new(bytesize) do |ptr|
      if decoder = decoder()
        read = decoder.read_utf8(self, Slice.new(ptr, bytesize))
        if read != bytesize
          raise IO::EOFError.new
        end
      else
        read_fully(Slice.new(ptr, bytesize))
      end
      {bytesize, 0}
    end
  end

  # Peeks into this IO, if possible.
  #
  # It returns:
  # - `nil` if this IO isn't peekable
  # - an empty slice if it is, but EOF was reached
  # - a non-empty slice if some data can be peeked
  #
  # The returned bytes are only valid data until a next call
  # to any method that reads from this IO is invoked.
  #
  # By default this method returns `nil`, but IO implementations
  # that provide buffering or wrap other IOs should override
  # this method.
  def peek : Bytes?
    nil
  end

  # Writes the contents of *slice*, interpreted as a sequence of UTF-8 or ASCII
  # characters, into this `IO`. The contents are transcoded into this `IO`'s
  # current encoding.
  #
  # ```
  # bytes = "你".to_slice # => Bytes[228, 189, 160]
  #
  # io = IO::Memory.new
  # io.set_encoding("GB2312")
  # io.write_string(bytes)
  # io.to_slice # => Bytes[196, 227]
  #
  # "你".encode("GB2312") # => Bytes[196, 227]
  # ```
  def write_string(slice : Bytes) : Nil
    if encoder = encoder()
      encoder.write(self, slice)
    else
      write(slice)
    end

    nil
  end

  # :ditto:
  @[Deprecated("Use `#write_string` instead.")]
  def write_utf8(slice : Bytes) : Nil
    write_string(slice)
  end

  private def encoder
    if encoding = @encoding
      @encoder ||= Encoder.new(encoding)
    else
      nil
    end
  end

  private def decoder
    if encoding = @encoding
      @decoder ||= Decoder.new(encoding)
    else
      nil
    end
  end

  # Tries to read exactly `slice.size` bytes from this `IO` into *slice*.
  # Raises `EOFError` if there aren't `slice.size` bytes of data.
  #
  # ```
  # io = IO::Memory.new "123451234"
  # slice = Bytes.new(5)
  # io.read_fully(slice) # => 5
  # slice                # => Bytes[49, 50, 51, 52, 53]
  # io.read_fully(slice) # raises IO::EOFError
  # ```
  def read_fully(slice : Bytes) : Int32
    read_fully?(slice) || raise(EOFError.new)
  end

  # Tries to read exactly `slice.size` bytes from this `IO` into *slice*.
  # Returns `nil` if there aren't `slice.size` bytes of data, otherwise
  # returns the number of bytes read.
  #
  # ```
  # io = IO::Memory.new "123451234"
  # slice = Bytes.new(5)
  # io.read_fully?(slice) # => 5
  # slice                 # => Bytes[49, 50, 51, 52, 53]
  # io.read_fully?(slice) # => nil
  # ```
  def read_fully?(slice : Bytes) : Int32?
    count = slice.size
    while slice.size > 0
      read_bytes = read slice
      return nil if read_bytes == 0
      slice += read_bytes
    end
    count
  end

  # Reads the rest of this `IO` data as a `String`.
  #
  # ```
  # io = IO::Memory.new "hello world"
  # io.gets_to_end # => "hello world"
  # io.gets_to_end # => ""
  # ```
  def gets_to_end : String
    String.build do |str|
      if decoder = decoder()
        while true
          decoder.read(self)
          break if decoder.out_slice.empty?

          decoder.write(str)
        end
      else
        buffer = uninitialized UInt8[DEFAULT_BUFFER_SIZE]
        while (read_bytes = read(buffer.to_slice)) > 0
          str.write buffer.to_slice[0, read_bytes]
        end
      end
    end
  end

  # Reads the rest of this `IO` data as a writable `Bytes`.
  #
  # ```
  # io = IO::Memory.new Bytes[0, 1, 3, 6, 10, 15]
  # io.getb_to_end # => Bytes[0, 1, 3, 6, 10, 15]
  # io.getb_to_end # => Bytes[]
  # ```
  def getb_to_end : Bytes
    io = IO::Memory.new
    IO.copy(self, io)
    io.to_slice
  end

  # Reads a line from this `IO`. A line is terminated by the `\n` character.
  # Returns `nil` if called at the end of this `IO`.
  #
  # By default the newline is removed from the returned string,
  # unless *chomp* is `false`.
  #
  # ```
  # io = IO::Memory.new "hello\nworld\nfoo\n"
  # io.gets               # => "hello"
  # io.gets(chomp: false) # => "world\n"
  # io.gets               # => "foo"
  # io.gets               # => nil
  # ```
  def gets(chomp = true) : String?
    gets '\n', chomp: chomp
  end

  # Reads a line of at most *limit* bytes from this `IO`.
  # A line is terminated by the `\n` character.
  # Returns `nil` if called at the end of this `IO`.
  #
  # ```
  # io = IO::Memory.new "hello\nworld"
  # io.gets(3) # => "hel"
  # io.gets(3) # => "lo\n"
  # io.gets(3) # => "wor"
  # io.gets(3) # => "ld"
  # io.gets(3) # => nil
  # ```
  def gets(limit : Int, chomp = false) : String?
    gets '\n', limit: limit, chomp: chomp
  end

  # Reads until *delimiter* is found, or the end of the `IO` is reached.
  # Returns `nil` if called at the end of this `IO`.
  #
  # ```
  # io = IO::Memory.new "hello\nworld"
  # io.gets('o') # => "hello"
  # io.gets('r') # => "\nwor"
  # io.gets('z') # => "ld"
  # io.gets('w') # => nil
  # ```
  def gets(delimiter : Char, chomp = false) : String?
    gets delimiter, Int32::MAX, chomp: chomp
  end

  # Reads until *delimiter* is found, *limit* bytes are read, or the end of the `IO` is reached.
  # Returns `nil` if called at the end of this `IO`.
  #
  # ```
  # io = IO::Memory.new "hello\nworld"
  # io.gets('o', 3)  # => "hel"
  # io.gets('r', 10) # => "lo\nwor"
  # io.gets('z', 10) # => "ld"
  # io.gets('w', 10) # => nil
  # ```
  def gets(delimiter : Char, limit : Int, chomp = false) : String?
    raise ArgumentError.new "Negative limit" if limit < 0

    ascii = delimiter.ascii?
    decoder = decoder()

    # If the char's representation is a single byte and we have an encoding,
    # search the delimiter in the buffer
    if ascii && decoder
      return decoder.gets(self, delimiter.ord.to_u8, limit: limit, chomp: chomp)
    end

    # If there's no encoding, the delimiter is ASCII and we can peek,
    # use a faster algorithm
    if ascii && !decoder && (peek = self.peek)
      if peek.empty?
        nil
      else
        gets_peek(delimiter, limit, chomp, peek)
      end
    else
      gets_slow(delimiter, limit, chomp)
    end
  end

  private def gets_peek(delimiter, limit, chomp, peek)
    limit = Int32::MAX if limit < 0

    delimiter_byte = delimiter.ord.to_u8

    # We first check, if the delimiter is already in the peek buffer.
    # In that case it's much faster to create a String from a slice
    # of the buffer instead of appending to a IO::Memory,
    # which happens in the other case.
    index = peek.index(delimiter_byte)
    if index
      # If we find it past the limit, limit the result
      if index >= limit
        index = limit
      else
        index += 1
      end

      advance = index

      if chomp && index > 0 && peek[index - 1] === delimiter_byte
        index -= 1

        if delimiter == '\n' && index > 0 && peek[index - 1] === '\r'
          index -= 1
        end
      end

      string = String.new(peek[0, index])
      skip(advance)
      return string
    end

    # We didn't find the delimiter, so we append to a String::Builder
    # until we find it or we reach the limit, appending what we have
    # in the peek buffer and peeking again.
    String.build do |buffer|
      while peek
        available = Math.min(peek.size, limit)
        buffer.write peek[0, available]
        skip(available)
        peek += available
        limit -= available

        if limit == 0
          break
        end

        if peek.size == 0
          peek = self.peek
        end

        if !peek || peek.empty?
          if buffer.bytesize == 0
            return nil
          else
            break
          end
        end

        index = peek.index(delimiter_byte)
        if index
          if index >= limit
            index = limit
          else
            index += 1
          end
          buffer.write peek[0, index]
          skip(index)
          break
        end
      end
      buffer.chomp!(delimiter_byte) if chomp
    end
  end

  private def gets_slow(delimiter : Char, limit, chomp)
    chomp_rn = delimiter == '\n' && chomp

    buffer = String::Builder.new
    total = 0
    while true
      info = read_char_with_bytesize
      unless info
        return buffer.empty? ? nil : buffer.to_s
      end

      char, char_bytesize = info

      # Consider the case of \r\n when the delimiter is \n and chomp = true
      if chomp_rn && char == '\r'
        info2 = read_char_with_bytesize
        unless info2
          buffer << char
          break
        end

        char2, char_bytesize2 = info2
        if char2 == '\n'
          break
        end

        buffer << '\r'
        total += char_bytesize
        break if total >= limit

        buffer << char2
        total += char_bytesize2
        break if total >= limit

        next
      elsif char == delimiter
        buffer << char unless chomp
        break
      else
        buffer << char
      end

      total += char_bytesize
      break if total >= limit
    end
    buffer.to_s
  end

  # Reads until *delimiter* is found or the end of the `IO` is reached.
  # Returns `nil` if called at the end of this `IO`.
  #
  # ```
  # io = IO::Memory.new "hello\nworld"
  # io.gets("wo") # => "hello\nwo"
  # io.gets("wo") # => "rld"
  # io.gets("wo") # => nil
  # ```
  def gets(delimiter : String, chomp = false) : String?
    # Empty string: read all
    if delimiter.empty?
      return gets_to_end
    end

    # One byte: use gets(Char)
    if delimiter.bytesize == 1
      return gets(delimiter.to_unsafe[0].unsafe_chr, chomp: chomp)
    end

    # One char: use gets(Char)
    if delimiter.size == 1
      return gets(delimiter[0], chomp: chomp)
    end

    # The 'hard' case: we read until we match the last byte,
    # and then compare backwards
    last_byte = delimiter.byte_at(delimiter.bytesize - 1)
    total_bytes = 0

    buffer = String::Builder.new
    while true
      unless byte = read_utf8_byte
        return buffer.empty? ? nil : buffer.to_s
      end
      buffer.write_byte(byte)
      total_bytes += 1

      if (byte == last_byte) &&
         (buffer.bytesize >= delimiter.bytesize) &&
         (buffer.buffer + total_bytes - delimiter.bytesize).memcmp(delimiter.to_unsafe, delimiter.bytesize) == 0
        buffer.back(delimiter.bytesize) if chomp
        break
      end
    end
    buffer.to_s
  end

  # Same as `gets`, but raises `EOFError` if called at the end of this `IO`.
  def read_line(*args, **options) : String
    gets(*args, **options) || raise EOFError.new
  end

  # Reads and discards exactly *bytes_count* bytes.
  # Raises `IO::EOFError` if there aren't at least *bytes_count* bytes.
  #
  # ```
  # io = IO::Memory.new "hello world"
  # io.skip(6)
  # io.gets    # => "world"
  # io.skip(1) # raises IO::EOFError
  # ```
  def skip(bytes_count : Int) : Nil
    buffer = uninitialized UInt8[DEFAULT_BUFFER_SIZE]
    while bytes_count > 0
      read_count = read(buffer.to_slice[0, Math.min(bytes_count, buffer.size)])
      raise IO::EOFError.new if read_count == 0

      bytes_count -= read_count
    end
  end

  # Reads and discards bytes from `self` until there
  # are no more bytes.
  def skip_to_end : Nil
    buffer = uninitialized UInt8[DEFAULT_BUFFER_SIZE]
    while read(buffer.to_slice) > 0
    end
  end

  # Writes a single byte into this `IO`.
  #
  # ```
  # io = IO::Memory.new
  # io.write_byte 97_u8
  # io.to_s # => "a"
  # ```
  def write_byte(byte : UInt8) : Nil
    x = byte
    write Slice.new(pointerof(x), 1)
  end

  # Writes the given object to this `IO` using the specified *format*.
  #
  # This ends up invoking `object.to_io(self, format)`, so any object defining a
  # `to_io(io : IO, format : IO::ByteFormat = IO::ByteFormat::SystemEndian)`
  # method can be written in this way.
  #
  # See `Int#to_io` and `Float#to_io`.
  #
  # ```
  # io = IO::Memory.new
  # io.write_bytes(0x01020304, IO::ByteFormat::LittleEndian)
  # io.rewind
  # io.gets(4) # => "\u{4}\u{3}\u{2}\u{1}"
  # ```
  def write_bytes(object, format : IO::ByteFormat = IO::ByteFormat::SystemEndian) : Nil
    object.to_io(self, format)
  end

  # Reads an instance of the given *type* from this `IO` using the specified *format*.
  #
  # This ends up invoking `type.from_io(self, format)`, so any type defining a
  # `from_io(io : IO, format : IO::ByteFormat = IO::ByteFormat::SystemEndian)`
  # method can be read in this way.
  #
  # See `Int.from_io` and `Float.from_io`.
  #
  # ```
  # io = IO::Memory.new
  # io.puts "\u{4}\u{3}\u{2}\u{1}"
  # io.rewind
  # io.read_bytes(Int32, IO::ByteFormat::LittleEndian) # => 0x01020304
  # ```
  def read_bytes(type, format : IO::ByteFormat = IO::ByteFormat::SystemEndian)
    type.from_io(self, format)
  end

  # Returns `true` if this `IO` is associated with a terminal device (tty), `false` otherwise.
  #
  # IO returns `false`, but including types may override.
  #
  # ```
  # STDIN.tty?          # => true
  # IO::Memory.new.tty? # => false
  # ```
  def tty? : Bool
    false
  end

  # Invokes the given block with each *line* in this `IO`, where a line
  # is defined by the arguments passed to this method, which can be the same
  # ones as in the `gets` methods.
  #
  # ```
  # io = IO::Memory.new("hello\nworld")
  # io.each_line do |line|
  #   puts line
  # end
  # # output:
  # # hello
  # # world
  # ```
  def each_line(*args, **options, &block : String ->) : Nil
    while line = gets(*args, **options)
      yield line
    end
  end

  # Returns an `Iterator` for the *lines* in this `IO`, where a line
  # is defined by the arguments passed to this method, which can be the same
  # ones as in the `gets` methods.
  #
  # ```
  # io = IO::Memory.new("hello\nworld")
  # iter = io.each_line
  # iter.next # => "hello"
  # iter.next # => "world"
  # ```
  def each_line(*args, **options)
    LineIterator.new(self, args, options)
  end

  # Invokes the given block with each `Char` in this `IO`.
  #
  # ```
  # io = IO::Memory.new("あめ")
  # io.each_char do |char|
  #   puts char
  # end
  # ```
  #
  # Output:
  #
  # ```text
  # あ
  # め
  # ```
  def each_char(&) : Nil
    while char = read_char
      yield char
    end
  end

  # Returns an `Iterator` for the chars in this `IO`.
  #
  # ```
  # io = IO::Memory.new("あめ")
  # iter = io.each_char
  # iter.next # => 'あ'
  # iter.next # => 'め'
  # ```
  def each_char
    CharIterator.new(self)
  end

  # Invokes the given block with each byte (`UInt8`) in this `IO`.
  #
  # ```
  # io = IO::Memory.new("aあ")
  # io.each_byte do |byte|
  #   puts byte
  # end
  # ```
  #
  # Output:
  #
  # ```text
  # 97
  # 227
  # 129
  # 130
  # ```
  def each_byte(&) : Nil
    while byte = read_byte
      yield byte
    end
  end

  # Returns an `Iterator` for the bytes in this `IO`.
  #
  # ```
  # io = IO::Memory.new("aあ")
  # iter = io.each_byte
  # iter.next # => 97
  # iter.next # => 227
  # iter.next # => 129
  # iter.next # => 130
  # ```
  def each_byte
    ByteIterator.new(self)
  end

  # Rewinds this `IO`. By default this method raises, but including types
  # may implement it.
  def rewind
    raise IO::Error.new("Can't rewind")
  end

  # Sets the encoding of this `IO`.
  #
  # The *invalid* argument can be:
  # * `nil`: an exception is raised on invalid byte sequences
  # * `:skip`: invalid byte sequences are ignored
  #
  # String operations (`gets`, `gets_to_end`, `read_char`, `<<`, `print`, `puts`
  # `printf`) will use this encoding.
  def set_encoding(encoding : String, invalid : Symbol? = nil) : Nil
    if utf8_encoding?(encoding, invalid)
      @encoding = nil
    else
      @encoding = EncodingOptions.new(encoding, invalid)
    end
    @encoder.try &.close
    @decoder.try &.close
    @encoder = nil
    @decoder = nil
    nil
  end

  # Returns this `IO`'s encoding. The default is `UTF-8`.
  def encoding : String
    @encoding.try(&.name) || "UTF-8"
  end

  private def utf8_encoding?(encoding : String, invalid : Symbol? = nil) : Bool
    invalid.nil? && (
      encoding.compare("UTF-8", case_insensitive: true) == 0 ||
        encoding.compare("UTF8", case_insensitive: true) == 0
    )
  end

  # :nodoc:
  def has_non_utf8_encoding? : Bool
    !!@encoding
  end

  # Seeks to a given *offset* (in bytes) according to the *whence* argument.
  #
  # The `IO` class raises on this method, but some subclasses, notable
  # `IO::FileDescriptor` and `IO::Memory` implement it.
  #
  # Returns `self`.
  #
  # ```
  # File.write("testfile", "abc")
  #
  # file = File.new("testfile")
  # file.gets(3) # => "abc"
  # file.seek(1, IO::Seek::Set)
  # file.gets(2) # => "bc"
  # file.seek(-1, IO::Seek::Current)
  # file.gets(1) # => "c"
  # ```
  def seek(offset, whence : Seek = Seek::Set)
    raise Error.new "Unable to seek"
  end

  # Returns the current position (in bytes) in this `IO`.
  #
  # The `IO` class raises on this method, but some subclasses, notable
  # `IO::FileDescriptor` and `IO::Memory` implement it.
  #
  # ```
  # File.write("testfile", "hello")
  #
  # file = File.new("testfile")
  # file.pos     # => 0
  # file.gets(2) # => "he"
  # file.pos     # => 2
  # ```
  def pos
    raise Error.new "Unable to pos"
  end

  # Sets the current position (in bytes) in this `IO`.
  #
  # The `IO` class raises on this method, but some subclasses, notable
  # `IO::FileDescriptor` and `IO::Memory` implement it.
  #
  # ```
  # File.write("testfile", "hello")
  #
  # file = File.new("testfile")
  # file.pos = 3
  # file.gets_to_end # => "lo"
  # ```
  def pos=(value)
    raise Error.new "Unable to pos="
  end

  # Same as `pos`.
  def tell
    pos
  end

  # Yields an `IO` to read a section inside this IO.
  #
  # The `IO` class raises on this method, but some subclasses, notable
  # `File` and `IO::Memory` implement it.
  #
  # Multiple sections can be read concurrently.
  def read_at(offset, bytesize, & : IO ->)
    raise Error.new "Unable to read_at"
  end

  # Copy all contents from *src* to *dst*.
  #
  # ```
  # io = IO::Memory.new "hello"
  # io2 = IO::Memory.new
  #
  # IO.copy io, io2
  #
  # io2.to_s # => "hello"
  # ```
  def self.copy(src, dst) : Int64
    buffer = uninitialized UInt8[DEFAULT_BUFFER_SIZE]
    count = 0_i64
    while (len = src.read(buffer.to_slice).to_i32) > 0
      dst.write buffer.to_slice[0, len]
      count &+= len
    end
    count
  end

  # Copy at most *limit* bytes from *src* to *dst*.
  #
  # ```
  # io = IO::Memory.new "hello"
  # io2 = IO::Memory.new
  #
  # IO.copy io, io2, 3
  #
  # io2.to_s # => "hel"
  # ```
  def self.copy(src, dst, limit : Int) : Int64
    raise ArgumentError.new("Negative limit") if limit < 0

    limit = limit.to_i64

    buffer = uninitialized UInt8[DEFAULT_BUFFER_SIZE]
    remaining = limit
    while (len = src.read(buffer.to_slice[0, Math.min(buffer.size, Math.max(remaining, 0))])) > 0
      dst.write buffer.to_slice[0, len]
      remaining &-= len
    end
    limit - remaining
  end

  # Compares two streams *stream1* to *stream2* to determine if they are identical.
  # Returns `true` if content are the same, `false` otherwise.
  #
  # ```
  # File.write("afile", "123")
  # stream1 = File.open("afile")
  # stream2 = IO::Memory.new("123")
  # IO.same_content?(stream1, stream2) # => true
  # ```
  def self.same_content?(stream1 : IO, stream2 : IO) : Bool
    buf1 = uninitialized UInt8[1024]
    buf2 = uninitialized UInt8[1024]

    while true
      read1 = stream1.read(buf1.to_slice)
      read2 = stream2.read_fully?(buf2.to_slice[0, read1])
      return false unless read2

      return false if buf1.to_unsafe.memcmp(buf2.to_unsafe, read1) != 0
      return true if read1 == 0
    end
  end

  private struct LineIterator(I, A, N)
    include Iterator(String)

    def initialize(@io : I, @args : A, @nargs : N)
    end

    def next
      @io.gets(*@args, **@nargs) || stop
    end
  end

  private struct CharIterator(I)
    include Iterator(Char)

    def initialize(@io : I)
    end

    def next
      @io.read_char || stop
    end
  end

  private struct ByteIterator(I)
    include Iterator(UInt8)

    def initialize(@io : I)
    end

    def next
      @io.read_byte || stop
    end
  end
end

require "./io/*"
