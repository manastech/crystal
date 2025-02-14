# A complex number is a number represented in the form a + bi. In this form,
# a and b are real numbers, and i is an imaginary number such as i² = -1.
# The a is the real part of the number, and the b is the imaginary part of
# the number.
#
# NOTE: To use `Complex`, you must explicitly import it with `require "complex"`
#
# ```
# require "complex"
#
# Complex.new(1, 0)   # => 1.0 + 0.0.i
# Complex.new(5, -12) # => 5.0 - 12.0.i
#
# 1.to_c # => 1.0 + 0.0.i
# 1.i    # => 0.0 + 1.0.i
# ```
struct Complex
  # Returns the real part.
  getter real : Float64

  # Returns the imaginary part.
  getter imag : Float64

  def initialize(real : Number, imag : Number = 0)
    @real = real.to_f
    @imag = imag.to_f
  end

  def self.new(c : Complex)
    c
  end

  # Returns a complex number which denotes the given polar form.
  def self.polar(abs : Number, phase : Number = 0)
    new(abs*Math.cos(phase), abs*Math.sin(phase))
  end

  # Determines whether `self` equals *other* or not.
  def ==(other : Complex)
    @real == other.real && @imag == other.imag
  end

  # :ditto:
  def ==(other : Number)
    @real == other && @imag.zero?
  end

  # :ditto:
  def ==(other)
    false
  end

  # Returns `self`.
  def to_c
    self
  end

  # Returns the value as a `Float64` if possible (the imaginary part should be exactly zero),
  # raises otherwise.
  def to_f64 : Float64
    unless @imag.zero?
      raise Exception.new "Complex number with non-zero imaginary part can't be converted to real number"
    end
    @real
  end

  # See `#to_f64`.
  def to_f
    to_f64
  end

  delegate to_i128, to_i64, to_i32, to_i16, to_i8, to: to_f64
  delegate to_u128, to_u64, to_u32, to_u16, to_u8, to: to_f64
  delegate to_f32, to: to_f64

  # See `#to_i32`.
  def to_i
    to_i32
  end

  # Writes this complex object to an *io*.
  #
  # ```
  # require "complex"
  #
  # Complex.new(42, 2).to_s # => "42.0 + 2.0i"
  # ```
  def to_s(io : IO) : Nil
    io << @real
    io << (@imag.nan? || Math.copysign(1.0, @imag) > 0 ? " + " : " - ")
    io << Math.copysign(@imag, 1.0)
    io << 'i'
  end

  # Writes this complex object to an *io*, surrounded by parentheses.
  #
  # ```
  # require "complex"
  #
  # Complex.new(42, 2).inspect # => "(42.0 + 2.0i)"
  # ```
  def inspect(io : IO) : Nil
    io << '('
    to_s(io)
    io << ')'
  end

  # Returns the absolute value of this complex number in a
  # number form, using the Pythagorean theorem.
  #
  # ```
  # require "complex"
  #
  # Complex.new(42, 2).abs  # => 42.04759208325728
  # Complex.new(-42, 2).abs # => 42.04759208325728
  # ```
  def abs : Float64
    Math.hypot(@real, @imag)
  end

  # Returns the square of absolute value in a number form.
  #
  # ```
  # require "complex"
  #
  # Complex.new(42, 2).abs2 # => 1768
  # ```
  def abs2 : Float64
    @real * @real + @imag * @imag
  end

  # Returns the complex sign of `self`.
  #
  # If `self` is non-zero, the returned value has the same phase as `self` and
  # absolute value `1.0`. If `self` is zero, returns `self`.
  #
  # The returned value's real and imaginary components always have the same
  # signs as the respective components of `self`.
  #
  # ```
  # require "complex"
  #
  # Complex.new(7, -24).sign        # => (0.28 - 0.96.i)
  # Complex.new(1.0 / 0.0, 24).sign # => (1.0 + 0.0.i)
  # Complex.new(-0.0, +0.0).sign    # => (-0.0 + 0.0.i)
  # ```
  def sign : Complex
    return self if zero?

    if @real.nan? || @imag.nan?
      return Complex.new(Float64::NAN, Float64::NAN)
    end

    return Complex.new(@real.sign, @imag) if @real != 0 && @imag == 0
    return Complex.new(@real, @imag.sign) if @real == 0 && @imag != 0

    case {real_inf_sign = @real.infinite?, imag_inf_sign = @imag.infinite?}
    in {Nil, Nil}
      phase.cis
    in {Nil, Int32}
      Complex.new(Math.copysign(0.0, @real), imag_inf_sign)
    in {Int32, Nil}
      Complex.new(real_inf_sign, Math.copysign(0.0, @imag))
    in {Int32, Int32}
      sqrt = Math.sqrt(0.5)
      Complex.new(sqrt * real_inf_sign, sqrt * imag_inf_sign)
    end
  end

  # Returns the phase of `self`.
  def phase : Float64
    Math.atan2(@imag, @real)
  end

  # Returns a `Tuple` with the `abs` value and the `phase`.
  #
  # ```
  # require "complex"
  #
  # Complex.new(42, 2).polar # => {42.047592083257278, 0.047583103276983396}
  # ```
  def polar : {Float64, Float64}
    {abs, phase}
  end

  # Returns the conjugate of `self`.
  #
  # ```
  # require "complex"
  #
  # Complex.new(42, 2).conj  # => 42.0 - 2.0.i
  # Complex.new(42, -2).conj # => 42.0 + 2.0.i
  # ```
  def conj : Complex
    Complex.new(@real, -@imag)
  end

  # Returns the inverse of `self`.
  def inv : Complex
    conj / abs2
  end

  # Returns `self`.
  def + : Complex
    self
  end

  # Adds the value of `self` to *other*.
  def +(other : Complex) : Complex
    Complex.new(@real + other.real, @imag + other.imag)
  end

  # :ditto:
  def +(other : Number) : Complex
    Complex.new(@real + other, @imag)
  end

  # Returns the opposite of `self`.
  def - : Complex
    Complex.new(-@real, -@imag)
  end

  # Removes the value of *other* from `self`.
  def -(other : Complex) : Complex
    Complex.new(@real - other.real, @imag - other.imag)
  end

  # :ditto:
  def -(other : Number) : Complex
    Complex.new(@real - other, @imag)
  end

  # Multiplies `self` by *other*.
  def *(other : Complex) : Complex
    Complex.new(@real * other.real - @imag * other.imag, @real * other.imag + @imag * other.real)
  end

  # :ditto:
  def *(other : Number) : Complex
    Complex.new(@real * other, @imag * other)
  end

  # Divides `self` by *other*.
  def /(other : Complex) : Complex
    if other.real.nan? || other.imag.nan?
      Complex.new(Float64::NAN, Float64::NAN)
    elsif other.imag.abs < other.real.abs
      r = other.imag / other.real
      d = other.real + r * other.imag

      if d.nan? || d == 0
        Complex.new(Float64::NAN, Float64::NAN)
      else
        Complex.new((@real + @imag * r) / d, (@imag - @real * r) / d)
      end
    elsif other.imag == 0 # other.real == 0
      Complex.new(@real / other.real, @imag / other.real)
    else # 0 < other.real.abs <= other.imag.abs
      r = other.real / other.imag
      d = other.imag + r * other.real

      if d.nan? || d == 0
        Complex.new(Float64::NAN, Float64::NAN)
      else
        Complex.new((@real * r + @imag) / d, (@imag * r - @real) / d)
      end
    end
  end

  # :ditto:
  def /(other : Number) : Complex
    Complex.new(@real / other, @imag / other)
  end

  # Returns the base `self` exponential of *other*.
  def **(other : Complex) : Complex
    return self ** other.real if other.imag.zero?
    return Complex.zero if zero? && other.real > 0
    abs, phase = polar
    Complex.polar((abs**other.real) / Math.exp(phase*other.imag), phase*other.real + Math.log(abs)*other.imag)
  end

  # :ditto:
  def **(other : Number) : Complex
    if @imag.zero?
      return Complex.new(@real ** other) if @real >= 0
      r = (-@real) ** other
      k = other * 2
    else
      return Complex.polar(abs**other, phase*other.to_f64) unless @real.zero?
      if @imag > 0
        r = @imag ** other
        k = other
      else
        r = (-@imag) ** other
        k = other * 3
      end
    end

    n = k.to_i64
    return Complex.polar(r, k.to_f64 * Math::PI/2) unless n == k
    case n % 4
    when 0 then Complex.new(r, 0)
    when 1 then Complex.new(0, r)
    when 2 then Complex.new(-r, 0)
    else        Complex.new(0, -r)
    end
  end

  # :ditto:
  def **(other : Int) : Complex
    return Complex.new(@real ** other) if @imag.zero?
    if @real.zero?
      power = @imag ** other
      case other % 4
      when 0 then Complex.new(power, 0)
      when 1 then Complex.new(0, power)
      when 2 then Complex.new(-power, 0)
      else        Complex.new(0, -power)
      end
    else
      Complex.polar(abs ** other, phase * other.to_f64)
    end
  end

  def clone
    self
  end

  # See `Object#hash(hasher)`
  def hash(hasher)
    hasher = real.hash(hasher)
    hasher = imag.hash(hasher) unless imag.zero?
    hasher
  end

  # Returns the number `0` in complex form.
  def self.zero : Complex
    new 0, 0
  end

  # Returns `true` if the complex number is zero.
  # This means the real and imaginary are both zero.
  #
  # ```
  # require "complex"
  #
  # Complex.new(0, 0).zero? # => true
  # Complex.new(1, 0).zero? # => false
  # Complex.new(0, 1).zero? # => false
  # ````
  def zero? : Bool
    @real == 0 && @imag == 0
  end

  def self.additive_identity : self
    zero
  end

  def self.multiplicative_identity : self
    new 1, 0
  end

  # Rounds to the nearest *digits*.
  def round(digits = 0) : Complex
    Complex.new(@real.round(digits), @imag.round(digits))
  end
