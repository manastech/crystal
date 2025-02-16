# Int is the base type of all integer types.
#
# There are four signed integer types: `Int8`, `Int16`, `Int32` and `Int64`,
# being able to represent numbers of 8, 16, 32 and 64 bits respectively.
# There are four unsigned integer types: `UInt8`, `UInt16`, `UInt32` and `UInt64`.
#
# An integer literal is an optional `+` or `-` sign, followed by
# a sequence of digits and underscores, optionally followed by a suffix.
# If no suffix is present, the literal's type is `Int32`, or `Int64` if the
# number doesn't fit into an `Int32`:
#
# ```
# 1 # Int32
#
# 1_i8  # Int8
# 1_i16 # Int16
# 1_i32 # Int32
# 1_i64 # Int64
#
# 1_u8  # UInt8
# 1_u16 # UInt16
# 1_u32 # UInt32
# 1_u64 # UInt64
#
# +10 # Int32
# -20 # Int32
#
# 2147483648 # Int64
# ```
#
# Literals without a suffix that are larger than `Int64::MAX` represent a
# `UInt64` if the number fits, e.g. `9223372036854775808` and
# `0x80000000_00000000`. This behavior is deprecated and will become an error in
# the future.
#
# The underscore `_` before the suffix is optional.
#
# Underscores can be used to make some numbers more readable:
#
# ```
# 1_000_000 # better than 1000000
# ```
#
# Binary numbers start with `0b`:
#
# ```
# 0b1101 # == 13
# ```
#
# Octal numbers start with `0o`:
#
# ```
# 0o123 # == 83
# ```
#
# Hexadecimal numbers start with `0x`:
#
# ```
# 0xFE012D # == 16646445
# 0xfe012d # == 16646445
# ```
#
# See [`Integer` literals](https://crystal-lang.org/reference/syntax_and_semantics/literals/integers.html) in the language reference.
struct Int
  alias Signed = Int8 | Int16 | Int32 | Int64 | Int128
  alias Unsigned = UInt8 | UInt16 | UInt32 | UInt64 | UInt128
  alias Primitive = Signed | Unsigned

  # Returns a `Char` that has the unicode codepoint of `self`.
  #
  # Raises `ArgumentError` if this integer's value doesn't fit a char's range
  # (`0..0xd7ff` and `0xe000..0x10ffff`).
  #
  # ```
  # 97.chr # => 'a'
  # ```
  def chr : Char
    unless 0 <= self <= 0xd7ff || 0xe000 <= self <= Char::MAX_CODEPOINT
      raise ArgumentError.new("0x#{self.to_s(16)} out of char range")
    end
    unsafe_chr
  end

  def ~
    self ^ -1
  end

  # Divides `self` by *other* using floored division.
  #
  # In floored division, given two integers x and y:
  # * q = x / y is rounded toward negative infinity
  # * r = x % y has the sign of the second argument
  # * x == q*y + r
  #
  # For example:
  #
  # ```text
  #  x     y     x / y     x % y
  #  5     3       1         2
  # -5     3      -2         1
  #  5    -3      -2        -1
  # -5    -3       1        -2
  # ```
  #
  # Raises if *other* is zero, or if *other* is -1 and
  # `self` is signed and is the minimum value for that
  # integer type.
  def //(other : Int::Primitive)
    check_div_argument other

    div = unsafe_div other
    mod = unsafe_mod other
    div -= 1 if other > 0 ? mod < 0 : mod > 0
    div
  end

  # Divides `self` by *other* using truncated division.
  #
  # In truncated division, given two integers x and y:
  # * `q = x.tdiv(y)` is rounded toward zero
  # * `r = x.remainder(y)` has the sign of the first argument
  # * `x == q*y + r`
  #
  # For example:
  #
  # ```text
  #  x     y     x / y     x % y
  #  5     3       1         2
  # -5     3      -1        -2
  #  5    -3      -1         2
  # -5    -3       1        -2
  # ```
  #
  # Raises if *other* is `0`, or if *other* is `-1` and
  # `self` is signed and is the minimum value for that
  # integer type.
  def tdiv(other : Int)
    check_div_argument other

    unsafe_div other
  end

  private def check_div_argument(other)
    if other == 0
      raise DivisionByZeroError.new
    end

    {% begin %}
      if self < 0 && self == {{@type}}::MIN && other == -1
        raise ArgumentError.new "Overflow: {{@type}}::MIN / -1"
      end
    {% end %}
  end

  def fdiv(other) : Float64
    to_f / other
  end

  # Returns `self` modulo *other*.
  #
  # This uses floored division.
  #
  # See `Int#/` for more details.
  def %(other : Int)
    {% begin %}
      if other == 0
        raise DivisionByZeroError.new
      elsif self < 0 && self == {{@type}}::MIN && other == -1
        self.class.new(0)
      elsif (self < 0) == (other < 0)
        self.unsafe_mod(other)
      else
        me = self.unsafe_mod(other)
        me == 0 ? me : me + other
      end
    {% end %}
  end

  # Returns `self` remainder *other*.
  #
  # This uses truncated division.
  #
  # See `Int#tdiv` for more details.
  def remainder(other : Int)
    {% begin %}
      if other == 0
        raise DivisionByZeroError.new
      elsif self < 0 && self == {{@type}}::MIN && other == -1
        self.class.new(0)
      else
        unsafe_mod other
      end
    {% end %}
  end

  # :nodoc:
  #
  # Computes (x * y) % z, but without intermediate overflows.
  # Precondition: `0 <= x < z && y >= 0`
  def self.mulmod(x, y, z)
    result = zero
    while y > 0
      if y.bits_set?(1)
        # result = (result + x) % z
        if result >= z &- x
          result &-= z &- x
        else
          result &+= x
        end
      end
      # x = (x + x) % z
      if x >= z &- x
        x &-= z &- x
      else
        x = x.unsafe_shl(1)
      end
      y = y.unsafe_shr(1)
    end
    result
  end

  # Returns the result of shifting this number's bits *count* positions to the right.
  # Also known as arithmetic right shift.
  #
  # * If *count* is greater than the number of bits of this integer, returns 0
  # * If *count* is negative, a left shift is performed
  #
  # ```
  # 8000 >> 1  # => 4000
  # 8000 >> 2  # => 2000
  # 8000 >> 32 # => 0
  # 8000 >> -1 # => 16000
  #
  # -8000 >> 1 # => -4000
  # ```
  def >>(count : Int)
    if count < 0
      self << count.abs
    elsif count < sizeof(self) * 8
      self.unsafe_shr(count)
    else
      self.class.zero
    end
  end

  # Returns the result of shifting this number's bits *count* positions to the left.
  #
  # * If *count* is greater than the number of bits of this integer, returns 0
  # * If *count* is negative, a right shift is performed
  #
  # ```
  # 8000 << 1  # => 16000
  # 8000 << 2  # => 32000
  # 8000 << 32 # => 0
  # 8000 << -1 # => 4000
  # ```
  def <<(count : Int)
    if count < 0
      self >> count.abs
    elsif count < sizeof(self) * 8
      self.unsafe_shl(count)
    else
      self.class.zero
    end
  end

  def <=>(other : Int) : Int32
    # Override Number#<=> because when comparing
    # Int vs Int there's no way we can return `nil`
    self > other ? 1 : (self < other ? -1 : 0)
  end

  def abs : self
    self >= 0 ? self : -self
  end

  def round(mode : RoundingMode) : self
    self
  end

  def ceil : self
    self
  end

  def floor : self
    self
  end

  def trunc : self
    self
  end

  # Returns `self`.
  def round_even : self
    self
  end

  # Returns `self`.
  def round_away
    self
  end

  # :inherit:
  #
  # Always returns `true` for `Int`.
  def integer? : Bool
    true
  end

  # Returns the value of raising `self` to the power of *exponent*.
  #
  # Raises `ArgumentError` if *exponent* is negative: if this is needed,
  # either use a float base or a float exponent.
  #
  # Raises `OverflowError` in case of overflow.
  #
  # ```
  # 2 ** 3  # => 8
  # 2 ** 0  # => 1
  # 2 ** -1 # ArgumentError
  # ```
  def **(exponent : Int) : self
    if exponent < 0
      raise ArgumentError.new "Cannot raise an integer to a negative integer power, use floats for that"
    end

    result = self.class.new(1)
    k = self
    while exponent > 0
      result *= k if exponent & 0b1 != 0
      exponent = exponent.unsafe_shr(1)
      k *= k if exponent > 0
    end
    result
  end

  # Returns the value of raising `self` to the power of *exponent*.
  #
  # Raises `ArgumentError` if *exponent* is negative: if this is needed,
  # either use a float base or a float exponent.
  #
  # Intermediate multiplication will wrap around silently in case of overflow.
  #
  # ```
  # 2 &** 3  # => 8
  # 2 &** 0  # => 1
  # 2 &** -1 # ArgumentError
  # ```
  def &**(exponent : Int) : self
    if exponent < 0
      raise ArgumentError.new "Cannot raise an integer to a negative integer power, use floats for that"
    end

    result = self.class.new(1)
    k = self
    while exponent > 0
      result &*= k if exponent & 0b1 != 0
      exponent = exponent.unsafe_shr(1)
      k &*= k if exponent > 0
    end
    result
  end

  # Returns the value of raising `self` to the power of *exponent*.
  #
  # ```
  # 2 ** 3.0  # => 8.0
  # 2 ** 0.0  # => 1.0
  # 2 ** -1.0 # => 0.5
  # ```
  def **(exponent : Float) : Float64
    to_f ** exponent
  end

  def ===(char : Char)
    self === char.ord
  end

  # Returns this number's *bit*th bit, starting with the least-significant.
  #
  # ```
  # 11.bit(0) # => 1
  # 11.bit(1) # => 1
  # 11.bit(2) # => 0
  # 11.bit(3) # => 1
  # 11.bit(4) # => 0
  # ```
  def bit(bit)
    self >> bit & 1
  end

  # Returns the requested range of bits
  #
  # ```
  # 0b10011.bits(0..1) # => 0b11
  # 0b10011.bits(0..2) # => 0b11
  # 0b10011.bits(0..3) # => 0b11
  # 0b10011.bits(0..4) # => 0b10011
  # 0b10011.bits(0..5) # => 0b10011
  # 0b10011.bits(1..4) # => 0b1001
  # ```
  def bits(range : Range)
    start_index = range.begin
    if start_index
      raise IndexError.new("Start index (#{start_index}) must be positive") if start_index < 0
    else
      start_index = 0
    end

    end_index = range.end
    if end_index
      raise IndexError.new("End index (#{end_index}) must be positive") if end_index < 0
      end_index += 1 unless range.exclusive?
      raise IndexError.new("End index (#{end_index}) must be greater than start index (#{start_index})") if end_index <= start_index
    else
      # if there is no end index then we only need to shift
      return self >> start_index
    end

    # Generates a mask `count` bits long maintaining the correct type
    count = end_index - start_index
    mask = (self.class.new(1) << count) &- 1

    if self < 0
      # Special case for negative to ensure the shift and mask work as expected
      # The result is always negative
      offset = (~self) >> start_index
      result = offset & mask
      ~result
    else
      # Shifts out the bits we want to ignore before applying the mask
      offset = self >> start_index
      offset & mask
    end
  end

  # Returns `true` if all bits in *mask* are set on `self`.
  #
  # ```
  # 0b0110.bits_set?(0b0110) # => true
  # 0b1101.bits_set?(0b0111) # => false
  # 0b1101.bits_set?(0b1100) # => true
  # ```
  def bits_set?(mask) : Bool
    (self & mask) == mask
  end

  # Returns the number of bits of this int value.
  #
  # “The number of bits” means that the bit position of the highest bit
  # which is different to the sign bit.
  # (The bit position of the bit 2**n is n+1.)
  # If there is no such bit (zero or minus one), zero is returned.
  #
  # I.e. This method returns `ceil(log2(self < 0 ? -self : self + 1))`.
  #
  # ```
  # 0.bit_length # => 0
  # 1.bit_length # => 1
  # 2.bit_length # => 2
  # 3.bit_length # => 2
  # 4.bit_length # => 3
  # 5.bit_length # => 3
  #
  # # The above is the same as
  # 0b0.bit_length   # => 0
  # 0b1.bit_length   # => 1
  # 0b10.bit_length  # => 2
  # 0b11.bit_length  # => 2
  # 0b100.bit_length # => 3
  # 0b101.bit_length # => 3
  # ```
  def bit_length : Int32
    x = self < 0 ? ~self : self

    if x.is_a?(Int::Primitive)
      Int32.new(sizeof(self) * 8 - x.leading_zeros_count)
    else
      # Safe fallback for any non-primitive Int type
      to_s(2).size
    end
  end

  # :nodoc:
  def next_power_of_two : self
    one = self.class.new!(1)

    bits = sizeof(self) * 8
    shift = bits &- (self &- 1).leading_zeros_count
    if self.is_a?(Int::Signed)
      shift = 0 if shift >= bits &- 1
    else
      shift = 0 if shift == bits
    end

    result = one << shift
    result >= self ? result : raise OverflowError.new
  end

  # Returns the greatest common divisor of `self` and *other*. Signed
  # integers may raise `OverflowError` if either has value equal to `MIN` of
  # its type.
  #
  # ```
  # 5.gcd(10) # => 5
  # 5.gcd(7)  # => 1
  # ```
  def gcd(other : self) : self
    # Implementation heavily inspired by
    # https://en.wikipedia.org/wiki/Binary_GCD_algorithm#Iterative_version_in_C
    u = self.abs
    v = other.abs
    return v if u == 0
    return u if v == 0

    # Let shift := lg K, where K is the greatest power of 2
    # dividing both u and v.
    shift = (u | v).trailing_zeros_count
    u = u.unsafe_shr(u.trailing_zeros_count)

    # From here on, u is always odd.
    loop do
      # remove all factors of 2 in v -- they are not common
      v = v.unsafe_shr(v.trailing_zeros_count)

      # Now u and v are both odd. Swap if necessary so u <= v,
      # then set v = v - u (which is even).
      u, v = v, u if u > v
      v &-= u
      break if v.zero?
    end

    # restore common factors of 2
    u.unsafe_shl shift
  end

  # Returns the least common multiple of `self` and *other*.
  #
  # Raises `OverflowError` in case of overflow.
  def lcm(other : Int)
    (self // gcd(other) * other).abs
  end

  def divisible_by?(num) : Bool
    remainder(num) == 0
  end

  def even? : Bool
    divisible_by? 2
  end

  def odd? : Bool
    !even?
  end

  def succ : self
    self + 1
  end

  def pred : self
    self - 1
  end

  def times(&block : self ->) : Nil
    i = self ^ self
    while i < self
      yield i
      i &+= 1
    end
  end

  def times
    TimesIterator(typeof(self)).new(self)
  end

  def upto(to, &block : self ->) : Nil
    return unless self <= to
    x = self
    while true
      yield x
      return if x == to
      x += 1
    end
  end

  def upto(to)
    UptoIterator(typeof(self), typeof(to)).new(self, to)
  end

  # Calls the given block with each integer value from self down to `to`.
  #
  # ```
  # 3.downto(1) do |i|
  #   puts i
  # end
  # ```
  #
  # Prints:
  #
  # ```text
  # 3
  # 2
  # 1
  # ```
  def downto(to, &block : self ->) : Nil
    return unless self >= to
    x = self
    while true
      yield x
      return if x == to
      x -= 1
    end
  end

  # Get an iterator for counting down from self to `to`.
  def downto(to)
    DowntoIterator(typeof(self), typeof(to)).new(self, to)
  end

  def to(to, &block : self ->) : Nil
    if self < to
      upto(to) { |i| yield i }
    elsif self > to
      downto(to) { |i| yield i }
    else
      yield self
    end
  end

  def to(to)
    self <= to ? upto(to) : downto(to)
  end

  def modulo(other)
    self % other
  end

  # Returns the digits of a number in a given base.
  # The digits are returned as an array with the least significant digit as the first array element.
  #
  # ```
  # 12345.digits      # => [5, 4, 3, 2, 1]
  # 12345.digits(7)   # => [4, 6, 6, 0, 5]
  # 12345.digits(100) # => [45, 23, 1]
  #
  # -12345.digits(7) # => ArgumentError
  # ```
  def digits(base = 10) : Array(Int32)
    if base < 2
      raise ArgumentError.new("Invalid base #{base}")
    end

    if self < 0
      raise ArgumentError.new("Can't request digits of negative number")
    end

    if self == 0
      return [0]
    end

    num = self

    digits_count = (Math.log(self.to_f + 1) / Math.log(base)).ceil.to_i

    ary = Array(Int32).new(digits_count)
    while num != 0
      ary << num.remainder(base).to_i
      num = num.tdiv(base)
    end
    ary
  end

  private DIGITS_DOWNCASE = "0123456789abcdefghijklmnopqrstuvwxyz"
  private DIGITS_UPCASE   = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"
  private DIGITS_BASE62   = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"

  # Returns a string representation of this integer.
  #
  # *base* specifies the radix of the returned string, and must be either 62 or
  # a number between 2 and 36. By default, digits above 9 are represented by
  # ASCII lowercase letters (`a` for 10, `b` for 11, etc.), but uppercase
  # letters may be used if *upcase* is `true`, unless base 62 is used. In that
  # case, lowercase letters are used for 10 to 35, and uppercase ones for 36 to
  # 61, and *upcase* must be `false`.
  #
  # *precision* specifies the minimum number of digits in the returned string.
  # If there are fewer digits than this number, the string is left-padded by
  # zeros. If `self` and *precision* are both zero, returns an empty string.
  #
  # ```
  # 1234.to_s                   # => "1234"
  # 1234.to_s(2)                # => "10011010010"
  # 1234.to_s(16)               # => "4d2"
  # 1234.to_s(16, upcase: true) # => "4D2"
  # 1234.to_s(36)               # => "ya"
  # 1234.to_s(62)               # => "jU"
  # 1234.to_s(precision: 2)     # => "1234"
  # 1234.to_s(precision: 6)     # => "001234"
  # ```
  def to_s(base : Int = 10, *, precision : Int = 1, upcase : Bool = false) : String
    raise ArgumentError.new("Invalid base #{base}") unless 2 <= base <= 36 || base == 62
    raise ArgumentError.new("upcase must be false for base 62") if upcase && base == 62
    raise ArgumentError.new("Precision must be non-negative") unless precision >= 0

    case {self, precision}
    when {0, 0}
      ""
    when {0, 1}
      "0"
    when {1, 1}
      "1"
    else
      internal_to_s(base, precision, upcase) do |ptr, count, negative|
        # reuse the `chars` buffer in `internal_to_s` if possible
        if precision <= count || precision <= 128
          if precision > count
            difference = precision - count
            ptr -= difference
            Slice.new(ptr, difference).fill('0'.ord.to_u8)
            count += difference
          end

          if negative
            ptr -= 1
            ptr.value = '-'.ord.to_u8
            count += 1
          end

          String.new(ptr, count, count)
        else
          len = precision + (negative ? 1 : 0)
          String.new(len) do |buffer|
            if negative
              buffer.value = '-'.ord.to_u8
              buffer += 1
            end

            Slice.new(buffer, precision - count).fill('0'.ord.to_u8)
            ptr.copy_to(buffer + precision - count, count)
            {len, len}
          end
        end
      end
    end
  end

  # Appends a string representation of this integer to the given *io*.
  #
  # *base* specifies the radix of the written string, and must be either 62 or
  # a number between 2 and 36. By default, digits above 9 are represented by
  # ASCII lowercase letters (`a` for 10, `b` for 11, etc.), but uppercase
  # letters may be used if *upcase* is `true`, unless base 62 is used. In that
  # case, lowercase letters are used for 10 to 35, and uppercase ones for 36 to
  # 61, and *upcase* must be `false`.
  #
  # *precision* specifies the minimum number of digits in the written string.
  # If there are fewer digits than this number, the string is left-padded by
  # zeros. If `self` and *precision* are both zero, returns an empty string.
  def to_s(io : IO, base : Int = 10, *, precision : Int = 1, upcase : Bool = false) : Nil
    raise ArgumentError.new("Invalid base #{base}") unless 2 <= base <= 36 || base == 62
    raise ArgumentError.new("upcase must be false for base 62") if upcase && base == 62
    raise ArgumentError.new("Precision must be non-negative") unless precision >= 0

    case {self, precision}
    when {0, 0}
      # do nothing
    when {0, 1}
      io << '0'
    when {1, 1}
      io << '1'
    else
      internal_to_s(base, precision, upcase) do |ptr, count, negative|
        io << '-' if negative
        if precision > count
          (precision - count).times { io << '0' }
        end
        io.write_string Slice.new(ptr, count)
      end
    end
  end

  private def internal_to_s(base, precision, upcase = false, &)
    # Given sizeof(self) <= 128 bits, we need at most 128 bytes for a base 2
    # representation, plus one byte for the negative sign (possibly used by the
    # string-returning overload).
    chars = uninitialized UInt8[129]
    ptr_end = chars.to_unsafe + 129
    ptr = ptr_end
    num = self

    neg = num < 0

    digits = (base == 62 ? DIGITS_BASE62 : (upcase ? DIGITS_UPCASE : DIGITS_DOWNCASE)).to_unsafe

    while num != 0
      ptr -= 1
      ptr.value = digits[num.remainder(base).abs]
      num = num.tdiv(base)
    end

    count = (ptr_end - ptr).to_i32
    yield ptr, count, neg
  end

  # Writes this integer to the given *io* in the given *format*.
  #
  # See also: `IO#write_bytes`.
  def to_io(io : IO, format : IO::ByteFormat) : Nil
    format.encode(self, io)
  end

  # Reads an integer from the given *io* in the given *format*.
  #
  # See also: `IO#read_bytes`.
  def self.from_io(io : IO, format : IO::ByteFormat) : self
    format.decode(self, io)
  end

  # Counts `1`-bits in the binary representation of this integer.
  #
  # ```
  # 5.popcount   # => 2
  # -15.popcount # => 29
  # ```
  abstract def popcount

  # Returns the number of trailing `0`-bits.
  abstract def trailing_zeros_count

  private class TimesIterator(T)
    include Iterator(T)

    @n : T
    @index : T

    def initialize(@n : T, @index = T.zero)
    end

    def next
      if @index < @n
        value = @index
        @index &+= 1
        value
      else
        stop
      end
    end
  end

  private class UptoIterator(T, N)
    include Iterator(T)

    @from : T
    @to : N
    @current : T
    @done : Bool

    def initialize(@from : T, @to : N)
      @current = @from
      @done = !(@from <= @to)
    end

    def next
      return stop if @done
      value = @current
      @done = @current == @to
      @current += 1 unless @done
      value
    end
  end

  private class DowntoIterator(T, N)
    include Iterator(T)

    @from : T
    @to : N
    @current : T
    @done : Bool

    def initialize(@from : T, @to : N)
      @current = @from
      @done = !(@from >= @to)
    end

    def next
      return stop if @done
      value = @current
      @done = @current == @to
      @current -= 1 unless @done
      value
    end
  end
end

struct Int8
  MIN = -128_i8
  MAX =  127_i8

  # Returns an `Int8` by invoking `to_i8` on *value*.
  # See `String#to_i` for more details.
  #
  # ```
  # Int8.new "20"                        # => 20
  # Int8.new "  20  ", whitespace: false # raises ArgumentError: Invalid Int8: "  20  "
  # ```
  def self.new(value : String, base : Int = 10, whitespace : Bool = true, underscore : Bool = false, prefix : Bool = false, strict : Bool = true, leading_zero_is_octal : Bool = false) : self
    value.to_i8 base: base, whitespace: whitespace, underscore: underscore, prefix: prefix, strict: strict, leading_zero_is_octal: leading_zero_is_octal
  end

  # Returns an `Int8` by invoking `to_i8` on *value*.
  def self.new(value) : self
    value.to_i8
  end

  # Returns an `Int8` by invoking `to_i8!` on *value*.
  def self.new!(value) : self
    value.to_i8!
  end

  Number.expand_div [Int8, UInt8, Int16, UInt16, Int32, UInt32, Int64, UInt64, Int128, UInt128], Float64
  Number.expand_div [Float32], Float32
  Number.expand_div [Float64], Float64

  def - : Int8
    0_i8 - self
  end

  # Returns `self` converted to a signed value of the same size.
  #
  # Simply returns `self` unmodified if `self` is already an `Int::Signed`.
  # Raises `OverflowError` in case of overflow.
  #
  # ```
  # 1_u32.to_signed # => 1_i32
  # 2_u16.to_signed # => 2_i16
  # 3_i64.to_signed # => 3_i64
  # ```
  def to_signed : Int8
    self
  end

  # Returns `self` converted to a signed value of the same size, wrapping in
  # case of overflow.
  #
  # Simply returns `self` unmodified if `self` is already an `Int::Signed`.
  #
  # ```
  # 1_u32.to_signed!     # => 1_i32
  # 65530_u16.to_signed! # => -6_i16
  # 3_i64.to_signed!     # => 3_i64
  # ```
  def to_signed! : Int8
    self
  end

  # Returns `self` converted to an unsigned value of the same size.
  #
  # Simply returns `self` unmodified if `self` is already an `Int::Unsigned`.
  # Raises `OverflowError` in case of overflow.
  #
  # ```
  # 1_i32.to_unsigned # => 1_u32
  # 2_i16.to_unsigned # => 2_u16
  # 3_u64.to_unsigned # => 3_u64
  # ```
  def to_unsigned : UInt8
    to_u8
  end

  # Returns `self` converted to an unsigned value of the same size, wrapping in
  # case of overflow.
  #
  # Simply returns `self` unmodified if `self` is already an `Int::Unsigned`.
  #
  # ```
  # 1_i32.to_unsigned!    # => 1_u32
  # (-6_i16).to_unsigned! # => 65530_u16
  # 3_u64.to_unsigned!    # => 3_u64
  # ```
  def to_unsigned! : UInt8
    to_u8!
  end

  # Returns the absolute value of `self` as an unsigned value of the same size.
  #
  # Returns `self` if `self` is already an `Int::Unsigned`. This method never
  # overflows.
  #
  # ```
  # 1_u32.abs_unsigned      # => 1_u32
  # 2_i32.abs_unsigned      # => 2_u32
  # -3_i8.abs_unsigned      # => 3_u8
  # Int16::MIN.abs_unsigned # => 32768_u16
  # ```
  def abs_unsigned : UInt8
    self < 0 ? 0_u8 &- self : to_u8!
  end

  # Returns the negative of `self` as a signed value of the same size.
  #
  # Returns `-self` if `self` is already an `Int::Signed`. Raises
  # `OverflowError` in case of overflow.
  #
  # ```
  # 1_i32.neg_signed      # => -1_i32
  # 2_u16.neg_signed      # => -2_i16
  # 128_u8.neg_signed     # => -128_i8
  # Int16::MIN.neg_signed # raises OverflowError
  # ```
  def neg_signed : self
    -self
  end

  def popcount : Int8
    Intrinsics.popcount8(self)
  end

  # Reverses the bits of `self`; the least significant bit becomes the most
  # significant, and vice-versa.
  #
  # ```
  # 0b01001011_u8.bit_reverse          # => 0b11010010
  # 0b1100100001100111_u16.bit_reverse # => 0b1110011000010011
  # ```
  def bit_reverse : self
    Intrinsics.bitreverse8(self).to_i8!
  end

  # Swaps the bytes of `self`; a little-endian value becomes a big-endian value,
  # and vice-versa. The bit order within each byte is unchanged.
  #
  # Has no effect on 8-bit integers.
  #
  # ```
  # 0x12_i8.byte_swap # => 0x12
  # ```
  def byte_swap : self
    self
  end

  # Returns the number of leading `0`-bits.
  def leading_zeros_count
    Intrinsics.countleading8(self, false)
  end

  def trailing_zeros_count
    Intrinsics.counttrailing8(self, false)
  end

  # Returns the bitwise rotation of `self` *n* times in the most significant
  # bit's direction. Negative shifts are equivalent to `rotate_right(-n)`.
  #
  # ```
  # 0b01001101_u8.rotate_left(3)  # => 0b01101010
  # 0b01001101_u8.rotate_left(8)  # => 0b01001101
  # 0b01001101_u8.rotate_left(11) # => 0b01101010
  # 0b01001101_u8.rotate_left(-1) # => 0b10100110
  # ```
  def rotate_left(n : Int) : self
    Intrinsics.fshl8(self, self, n.to_i8!).to_i8!
  end

  # Returns the bitwise rotation of `self` *n* times in the least significant
  # bit's direction. Negative shifts are equivalent to `rotate_left(-n)`.
  #
  # ```
  # 0b01001101_u8.rotate_right(3)  # => 0b10101001
  # 0b01001101_u8.rotate_right(8)  # => 0b01001101
  # 0b01001101_u8.rotate_right(11) # => 0b10101001
  # 0b01001101_u8.rotate_right(-1) # => 0b10011010
  # ```
  def rotate_right(n : Int) : self
    Intrinsics.fshr8(self, self, n.to_i8!).to_i8!
  end

  def clone
    self
  end
end

struct Int16
  MIN = -32768_i16
  MAX =  32767_i16

  # Returns an `Int16` by invoking `to_i16` on *value*.
  # See `String#to_i` for more details.
  #
  # ```
  # Int16.new "20"                        # => 20
  # Int16.new "  20  ", whitespace: false # raises ArgumentError: Invalid Int16: "  20  "
  # ```
  def self.new(value : String, base : Int = 10, whitespace : Bool = true, underscore : Bool = false, prefix : Bool = false, strict : Bool = true, leading_zero_is_octal : Bool = false) : self
    value.to_i16 base: base, whitespace: whitespace, underscore: underscore, prefix: prefix, strict: strict, leading_zero_is_octal: leading_zero_is_octal
  end

  # Returns an `Int16` by invoking `to_i16` on *value*.
  def self.new(value) : self
    value.to_i16
  end

  # Returns an `Int16` by invoking `to_i16!` on *value*.
  def self.new!(value) : self
    value.to_i16!
  end

  Number.expand_div [Int8, UInt8, Int16, UInt16, Int32, UInt32, Int64, UInt64, Int128, UInt128], Float64
  Number.expand_div [Float32], Float32
  Number.expand_div [Float64], Float64

  def - : Int16
    0_i16 - self
  end

  # Returns `self` converted to a signed value of the same size.
  #
  # Simply returns `self` unmodified if `self` is already an `Int::Signed`.
  # Raises `OverflowError` in case of overflow.
  #
  # ```
  # 1_u32.to_signed # => 1_i32
  # 2_u16.to_signed # => 2_i16
  # 3_i64.to_signed # => 3_i64
  # ```
  def to_signed : Int16
    self
  end

  # Returns `self` converted to a signed value of the same size, wrapping in
  # case of overflow.
  #
  # Simply returns `self` unmodified if `self` is already an `Int::Signed`.
  #
  # ```
  # 1_u32.to_signed!     # => 1_i32
  # 65530_u16.to_signed! # => -6_i16
  # 3_i64.to_signed!     # => 3_i64
  # ```
  def to_signed! : Int16
    self
  end

  # Returns `self` converted to an unsigned value of the same size.
  #
  # Simply returns `self` unmodified if `self` is already an `Int::Unsigned`.
  # Raises `OverflowError` in case of overflow.
  #
  # ```
  # 1_i32.to_unsigned # => 1_u32
  # 2_i16.to_unsigned # => 2_u16
  # 3_u64.to_unsigned # => 3_u64
  # ```
  def to_unsigned : UInt16
    to_u16
  end

  # Returns `self` converted to an unsigned value of the same size, wrapping in
  # case of overflow.
  #
  # Simply returns `self` unmodified if `self` is already an `Int::Unsigned`.
  #
  # ```
  # 1_i32.to_unsigned!    # => 1_u32
  # (-6_i16).to_unsigned! # => 65530_u16
  # 3_u64.to_unsigned!    # => 3_u64
  # ```
  def to_unsigned! : UInt16
    to_u16!
  end

  # Returns the absolute value of `self` as an unsigned value of the same size.
  #
  # Returns `self` if `self` is already an `Int::Unsigned`. This method never
  # overflows.
  #
  # ```
  # 1_u32.abs_unsigned      # => 1_u32
  # 2_i32.abs_unsigned      # => 2_u32
  # -3_i8.abs_unsigned      # => 3_u8
  # Int16::MIN.abs_unsigned # => 32768_u16
  # ```
  def abs_unsigned : UInt16
    self < 0 ? 0_u16 &- self : to_u16!
  end

  # Returns the negative of `self` as a signed value of the same size.
  #
  # Returns `-self` if `self` is already an `Int::Signed`. Raises
  # `OverflowError` in case of overflow.
  #
  # ```
  # 1_i32.neg_signed      # => -1_i32
  # 2_u16.neg_signed      # => -2_i16
  # 128_u8.neg_signed     # => -128_i8
  # Int16::MIN.neg_signed # raises OverflowError
  # ```
  def neg_signed : self
    -self
  end

  def popcount : Int16
    Intrinsics.popcount16(self)
  end

  # Reverses the bits of `self`; the least significant bit becomes the most
  # significant, and vice-versa.
  #
  # ```
  # 0b01001011_u8.bit_reverse          # => 0b11010010
  # 0b1100100001100111_u16.bit_reverse # => 0b1110011000010011
  # ```
  def bit_reverse : self
    Intrinsics.bitreverse16(self).to_i16!
  end

  # Swaps the bytes of `self`; a little-endian value becomes a big-endian value,
  # and vice-versa. The bit order within each byte is unchanged.
  #
  # Has no effect on 8-bit integers.
  #
  # ```
  # 0x1234_i16.byte_swap # => 0x3412
  # ```
  def byte_swap : self
    Intrinsics.bswap16(self).to_i16!
  end

  # Returns the number of leading `0`-bits.
  def leading_zeros_count
    Intrinsics.countleading16(self, false)
  end

  def trailing_zeros_count
    Intrinsics.counttrailing16(self, false)
  end

  # Returns the bitwise rotation of `self` *n* times in the most significant
  # bit's direction. Negative shifts are equivalent to `rotate_right(-n)`.
  #
  # ```
  # 0b01001101_u8.rotate_left(3)  # => 0b01101010
  # 0b01001101_u8.rotate_left(8)  # => 0b01001101
  # 0b01001101_u8.rotate_left(11) # => 0b01101010
  # 0b01001101_u8.rotate_left(-1) # => 0b10100110
  # ```
  def rotate_left(n : Int) : self
    Intrinsics.fshl16(self, self, n.to_i16!).to_i16!
  end

  # Returns the bitwise rotation of `self` *n* times in the least significant
  # bit's direction. Negative shifts are equivalent to `rotate_left(-n)`.
  #
  # ```
  # 0b01001101_u8.rotate_right(3)  # => 0b10101001
  # 0b01001101_u8.rotate_right(8)  # => 0b01001101
  # 0b01001101_u8.rotate_right(11) # => 0b10101001
  # 0b01001101_u8.rotate_right(-1) # => 0b10011010
  # ```
  def rotate_right(n : Int) : self
    Intrinsics.fshr16(self, self, n.to_i16!).to_i16!
  end

  def clone
    self
  end
end

struct Int32
  MIN = -2147483648_i32
  MAX =  2147483647_i32

  # Returns an `Int32` by invoking `to_i32` on *value*.
  # See `String#to_i` for more details.
  #
  # ```
  # Int32.new "20"                        # => 20
  # Int32.new "  20  ", whitespace: false # raises ArgumentError: Invalid Int32: "  20  "
  # ```
  def self.new(value : String, base : Int = 10, whitespace : Bool = true, underscore : Bool = false, prefix : Bool = false, strict : Bool = true, leading_zero_is_octal : Bool = false) : self
    value.to_i32 base: base, whitespace: whitespace, underscore: underscore, prefix: prefix, strict: strict, leading_zero_is_octal: leading_zero_is_octal
  end

  # Returns an `Int32` by invoking `to_i32` on *value*.
  def self.new(value) : self
    value.to_i32
  end

  # Returns an `Int32` by invoking `to_i32!` on *value*.
  def self.new!(value) : self
    value.to_i32!
  end

  Number.expand_div [Int8, UInt8, Int16, UInt16, Int32, UInt32, Int64, UInt64, Int128, UInt128], Float64
  Number.expand_div [Float32], Float32
  Number.expand_div [Float64], Float64

  def - : Int32
    0 - self
  end

  # Returns `self` converted to a signed value of the same size.
  #
  # Simply returns `self` unmodified if `self` is already an `Int::Signed`.
  # Raises `OverflowError` in case of overflow.
  #
  # ```
  # 1_u32.to_signed # => 1_i32
  # 2_u16.to_signed # => 2_i16
  # 3_i64.to_signed # => 3_i64
  # ```
  def to_signed : Int32
    self
  end

  # Returns `self` converted to a signed value of the same size, wrapping in
  # case of overflow.
  #
  # Simply returns `self` unmodified if `self` is already an `Int::Signed`.
  #
  # ```
  # 1_u32.to_signed!     # => 1_i32
  # 65530_u16.to_signed! # => -6_i16
  # 3_i64.to_signed!     # => 3_i64
  # ```
  def to_signed! : Int32
    self
  end

  # Returns `self` converted to an unsigned value of the same size.
  #
  # Simply returns `self` unmodified if `self` is already an `Int::Unsigned`.
  # Raises `OverflowError` in case of overflow.
  #
  # ```
  # 1_i32.to_unsigned # => 1_u32
  # 2_i16.to_unsigned # => 2_u16
  # 3_u64.to_unsigned # => 3_u64
  # ```
  def to_unsigned : UInt32
    to_u32
  end

  # Returns `self` converted to an unsigned value of the same size, wrapping in
  # case of overflow.
  #
  # Simply returns `self` unmodified if `self` is already an `Int::Unsigned`.
  #
  # ```
  # 1_i32.to_unsigned!    # => 1_u32
  # (-6_i16).to_unsigned! # => 65530_u16
  # 3_u64.to_unsigned!    # => 3_u64
  # ```
  def to_unsigned! : UInt32
    to_u32!
  end

  # Returns the absolute value of `self` as an unsigned value of the same size.
  #
  # Returns `self` if `self` is already an `Int::Unsigned`. This method never
  # overflows.
  #
  # ```
  # 1_u32.abs_unsigned      # => 1_u32
  # 2_i32.abs_unsigned      # => 2_u32
  # -3_i8.abs_unsigned      # => 3_u8
  # Int16::MIN.abs_unsigned # => 32768_u16
  # ```
  def abs_unsigned : UInt32
    self < 0 ? 0_u32 &- self : to_u32!
  end

  # Returns the negative of `self` as a signed value of the same size.
  #
  # Returns `-self` if `self` is already an `Int::Signed`. Raises
  # `OverflowError` in case of overflow.
  #
  # ```
  # 1_i32.neg_signed      # => -1_i32
  # 2_u16.neg_signed      # => -2_i16
  # 128_u8.neg_signed     # => -128_i8
  # Int16::MIN.neg_signed # raises OverflowError
  # ```
  def neg_signed : self
    -self
  end

  def popcount : Int32
    Intrinsics.popcount32(self)
  end

  # Reverses the bits of `self`; the least significant bit becomes the most
  # significant, and vice-versa.
  #
  # ```
  # 0b01001011_u8.bit_reverse          # => 0b11010010
  # 0b1100100001100111_u16.bit_reverse # => 0b1110011000010011
  # ```
  def bit_reverse : self
    Intrinsics.bitreverse32(self).to_i32!
  end

  # Swaps the bytes of `self`; a little-endian value becomes a big-endian value,
  # and vice-versa. The bit order within each byte is unchanged.
  #
  # Has no effect on 8-bit integers.
  #
  # ```
  # 0x12345678_i32.byte_swap # => 0x78563412
  # ```
  def byte_swap : self
    Intrinsics.bswap32(self).to_i32!
  end

  # Returns the number of leading `0`-bits.
  def leading_zeros_count
    Intrinsics.countleading32(self, false)
  end

  def trailing_zeros_count
    Intrinsics.counttrailing32(self, false)
  end

  # Returns the bitwise rotation of `self` *n* times in the most significant
  # bit's direction. Negative shifts are equivalent to `rotate_right(-n)`.
  #
  # ```
  # 0b01001101_u8.rotate_left(3)  # => 0b01101010
  # 0b01001101_u8.rotate_left(8)  # => 0b01001101
  # 0b01001101_u8.rotate_left(11) # => 0b01101010
  # 0b01001101_u8.rotate_left(-1) # => 0b10100110
  # ```
  def rotate_left(n : Int) : self
    Intrinsics.fshl32(self, self, n.to_i32!).to_i32!
  end

  # Returns the bitwise rotation of `self` *n* times in the least significant
  # bit's direction. Negative shifts are equivalent to `rotate_left(-n)`.
  #
  # ```
  # 0b01001101_u8.rotate_right(3)  # => 0b10101001
  # 0b01001101_u8.rotate_right(8)  # => 0b01001101
  # 0b01001101_u8.rotate_right(11) # => 0b10101001
  # 0b01001101_u8.rotate_right(-1) # => 0b10011010
  # ```
  def rotate_right(n : Int) : self
    Intrinsics.fshr32(self, self, n.to_i32!).to_i32!
  end

  def clone
    self
  end
end

struct Int64
  MIN = -9223372036854775808_i64
  MAX =  9223372036854775807_i64

  # Returns an `Int64` by invoking `to_i64` on *value*.
  # See `String#to_i` for more details.
  #
  # ```
  # Int64.new "20"                        # => 20
  # Int64.new "  20  ", whitespace: false # raises ArgumentError: Invalid Int64: "  20  "
  # ```
  def self.new(value : String, base : Int = 10, whitespace : Bool = true, underscore : Bool = false, prefix : Bool = false, strict : Bool = true, leading_zero_is_octal : Bool = false) : self
    value.to_i64 base: base, whitespace: whitespace, underscore: underscore, prefix: prefix, strict: strict, leading_zero_is_octal: leading_zero_is_octal
  end

  # Returns an `Int64` by invoking `to_i64` on *value*.
  def self.new(value) : self
    value.to_i64
  end

  # Returns an `Int64` by invoking `to_i64!` on *value*.
  def self.new!(value) : self
    value.to_i64!
  end

  Number.expand_div [Int8, UInt8, Int16, UInt16, Int32, UInt32, Int64, UInt64, Int128, UInt128], Float64
  Number.expand_div [Float32], Float32
  Number.expand_div [Float64], Float64

  def - : Int64
    0_i64 - self
  end

  # Returns `self` converted to a signed value of the same size.
  #
  # Simply returns `self` unmodified if `self` is already an `Int::Signed`.
  # Raises `OverflowError` in case of overflow.
  #
  # ```
  # 1_u32.to_signed # => 1_i32
  # 2_u16.to_signed # => 2_i16
  # 3_i64.to_signed # => 3_i64
  # ```
  def to_signed : Int64
    self
  end

  # Returns `self` converted to a signed value of the same size, wrapping in
  # case of overflow.
  #
  # Simply returns `self` unmodified if `self` is already an `Int::Signed`.
  #
  # ```
  # 1_u32.to_signed!     # => 1_i32
  # 65530_u16.to_signed! # => -6_i16
  # 3_i64.to_signed!     # => 3_i64
  # ```
  def to_signed! : Int64
    self
  end

  # Returns `self` converted to an unsigned value of the same size.
  #
  # Simply returns `self` unmodified if `self` is already an `Int::Unsigned`.
  # Raises `OverflowError` in case of overflow.
  #
  # ```
  # 1_i32.to_unsigned # => 1_u32
  # 2_i16.to_unsigned # => 2_u16
  # 3_u64.to_unsigned # => 3_u64
  # ```
  def to_unsigned : UInt64
    to_u64
  end

  # Returns `self` converted to an unsigned value of the same size, wrapping in
  # case of overflow.
  #
  # Simply returns `self` unmodified if `self` is already an `Int::Unsigned`.
  #
  # ```
  # 1_i32.to_unsigned!    # => 1_u32
  # (-6_i16).to_unsigned! # => 65530_u16
  # 3_u64.to_unsigned!    # => 3_u64
  # ```
  def to_unsigned! : UInt64
    to_u64!
  end

  # Returns the absolute value of `self` as an unsigned value of the same size.
  #
  # Returns `self` if `self` is already an `Int::Unsigned`. This method never
  # overflows.
  #
  # ```
  # 1_u32.abs_unsigned      # => 1_u32
  # 2_i32.abs_unsigned      # => 2_u32
  # -3_i8.abs_unsigned      # => 3_u8
  # Int16::MIN.abs_unsigned # => 32768_u16
  # ```
  def abs_unsigned : UInt64
    self < 0 ? 0_u64 &- self : to_u64!
  end

  # Returns the negative of `self` as a signed value of the same size.
  #
  # Returns `-self` if `self` is already an `Int::Signed`. Raises
  # `OverflowError` in case of overflow.
  #
  # ```
  # 1_i32.neg_signed      # => -1_i32
  # 2_u16.neg_signed      # => -2_i16
  # 128_u8.neg_signed     # => -128_i8
  # Int16::MIN.neg_signed # raises OverflowError
  # ```
  def neg_signed : self
    -self
  end

  def popcount : Int64
    Intrinsics.popcount64(self)
  end

  # Reverses the bits of `self`; the least significant bit becomes the most
  # significant, and vice-versa.
  #
  # ```
  # 0b01001011_u8.bit_reverse          # => 0b11010010
  # 0b1100100001100111_u16.bit_reverse # => 0b1110011000010011
  # ```
  def bit_reverse : self
    Intrinsics.bitreverse64(self).to_i64!
  end

  # Swaps the bytes of `self`; a little-endian value becomes a big-endian value,
  # and vice-versa. The bit order within each byte is unchanged.
  #
  # Has no effect on 8-bit integers.
  #
  # ```
  # 0x12345678_i64.byte_swap         # => 0x7856341200000000
  # 0x123456789ABCDEF0_i64.byte_swap # => -0xf21436587a9cbee
  # ```
  def byte_swap : self
    Intrinsics.bswap64(self).to_i64!
  end

  # Returns the number of leading `0`-bits.
  def leading_zeros_count
    Intrinsics.countleading64(self, false)
  end

  def trailing_zeros_count
    Intrinsics.counttrailing64(self, false)
  end

  # Returns the bitwise rotation of `self` *n* times in the most significant
  # bit's direction. Negative shifts are equivalent to `rotate_right(-n)`.
  #
  # ```
  # 0b01001101_u8.rotate_left(3)  # => 0b01101010
  # 0b01001101_u8.rotate_left(8)  # => 0b01001101
  # 0b01001101_u8.rotate_left(11) # => 0b01101010
  # 0b01001101_u8.rotate_left(-1) # => 0b10100110
  # ```
  def rotate_left(n : Int) : self
    Intrinsics.fshl64(self, self, n.to_i64!).to_i64!
  end

  # Returns the bitwise rotation of `self` *n* times in the least significant
  # bit's direction. Negative shifts are equivalent to `rotate_left(-n)`.
  #
  # ```
  # 0b01001101_u8.rotate_right(3)  # => 0b10101001
  # 0b01001101_u8.rotate_right(8)  # => 0b01001101
  # 0b01001101_u8.rotate_right(11) # => 0b10101001
  # 0b01001101_u8.rotate_right(-1) # => 0b10011010
  # ```
  def rotate_right(n : Int) : self
    Intrinsics.fshr64(self, self, n.to_i64!).to_i64!
  end

  def clone
    self
  end
end

struct Int128
  MIN = -170141183460469231731687303715884105728_i128
  MAX =  170141183460469231731687303715884105727_i128

  # Returns an `Int128` by invoking `to_i128` on *value*.
  # See `String#to_i` for more details.
  #
  # ```
  # Int128.new "20"                        # => 20
  # Int128.new "  20  ", whitespace: false # raises ArgumentError: Invalid Int128: "  20  "
  # ```
  def self.new(value : String, base : Int = 10, whitespace : Bool = true, underscore : Bool = false, prefix : Bool = false, strict : Bool = true, leading_zero_is_octal : Bool = false) : self
    value.to_i128 base: base, whitespace: whitespace, underscore: underscore, prefix: prefix, strict: strict, leading_zero_is_octal: leading_zero_is_octal
  end

  # Returns an `Int128` by invoking `to_i128` on *value*.
  def self.new(value) : self
    value.to_i128
  end

  # Returns an `Int128` by invoking `to_i128!` on *value*.
  def self.new!(value) : self
    value.to_i128!
  end

  Number.expand_div [Int8, UInt8, Int16, UInt16, Int32, UInt32, Int64, UInt64, Int128, UInt128], Float64
  Number.expand_div [Float32], Float32
  Number.expand_div [Float64], Float64

  def -
    0_i128 - self
  end

  # Returns `self` converted to a signed value of the same size.
  #
  # Simply returns `self` unmodified if `self` is already an `Int::Signed`.
  # Raises `OverflowError` in case of overflow.
  #
  # ```
  # 1_u32.to_signed # => 1_i32
  # 2_u16.to_signed # => 2_i16
  # 3_i64.to_signed # => 3_i64
  # ```
  def to_signed : Int128
    self
  end

  # Returns `self` converted to a signed value of the same size, wrapping in
  # case of overflow.
  #
  # Simply returns `self` unmodified if `self` is already an `Int::Signed`.
  #
  # ```
  # 1_u32.to_signed!     # => 1_i32
  # 65530_u16.to_signed! # => -6_i16
  # 3_i64.to_signed!     # => 3_i64
  # ```
  def to_signed! : Int128
    self
  end

  # Returns `self` converted to an unsigned value of the same size.
  #
  # Simply returns `self` unmodified if `self` is already an `Int::Unsigned`.
  # Raises `OverflowError` in case of overflow.
  #
  # ```
  # 1_i32.to_unsigned # => 1_u32
  # 2_i16.to_unsigned # => 2_u16
  # 3_u64.to_unsigned # => 3_u64
  # ```
  def to_unsigned : UInt128
    to_u128
  end

  # Returns `self` converted to an unsigned value of the same size, wrapping in
  # case of overflow.
  #
  # Simply returns `self` unmodified if `self` is already an `Int::Unsigned`.
  #
  # ```
  # 1_i32.to_unsigned!    # => 1_u32
  # (-6_i16).to_unsigned! # => 65530_u16
  # 3_u64.to_unsigned!    # => 3_u64
  # ```
  def to_unsigned! : UInt128
    to_u128!
  end

  # Returns the absolute value of `self` as an unsigned value of the same size.
  #
  # Returns `self` if `self` is already an `Int::Unsigned`. This method never
  # overflows.
  #
  # ```
  # 1_u32.abs_unsigned      # => 1_u32
  # 2_i32.abs_unsigned      # => 2_u32
  # -3_i8.abs_unsigned      # => 3_u8
  # Int16::MIN.abs_unsigned # => 32768_u16
  # ```
  def abs_unsigned : UInt128
    self < 0 ? UInt128.new(0) &- self : to_u128!
  end

  # Returns the negative of `self` as a signed value of the same size.
  #
  # Returns `-self` if `self` is already an `Int::Signed`. Raises
  # `OverflowError` in case of overflow.
  #
  # ```
  # 1_i32.neg_signed      # => -1_i32
  # 2_u16.neg_signed      # => -2_i16
  # 128_u8.neg_signed     # => -128_i8
  # Int16::MIN.neg_signed # raises OverflowError
  # ```
  def neg_signed : self
    -self
  end

  def popcount
    Intrinsics.popcount128(self)
  end

  # Reverses the bits of `self`; the least significant bit becomes the most
  # significant, and vice-versa.
  #
  # ```
  # 0b01001011_u8.bit_reverse          # => 0b11010010
  # 0b1100100001100111_u16.bit_reverse # => 0b1110011000010011
  # ```
  def bit_reverse : self
    Intrinsics.bitreverse128(self).to_i128!
  end

  # Swaps the bytes of `self`; a little-endian value becomes a big-endian value,
  # and vice-versa. The bit order within each byte is unchanged.
  #
  # Has no effect on 8-bit integers.
  #
  # ```
  # 0x123456789_i128.byte_swap # ＝> -0x7698badcff0000000000000000000000
  # ```
  def byte_swap : self
    Intrinsics.bswap128(self).to_i128!
  end

  # Returns the number of leading `0`-bits.
  def leading_zeros_count
    Intrinsics.countleading128(self, false)
  end

  def trailing_zeros_count
    Intrinsics.counttrailing128(self, false)
  end

  # Returns the bitwise rotation of `self` *n* times in the most significant
  # bit's direction. Negative shifts are equivalent to `rotate_right(-n)`.
  #
  # ```
  # 0b01001101_u8.rotate_left(3)  # => 0b01101010
  # 0b01001101_u8.rotate_left(8)  # => 0b01001101
  # 0b01001101_u8.rotate_left(11) # => 0b01101010
  # 0b01001101_u8.rotate_left(-1) # => 0b10100110
  # ```
  def rotate_left(n : Int) : self
    Intrinsics.fshl128(self, self, n.to_i128!).to_i128!
  end

  # Returns the bitwise rotation of `self` *n* times in the least significant
  # bit's direction. Negative shifts are equivalent to `rotate_left(-n)`.
  #
  # ```
  # 0b01001101_u8.rotate_right(3)  # => 0b10101001
  # 0b01001101_u8.rotate_right(8)  # => 0b01001101
  # 0b01001101_u8.rotate_right(11) # => 0b10101001
  # 0b01001101_u8.rotate_right(-1) # => 0b10011010
  # ```
  def rotate_right(n : Int) : self
    Intrinsics.fshr128(self, self, n.to_i128!).to_i128!
  end

  def clone
    self
  end
end

struct UInt8
  MIN =   0_u8
  MAX = 255_u8

  # Returns an `UInt8` by invoking `to_u8` on *value*.
  # See `String#to_i` for more details.
  #
  # ```
  # UInt8.new "20"                        # => 20
  # UInt8.new "  20  ", whitespace: false # raises ArgumentError: Invalid UInt8: "  20  "
  # ```
  def self.new(value : String, base : Int = 10, whitespace : Bool = true, underscore : Bool = false, prefix : Bool = false, strict : Bool = true, leading_zero_is_octal : Bool = false) : self
    value.to_u8 base: base, whitespace: whitespace, underscore: underscore, prefix: prefix, strict: strict, leading_zero_is_octal: leading_zero_is_octal
  end

  # Returns an `UInt8` by invoking `to_u8` on *value*.
  def self.new(value) : self
    value.to_u8
  end

  # Returns an `UInt8` by invoking `to_u8!` on *value*.
  def self.new!(value) : self
    value.to_u8!
  end

  Number.expand_div [Int8, UInt8, Int16, UInt16, Int32, UInt32, Int64, UInt64, Int128, UInt128], Float64
  Number.expand_div [Float32], Float32
  Number.expand_div [Float64], Float64

  def &- : UInt8
    0_u8 &- self
  end

  # Returns `self` converted to a signed value of the same size.
  #
  # Simply returns `self` unmodified if `self` is already an `Int::Signed`.
  # Raises `OverflowError` in case of overflow.
  #
  # ```
  # 1_u32.to_signed # => 1_i32
  # 2_u16.to_signed # => 2_i16
  # 3_i64.to_signed # => 3_i64
  # ```
  def to_signed : Int8
    to_i8
  end

  # Returns `self` converted to a signed value of the same size, wrapping in
  # case of overflow.
  #
  # Simply returns `self` unmodified if `self` is already an `Int::Signed`.
  #
  # ```
  # 1_u32.to_signed!     # => 1_i32
  # 65530_u16.to_signed! # => -6_i16
  # 3_i64.to_signed!     # => 3_i64
  # ```
  def to_signed! : Int8
    to_i8!
  end

  # Returns `self` converted to an unsigned value of the same size.
  #
  # Simply returns `self` unmodified if `self` is already an `Int::Unsigned`.
  # Raises `OverflowError` in case of overflow.
  #
  # ```
  # 1_i32.to_unsigned # => 1_u32
  # 2_i16.to_unsigned # => 2_u16
  # 3_u64.to_unsigned # => 3_u64
  # ```
  def to_unsigned : UInt8
    self
  end

  # Returns `self` converted to an unsigned value of the same size, wrapping in
  # case of overflow.
  #
  # Simply returns `self` unmodified if `self` is already an `Int::Unsigned`.
  #
  # ```
  # 1_i32.to_unsigned!    # => 1_u32
  # (-6_i16).to_unsigned! # => 65530_u16
  # 3_u64.to_unsigned!    # => 3_u64
  # ```
  def to_unsigned! : UInt8
    self
  end

  def abs : self
    self
  end

  # Returns the absolute value of `self` as an unsigned value of the same size.
  #
  # Returns `self` if `self` is already an `Int::Unsigned`. This method never
  # overflows.
  #
  # ```
  # 1_u32.abs_unsigned      # => 1_u32
  # 2_i32.abs_unsigned      # => 2_u32
  # -3_i8.abs_unsigned      # => 3_u8
  # Int16::MIN.abs_unsigned # => 32768_u16
  # ```
  def abs_unsigned : self
    self
  end

  # Returns the negative of `self` as a signed value of the same size.
  #
  # Returns `-self` if `self` is already an `Int::Signed`. Raises
  # `OverflowError` in case of overflow.
  #
  # ```
  # 1_i32.neg_signed      # => -1_i32
  # 2_u16.neg_signed      # => -2_i16
  # 128_u8.neg_signed     # => -128_i8
  # Int16::MIN.neg_signed # raises OverflowError
  # ```
  def neg_signed : Int8
    0_i8 - self
  end

  def popcount : Int8
    Intrinsics.popcount8(self)
  end

  # Reverses the bits of `self`; the least significant bit becomes the most
  # significant, and vice-versa.
  #
  # ```
  # 0b01001011_u8.bit_reverse          # => 0b11010010
  # 0b1100100001100111_u16.bit_reverse # => 0b1110011000010011
  # ```
  def bit_reverse : self
    Intrinsics.bitreverse8(self)
  end

  # Swaps the bytes of `self`; a little-endian value becomes a big-endian value,
  # and vice-versa. The bit order within each byte is unchanged.
  #
  # Has no effect on 8-bit integers.
  #
  # ```
  # 0x12_u8.byte_swap # => 0x12
  # ```
  def byte_swap : self
    self
  end

  # Returns the number of leading `0`-bits.
  def leading_zeros_count
    Intrinsics.countleading8(self, false)
  end

  def trailing_zeros_count
    Intrinsics.counttrailing8(self, false)
  end

  # Returns the bitwise rotation of `self` *n* times in the most significant
  # bit's direction. Negative shifts are equivalent to `rotate_right(-n)`.
  #
  # ```
  # 0b01001101_u8.rotate_left(3)  # => 0b01101010
  # 0b01001101_u8.rotate_left(8)  # => 0b01001101
  # 0b01001101_u8.rotate_left(11) # => 0b01101010
  # 0b01001101_u8.rotate_left(-1) # => 0b10100110
  # ```
  def rotate_left(n : Int) : self
    Intrinsics.fshl8(self, self, n.to_u8!)
  end

  # Returns the bitwise rotation of `self` *n* times in the least significant
  # bit's direction. Negative shifts are equivalent to `rotate_left(-n)`.
  #
  # ```
  # 0b01001101_u8.rotate_right(3)  # => 0b10101001
  # 0b01001101_u8.rotate_right(8)  # => 0b01001101
  # 0b01001101_u8.rotate_right(11) # => 0b10101001
  # 0b01001101_u8.rotate_right(-1) # => 0b10011010
  # ```
  def rotate_right(n : Int) : self
    Intrinsics.fshr8(self, self, n.to_u8!)
  end

  def clone
    self
  end
end

struct UInt16
  MIN =     0_u16
  MAX = 65535_u16

  # Returns an `UInt16` by invoking `to_u16` on *value*.
  # See `String#to_i` for more details.
  #
  # ```
  # UInt16.new "20"                        # => 20
  # UInt16.new "  20  ", whitespace: false # raises ArgumentError: Invalid UInt16: "  20  "
  # ```
  def self.new(value : String, base : Int = 10, whitespace : Bool = true, underscore : Bool = false, prefix : Bool = false, strict : Bool = true, leading_zero_is_octal : Bool = false) : self
    value.to_u16 base: base, whitespace: whitespace, underscore: underscore, prefix: prefix, strict: strict, leading_zero_is_octal: leading_zero_is_octal
  end

  # Returns an `UInt16` by invoking `to_u16` on *value*.
  def self.new(value) : self
    value.to_u16
  end

  # Returns an `UInt16` by invoking `to_u16!` on *value*.
  def self.new!(value) : self
    value.to_u16!
  end

  Number.expand_div [Int8, UInt8, Int16, UInt16, Int32, UInt32, Int64, UInt64, Int128, UInt128], Float64
  Number.expand_div [Float32], Float32
  Number.expand_div [Float64], Float64

  def &- : UInt16
    0_u16 &- self
  end

  # Returns `self` converted to a signed value of the same size.
  #
  # Simply returns `self` unmodified if `self` is already an `Int::Signed`.
  # Raises `OverflowError` in case of overflow.
  #
  # ```
  # 1_u32.to_signed # => 1_i32
  # 2_u16.to_signed # => 2_i16
  # 3_i64.to_signed # => 3_i64
  # ```
  def to_signed : Int16
    to_i16
  end

  # Returns `self` converted to a signed value of the same size, wrapping in
  # case of overflow.
  #
  # Simply returns `self` unmodified if `self` is already an `Int::Signed`.
  #
  # ```
  # 1_u32.to_signed!     # => 1_i32
  # 65530_u16.to_signed! # => -6_i16
  # 3_i64.to_signed!     # => 3_i64
  # ```
  def to_signed! : Int16
    to_i16!
  end

  # Returns `self` converted to an unsigned value of the same size.
  #
  # Simply returns `self` unmodified if `self` is already an `Int::Unsigned`.
  # Raises `OverflowError` in case of overflow.
  #
  # ```
  # 1_i32.to_unsigned # => 1_u32
  # 2_i16.to_unsigned # => 2_u16
  # 3_u64.to_unsigned # => 3_u64
  # ```
  def to_unsigned : UInt16
    self
  end

  # Returns `self` converted to an unsigned value of the same size, wrapping in
  # case of overflow.
  #
  # Simply returns `self` unmodified if `self` is already an `Int::Unsigned`.
  #
  # ```
  # 1_i32.to_unsigned!    # => 1_u32
  # (-6_i16).to_unsigned! # => 65530_u16
  # 3_u64.to_unsigned!    # => 3_u64
  # ```
  def to_unsigned! : UInt16
    self
  end

  def abs : self
    self
  end

  # Returns the absolute value of `self` as an unsigned value of the same size.
  #
  # Returns `self` if `self` is already an `Int::Unsigned`. This method never
  # overflows.
  #
  # ```
  # 1_u32.abs_unsigned      # => 1_u32
  # 2_i32.abs_unsigned      # => 2_u32
  # -3_i8.abs_unsigned      # => 3_u8
  # Int16::MIN.abs_unsigned # => 32768_u16
  # ```
  def abs_unsigned : self
    self
  end

  # Returns the negative of `self` as a signed value of the same size.
  #
  # Returns `-self` if `self` is already an `Int::Signed`. Raises
  # `OverflowError` in case of overflow.
  #
  # ```
  # 1_i32.neg_signed      # => -1_i32
  # 2_u16.neg_signed      # => -2_i16
  # 128_u8.neg_signed     # => -128_i8
  # Int16::MIN.neg_signed # raises OverflowError
  # ```
  def neg_signed : Int16
    0_i16 - self
  end

  def popcount : Int16
    Intrinsics.popcount16(self)
  end

  # Reverses the bits of `self`; the least significant bit becomes the most
  # significant, and vice-versa.
  #
  # ```
  # 0b01001011_u8.bit_reverse          # => 0b11010010
  # 0b1100100001100111_u16.bit_reverse # => 0b1110011000010011
  # ```
  def bit_reverse : self
    Intrinsics.bitreverse16(self)
  end

  # Swaps the bytes of `self`; a little-endian value becomes a big-endian value,
  # and vice-versa. The bit order within each byte is unchanged.
  #
  # Has no effect on 8-bit integers.
  #
  # ```
  # 0x1234_u16.byte_swap # => 0x3412
  # ```
  def byte_swap : self
    Intrinsics.bswap16(self)
  end

  # Returns the number of leading `0`-bits.
  def leading_zeros_count
    Intrinsics.countleading16(self, false)
  end

  def trailing_zeros_count
    Intrinsics.counttrailing16(self, false)
  end

  # Returns the bitwise rotation of `self` *n* times in the most significant
  # bit's direction. Negative shifts are equivalent to `rotate_right(-n)`.
  #
  # ```
  # 0b01001101_u8.rotate_left(3)  # => 0b01101010
  # 0b01001101_u8.rotate_left(8)  # => 0b01001101
  # 0b01001101_u8.rotate_left(11) # => 0b01101010
  # 0b01001101_u8.rotate_left(-1) # => 0b10100110
  # ```
  def rotate_left(n : Int) : self
    Intrinsics.fshl16(self, self, n.to_u16!)
  end

  # Returns the bitwise rotation of `self` *n* times in the least significant
  # bit's direction. Negative shifts are equivalent to `rotate_left(-n)`.
  #
  # ```
  # 0b01001101_u8.rotate_right(3)  # => 0b10101001
  # 0b01001101_u8.rotate_right(8)  # => 0b01001101
  # 0b01001101_u8.rotate_right(11) # => 0b10101001
  # 0b01001101_u8.rotate_right(-1) # => 0b10011010
  # ```
  def rotate_right(n : Int) : self
    Intrinsics.fshr16(self, self, n.to_u16!)
  end

  def clone
    self
  end
end

struct UInt32
  MIN =          0_u32
  MAX = 4294967295_u32

  # Returns an `UInt32` by invoking `to_u32` on *value*.
  # See `String#to_i` for more details.
  #
  # ```
  # UInt32.new "20"                        # => 20
  # UInt32.new "  20  ", whitespace: false # raises ArgumentError: Invalid UInt32: "  20  "
  # ```
  def self.new(value : String, base : Int = 10, whitespace : Bool = true, underscore : Bool = false, prefix : Bool = false, strict : Bool = true, leading_zero_is_octal : Bool = false) : self
    value.to_u32 base: base, whitespace: whitespace, underscore: underscore, prefix: prefix, strict: strict, leading_zero_is_octal: leading_zero_is_octal
  end

  # Returns an `UInt32` by invoking `to_u32` on *value*.
  def self.new(value) : self
    value.to_u32
  end

  # Returns an `UInt32` by invoking `to_u32!` on *value*.
  def self.new!(value) : self
    value.to_u32!
  end

  Number.expand_div [Int8, UInt8, Int16, UInt16, Int32, UInt32, Int64, UInt64, Int128, UInt128], Float64
  Number.expand_div [Float32], Float32
  Number.expand_div [Float64], Float64

  def &- : UInt32
    0_u32 &- self
  end

  # Returns `self` converted to a signed value of the same size.
  #
  # Simply returns `self` unmodified if `self` is already an `Int::Signed`.
  # Raises `OverflowError` in case of overflow.
  #
  # ```
  # 1_u32.to_signed # => 1_i32
  # 2_u16.to_signed # => 2_i16
  # 3_i64.to_signed # => 3_i64
  # ```
  def to_signed : Int32
    to_i32
  end

  # Returns `self` converted to a signed value of the same size, wrapping in
  # case of overflow.
  #
  # Simply returns `self` unmodified if `self` is already an `Int::Signed`.
  #
  # ```
  # 1_u32.to_signed!     # => 1_i32
  # 65530_u16.to_signed! # => -6_i16
  # 3_i64.to_signed!     # => 3_i64
  # ```
  def to_signed! : Int32
    to_i32!
  end

  # Returns `self` converted to an unsigned value of the same size.
  #
  # Simply returns `self` unmodified if `self` is already an `Int::Unsigned`.
  # Raises `OverflowError` in case of overflow.
  #
  # ```
  # 1_i32.to_unsigned # => 1_u32
  # 2_i16.to_unsigned # => 2_u16
  # 3_u64.to_unsigned # => 3_u64
  # ```
  def to_unsigned : UInt32
    self
  end

  # Returns `self` converted to an unsigned value of the same size, wrapping in
  # case of overflow.
  #
  # Simply returns `self` unmodified if `self` is already an `Int::Unsigned`.
  #
  # ```
  # 1_i32.to_unsigned!    # => 1_u32
  # (-6_i16).to_unsigned! # => 65530_u16
  # 3_u64.to_unsigned!    # => 3_u64
  # ```
  def to_unsigned! : UInt32
    self
  end

  def abs : self
    self
  end

  # Returns the absolute value of `self` as an unsigned value of the same size.
  #
  # Returns `self` if `self` is already an `Int::Unsigned`. This method never
  # overflows.
  #
  # ```
  # 1_u32.abs_unsigned      # => 1_u32
  # 2_i32.abs_unsigned      # => 2_u32
  # -3_i8.abs_unsigned      # => 3_u8
  # Int16::MIN.abs_unsigned # => 32768_u16
  # ```
  def abs_unsigned : self
    self
  end

  # Returns the negative of `self` as a signed value of the same size.
  #
  # Returns `-self` if `self` is already an `Int::Signed`. Raises
  # `OverflowError` in case of overflow.
  #
  # ```
  # 1_i32.neg_signed      # => -1_i32
  # 2_u16.neg_signed      # => -2_i16
  # 128_u8.neg_signed     # => -128_i8
  # Int16::MIN.neg_signed # raises OverflowError
  # ```
  def neg_signed : Int32
    0_i32 - self
  end

  def popcount : Int32
    Intrinsics.popcount32(self)
  end

  # Reverses the bits of `self`; the least significant bit becomes the most
  # significant, and vice-versa.
  #
  # ```
  # 0b01001011_u8.bit_reverse          # => 0b11010010
  # 0b1100100001100111_u16.bit_reverse # => 0b1110011000010011
  # ```
  def bit_reverse : self
    Intrinsics.bitreverse32(self)
  end

  # Swaps the bytes of `self`; a little-endian value becomes a big-endian value,
  # and vice-versa. The bit order within each byte is unchanged.
  #
  # Has no effect on 8-bit integers.
  #
  # ```
  # 0x12345678_u32.byte_swap # => 0x78563412
  # ```
  def byte_swap : self
    Intrinsics.bswap32(self)
  end

  # Returns the number of leading `0`-bits.
  def leading_zeros_count
    Intrinsics.countleading32(self, false)
  end

  def trailing_zeros_count
    Intrinsics.counttrailing32(self, false)
  end

  # Returns the bitwise rotation of `self` *n* times in the most significant
  # bit's direction. Negative shifts are equivalent to `rotate_right(-n)`.
  #
  # ```
  # 0b01001101_u8.rotate_left(3)  # => 0b01101010
  # 0b01001101_u8.rotate_left(8)  # => 0b01001101
  # 0b01001101_u8.rotate_left(11) # => 0b01101010
  # 0b01001101_u8.rotate_left(-1) # => 0b10100110
  # ```
  def rotate_left(n : Int) : self
    Intrinsics.fshl32(self, self, n.to_u32!)
  end

  # Returns the bitwise rotation of `self` *n* times in the least significant
  # bit's direction. Negative shifts are equivalent to `rotate_left(-n)`.
  #
  # ```
  # 0b01001101_u8.rotate_right(3)  # => 0b10101001
  # 0b01001101_u8.rotate_right(8)  # => 0b01001101
  # 0b01001101_u8.rotate_right(11) # => 0b10101001
  # 0b01001101_u8.rotate_right(-1) # => 0b10011010
  # ```
  def rotate_right(n : Int) : self
    Intrinsics.fshr32(self, self, n.to_u32!)
  end

  def clone
    self
  end
end

struct UInt64
  MIN =                    0_u64
  MAX = 18446744073709551615_u64

  # Returns an `UInt64` by invoking `to_u64` on *value*.
  # See `String#to_i` for more details.
  #
  # ```
  # UInt64.new "20"                        # => 20
  # UInt64.new "  20  ", whitespace: false # raises ArgumentError: Invalid UInt64: "  20  "
  # ```
  def self.new(value : String, base : Int = 10, whitespace : Bool = true, underscore : Bool = false, prefix : Bool = false, strict : Bool = true, leading_zero_is_octal : Bool = false) : self
    value.to_u64 base: base, whitespace: whitespace, underscore: underscore, prefix: prefix, strict: strict, leading_zero_is_octal: leading_zero_is_octal
  end

  # Returns an `UInt64` by invoking `to_u64` on *value*.
  def self.new(value) : self
    value.to_u64
  end

  # Returns an `UInt64` by invoking `to_u64!` on *value*.
  def self.new!(value) : self
    value.to_u64!
  end

  Number.expand_div [Int8, UInt8, Int16, UInt16, Int32, UInt32, Int64, UInt64, Int128, UInt128], Float64
  Number.expand_div [Float32], Float32
  Number.expand_div [Float64], Float64

  def &- : UInt64
    0_u64 &- self
  end

  # Returns `self` converted to a signed value of the same size.
  #
  # Simply returns `self` unmodified if `self` is already an `Int::Signed`.
  # Raises `OverflowError` in case of overflow.
  #
  # ```
  # 1_u32.to_signed # => 1_i32
  # 2_u16.to_signed # => 2_i16
  # 3_i64.to_signed # => 3_i64
  # ```
  def to_signed : Int64
    to_i64
  end

  # Returns `self` converted to a signed value of the same size, wrapping in
  # case of overflow.
  #
  # Simply returns `self` unmodified if `self` is already an `Int::Signed`.
  #
  # ```
  # 1_u32.to_signed!     # => 1_i32
  # 65530_u16.to_signed! # => -6_i16
  # 3_i64.to_signed!     # => 3_i64
  # ```
  def to_signed! : Int64
    to_i64!
  end

  # Returns `self` converted to an unsigned value of the same size.
  #
  # Simply returns `self` unmodified if `self` is already an `Int::Unsigned`.
  # Raises `OverflowError` in case of overflow.
  #
  # ```
  # 1_i32.to_unsigned # => 1_u32
  # 2_i16.to_unsigned # => 2_u16
  # 3_u64.to_unsigned # => 3_u64
  # ```
  def to_unsigned : UInt64
    self
  end

  # Returns `self` converted to an unsigned value of the same size, wrapping in
  # case of overflow.
  #
  # Simply returns `self` unmodified if `self` is already an `Int::Unsigned`.
  #
  # ```
  # 1_i32.to_unsigned!    # => 1_u32
  # (-6_i16).to_unsigned! # => 65530_u16
  # 3_u64.to_unsigned!    # => 3_u64
  # ```
  def to_unsigned! : UInt64
    self
  end

  def abs : self
    self
  end

  # Returns the absolute value of `self` as an unsigned value of the same size.
  #
  # Returns `self` if `self` is already an `Int::Unsigned`. This method never
  # overflows.
  #
  # ```
  # 1_u32.abs_unsigned      # => 1_u32
  # 2_i32.abs_unsigned      # => 2_u32
  # -3_i8.abs_unsigned      # => 3_u8
  # Int16::MIN.abs_unsigned # => 32768_u16
  # ```
  def abs_unsigned : self
    self
  end

  # Returns the negative of `self` as a signed value of the same size.
  #
  # Returns `-self` if `self` is already an `Int::Signed`. Raises
  # `OverflowError` in case of overflow.
  #
  # ```
  # 1_i32.neg_signed      # => -1_i32
  # 2_u16.neg_signed      # => -2_i16
  # 128_u8.neg_signed     # => -128_i8
  # Int16::MIN.neg_signed # raises OverflowError
  # ```
  def neg_signed : Int64
    0_i64 - self
  end

  def popcount : Int64
    Intrinsics.popcount64(self)
  end

  # Reverses the bits of `self`; the least significant bit becomes the most
  # significant, and vice-versa.
  #
  # ```
  # 0b01001011_u8.bit_reverse          # => 0b11010010
  # 0b1100100001100111_u16.bit_reverse # => 0b1110011000010011
  # ```
  def bit_reverse : self
    Intrinsics.bitreverse64(self)
  end

  # Swaps the bytes of `self`; a little-endian value becomes a big-endian value,
  # and vice-versa. The bit order within each byte is unchanged.
  #
  # Has no effect on 8-bit integers.
  #
  # ```
  # 0x123456789ABCDEF0_u64.byte_swap # => 0xF0DEBC9A78563412
  # ```
  def byte_swap : self
    Intrinsics.bswap64(self)
  end

  # Returns the number of leading `0`-bits.
  def leading_zeros_count
    Intrinsics.countleading64(self, false)
  end

  def trailing_zeros_count
    Intrinsics.counttrailing64(self, false)
  end

  # Returns the bitwise rotation of `self` *n* times in the most significant
  # bit's direction. Negative shifts are equivalent to `rotate_right(-n)`.
  #
  # ```
  # 0b01001101_u8.rotate_left(3)  # => 0b01101010
  # 0b01001101_u8.rotate_left(8)  # => 0b01001101
  # 0b01001101_u8.rotate_left(11) # => 0b01101010
  # 0b01001101_u8.rotate_left(-1) # => 0b10100110
  # ```
  def rotate_left(n : Int) : self
    Intrinsics.fshl64(self, self, n.to_u64!)
  end

  # Returns the bitwise rotation of `self` *n* times in the least significant
  # bit's direction. Negative shifts are equivalent to `rotate_left(-n)`.
  #
  # ```
  # 0b01001101_u8.rotate_right(3)  # => 0b10101001
  # 0b01001101_u8.rotate_right(8)  # => 0b01001101
  # 0b01001101_u8.rotate_right(11) # => 0b10101001
  # 0b01001101_u8.rotate_right(-1) # => 0b10011010
  # ```
  def rotate_right(n : Int) : self
    Intrinsics.fshr64(self, self, n.to_u64!)
  end

  def clone
    self
  end
end

struct UInt128
  MIN =                                       0_u128
  MAX = 340282366920938463463374607431768211455_u128

  # Returns an `UInt128` by invoking `to_u128` on *value*.
  # See `String#to_i` for more details.
  #
  # ```
  # UInt128.new "20"                        # => 20
  # UInt128.new "  20  ", whitespace: false # raises ArgumentError: Invalid UInt128: "  20  "
  # ```
  def self.new(value : String, base : Int = 10, whitespace : Bool = true, underscore : Bool = false, prefix : Bool = false, strict : Bool = true, leading_zero_is_octal : Bool = false) : self
    value.to_u128 base: base, whitespace: whitespace, underscore: underscore, prefix: prefix, strict: strict, leading_zero_is_octal: leading_zero_is_octal
  end

  # Returns an `UInt128` by invoking `to_u128` on *value*.
  def self.new(value) : self
    value.to_u128
  end

  # Returns an `UInt128` by invoking `to_u128!` on *value*.
  def self.new!(value) : self
    value.to_u128!
  end

  Number.expand_div [Int8, UInt8, Int16, UInt16, Int32, UInt32, Int64, UInt64, Int128, UInt128], Float64
  Number.expand_div [Float32], Float32
  Number.expand_div [Float64], Float64

  def &-
    # TODO: use 0_u128 &- self
    UInt128.new(0) &- self
  end

  # Returns `self` converted to a signed value of the same size.
  #
  # Simply returns `self` unmodified if `self` is already an `Int::Signed`.
  # Raises `OverflowError` in case of overflow.
  #
  # ```
  # 1_u32.to_signed # => 1_i32
  # 2_u16.to_signed # => 2_i16
  # 3_i64.to_signed # => 3_i64
  # ```
  def to_signed : Int128
    to_i128
  end

  # Returns `self` converted to a signed value of the same size, wrapping in
  # case of overflow.
  #
  # Simply returns `self` unmodified if `self` is already an `Int::Signed`.
  #
  # ```
  # 1_u32.to_signed!     # => 1_i32
  # 65530_u16.to_signed! # => -6_i16
  # 3_i64.to_signed!     # => 3_i64
  # ```
  def to_signed! : Int128
    to_i128!
  end

  # Returns `self` converted to an unsigned value of the same size.
  #
  # Simply returns `self` unmodified if `self` is already an `Int::Unsigned`.
  # Raises `OverflowError` in case of overflow.
  #
  # ```
  # 1_i32.to_unsigned # => 1_u32
  # 2_i16.to_unsigned # => 2_u16
  # 3_u64.to_unsigned # => 3_u64
  # ```
  def to_unsigned : UInt128
    self
  end

  # Returns `self` converted to an unsigned value of the same size, wrapping in
  # case of overflow.
  #
  # Simply returns `self` unmodified if `self` is already an `Int::Unsigned`.
  #
  # ```
  # 1_i32.to_unsigned!    # => 1_u32
  # (-6_i16).to_unsigned! # => 65530_u16
  # 3_u64.to_unsigned!    # => 3_u64
  # ```
  def to_unsigned! : UInt128
    self
  end

  def abs
    self
  end

  # Returns the absolute value of `self` as an unsigned value of the same size.
  #
  # Returns `self` if `self` is already an `Int::Unsigned`. This method never
  # overflows.
  #
  # ```
  # 1_u32.abs_unsigned      # => 1_u32
  # 2_i32.abs_unsigned      # => 2_u32
  # -3_i8.abs_unsigned      # => 3_u8
  # Int16::MIN.abs_unsigned # => 32768_u16
  # ```
  def abs_unsigned : self
    self
  end

  # Returns the negative of `self` as a signed value of the same size.
  #
  # Returns `-self` if `self` is already an `Int::Signed`. Raises
  # `OverflowError` in case of overflow.
  #
  # ```
  # 1_i32.neg_signed      # => -1_i32
  # 2_u16.neg_signed      # => -2_i16
  # 128_u8.neg_signed     # => -128_i8
  # Int16::MIN.neg_signed # raises OverflowError
  # ```
  def neg_signed : Int128
    Int128.new(0) - self
  end

  def popcount
    Intrinsics.popcount128(self)
  end

  # Reverses the bits of `self`; the least significant bit becomes the most
  # significant, and vice-versa.
  #
  # ```
  # 0b01001011_u8.bit_reverse          # => 0b11010010
  # 0b1100100001100111_u16.bit_reverse # => 0b1110011000010011
  # ```
  def bit_reverse : self
    Intrinsics.bitreverse128(self)
  end

  # Swaps the bytes of `self`; a little-endian value becomes a big-endian value,
  # and vice-versa. The bit order within each byte is unchanged.
  #
  # Has no effect on 8-bit integers.
  #
  # ```
  # 0x123456789ABCDEF013579BDF2468ACE0_u128.byte_swap # ＝> 0xE0AC6824DF9B5713F0DEBC9A78563412
  # ```
  def byte_swap : self
    Intrinsics.bswap128(self)
  end

  # Returns the number of leading `0`-bits.
  def leading_zeros_count
    Intrinsics.countleading128(self, false)
  end

  def trailing_zeros_count
    Intrinsics.counttrailing128(self, false)
  end

  # Returns the bitwise rotation of `self` *n* times in the most significant
  # bit's direction. Negative shifts are equivalent to `rotate_right(-n)`.
  #
  # ```
  # 0b01001101_u8.rotate_left(3)  # => 0b01101010
  # 0b01001101_u8.rotate_left(8)  # => 0b01001101
  # 0b01001101_u8.rotate_left(11) # => 0b01101010
  # 0b01001101_u8.rotate_left(-1) # => 0b10100110
  # ```
  def rotate_left(n : Int) : self
    Intrinsics.fshl128(self, self, n.to_u128!)
  end

  # Returns the bitwise rotation of `self` *n* times in the least significant
  # bit's direction. Negative shifts are equivalent to `rotate_left(-n)`.
  #
  # ```
  # 0b01001101_u8.rotate_right(3)  # => 0b10101001
  # 0b01001101_u8.rotate_right(8)  # => 0b01001101
  # 0b01001101_u8.rotate_right(11) # => 0b10101001
  # 0b01001101_u8.rotate_right(-1) # => 0b10011010
  # ```
  def rotate_right(n : Int) : self
    Intrinsics.fshr128(self, self, n.to_u128!)
  end

  def clone
    self
  end
end
