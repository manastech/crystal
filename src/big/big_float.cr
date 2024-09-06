require "c/string"
require "big"

# A `BigFloat` can represent arbitrarily large floats.
#
# It is implemented under the hood with [GMP](https://gmplib.org/).
#
# NOTE: To use `BigFloat`, you must explicitly import it with `require "big"`
struct BigFloat < Float
  include Comparable(Int)
  include Comparable(BigFloat)
  include Comparable(Float)

  def initialize
    LibGMP.mpf_init(out @mpf)
  end

  def initialize(str : String)
    # Strip leading '+' char to smooth out cases with strings like "+123"
    str = str.lchop('+')
    # Strip '_' to make it compatible with int literals like "1_000_000"
    str = str.delete('_')
    if LibGMP.mpf_init_set_str(out @mpf, str, 10) == -1
      raise ArgumentError.new("Invalid BigFloat: #{str.inspect}")
    end
  end

  def initialize(num : BigInt)
    LibGMP.mpf_init(out @mpf)
    LibGMP.mpf_set_z(self, num)
  end

  def initialize(num : BigRational)
    LibGMP.mpf_init(out @mpf)
    LibGMP.mpf_set_q(self, num)
  end

  def initialize(num : BigFloat)
    LibGMP.mpf_init(out @mpf)
    LibGMP.mpf_set(self, num)
  end

  def initialize(num : Int)
    Int.primitive_si_ui_check(num) do |si, ui, big_i|
      {
        si:    LibGMP.mpf_init_set_si(out @mpf, {{ si }}),
        ui:    LibGMP.mpf_init_set_ui(out @mpf, {{ ui }}),
        big_i: begin
          LibGMP.mpf_init(out @mpf)
          LibGMP.mpf_set_z(self, {{ big_i }})
        end,
      }
    end
  end

  def initialize(num : Float::Primitive)
    raise ArgumentError.new "Can only construct from a finite number" unless num.finite?
    LibGMP.mpf_init_set_d(out @mpf, num)
  end

  def initialize(num : Number)
    LibGMP.mpf_init_set_d(out @mpf, num.to_f64)
  end

  def initialize(num : Float, precision : Int)
    raise ArgumentError.new "Can only construct from a finite number" unless num.finite?
    LibGMP.mpf_init2(out @mpf, precision.to_u64)
    LibGMP.mpf_set_d(self, num.to_f64)
  end

  def initialize(@mpf : LibGMP::MPF)
  end

  def self.new(&)
    LibGMP.mpf_init(out mpf)
    yield pointerof(mpf)
    new(mpf)
  end

  def self.default_precision
    LibGMP.mpf_get_default_prec
  end

  def self.default_precision=(prec : Int)
    LibGMP.mpf_set_default_prec(prec.to_u64)
  end

  def <=>(other : BigFloat)
    LibGMP.mpf_cmp(self, other)
  end

  def <=>(other : BigInt)
    LibGMP.mpf_cmp_z(self, other)
  end

  def <=>(other : Float::Primitive)
    LibGMP.mpf_cmp_d(self, other) unless other.nan?
  end

  def <=>(other : Int)
    Int.primitive_si_ui_check(other) do |si, ui, big_i|
      {
        si:    LibGMP.mpf_cmp_si(self, {{ si }}),
        ui:    LibGMP.mpf_cmp_ui(self, {{ ui }}),
        big_i: self <=> {{ big_i }},
      }
    end
  end

  def <=>(other : Number)
    LibGMP.mpf_cmp(self, other.to_big_f)
  end

  def - : BigFloat
    BigFloat.new { |mpf| LibGMP.mpf_neg(mpf, self) }
  end

  def +(other : Int::Primitive) : BigFloat
    Int.primitive_ui_check(other) do |ui, neg_ui, big_i|
      {
        ui:     BigFloat.new { |mpf| LibGMP.mpf_add_ui(mpf, self, {{ ui }}) },
        neg_ui: BigFloat.new { |mpf| LibGMP.mpf_sub_ui(mpf, self, {{ neg_ui }}) },
        big_i:  self + {{ big_i }},
      }
    end
  end

  def +(other : Number) : BigFloat
    BigFloat.new { |mpf| LibGMP.mpf_add(mpf, self, other.to_big_f) }
  end

  def -(other : Int::Primitive) : BigFloat
    Int.primitive_ui_check(other) do |ui, neg_ui, big_i|
      {
        ui:     BigFloat.new { |mpf| LibGMP.mpf_sub_ui(mpf, self, {{ ui }}) },
        neg_ui: BigFloat.new { |mpf| LibGMP.mpf_add_ui(mpf, self, {{ neg_ui }}) },
        big_i:  self - {{ big_i }},
      }
    end
  end

  def -(other : Number) : BigFloat
    BigFloat.new { |mpf| LibGMP.mpf_sub(mpf, self, other.to_big_f) }
  end

  def *(other : Int::Primitive) : BigFloat
    Int.primitive_ui_check(other) do |ui, neg_ui, big_i|
      {
        ui:     BigFloat.new { |mpf| LibGMP.mpf_mul_ui(mpf, self, {{ ui }}) },
        neg_ui: BigFloat.new { |mpf| LibGMP.mpf_mul_ui(mpf, self, {{ neg_ui }}); LibGMP.mpf_neg(mpf, mpf) },
        big_i:  self + {{ big_i }},
      }
    end
  end

  def *(other : Number) : BigFloat
    BigFloat.new { |mpf| LibGMP.mpf_mul(mpf, self, other.to_big_f) }
  end

  def /(other : Int::Primitive) : BigFloat
    # Division by 0 in BigFloat is not allowed, there is no BigFloat::Infinity
    raise DivisionByZeroError.new if other == 0
    Int.primitive_ui_check(other) do |ui, neg_ui, _|
      {
        ui:     BigFloat.new { |mpf| LibGMP.mpf_div_ui(mpf, self, {{ ui }}) },
        neg_ui: BigFloat.new { |mpf| LibGMP.mpf_div_ui(mpf, self, {{ neg_ui }}); LibGMP.mpf_neg(mpf, mpf) },
        big_i:  BigFloat.new { |mpf| LibGMP.mpf_div(mpf, self, BigFloat.new(other)) },
      }
    end
  end

  def /(other : BigFloat) : BigFloat
    # Division by 0 in BigFloat is not allowed, there is no BigFloat::Infinity
    raise DivisionByZeroError.new if other == 0
    BigFloat.new { |mpf| LibGMP.mpf_div(mpf, self, other) }
  end

  Number.expand_div [BigInt], BigFloat
  Number.expand_div [BigDecimal], BigDecimal
  Number.expand_div [BigRational], BigRational

  def **(other : BigInt) : BigFloat
    is_zero = self.zero?
    if is_zero
      case other
      when .>(0)
        return self
      when .<(0)
        # there is no BigFloat::Infinity
        raise ArgumentError.new "Cannot raise 0 to a negative power"
      end
    end

    BigFloat.new do |result|
      LibGMP.mpf_init_set_si(result, 1)
      next if is_zero # define `0 ** 0 == 1`

      # these are mutated and must be copies of `other` and `self`!
      exponent = BigInt.new { |mpz| LibGMP.abs(mpz, other) } # `other.abs`
      k = BigFloat.new { |mpf| LibGMP.mpf_set(mpf, self) }   # `self`

      while exponent > 0
        LibGMP.mpf_mul(result, result, k) if exponent.to_i!.odd? # `result *= k`
        LibGMP.fdiv_q_2exp(exponent, exponent, 1)                # `exponent /= 2`
        LibGMP.mpf_mul(k, k, k) if exponent > 0                  # `k *= k`
      end

      LibGMP.mpf_ui_div(result, 1, result) if other < 0 # `result = 1 / result`
    end
  end

  def **(other : Int) : BigFloat
    # there is no BigFloat::Infinity
    if zero? && other < 0
      raise ArgumentError.new "Cannot raise 0 to a negative power"
    end

    Int.primitive_ui_check(other) do |ui, neg_ui, big_i|
      {
        ui:     BigFloat.new { |mpf| LibGMP.mpf_pow_ui(mpf, self, {{ ui }}) },
        neg_ui: BigFloat.new { |mpf| LibGMP.mpf_pow_ui(mpf, self, {{ neg_ui }}); LibGMP.mpf_ui_div(mpf, 1, mpf) },
        big_i:  self ** {{ big_i }},
      }
    end
  end

  def abs : BigFloat
    BigFloat.new { |mpf| LibGMP.mpf_abs(mpf, self) }
  end

  # Rounds towards positive infinity.
  def ceil : BigFloat
    BigFloat.new { |mpf| LibGMP.mpf_ceil(mpf, self) }
  end

  # Rounds towards negative infinity.
  def floor : BigFloat
    BigFloat.new { |mpf| LibGMP.mpf_floor(mpf, self) }
  end

  # Rounds towards zero.
  def trunc : BigFloat
    BigFloat.new { |mpf| LibGMP.mpf_trunc(mpf, self) }
  end

  def to_f64 : Float64
    LibGMP.mpf_get_d(self)
  end

  def to_f32 : Float32
    to_f64.to_f32
  end

  def to_f : Float64
    to_f64
  end

  def to_f32! : Float32
    to_f64.to_f32!
  end

  def to_f64! : Float64
    to_f64
  end

  def to_f! : Float64
    to_f64!
  end

  def to_big_f : BigFloat
    self
  end

  def to_big_i : BigInt
    BigInt.new { |mpz| LibGMP.set_f(mpz, mpf) }
  end

  def to_i64 : Int64
    raise OverflowError.new unless LibGMP::Long::MIN <= self <= LibGMP::Long::MAX
    LibGMP.mpf_get_si(self).to_i64!
  end

  def to_i32 : Int32
    to_i64.to_i32
  end

  def to_i16 : Int16
    to_i64.to_i16
  end

  def to_i8 : Int8
    to_i64.to_i8
  end

  def to_i : Int32
    to_i32
  end

  def to_i! : Int32
    to_i32!
  end

  def to_i8! : Int8
    LibGMP.mpf_get_si(self).to_i8!
  end

  def to_i16! : Int16
    LibGMP.mpf_get_si(self).to_i16!
  end

  def to_i32! : Int32
    LibGMP.mpf_get_si(self).to_i32!
  end

  def to_i64! : Int64
    LibGMP.mpf_get_si(self).to_i64!
  end

  def to_u64 : UInt64
    raise OverflowError.new unless 0 <= self <= LibGMP::ULong::MAX
    LibGMP.mpf_get_ui(self).to_u64!
  end

  def to_u32 : UInt32
    to_u64.to_u32
  end

  def to_u16 : UInt16
    to_u64.to_u16
  end

  def to_u8 : UInt8
    to_u64.to_u8
  end

  def to_u : UInt32
    to_u32
  end

  def to_u! : UInt32
    to_u32!
  end

  def to_u8! : UInt8
    LibGMP.mpf_get_ui(self).to_u8!
  end

  def to_u16! : UInt16
    LibGMP.mpf_get_ui(self).to_u16!
  end

  def to_u32! : UInt32
    LibGMP.mpf_get_ui(self).to_u32!
  end

  def to_u64! : UInt64
    LibGMP.mpf_get_ui(self).to_u64!
  end

  def to_unsafe
    mpf
  end

  def to_s(io : IO) : Nil
    cstr = LibGMP.mpf_get_str(nil, out decimal_exponent, 10, 0, self)
    length = LibC.strlen(cstr)
    buffer = Slice.new(cstr, length)

    # add negative sign
    if buffer[0]? == 45 # '-'
      io << '-'
      buffer = buffer[1..]
      length -= 1
    end

    point = decimal_exponent
    exp = point
    exp_mode = point > 15 || point < -3
    point = 1 if exp_mode

    # add leading zero
    io << '0' if point < 1

    # add integer part digits
    if decimal_exponent > 0 && !exp_mode
      # whole number but not big enough to be exp form
      io.write_string buffer[0, {decimal_exponent, length}.min]
      buffer = buffer[{decimal_exponent, length}.min...]
      (point - length).times { io << '0' }
    elsif point > 0
      io.write_string buffer[0, point]
      buffer = buffer[point...]
    end

    io << '.'

    # add leading zeros after point
    if point < 0
      (-point).times { io << '0' }
    end

    # add fractional part digits
    io.write_string buffer

    # print trailing 0 if whole number or exp notation of power of ten
    if (decimal_exponent >= length && !exp_mode) || (exp != point && length == 1)
      io << '0'
    end

    # exp notation
    if exp != point
      io << 'e'
      io << '+' if exp > 0
      (exp - 1).to_s(io)
    end
  end

  def clone
    self
  end

  # Rounds towards the nearest integer. If both neighboring integers are equidistant,
  # rounds towards the even neighbor (Banker's rounding).
  def round_even : self
    if self >= 0
      halfway = self + 0.5
    else
      halfway = self - 0.5
    end
    if halfway.integer?
      if halfway == (halfway / 2).trunc * 2
        halfway
      else
        halfway - sign
      end
    else
      if self >= 0
        halfway.floor
      else
        halfway.ceil
      end
    end
  end

  # Rounds towards the nearest integer. If both neighboring integers are equidistant,
  # rounds away from zero.
  def round_away : self
    if self >= 0
      (self + 0.5).floor
    else
      (self - 0.5).ceil
    end
  end

  # :inherit:
  def integer? : Bool
    !LibGMP.mpf_integer_p(mpf).zero?
  end

  private def mpf
    pointerof(@mpf)
  end
