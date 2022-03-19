require "big"

class InvalidBigDecimalException < Exception
  def initialize(big_decimal_str : String, reason : String)
    super("Invalid BigDecimal: #{big_decimal_str} (#{reason})")
  end
end

# A `BigDecimal` can represent arbitrarily large precision decimals.
#
# It is internally represented by a pair of `BigInt` and `UInt64`: value and scale.
# Value contains the actual value, and scale tells the decimal point place.
# E.g. when value is `1234` and scale `2`, the result is `12.34`.
#
# The general idea and some of the arithmetic algorithms were adapted from
# the MIT/APACHE-licensed [bigdecimal-rs](https://github.com/akubera/bigdecimal-rs).
struct BigDecimal < Number
  private ZERO = BigInt.new(0)
  private TEN  = BigInt.new(10)

  DEFAULT_MAX_DIV_ITERATIONS = 100_u64

  include Comparable(Int)
  include Comparable(Float)
  include Comparable(BigRational)
  include Comparable(BigDecimal)

  getter value : BigInt
  getter scale : UInt64

  # Creates a new `BigDecimal` from `Float`.
  #
  # NOTE: Floats are fundamentally less precise than BigDecimals,
  # which makes initialization from them risky.
  def self.new(num : Float)
    new(num.to_s)
  end

  # Creates a new `BigDecimal` from `BigRational`.
  #
  # NOTE: BigRational are fundamentally more precise than BigDecimals,
  # which makes initialization from them risky.
  def self.new(num : BigRational)
    num.numerator.to_big_d / num.denominator.to_big_d
  end

  # Returns *num*. Useful for generic code that does `T.new(...)` with `T`
  # being a `Number`.
  def self.new(num : BigDecimal)
    num
  end

  # Creates a new `BigDecimal` from `BigInt` *value* and `UInt64` *scale*,
  # which matches the internal representation.
  def initialize(@value : BigInt, @scale : UInt64)
  end

  # Creates a new `BigDecimal` from `Int`.
  def initialize(num : Int = 0, scale : Int = 0)
    initialize(num.to_big_i, scale.to_u64)
  end

  # Creates a new `BigDecimal` from a `String`.
  #
  # Allows only valid number strings with an optional negative sign.
  def initialize(str : String)
    # Strip leading '+' char to smooth out cases with strings like "+123"
    str = str.lchop('+')
    # Strip '_' to make it compatible with int literals like "1_000_000"
    str = str.delete('_')

    value_str, value_negative, fraction_str, exponent_str, exponent_negative = parse_e_notation(str.each_char.with_index)

    decimal_count = fraction_str ? fraction_str.size.to_u64 : 0_u64
    unscaled_string = fraction_str ? value_str + fraction_str : value_str
    @value = (value_negative ? "-" + unscaled_string : unscaled_string).to_big_i

    if exponent_str
      # TODO wrap error
      @scale = exponent_str.to_u64
      if exponent_negative
        @scale += decimal_count
      else
        if @scale < decimal_count
          @scale = decimal_count - @scale
        else
          @scale -= decimal_count
          @value *= 10.to_big_i ** @scale
          @scale = 0_u64
        end
      end
    else
      @scale = decimal_count
    end
  end

  private def parse_e_notation(iterator)
    token = take_next_character(iterator)
    value_negative = false
    if token_sign?(token)
      token, value_negative = parse_sign_symbol(token, iterator)
    elsif !(token_digit?(token) || token_decimal?(token))
      raise_parse_error(token)
    end
    next_token, value_str, fraction_str, exponent_str, exponent_negative = parse_numerical_part(token, iterator)
    parse_end(next_token)
    {value_str, value_negative, fraction_str, exponent_str, exponent_negative}
  end

  private def parse_sign_symbol(token, iterator)
    {take_next_character(iterator), token[0] == '-'}
  end

  private def parse_numerical_part(token, iterator)
    value_str = ""
    fraction_str = nil
    if token_digit?(token)
      token, value_str = parse_digits(token, iterator)
      token, fraction_str = parse_fractional_part(token, iterator) if token_decimal?(token)
    elsif token_decimal?(token)
      token, fraction_str = parse_fractional_part(token, iterator)
      raise_parse_error(token) if fraction_str.empty?
    else
      raise_parse_error(token)
    end
    next_token, exponent_str, exponent_negative = token_e?(token) ? parse_exponent_part(token, iterator) : {token, nil, false}
    {next_token, value_str, fraction_str, exponent_str, exponent_negative}
  end

  private def parse_digits(token, iterator)
    val = String.build do |io|
      while token_digit?(token)
        io << token[0]
        token = take_next_character(iterator, true)
      end
    end
    {token, val}
  end

  private def parse_fractional_part(token, iterator)
    token = take_next_character(iterator, true) # consume '.'
    parse_digits(token, iterator)
  end

  private def parse_exponent_part(token, iterator)
    token = take_next_character(iterator) # consume 'e'
    if token_sign?(token)
      next_token, exponent_negative = parse_sign_symbol(token, iterator)
      token, val = parse_digits(next_token, iterator)
      {token, val, exponent_negative}
    elsif token_digit?(token)
      token, val = parse_digits(token, iterator)
      {token, val, false}
    else
      raise_parse_error(token)
    end
  end

  private def parse_end(token)
    raise_parse_error(token) unless token_end?(token)
  end

  private def take_next_character(iterator, allow_end = false) : Tuple(Char | Nil, Int32)
    next_c = iterator.next
    if next_c == Iterator::Stop::INSTANCE
      raise_parse_eos_error unless allow_end
      {nil, -1}
    else
      next_c.as(Tuple(Char, Int32))
    end
  end

  private def token_digit?(token)
    c = token[0]
    c && c >= '0' && c <= '9'
  end

  private def token_sign?(token)
    c = token[0]
    c && (c == '-' || c == '+')
  end

  private def token_decimal?(token)
    c = token[0]
    c && c == '.'
  end

  private def token_e?(token)
    c = token[0]
    c && (c == 'e' || c == 'E')
  end

  private def token_end?(token)
    token[0] == nil && token[1] == -1
  end

  private def raise_parse_error(token)
    raise_parse_eos_error if token_end?(token)
    raise ArgumentError.new("Unexpected '#{token[0]}' at character #{token[1]}")
  end

  private def raise_parse_eos_error
    raise ArgumentError.new("Unexpected end of number string")
  end

  def - : BigDecimal
    BigDecimal.new(-@value, @scale)
  end

  def +(other : BigDecimal) : BigDecimal
    if @scale > other.scale
      scaled = other.scale_to(self)
      BigDecimal.new(@value + scaled.value, @scale)
    elsif @scale < other.scale
      scaled = scale_to(other)
      BigDecimal.new(scaled.value + other.value, other.scale)
    else
      BigDecimal.new(@value + other.value, @scale)
    end
  end

  def +(other : Number) : BigDecimal
    self + BigDecimal.new(other)
  end

  def -(other : BigDecimal) : BigDecimal
    if @scale > other.scale
      scaled = other.scale_to(self)
      BigDecimal.new(@value - scaled.value, @scale)
    elsif @scale < other.scale
      scaled = scale_to(other)
      BigDecimal.new(scaled.value - other.value, other.scale)
    else
      BigDecimal.new(@value - other.value, @scale)
    end
  end

  def -(other : Number) : BigDecimal
    self - BigDecimal.new(other)
  end

  def *(other : BigDecimal) : BigDecimal
    BigDecimal.new(@value * other.value, @scale + other.scale)
  end

  def *(other : Number) : BigDecimal
    self * BigDecimal.new(other)
  end

  def /(other : BigDecimal) : BigDecimal
    div other
  end

  Number.expand_div [BigInt, BigFloat], BigDecimal
  Number.expand_div [BigRational], BigRational

  # Divides `self` with another `BigDecimal`, with a optionally configurable *max_div_iterations*, which
  # defines a maximum number of iterations in case the division is not exact.
  #
  # ```
  # BigDecimal.new(1).div(BigDecimal.new(2))    # => BigDecimal(@value=5, @scale=2)
  # BigDecimal.new(1).div(BigDecimal.new(3), 5) # => BigDecimal(@value=33333, @scale=5)
  # ```
  def div(other : BigDecimal, max_div_iterations = DEFAULT_MAX_DIV_ITERATIONS) : BigDecimal
    check_division_by_zero other
    other.factor_powers_of_ten

    numerator, denominator = @value, other.@value
    scale = if @scale >= other.scale
              @scale - other.scale
            else
              numerator *= TEN ** (other.scale - @scale)
              0
            end

    quotient, remainder = numerator.divmod(denominator)
    if remainder == ZERO
      return BigDecimal.new(normalize_quotient(other, quotient), scale)
    end

    remainder = remainder * TEN
    i = 0
    while remainder != ZERO && i < max_div_iterations
      inner_quotient, inner_remainder = remainder.divmod(denominator)
      quotient = quotient * TEN + inner_quotient
      remainder = inner_remainder * TEN
      i += 1
    end

    BigDecimal.new(normalize_quotient(other, quotient), scale + i)
  end

  def <=>(other : BigDecimal) : Int32
    if @scale > other.scale
      @value <=> other.scale_to(self).value
    elsif @scale < other.scale
      scale_to(other).value <=> other.value
    else
      @value <=> other.value
    end
  end

  def <=>(other : Int | Float | BigRational)
    self <=> BigDecimal.new(other)
  end

  def ==(other : BigDecimal) : Bool
    case @scale
    when .>(other.scale)
      scaled = other.value * power_ten_to(@scale - other.scale)
      @value == scaled
    when .<(other.scale)
      scaled = @value * power_ten_to(other.scale - @scale)
      scaled == other.value
    else
      @value == other.value
    end
  end

  def zero? : Bool
    @value.zero?
  end

  # Scales a `BigDecimal` to another `BigDecimal`, so they can be
  # computed easier.
  def scale_to(new_scale : BigDecimal) : BigDecimal
    in_scale(new_scale.scale)
  end

  # :nodoc:
  private def in_scale(new_scale : UInt64) : BigDecimal
    if @value == 0
      BigDecimal.new(0.to_big_i, new_scale)
    elsif @scale > new_scale
      scale_diff = @scale - new_scale.to_big_i
      BigDecimal.new(@value // power_ten_to(scale_diff), new_scale)
    elsif @scale < new_scale
      scale_diff = new_scale - @scale.to_big_i
      BigDecimal.new(@value * power_ten_to(scale_diff), new_scale)
    else
      self
    end
  end

  # Raises the decimal to the *other*th power
  #
  # ```
  # require "big"
  #
  # BigDecimal.new(1234, 2) ** 2 # => 152.2756
  # ```
  def **(other : Int) : BigDecimal
    return (to_big_r ** other).to_big_d if other < 0
    BigDecimal.new(@value ** other, @scale * other)
  end

  # Rounds towards positive infinity.
  def ceil : BigDecimal
    round_impl { |rem| rem > 0 }
  end

  # Rounds towards negative infinity.
  def floor : BigDecimal
    round_impl { |rem| rem < 0 }
  end

  # Rounds towards zero.
  def trunc : BigDecimal
    round_impl { false }
  end

  # Rounds towards the nearest integer. If both neighboring integers are equidistant,
  # rounds towards the even neighbor (Banker's rounding).
  def round_even : BigDecimal
    round_impl do |rem, rem_range, mantissa|
      case rem.abs <=> rem_range // 2
      when .<(0)
        false
      when .>(0)
        true
      else
        # `to_i!` is safe as GMP explicitly states the "least significant part"
        # is returned and that always preserves `mantissa`'s parity modulo 2
        mantissa.to_i!.odd?
      end
    end
  end

  # Rounds towards the nearest integer. If both neighboring integers are equidistant,
  # rounds away from zero.
  def round_away : BigDecimal
    round_impl { |rem, rem_range| rem.abs >= rem_range // 2 }
  end

  private def round_impl
    return self if @scale <= 0 || zero?

    # `self == @value / 10 ** @scale == mantissa + (rem / 10 ** @scale)`
    #
    # Where:
    # - `mantissa` and `rem` are both integers
    # - `rem.abs < 10 ** @scale`
    # - if `self` is negative, so are `mantissa` and `rem`
    multiplier = power_ten_to(@scale)
    mantissa, rem = @value.unsafe_truncated_divmod(multiplier)

    round_away = yield rem, multiplier, mantissa
    mantissa += self.sign if round_away

    BigDecimal.new(mantissa, 0)
  end

  def round(digits : Number, base = 10, *, mode : RoundingMode = :ties_even) : BigDecimal
    return self if (base == 10 && @scale <= digits) || zero?

    # the following is same as the overload in `Number` except `base.to_f`
    # becomes `.to_big_d`
    if digits < 0
      multiplier = base.to_big_d ** digits.abs
      shifted = self / multiplier
    else
      multiplier = base.to_big_d ** digits
      shifted = self * multiplier
    end

    rounded = shifted.round(mode)

    if digits < 0
      result = rounded * multiplier
    else
      result = rounded / multiplier
    end

    BigDecimal.new result
  end

  def to_s(io : IO) : Nil
    factor_powers_of_ten

    s = @value.to_s
    if @scale == 0
      io << s
      return
    end

    if @scale >= s.size && @value >= 0
      io << "0."
      (@scale - s.size).times do
        io << '0'
      end
      io << s
    elsif @scale >= s.size && @value < 0
      io << "-0.0"
      (@scale - s.size).times do
        io << '0'
      end
      io << s[1..-1]
    elsif (offset = s.size - @scale) == 1 && @value < 0
      io << "-0." << s[offset..-1]
    else
      io << s[0...offset] << '.' << s[offset..-1]
    end
  end

  # Converts to `BigInt`. Truncates anything on the right side of the decimal point.
  def to_big_i : BigInt
    trunc.value
  end

  # Converts to `BigFloat`.
  def to_big_f
    BigFloat.new(to_s)
  end

  def to_big_d
    self
  end

  def to_big_r : BigRational
    BigRational.new(self.value, TEN ** self.scale)
  end

  # Converts to `Int64`. Truncates anything on the right side of the decimal point.
  # Raises `OverflowError` in case of overflow.
  def to_i64 : Int64
    to_big_i.to_i64
  end

  # Converts to `Int32`. Truncates anything on the right side of the decimal point.
  # Raises `OverflowError` in case of overflow.
  def to_i32 : Int32
    to_big_i.to_i32
  end

  # Converts to `Int16`. Truncates anything on the right side of the decimal point.
  # Raises `OverflowError` in case of overflow.
  def to_i16 : Int16
    to_big_i.to_i16
  end

  # Converts to `Int8`. Truncates anything on the right side of the decimal point.
  # Raises `OverflowError` in case of overflow.
  def to_i8 : Int8
    to_big_i.to_i8
  end

  # Converts to `Int32`. Truncates anything on the right side of the decimal point.
  # Raises `OverflowError` in case of overflow.
  def to_i : Int32
    to_i32
  end

  # Converts to `Int8`. Truncates anything on the right side of the decimal point.
  # In case of overflow a wrapping is performed.
  def to_i8!
    to_big_i.to_i8!
  end

  # Converts to `Int16`. Truncates anything on the right side of the decimal point.
  # In case of overflow a wrapping is performed.
  def to_i16!
    to_big_i.to_i16!
  end

  # Converts to `Int32`. Truncates anything on the right side of the decimal point.
  # In case of overflow a wrapping is performed.
  def to_i32! : Int32
    to_big_i.to_i32!
  end

  # Converts to `Int64`. Truncates anything on the right side of the decimal point.
  # In case of overflow a wrapping is performed.
  def to_i64!
    to_big_i.to_i64!
  end

  # Converts to `Int32`. Truncates anything on the right side of the decimal point.
  # In case of overflow a wrapping is performed.
  def to_i! : Int32
    to_i32!
  end

  private def to_big_u
    raise OverflowError.new if self < 0
    to_big_u!
  end

  private def to_big_u!
    (@value.abs // TEN ** @scale)
  end

  # Converts to `UInt64`. Truncates anything on the right side of the decimal point.
  # Raises `OverflowError` in case of overflow.
  def to_u64 : UInt64
    to_big_u.to_u64
  end

  # Converts to `UInt32`. Truncates anything on the right side of the decimal point.
  # Raises `OverflowError` in case of overflow.
  def to_u32 : UInt32
    to_big_u.to_u32
  end

  # Converts to `UInt16`. Truncates anything on the right side of the decimal point.
  # Raises `OverflowError` in case of overflow.
  def to_u16 : UInt16
    to_big_u.to_u16
  end

  # Converts to `UInt8`. Truncates anything on the right side of the decimal point.
  # Raises `OverflowError` in case of overflow.
  def to_u8 : UInt8
    to_big_u.to_u8
  end

  # Converts to `UInt32`. Truncates anything on the right side of the decimal point.
  # Raises `OverflowError` in case of overflow.
  def to_u : UInt32
    to_u32
  end

  # Converts to `UInt8`. Truncates anything on the right side of the decimal point,
  # converting negative to positive.
  # In case of overflow a wrapping is performed.
  def to_u8!
    to_big_u!.to_u8!
  end

  # Converts to `UInt16`. Truncates anything on the right side of the decimal point,
  # converting negative to positive.
  # In case of overflow a wrapping is performed.
  def to_u16!
    to_big_u!.to_u16!
  end

  # Converts to `UInt32`. Truncates anything on the right side of the decimal point,
  # converting negative to positive.
  # In case of overflow a wrapping is performed.
  def to_u32! : UInt32
    to_big_u!.to_u32!
  end

  # Converts to `UInt64`. Truncates anything on the right side of the decimal point,
  # converting negative to positive.
  # In case of overflow a wrapping is performed.
  def to_u64!
    to_big_u!.to_u64!
  end

  # Converts to `UInt32`. Truncates anything on the right side of the decimal point,
  # converting negative to positive.
  # In case of overflow a wrapping is performed.
  def to_u! : UInt32
    to_u32!
  end

  # Converts to `Float64`.
  # Raises `OverflowError` in case of overflow.
  def to_f64 : Float64
    to_s.to_f64
  end

  # Converts to `Float32`.
  # Raises `OverflowError` in case of overflow.
  def to_f32 : Float32
    to_f64.to_f32
  end

  # Converts to `Float64`.
  # Raises `OverflowError` in case of overflow.
  def to_f : Float64
    to_f64
  end

  # Converts to `Float32`.
  # In case of overflow a wrapping is performed.
  def to_f32!
    to_f64.to_f32!
  end

  # Converts to `Float64`.
  # In case of overflow a wrapping is performed.
  def to_f64! : Float64
    to_f64
  end

  # Converts to `Float64`.
  # In case of overflow a wrapping is performed.
  def to_f! : Float64
    to_f64!
  end

  def clone
    self
  end

  def hash(hasher)
    hasher.string(to_s)
  end

  # Returns the *quotient* as absolutely negative if `self` and *other* have
  # different signs, otherwise returns the *quotient*.
  def normalize_quotient(other : BigDecimal, quotient : BigInt) : BigInt
    if (@value < 0 && other.value > 0) || (other.value < 0 && @value > 0)
      -quotient.abs
    else
      quotient
    end
  end

  private def check_division_by_zero(bd : BigDecimal)
    raise DivisionByZeroError.new if bd.value == 0
  end

  private def power_ten_to(x : Int) : Int
    TEN ** x
  end

  # Factors out any extra powers of ten in the internal representation.
  # For instance, value=100 scale=2 => value=1 scale=0
  protected def factor_powers_of_ten
    while @scale > 0
      quotient, remainder = value.divmod(TEN)
      break if remainder != 0

      @value = quotient
      @scale = @scale - 1
    end
  end
end

struct Int
  include Comparable(BigDecimal)

  # Converts `self` to `BigDecimal`.
  # ```
  # require "big"
  # 12123415151254124124.to_big_d
  # ```
  def to_big_d : BigDecimal
    BigDecimal.new(self)
  end

  def <=>(other : BigDecimal)
    to_big_d <=> other
  end

  def +(other : BigDecimal) : BigDecimal
    other + self
  end

  def -(other : BigDecimal) : BigDecimal
    to_big_d - other
  end

  def *(other : BigDecimal) : BigDecimal
    other * self
  end
end

struct Float
  include Comparable(BigDecimal)

  def <=>(other : BigDecimal)
    to_big_d <=> other
  end

  # Converts `self` to `BigDecimal`.
  #
  # NOTE: Floats are fundamentally less precise than BigDecimals,
  # which makes conversion to them risky.
  # ```
  # require "big"
  # 1212341515125412412412421.0.to_big_d
  # ```
  def to_big_d : BigDecimal
    BigDecimal.new(self)
  end
end

struct BigRational
  include Comparable(BigDecimal)

  def <=>(other : BigDecimal)
    to_big_d <=> other
  end

  # Converts `self` to `BigDecimal`.
  def to_big_d : BigDecimal
    BigDecimal.new(self)
  end
end

class String
  # Converts `self` to `BigDecimal`.
  # ```
  # require "big"
  # "1212341515125412412412421".to_big_d
  # ```
  def to_big_d : BigDecimal
    BigDecimal.new(self)
  end
end
