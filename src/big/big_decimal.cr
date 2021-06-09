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
  private TWO  = BigInt.new(2)
  private FIVE = BigInt.new(5)
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

    raise InvalidBigDecimalException.new(str, "Zero size") if str.bytesize == 0

    # Check str's validity and find index of '.'
    decimal_index = nil
    # Check str's validity and find index of 'e'
    exponent_index = nil

    str.each_char_with_index do |char, index|
      case char
      when '-'
        unless index == 0 || exponent_index == index - 1
          raise InvalidBigDecimalException.new(str, "Unexpected '-' character")
        end
      when '+'
        unless exponent_index == index - 1
          raise InvalidBigDecimalException.new(str, "Unexpected '+' character")
        end
      when '.'
        if decimal_index
          raise InvalidBigDecimalException.new(str, "Unexpected '.' character")
        end
        decimal_index = index
      when 'e', 'E'
        if exponent_index
          raise InvalidBigDecimalException.new(str, "Unexpected #{char.inspect} character")
        end
        exponent_index = index
      when '0'..'9'
        # Pass
      else
        raise InvalidBigDecimalException.new(str, "Unexpected #{char.inspect} character")
      end
    end

    decimal_end_index = (exponent_index || str.bytesize) - 1
    if decimal_index
      decimal_count = (decimal_end_index - decimal_index).to_u64

      value_str = String.build do |builder|
        # We know this is ASCII, so we can slice by index
        builder.write(str.to_slice[0, decimal_index])
        builder.write(str.to_slice[decimal_index + 1, decimal_count])
      end
      @value = value_str.to_big_i
    else
      decimal_count = 0_u64
      @value = str[0..decimal_end_index].to_big_i
    end

    if exponent_index
      exponent_postfix = str[exponent_index + 1]
      case exponent_postfix
      when '+', '-'
        exponent_positive = exponent_postfix == '+'
        exponent = str[(exponent_index + 2)..-1].to_u64
      else
        exponent_positive = true
        exponent = str[(exponent_index + 1)..-1].to_u64
      end

      @scale = exponent
      if exponent_positive
        if @scale < decimal_count
          @scale = decimal_count - @scale
        else
          @scale -= decimal_count
          @value *= 10.to_big_i ** @scale
          @scale = 0_u64
        end
      else
        @scale += decimal_count
      end
    else
      @scale = decimal_count
    end
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

  def +(other : Int) : BigDecimal
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

  def -(other : Int) : BigDecimal
    self - BigDecimal.new(other)
  end

  def *(other : BigDecimal) : BigDecimal
    BigDecimal.new(@value * other.value, @scale + other.scale)
  end

  def *(other : Int) : BigDecimal
    self * BigDecimal.new(other)
  end

  def /(other : BigDecimal) : BigDecimal
    div other
  end

  Number.expand_div [BigInt, BigFloat], BigDecimal
  Number.expand_div [BigRational], BigRational

  # Divides `self` with another `BigDecimal`, with an optionally configurable *max_div_iterations*, which
  # defines a maximum number of iterations in case the division is not exact.
  #
  # ```
  # BigDecimal.new(1).div(BigDecimal.new(2))    # => BigDecimal(@value=5, @scale=2)
  # BigDecimal.new(1).div(BigDecimal.new(3), 5) # => BigDecimal(@value=33333, @scale=5)
  # ```
  def div(other : BigDecimal, max_div_iterations = DEFAULT_MAX_DIV_ITERATIONS) : BigDecimal
    check_division_by_zero other
    return self if @value.zero?
    other.factor_powers_of_ten

    # ```
    #    (a / 10 ** b) / (c / 10 ** d)
    # == (a / c) / 10 ** (b - d)
    # == (a * 10 ** scale_add // c) / 10 ** (b - d + scale_add)
    # ```
    #
    # We want to find the minimum `scale_add` such that:
    #
    # - `b - d + scale_add >= 0`
    # - `a * 10 ** scale_add % c == 0`
    #
    # If this is not possible, we let the returned number's scale be
    # `{b - d, 0}.max + max_div_iterations`.

    numerator, denominator = @value, other.@value
    scale = if @scale >= other.scale
              @scale - other.scale
            else
              numerator *= power_ten_to(other.scale - @scale)
              0
            end

    # Attempt division first; if `a % c == 0`, we're done.
    quotient, remainder = numerator.divmod(denominator)
    if remainder.zero?
      return BigDecimal.new(normalize_quotient(other, quotient), scale)
    end

    # `c == denominator_reduced * 2 ** denominator_exp2 * 5 ** denominator_exp5`
    denominator_reduced, denominator_exp2 = denominator.factor_by(TWO)

    # Heuristic: for low powers of 5 we perform the divisions ourselves, since
    # `BigInt#factor_by` can be slower
    case denominator_reduced
    when 1
      denominator_exp5 = 0_u64
    when 5
      denominator_reduced = denominator_reduced // FIVE
      denominator_exp5 = 1_u64
    when 25
      denominator_reduced = denominator_reduced // FIVE // FIVE
      denominator_exp5 = 2_u64
    else
      denominator_reduced, denominator_exp5 = denominator_reduced.factor_by(FIVE)
    end

    if denominator_reduced != 1
      # If `c` has any prime factor other than 2 or 5, then division will always
      # be inexact; use *max_div_iterations*.
      scale_add = max_div_iterations.to_u64
    elsif denominator_exp2 <= 1 && denominator_exp5 <= 1
      # Heuristic: if `denominator` is one of 2, 5, or 10, then `scale_add` must
      # be 1 because `remainder` can never be divisible by 10. Thus we could
      # skip the `factor_by` and `power_ten_to` calls here.
      quotient = numerator * TEN // denominator
      return BigDecimal.new(normalize_quotient(other, quotient), scale + 1)
    else
      # `a = ... * 10 ** numerator_exp10`
      # For `a * 10 ** scale_add` to be divisible by `c`, it must be the case
      # `numerator_exp10 + scale_add` is greater than `denominator_exp2` and
      # `denominator_exp5`
      _, numerator_exp10 = remainder.factor_by(TEN)
      scale_add = {denominator_exp2, denominator_exp5}.max - numerator_exp10
      scale_add = max_div_iterations.to_u64 if scale_add > max_div_iterations
    end

    quotient = numerator * power_ten_to(scale_add) // denominator
    BigDecimal.new(normalize_quotient(other, quotient), scale + scale_add)
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

  # Scales a `BigDecimal` to another `BigDecimal`, so they can be
  # computed easier.
  def scale_to(new_scale : BigDecimal) : BigDecimal
    in_scale(new_scale.scale)
  end

  # :nodoc:
  def in_scale(new_scale : UInt64) : BigDecimal
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
    if other < 0
      raise ArgumentError.new("Negative exponent isn't supported")
    end
    BigDecimal.new(@value ** other, @scale * other)
  end

  def ceil : BigDecimal
    mask = power_ten_to(@scale)
    diff = (mask - @value % mask) % mask
    value = self + BigDecimal.new(diff, @scale)
    value.in_scale(0)
  end

  def floor : BigDecimal
    in_scale(0)
  end

  def trunc : BigDecimal
    self < 0 ? ceil : floor
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
    BigRational.new(@value, power_ten_to(@scale))
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
    if @scale > 0
      reduced, exp = value.factor_by(TEN)
      if exp <= @scale
        @value = reduced
        @scale -= exp
      else
        @value //= power_ten_to(@scale)
        @scale = 0
      end
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