end

struct Number
  include Comparable(BigFloat)

  def +(other : BigFloat)
    other + self
  end

  def -(other : BigFloat)
    to_big_f - other
  end

  def *(other : BigFloat) : BigFloat
    other * self
  end

  def /(other : BigFloat) : BigFloat
    to_big_f / other
  end

  def to_big_f : BigFloat
    BigFloat.new(self)
  end
end

struct Int
  def <=>(other : BigFloat)
    -(other <=> self)
  end

  def -(other : BigFloat) : BigFloat
    Int.primitive_ui_check(self) do |ui, neg_ui, _|
      {
        ui:     BigFloat.new { |mpf| LibGMP.mpf_neg(mpf, other); LibGMP.mpf_add_ui(mpf, mpf, {{ ui }}) },
        neg_ui: BigFloat.new { |mpf| LibGMP.mpf_neg(mpf, other); LibGMP.mpf_sub_ui(mpf, mpf, {{ neg_ui }}) },
        big_i:  BigFloat.new { |mpf| LibGMP.mpf_sub(mpf, BigFloat.new(self), other) },
      }
    end
  end

  def /(other : BigFloat) : BigFloat
    # Division by 0 in BigFloat is not allowed, there is no BigFloat::Infinity
    raise DivisionByZeroError.new if other == 0

    Int.primitive_ui_check(self) do |ui, neg_ui, _|
      {
        ui:     BigFloat.new { |mpf| LibGMP.mpf_ui_div(mpf, {{ ui }}, other) },
        neg_ui: BigFloat.new { |mpf| LibGMP.mpf_ui_div(mpf, {{ neg_ui }}, other); LibGMP.mpf_neg(mpf, mpf) },
        big_i:  BigFloat.new { |mpf| LibGMP.mpf_div(mpf, BigFloat.new(self), other) },
      }
    end
  end