end

struct Number
  # Returns a `Complex` object with the value of `self` as the real part.
  def to_c : Complex
    Complex.new(self, 0)
  end

  # Returns a `Complex` object with the value of `self` as the imaginary part.
  def i : Complex
    Complex.new(0, self)
  end

  def ==(other : Complex)
    other == self
  end

  # [Cis](https://en.wikipedia.org/wiki/Cis_(mathematics)) is a mathematical notation representing `cos x + i sin x`.
  #
  # Returns a `Complex` object with real part `Math.cos(self)` and imaginary part `Math.sin(self)`, where `self` represents the angle in radians.
  def cis : Complex
    Complex.new(Math.cos(self), Math.sin(self))
  end

  def +(other : Complex) : Complex
    Complex.new(self + other.real, other.imag)
  end

  def -(other : Complex) : Complex
    Complex.new(self - other.real, -other.imag)
  end

  def *(other : Complex) : Complex
    Complex.new(self * other.real, self * other.imag)
  end

  def /(other : Complex) : Complex
    self * other.inv
  end

  def **(other : Complex) : Complex
    self.to_c ** other
  end
end

struct Float64
  def **(other : Complex) : Complex
    self.to_c ** other
  end
end

struct Float32
  def **(other : Complex) : Complex
    self.to_c ** other
  end
