require "c/string"
require "crystal/small_deque"
{% unless flag?(:without_iconv) %}
  require "crystal/iconv"
{% end %}
require "float/fast_float"

# A `String` represents an immutable sequence of UTF-8 characters.
#
# A `String` is typically created with a string literal, enclosing UTF-8 characters
# in double quotes:
#
# ```
# "hello world"
# ```
#
# See [`String` literals](https://crystal-lang.org/reference/syntax_and_semantics/literals/string.html) in the language reference.
#
# A backslash can be used to denote some characters inside the string:
#
# ```
# "\"" # double quote
# "\\" # backslash
# "\e" # escape
# "\f" # form feed
# "\n" # newline
# "\r" # carriage return
# "\t" # tab
# "\v" # vertical tab
# ```
#
# You can use a backslash followed by an *u* and four hexadecimal characters to denote a unicode codepoint written:
#
# ```
# "\u0041" # == "A"
# ```
#
# Or you can use curly braces and specify up to six hexadecimal numbers (0 to 10FFFF):
#
# ```
# "\u{41}" # == "A"
# ```
#
# A string can span multiple lines:
#
# ```
# "hello
#       world" # same as "hello\n      world"
# ```
#
# Note that in the above example trailing and leading spaces, as well as newlines,
# end up in the resulting string. To avoid this, you can split a string into multiple lines
# by joining multiple literals with a backslash:
#
# ```
# "hello " \
# "world, " \
# "no newlines" # same as "hello world, no newlines"
# ```
#
# Alternatively, a backslash followed by a newline can be inserted inside the string literal:
#
# ```
# "hello \
#      world, \
#      no newlines" # same as "hello world, no newlines"
# ```
#
# In this case, leading whitespace is not included in the resulting string.
#
# If you need to write a string that has many double quotes, parentheses, or similar
# characters, you can use alternative literals:
#
# ```
# # Supports double quotes and nested parentheses
# %(hello ("world")) # same as "hello (\"world\")"
#
# # Supports double quotes and nested brackets
# %[hello ["world"]] # same as "hello [\"world\"]"
#
# # Supports double quotes and nested curlies
# %{hello {"world"}} # same as "hello {\"world\"}"
#
# # Supports double quotes and nested angles
# %<hello <"world">> # same as "hello <\"world\">"
# ```
#
# To create a `String` with embedded expressions, you can use string interpolation:
#
# ```
# a = 1
# b = 2
# "sum = #{a + b}" # "sum = 3"
# ```
#
# This ends up invoking `Object#to_s(IO)` on each expression enclosed by `#{...}`.
#
# If you need to dynamically build a string, use `String#build` or `IO::Memory`.
#
# ### Non UTF-8 valid strings
#
# A string might end up being composed of bytes which form an invalid
# byte sequence according to UTF-8. This can happen if the string is created
# via one of the constructors that accept bytes, or when getting a string
# from `String.build` or `IO::Memory`. No exception will be raised, but every
# byte that doesn't start a valid UTF-8 byte sequence is interpreted as though
# it encodes the Unicode replacement character (U+FFFD) by itself. For example:
#
# ```
# # here 255 is not a valid byte value in the UTF-8 encoding
# string = String.new(Bytes[255, 97])
# string.valid_encoding? # => false
#
# # The first char here is the unicode replacement char
# string.chars # => ['�', 'a']
# ```
#
# One can also create strings with specific byte value in them by
# using octal and hexadecimal escape sequences:
#
# ```
# # Octal escape sequences
# "\101" # # => "A"
# "\12"  # # => "\n"
# "\1"   # string with one character with code point 1
# "\377" # string with one byte with value 255
#
# # Hexadecimal escape sequences
# "\x41" # # => "A"
# "\xFF" # string with one byte with value 255
# ```
#
# The reason for allowing strings that don't have a valid UTF-8 sequence
# is that the world is full of content that isn't properly encoded,
# and having a program raise an exception or stop because of this
# is not good. It's better if programs are more resilient, but
# show a replacement character when there's an error in incoming data.
#
# Note that this interpretation only applies to methods inside Crystal; calling
# `#to_slice` or `#to_unsafe`, e.g. when passing a string to a C library, will
# expose the invalid UTF-8 byte sequences. In particular, `Regex`'s underlying
# engine may reject strings that are not valid UTF-8, or it may invoke undefined
# behavior on invalid strings. If this is undesired, `#scrub` could be used to
# remove the offending byte sequences first.
class String
  # :nodoc:
  #
  # Holds the offset to the first character byte.
  HEADER_SIZE = offsetof(String, @c)

  include Comparable(self)

  macro inherited
    {{ raise "Cannot inherit from String" }}
  end

  # Creates a `String` from the given *slice*. `Bytes` will be copied from the slice.
  #
  # This method is always safe to call, and the resulting string will have
  # the contents and size of the slice.
  #
  # ```
  # slice = Slice.new(4) { |i| ('a'.ord + i).to_u8 }
  # String.new(slice) # => "abcd"
  # ```
  def self.new(slice : Bytes)
    new(slice.to_unsafe, slice.size)
  end

  # Creates a new `String` from the given *bytes*, which are encoded in the given *encoding*.
  #
  # The *invalid* argument can be:
  # * `nil`: an exception is raised on invalid byte sequences
  # * `:skip`: invalid byte sequences are ignored
  #
  # ```
  # slice = Slice.new(2, 0_u8)
  # slice[0] = 186_u8
  # slice[1] = 195_u8
  # String.new(slice, "GB2312") # => "好"
  # ```
  def self.new(bytes : Bytes, encoding : String, invalid : Symbol? = nil) : String
    String.build do |str|
      String.encode(bytes, encoding, "UTF-8", str, invalid)
    end
  end

  # Creates a `String` from a pointer. `Bytes` will be copied from the pointer.
  #
  # This method is **unsafe**: the pointer must point to data that eventually
  # contains a zero byte that indicates the ends of the string. Otherwise,
  # the result of this method is undefined and might cause a segmentation fault.
  #
  # This method is typically used in C bindings, where you get a `char*` from a
  # library and the library guarantees that this pointer eventually has an
  # ending zero byte.
  #
  # ```
  # ptr = Pointer.malloc(5) { |i| i == 4 ? 0_u8 : ('a'.ord + i).to_u8 }
  # String.new(ptr) # => "abcd"
  # ```
  def self.new(chars : UInt8*)
    raise ArgumentError.new("Cannot create a string with a null pointer") if chars.null?

    new(chars, LibC.strlen(chars))
  end

  # Creates a new `String` from a pointer, indicating its bytesize count
  # and, optionally, the UTF-8 codepoints count (size). `Bytes` will be
  # copied from the pointer.
  #
  # If the given size is zero, the amount of UTF-8 codepoints will be
  # lazily computed when needed.
  #
  # ```
  # ptr = Pointer.malloc(4) { |i| ('a'.ord + i).to_u8 }
  # String.new(ptr, 2) # => "ab"
  # ```
  def self.new(chars : UInt8*, bytesize, size = 0)
    # Avoid allocating memory for the empty string
    return "" if bytesize == 0

    if chars.null?
      raise ArgumentError.new("Cannot create a string with a null pointer and a non-zero (#{bytesize}) bytesize")
    end

    new(bytesize) do |buffer|
      buffer.copy_from(chars, bytesize)
      {bytesize, size}
    end
  end

  # Creates a new `String` by allocating a buffer (`Pointer(UInt8)`) with the given capacity, then
  # yielding that buffer. The block must return a tuple with the bytesize and size
  # (UTF-8 codepoints count) of the String. If the returned size is zero, the UTF-8 codepoints
  # count will be lazily computed.
  #
  # The bytesize returned by the block must be less than or equal to the
  # capacity given to this String, otherwise `ArgumentError` is raised.
  #
  # If you need to build a `String` where the maximum capacity is unknown, use `String#build`.
  #
  # ```
  # str = String.new(4) do |buffer|
  #   buffer[0] = 'a'.ord.to_u8
  #   buffer[1] = 'b'.ord.to_u8
  #   {2, 2}
  # end
  # str # => "ab"
  # ```
  def self.new(capacity : Int, &)
    check_capacity_in_bounds(capacity)

    str = GC.malloc_atomic(capacity.to_u32 + HEADER_SIZE + 1).as(UInt8*)
    buffer = str.as(String).to_unsafe
    bytesize, size = yield buffer

    unless 0 <= bytesize <= capacity
      raise ArgumentError.new("Bytesize out of capacity bounds")
    end

    buffer[bytesize] = 0_u8

    # Try to reclaim some memory if capacity is bigger than what was requested
    if bytesize < capacity
      str = GC.realloc(str, bytesize.to_u32 + HEADER_SIZE + 1)
    end

    set_crystal_type_id(str)
    str = str.as(String)
    str.initialize_header(bytesize.to_i, size.to_i)
    str
  end

  # :nodoc:
  #
  # Initializes the header information of a `String` instance.
  # The actual character content at `@c` is expected to be already filled and is
  # unaffected by this method.
  def initialize_header(@bytesize : Int32, @length : Int32 = 0)
  end

  # Builds a `String` by creating a `String::Builder` with the given initial capacity, yielding
  # it to the block and finally getting a `String` out of it. The `String::Builder` automatically
  # resizes as needed.
  #
  # ```
  # str = String.build do |str|
  #   str << "hello "
  #   str << 1
  # end
  # str # => "hello 1"
  # ```
  def self.build(capacity = 64, &) : self
    String::Builder.build(capacity) do |builder|
      yield builder
    end
  end

  # Returns the number of bytes in this string.
  #
  # ```
  # "hello".bytesize # => 5
  # "你好".bytesize    # => 6
  # ```
  def bytesize : Int32
    @bytesize
  end

  # Returns the result of interpreting leading characters in this string as an
  # integer base *base* (between 2 and 36).
  #
  # If there is not a valid number at the start of this string,
  # or if the resulting integer doesn't fit an `Int32`, an `ArgumentError` is raised.
  #
  # Options:
  # * **whitespace**: if `true`, leading and trailing whitespaces are allowed
  # * **underscore**: if `true`, underscores in numbers are allowed
  # * **prefix**: if `true`, the prefixes `"0x"`, `"0o"` and `"0b"` override the base
  # * **strict**: if `true`, extraneous characters past the end of the number
  #   are disallowed, unless **whitespace** is also `true` and all the trailing
  #   characters past the number are whitespaces
  # * **leading_zero_is_octal**: if `true`, then a number prefixed with `"0"` will be treated as an octal
  #
  # ```
  # "12345".to_i             # => 12345
  # "0a".to_i                # raises ArgumentError
  # "hello".to_i             # raises ArgumentError
  # "0a".to_i(16)            # => 10
  # "1100101".to_i(2)        # => 101
  # "1100101".to_i(8)        # => 294977
  # "1100101".to_i(10)       # => 1100101
  # "1100101".to_i(base: 16) # => 17826049
  #
  # "12_345".to_i                   # raises ArgumentError
  # "12_345".to_i(underscore: true) # => 12345
  #
  # "  12345  ".to_i                    # => 12345
  # "  12345  ".to_i(whitespace: false) # raises ArgumentError
  #
  # "0x123abc".to_i               # raises ArgumentError
  # "0x123abc".to_i(prefix: true) # => 1194684
  #
  # "99 red balloons".to_i                # raises ArgumentError
  # "99 red balloons".to_i(strict: false) # => 99
  #
  # "0755".to_i                              # => 755
  # "0755".to_i(leading_zero_is_octal: true) # => 493
  # ```
  def to_i(base : Int = 10, whitespace : Bool = true, underscore : Bool = false, prefix : Bool = false, strict : Bool = true, leading_zero_is_octal : Bool = false)
    to_i32(base, whitespace, underscore, prefix, strict, leading_zero_is_octal)
  end

  # Same as `#to_i`, but returns `nil` if there is not a valid number at the start
  # of this string, or if the resulting integer doesn't fit an `Int32`.
  #
  # ```
  # "12345".to_i?             # => 12345
  # "99 red balloons".to_i?   # => nil
  # "0a".to_i?(strict: false) # => 0
  # "hello".to_i?             # => nil
  # ```
  def to_i?(base : Int = 10, whitespace : Bool = true, underscore : Bool = false, prefix : Bool = false, strict : Bool = true, leading_zero_is_octal : Bool = false)
    to_i32?(base, whitespace, underscore, prefix, strict, leading_zero_is_octal)
  end

  # Same as `#to_i`, but returns the block's value if there is not a valid number at the start
  # of this string, or if the resulting integer doesn't fit an `Int32`.
  #
  # ```
  # "12345".to_i { 0 } # => 12345
  # "hello".to_i { 0 } # => 0
  # ```
  def to_i(base : Int = 10, whitespace : Bool = true, underscore : Bool = false, prefix : Bool = false, strict : Bool = true, leading_zero_is_octal : Bool = false, &block)
    to_i32(base, whitespace, underscore, prefix, strict, leading_zero_is_octal) { yield }
  end

  # Same as `#to_i` but returns an `Int8`.
  def to_i8(base : Int = 10, whitespace : Bool = true, underscore : Bool = false, prefix : Bool = false, strict : Bool = true, leading_zero_is_octal : Bool = false) : Int8
    to_i8(base, whitespace, underscore, prefix, strict, leading_zero_is_octal) { raise ArgumentError.new("Invalid Int8: #{self.inspect}") }
  end

  # Same as `#to_i` but returns an `Int8` or `nil`.
  def to_i8?(base : Int = 10, whitespace : Bool = true, underscore : Bool = false, prefix : Bool = false, strict : Bool = true, leading_zero_is_octal : Bool = false) : Int8?
    to_i8(base, whitespace, underscore, prefix, strict, leading_zero_is_octal) { nil }
  end

  # Same as `#to_i` but returns an `Int8` or the block's value.
  def to_i8(base : Int = 10, whitespace : Bool = true, underscore : Bool = false, prefix : Bool = false, strict : Bool = true, leading_zero_is_octal : Bool = false, &block)
    gen_to_ Int8, UInt8, 127, 128
  end

  # Same as `#to_i` but returns an `UInt8`.
  def to_u8(base : Int = 10, whitespace : Bool = true, underscore : Bool = false, prefix : Bool = false, strict : Bool = true, leading_zero_is_octal : Bool = false) : UInt8
    to_u8(base, whitespace, underscore, prefix, strict, leading_zero_is_octal) { raise ArgumentError.new("Invalid UInt8: #{self.inspect}") }
  end

  # Same as `#to_i` but returns an `UInt8` or `nil`.
  def to_u8?(base : Int = 10, whitespace : Bool = true, underscore : Bool = false, prefix : Bool = false, strict : Bool = true, leading_zero_is_octal : Bool = false) : UInt8?
    to_u8(base, whitespace, underscore, prefix, strict, leading_zero_is_octal) { nil }
  end

  # Same as `#to_i` but returns an `UInt8` or the block's value.
  def to_u8(base : Int = 10, whitespace : Bool = true, underscore : Bool = false, prefix : Bool = false, strict : Bool = true, leading_zero_is_octal : Bool = false, &block)
    gen_to_ UInt8, UInt8
  end

  # Same as `#to_i` but returns an `Int16`.
  def to_i16(base : Int = 10, whitespace : Bool = true, underscore : Bool = false, prefix : Bool = false, strict : Bool = true, leading_zero_is_octal : Bool = false) : Int16
    to_i16(base, whitespace, underscore, prefix, strict, leading_zero_is_octal) { raise ArgumentError.new("Invalid Int16: #{self.inspect}") }
  end

  # Same as `#to_i` but returns an `Int16` or `nil`.
  def to_i16?(base : Int = 10, whitespace : Bool = true, underscore : Bool = false, prefix : Bool = false, strict : Bool = true, leading_zero_is_octal : Bool = false) : Int16?
    to_i16(base, whitespace, underscore, prefix, strict, leading_zero_is_octal) { nil }
  end

  # Same as `#to_i` but returns an `Int16` or the block's value.
  def to_i16(base : Int = 10, whitespace : Bool = true, underscore : Bool = false, prefix : Bool = false, strict : Bool = true, leading_zero_is_octal : Bool = false, &block)
    gen_to_ Int16, UInt16, 32767, 32768
  end

  # Same as `#to_i` but returns an `UInt16`.
  def to_u16(base : Int = 10, whitespace : Bool = true, underscore : Bool = false, prefix : Bool = false, strict : Bool = true, leading_zero_is_octal : Bool = false) : UInt16
    to_u16(base, whitespace, underscore, prefix, strict, leading_zero_is_octal) { raise ArgumentError.new("Invalid UInt16: #{self.inspect}") }
  end

  # Same as `#to_i` but returns an `UInt16` or `nil`.
  def to_u16?(base : Int = 10, whitespace : Bool = true, underscore : Bool = false, prefix : Bool = false, strict : Bool = true, leading_zero_is_octal : Bool = false) : UInt16?
    to_u16(base, whitespace, underscore, prefix, strict, leading_zero_is_octal) { nil }
  end

  # Same as `#to_i` but returns an `UInt16` or the block's value.
  def to_u16(base : Int = 10, whitespace : Bool = true, underscore : Bool = false, prefix : Bool = false, strict : Bool = true, leading_zero_is_octal : Bool = false, &block)
    gen_to_ UInt16, UInt16
  end

  # Same as `#to_i`.
  def to_i32(base : Int = 10, whitespace : Bool = true, underscore : Bool = false, prefix : Bool = false, strict : Bool = true, leading_zero_is_octal : Bool = false) : Int32
    to_i32(base, whitespace, underscore, prefix, strict, leading_zero_is_octal) { raise ArgumentError.new("Invalid Int32: #{self.inspect}") }
  end

  # Same as `#to_i`.
  def to_i32?(base : Int = 10, whitespace : Bool = true, underscore : Bool = false, prefix : Bool = false, strict : Bool = true, leading_zero_is_octal : Bool = false) : Int32?
    to_i32(base, whitespace, underscore, prefix, strict, leading_zero_is_octal) { nil }
  end

  # Same as `#to_i`.
  def to_i32(base : Int = 10, whitespace : Bool = true, underscore : Bool = false, prefix : Bool = false, strict : Bool = true, leading_zero_is_octal : Bool = false, &block)
    gen_to_ Int32, UInt32, 2147483647, 2147483648
  end

  # Same as `#to_i` but returns an `UInt32`.
  def to_u32(base : Int = 10, whitespace : Bool = true, underscore : Bool = false, prefix : Bool = false, strict : Bool = true, leading_zero_is_octal : Bool = false) : UInt32
    to_u32(base, whitespace, underscore, prefix, strict, leading_zero_is_octal) { raise ArgumentError.new("Invalid UInt32: #{self.inspect}") }
  end

  # Same as `#to_i` but returns an `UInt32` or `nil`.
  def to_u32?(base : Int = 10, whitespace : Bool = true, underscore : Bool = false, prefix : Bool = false, strict : Bool = true, leading_zero_is_octal : Bool = false) : UInt32?
    to_u32(base, whitespace, underscore, prefix, strict, leading_zero_is_octal) { nil }
  end

  # Same as `#to_i` but returns an `UInt32` or the block's value.
  def to_u32(base : Int = 10, whitespace : Bool = true, underscore : Bool = false, prefix : Bool = false, strict : Bool = true, leading_zero_is_octal : Bool = false, &block)
    gen_to_ UInt32, UInt32
  end

  # Same as `#to_i` but returns an `Int64`.
  def to_i64(base : Int = 10, whitespace : Bool = true, underscore : Bool = false, prefix : Bool = false, strict : Bool = true, leading_zero_is_octal : Bool = false) : Int64
    to_i64(base, whitespace, underscore, prefix, strict, leading_zero_is_octal) { raise ArgumentError.new("Invalid Int64: #{self.inspect}") }
  end

  # Same as `#to_i` but returns an `Int64` or `nil`.
  def to_i64?(base : Int = 10, whitespace : Bool = true, underscore : Bool = false, prefix : Bool = false, strict : Bool = true, leading_zero_is_octal : Bool = false) : Int64?
    to_i64(base, whitespace, underscore, prefix, strict, leading_zero_is_octal) { nil }
  end

  # Same as `#to_i` but returns an `Int64` or the block's value.
  def to_i64(base : Int = 10, whitespace : Bool = true, underscore : Bool = false, prefix : Bool = false, strict : Bool = true, leading_zero_is_octal : Bool = false, &block)
    gen_to_ Int64, UInt64, 9223372036854775807, 9223372036854775808u64
  end

  # Same as `#to_i` but returns an `UInt64`.
  def to_u64(base : Int = 10, whitespace : Bool = true, underscore : Bool = false, prefix : Bool = false, strict : Bool = true, leading_zero_is_octal : Bool = false) : UInt64
    to_u64(base, whitespace, underscore, prefix, strict, leading_zero_is_octal) { raise ArgumentError.new("Invalid UInt64: #{self.inspect}") }
  end

  # Same as `#to_i` but returns an `UInt64` or `nil`.
  def to_u64?(base : Int = 10, whitespace : Bool = true, underscore : Bool = false, prefix : Bool = false, strict : Bool = true, leading_zero_is_octal : Bool = false) : UInt64?
    to_u64(base, whitespace, underscore, prefix, strict, leading_zero_is_octal) { nil }
  end

  # Same as `#to_i` but returns an `UInt64` or the block's value.
  def to_u64(base : Int = 10, whitespace : Bool = true, underscore : Bool = false, prefix : Bool = false, strict : Bool = true, leading_zero_is_octal : Bool = false, &block)
    gen_to_ UInt64, UInt64
  end

  # Same as `#to_i` but returns an `Int128`.
  def to_i128(base : Int = 10, whitespace : Bool = true, underscore : Bool = false, prefix : Bool = false, strict : Bool = true, leading_zero_is_octal : Bool = false) : Int128
    to_i128(base, whitespace, underscore, prefix, strict, leading_zero_is_octal) { raise ArgumentError.new("Invalid Int128: #{self.inspect}") }
  end

  # Same as `#to_i` but returns an `Int128` or `nil`.
  def to_i128?(base : Int = 10, whitespace : Bool = true, underscore : Bool = false, prefix : Bool = false, strict : Bool = true, leading_zero_is_octal : Bool = false) : Int128?
    to_i128(base, whitespace, underscore, prefix, strict, leading_zero_is_octal) { nil }
  end

  # Same as `#to_i` but returns an `Int128` or the block's value.
  def to_i128(base : Int = 10, whitespace : Bool = true, underscore : Bool = false, prefix : Bool = false, strict : Bool = true, leading_zero_is_octal : Bool = false, &block)
    gen_to_ Int128, UInt128, Int128::MAX, (UInt128.new(Int128::MAX) + 1)
  end

  # Same as `#to_i` but returns an `UInt128`.
  def to_u128(base : Int = 10, whitespace : Bool = true, underscore : Bool = false, prefix : Bool = false, strict : Bool = true, leading_zero_is_octal : Bool = false) : UInt128
    to_u128(base, whitespace, underscore, prefix, strict, leading_zero_is_octal) { raise ArgumentError.new("Invalid UInt128: #{self.inspect}") }
  end

  # Same as `#to_i` but returns an `UInt128` or `nil`.
  def to_u128?(base : Int = 10, whitespace : Bool = true, underscore : Bool = false, prefix : Bool = false, strict : Bool = true, leading_zero_is_octal : Bool = false) : UInt128?
    to_u128(base, whitespace, underscore, prefix, strict, leading_zero_is_octal) { nil }
  end

  # Same as `#to_i` but returns an `UInt128` or the block's value.
  def to_u128(base : Int = 10, whitespace : Bool = true, underscore : Bool = false, prefix : Bool = false, strict : Bool = true, leading_zero_is_octal : Bool = false, &block)
    gen_to_ UInt128, UInt128
  end

  # :nodoc:
  CHAR_TO_DIGIT = begin
    table = StaticArray(Int8, 256).new(-1_i8)
    10_i8.times do |i|
      table.to_unsafe[48 + i] = i
    end
    26_i8.times do |i|
      table.to_unsafe[65 + i] = i + 10
      table.to_unsafe[97 + i] = i + 10
    end
    table
  end

  # :nodoc:
  CHAR_TO_DIGIT62 = begin
    table = CHAR_TO_DIGIT.clone
    26_i8.times do |i|
      table.to_unsafe[65 + i] = i + 36
    end
    table
  end

  # :nodoc:
  record ToUnsignedInfo(T),
    value : T,
    negative : Bool,
    invalid : Bool

  private macro gen_to_(int_class, unsigned_int_class, max_positive = nil, max_negative = nil)
    {% unsigned = int_class == unsigned_int_class %}
    info = to_unsigned_info({{unsigned_int_class}}, base, whitespace, underscore, prefix, strict, leading_zero_is_octal, unsigned: {{unsigned}})

    return yield if info.invalid

    if info.negative
      {% if max_negative %}
        return yield if info.value > {{max_negative}}
        (~info.value &+ 1).unsafe_as({{int_class}})
      {% else %}
        return yield
      {% end %}
    else
      {% if max_positive %}
        return yield if info.value > {{max_positive}}
      {% end %}
      {{int_class}}.new(info.value)
    end
  end

  private def to_unsigned_info(int_class, base, whitespace, underscore, prefix, strict, leading_zero_is_octal, unsigned)
    raise ArgumentError.new("Invalid base #{base}") unless 2 <= base <= 36 || base == 62

    ptr = to_unsafe

    # Skip leading whitespace
    if whitespace
      ptr += calc_excess_left
    end

    negative = false

    # Check + and -
    case ptr.value.unsafe_chr
    when '-'
      if unsigned
        return ToUnsignedInfo.new(value: int_class.new(0), negative: true, invalid: true)
      end
      negative = true
      ptr += 1
    when '+'
      ptr += 1
    else
      # no sign prefix
    end

    found_digit = false
    last_is_underscore = true

    # Check leading zero
    if ptr.value.unsafe_chr == '0'
      ptr += 1
      last_is_underscore = false
      if prefix
        case ptr.value.unsafe_chr
        when 'b'
          base = 2
          ptr += 1
        when 'x'
          base = 16
          ptr += 1
        when 'o'
          base = 8
          ptr += 1
        else
          if leading_zero_is_octal
            base = 8
          else
            base = 10
            found_digit = true
          end
        end
      elsif leading_zero_is_octal
        base = 8
      else
        found_digit = true
      end
    end

    value = int_class.new(0)
    mul_overflow = ~(int_class.new(0)) // base
    invalid = false

    digits = (base == 62 ? CHAR_TO_DIGIT62 : CHAR_TO_DIGIT).to_unsafe
    while ptr.value != 0
      if underscore && ptr.value.unsafe_chr == '_'
        break if last_is_underscore
        last_is_underscore = true
        ptr += 1
        next
      end

      last_is_underscore = false
      digit = digits[ptr.value]
      if digit == -1 || digit >= base
        break
      end

      if value > mul_overflow
        invalid = true
        break
      end

      value *= base

      old = value
      value &+= digit
      if value < old
        invalid = true
        break
      end

      found_digit = true
      ptr += 1
    end

    if found_digit
      unless ptr.value == 0
        if whitespace
          ptr += calc_excess_right
        end

        if strict && ptr.value != 0
          invalid = true
        end
      end
    else
      invalid = true
    end

    ToUnsignedInfo.new(value: value, negative: negative, invalid: invalid)
  end

  # Returns the result of interpreting characters in this string as a floating point number (`Float64`).
  # This method raises an exception if the string is not a valid float representation
  # or exceeds the range of the data type. Values representing infinity or NaN
  # are considered valid.
  #
  # Options:
  # * **whitespace**: if `true`, leading and trailing whitespaces are allowed
  # * **strict**: if `true`, extraneous characters past the end of the number
  #   are disallowed, unless **whitespace** is also `true` and all the trailing
  #   characters past the number are whitespaces
  #
  # ```
  # "123.45e1".to_f                # => 1234.5
  # "45.67 degrees".to_f           # raises ArgumentError
  # "thx1138".to_f(strict: false)  # raises ArgumentError
  # " 1.2".to_f(whitespace: false) # raises ArgumentError
  # "1.2foo".to_f(strict: false)   # => 1.2
  # ```
  def to_f(whitespace : Bool = true, strict : Bool = true) : Float64
    to_f64(whitespace: whitespace, strict: strict)
  end

  # :ditto:
  def to_f64(whitespace : Bool = true, strict : Bool = true) : Float64
    to_f64?(whitespace: whitespace, strict: strict) || raise ArgumentError.new("Invalid Float64: #{self.inspect}")
  end

  # Returns the result of interpreting characters in this string as a floating point number (`Float64`).
  # This method returns `nil` if the string is not a valid float representation
  # or exceeds the range of the data type. Values representing infinity or NaN
  # are considered valid.
  #
  # Options:
  # * **whitespace**: if `true`, leading and trailing whitespaces are allowed
  # * **strict**: if `true`, extraneous characters past the end of the number
  #   are disallowed, unless **whitespace** is also `true` and all the trailing
  #   characters past the number are whitespaces
  #
  # ```
  # "123.45e1".to_f?                # => 1234.5
  # "45.67 degrees".to_f?           # => nil
  # "thx1138".to_f?                 # => nil
  # " 1.2".to_f?(whitespace: false) # => nil
  # "1.2foo".to_f?(strict: false)   # => 1.2
  # ```
  def to_f?(whitespace : Bool = true, strict : Bool = true) : Float64?
    to_f64?(whitespace: whitespace, strict: strict)
  end

  # :ditto:
  def to_f64?(whitespace : Bool = true, strict : Bool = true) : Float64?
    Float::FastFloat.to_f64?(self, whitespace, strict)
  end

  # Same as `#to_f` but returns a Float32.
  def to_f32(whitespace : Bool = true, strict : Bool = true) : Float32
    to_f32?(whitespace: whitespace, strict: strict) || raise ArgumentError.new("Invalid Float32: #{self.inspect}")
  end

  # Same as `#to_f?` but returns a Float32.
  def to_f32?(whitespace : Bool = true, strict : Bool = true) : Float32?
    Float::FastFloat.to_f32?(self, whitespace, strict)
  end

  # Returns the `Char` at the given *index*.
  #
  # Negative indices can be used to start counting from the end of the string.
  #
  # Raises `IndexError` if the *index* is out of bounds.
  #
  # ```
  # "hello"[0]  # => 'h'
  # "hello"[1]  # => 'e'
  # "hello"[-1] # => 'o'
  # "hello"[-2] # => 'l'
  # "hello"[5]  # raises IndexError
  # ```
  def [](index : Int) : Char
    char_at(index) { raise IndexError.new }
  end

  # Returns the substring indicated by *range* as span of character indices.
  #
  # The substring ranges from `self[range.begin]` to `self[range.end]`
  # (or `self[range.end - 1]` if the range is exclusive). It can be smaller than
  # `range.size` if the end index is larger than `self.size`.
  #
  # ```
  # s = "abcde"
  # s[1..3] # => "bcd"
  # # range.end > s.size
  # s[3..7] # => "de"
  # ```
  #
  # Open ended ranges are clamped at the start and end of `self`, respectively.
  #
  # ```
  # # open ended ranges
  # s[2..] # => "cde"
  # s[..2] # => "abc"
  # ```
  #
  # Negative range values are added to `self.size`, thus they are treated as
  # character indices counting from the end, `-1` designating the last character.
  #
  # ```
  # # negative indices, both ranges are equivalent for `s`
  # s[1..3]   # => "bcd"
  # s[-4..-2] # => "bcd"
  # # Mixing negative and positive indices, both ranges are equivalent for `s`
  # s[1..-2] # => "bcd"
  # s[-4..3] # => "bcd"
  # ```
  #
  # Raises `IndexError` if the start index it out of range (`range.begin >
  # self.size || range.begin < -self.size). If `range.begin == self.size` an
  # empty string is returned. If `range.begin > range.end`, an empty string is
  # returned.
  #
  # ```
  # # range.begin > array.size
  # s[6..10] # raise IndexError
  # # range.begin == s.size
  # s[5..10] # => ""
  # # range.begin > range.end
  # s[3..1]   # => ""
  # s[-2..-4] # => ""
  # s[-2..1]  # => ""
  # s[3..-4]  # => ""
  # ```
  def [](range : Range) : String
    self[*Indexable.range_to_index_and_count(range, size) || raise IndexError.new]
  end

  # Like `#[](Range)`, but returns `nil` if `range.begin` is out of range.
  #
  # ```
  # "hello"[6..7]? # => nil
  # "hello"[6..]?  # => nil
  # ```
  def []?(range : Range) : String?
    self[*Indexable.range_to_index_and_count(range, size) || return nil]?
  end

  # Returns a substring starting from the *start* character of size *count*.
  #
  # Negative *start* is added to `self.size`, thus it's treated as a character
  # index counting from the end, `-1` designating the last character.
  #
  # Raises `IndexError` if *start* index is out of bounds.
  # Raises `ArgumentError` if *count* is negative.
  def [](start : Int, count : Int) : String
    self[start, count]? || raise IndexError.new
  end

  # Like `#[](Int, Int)` but returns `nil` if the *start* index is out of bounds.
  def []?(start : Int, count : Int) : String?
    return byte_slice?(start, count) if single_byte_optimizable?

    start, count = Indexable.normalize_start_and_count(start, count, size) { return nil }
    return "" if count == 0
    return self if count == size

    start_pos, end_pos = find_start_and_end(start, count)
    byte_count = end_pos - start_pos

    String.new(byte_count) do |buffer|
      buffer.copy_from(to_unsafe + start_pos, byte_count)
      {byte_count, 0}
    end
  end

  # Returns the character at *index* or `nil` if it's out of range.
  #
  # Negative indices can be used to start counting from the end of the string.
  #
  # See `#[]` for a raising alternative.
  #
  # ```
  # "hello"[0]?  # => 'h'
  # "hello"[1]?  # => 'e'
  # "hello"[-1]? # => 'o'
  # "hello"[-2]? # => 'l'
  # "hello"[5]?  # => nil
  # ```
  def []?(index : Int) : Char?
    char_at(index) { nil }
  end

  # Returns *str* if *str* is found in this string, or `nil` otherwise.
  #
  # ```
  # "crystal"["cry"]?  # => "cry"
  # "crystal"["ruby"]? # => nil
  # ```
  def []?(str : String | Char)
    includes?(str) ? str : nil
  end

  def []?(regex : Regex, *, options : Regex::MatchOptions = Regex::MatchOptions::None) : String?
    self[regex, 0, options: options]?
  end

  def []?(regex : Regex, group, *, options : Regex::MatchOptions = Regex::MatchOptions::None) : String?
    match = match(regex, options: options)
    match[group]? if match
  end

  # Returns *str* if *str* is found in this string.
  #
  # ```
  # "crystal"["cry"]  # => "cry"
  # "crystal"["ruby"] # raises NilAssertionError
  # ```
  def [](str : String | Char)
    self[str]?.not_nil!
  end

  def [](regex : Regex, *, options : Regex::MatchOptions = Regex::MatchOptions::None) : String
    self[regex, options: options]?.not_nil!
  end

  def [](regex : Regex, group, *, options : Regex::MatchOptions = Regex::MatchOptions::None) : String
    self[regex, group, options: options]?.not_nil!
  end

  # Returns the `Char` at the given *index*.
  #
  # Negative indices can be used to start counting from the end of the string.
  #
  # Raises `IndexError` if the *index* is out of bounds.
  #
  # ```
  # "hello".char_at(0)  # => 'h'
  # "hello".char_at(1)  # => 'e'
  # "hello".char_at(-1) # => 'o'
  # "hello".char_at(-2) # => 'l'
  # "hello".char_at(5)  # raises IndexError
  # ```
  def char_at(index : Int) : Char
    char_at(index) { raise IndexError.new }
  end

  # Returns the `Char` at the given *index*, or result of running the given block if out of bounds.
  #
  # Negative indices can be used to start counting from the end of the string.
  #
  # ```
  # "hello".char_at(4) { 'x' }  # => 'o'
  # "hello".char_at(5) { 'x' }  # => 'x'
  # "hello".char_at(-1) { 'x' } # => 'o'
  # "hello".char_at(-5) { 'x' } # => 'h'
  # "hello".char_at(-6) { 'x' } # => 'x'
  # ```
  def char_at(index : Int, &)
    if single_byte_optimizable?
      byte = byte_at?(index)
      if byte
        return byte < 0x80 ? byte.unsafe_chr : Char::REPLACEMENT
      else
        return yield
      end
    end

    index += size if index < 0

    byte_index = char_index_to_byte_index(index)
    if byte_index && byte_index < @bytesize
      Char::Reader.new(self, pos: byte_index).current_char
    else
      yield
    end
  end

  # Returns a new string that results from deleting characters
  # at the given range.
  #
  # ```
  # "abcdef".delete_at(1..3) # => "aef"
  # ```
  #
  # Negative indices can be used to start counting from the end of the string:
  #
  # ```
  # "abcdef".delete_at(-3..-2) # => "abcf"
  # ```
  #
  # Raises `IndexError` if any index is outside the bounds of this string.
  def delete_at(range : Range) : String
    delete_at(*Indexable.range_to_index_and_count(range, size) || raise IndexError.new)
  end

  # Returns a new string that results from deleting the character
  # at the given *index*.
  #
  # ```
  # "abcde".delete_at(0) # => "bcde"
  # "abcde".delete_at(2) # => "abde"
  # "abcde".delete_at(4) # => "abcd"
  # ```
  #
  # A negative *index* counts from the end of the string:
  #
  # ```
  # "abcde".delete_at(-2) # => "abce"
  # ```
  #
  # If *index* is outside the bounds of the string, `IndexError` is raised.
  def delete_at(index : Int) : String
    index += size if index < 0

    byte_index = char_index_to_byte_index(index)
    if byte_index && byte_index < @bytesize
      char_bytesize = char_bytesize_at(byte_index)

      new_bytesize = self.bytesize - char_bytesize
      String.new(new_bytesize) do |buffer|
        # Copy left part
        buffer.copy_from(to_unsafe, byte_index)

        # Copy right part
        (buffer + byte_index).copy_from(
          to_unsafe + byte_index + char_bytesize,
          self.bytesize - byte_index - char_bytesize,
        )

        {new_bytesize, size - 1}
      end
    else
      raise IndexError.new
    end
  end

  # Returns a new string that results from deleting *count* characters
  # starting at *start*.
  #
  # ```
  # "abcdefg".delete_at(1, 3) # => "aefg"
  # ```
  #
  # Deleting more characters than those in the string is valid, and just
  # results in deleting up to the last character:
  #
  # ```
  # "abcdefg".delete_at(3, 10) # => "abc"
  # ```
  #
  # A negative *start* counts from the end of the string:
  #
  # ```
  # "abcdefg".delete_at(-3, 2) # => "abcdg"
  # ```
  #
  # If *count* is negative, `ArgumentError` is raised.
  #
  # If *start* is outside the bounds of the string, `ArgumentError`
  # is raised.
  #
  # However, *start* can be the position that is exactly the end of the string:
  #
  # ```
  # "abcd".delete_at(4, 3) # => "abcd"
  # ```
  def delete_at(start : Int, count : Int) : String
    start, count = Indexable.normalize_start_and_count(start, count, size)

    case count
    when 0
      self
    when size
      ""
    else
      if single_byte_optimizable?
        byte_delete_at(start, count, count)
      else
        unicode_delete_at(start, count)
      end
    end
  end

  # :ditto:
  @[Deprecated("Use `#delete_at(start, count)` instead")]
  def delete_at(*, index start : Int, count : Int) : String
    delete_at(start, count)
  end

  private def byte_delete_at(start, count, byte_count)
    new_bytesize = bytesize - byte_count
    String.new(new_bytesize) do |buffer|
      # Copy left part
      buffer.copy_from(to_unsafe, start)

      # Copy right part
      (buffer + start).copy_from(
        to_unsafe + start + byte_count,
        bytesize - start - byte_count,
      )

      {new_bytesize, size - count}
    end
  end

  private def unicode_delete_at(start, count)
    start_pos, end_pos = find_start_and_end(start, count)
    byte_delete_at(start_pos, count, end_pos - start_pos)
  end

  private def find_start_and_end(start, count)
    start_pos = nil
    end_pos = nil

    reader = Char::Reader.new(self)
    i = 0

    reader.each do
      if i == start
        start_pos = reader.pos
      elsif i == start + count
        end_pos = reader.pos
        i += 1
        break
      end
      i += 1
    end

    end_pos = reader.pos if i == start + count

    {start_pos.not_nil!, end_pos.not_nil!}
  end

  # Returns a new string built from *count* bytes starting at *start* byte.
  #
  # *start* can be negative to start counting
  # from the end of the string.
  # If *count* is bigger than the number of bytes from *start* to `#bytesize`,
  # only remaining bytes are returned.
  #
  # This method should be avoided,
  # unless the string is proven to be ASCII-only (for example `#ascii_only?`),
  # or the byte positions are known to be at character boundaries.
  # Otherwise, multi-byte characters may be split, leading to an invalid UTF-8 encoding.
  #
  # Raises `IndexError` if the *start* index is out of bounds.
  #
  # Raises `ArgumentError` if *count* is negative.
  #
  # ```
  # "hello".byte_slice(0, 2)   # => "he"
  # "hello".byte_slice(0, 100) # => "hello"
  # "hello".byte_slice(-2, 3)  # => "he"
  # "hello".byte_slice(-2, 5)  # => "he"
  # "hello".byte_slice(-2, 5)  # => "he"
  # "¥hello".byte_slice(0, 2)  # => "¥"
  # "¥hello".byte_slice(2, 2)  # => "he"
  # "¥hello".byte_slice(0, 1)  # => "\xC2" (invalid UTF-8 character)
  # "¥hello".byte_slice(1, 1)  # => "\xA5" (invalid UTF-8 character)
  # "¥hello".byte_slice(1, 2)  # => "\xA5h" (invalid UTF-8 character)
  # "hello".byte_slice(6, 2)   # raises IndexError
  # "hello".byte_slice(-6, 2)  # raises IndexError
  # "hello".byte_slice(0, -2)  # raises ArgumentError
  # ```
  def byte_slice(start : Int, count : Int) : String
    byte_slice?(start, count) || raise IndexError.new
  end

  # Returns a new string built from byte in *range*.
  #
  # Byte indices can be negative to start counting from the end of the string.
  # If the end index is bigger than `#bytesize`, only remaining bytes are returned.
  #
  # This method should be avoided,
  # unless the string is proven to be ASCII-only (for example `#ascii_only?`),
  # or the byte positions are known to be at character boundaries.
  # Otherwise, multi-byte characters may be split, leading to an invalid UTF-8 encoding.
  #
  # Raises `IndexError` if the *range* begin is out of bounds.
  #
  # ```
  # "hello".byte_slice(0..2)   # => "hel"
  # "hello".byte_slice(0..100) # => "hello"
  # "hello".byte_slice(-2..3)  # => "l"
  # "hello".byte_slice(-2..5)  # => "lo"
  # "¥hello".byte_slice(0...2) # => "¥"
  # "¥hello".byte_slice(2...4) # => "he"
  # "¥hello".byte_slice(0..0)  # => "\xC2" (invalid UTF-8 character)
  # "¥hello".byte_slice(1..1)  # => "\xA5" (invalid UTF-8 character)
  # "¥hello".byte_slice(1..2)  # => "\xA5h" (invalid UTF-8 character)
  # "hello".byte_slice(6..2)   # raises IndexError
  # "hello".byte_slice(-6..2)  # raises IndexError
  # ```
  def byte_slice(range : Range) : String
    byte_slice(*Indexable.range_to_index_and_count(range, bytesize) || raise IndexError.new)
  end

  # Like `byte_slice(Int, Int)` but returns `Nil` if the *start* index is out of bounds.
  #
  # Raises `ArgumentError` if *count* is negative.
  #
  # ```
  # "hello".byte_slice?(0, 2)   # => "he"
  # "hello".byte_slice?(0, 100) # => "hello"
  # "hello".byte_slice?(6, 2)   # => nil
  # "hello".byte_slice?(-6, 2)  # => nil
  # "hello".byte_slice?(0, -2)  # raises ArgumentError
  # ```
  def byte_slice?(start : Int, count : Int) : String | Nil
    start, count = Indexable.normalize_start_and_count(start, count, bytesize) { return nil }
    return "" if count == 0
    return self if count == bytesize

    single_byte_optimizable = single_byte_optimizable?

    String.new(count) do |buffer|
      buffer.copy_from(to_unsafe + start, count)
      slice_size = single_byte_optimizable ? count : 0
      {count, slice_size}
    end
  end

  # Like `byte_slice(Range)` but returns `Nil` if *range* begin is out of bounds.
  #
  # ```
  # "hello".byte_slice?(0..2)   # => "hel"
  # "hello".byte_slice?(0..100) # => "hello"
  # "hello".byte_slice?(6..8)   # => nil
  # "hello".byte_slice?(-6..2)  # => nil
  # ```
  def byte_slice?(range : Range) : String?
    byte_slice?(*Indexable.range_to_index_and_count(range, bytesize) || return nil)
  end

  # Returns a substring starting from the *start* byte.
  #
  # *start* can be negative to start counting
  # from the end of the string.
  #
  # This method should be avoided,
  # unless the string is proven to be ASCII-only (for example `#ascii_only?`),
  # or the byte positions are known to be at character boundaries.
  # Otherwise, multi-byte characters may be split, leading to an invalid UTF-8 encoding.
  #
  # Raises `IndexError` if *start* index is out of bounds.
  #
  # ```
  # "hello".byte_slice(0)  # => "hello"
  # "hello".byte_slice(2)  # => "llo"
  # "hello".byte_slice(-2) # => "lo"
  # "¥hello".byte_slice(2) # => "hello"
  # "¥hello".byte_slice(1) # => "\xA5hello" (invalid UTF-8 character)
  # "hello".byte_slice(6)  # raises IndexError
  # "hello".byte_slice(-6) # raises IndexError
  # ```
  def byte_slice(start : Int) : String
    count = bytesize - start
    raise IndexError.new if start > 0 && count < 0
    byte_slice start, count
  end

  # Returns a substring starting from the *start* byte.
  #
  # *start* can be negative to start counting
  # from the end of the string.
  #
  # This method should be avoided,
  # unless the string is proven to be ASCII-only (for example `#ascii_only?`),
  # or the byte positions are known to be at character boundaries.
  # Otherwise, multi-byte characters may be split, leading to an invalid UTF-8 encoding.
  #
  # Returns `nil` if *start* index is out of bounds.
  #
  # ```
  # "hello".byte_slice?(0)  # => "hello"
  # "hello".byte_slice?(2)  # => "llo"
  # "hello".byte_slice?(-2) # => "lo"
  # "¥hello".byte_slice?(2) # => "hello"
  # "¥hello".byte_slice?(1) # => "\xA5hello" (invalid UTF-8 character)
  # "hello".byte_slice?(6)  # => nil
  # "hello".byte_slice?(-6) # => nil
  # ```
  def byte_slice?(start : Int) : String?
    count = bytesize - start
    return nil if start > 0 && count < 0
    byte_slice? start, count
  end

  # Returns the codepoint of the character at the given *index*.
  #
  # Negative indices can be used to start counting from the end of the string.
  #
  # Raises `IndexError` if the *index* is out of bounds.
  #
  # See also: `Char#ord`.
  #
  # ```
  # "hello".codepoint_at(0)  # => 104
  # "hello".codepoint_at(-1) # => 111
  # "hello".codepoint_at(5)  # raises IndexError
  # ```
  def codepoint_at(index) : Int32
    char_at(index).ord
  end

  # Returns the byte at the given *index*.
  #
  # Raises `IndexError` if the *index* is out of bounds.
  #
  # ```
  # "¥hello".byte_at(0)  # => 194
  # "¥hello".byte_at(1)  # => 165
  # "¥hello".byte_at(2)  # => 104
  # "¥hello".byte_at(-1) # => 111
  # "¥hello".byte_at(6)  # => 111
  # "¥hello".byte_at(7)  # raises IndexError
  # ```
  def byte_at(index) : UInt8
    byte_at(index) { raise IndexError.new }
  end

  # Returns the byte at the given *index*, or `nil` if out of bounds.
  #
  # ```
  # "¥hello".byte_at?(0)  # => 194
  # "¥hello".byte_at?(1)  # => 165
  # "¥hello".byte_at?(2)  # => 104
  # "¥hello".byte_at?(-1) # => 111
  # "¥hello".byte_at?(6)  # => 111
  # "¥hello".byte_at?(7)  # => nil
  # ```
  def byte_at?(index) : UInt8 | Nil
    byte_at(index) { nil }
  end

  # Returns the byte at the given *index*, or yields if out of bounds.
  #
  # ```
  # "¥hello".byte_at(6) { "OUT OF BOUNDS" } # => 111
  # "¥hello".byte_at(7) { "OUT OF BOUNDS" } # => "OUT OF BOUNDS"
  # ```
  def byte_at(index, &)
    index += bytesize if index < 0
    if 0 <= index < bytesize
      to_unsafe[index]
    else
      yield
    end
  end

  # Returns the byte at the given *index* without bounds checking.
  @[Deprecated("Use `to_unsafe[index]` instead.")]
  def unsafe_byte_at(index : Int) : UInt8
    to_unsafe[index]
  end

  # Returns a new `String` with each uppercase letter replaced with its lowercase counterpart.
  #
  # ```
  # "hEllO".downcase # => "hello"
  # ```
  def downcase(options : Unicode::CaseOptions = :none) : String
    return self if empty?

    if single_byte_optimizable? && (options.none? || options.ascii?)
      return String.new(bytesize) do |buffer|
        bytesize.times do |i|
          byte = to_unsafe[i]
          buffer[i] = 'A'.ord <= byte <= 'Z'.ord ? byte + 32 : byte
        end
        {@bytesize, @length}
      end
    end

    String.build(bytesize) { |io| downcase io, options }
  end

  # Writes a downcased version of `self` to the given *io*.
  #
  # ```
  # io = IO::Memory.new
  # "hEllO".downcase io
  # io.to_s # => "hello"
  # ```
  def downcase(io : IO, options : Unicode::CaseOptions = :none) : Nil
    each_char do |char|
      char.downcase(options) do |res|
        io << res
      end
    end
  end

  # Returns a new `String` with each lowercase letter replaced with its uppercase counterpart.
  #
  # ```
  # "hEllO".upcase # => "HELLO"
  # ```
  def upcase(options : Unicode::CaseOptions = :none) : String
    return self if empty?

    if single_byte_optimizable? && (options.none? || options.ascii?)
      return String.new(bytesize) do |buffer|
        bytesize.times do |i|
          byte = to_unsafe[i]
          buffer[i] = 'a'.ord <= byte <= 'z'.ord ? byte - 32 : byte
        end
        {@bytesize, @length}
      end
    end

    String.build(bytesize) { |io| upcase io, options }
  end

  # Writes a upcased version of `self` to the given *io*.
  #
  # ```
  # io = IO::Memory.new
  # "hEllO".upcase io
  # io.to_s # => "HELLO"
  # ```
  def upcase(io : IO, options : Unicode::CaseOptions = :none) : Nil
    each_char do |char|
      char.upcase(options) do |res|
        io << res
      end
    end
  end

  # Returns a new `String` with the first letter converted to uppercase and every
  # subsequent letter converted to lowercase.
  #
  # ```
  # "hEllO".capitalize # => "Hello"
  # ```
  def capitalize(options : Unicode::CaseOptions = :none) : String
    return self if empty?

    if single_byte_optimizable? && (options.none? || options.ascii?)
      return String.new(bytesize) do |buffer|
        bytesize.times do |i|
          byte = to_unsafe[i]

          buffer[i] = if byte >= 0x80
                        byte
                      elsif i.zero?
                        byte.unsafe_chr.upcase.ord.to_u8!
                      else
                        byte.unsafe_chr.downcase.ord.to_u8!
                      end
        end
        {@bytesize, @length}
      end
    end

    String.build(bytesize) { |io| capitalize io, options }
  end

  # Writes a capitalized version of `self` to the given *io*.
  #
  # ```
  # io = IO::Memory.new
  # "hEllO".capitalize io
  # io.to_s # => "Hello"
  # ```
  def capitalize(io : IO, options : Unicode::CaseOptions = :none) : Nil
    each_char_with_index do |char, i|
      if i.zero?
        char.titlecase(options) { |c| io << c }
      else
        char.downcase(options) { |c| io << c }
      end
    end
  end

  # Returns a new `String` with the first letter after any space converted to uppercase and every other letter converted to lowercase.
  # Optionally, if *underscore_to_space* is `true`, underscores (`_`) will be converted to a space and the following letter converted to uppercase.
  #
  # ```
  # "hEllO tAb\tworld".titleize                   # => "Hello Tab\tWorld"
  # "  spaces before".titleize                    # => "  Spaces Before"
  # "x-men: the last stand".titleize              # => "X-men: The Last Stand"
  # "foo_bar".titleize                            # => "Foo_bar"
  # "foo_bar".titleize(underscore_to_space: true) # => "Foo Bar"
  # ```
  def titleize(options : Unicode::CaseOptions = :none, *, underscore_to_space : Bool = false) : String
    return self if empty?

    if single_byte_optimizable? && (options.none? || options.ascii?)
      upcase_next = true

      return String.new(bytesize) do |buffer|
        bytesize.times do |i|
          byte = to_unsafe[i]
          if byte < 0x80
            char = byte.unsafe_chr
            replaced_char, upcase_next = if upcase_next
                                           {char.upcase, false}
                                         elsif underscore_to_space && '_' == char
                                           {' ', true}
                                         else
                                           {char.downcase, char.ascii_whitespace?}
                                         end

            buffer[i] = replaced_char.ord.to_u8!
          else
            buffer[i] = byte
            upcase_next = false
          end
        end
        {@bytesize, @length}
      end
    end

    String.build(bytesize) { |io| titleize io, options, underscore_to_space: underscore_to_space }
  end

  # Writes a titleized version of `self` to the given *io*.
  # Optionally, if *underscore_to_space* is `true`, underscores (`_`) will be converted to a space and the following letter converted to uppercase.
  #
  # ```
  # io = IO::Memory.new
  # "x-men: the last stand".titleize io
  # io.to_s # => "X-men: The Last Stand"
  # ```
  def titleize(io : IO, options : Unicode::CaseOptions = :none, *, underscore_to_space : Bool = false) : Nil
    upcase_next = true

    each_char_with_index do |char, i|
      if upcase_next
        upcase_next = false
        char.titlecase(options) { |c| io << c }
      elsif underscore_to_space && '_' == char
        upcase_next = true
        io << ' '
      else
        upcase_next = char.whitespace?
        char.downcase(options) { |c| io << c }
      end
    end
  end

  # Returns the result of normalizing this `String` according to the given
  # [Unicode normalization form](https://unicode.org/reports/tr15/).
  #
  # ```
  # str = "\u{1E9B}\u{0323}"                # => "ẛ̣"
  # str.unicode_normalize.codepoints        # => [0x1E9B, 0x0323]
  # str.unicode_normalize(:nfd).codepoints  # => [0x017F, 0x0323, 0x0307]
  # str.unicode_normalize(:nfkc).codepoints # => [0x1E69]
  # str.unicode_normalize(:nfkd).codepoints # => [0x0073, 0x0323, 0x0307]
  # ```
  def unicode_normalize(form : Unicode::NormalizationForm = :nfc) : String
    return self if Unicode.quick_check_normalized(self, form).yes?
    String.build { |io| do_unicode_normalize(io, form) }
  end

  # Normalizes this `String` according to the given
  # [Unicode normalization form](https://unicode.org/reports/tr15/) and
  # writes the result to the given *io*.
  def unicode_normalize(io : IO, form : Unicode::NormalizationForm = :nfc) : Nil
    return io << self if Unicode.quick_check_normalized(self, form).yes?
    do_unicode_normalize(io, form)
  end

  private def do_unicode_normalize(io, form)
    # the maximum number of code points after any normalization is `3 * size` as
    # required by the Unicode standard; allow a single reallocation as the
    # majority of strings have only few characters that aren't normalized
    codepoints = Array(Int32).new((size * 3 + 1) // 2)

    each_char do |char|
      case form
      in .nfc?, .nfd?
        Unicode.canonical_decompose(codepoints, char)
      in .nfkc?, .nfkd?
        Unicode.compatibility_decompose(codepoints, char)
      end
    end

    Unicode.canonical_order!(codepoints)

    case form
    in .nfc?, .nfkc?
      Unicode.canonical_compose!(codepoints) { |char| io << char }
    in .nfd?, .nfkd?
      codepoints.each { |codepoint| io << codepoint.unsafe_chr }
    end
  end

  # Returns whether this `String` is in the given
  # [Unicode normalization form](https://unicode.org/reports/tr15/).
  #
  # ```
  # foo = "\u{00E0}"              # => "à"
  # foo.unicode_normalized?       # => true
  # foo.unicode_normalized?(:nfd) # => false
  #
  # bar = "\u{0061}\u{0300}"      # => "à"
  # bar.unicode_normalized?       # => false
  # bar.unicode_normalized?(:nfd) # => true
  # ```
  def unicode_normalized?(form : Unicode::NormalizationForm = :nfc) : Bool
    case Unicode.quick_check_normalized(self, form)
    in .yes?
      true
    in .no?
      false
    in .maybe?
      self == String.build { |io| do_unicode_normalize(io, form) }
    end
  end

  # Returns a new `String` with the last carriage return removed (that is, it
  # will remove \n, \r, and \r\n).
  #
  # ```
  # "string\r\n".chomp # => "string"
  # "string\n\r".chomp # => "string\n"
  # "string\n".chomp   # => "string"
  # "string".chomp     # => "string"
  # "x".chomp.chomp    # => "x"
  # ```
  def chomp : String
    return self if empty?

    case to_unsafe[bytesize - 1]
    when '\n'
      if bytesize > 1 && to_unsafe[bytesize - 2] === '\r'
        unsafe_byte_slice_string(0, bytesize - 2, @length > 0 ? @length - 2 : 0)
      else
        unsafe_byte_slice_string(0, bytesize - 1, @length > 0 ? @length - 1 : 0)
      end
    when '\r'
      unsafe_byte_slice_string(0, bytesize - 1, @length > 0 ? @length - 1 : 0)
    else
      self
    end
  end

  # Returns a new `String` with *suffix* removed from the end of the string.
  # If *suffix* is `'\n'` then `"\r\n"` is also removed if the string ends with it.
  #
  # ```
  # "hello".chomp('o') # => "hell"
  # "hello".chomp('a') # => "hello"
  # ```
  def chomp(suffix : Char) : String
    if suffix == '\n'
      chomp
    elsif ends_with?(suffix)
      unsafe_byte_slice_string(0, bytesize - suffix.bytesize)
    else
      self
    end
  end

  # Returns a new `String` with *suffix* removed from the end of the string.
  # If *suffix* is `"\n"` then `"\r\n"` is also removed if the string ends with it.
  #
  # ```
  # "hello".chomp("llo") # => "he"
  # "hello".chomp("ol")  # => "hello"
  # ```
  def chomp(suffix : String) : String
    if suffix.bytesize == 1
      chomp(suffix.to_unsafe[0].unsafe_chr)
    elsif ends_with?(suffix)
      unsafe_byte_slice_string(0, bytesize - suffix.bytesize)
    else
      self
    end
  end

  # Returns a new `String` with the first char removed from it.
  # Applying lchop to an empty string returns an empty string.
  #
  # ```
  # "hello".lchop # => "ello"
  # "".lchop      # => ""
  # ```
  def lchop : String
    lchop? || ""
  end

  # Returns a new `String` with *prefix* removed from the beginning of the string.
  #
  # ```
  # "hello".lchop('h')   # => "ello"
  # "hello".lchop('g')   # => "hello"
  # "hello".lchop("hel") # => "lo"
  # "hello".lchop("eh")  # => "hello"
  # ```
  def lchop(prefix : Char | String) : String
    lchop?(prefix) || self
  end

  # Returns a new `String` with the first char removed from it if possible, else returns `nil`.
  #
  # ```
  # "hello".lchop? # => "ello"
  # "".lchop?      # => nil
  # ```
  def lchop? : String?
    return if empty?

    if single_byte_optimizable?
      unsafe_byte_slice_string(1, bytesize - 1)
    else
      first_char_bytesize = char_bytesize_at(0)
      unsafe_byte_slice_string(first_char_bytesize, bytesize - first_char_bytesize)
    end
  end

  # Returns a new `String` with *prefix* removed from the beginning of the string if possible, else returns `nil`.
  #
  # ```
  # "hello".lchop?('h')   # => "ello"
  # "hello".lchop?('g')   # => nil
  # "hello".lchop?("hel") # => "lo"
  # "hello".lchop?("eh")  # => nil
  # ```
  def lchop?(prefix : Char | String) : String?
    if starts_with?(prefix)
      unsafe_byte_slice_string(prefix.bytesize, bytesize - prefix.bytesize)
    end
  end

  # Returns a new `String` with the last character removed.
  # Applying rchop to an empty string returns an empty string.
  #
  # ```
  # "string\r\n".rchop # => "string\r"
  # "string\n\r".rchop # => "string\n"
  # "string\n".rchop   # => "string"
  # "string".rchop     # => "strin"
  # "x".rchop.rchop    # => ""
  # ```
  def rchop : String
    rchop? || ""
  end

  # Returns a new `String` with *suffix* removed from the end of the string.
  #
  # ```
  # "string".rchop('g')   # => "strin"
  # "string".rchop('x')   # => "string"
  # "string".rchop("ing") # => "str"
  # "string".rchop("inx") # => "string"
  # ```
  def rchop(suffix : Char | String) : String
    rchop?(suffix) || self
  end

  # Returns a new `String` with the last character removed if possible, else returns `nil`.
  #
  # ```
  # "string\r\n".rchop? # => "string\r"
  # "string\n\r".rchop? # => "string\n"
  # "string\n".rchop?   # => "string"
  # "string".rchop?     # => "strin"
  # "".rchop?           # => nil
  # ```
  def rchop? : String?
    return if empty?

    unsafe_byte_slice_string(0, Char::Reader.new(at_end: self).pos, @length > 0 ? @length - 1 : 0)
  end

  # Returns a new `String` with *suffix* removed from the end of the string if possible, else returns `nil`.
  #
  # ```
  # "string".rchop?('g')   # => "strin"
  # "string".rchop?('x')   # => nil
  # "string".rchop?("ing") # => "str"
  # "string".rchop?("inx") # => nil
  # ```
  def rchop?(suffix : Char | String) : String?
    if ends_with?(suffix)
      unsafe_byte_slice_string(0, bytesize - suffix.bytesize)
    end
  end

  # Returns a slice of bytes containing this string encoded in the given encoding.
  #
  # The *invalid* argument can be:
  # * `nil`: an exception is raised on invalid byte sequences
  # * `:skip`: invalid byte sequences are ignored
  #
  # ```
  # "好".encode("GB2312") # => Bytes[186, 195]
  # "好".bytes            # => [229, 165, 189]
  # ```
  def encode(encoding : String, invalid : Symbol? = nil) : Bytes
    io = IO::Memory.new
    String.encode(to_slice, "UTF-8", encoding, io, invalid)
    io.to_slice
  end

  # :nodoc:
  def self.encode(slice, from, to, io, invalid)
    IO::EncodingOptions.check_invalid(invalid)

    inbuf_ptr = slice.to_unsafe
    inbytesleft = LibC::SizeT.new(slice.size)
    outbuf = uninitialized UInt8[1024]

    Crystal::Iconv.new(from, to, invalid) do |iconv|
      while inbytesleft > 0
        outbuf_ptr = outbuf.to_unsafe
        outbytesleft = LibC::SizeT.new(outbuf.size)
        err = iconv.convert(pointerof(inbuf_ptr), pointerof(inbytesleft), pointerof(outbuf_ptr), pointerof(outbytesleft))
        if err == Crystal::Iconv::ERROR
          iconv.handle_invalid(pointerof(inbuf_ptr), pointerof(inbytesleft))
        end
        io.write(outbuf.to_slice[0, outbuf.size - outbytesleft])
      end

      outbuf_ptr = outbuf.to_unsafe
      outbytesleft = LibC::SizeT.new(outbuf.size)
      err = iconv.convert(Pointer(UInt8*).null, Pointer(LibC::SizeT).null, pointerof(outbuf_ptr), pointerof(outbytesleft))
      if err == Crystal::Iconv::ERROR
        iconv.handle_invalid(pointerof(inbuf_ptr), pointerof(inbytesleft))
      end
      io.write(outbuf.to_slice[0, outbuf.size - outbytesleft])
    end
  end

  # Interprets this string as containing a sequence of hexadecimal values
  # and decodes it as a slice of bytes. Two consecutive bytes in the string
  # represent a byte in the returned slice.
  #
  # Raises `ArgumentError` if this string does not denote an hexstring.
  #
  # ```
  # "0102031aff".hexbytes  # => Bytes[1, 2, 3, 26, 255]
  # "1".hexbytes           # raises ArgumentError
  # "hello world".hexbytes # raises ArgumentError
  # ```
  def hexbytes : Bytes
    hexbytes? || raise(ArgumentError.new("#{self} is not a hexstring"))
  end

  # Interprets this string as containing a sequence of hexadecimal values
  # and decodes it as a slice of bytes. Two consecutive bytes in the string
  # represent a byte in the returned slice.
  #
  # Returns `nil` if this string does not denote an hexstring.
  #
  # ```
  # "0102031aff".hexbytes?  # => Bytes[1, 2, 3, 26, 255]
  # "1".hexbytes?           # => nil
  # "hello world".hexbytes? # => nil
  # ```
  def hexbytes? : Bytes?
    return unless bytesize.divisible_by?(2)

    bytes = Bytes.new(bytesize // 2)

    i = 0
    while i < bytesize
      high_nibble = to_unsafe[i].unsafe_chr.to_u8?(16)
      low_nibble = to_unsafe[i + 1].unsafe_chr.to_u8?(16)
      return unless high_nibble && low_nibble

      bytes[i // 2] = (high_nibble << 4) | low_nibble
      i += 2
    end

    bytes
  end

  # Returns a new `String` that results of inserting *other* in `self` at *index*.
  # Negative indices count from the end of the string, and insert **after**
  # the given index.
  #
  # Raises `IndexError` if the index is out of bounds.
  #
  # ```
  # "abcd".insert(0, 'X')  # => "Xabcd"
  # "abcd".insert(3, 'X')  # => "abcXd"
  # "abcd".insert(4, 'X')  # => "abcdX"
  # "abcd".insert(-3, 'X') # => "abXcd"
  # "abcd".insert(-1, 'X') # => "abcdX"
  #
  # "abcd".insert(5, 'X')  # raises IndexError
  # "abcd".insert(-6, 'X') # raises IndexError
  # ```
  def insert(index : Int, other : Char) : String
    index = index.to_i
    index += size + 1 if index < 0

    byte_index = char_index_to_byte_index(index)
    raise IndexError.new unless byte_index

    bytes, count = String.char_bytes_and_bytesize(other)

    new_bytesize = bytesize + count
    new_size = (single_byte_optimizable? && other.ascii?) ? new_bytesize : 0

    insert_impl(byte_index, bytes.to_unsafe, count, new_bytesize, new_size)
  end

  # Returns a new `String` that results of inserting *other* in `self` at *index*.
  # Negative indices count from the end of the string, and insert **after**
  # the given index.
  #
  # Raises `IndexError` if the index is out of bounds.
  #
  # ```
  # "abcd".insert(0, "FOO")  # => "FOOabcd"
  # "abcd".insert(3, "FOO")  # => "abcFOOd"
  # "abcd".insert(4, "FOO")  # => "abcdFOO"
  # "abcd".insert(-3, "FOO") # => "abFOOcd"
  # "abcd".insert(-1, "FOO") # => "abcdFOO"
  #
  # "abcd".insert(5, "FOO")  # raises IndexError
  # "abcd".insert(-6, "FOO") # raises IndexError
  # ```
  def insert(index : Int, other : String) : String
    index = index.to_i
    index += size + 1 if index < 0

    byte_index = char_index_to_byte_index(index)
    raise IndexError.new unless byte_index

    new_bytesize = bytesize + other.bytesize
    new_size = single_byte_optimizable? && other.single_byte_optimizable? ? new_bytesize : 0

    insert_impl(byte_index, other.to_unsafe, other.bytesize, new_bytesize, new_size)
  end

  private def insert_impl(byte_index, other, other_bytesize, new_bytesize, new_size)
    String.new(new_bytesize) do |buffer|
      buffer.copy_from(to_unsafe, byte_index)
      buffer += byte_index
      buffer.copy_from(other, other_bytesize)
      buffer += other_bytesize
      buffer.copy_from(to_unsafe + byte_index, bytesize - byte_index)
      {new_bytesize, new_size}
    end
  end

  # Returns a new `String` with leading and trailing whitespace removed.
  #
  # ```
  # "    hello    ".strip # => "hello"
  # "\tgoodbye\r\n".strip # => "goodbye"
  # ```
  def strip : String
    excess_left = calc_excess_left
    if excess_left == bytesize
      return ""
    end

    excess_right = calc_excess_right
    remove_excess(excess_left, excess_right)
  end

  # Returns a new string where leading and trailing occurrences of *char* are removed.
  #
  # ```
  # "aaabcdaaa".strip('a') # => "bcd"
  # ```
  def strip(char : Char) : String
    return self if empty?

    excess_left = calc_excess_left(char)
    if excess_left == bytesize
      return ""
    end

    excess_right = calc_excess_right(char)
    remove_excess(excess_left, excess_right)
  end

  # Returns a new string where leading and trailing occurrences of any char
  # in *chars* are removed. The *chars* argument is not a prefix or suffix;
  # rather; all combinations of its values are stripped.
  #
  # ```
  # "abcdefcba".strip("abc") # => "def"
  # ```
  def strip(chars : String) : String
    return self if empty?

    case chars.size
    when 0
      self
    when 1
      strip(chars[0])
    else
      excess_left = calc_excess_left(chars)
      if excess_left == bytesize
        return ""
      end

      excess_right = calc_excess_right(chars)
      remove_excess(excess_left, excess_right)
    end
  end

  # Returns a new string where leading and trailing characters for which
  # the block returns a *truthy* value are removed.
  #
  # ```
  # "bcadefcba".strip { |c| 'a' <= c <= 'c' } # => "def"
  # ```
  def strip(&block : Char -> _) : String
    return self if empty?

    excess_left = calc_excess_left { |c| yield c }
    if excess_left == bytesize
      return ""
    end

    excess_right = calc_excess_right { |c| yield c }
    remove_excess(excess_left, excess_right)
  end

  # Returns a new `String` with trailing whitespace removed.
  #
  # ```
  # "    hello    ".rstrip # => "    hello"
  # "\tgoodbye\r\n".rstrip # => "\tgoodbye"
  # ```
  def rstrip : String
    remove_excess_right(calc_excess_right)
  end

  # Returns a new string with trailing occurrences of *char* removed.
  #
  # ```
  # "aaabcdaaa".rstrip('a') # => "aaabcd"
  # ```
  def rstrip(char : Char) : String
    return self if empty?

    remove_excess_right(calc_excess_right(char))
  end

  # Returns a new string where trailing occurrences of any char
  # in *chars* are removed. The *chars* argument is not a suffix;
  # rather; all combinations of its values are stripped.
  #
  # ```
  # "abcdefcba".rstrip("abc") # => "abcdef"
  # ```
  def rstrip(chars : String) : String
    return self if empty?

    case chars.size
    when 0
      self
    when 1
      rstrip(chars[0])
    else
      remove_excess_right(calc_excess_right(chars))
    end
  end

  # Returns a new string where trailing characters for which
  # the block returns a *truthy* value are removed.
  #
  # ```
  # "bcadefcba".rstrip { |c| 'a' <= c <= 'c' } # => "bcadef"
  # ```
  def rstrip(&block : Char -> _) : String
    return self if empty?

    excess_right = calc_excess_right { |c| yield c }
    remove_excess_right(excess_right)
  end

  # Returns a new `String` with leading whitespace removed.
  #
  # ```
  # "    hello    ".lstrip # => "hello    "
  # "\tgoodbye\r\n".lstrip # => "goodbye\r\n"
  # ```
  def lstrip : String
    remove_excess_left(calc_excess_left)
  end

  # Returns a new string with leading occurrences of *char* removed.
  #
  # ```
  # "aaabcdaaa".lstrip('a') # => "bcdaaa"
  # ```
  def lstrip(char : Char) : String
    return self if empty?

    remove_excess_left(calc_excess_left(char))
  end

  # Returns a new string where leading occurrences of any char
  # in *chars* are removed. The *chars* argument is not a suffix;
  # rather; all combinations of its values are stripped.
  #
  # ```
  # "bcadefcba".lstrip("abc") # => "defcba"
  # ```
  def lstrip(chars : String) : String
    return self if empty?

    case chars.size
    when 0
      self
    when 1
      lstrip(chars[0])
    else
      remove_excess_left(calc_excess_left(chars))
    end
  end

  # Returns a new string where leading characters for which
  # the block returns a *truthy* value are removed.
  #
  # ```
  # "bcadefcba".lstrip { |c| 'a' <= c <= 'c' } # => "defcba"
  # ```
  def lstrip(&block : Char -> _) : String
    return self if empty?

    excess_left = calc_excess_left { |c| yield c }
    remove_excess_left(excess_left)
  end

  # :nodoc:
  def calc_excess_right
    if single_byte_optimizable?
      i = bytesize - 1
      while i >= 0 && to_unsafe[i].unsafe_chr.ascii_whitespace?
        i -= 1
      end
      bytesize - 1 - i
    else
      calc_excess_right &.whitespace?
    end
  end

  private def calc_excess_right(char : Char)
    calc_excess_right do |reader_char|
      char == reader_char
    end
  end

  private def calc_excess_right(chars : String)
    calc_excess_right do |reader_char|
      chars.includes?(reader_char)
    end
  end

  private def calc_excess_right(&block)
    byte_index = bytesize
    reader = Char::Reader.new(at_end: self)
    while (yield reader.current_char)
      byte_index = reader.pos
      if byte_index == 0
        return bytesize
      else
        reader.previous_char
      end
    end
    bytesize - byte_index
  end

  # :nodoc:
  def calc_excess_left
    if single_byte_optimizable?
      excess_left = 0
      # All strings end with '\0', and it's not a whitespace
      # so it's safe to access past 1 byte beyond the string data
      while to_unsafe[excess_left].unsafe_chr.ascii_whitespace?
        excess_left += 1
      end
      excess_left
    else
      calc_excess_left &.whitespace?
    end
  end

  private def calc_excess_left(char : Char)
    calc_excess_left do |reader_char|
      char == reader_char
    end
  end

  private def calc_excess_left(chars : String)
    calc_excess_left do |reader_char|
      chars.includes?(reader_char)
    end
  end

  private def calc_excess_left(&block)
    reader = Char::Reader.new(self)
    while (yield reader.current_char)
      reader.next_char
      return bytesize unless reader.has_next?
    end
    reader.pos
  end

  private def remove_excess(excess_left, excess_right)
    if excess_right == 0 && excess_left == 0
      self
    else
      unsafe_byte_slice_string(excess_left, bytesize - excess_right - excess_left)
    end
  end

  private def remove_excess_right(excess_right)
    case excess_right
    when 0
      self
    when bytesize
      ""
    else
      unsafe_byte_slice_string(0, bytesize - excess_right)
    end
  end

  private def remove_excess_left(excess_left)
    case excess_left
    when 0
      self
    when bytesize
      ""
    else
      unsafe_byte_slice_string(excess_left)
    end
  end

  # Returns a new string _tr_anslating characters using *from* and *to* as a
  # map. If *to* is shorter than *from*, the last character in *to* is used for
  # the rest. If *to* is empty, this acts like `String#delete`.
  #
  # ```
  # "aabbcc".tr("abc", "xyz") # => "xxyyzz"
  # "aabbcc".tr("abc", "x")   # => "xxxxxx"
  # "aabbcc".tr("a", "xyz")   # => "xxbbcc"
  # ```
  def tr(from : String, to : String) : String
    return delete(from) if to.empty?

    if from.bytesize == 1
      return gsub(from.to_unsafe[0].unsafe_chr, to[0])
    end

    multi = nil
    table = StaticArray(Int32, 256).new(-1)
    reader = Char::Reader.new(to)
    char = reader.current_char
    next_char = reader.next_char
    from.each_char do |ch|
      if ch.ord >= 256
        multi ||= {} of Char => Char
        multi[ch] = char
      else
        table[ch.ord] = char.ord
      end
      if next_char != Char::ZERO
        char = next_char
        reader.next_char
        next_char = reader.current_char
      end
    end

    String.build(bytesize) do |buffer|
      each_char do |ch|
        if ch.ord < 256
          if (a = table[ch.ord]) >= 0
            buffer << a.unsafe_chr
          else
            buffer << ch
          end
        else
          if a = multi.try &.[ch]?
            buffer << a
          else
            buffer << ch
          end
        end
      end
    end
  end

  # Returns a new `String` where the first character is yielded to the given
  # block and replaced by its return value.
  #
  # ```
  # "hello".sub { |char| char + 1 } # => "iello"
  # "hello".sub { "hi" }            # => "hiello"
  # ```
  def sub(&block : Char -> _) : String
    return self if empty?

    String.build(bytesize) do |buffer|
      reader = Char::Reader.new(self)
      buffer << yield reader.current_char
      reader.next_char
      buffer.write unsafe_byte_slice(reader.pos)
    end
  end

  # Returns a `String` where the first occurrence of *char* is replaced by
  # *replacement*.
  #
  # ```
  # "hello".sub('l', "lo")      # => "helolo"
  # "hello world".sub('o', 'a') # => "hella world"
  # ```
  def sub(char : Char, replacement) : String
    if includes?(char)
      String.build(bytesize) do |buffer|
        reader = Char::Reader.new(self)
        while reader.has_next?
          if reader.current_char == char
            buffer << replacement
            break
          else
            buffer << reader.current_char
          end
          reader.next_char
        end
        reader.next_char
        buffer.write unsafe_byte_slice(reader.pos)
      end
    else
      self
    end
  end

  # Returns a `String` where the first occurrence of *pattern* is replaced by
  # the block's return value.
  #
  # ```
  # "hello".sub(/./) { |s| s[0].ord.to_s + ' ' } # => "104 ello"
  # ```
  def sub(pattern : Regex, *, options : Regex::MatchOptions = Regex::MatchOptions::None, &) : String
    sub_append(pattern, options) do |str, match, buffer|
      $~ = match
      buffer << yield str, match
    end
  end

  # Returns a `String` where the first occurrence of *pattern* is replaced by
  # *replacement*
  #
  # ```
  # "hello".sub(/[aeiou]/, "*") # => "h*llo"
  # ```
  #
  # Within *replacement*, the special match variable `$~` will not refer to the
  # current match.
  #
  # If *backreferences* is `true` (the default value), *replacement* can include backreferences:
  #
  # ```
  # "hello".sub(/[aeiou]/, "(\\0)") # => "h(e)llo"
  # ```
  #
  # When substitution is performed, any backreferences found in *replacement*
  # will be replaced with the contents of the corresponding capture group in
  # *pattern*. Backreferences to capture groups that were not present in
  # *pattern* or that did not match will be skipped. See `Regex` for information
  # about capture groups.
  #
  # Backreferences are expressed in the form `"\\d"`, where *d* is a group
  # number, or `"\\k&lt;name>"` where *name* is the name of a named capture group.
  # A sequence of literal characters resembling a backreference can be
  # expressed by placing `"\\"` before the sequence.
  #
  # ```
  # "foo".sub(/o/, "x\\0x")                  # => "fxoxo"
  # "foofoo".sub(/(?<bar>oo)/, "|\\k<bar>|") # => "f|oo|foo"
  # "foo".sub(/o/, "\\\\0")                  # => "f\\0o"
  # ```
  #
  # Raises `ArgumentError` if an incomplete named back-reference is present in
  # *replacement*.
  #
  # Raises `IndexError` if a named group referenced in *replacement* is not present
  # in *pattern*.
  def sub(pattern : Regex, replacement, backreferences = true, *, options : Regex::MatchOptions = Regex::MatchOptions::None) : String
    if backreferences && replacement.is_a?(String) && replacement.has_back_references?
      sub_append(pattern, options) { |_, match, buffer| scan_backreferences(replacement, match, buffer) }
    else
      sub(pattern, options: options) { replacement }
    end
  end

  # Returns a `String` where the first occurrences of the given *pattern* is replaced
  # with the matching entry from the *hash* of replacements. If the first match
  # is not included in the *hash*, nothing is replaced.
  #
  # ```
  # "hello".sub(/(he|l|o)/, {"he": "ha", "l": "la"}) # => "hallo"
  # "hello".sub(/(he|l|o)/, {"l": "la"})             # => "hello"
  # ```
  def sub(pattern : Regex, hash : Hash(String, _) | NamedTuple, options : Regex::MatchOptions = Regex::MatchOptions::None) : String
    # FIXME: The options parameter should be a named-only parameter, but that breaks overload ordering (fixed with -Dpreview_overload_ordering).

    sub(pattern, options: options) do |match|
      if hash.has_key?(match)
        hash[match]
      else
        return self
      end
    end
  end

  # Returns a `String` where the first occurrences of the given *string* is replaced
  # with the given *replacement*.
  #
  # ```
  # "hello yellow".sub("ll", "dd") # => "heddo yellow"
  # ```
  def sub(string : String, replacement) : String
    sub(string) { replacement }
  end

  # Returns a `String` where the first occurrences of the given *string* is replaced
  # with the block's value.
  #
  # ```
  # "hello yellow".sub("ll") { "dd" } # => "heddo yellow"
  # ```
  def sub(string : String, &block) : String
    index = self.byte_index(string)
    return self unless index

    String.build(bytesize) do |buffer|
      buffer.write unsafe_byte_slice(0, index)
      buffer << yield string
      buffer.write unsafe_byte_slice(index + string.bytesize)
    end
  end

  # Returns a `String` where the first char in the string matching a key in the
  # given *hash* is replaced by the corresponding hash value.
  #
  # ```
  # "hello".sub({'a' => 'b', 'l' => 'd'}) # => "hedlo"
  # ```
  def sub(hash : Hash(Char, _)) : String
    return self if empty?

    String.build(bytesize) do |buffer|
      reader = Char::Reader.new(self)
      while reader.has_next?
        if hash.has_key?(reader.current_char)
          buffer << hash[reader.current_char]
          reader.next_char
          break
        else
          buffer << reader.current_char
          reader.next_char
        end
      end

      if reader.has_next?
        buffer << reader.current_char
        reader.next_char
        buffer.write unsafe_byte_slice(reader.pos)
      end
    end
  end

  private def sub_append(pattern : Regex, options : Regex::MatchOptions, &)
    match = pattern.match(self, options: options)
    return self unless match

    String.build(bytesize) do |buffer|
      buffer.write unsafe_byte_slice(0, match.byte_begin)
      str = match[0]
      $~ = match
      yield str, match, buffer
      buffer.write unsafe_byte_slice(match.byte_begin + str.bytesize)
    end
  end

  # Returns a new `String` with the character at the given index
  # replaced by *replacement*.
  #
  # ```
  # "hello".sub(1, 'a') # => "hallo"
  # ```
  def sub(index : Int, replacement : Char) : String
    sub_index(index.to_i, replacement) do |buffer|
      replacement.each_byte do |byte|
        buffer.value = byte
        buffer += 1
      end
      {buffer, @length}
    end
  end

  # Returns a new `String` with the character at the given index
  # replaced by *replacement*.
  #
  # ```
  # "hello".sub(1, "eee") # => "heeello"
  # ```
  def sub(index : Int, replacement : String) : String
    sub_index(index.to_i, replacement) do |buffer|
      buffer.copy_from(replacement.to_unsafe, replacement.bytesize)
      buffer += replacement.bytesize
      {buffer, self.size_known? && replacement.size_known? ? self.size + replacement.size - 1 : 0}
    end
  end

  private def sub_index(index, replacement, &)
    index += size if index < 0

    byte_index = char_index_to_byte_index(index)
    raise IndexError.new unless byte_index && byte_index < bytesize

    width = char_bytesize_at(byte_index)
    replacement_width = replacement.bytesize
    new_bytesize = bytesize - width + replacement_width

    String.new(new_bytesize) do |buffer|
      buffer.copy_from(to_unsafe, byte_index)
      buffer += byte_index
      buffer, length = yield buffer
      buffer.copy_from(to_unsafe + byte_index + width, bytesize - byte_index - width)
      {new_bytesize, length}
    end
  end

  # Returns a new `String` with characters at the given range
  # replaced by *replacement*.
  #
  # ```
  # "hello".sub(1..2, 'a') # => "halo"
  # ```
  def sub(range : Range, replacement : Char) : String
    sub_range(range, replacement) do |buffer, from_index, to_index|
      replacement.each_byte do |byte|
        buffer.value = byte
        buffer += 1
      end
      {buffer, single_byte_optimizable? ? bytesize - (to_index - from_index) + 1 : 0}
    end
  end

  # Returns a new `String` with characters at the given range
  # replaced by *replacement*.
  #
  # ```
  # "hello".sub(1..2, "eee") # => "heeelo"
  # ```
  def sub(range : Range, replacement : String) : String
    sub_range(range, replacement) do |buffer|
      buffer.copy_from(replacement.to_unsafe, replacement.bytesize)
      buffer += replacement.bytesize
      {buffer, 0}
    end
  end

  private def sub_range(range, replacement, &)
    start, count = Indexable.range_to_index_and_count(range, size) || raise IndexError.new

    from_index = char_index_to_byte_index(start)
    raise IndexError.new unless from_index

    if count == 0
      to_index = from_index
    else
      to_index = char_index_to_byte_index(start + count)
      raise IndexError.new unless to_index
    end

    new_bytesize = bytesize - (to_index - from_index) + replacement.bytesize

    String.new(new_bytesize) do |buffer|
      buffer.copy_from(to_unsafe, from_index)
      buffer += from_index
      buffer, length = yield buffer, from_index, to_index
      buffer.copy_from(to_unsafe + to_index, bytesize - to_index)
      {new_bytesize, length}
    end
  end

  # This returns `true` if this string has `'\\'` in it. It might not be a back reference,
  # but `'\\'` is probably used for back references, so this check is faster than parsing
  # the whole thing.
  def has_back_references?
    to_slice.index('\\'.ord.to_u8)
  end

  private def scan_backreferences(replacement, match_data, buffer)
    # We only append to the buffer in chunks, so if we have "foo\\1", we remember that
    # the chunk starts at index 0 (first_index) and when we find a "\\" we append
    # from 0 to 3 in a single write. When we find a "\\0" or "\\k<...>", we append
    # from the first_index, process the backreference, and then reset first_index
    # to the new index.
    first_index = 0
    index = 0

    while index = replacement.byte_index('\\'.ord.to_u8, index)
      index += 1
      chr = replacement.to_unsafe[index].unsafe_chr
      case chr
      when '\\'
        buffer.write(replacement.unsafe_byte_slice(first_index, index - first_index))
        index += 1
        first_index = index
      when '0'..'9'
        buffer.write(replacement.unsafe_byte_slice(first_index, index - 1 - first_index))
        buffer << match_data[chr - '0']?
        index += 1
        first_index = index
      when 'k'
        index += 1
        chr = replacement.to_unsafe[index].unsafe_chr
        next unless chr == '<'

        buffer.write(replacement.unsafe_byte_slice(first_index, index - 2 - first_index))

        index += 1
        start_index = index
        end_index = replacement.byte_index('>'.ord.to_u8, start_index)
        raise ArgumentError.new("Missing ending '>' for '\\\\k<...'") unless end_index

        name = replacement.byte_slice(start_index, end_index - start_index)
        capture = match_data[name]?
        raise IndexError.new("Undefined group name reference: #{name.inspect}") unless capture

        buffer << capture
        index = end_index + 1
        first_index = index
      end
    end

    if first_index != replacement.bytesize
      buffer.write(replacement.unsafe_byte_slice(first_index))
    end
  end

  # Returns a `String` where each character yielded to the given block
  # is replaced by the block's return value.
  #
  # ```
  # "hello".gsub { |char| char + 1 } # => "ifmmp"
  # "hello".gsub { "hi" }            # => "hihihihihi"
  # ```
  def gsub(&block : Char -> _) : String
    String.build(bytesize) do |buffer|
      each_char do |my_char|
        buffer << yield my_char
      end
    end
  end

  # Returns a `String` where all occurrences of the given char are
  # replaced with the given *replacement*.
  #
  # ```
  # "hello".gsub('l', "lo")      # => "heloloo"
  # "hello world".gsub('o', 'a') # => "hella warld"
  # ```
  def gsub(char : Char, replacement) : String
    if replacement.is_a?(String) && replacement.bytesize == 1
      return gsub(char, replacement.to_unsafe[0].unsafe_chr)
    end

    if includes?(char)
      if replacement.is_a?(Char) && char.ascii? && replacement.ascii?
        return gsub_ascii_char(char, replacement)
      end

      gsub { |my_char| char == my_char ? replacement : my_char }
    else
      self
    end
  end

  private def gsub_ascii_char(char, replacement)
    String.new(bytesize) do |buffer|
      to_slice.each_with_index do |byte, i|
        if char.ord == byte
          buffer[i] = replacement.ord.to_u8
        else
          buffer[i] = byte
        end
      end
      {bytesize, @length}
    end
  end

  # Returns a `String` where all occurrences of the given *pattern* are replaced
  # by the block value's value.
  #
  # ```
  # "hello".gsub(/./) { |s| s[0].ord.to_s + ' ' } # => "104 101 108 108 111 "
  # ```
  def gsub(pattern : Regex, *, options : Regex::MatchOptions = Regex::MatchOptions::None, &) : String
    gsub_append(pattern, options) do |string, match, buffer|
      $~ = match
      buffer << yield string, match
    end
  end

  # Returns a `String` where all occurrences of the given *pattern* are replaced
  # with the given *replacement*.
  #
  # ```
  # "hello".gsub(/[aeiou]/, '*') # => "h*ll*"
  # ```
  #
  # Within *replacement*, the special match variable `$~` will not refer to the
  # current match.
  #
  # If *backreferences* is `true` (the default value), *replacement* can include backreferences:
  #
  # ```
  # "hello".gsub(/[aeiou]/, "(\\0)") # => "h(e)ll(o)"
  # ```
  #
  # When substitution is performed, any backreferences found in *replacement*
  # will be replaced with the contents of the corresponding capture group in
  # *pattern*. Backreferences to capture groups that were not present in
  # *pattern* or that did not match will be skipped. See `Regex` for information
  # about capture groups.
  #
  # Backreferences are expressed in the form `"\\d"`, where *d* is a group
  # number, or `"\\k<name>"` where *name* is the name of a named capture group.
  # A sequence of literal characters resembling a backreference can be
  # expressed by placing `"\\"` before the sequence.
  #
  # ```
  # "foo".gsub(/o/, "x\\0x")                  # => "fxoxxox"
  # "foofoo".gsub(/(?<bar>oo)/, "|\\k<bar>|") # => "f|oo|f|oo|"
  # "foo".gsub(/o/, "\\\\0")                  # => "f\\0\\0"
  # ```
  #
  # Raises `ArgumentError` if an incomplete named back-reference is present in
  # *replacement*.
  #
  # Raises `IndexError` if a named group referenced in *replacement* is not present
  # in *pattern*.
  def gsub(pattern : Regex, replacement, backreferences = true, *, options : Regex::MatchOptions = Regex::MatchOptions::None) : String
    if backreferences && replacement.is_a?(String) && replacement.has_back_references?
      gsub_append(pattern, options) { |_, match, buffer| scan_backreferences(replacement, match, buffer) }
    else
      gsub(pattern, options: options) { replacement }
    end
  end

  # Returns a `String` where all occurrences of the given *pattern* are replaced
  # with a *hash* of replacements. If the *hash* contains the matched pattern,
  # the corresponding value is used as a replacement. Otherwise the match is
  # not included in the returned string.
  #
  # ```
  # # "he" and "l" are matched and replaced,
  # # but "o" is not and so is not included
  # "hello".gsub(/(he|l|o)/, {"he": "ha", "l": "la"}) # => "halala"
  # ```
  def gsub(pattern : Regex, hash : Hash(String, _) | NamedTuple, options : Regex::MatchOptions = Regex::MatchOptions::None) : String
    # FIXME: The options parameter should be a named-only parameter, but that breaks overload ordering (fixed with -Dpreview_overload_ordering).

    gsub(pattern, options: options) do |match|
      hash[match]?
    end
  end

  # Returns a `String` where all occurrences of the given *string* are replaced
  # with the given *replacement*.
  #
  # ```
  # "hello yellow".gsub("ll", "dd") # => "heddo yeddow"
  # ```
  def gsub(string : String, replacement) : String
    if string.bytesize == 1
      gsub(string.to_unsafe[0].unsafe_chr, replacement)
    else
      gsub(string) { replacement }
    end
  end

  # Returns a `String` where all occurrences of the given *string* are replaced
  # with the block's value.
  #
  # ```
  # "hello yellow".gsub("ll") { "dd" } # => "heddo yeddow"
  # ```
  def gsub(string : String, &block) : String
    byte_offset = 0
    index = self.byte_index(string, byte_offset)
    return self unless index

    last_byte_offset = 0

    String.build(bytesize) do |buffer|
      while index
        buffer.write unsafe_byte_slice(last_byte_offset, index - last_byte_offset)
        buffer << yield string

        if string.bytesize == 0
          # The pattern matched an empty result. We must advance one character to avoid stagnation.
          byte_offset = index + char_bytesize_at(byte_offset)
          last_byte_offset = index
        else
          byte_offset = index + string.bytesize
          last_byte_offset = byte_offset
        end

        index = self.byte_index(string, byte_offset)
      end

      if last_byte_offset < bytesize
        buffer.write unsafe_byte_slice(last_byte_offset)
      end
    end
  end

  # Returns a `String` where all chars in the given hash are replaced
  # by the corresponding *hash* values.
  #
  # ```
  # "hello".gsub({'e' => 'a', 'l' => 'd'}) # => "haddo"
  # ```
  def gsub(hash : Hash(Char, _)) : String
    gsub do |char|
      hash[char]? || char
    end
  end

  # Returns a `String` where all chars in the given named tuple are replaced
  # by the corresponding *tuple* values.
  #
  # ```
  # "hello".gsub({e: 'a', l: 'd'}) # => "haddo"
  # ```
  def gsub(tuple : NamedTuple) : String
    gsub do |char|
      tuple[char.to_s]? || char
    end
  end

  private def gsub_append(pattern : Regex, options : Regex::MatchOptions, &)
    byte_offset = 0
    match = pattern.match_at_byte_index(self, byte_offset, options: options)
    return self unless match

    last_byte_offset = 0

    String.build(bytesize) do |buffer|
      while match
        index = match.byte_begin(0)

        buffer.write unsafe_byte_slice(last_byte_offset, index - last_byte_offset)
        str = match[0]
        $~ = match
        yield str, match, buffer

        if str.bytesize == 0
          # The pattern matched an empty result. We must advance one character to avoid stagnation.
          byte_offset = index + char_bytesize_at(byte_offset)
          last_byte_offset = index
        else
          byte_offset = index + str.bytesize
          last_byte_offset = byte_offset
        end

        match = pattern.match_at_byte_index(self, byte_offset, options: options | Regex::MatchOptions::NO_UTF_CHECK)
      end

      if last_byte_offset < bytesize
        buffer.write unsafe_byte_slice(last_byte_offset)
      end
    end
  end

  # Yields each char in this string to the block,
  # returns the number of times the block returned a truthy value.
  #
  # ```
  # "aabbcc".count &.in?('a', 'b') # => 4
  # ```
  def count(&) : Int32
    count = 0
    each_char do |char|
      count += 1 if yield char
    end
    count
  end

  # Counts the occurrences of *other* char in this string.
  #
  # ```
  # "aabbcc".count('a') # => 2
  # ```
  def count(other : Char) : Int32
    count { |char| char == other }
  end

  # Sets should be a list of strings following the rules
  # described at `Char#in_set?`. Returns the number of characters
  # in this string that match the given set.
  def count(*sets) : Int32
    count(&.in_set?(*sets))
  end

  # Yields each char in this string to the block.
  # Returns a new `String` with all characters for which the
  # block returned a truthy value removed.
  #
  # ```
  # "aabbcc".delete &.in?('a', 'b') # => "cc"
  # ```
  def delete(&) : String
    String.build(bytesize) do |buffer|
      each_char do |char|
        buffer << char unless yield char
      end
    end
  end

  # Returns a new `String` with all occurrences of *char* removed.
  #
  # ```
  # "aabbcc".delete('b') # => "aacc"
  # ```
  def delete(char : Char) : String
    delete { |my_char| my_char == char }
  end

  # Sets should be a list of strings following the rules
  # described at `Char#in_set?`. Returns a new `String` with
  # all characters that match the given set removed.
  #
  # ```
  # "aabbccdd".delete("a-c") # => "dd"
  # ```
  def delete(*sets) : String
    delete(&.in_set?(*sets))
  end

  # Yields each char in this string to the block.
  # Returns a new `String`, that has all characters removed,
  # that were the same as the previous one and for which the given
  # block returned a truthy value.
  #
  # ```
  # "aaabbbccc".squeeze &.in?('a', 'b') # => "abccc"
  # "aaabbbccc".squeeze &.in?('a', 'c') # => "abbbc"
  # ```
  def squeeze(&) : String
    previous = nil
    String.build(bytesize) do |buffer|
      each_char do |char|
        buffer << char unless yield(char) && previous == char
        previous = char
      end
    end
  end

  # Returns a new `String`, with all runs of char replaced by one instance.
  #
  # ```
  # "a    bbb".squeeze(' ') # => "a bbb"
  # ```
  def squeeze(char : Char) : String
    squeeze { |my_char| char == my_char }
  end

  # Sets should be a list of strings following the rules
  # described at `Char#in_set?`. Returns a new `String` with all
  # runs of the same character replaced by one instance, if
  # they match the given set.
  #
  # If no set is given, all characters are matched.
  #
  # ```
  # "aaabbbcccddd".squeeze("b-d") # => "aaabcd"
  # "a       bbb".squeeze         # => "a b"
  # ```
  def squeeze(*sets : String) : String
    squeeze(&.in_set?(*sets))
  end

  # Returns a new `String`, that has all characters removed,
  # that were the same as the previous one.
  #
  # ```
  # "a       bbb".squeeze # => "a b"
  # ```
  def squeeze : String
    squeeze { true }
  end

  # Returns `true` if this is the empty string, `""`.
  def empty? : Bool
    bytesize == 0
  end

  # Returns `true` if this string consists exclusively of unicode whitespace.
  #
  # ```
  # "".blank?        # => true
  # "   ".blank?     # => true
  # "   a   ".blank? # => false
  # ```
  def blank? : Bool
    each_char do |char|
      return false unless char.whitespace?
    end
    true
  end

  # Returns `self` unless `#blank?` is `true` in which case it returns `nil`.
  #
  # ```
  # "a".presence         # => "a"
  # "".presence          # => nil
  # "   ".presence       # => nil
  # "    a    ".presence # => "    a    "
  # nil.presence         # => nil
  #
  # config = {"empty" => ""}
  # config["empty"]?.presence || "default"   # => "default"
  # config["missing"]?.presence || "default" # => "default"
  # ```
  #
  # See also: `Nil#presence`.
  def presence : self?
    self unless blank?
  end

  # Returns `true` if this string is equal to `*other*.
  #
  # Equality is checked byte-per-byte: if any byte is different from the corresponding
  # byte, it returns `false`. This means two strings containing invalid
  # UTF-8 byte sequences may compare unequal, even when they both produce the
  # Unicode replacement character at the same string indices.
  #
  # Thus equality is case-sensitive, as it is with the comparison operator (`#<=>`).
  # `#compare` offers a case-insensitive alternative.
  #
  # ```
  # "abcdef" == "abcde"   # => false
  # "abcdef" == "abcdef"  # => true
  # "abcdef" == "abcdefg" # => false
  # "abcdef" == "ABCDEF"  # => false
  #
  # "abcdef".compare("ABCDEF", case_insensitive: true) == 0 # => true
  # ```
  def ==(other : self) : Bool
    # Quick pointer comparison if both strings are identical references
    return true if same?(other)

    # If the bytesize differs, they cannot be equal
    return false if bytesize != other.bytesize

    # If the character size of both strings differs, they cannot be equal.
    # We need to exclude the case that @length of either string might not have
    # been calculated (indicated by `0`).
    return false if @length != other.@length && @length != 0 && other.@length != 0

    # All meta data matches up, so we need to compare byte-by-byte.
    to_unsafe.memcmp(other.to_unsafe, bytesize) == 0
  end

  # The comparison operator.
  #
  # Compares this string with *other*, returning `-1`, `0` or `1` depending on whether
  # this string is less, equal or greater than *other*.
  #
  # Comparison is done byte-per-byte: if a byte is less than the other corresponding
  # byte, `-1` is returned and so on. This means two strings containing invalid
  # UTF-8 byte sequences may compare unequal, even when they both produce the
  # Unicode replacement character at the same string indices.
  #
  # If the strings are of different lengths, and the strings are equal when compared
  # up to the shortest length, then the longer string is considered greater than
  # the shorter one.
  #
  # ```
  # "abcdef" <=> "abcde"   # => 1
  # "abcdef" <=> "abcdef"  # => 0
  # "abcdef" <=> "abcdefg" # => -1
  # "abcdef" <=> "ABCDEF"  # => 1
  # ```
  #
  # The comparison is case-sensitive. `#compare` is a case-insensitive alternative.
  def <=>(other : self) : Int32
    return 0 if same?(other)
    min_bytesize = Math.min(bytesize, other.bytesize)

    cmp = to_unsafe.memcmp(other.to_unsafe, min_bytesize)
    cmp == 0 ? (bytesize <=> other.bytesize) : cmp.sign
  end

  # Compares this string with *other*, returning `-1`, `0` or `1` depending on whether
  # this string is less, equal or greater than *other*, optionally in a *case_insensitive*
  # manner.
  #
  # Case-sensitive comparisons (`case_insensitive == false`) are equivalent to
  # `#<=>` and are always done byte-per-byte.
  #
  # ```
  # "abcdef".compare("abcde")   # => 1
  # "abcdef".compare("abcdef")  # => 0
  # "abcdef".compare("abcdefg") # => -1
  # "abcdef".compare("ABCDEF")  # => 1
  #
  # "abcdef".compare("ABCDEF", case_insensitive: true) # => 0
  # "abcdef".compare("ABCDEG", case_insensitive: true) # => -1
  #
  # "heIIo".compare("heııo", case_insensitive: true, options: Unicode::CaseOptions::Turkic) # => 0
  # "Baﬄe".compare("baffle", case_insensitive: true, options: Unicode::CaseOptions::Fold)   # => 0
  # ```
  #
  # Case-sensitive only comparison is provided by the comparison operator `#<=>`.
  def compare(other : String, case_insensitive = false, options : Unicode::CaseOptions = :none) : Int32
    return self <=> other unless case_insensitive

    if single_byte_optimizable? && other.single_byte_optimizable?
      position = 0

      while position < bytesize && position < other.bytesize
        byte1 = to_unsafe[position]
        byte2 = other.to_unsafe[position]

        # Lowercase both bytes
        # Also reject any invalid code units
        if 65 <= byte1 <= 90
          byte1 += 32
        elsif byte1 >= 0x80
          return 1 if byte2 < 0x80
        end

        if 65 <= byte2 <= 90
          byte2 += 32
        elsif byte2 >= 0x80
          return byte1 < 0x80 ? -1 : 0
        end

        comparison = byte1 <=> byte2
        return comparison unless comparison == 0

        position += 1
      end

      bytesize <=> other.bytesize
    else
      reader1 = Char::Reader.new(self)
      reader2 = Char::Reader.new(other)

      # 3 chars maximum for case folding; 2 held in temporary buffers
      chars1 = Crystal::SmallDeque(Char, 2).new
      chars2 = Crystal::SmallDeque(Char, 2).new

      while true
        lhs = chars1.shift do
          next unless reader1.has_next?
          lhs_ = nil
          reader1.current_char.downcase(options) do |char|
            if lhs_
              chars1 << char
            else
              lhs_ = char
            end
          end
          reader1.next_char
          lhs_
        end

        rhs = chars2.shift do
          next unless reader2.has_next?
          rhs_ = nil
          reader2.current_char.downcase(options) do |char|
            if rhs_
              chars2 << char
            else
              rhs_ = char
            end
          end
          reader2.next_char
          rhs_
        end

        case {lhs, rhs}
        in {Nil, Nil}
          return 0
        in {Nil, Char}
          return -1
        in {Char, Nil}
          return 1
        in {Char, Char}
          comparison = lhs <=> rhs
          return comparison.sign unless comparison == 0
        end
      end
    end
  end

  # Tests whether *str* matches *regex*.
  # If successful, it returns the position of the first match.
  # If unsuccessful, it returns `nil`.
  #
  # If the argument isn't a `Regex`, it returns `nil`.
  #
  # ```
  # "Haystack" =~ /ay/ # => 1
  # "Haystack" =~ /z/  # => nil
  #
  # "Haystack" =~ 45 # => nil
  # ```
  def =~(regex : Regex, *, options : Regex::MatchOptions = Regex::MatchOptions::None) : Int32?
    match = regex.match(self, options: options)
    $~ = match
    match.try &.begin(0)
  end

  # :ditto:
  def =~(other, *, options : Regex::MatchOptions = Regex::MatchOptions::None) : Nil
    nil
  end

  # Concatenates *str* and *other*.
  #
  # ```
  # "abc" + "def" # => "abcdef"
  # "abc" + 'd'   # => "abcd"
  # ```
  def +(other : self) : String
    return self if other.empty?
    return other if self.empty?

    size = bytesize + other.bytesize
    String.new(size) do |buffer|
      buffer.copy_from(to_unsafe, bytesize)
      (buffer + bytesize).copy_from(other.to_unsafe, other.bytesize)

      if size_known? && other.size_known?
        {size, @length + other.@length}
      else
        {size, 0}
      end
    end
  end

  # :ditto:
  def +(char : Char) : String
    bytes, count = String.char_bytes_and_bytesize(char)
    size = bytesize + count
    String.new(size) do |buffer|
      buffer.copy_from(to_unsafe, bytesize)
      (buffer + bytesize).copy_from(bytes.to_unsafe, count)

      if size_known?
        {size, @length + 1}
      else
        {size, 0}
      end
    end
  end

  # Makes a new `String` by adding *str* to itself *times* times.
  #
  # ```
  # "Developers! " * 4
  # # => "Developers! Developers! Developers! Developers! "
  # ```
  def *(times : Int) : String
    raise ArgumentError.new "Negative argument" if times < 0

    if times == 0 || bytesize == 0
      return ""
    elsif bytesize == 1
      return String.new(times) do |buffer|
        Slice.new(buffer, times).fill(to_unsafe[0])
        {times, times}
      end
    end

    total_bytesize = bytesize * times
    String.new(total_bytesize) do |buffer|
      buffer.copy_from(to_unsafe, bytesize)
      n = bytesize

      while n <= total_bytesize // 2
        (buffer + n).copy_from(buffer, n)
        n *= 2
      end

      (buffer + n).copy_from(buffer, total_bytesize - n)
      {total_bytesize, @length * times}
    end
  end

  # Prime number constant for Rabin-Karp algorithm `String#index`.
  private PRIME_RK = 2097169u32

  # Update rolling hash for Rabin-Karp algorithm `String#index`.
  private macro update_hash(n)
    {% for i in 1..n %}
      byte = head_pointer.value
      hash = hash &* PRIME_RK &+ pointer.value &- pow &* byte
      pointer += 1
      head_pointer += 1
    {% end %}
  end

  private macro update_simplehash(n)
    {% for i in 1..n %}
      hash = (hash << 8) | pointer.value
      pointer += 1
    {% end %}
  end

  # Returns the index of the _first_ occurrence of *search* in the string, or `nil` if not present.
  # If *offset* is present, it defines the position to start the search.
  #
  # ```
  # "Hello, World".index('o')    # => 4
  # "Hello, World".index('Z')    # => nil
  # "Hello, World".index("o", 5) # => 8
  # "Hello, World".index("H", 2) # => nil
  # "Hello, World".index(/[ ]+/) # => 6
  # "Hello, World".index(/\d+/)  # => nil
  # ```
  def index(search : Char, offset = 0) : Int32?
    # If it's ASCII we can delegate to slice
    if single_byte_optimizable?
      # With `single_byte_optimizable?` there are only ASCII characters and
      # invalid UTF-8 byte sequences, and we can reject anything that is neither
      # ASCII nor the replacement character.
      case search
      when .ascii?
        return to_slice.fast_index(search.ord.to_u8!, offset)
      when Char::REPLACEMENT
        offset.upto(bytesize - 1) do |i|
          if to_unsafe[i] >= 0x80
            return i.to_i
          end
        end
      end

      return nil
    end

    offset += size if offset < 0
    return nil if offset < 0

    each_char_with_index do |char, i|
      if i >= offset && char == search
        return i
      end
    end

    nil
  end

  private def index_short(hash_type, offset : Int32, pointer : UInt8*, end_pointer : UInt8*, search, &)
    search_hash = hash_type.new(0)
    hash = hash_type.new(0)
    mask = hash_type.new(0)

    search.each_byte do |b|
      search_hash = (search_hash << 8) | b
      hash = (hash << 8) | pointer.value
      mask = (mask << 8) | 0xff
      pointer += 1
    end

    while true
      return offset if (hash & mask) == search_hash

      char_bytesize = yield pointer
      return if pointer + char_bytesize > end_pointer
      case char_bytesize
      when 1 then update_simplehash 1
      when 2 then update_simplehash 2
      when 3 then update_simplehash 3
      else        update_simplehash 4
      end

      offset &+= 1
    end
  end

  # :ditto:
  def index(search : String, offset = 0)
    offset += size if offset < 0
    return if offset < 0

    return size < offset ? nil : offset if search.empty?
    return index(search[0], offset) if search.size == 1 && search.valid_encoding?

    # Rabin-Karp algorithm
    # https://en.wikipedia.org/wiki/Rabin%E2%80%93Karp_algorithm

    # Find start index with offset
    char_index = 0
    pointer = to_unsafe
    end_pointer = pointer + bytesize
    while char_index < offset && pointer < end_pointer
      char_bytesize = String.char_bytesize_at(pointer)
      pointer += char_bytesize
      char_index += 1
    end

    return if pointer + search.bytesize > end_pointer

    if search.bytesize <= 8
      search_bytesize = search.bytesize
      return index_short(UInt64, char_index, pointer, end_pointer, search) do |pointer|
        String.char_bytesize_at(pointer - search_bytesize)
      end
    end

    head_pointer = pointer
    search_hash = 0u32
    hash = 0u32

    # calculate a rolling hash of search text (needle) and this text (haystack)
    search.each_byte do |b|
      search_hash = search_hash &* PRIME_RK &+ b
      hash = hash &* PRIME_RK &+ pointer.value
      pointer += 1
    end
    pow = PRIME_RK &** search.bytesize

    while true
      # check hash equality and real string equality
      if hash == search_hash && head_pointer.memcmp(search.to_unsafe, search.bytesize) == 0
        return char_index
      end

      char_bytesize = String.char_bytesize_at(head_pointer)
      return if pointer + char_bytesize > end_pointer
      case char_bytesize
      when 1 then update_hash 1
      when 2 then update_hash 2
      when 3 then update_hash 3
      else        update_hash 4
      end

      char_index += 1
    end
  end

  # :ditto:
  def index(search : Regex, offset = 0, *, options : Regex::MatchOptions = Regex::MatchOptions::None) : Int32?
    offset += size if offset < 0
    return nil unless 0 <= offset <= size

    self.match(search, offset, options: options).try &.begin
  end

  # Returns the index of the _first_ occurrence of *search* in the string. If *offset* is present,
  # it defines the position to start the search.
  #
  # Raises `Enumerable::NotFoundError` if *search* does not occur in `self`.
  #
  # ```
  # "Hello, World".index!('o')    # => 4
  # "Hello, World".index!('Z')    # raises Enumerable::NotFoundError
  # "Hello, World".index!("o", 5) # => 8
  # "Hello, World".index!("H", 2) # raises Enumerable::NotFoundError
  # "Hello, World".index!(/[ ]+/) # => 6
  # "Hello, World".index!(/\d+/)  # raises Enumerable::NotFoundError
  # ```
  def index!(search, offset = 0) : Int32
    index(search, offset) || raise Enumerable::NotFoundError.new
  end

  # :ditto:
  def index!(search : Regex, offset = 0, *, options : Regex::MatchOptions = Regex::MatchOptions::None) : Int32
    index(search, offset, options: options) || raise Enumerable::NotFoundError.new
  end

  # Returns the index of the _last_ appearance of *search* in the string,
  # If *offset* is present, it defines the position to _end_ the search
  # (characters beyond this point are ignored).
  #
  # ```
  # "Hello, World".rindex('o')    # => 8
  # "Hello, World".rindex('Z')    # => nil
  # "Hello, World".rindex('o', 5) # => 4
  # "Hello, World".rindex('W', 2) # => nil
  # ```
  def rindex(search : Char, offset = size - 1)
    # If it's ASCII we can delegate to slice
    if single_byte_optimizable?
      # With `single_byte_optimizable?` there are only ASCII characters and
      # invalid UTF-8 byte sequences, and we can reject anything that is neither
      # ASCII nor the replacement character.
      case search
      when .ascii?
        return to_slice.rindex(search.ord.to_u8!, offset)
      when Char::REPLACEMENT
        offset.downto(0) do |i|
          if to_unsafe[i] >= 0x80
            return i.to_i
          end
        end
      end

      return nil
    end

    offset += size if offset < 0
    return nil if offset < 0

    if offset == size - 1
      reader = Char::Reader.new(at_end: self)
    else
      byte_index = char_index_to_byte_index(offset)
      raise IndexError.new unless byte_index
      reader = Char::Reader.new(self, pos: byte_index)
    end

    while true
      if reader.current_char == search
        return offset
      elsif reader.has_previous?
        reader.previous_char
        offset -= 1
      else
        return nil
      end
    end
  end

  # Returns the index of the _last_ appearance of *search* in the string,
  # If *offset* is present, it defines the position to _end_ the search
  # (characters beyond this point are ignored).
  #
  # ```
  # "Hello, World".rindex("orld")    # => 8
  # "Hello, World".rindex("snorlax") # => nil
  # "Hello, World".rindex("o", 5)    # => 4
  # "Hello, World".rindex("W", 2)    # => nil
  # ```
  def rindex(search : String, offset = size - search.size) : Int32?
    offset += size if offset < 0
    return if offset < 0

    # Rabin-Karp algorithm
    # https://en.wikipedia.org/wiki/Rabin%E2%80%93Karp_algorithm

    # calculate a rolling hash of search text (needle)
    search_hash = 0u32
    search.to_slice.reverse_each do |b|
      search_hash = search_hash &* PRIME_RK &+ b
    end
    pow = PRIME_RK &** search.bytesize

    hash = 0u32
    char_index = size

    begin_pointer = to_unsafe
    pointer = begin_pointer + bytesize
    tail_pointer = pointer
    hash_begin_pointer = pointer - search.bytesize

    return if hash_begin_pointer < begin_pointer

    # calculate a rolling hash of this text (haystack)
    while hash_begin_pointer < pointer
      pointer -= 1
      byte = pointer.value
      char_index -= 1 if (byte & 0xC0) != 0x80

      hash = hash &* PRIME_RK &+ byte
    end

    while true
      # check hash equality and real string equality
      if hash == search_hash && char_index <= offset &&
         pointer.memcmp(search.to_unsafe, search.bytesize) == 0
        return char_index
      end

      return if begin_pointer == pointer

      pointer -= 1
      tail_pointer -= 1
      byte = pointer.value
      char_index -= 1 if (byte & 0xC0) != 0x80

      # update a rolling hash of this text (haystack)
      hash = hash &* PRIME_RK &+ byte &- pow &* tail_pointer.value
    end
  end

  # Returns the index of the _last_ appearance of *search* in the string,
  # If *offset* is present, it defines the position to _end_ the search
  # (characters beyond this point are ignored).
  #
  # ```
  # "Hello, World".rindex(/world/i) # => 7
  # "Hello, World".rindex(/world/)  # => nil
  # "Hello, World".rindex(/o/, 5)   # => 4
  # "Hello, World".rindex(/W/, 2)   # => nil
  # ```
  def rindex(search : Regex, offset = size, *, options : Regex::MatchOptions = Regex::MatchOptions::None) : Int32?
    offset += size if offset < 0
    return nil unless 0 <= offset <= size

    match_result = nil
    scan(search, options: options) do |match_data|
      break if (index = match_data.begin) && index > offset
      match_result = match_data
    end

    match_result.try &.begin
  end

  # Returns the index of the _last_ appearance of *search* in the string,
  # If *offset* is present, it defines the position to _end_ the search
  # (characters beyond this point are ignored).
  # Raises `Enumerable::NotFoundError` if *search* does not occur in `self`.
  #
  # ```
  # "Hello, World".rindex!('o')    # => 8
  # "Hello, World".rindex!('Z')    # raises Enumerable::NotFoundError
  # "Hello, World".rindex!('o', 5) # => 4
  # "Hello, World".rindex!('W', 2) # raises Enumerable::NotFoundError
  # ```
  def rindex!(search : Char, offset = size - 1) : Int32
    rindex(search, offset) || raise Enumerable::NotFoundError.new
  end

  # Returns the index of the _last_ appearance of *search* in the string,
  # If *offset* is present, it defines the position to _end_ the search
  # (characters beyond this point are ignored).
  # Raises `Enumerable::NotFoundError` if *search* does not occur in `self`.
  #
  # ```
  # "Hello, World".rindex!("orld")    # => 8
  # "Hello, World".rindex!("snorlax") # raises Enumerable::NotFoundError
  # "Hello, World".rindex!("o", 5)    # => 4
  # "Hello, World".rindex!("W", 2)    # raises Enumerable::NotFoundError
  # ```
  def rindex!(search : String, offset = size - search.size) : Int32
    rindex(search, offset) || raise Enumerable::NotFoundError.new
  end

  # Returns the index of the _last_ appearance of *search* in the string,
  # If *offset* is present, it defines the position to _end_ the search
  # (characters beyond this point are ignored).
  # Raises `Enumerable::NotFoundError` if *search* does not occur in `self`.
  #
  # ```
  # "Hello, World".rindex!(/world/i) # => 7
  # "Hello, World".rindex!(/world/)  # raises Enumerable::NotFoundError
  # "Hello, World".rindex!(/o/, 5)   # => 4
  # "Hello, World".rindex!(/W/, 2)   # raises Enumerable::NotFoundError
  # ```
  def rindex!(search : Regex, offset = size, *, options : Regex::MatchOptions = Regex::MatchOptions::None) : Int32
    rindex(search, offset, options: options) || raise Enumerable::NotFoundError.new
  end

  # Searches separator or pattern (`Regex`) in the string, and returns
  # a `Tuple` with the part before it, the match, and the part after it.
  # If it is not found, returns str followed by two empty strings.
  #
  # ```
  # "hello".partition("l") # => {"he", "l", "lo"}
  # "hello".partition("x") # => {"hello", "", ""}
  # ```
  def partition(search : (Char | String)) : Tuple(String, String, String)
    pre = mid = post = ""
    search_size = search.is_a?(Char) ? 1 : search.size
    case pos = self.index(search)
    when .nil?
      pre = self
    when 0
      mid = search.to_s
      post = self[(pos + search_size)..-1]
    else
      pre = self[0..(pos - 1)]
      mid = search.to_s
      post = self[(pos + search_size)..-1]
    end
    {pre, mid, post}
  end

  # :ditto:
  def partition(search : Regex, *, options : Regex::MatchOptions = Regex::MatchOptions::None) : Tuple(String, String, String)
    pre = mid = post = ""
    case m = self.match(search, options: options)
    when .nil?
      pre = self
    else
      pre = m.pre_match
      mid = m[0]
      post = m.post_match
    end
    {pre, mid, post}
  end

  # Searches separator or pattern (`Regex`) in the string from the end of the string,
  # and returns a `Tuple` with the part before it, the match, and the part after it.
  # If it is not found, returns two empty strings and str.
  #
  # ```
  # "hello".rpartition("l")  # => {"hel", "l", "o"}
  # "hello".rpartition("x")  # => {"", "", "hello"}
  # "hello".rpartition(/.l/) # => {"he", "ll", "o"}
  # ```
  def rpartition(search : (Char | String)) : Tuple(String, String, String)
    pos = self.rindex(search)
    search_size = search.is_a?(Char) ? 1 : search.size

    pre = mid = post = ""

    case pos
    when .nil?
      post = self
    when 0
      mid = search.to_s
      post = self[(pos + search_size)..-1]
    else
      pre = self[0..(pos - 1)]
      mid = search.to_s
      post = self[(pos + search_size)..-1]
    end
    {pre, mid, post}
  end

  # :ditto:
  def rpartition(search : Regex, *, options : Regex::MatchOptions = Regex::MatchOptions::None) : Tuple(String, String, String)
    match_result = nil
    pos = self.size - 1

    while pos >= 0
      self[pos..-1].scan(search, options: options) do |m|
        match_result = m
      end
      break unless match_result.nil?
      pos -= 1
    end

    pre = mid = post = ""

    case
    when match_result.nil?
      post = self
    when pos == 0
      mid = match_result[0]
      post = self[match_result[0].size..-1]
    else
      pre = self[0..pos - 1]
      mid = match_result.not_nil![0]
      post = self[pos + match_result.not_nil![0].size..-1]
    end
    {pre, mid, post}
  end

  # Returns the index of the _first_ occurrence of *byte* in the string, or `nil` if not present.
  # If *offset* is present, it defines the position to start the search.
  #
  # Negative *offset* can be used to start the search from the end of the string.
  #
  # ```
  # "Hello, World".byte_index(0x6f)             # => 4
  # "Hello, World".byte_index(0x5a)             # => nil
  # "Hello, World".byte_index(0x6f, 5)          # => 8
  # "💣".byte_index(0xA3)                        # => 3
  # "Dizzy Miss Lizzy".byte_index('z'.ord)      # => 2
  # "Dizzy Miss Lizzy".byte_index('z'.ord, 3)   # => 3
  # "Dizzy Miss Lizzy".byte_index('z'.ord, -4)  # => 13
  # "Dizzy Miss Lizzy".byte_index('z'.ord, -17) # => nil
  # ```
  def byte_index(byte : Int, offset : Int32 = 0) : Int32?
    offset += bytesize if offset < 0
    return if offset < 0

    to_slice.fast_index(byte.to_u8, offset)
  end

  # Returns the index of the _first_ occurrence of *char* in the string, or `nil` if not present.
  # If *offset* is present, it defines the position to start the search.
  #
  # Negative *offset* can be used to start the search from the end of the string.
  #
  # ```
  # "Hello, World".byte_index('o')          # => 4
  # "Hello, World".byte_index('Z')          # => nil
  # "Hello, World".byte_index('o', 5)       # => 8
  # "Hi, 💣".byte_index('💣')                 # => 4
  # "Dizzy Miss Lizzy".byte_index('z')      # => 2
  # "Dizzy Miss Lizzy".byte_index('z', 3)   # => 3
  # "Dizzy Miss Lizzy".byte_index('z', -4)  # => 13
  # "Dizzy Miss Lizzy".byte_index('z', -17) # => nil
  # ```
  def byte_index(char search : Char, offset = 0) : Int32?
    return byte_index(search.ord, offset) if search.ascii?

    offset += bytesize if offset < 0
    return if offset < 0
    return if offset + search.bytesize > bytesize

    pointer = to_unsafe + offset
    end_pointer = to_unsafe + bytesize
    index_short(UInt32, offset, pointer, end_pointer, search) { 1 }
  end

  # Returns the byte index of *search* in the string, or `nil` if the string is not present.
  # If *offset* is present, it defines the position to start the search.
  #
  # Negative *offset* can be used to start the search from the end of the string.
  #
  # ```
  # "¥hello".byte_index("hello")              # => 2
  # "hello".byte_index("world")               # => nil
  # "Dizzy Miss Lizzy".byte_index("izzy")     # => 1
  # "Dizzy Miss Lizzy".byte_index("izzy", 2)  # => 12
  # "Dizzy Miss Lizzy".byte_index("izzy", -4) # => 12
  # "Dizzy Miss Lizzy".byte_index("izzy", -3) # => nil
  # ```
  def byte_index(search : String, offset = 0) : Int32?
    offset += bytesize if offset < 0
    return if offset < 0

    return bytesize < offset ? nil : offset if search.empty?
    return byte_index(search.to_unsafe[0], offset) if search.bytesize == 1

    # Rabin-Karp algorithm
    # https://en.wikipedia.org/wiki/Rabin%E2%80%93Karp_algorithm

    pointer = to_unsafe + offset
    end_pointer = to_unsafe + bytesize
    return if pointer + search.bytesize > end_pointer

    search_hash = 0u32
    hash = 0u32

    if search.bytesize <= 8
      return index_short(UInt64, offset, pointer, end_pointer, search) { 1 }
    end

    head_pointer = pointer

    # calculate a rolling hash of search text (needle) and this text (haystack)
    search.each_byte do |b|
      search_hash = search_hash &* PRIME_RK &+ b
      hash = hash &* PRIME_RK &+ pointer.value
      pointer += 1
    end
    pow = PRIME_RK &** search.bytesize

    while true
      # check hash equality and real string equality
      if hash == search_hash && head_pointer.memcmp(search.to_unsafe, search.bytesize) == 0
        return offset
      end

      return if pointer >= end_pointer

      # update a rolling hash of this text (haystack)
      update_hash 1
      offset += 1
    end

    nil
  end

  # Returns the byte index of the regex *pattern* in the string, or `nil` if the pattern does not find a match.
  # If *offset* is present, it defines the position to start the search.
  #
  # Negative *offset* can be used to start the search from the end of the string.
  #
  # ```
  # "hello world".byte_index(/o/)             # => 4
  # "hello world".byte_index(/o/, offset: 4)  # => 4
  # "hello world".byte_index(/o/, offset: 5)  # => 7
  # "hello world".byte_index(/o/, offset: -1) # => nil
  # "hello world".byte_index(/y/)             # => nil
  # ```
  def byte_index(pattern : Regex, offset = 0, options : Regex::MatchOptions = Regex::MatchOptions::None) : Int32?
    offset += bytesize if offset < 0
    return if offset < 0

    if match = pattern.match_at_byte_index(self, offset, options: options)
      match.byte_begin
    end
  end

  # Returns the byte index of a char index, or `nil` if out of bounds.
  #
  # It is valid to pass `#size` to *index*, and in this case the answer
  # will be the bytesize of this string.
  #
  # ```
  # "hello".char_index_to_byte_index(1) # => 1
  # "hello".char_index_to_byte_index(5) # => 5
  # "こんにちは".char_index_to_byte_index(1) # => 3
  # "こんにちは".char_index_to_byte_index(5) # => 15
  # ```
  def char_index_to_byte_index(index)
    if single_byte_optimizable?
      return 0 <= index <= bytesize ? index : nil
    end

    size = each_byte_index_and_char_index do |byte_index, char_index|
      return byte_index if index == char_index
    end
    return @bytesize if index == size
    nil
  end

  # Returns the char index of a byte index, or `nil` if out of bounds.
  #
  # It is valid to pass `#bytesize` to *index*, and in this case the answer
  # will be the size of this string.
  def byte_index_to_char_index(index) : Int32?
    if single_byte_optimizable?
      return 0 <= index <= bytesize ? index : nil
    end

    size = each_byte_index_and_char_index do |byte_index, char_index|
      return char_index if index == byte_index
    end
    return size if index == @bytesize
    nil
  end

  # Returns `true` if the string contains *search*.
  #
  # ```
  # "Team".includes?('i')            # => false
  # "Dysfunctional".includes?("fun") # => true
  # ```
  def includes?(search : Char | String) : Bool
    !!index(search)
  end

  # Makes an array by splitting the string on any amount of ASCII whitespace
  # characters (and removing that whitespace).
  #
  # If *limit* is present, up to *limit* new strings will be created, with the
  # entire remainder added to the last string.
  #
  # ```
  # old_pond = "
  #   Old pond
  #   a frog leaps in
  #   water's sound
  # "
  # old_pond.split    # => ["Old", "pond", "a", "frog", "leaps", "in", "water's", "sound"]
  # old_pond.split(3) # => ["Old", "pond", "a frog leaps in\n  water's sound\n"]
  # ```
  def split(limit : Int32? = nil) : Array(String)
    ary = Array(String).new
    split(limit) do |string|
      ary << string
    end
    ary
  end

  # Splits the string after any amount of ASCII whitespace characters and yields
  # each non-whitespace part to a block.
  #
  # If *limit* is present, up to *limit* new strings will be created, with the
  # entire remainder added to the last string.
  #
  # ```
  # ary = [] of String
  # old_pond = "
  #   Old pond
  #   a frog leaps in
  #   water's sound
  # "
  #
  # old_pond.split { |s| ary << s }
  # ary # => ["Old", "pond", "a", "frog", "leaps", "in", "water's", "sound"]
  # ary.clear
  #
  # old_pond.split(3) { |s| ary << s }
  # ary # => ["Old", "pond", "a frog leaps in\n  water's sound\n"]
  # ```
  def split(limit : Int32? = nil, &block : String -> _)
    if limit && limit <= 1
      yield self
      return
    end

    if single_byte_optimizable?
      split_single_byte(limit) do |piece|
        yield piece
      end
      return
    end

    yielded = 0
    start_pos = 0
    piece_size = 0
    looking_for_space = false

    reader = Char::Reader.new(self)
    reader.each do |char|
      if char.whitespace?
        if looking_for_space
          piece_bytesize = reader.pos - start_pos
          yield String.new(to_unsafe + start_pos, piece_bytesize, piece_size)
          yielded += 1
          looking_for_space = false
        end
      else
        if looking_for_space
          piece_size += 1
        else
          start_pos = reader.pos
          piece_size = 1
          looking_for_space = true

          break if limit && yielded + 1 == limit
        end
      end
    end

    if looking_for_space
      piece_bytesize = bytesize - start_pos
      yield String.new(to_unsafe + start_pos, piece_bytesize, piece_size)
    end
  end

  private def split_single_byte(limit, &)
    yielded = 0
    index = 0
    i = 0
    looking_for_space = false
    limit_reached = false
    while i < bytesize
      if looking_for_space
        while i < bytesize
          c = to_unsafe[i]
          i += 1
          if c.unsafe_chr.ascii_whitespace?
            piece_bytesize = i - 1 - index
            yield String.new(to_unsafe + index, piece_bytesize, piece_bytesize)
            yielded += 1
            looking_for_space = false

            if limit && yielded + 1 == limit
              limit_reached = true
            end

            break
          end
        end
      else
        while i < bytesize
          c = to_unsafe[i]
          i += 1
          unless c.unsafe_chr.ascii_whitespace?
            index = i - 1
            looking_for_space = true
            break
          end
        end

        break if limit_reached
      end
    end
    if looking_for_space
      piece_bytesize = bytesize - index
      yield String.new(to_unsafe + index, piece_bytesize, piece_bytesize)
    end
  end

  # Makes an `Array` by splitting the string on the given character *separator*
  # (and removing that character).
  #
  # If *limit* is present, up to *limit* new strings will be created,
  # with the entire remainder added to the last string.
  #
  # If *remove_empty* is `true`, any empty strings are removed from the result.
  #
  # ```
  # "foo,,bar,baz".split(',')                     # => ["foo", "", "bar", "baz"]
  # "foo,,bar,baz".split(',', remove_empty: true) # => ["foo", "bar", "baz"]
  # "foo,bar,baz".split(',', 2)                   # => ["foo", "bar,baz"]
  # ```
  def split(separator : Char, limit = nil, *, remove_empty = false) : Array(String)
    ary = Array(String).new
    split(separator, limit, remove_empty: remove_empty) do |string|
      ary << string
    end
    ary
  end

  # Splits the string after each character *separator* and yields each part to a block.
  #
  # If *limit* is present, up to *limit* new strings will be created,
  # with the entire remainder added to the last string.
  #
  # If *remove_empty* is `true`, any empty strings are not yielded.
  #
  # ```
  # ary = [] of String
  #
  # "foo,,bar,baz".split(',') { |string| ary << string }
  # ary # => ["foo", "", "bar", "baz"]
  # ary.clear
  #
  # "foo,,bar,baz".split(',', remove_empty: true) { |string| ary << string }
  # ary # => ["foo", "bar", "baz"]
  # ary.clear
  #
  # "foo,bar,baz".split(',', 2) { |string| ary << string }
  # ary # => ["foo", "bar,baz"]
  # ```
  def split(separator : Char, limit = nil, *, remove_empty = false, &block : String -> _)
    if empty?
      yield "" unless remove_empty
      return
    end

    if limit && limit <= 1
      yield self
      return
    end

    yielded = 0
    byte_offset = 0

    reader = Char::Reader.new(self)
    reader.each do |char|
      if char == separator
        piece_bytesize = reader.pos - byte_offset
        yield String.new(to_unsafe + byte_offset, piece_bytesize) unless remove_empty && piece_bytesize == 0
        yielded += 1
        byte_offset = reader.pos + reader.current_char_width
        break if limit && yielded + 1 == limit
      end
    end

    piece_bytesize = bytesize - byte_offset
    return if remove_empty && piece_bytesize == 0
    yield String.new(to_unsafe + byte_offset, piece_bytesize)
  end

  # Makes an `Array` by splitting the string on *separator* (and removing instances of *separator*).
  #
  # If *limit* is present, the array will be limited to *limit* items and
  # the final item will contain the remainder of the string.
  #
  # If *separator* is an empty string (`""`), the string will be separated into one-character strings.
  #
  # If *remove_empty* is `true`, any empty strings are removed from the result.
  #
  # ```
  # long_river_name = "Mississippi"
  # long_river_name.split("ss")                    # => ["Mi", "i", "ippi"]
  # long_river_name.split("i")                     # => ["M", "ss", "ss", "pp", ""]
  # long_river_name.split("i", remove_empty: true) # => ["M", "ss", "ss", "pp"]
  # long_river_name.split("")                      # => ["M", "i", "s", "s", "i", "s", "s", "i", "p", "p", "i"]
  # ```
  def split(separator : String, limit = nil, *, remove_empty = false) : Array(String)
    ary = Array(String).new
    split(separator, limit, remove_empty: remove_empty) do |string|
      ary << string
    end
    ary
  end

  # Splits the string after each string *separator* and yields each part to a block.
  #
  # If *limit* is present, the array will be limited to *limit* items and
  # the final item will contain the remainder of the string.
  #
  # If *separator* is an empty string (`""`), the string will be separated into one-character strings.
  #
  # If *remove_empty* is `true`, any empty strings are removed from the result.
  #
  # ```
  # ary = [] of String
  # long_river_name = "Mississippi"
  #
  # long_river_name.split("ss") { |s| ary << s }
  # ary # => ["Mi", "i", "ippi"]
  # ary.clear
  #
  # long_river_name.split("i") { |s| ary << s }
  # ary # => ["M", "ss", "ss", "pp", ""]
  # ary.clear
  #
  # long_river_name.split("i", remove_empty: true) { |s| ary << s }
  # ary # => ["M", "ss", "ss", "pp"]
  # ary.clear
  #
  # long_river_name.split("") { |s| ary << s }
  # ary # => ["M", "i", "s", "s", "i", "s", "s", "i", "p", "p", "i"]
  # ```
  def split(separator : String, limit = nil, *, remove_empty = false, &block : String -> _)
    if empty?
      yield "" unless remove_empty
      return
    end

    if limit && limit <= 1
      yield self
      return
    end

    if separator.empty?
      split_by_empty_separator(limit) do |string|
        yield string
      end
      return
    end

    yielded = 0
    byte_offset = 0
    separator_bytesize = separator.bytesize

    single_byte_optimizable = single_byte_optimizable?

    i = 0
    stop = bytesize - separator.bytesize + 1
    while i < stop
      if (to_unsafe + i).memcmp(separator.to_unsafe, separator_bytesize) == 0
        piece_bytesize = i - byte_offset
        piece_size = single_byte_optimizable ? piece_bytesize : 0
        unless remove_empty && piece_bytesize == 0
          yield String.new(to_unsafe + byte_offset, piece_bytesize, piece_size)
        end
        yielded += 1
        byte_offset = i + separator_bytesize
        i += separator_bytesize - 1
        break if limit && yielded + 1 == limit
      end
      i += 1
    end

    piece_bytesize = bytesize - byte_offset
    return if remove_empty && piece_bytesize == 0
    piece_size = single_byte_optimizable ? piece_bytesize : 0
    yield String.new(to_unsafe + byte_offset, piece_bytesize, piece_size)
  end

  # Makes an `Array` by splitting the string on *separator* (and removing instances of *separator*).
  #
  # If *limit* is present, the array will be limited to *limit* items and
  # the final item will contain the remainder of the string.
  #
  # If *separator* is an empty regex (`//`), the string will be separated into one-character strings.
  #
  # If *remove_empty* is `true`, any empty strings are removed from the result.
  #
  # ```
  # long_river_name = "Mississippi"
  # long_river_name.split(/s+/) # => ["Mi", "i", "ippi"]
  # long_river_name.split(//)   # => ["M", "i", "s", "s", "i", "s", "s", "i", "p", "p", "i"]
  # ```
  def split(separator : Regex, limit = nil, *, remove_empty = false, options : Regex::MatchOptions = Regex::MatchOptions::None) : Array(String)
    ary = Array(String).new
    split(separator, limit, remove_empty: remove_empty, options: options) do |string|
      ary << string
    end
    ary
  end

  # Splits the string after each regex *separator* and yields each part to a block.
  #
  # If *limit* is present, the array will be limited to *limit* items and
  # the final item will contain the remainder of the string.
  #
  # If *separator* is an empty regex (`//`), the string will be separated into one-character strings.
  #
  # If *remove_empty* is `true`, any empty strings are removed from the result.
  #
  # ```
  # ary = [] of String
  # long_river_name = "Mississippi"
  #
  # long_river_name.split(/s+/) { |s| ary << s }
  # ary # => ["Mi", "i", "ippi"]
  # ary.clear
  #
  # long_river_name.split(//) { |s| ary << s }
  # ary # => ["M", "i", "s", "s", "i", "s", "s", "i", "p", "p", "i"]
  # ```
  def split(separator : Regex, limit = nil, *, remove_empty = false, options : Regex::MatchOptions = Regex::MatchOptions::None, &block : String -> _)
    if empty?
      yield "" unless remove_empty
      return
    end

    if limit && limit <= 1
      yield self
      return
    end

    if separator.source.empty?
      split_by_empty_separator(limit) do |string|
        yield string
      end
      return
    end

    count = 0
    match_offset = slice_offset = 0

    while match = separator.match_at_byte_index(self, match_offset, options: options)
      index = match.byte_begin(0)
      match_bytesize = match.byte_end(0) - index
      next_offset = index + match_bytesize

      if next_offset == slice_offset
        match_offset = next_offset + char_bytesize_at(next_offset)
      else
        slice_size = index - slice_offset

        yield byte_slice(slice_offset, slice_size) unless remove_empty && slice_size == 0
        count += 1

        1.upto(match.size) do |i|
          if group = match[i]?
            yield group
          end
        end

        slice_offset = match_offset = next_offset
      end

      break if limit && count + 1 == limit
      break if match_offset >= bytesize
      options |= :no_utf_check
    end

    yield byte_slice(slice_offset) unless remove_empty && slice_offset == bytesize
  end

  private def split_by_empty_separator(limit, &block : String -> _)
    yielded = 0

    each_char do |c|
      yield c.to_s
      yielded += 1
      break if limit && yielded + 1 == limit
    end

    if limit && yielded != size
      yield self[yielded..-1]
      yielded += 1
    end
  end

  def lines(chomp = true) : Array(String)
    lines = [] of String
    each_line(chomp: chomp) do |line|
      lines << line
    end
    lines
  end

  # Splits the string after each newline and yields each line to a block.
  #
  # ```
  # haiku = "the first cold shower
  # even the monkey seems to want
  # a little coat of straw"
  # haiku.each_line do |stanza|
  #   puts stanza
  # end
  # # output:
  # # the first cold shower
  # # even the monkey seems to want
  # # a little coat of straw
  # ```
  def each_line(chomp = true, &block : String ->) : Nil
    return if empty?

    offset = 0

    while byte_index = byte_index('\n'.ord.to_u8, offset)
      count = byte_index - offset + 1
      if chomp
        count -= 1
        if offset + count > 0 && to_unsafe[offset + count - 1] === '\r'
          count -= 1
        end
      end

      yield unsafe_byte_slice_string(offset, count)
      offset = byte_index + 1
    end

    unless offset == bytesize
      yield unsafe_byte_slice_string(offset)
    end
  end

  # Returns an `Iterator` which yields each line of this string (see `String#each_line`).
  def each_line(chomp = true)
    LineIterator.new(self, chomp)
  end

  # Converts camelcase boundaries to underscores.
  #
  # ```
  # "DoesWhatItSaysOnTheTin".underscore                         # => "does_what_it_says_on_the_tin"
  # "PartyInTheUSA".underscore                                  # => "party_in_the_usa"
  # "HTTP_CLIENT".underscore                                    # => "http_client"
  # "3.14IsPi".underscore                                       # => "3.14_is_pi"
  # "InterestingImage".underscore(Unicode::CaseOptions::Turkic) # => "ınteresting_ımage"
  # ```
  def underscore(options : Unicode::CaseOptions = :none) : String
    String.build(bytesize + 10) { |io| underscore io, options }
  end

  # Writes an underscored version of `self` to the given *io*.
  #
  # ```
  # io = IO::Memory.new
  # "DoesWhatItSaysOnTheTin".underscore io
  # io.to_s # => "does_what_it_says_on_the_tin"
  # ```
  def underscore(io : IO, options : Unicode::CaseOptions = :none) : Nil
    first = true
    last_is_downcase = false
    last_is_upcase = false
    last_is_digit = false
    mem : Char? = nil

    each_char do |char|
      if options.ascii?
        digit = char.ascii_number?
        downcase = digit || char.ascii_lowercase?
        upcase = char.ascii_uppercase?
      else
        digit = char.number?
        downcase = digit || char.lowercase?
        upcase = char.uppercase?
      end

      if first
        char.downcase(options) { |c| io << c }
      elsif last_is_downcase && upcase
        if mem
          # This is the case of A1Bcd, we need to put 'mem' (not to need to convert as downcase
          #                       ^
          # because 'mem' is digit surely) before putting this char as downcase.
          io << mem
          mem = nil
        end
        # This is the case of AbcDe, we need to put an underscore before the 'D'
        #                        ^
        io << '_'
        char.downcase(options) { |c| io << c }
      elsif (last_is_upcase || last_is_digit) && (upcase || digit)
        # This is the case of 1) A1Bcd, 2) A1BCd or 3) A1B_cd:if the next char is upcase (case 1) we need
        #                          ^         ^           ^
        # 1) we need to append this char as downcase
        # 2) we need to append an underscore and then the char as downcase, so we save this char
        #    in 'mem' and decide later
        # 3) we need to append this char as downcase and then a single underscore
        if mem
          # case 2
          mem.downcase(options) { |c| io << c }
        end
        mem = char
      else
        if mem
          if char == '_'
            # case 3
          elsif last_is_upcase && downcase
            # case 1
            io << '_'
          end
          mem.downcase(options) { |c| io << c }
          mem = nil
        end

        char.downcase(options) { |c| io << c }
      end

      last_is_downcase = downcase
      last_is_upcase = upcase
      last_is_digit = digit
      first = false
    end

    mem.downcase(options) { |c| io << c } if mem
  end

  # Converts underscores to camelcase boundaries.
  #
  # If *lower* is true, lower camelcase will be returned (the first letter is downcased).
  #
  # ```
  # "eiffel_tower".camelcase                                            # => "EiffelTower"
  # "empire_state_building".camelcase(lower: true)                      # => "empireStateBuilding"
  # "isolated_integer".camelcase(options: Unicode::CaseOptions::Turkic) # => "İsolatedİnteger"
  # ```
  def camelcase(options : Unicode::CaseOptions = Unicode::CaseOptions::None, *, lower : Bool = false) : String
    return self if empty?

    String.build(bytesize) { |io| camelcase io, options, lower: lower }
  end

  # Writes an camelcased version of `self` to the given *io*.
  #
  # If *lower* is true, lower camelcase will be written (the first letter is downcased).
  #
  # ```
  # io = IO::Memory.new
  # "eiffel_tower".camelcase io
  # io.to_s # => "EiffelTower"
  # ```
  def camelcase(io : IO, options : Unicode::CaseOptions = Unicode::CaseOptions::None, *, lower : Bool = false) : Nil
    first = true
    last_is_underscore = false

    each_char do |char|
      if first
        if lower
          char.downcase(options) { |c| io << c }
        else
          char.titlecase(options) { |c| io << c }
        end
      elsif char == '_'
        last_is_underscore = true
      elsif last_is_underscore
        char.titlecase(options) { |c| io << c }
        last_is_underscore = false
      else
        io << char
      end
      first = false
    end
  end

  # Reverses the order of characters in the string.
  #
  # ```
  # "Argentina".reverse # => "anitnegrA"
  # "racecar".reverse   # => "racecar"
  # ```
  #
  # Works on Unicode graphemes (and not codepoints) so combining characters are preserved.
  #
  # ```
  # "Noe\u0308l".reverse # => "lëoN"
  # ```
  def reverse : String
    return self if bytesize <= 1

    if single_byte_optimizable?
      String.new(bytesize) do |buffer|
        bytesize.times do |i|
          buffer[i] = self.to_unsafe[bytesize - i - 1]
        end
        {@bytesize, @length}
      end
    else
      # Iterate graphemes to reverse the string,
      # so combining characters are placed correctly
      String.new(bytesize) do |buffer|
        buffer += bytesize
        each_grapheme_boundary do |range|
          buffer -= range.size
          buffer.copy_from(to_unsafe + range.begin, range.size)
        end
        {@bytesize, @length}
      end
    end
  end

  # Adds instances of *char* to right of the string until it is at least size of *len*.
  #
  # ```
  # "Purple".ljust(8)      # => "Purple  "
  # "Purple".ljust(8, '-') # => "Purple--"
  # "Aubergine".ljust(8)   # => "Aubergine"
  # ```
  def ljust(len : Int, char : Char = ' ') : String
    just len, char, -1
  end

  # Adds instances of *char* to right of the string until it is at least size of *len*,
  # and then appends the result to the given IO.
  #
  # ```
  # io = IO::Memory.new
  # "Purple".ljust(io, 8, '-')
  # io.to_s # => "Purple--"
  # ```
  def ljust(io : IO, len : Int, char : Char = ' ') : Nil
    io << self
    (len - size).times { io << char }
  end

  # Adds instances of *char* to left of the string until it is at least size of *len*.
  #
  # ```
  # "Purple".rjust(8)      # => "  Purple"
  # "Purple".rjust(8, '-') # => "--Purple"
  # "Aubergine".rjust(8)   # => "Aubergine"
  # ```
  def rjust(len : Int, char : Char = ' ') : String
    just len, char, 1
  end

  # Adds instances of *char* to left of the string until it is at least size of *len*,
  # and then appends the result to the given IO.
  #
  # ```
  # io = IO::Memory.new
  # "Purple".rjust(io, 8, '-')
  # io.to_s # => "--Purple"
  # ```
  def rjust(io : IO, len : Int, char : Char = ' ') : Nil
    (len - size).times { io << char }
    io << self
  end

  # Adds instances of *char* to left and right of the string until it is at least size of *len*.
  #
  # ```
  # "Purple".center(8)      # => " Purple "
  # "Purple".center(8, '-') # => "-Purple-"
  # "Purple".center(9, '-') # => "-Purple--"
  # "Aubergine".center(8)   # => "Aubergine"
  # ```
  def center(len : Int, char : Char = ' ') : String
    just len, char, 0
  end

  # Adds instances of *char* to left and right of the string until it is at least size of *len*,
  # then appends the result to the given IO.
  #
  # ```
  # io = IO::Memory.new
  # "Purple".center(io, 9, '-')
  # io.to_s # => "-Purple--"
  # ```
  def center(io : IO, len : Int, char : Char = ' ') : Nil
    difference = len - size

    if difference <= 0
      io << self
      return
    end

    left_padding = difference // 2
    right_padding = difference - left_padding

    left_padding.times { io << char }
    io << self
    right_padding.times { io << char }
  end

  private def just(len, char, justify)
    return self if size >= len

    bytes, count = String.char_bytes_and_bytesize(char)
    padding = (len - size)
    new_bytesize = bytesize + padding * count
    case justify
    when .< 0
      leftpadding, rightpadding = 0, padding
    when .> 0
      leftpadding, rightpadding = padding, 0
    else
      leftpadding = padding // 2
      rightpadding = padding - leftpadding
    end

    String.new(new_bytesize) do |buffer|
      if leftpadding > 0
        if count == 1
          Slice.new(buffer, leftpadding).fill(char.ord.to_u8)
          buffer += leftpadding
        else
          leftpadding.times do
            buffer.copy_from(bytes.to_unsafe, count)
            buffer += count
          end
        end
      end
      buffer.copy_from(to_unsafe, bytesize)
      buffer += bytesize
      if rightpadding > 0
        if count == 1
          Slice.new(buffer, rightpadding).fill(char.ord.to_u8)
        else
          rightpadding.times do
            buffer.copy_from(bytes.to_unsafe, count)
            buffer += count
          end
        end
      end
      {new_bytesize, len}
    end
  end

  # Returns the successor of the string. The successor is calculated
  # by incrementing characters starting from the rightmost alphanumeric
  # (or the rightmost character if there are no alphanumerics) in the string.
  # Incrementing a digit always results in another digit, and incrementing
  # a letter results in another letter of the same case.
  #
  # If the increment generates a "carry", the character to the left of it is
  # incremented. This process repeats until there is no carry,
  # adding an additional character if necessary.
  #
  # ```
  # "abcd".succ      # => "abce"
  # "THX1138".succ   # => "THX1139"
  # "((koala))".succ # => "((koalb))"
  # "1999zzz".succ   # => "2000aaa"
  # "ZZZ9999".succ   # => "AAAA0000"
  # "***".succ       # => "**+"
  # ```
  def succ : String
    return self if empty?

    chars = self.chars

    carry = nil
    last_alnum = 0
    index = size - 1

    while index >= 0
      s = chars[index]
      if s.ascii_alphanumeric?
        carry = 0
        if ('0' <= s && s < '9') ||
           ('a' <= s && s < 'z') ||
           ('A' <= s && s < 'Z')
          chars[index] = s.succ
          break
        elsif s == '9'
          chars[index] = '0'
          carry = '1'
        elsif s == 'z'
          chars[index] = carry = 'a'
        elsif s == 'Z'
          chars[index] = carry = 'A'
        end

        last_alnum = index
      end
      index -= 1
    end

    if carry.nil? # there were no alphanumeric chars
      chars[size - 1] = chars[size - 1].succ
    end

    if carry.is_a?(Char) && index < 0 # we still have a carry and already reached the beginning
      chars.insert(last_alnum, carry)
    end

    String.build(chars.size) do |str|
      chars.each do |char|
        str << char
      end
    end
  end

  # Finds matches of *regex* starting at *pos* and updates `$~` to the result.
  #
  # ```
  # "foo".match(/foo/) # => Regex::MatchData("foo")
  # $~                 # => Regex::MatchData("foo")
  #
  # "foo".match(/bar/) # => nil
  # $~                 # raises Exception
  # ```
  def match(regex : Regex, pos = 0, *, options : Regex::MatchOptions = Regex::MatchOptions::None) : Regex::MatchData?
    $~ = regex.match self, pos, options: options
  end

  # Finds matches of *regex* starting at *pos* and updates `$~` to the result.
  # Raises `Regex::Error` if there are no matches.
  #
  # ```
  # "foo".match!(/foo/) # => Regex::MatchData("foo")
  # $~                  # => Regex::MatchData("foo")
  #
  # "foo".match!(/bar/) # => raises Exception
  def match!(regex : Regex, pos = 0, *, options : Regex::MatchOptions = Regex::MatchOptions::None) : Regex::MatchData
    $~ = regex.match! self, pos, options: options
  end

  # Finds match of *regex* like `#match`, but it returns `Bool` value.
  # It neither returns `MatchData` nor assigns it to the `$~` variable.
  #
  # ```
  # "foo".matches?(/bar/) # => false
  # "foo".matches?(/foo/) # => true
  #
  # # `$~` is not set even if last match succeeds.
  # $~ # raises Exception
  # ```
  def matches?(regex : Regex, pos = 0, *, options : Regex::MatchOptions = Regex::MatchOptions::None) : Bool
    regex.matches? self, pos, options: options
  end

  # Matches the regular expression *regex* against the entire string and returns
  # the resulting `MatchData`.
  # It also updates `$~` with the result.
  #
  # ```
  # "foo".match_full(/foo/)  # => Regex::MatchData("foo")
  # $~                       # => Regex::MatchData("foo")
  # "fooo".match_full(/foo/) # => nil
  # $~                       # raises Exception
  # ```
  def match_full(regex : Regex) : Regex::MatchData?
    match(regex, options: Regex::MatchOptions::ANCHORED | Regex::MatchOptions::ENDANCHORED)
  end

  # Matches the regular expression *regex* against the entire string and returns
  # the resulting `MatchData`.
  # It also updates `$~` with the result.
  # Raises `Regex::Error` if there are no matches.
  #
  # ```
  # "foo".match_full!(/foo/)  # => Regex::MatchData("foo")
  # $~                        # => Regex::MatchData("foo")
  # "fooo".match_full!(/foo/) # Regex::Error
  # $~                        # raises Exception
  # ```
  def match_full!(regex : Regex) : Regex::MatchData?
    match!(regex, options: Regex::MatchOptions::ANCHORED | Regex::MatchOptions::ENDANCHORED)
  end

  # Returns `true` if the regular expression *regex* matches this string entirely.
  #
  # ```
  # "foo".matches_full?(/foo/)  # => true
  # "fooo".matches_full?(/foo/) # => false
  #
  # # `$~` is not set even if last match succeeds.
  # $~ # raises Exception
  # ```
  def matches_full?(regex : Regex) : Bool
    matches?(regex, options: Regex::MatchOptions::ANCHORED | Regex::MatchOptions::ENDANCHORED)
  end

  # Searches the string for instances of *pattern*,
  # yielding a `Regex::MatchData` for each match.
  def scan(pattern : Regex, *, options : Regex::MatchOptions = Regex::MatchOptions::None, &) : self
    byte_offset = 0

    while match = pattern.match_at_byte_index(self, byte_offset, options: options)
      index = match.byte_begin(0)
      $~ = match
      yield match
      match_bytesize = match.byte_end(0) - index
      match_bytesize += char_bytesize_at(byte_offset) if match_bytesize == 0
      byte_offset = index + match_bytesize
      options |= :no_utf_check
    end

    self
  end

  # Searches the string for instances of *pattern*,
  # returning an `Array` of `Regex::MatchData` for each match.
  def scan(pattern : Regex, *, options : Regex::MatchOptions = Regex::MatchOptions::None) : Array(Regex::MatchData)
    matches = [] of Regex::MatchData
    scan(pattern, options: options) do |match|
      matches << match
    end
    matches
  end

  # Searches the string for instances of *pattern*,
  # yielding the matched string for each match.
  def scan(pattern : String, &) : self
    return self if pattern.empty?
    index = 0
    while index = byte_index(pattern, index)
      yield pattern
      index += pattern.bytesize
    end
    self
  end

  # Searches the string for instances of *pattern*,
  # returning an array of the matched string for each match.
  def scan(pattern : String) : Array(String)
    matches = [] of String
    scan(pattern) do |match|
      matches << match
    end
    matches
  end

  # Yields each character in the string to the block.
  #
  # ```
  # array = [] of Char
  # "ab☃".each_char do |char|
  #   array << char
  # end
  # array # => ['a', 'b', '☃']
  # ```
  def each_char(&) : Nil
    if single_byte_optimizable?
      each_byte do |byte|
        yield (byte < 0x80 ? byte.unsafe_chr : Char::REPLACEMENT)
      end
    else
      Char::Reader.new(self).each do |char|
        yield char
      end
    end
  end

  # Returns an `Iterator` over each character in the string.
  #
  # ```
  # chars = "ab☃".each_char
  # chars.next # => 'a'
  # chars.next # => 'b'
  # chars.next # => '☃'
  # ```
  def each_char
    CharIterator.new(Char::Reader.new(self))
  end

  # Yields each character and its index in the string to the block.
  #
  # ```
  # array = [] of Tuple(Char, Int32)
  # "ab☃".each_char_with_index do |char, index|
  #   array << {char, index}
  # end
  # array # => [{'a', 0}, {'b', 1}, {'☃', 2}]
  # ```
  #
  # Accepts an optional *offset* parameter, which tells it to start counting
  # from there.
  def each_char_with_index(offset = 0, &)
    each_char do |char|
      yield char, offset
      offset += 1
    end
  end

  # Returns an `Array` of all characters in the string.
  #
  # ```
  # "ab☃".chars # => ['a', 'b', '☃']
  # ```
  def chars : Array(Char)
    chars = Array(Char).new(@length > 0 ? @length : bytesize)
    each_char do |char|
      chars << char
    end
    chars
  end

  # Yields each codepoint to the block.
  #
  # ```
  # array = [] of Int32
  # "ab☃".each_codepoint do |codepoint|
  #   array << codepoint
  # end
  # array # => [97, 98, 9731]
  # ```
  #
  # See also: `Char#ord`.
  def each_codepoint(&)
    each_char do |char|
      yield char.ord
    end
  end

  # Returns an `Iterator` for each codepoint.
  #
  # ```
  # codepoints = "ab☃".each_codepoint
  # codepoints.next # => 97
  # codepoints.next # => 98
  # codepoints.next # => 9731
  # ```
  #
  # See also: `Char#ord`.
  def each_codepoint
    each_char.map &.ord
  end

  # Returns an `Array` of the codepoints that make the string.
  #
  # ```
  # "ab☃".codepoints # => [97, 98, 9731]
  # ```
  #
  # See also: `Char#ord`.
  def codepoints : Array(Int32)
    codepoints = Array(Int32).new(@length > 0 ? @length : bytesize)
    each_codepoint do |codepoint|
      codepoints << codepoint
    end
    codepoints
  end

  # Yields each byte in the string to the block.
  #
  # ```
  # array = [] of UInt8
  # "ab☃".each_byte do |byte|
  #   array << byte
  # end
  # array # => [97, 98, 226, 152, 131]
  # ```
  def each_byte(&)
    to_slice.each do |byte|
      yield byte
    end
    nil
  end

  # Returns an `Iterator` over each byte in the string.
  #
  # ```
  # bytes = "ab☃".each_byte
  # bytes.next # => 97
  # bytes.next # => 98
  # bytes.next # => 226
  # bytes.next # => 152
  # bytes.next # => 131
  # ```
  def each_byte
    to_slice.each
  end

  # Returns this string's bytes as an `Array(UInt8)`.
  #
  # ```
  # "hello".bytes # => [104, 101, 108, 108, 111]
  # "你好".bytes    # => [228, 189, 160, 229, 165, 189]
  # ```
  def bytes : Array(UInt8)
    Array.new(bytesize) { |i| to_unsafe[i] }
  end

  # Pretty prints `self` into the given printer.
  def pretty_print(pp : PrettyPrint) : Nil
    printed_bytesize = 0
    pp.group do
      split('\n') do |part|
        printed_bytesize += part.bytesize
        if printed_bytesize != bytesize
          printed_bytesize += 1 # == "\n".bytesize
          pp.text('"')
          pp.text(part.inspect_unquoted)
          pp.text("\\n\"")
          break if printed_bytesize == bytesize
          pp.text(" +")
          pp.breakable
        else
          pp.text(part.inspect)
        end
      end
    end
  end

  # Returns a representation of `self` as a Crystal string literal, wrapped in
  # double quotes.
  #
  # Non-printable characters (see `Char#printable?`) are escaped.
  #
  # ```
  # "\u{1f48e} - à la carte\n".inspect # => %("\u{1F48E} - à la carte\\n")
  # ```
  #
  # See `Char#unicode_escape` for the format used to escape characters without a
  # special escape sequence.
  #
  # * `#inspect_unquoted` omits the delimiters.
  # * `#dump` additionally escapes all non-ASCII characters.
  def inspect : String
    super
  end

  # :ditto:
  def inspect(io : IO) : Nil
    dump_or_inspect(io) do |char, error|
      inspect_char(char, error, io)
    end
  end

  # Returns a representation of `self` as the content of a Crystal string literal
  # without delimiters.
  #
  # Non-printable characters (see `Char#printable?`) are escaped.
  #
  # ```
  # "\u{1f48e} - à la carte\n".inspect_unquoted # => %(\u{1F48E} - à la carte\\n)
  # ```
  #
  # See `Char#unicode_escape` for the format used to escape characters without a
  # special escape sequence.
  #
  # * `#inspect` wraps the content in double quotes.
  # * `#dump_unquoted` additionally escapes all non-ASCII characters.
  def inspect_unquoted : String
    String.build do |io|
      inspect_unquoted(io)
    end
  end

  # :ditto:
  def inspect_unquoted(io : IO) : Nil
    dump_or_inspect_unquoted(io) do |char, error|
      inspect_char(char, error, io)
    end
  end

  # Returns a representation of `self` as an ASCII-compatible Crystal string
  # literal, wrapped in double quotes.
  #
  # Non-printable characters (see `Char#printable?`) and non-ASCII characters
  # (codepoints larger `U+007F`) are escaped.
  #
  # ```
  # "\u{1f48e} - à la carte\n".dump # => %("\\u{1F48E} - \\u00E0 la carte\\n")
  # ```
  #
  # See `Char#unicode_escape` for the format used to escape characters without a
  # special escape sequence.
  #
  # * `#dump_unquoted` omits the delimiters.
  # * `#inspect` only escapes non-printable characters.
  def dump : String
    String.build do |io|
      dump io
    end
  end

  # :ditto:
  def dump(io : IO) : Nil
    dump_or_inspect(io) do |char, error|
      dump_char(char, error, io)
    end
  end

  # Returns a representation of `self` as the content of an ASCII-compatible
  # Crystal string literal without delimiters.
  #
  # Non-printable characters (see `Char#printable?`) and non-ASCII characters
  # (codepoints larger `U+007F`) are escaped.
  #
  # ```
  # "\u{1f48e} - à la carte\n".dump_unquoted # => %(\\u{1F48E} - \\u00E0 la carte\\n)
  # ```
  #
  # See `Char#unicode_escape` for the format used to escape characters without a
  # special escape sequence.
  #
  # * `#dump` wraps the content in double quotes.
  # * `#inspect_unquoted` only escapes non-printable characters.
  def dump_unquoted : String
    String.build do |io|
      dump_unquoted(io)
    end
  end

  # :nodoc:
  def dump_unquoted(io : IO) : Nil
    dump_or_inspect_unquoted(io) do |char, error|
      dump_char(char, error, io)
    end
  end

  private def dump_or_inspect(io, &)
    io << '"'
    dump_or_inspect_unquoted(io) do |char, error|
      yield char, error
    end
    io << '"'
  end

  private def dump_or_inspect_unquoted(io, &)
    reader = Char::Reader.new(self)
    while reader.has_next?
      current_char = reader.current_char
      case current_char
      when '"'  then io << "\\\""
      when '\\' then io << "\\\\"
      when '\a' then io << "\\a"
      when '\b' then io << "\\b"
      when '\e' then io << "\\e"
      when '\f' then io << "\\f"
      when '\n' then io << "\\n"
      when '\r' then io << "\\r"
      when '\t' then io << "\\t"
      when '\v' then io << "\\v"
      when '#'
        current_char = reader.next_char
        if current_char == '{'
          io << "\\\#{"
          reader.next_char
          next
        else
          io << '#'
          next
        end
      else
        if reader.error
          reader.current_char_width.times do |i|
            yield '\0', to_unsafe[reader.pos + i]
          end
        else
          yield current_char, nil
        end
      end
      reader.next_char
    end
  end

  private def inspect_char(char, error, io)
    dump_or_inspect_char char, error, io do
      !char.printable?
    end
  end

  private def dump_char(char, error, io)
    dump_or_inspect_char char, error, io do
      # Technically, the condition would be `!char.ascii? || !char.printable?` but
      # all non-printable ASCII characters are control characters, so we can simplify.
      !char.ascii? || char.ascii_control?
    end
  end

  private def dump_or_inspect_char(char, error, io, &)
    if error
      dump_hex(error, io)
    elsif yield
      char.unicode_escape(io)
    else
      io << char
    end
  end

  private def dump_hex(char, io)
    io << "\\x"
    io << '0' if char < 0x0F
    char.to_s(io, 16, upcase: true)
  end

  # Returns `true` if this string starts with the given *str*.
  #
  # ```
  # "hello".starts_with?("h")  # => true
  # "hello".starts_with?("he") # => true
  # "hello".starts_with?("hu") # => false
  # ```
  def starts_with?(str : String) : Bool
    return false if str.bytesize > bytesize
    to_unsafe.memcmp(str.to_unsafe, str.bytesize) == 0
  end

  # Returns `true` if this string starts with the given *char*.
  #
  # ```
  # "hello".starts_with?('h') # => true
  # "hello".starts_with?('e') # => false
  # ```
  def starts_with?(char : Char) : Bool
    each_char do |c|
      return c == char
    end

    false
  end

  # Returns `true` if the regular expression *re* matches at the start of this string.
  #
  # ```
  # "22hello".starts_with?(/[0-9]/) # => true
  # "22hello".starts_with?(/[a-z]/) # => false
  # "h22".starts_with?(/[a-z]/)     # => true
  # "h22".starts_with?(/[A-Z]/)     # => false
  # "h22".starts_with?(/[a-z]{2}/)  # => false
  # "hh22".starts_with?(/[a-z]{2}/) # => true
  # ```
  def starts_with?(re : Regex, *, options : Regex::MatchOptions = Regex::MatchOptions::None) : Bool
    !!($~ = re.match_at_byte_index(self, 0, options: options | Regex::MatchOptions::ANCHORED))
  end

  # Returns `true` if this string ends with the given *str*.
  #
  # ```
  # "hello".ends_with?("o")  # => true
  # "hello".ends_with?("lo") # => true
  # "hello".ends_with?("ll") # => false
  # ```
  def ends_with?(str : String) : Bool
    return false if str.bytesize > bytesize
    (to_unsafe + bytesize - str.bytesize).memcmp(str.to_unsafe, str.bytesize) == 0
  end

  # Returns `true` if this string ends with the given *char*.
  #
  # ```
  # "hello".ends_with?('o') # => true
  # "hello".ends_with?('l') # => false
  # ```
  def ends_with?(char : Char) : Bool
    return false unless bytesize > 0

    if char.ascii? || single_byte_optimizable?
      byte = to_unsafe[bytesize - 1]
      return byte < 0x80 ? byte == char.ord : char == Char::REPLACEMENT
    end

    bytes, count = String.char_bytes_and_bytesize(char)
    return false if bytesize < count

    count.times do |i|
      return false unless to_unsafe[bytesize - count + i] == bytes[i]
    end

    true
  end

  # Returns `true` if the regular expression *re* matches at the end of this string.
  #
  # ```
  # "22hello".ends_with?(/[0-9]/) # => false
  # "22hello".ends_with?(/[a-z]/) # => true
  # "22h".ends_with?(/[a-z]/)     # => true
  # "22h".ends_with?(/[A-Z]/)     # => false
  # "22h".ends_with?(/[a-z]{2}/)  # => false
  # "22hh".ends_with?(/[a-z]{2}/) # => true
  # ```
  def ends_with?(re : Regex, *, options : Regex::MatchOptions = Regex::MatchOptions::None) : Bool
    if Regex.supports_match_options?(Regex::MatchOptions::ENDANCHORED)
      result = re.match(self, options: options | Regex::MatchOptions::ENDANCHORED)
    else
      # Workaround when ENDANCHORED is unavailable (PCRE).
      result = /#{re}\z/.match(self, options: options)
    end
    $~ = result
    !!result
  end

  # Interpolates *other* into the string using top-level `::sprintf`.
  #
  # ```
  # "I have %d apples" % 5                                             # => "I have 5 apples"
  # "%s, %s, %s, D" % ['A', 'B', 'C']                                  # => "A, B, C, D"
  # "sum: %{one} + %{two} = %{three}" % {one: 1, two: 2, three: 1 + 2} # => "sum: 1 + 2 = 3"
  # "I have %<apples>s apples" % {apples: 4}                           # => "I have 4 apples"
  # ```
  def %(other) : String
    sprintf self, other
  end

  # See `Object#hash(hasher)`
  def hash(hasher)
    hasher.string(self)
  end

  # Returns the number of unicode codepoints in this string.
  #
  # ```
  # "hello".size # => 5
  # "你好".size    # => 2
  # ```
  def size : Int32
    if @length > 0 || @bytesize == 0
      return @length
    end

    @length = each_byte_index_and_char_index { }
  end

  # Returns `true` if this String is comprised in its entirety
  # by ASCII characters.
  #
  # ```
  # "hello".ascii_only? # => true
  # "你好".ascii_only?    # => false
  # ```
  def ascii_only? : Bool
    if @bytesize == size
      each_byte do |byte|
        return false unless byte < 0x80
      end
      true
    else
      false
    end
  end

  # :nodoc:
  def single_byte_optimizable? : Bool
    @bytesize == size
  end

  # Returns `true` if this String is encoded correctly
  # according to the UTF-8 encoding.
  def valid_encoding? : Bool
    Unicode.valid?(to_slice)
  end

  # Returns a String where bytes that are invalid in the
  # UTF-8 encoding are replaced with *replacement*.
  def scrub(replacement = Char::REPLACEMENT) : String
    # If the string is valid we have a chance of returning self
    # to avoid creating a new string
    result = nil

    reader = Char::Reader.new(self)
    while reader.has_next?
      if reader.error
        unless result
          result = String::Builder.new(bytesize)
          result.write(to_slice[0, reader.pos])
        end
        result << replacement
      else
        result << reader.current_char if result
      end
      reader.next_char
    end

    result ? result.to_s : self
  end

  protected def char_bytesize_at(byte_index)
    String.char_bytesize_at(to_unsafe + byte_index)
  end

  protected def self.char_bytesize_at(bytes : Pointer(UInt8))
    first = bytes.value

    if first < 0x80
      return 1
    end

    if first < 0xc2
      return 1 # Invalid
    end

    second = bytes[1]

    if (second & 0xc0) != 0x80
      return 1 # Invalid
    end

    if first < 0xe0
      return 2
    end

    third = bytes[2]

    if (third & 0xc0) != 0x80
      return 1 # Invalid
    end

    if first < 0xf0
      if first == 0xe0 && second < 0xa0
        return 1 # Invalid
      end

      if first == 0xed && second >= 0xa0
        return 1 # Invalid
      end

      return 3
    end

    if first == 0xf0 && second < 0x90
      return 1 # Invalid
    end

    if first == 0xf4 && second >= 0x90
      return 1 # Invalid
    end

    fourth = bytes[3]

    if (fourth & 0xc0) != 0x80
      return 1 # Invalid
    end

    if first < 0xf5
      return 4
    end

    1 # Invalid
  end

  # :nodoc:
  def size_known? : Bool
    @bytesize == 0 || @length > 0
  end

  protected def each_byte_index_and_char_index(&)
    byte_index = 0
    char_index = 0

    while byte_index < bytesize
      yield byte_index, char_index
      byte_index += char_bytesize_at(byte_index)
      char_index += 1
    end

    char_index
  end

  # Returns `self`.
  def clone : String
    self
  end

  # :ditto:
  def dup : String
    self
  end

  # :ditto:
  def to_s : String
    self
  end

  # Appends `self` to *io*.
  def to_s(io : IO) : Nil
    io.write_string(to_slice)
  end

  # Returns the underlying bytes of this String.
  #
  # The returned slice is read-only.
  #
  # May contain invalid UTF-8 byte sequences; `#scrub` may be used to first
  # obtain a `String` that is guaranteed to be valid UTF-8.
  def to_slice : Bytes
    Slice.new(to_unsafe, bytesize, read_only: true)
  end

  # Returns a pointer to the underlying bytes of this String.
  #
  # May contain invalid UTF-8 byte sequences; `#scrub` may be used to first
  # obtain a `String` that is guaranteed to be valid UTF-8.
  def to_unsafe : UInt8*
    pointerof(@c)
  end

  # Returns *count* of underlying bytes of this String starting at given *byte_offset*.
  #
  # The returned slice is read-only.
  def unsafe_byte_slice(byte_offset, count) : Slice
    Slice.new(to_unsafe + byte_offset, count, read_only: true)
  end

  # Returns the underlying bytes of this String starting at given *byte_offset*.
  #
  # The returned slice is read-only.
  def unsafe_byte_slice(byte_offset) : Slice
    Slice.new(to_unsafe + byte_offset, bytesize - byte_offset, read_only: true)
  end

  protected def unsafe_byte_slice_string(byte_offset, *, size = 0)
    String.new(to_unsafe + byte_offset, bytesize - byte_offset, size)
  end

  protected def unsafe_byte_slice_string(byte_offset, count, size = 0)
    String.new(to_unsafe + byte_offset, count, size)
  end

  protected def self.char_bytes_and_bytesize(char : Char)
    bytes = uninitialized UInt8[4]

    bytesize = 0
    char.each_byte do |byte|
      bytes[bytesize] = byte
      bytesize += 1
    end

    {bytes, bytesize}
  end

  # Raises an `ArgumentError` if `self` has null bytes. Returns `self` otherwise.
  #
  # This method should sometimes be called before passing a `String` to a C function.
  def check_no_null_byte(name = nil) : self
    if byte_index(0)
      name = "`#{name}` " if name
      raise ArgumentError.new("String #{name}contains null byte")
    end
    self
  end

  # :nodoc:
  def self.check_capacity_in_bounds(capacity) : Nil
    if capacity < 0
      raise ArgumentError.new("Negative capacity")
    end

    if capacity.to_u64 > (UInt32::MAX - HEADER_SIZE - 1)
      raise ArgumentError.new("Capacity too big")
    end
  end

  private class CharIterator
    include Iterator(Char)

    @reader : Char::Reader
    @end : Bool

    def initialize(@reader, @end = false)
      check_empty
    end

    def next
      return stop if @end

      value = @reader.current_char
      @reader.next_char
      @end = true unless @reader.has_next?

      value
    end

    private def check_empty
      @end = true if @reader.string.bytesize == 0
    end
  end

  private class LineIterator
    include Iterator(String)

    def initialize(@string : String, @chomp : Bool)
      @offset = 0
      @end = false
    end

    def next
      return stop if @end

      byte_index = @string.byte_index('\n'.ord.to_u8, @offset)
      if byte_index
        count = byte_index - @offset + 1
        if @chomp
          count -= 1
          if @offset + count > 0 && @string.to_unsafe[@offset + count - 1] === '\r'
            count -= 1
          end
        end

        value = @string.unsafe_byte_slice_string(@offset, count)
        @offset = byte_index + 1
      else
        if @offset == @string.bytesize
          value = stop
        else
          value = @string.unsafe_byte_slice_string(@offset)
        end
        @end = true
      end

      value
    end
  end

  # Implementation of string interpolation of a single string.
  #
  # For example, this code will end up invoking this method:
  #
  # ```
  # value = "hello"
  # "#{value}" # same as String.interpolation(value)
  # ```
  #
  # In this case the implementation just returns the same string.
  #
  # NOTE: there should never be a need to call this method instead of using string interpolation.
  def self.interpolation(value : String) : String
    value
  end

  # Implementation of string interpolation of a single non-string value.
  #
  # For example, this code will end up invoking this method:
  #
  # ```
  # value = 123
  # "#{value}" # same as String.interpolation(value)
  # ```
  #
  # In this case the implementation just returns the result of calling `value.to_s`.
  #
  # NOTE: there should never be a need to call this method instead of using string interpolation.
  def self.interpolation(value) : String
    value.to_s
  end

  # Implementation of string interpolation of a string and a char.
  #
  # For example, this code will end up invoking this method:
  #
  # ```
  # char = '!'
  # "hello#{char}" # same as String.interpolation("hello", char)
  # ```
  #
  # In this case the implementation just does `value + char`.
  #
  # NOTE: there should never be a need to call this method instead of using string interpolation.
  def self.interpolation(value : String, char : Char) : String
    value + char
  end

  # Implementation of string interpolation of a char and a string.
  #
  # For example, this code will end up invoking this method:
  #
  # ```
  # char = '!'
  # "#{char}hello" # same as String.interpolation(char, "hello")
  # ```
  #
  # In this case the implementation just does `char + value`.
  #
  # NOTE: there should never be a need to call this method instead of using string interpolation.
  def self.interpolation(char : Char, value : String) : String
    char + value
  end

  # Implementation of string interpolation of multiple string values.
  #
  # For example, this code will end up invoking this method:
  #
  # ```
  # value1 = "hello"
  # value2 = "world"
  # "#{value1} #{value2}!" # same as String.interpolation(value1, " ", value2, "!")
  # ```
  #
  # In this case the implementation can pre-compute the needed string bytesize and so
  # it's a bit more performant than interpolating non-string values.
  #
  # NOTE: there should never be a need to call this method instead of using string interpolation.
  def self.interpolation(*values : String) : String
    bytesize = values.sum(&.bytesize)
    size = if values.all?(&.size_known?)
             values.sum(&.size)
           else
             0
           end
    String.new(bytesize) do |buffer|
      values.each do |value|
        buffer.copy_from(value.to_unsafe, value.bytesize)
        buffer += value.bytesize
      end
      {bytesize, size}
    end
  end

  # Implementation of string interpolation of multiple, possibly non-string values.
  #
  # For example, this code will end up invoking this method:
  #
  # ```
  # value1 = "hello"
  # value2 = 123
  # "#{value1} #{value2}!" # same as String.interpolation(value1, " ", value2, "!")
  # ```
  #
  # In this case the implementation will call `String.build` with the given values.
  #
  # NOTE: there should never be a need to call this method instead of using string interpolation.
  def self.interpolation(*values : *T) : String forall T
    capacity = 0
    {% for i in 0...T.size %}
      value{{i}} = values[{{i}}]
      if value{{i}}.is_a?(String)
        capacity += value{{i}}.bytesize
      else
        capacity += 15
      end
    {% end %}
    String.build(capacity) do |io|
      {% for i in 0...T.size %}
        if value{{i}}.is_a?(String)
          io.write(value{{i}}.to_slice)
        else
          io << value{{i}}
        end
      {% end %}
    end
  end
end

require "./string/*"