end

struct Float
  def <=>(other : BigFloat)
    cmp = other <=> self
    -cmp if cmp
  end
end

class String
  # Converts `self` to a `BigFloat`.
  #
  # ```
  # require "big"
  # "1234.0".to_big_f
  # ```
  def to_big_f : BigFloat
    BigFloat.new(self)
  end
end

module Math
  # Decomposes the given floating-point *value* into a normalized fraction and an integral power of two.
  def frexp(value : BigFloat) : {BigFloat, Int64}
    LibGMP.mpf_get_d_2exp(out exp, value) # we need BigFloat frac, so will skip Float64 one.
    frac = BigFloat.new do |mpf|
      if exp >= 0
        LibGMP.mpf_div_2exp(mpf, value, exp)
      else
        LibGMP.mpf_mul_2exp(mpf, value, -exp)
      end
    end
    {frac, exp.to_i64}
  end

  # Calculates the square root of *value*.
  #
  # ```
  # require "big"
  #
  # Math.sqrt(1_000_000_000_000.to_big_f * 1_000_000_000_000.to_big_f) # => 1000000000000.0
  # ```
  def sqrt(value : BigFloat) : BigFloat
    BigFloat.new { |mpf| LibGMP.mpf_sqrt(mpf, value) }
  end
end

module Random
  private def rand_range(range : Range(BigFloat, BigFloat)) : BigFloat
    span = range.end - range.begin
    if range.exclusive?
      return range.begin + span*rand(1.0) if span > 0
    else
      return range.begin + span*rand if span >= 0
    end
    raise ArgumentError.new "Invalid range for rand: #{range}"
  end
end

# :nodoc:
struct Crystal::Hasher
  def self.reduce_num(value : BigFloat)
    float_normalize_wrap(value) do |value|
      # more exact version of `Math.frexp`
      LibGMP.mpf_get_d_2exp(out exp, value)
      frac = BigFloat.new do |mpf|
        if exp >= 0
          LibGMP.mpf_div_2exp(mpf, value, exp)
        else
          LibGMP.mpf_mul_2exp(mpf, value, -exp)
        end
      end
      float_normalize_reference(value, frac, exp)
    end
  end
end