end

module Math
  # Calculates the exponential of *value*.
  #
  # ```
  # require "complex"
  #
  # Math.exp(4 + 2.i) # => -22.720847417619233 + 49.645957334580565.i
  # ```
  def exp(value : Complex) : Complex
    r = exp(value.real)
    Complex.new(r * cos(value.imag), r * sin(value.imag))
  end

  # Calculates the natural logarithm of *value*.
  #
  # ```
  # require "complex"
  #
  # Math.log(4 + 2.i) # => 1.4978661367769956 + 0.4636476090008061.i
  # ```
  def log(value : Complex) : Complex
    Complex.new(Math.log(value.abs), value.phase)
  end

  # Calculates the logarithm of *value* to base 2.
  #
  # ```
  # require "complex"
  #
  # Math.log2(4 + 2.i) # => 2.1609640474436813 + 0.6689021062254881.i
  # ```
  def log2(value : Complex) : Complex
    log(value) / LOG2
  end

  # Calculates the logarithm of *value* to base 10.
  #
  # ```
  # require "complex"
  #
  # Math.log10(4 + 2.i) # => 0.6505149978319906 + 0.20135959813668655.i
  # ```
  def log10(value : Complex) : Complex
    log(value) / LOG10
  end

  # Calculates the square root of *value*.
  # Inspired by the [following blog post](https://pavpanchekha.com/blog/casio-mathjs.html) of Pavel Panchekha on floating point precision.
  #
  # ```
  # require "complex"
  #
  # Math.sqrt(4 + 2.i) # => 2.0581710272714924 + 0.48586827175664565.i
  # ```
  #
  # Although the imaginary number is defined as i = sqrt(-1),
  # calling `Math.sqrt` with a negative number will return `-NaN`.
  # To obtain the result in the complex plane, `Math.sqrt` must
  # be called with a complex number.
  #
  # ```
  # Math.sqrt(-1.0)         # => -NaN
  # Math.sqrt(-1.0 + 0.0.i) # => 0.0 + 1.0.i
  # ```
  def sqrt(value : Complex) : Complex
    r = value.abs

    re = if value.real >= 0
           0.5 * sqrt(2.0 * (r + value.real))
         else
           value.imag.abs / sqrt(2.0 * (r - value.real))
         end

    im = if value.real <= 0
           0.5 * sqrt(2.0 * (r - value.real))
         else
           value.imag.abs / sqrt(2.0 * (r + value.real))
         end

    Complex.new(re, value.imag >= 0 ? im : -im)
  end
end
