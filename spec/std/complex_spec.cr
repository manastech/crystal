require "spec"
require "complex"
require "big"
require "../support/number"
{% unless flag?(:wasm32) %}
  require "big"
{% end %}

# exact equality, including component signs
private def assert_complex_eq(z1 : Complex, z2 : Complex, *, file = __FILE__, line = __LINE__)
  z1.should eq(z2), file: file, line: line
  Math.copysign(1.0, z1.real).should eq(Math.copysign(1.0, z2.real)), file: file, line: line
  Math.copysign(1.0, z1.imag).should eq(Math.copysign(1.0, z2.imag)), file: file, line: line
end

private def assert_complex_nan(z : Complex, *, file = __FILE__, line = __LINE__)
  z.real.nan?.should be_true, file: file, line: line
  z.imag.nan?.should be_true, file: file, line: line
end

describe "Complex" do
  describe "as numbers" do
    it_can_convert_between([Complex], [Complex])
    it_can_convert_between({{BUILTIN_NUMBER_TYPES}}, [Complex])
    it_can_convert_between([Complex], {{BUILTIN_NUMBER_TYPES}})

    division_between_returns {{BUILTIN_NUMBER_TYPES}}, [Complex], Complex
    division_between_returns [Complex], {{BUILTIN_NUMBER_TYPES}}, Complex

    division_between_returns [Complex], [Complex], Complex
  end

  it "i" do
    a = 4.5 + 6.7.i
    b = Complex.new(4.5, 6.7)
    c = Complex.new(4.5, 9.6)
    a.should eq(b)
    a.should_not eq(c)
  end

  describe "==" do
    it "complex == complex" do
      a = Complex.new(1.5, 2)
      b = Complex.new(1.5, 2)
      c = Complex.new(2.25, 3)
      (a == b).should be_true
      (a == c).should be_false
    end

    it "complex == number" do
      a = Complex.new(5.3, 0)
      b = 5.3
      c = 4.2
      (a == b).should be_true
      (a == c).should be_false

      {% unless flag?(:wasm32) %}
        (a == BigDecimal.new(53, 1)).should be_false
      {% end %}
    end

    it "number == complex" do
      a = -1.75
      b = Complex.new(-1.75, 0)
      c = Complex.new(7.2, 0)
      (a == b).should be_true
      (a == c).should be_false

      {% unless flag?(:wasm32) %}
        (BigDecimal.new(72, 1) == c).should be_false
      {% end %}
    end
  end

  it "to_s" do
    Complex.new(1.25, 8.2).to_s.should eq("1.25 + 8.2i")
    Complex.new(1.25, -8.2).to_s.should eq("1.25 - 8.2i")

    Complex.new(+0.0, +0.0).to_s.should eq("0.0 + 0.0i")
    Complex.new(-0.0, -0.0).to_s.should eq("-0.0 - 0.0i")

    Complex.new(+Float64::INFINITY, +Float64::INFINITY).to_s.should eq("Infinity + Infinityi")
    Complex.new(-Float64::INFINITY, -Float64::INFINITY).to_s.should eq("-Infinity - Infinityi")

    pos_nan = Math.copysign(Float64::NAN, 1)
    neg_nan = Math.copysign(Float64::NAN, -1)
    Complex.new(pos_nan, pos_nan).to_s.should eq("NaN + NaNi")
    Complex.new(neg_nan, neg_nan).to_s.should eq("NaN + NaNi")
  end

  it "inspect" do
    Complex.new(1.25, 8.2).inspect.should eq("(1.25 + 8.2i)")
    Complex.new(1.25, -8.2).inspect.should eq("(1.25 - 8.2i)")

    Complex.new(+0.0, +0.0).inspect.should eq("(0.0 + 0.0i)")
    Complex.new(-0.0, -0.0).inspect.should eq("(-0.0 - 0.0i)")

    Complex.new(+Float64::INFINITY, +Float64::INFINITY).inspect.should eq("(Infinity + Infinityi)")
    Complex.new(-Float64::INFINITY, -Float64::INFINITY).inspect.should eq("(-Infinity - Infinityi)")

    pos_nan = Math.copysign(Float64::NAN, 1)
    neg_nan = Math.copysign(Float64::NAN, -1)
    Complex.new(pos_nan, pos_nan).inspect.should eq("(NaN + NaNi)")
    Complex.new(neg_nan, neg_nan).inspect.should eq("(NaN + NaNi)")
  end

  it "abs" do
    Complex.new(5.1, 9.7).abs.should eq(10.959014554237985)
  end

  it "abs2" do
    Complex.new(-1.1, 9).abs2.should eq(82.21)
  end

  describe "sign" do
    it "finite, non-zero" do
      Complex.new(-1.4, 7.7).sign.should be_close(Complex.new(-0.17888543819998315, 0.9838699100999074), 1e-14)
      Complex.new(1.4, -7.7).sign.should be_close(Complex.new(0.17888543819998315, -0.9838699100999074), 1e-14)
    end

    it "complex zero" do
      assert_complex_eq Complex.new(+0.0, +0.0).sign, Complex.new(+0.0, +0.0)
      assert_complex_eq Complex.new(+0.0, -0.0).sign, Complex.new(+0.0, -0.0)
      assert_complex_eq Complex.new(-0.0, +0.0).sign, Complex.new(-0.0, +0.0)
      assert_complex_eq Complex.new(-0.0, -0.0).sign, Complex.new(-0.0, -0.0)
    end

    it "real zero" do
      assert_complex_eq Complex.new(+0.0, +2.0).sign, Complex.new(+0.0, +1.0)
      assert_complex_eq Complex.new(+0.0, -2.0).sign, Complex.new(+0.0, -1.0)
      assert_complex_eq Complex.new(-0.0, +2.0).sign, Complex.new(-0.0, +1.0)
      assert_complex_eq Complex.new(-0.0, -2.0).sign, Complex.new(-0.0, -1.0)
    end

    it "imaginary zero" do
      assert_complex_eq Complex.new(+2.0, +0.0).sign, Complex.new(+1.0, +0.0)
      assert_complex_eq Complex.new(+2.0, -0.0).sign, Complex.new(+1.0, -0.0)
      assert_complex_eq Complex.new(-2.0, +0.0).sign, Complex.new(-1.0, +0.0)
      assert_complex_eq Complex.new(-2.0, -0.0).sign, Complex.new(-1.0, -0.0)
    end

    it "infinity" do
      inf = Float64::INFINITY

      # 1st quadrant
      assert_complex_eq Complex.new(+inf, +0.0).sign, Complex.new(+1.0, +0.0)
      assert_complex_eq Complex.new(+inf, +1.0).sign, Complex.new(+1.0, +0.0)
      assert_complex_eq Complex.new(+1.0, +inf).sign, Complex.new(+0.0, +1.0)
      assert_complex_eq Complex.new(+0.0, +inf).sign, Complex.new(+0.0, +1.0)

      # 2nd quadrant
      assert_complex_eq Complex.new(-0.0, +inf).sign, Complex.new(-0.0, +1.0)
      assert_complex_eq Complex.new(-1.0, +inf).sign, Complex.new(-0.0, +1.0)
      assert_complex_eq Complex.new(-inf, +1.0).sign, Complex.new(-1.0, +0.0)
      assert_complex_eq Complex.new(-inf, +0.0).sign, Complex.new(-1.0, +0.0)

      # 3rd quadrant
      assert_complex_eq Complex.new(-inf, -0.0).sign, Complex.new(-1.0, -0.0)
      assert_complex_eq Complex.new(-inf, -1.0).sign, Complex.new(-1.0, -0.0)
      assert_complex_eq Complex.new(-1.0, -inf).sign, Complex.new(-0.0, -1.0)
      assert_complex_eq Complex.new(-0.0, -inf).sign, Complex.new(-0.0, -1.0)

      # 4th quadrant
      assert_complex_eq Complex.new(+0.0, -inf).sign, Complex.new(+0.0, -1.0)
      assert_complex_eq Complex.new(+1.0, -inf).sign, Complex.new(+0.0, -1.0)
      assert_complex_eq Complex.new(+inf, -1.0).sign, Complex.new(+1.0, -0.0)
      assert_complex_eq Complex.new(+inf, -0.0).sign, Complex.new(+1.0, -0.0)

      # diagonals
      sqr = Math.sqrt(0.5)
      Complex.new(+inf, +inf).sign.should be_close(Complex.new(+sqr, +sqr), 1e-14)
      Complex.new(-inf, +inf).sign.should be_close(Complex.new(-sqr, +sqr), 1e-14)
      Complex.new(-inf, -inf).sign.should be_close(Complex.new(-sqr, -sqr), 1e-14)
      Complex.new(+inf, -inf).sign.should be_close(Complex.new(+sqr, -sqr), 1e-14)
    end

    it "not-a-number" do
      assert_complex_nan Complex.new(Float64::NAN, +0.0).sign
      assert_complex_nan Complex.new(Float64::NAN, +1.0).sign
      assert_complex_nan Complex.new(Float64::NAN, Float64::INFINITY).sign
      assert_complex_nan Complex.new(-0.0, Float64::NAN).sign
      assert_complex_nan Complex.new(-1.0, Float64::NAN).sign
      assert_complex_nan Complex.new(-Float64::INFINITY, Float64::NAN).sign
      assert_complex_nan Complex.new(Float64::NAN, Float64::NAN).sign
      assert_complex_nan Complex.new(Float64::NAN, Float64::NAN).sign
      assert_complex_nan Complex.new(Float64::NAN, Float64::NAN).sign
      assert_complex_nan Complex.new(Float64::NAN, Float64::NAN).sign
    end
  end

  it "phase" do
    Complex.new(11.5, -6.25).phase.should eq(-0.4978223326170012)
  end

  it "polar" do
    Complex.new(7.25, -13.1).polar.should eq({14.972391258579906, -1.0653196179316864})
  end

  it "cis" do
    {% if flag?(:aarch64) && flag?(:darwin) %}
      2.4.cis.should eq(Complex.new(-0.7373937155412454, 0.6754631805511511))
    {% else %}
      2.4.cis.should eq(Complex.new(-0.7373937155412454, 0.675463180551151))
    {% end %}
  end

  it "conj" do
    Complex.new(10.1, 3.7).conj.should eq(Complex.new(10.1, -3.7))
  end

  it "inv" do
    Complex.new(1.5, -2.5).inv.should eq(Complex.new(0.17647058823529413, 0.29411764705882354))
  end

  describe "+" do
    it "+ complex" do
      (+Complex.new(-5.43, -27.12)).should eq(Complex.new(-5.43, -27.12))
    end

    it "complex + complex" do
      (Complex.new(2.2, 7) + Complex.new(10.1, 1.34)).should eq(Complex.new(12.3, 8.34))
    end

    it "complex + number" do
      (Complex.new(0.3, 5.5) + 15).should eq(Complex.new(15.3, 5.5))
    end

    it "number + complex" do
      (-1.7 + Complex.new(7, 4.1)).should eq(Complex.new(5.3, 4.1))
    end
  end

  describe "-" do
    it "- complex" do
      (-Complex.new(5.43, 27.12)).should eq(Complex.new(-5.43, -27.12))
    end

    it "complex - complex" do
      (Complex.new(21.7, 2.0) - Complex.new(0.15, 3.4)).should eq(Complex.new(21.55, -1.4))
    end

    it "complex - number" do
      (Complex.new(8.1, 6.15) - 15).should eq(Complex.new(-6.9, 6.15))
    end

    it "number - complex" do
      (-3.27 - Complex.new(7, 5.1)).should eq(Complex.new(-10.27, -5.1))
    end
  end

  describe "*" do
    it "complex * complex" do
      (Complex.new(12.2, 9.8)*Complex.new(4.78, 2.86)).should eq(Complex.new(30.288, 81.736))
    end

    it "complex * number" do
      (Complex.new(11.3, 15.25)*1.2).should eq(Complex.new(13.56, 18.3))
    end

    it "number * complex" do
      (-1.7*Complex.new(9.7, 3.22)).should eq(Complex.new(-16.49, -5.474))
    end
  end

  describe "/" do
    it "complex / complex" do
      ((Complex.new(4, 6.2))/(Complex.new(0.5, 2.7))).should eq(Complex.new(2.485411140583554, -1.0212201591511936))
      ((Complex.new(4.1, 6.0))/(Complex.new(10, 2.2))).should eq(Complex.new(0.5169782525753529, 0.48626478443342236))

      (1.to_c / -1.to_c).should eq(-1.to_c)
      assert_complex_nan 1.to_c / Float64::NAN

      (1.to_c / 0.to_c).real.abs.should eq(Float64::INFINITY)
      (1.to_c / 0.to_c).imag.nan?.should be_true
    end

    it "complex / number" do
      ((Complex.new(21.3, 5.8))/1.9).should eq(Complex.new(11.210526315789474, 3.0526315789473686))
    end

    it "number / complex" do
      (-5.7/(Complex.new(2.27, 8.92))).should eq(Complex.new(-0.1527278908111847, 0.6001466017778712))
    end
  end

  describe "**" do
    it "complex ** complex" do
      (Complex.polar(Math::E, 1)**Complex.new(1, 2)).should be_close(Complex.polar(1/Math::E, 3), 1e-8)
    end

    it "number ** complex" do
      (Math::E**Complex.new(1, 2)).should be_close(Complex.polar(Math::E, 2), 1e-8)
      (1**Complex.new(1, 2)).should be_close(Complex.new(1), 1e-8)
      (1.0**Complex.new(1, 2)).should be_close(Complex.new(1), 1e-8)
      (1.to_c**Complex.new(1, 2)).should be_close(Complex.new(1), 1e-8)
      (BigInt.new(1)**Complex.new(1, 2)).should be_close(Complex.new(1), 1e-8)
      (BigFloat.new(1)**Complex.new(1, 2)).should be_close(Complex.new(1), 1e-8)
      (BigDecimal.new(1)**Complex.new(1, 2)).should be_close(Complex.new(1), 1e-8)
      (BigRational.new(1)**Complex.new(1, 2)).should be_close(Complex.new(1), 1e-8)
    end

    it "complex ** number" do
      (Complex.new(1, 2)**2).should be_close(Complex.new(-3, 4), 1e-8)
      (Complex.new(1, 2)**2.0).should be_close(Complex.new(-3, 4), 1e-8)
      (Complex.new(1, 2)**2.to_c).should be_close(Complex.new(-3, 4), 1e-8)
      (Complex.new(1, 2)**BigInt.new(2)).should be_close(Complex.new(-3, 4), 1e-8)
      (Complex.new(1, 2)**BigFloat.new(2)).should be_close(Complex.new(-3, 4), 1e-8)
      (Complex.new(1, 2)**BigDecimal.new(2)).should be_close(Complex.new(-3, 4), 1e-8)
      (Complex.new(1, 2)**BigRational.new(2)).should be_close(Complex.new(-3, 4), 1e-8)
    end

    it "complex ** 0" do
      (Complex.new(1, 2)**0).should be_close(Complex.new(1), 1e-8)
      (Complex.new(1, 2)**0.0).should be_close(Complex.new(1), 1e-8)
      (Complex.new(1, 2)**0.to_c).should be_close(Complex.new(1), 1e-8)
      (Complex.new(1, 2)**BigInt.new(0)).should be_close(Complex.new(1), 1e-8)
      (Complex.new(1, 2)**BigFloat.new(0)).should be_close(Complex.new(1), 1e-8)
      (Complex.new(1, 2)**BigDecimal.new(0)).should be_close(Complex.new(1), 1e-8)
      (Complex.new(1, 2)**BigRational.new(0)).should be_close(Complex.new(1), 1e-8)
    end

    it "complex ** 1" do
      (Complex.new(1, 2)**1).should be_close(Complex.new(1, 2), 1e-8)
      (Complex.new(1, 2)**1.0).should be_close(Complex.new(1, 2), 1e-8)
      (Complex.new(1, 2)**1.to_c).should be_close(Complex.new(1, 2), 1e-8)
      (Complex.new(1, 2)**BigInt.new(1)).should be_close(Complex.new(1, 2), 1e-8)
      (Complex.new(1, 2)**BigFloat.new(1)).should be_close(Complex.new(1, 2), 1e-8)
      (Complex.new(1, 2)**BigDecimal.new(1)).should be_close(Complex.new(1, 2), 1e-8)
      (Complex.new(1, 2)**BigRational.new(1)).should be_close(Complex.new(1, 2), 1e-8)
    end

    it "0 ** 0" do
      (Complex.zero**0).should eq(Complex.new(1))
      (Complex.zero**0.0).should eq(Complex.new(1))
      (Complex.zero**0.to_c).should eq(Complex.new(1))
      (Complex.zero**BigInt.new(0)).should eq(Complex.new(1))
      (Complex.zero**BigFloat.new(0)).should eq(Complex.new(1))
      (Complex.zero**BigDecimal.new(0)).should eq(Complex.new(1))
      (Complex.zero**BigRational.new(0)).should eq(Complex.new(1))
    end

    it "0 ** 1" do
      (Complex.zero**1).should eq(Complex.zero)
      (Complex.zero**1.0).should eq(Complex.zero)
      (Complex.zero**1.to_c).should eq(Complex.zero)
      (Complex.zero**BigInt.new(1)).should eq(Complex.zero)
      (Complex.zero**BigFloat.new(1)).should eq(Complex.zero)
      (Complex.zero**BigDecimal.new(1)).should eq(Complex.zero)
      (Complex.zero**BigRational.new(1)).should eq(Complex.zero)
    end

    it "0 ** -1" do
      z = Complex.zero ** (-1)
      z.real.infinite?.should eq(1)
      z.imag.zero?.should be_true

      z = Complex.zero ** (-1.0)
      z.real.infinite?.should eq(1)
      z.imag.zero?.should be_true

      z = Complex.zero ** (-1).to_c
      z.real.infinite?.should eq(1)
      z.imag.zero?.should be_true

      z = Complex.zero ** BigInt.new(-1)
      z.real.infinite?.should eq(1)
      z.imag.zero?.should be_true

      z = Complex.zero ** BigFloat.new(-1)
      z.real.infinite?.should eq(1)
      z.imag.zero?.should be_true

      z = Complex.zero ** BigDecimal.new(-1)
      z.real.infinite?.should eq(1)
      z.imag.zero?.should be_true

      z = Complex.zero ** BigRational.new(-1)
      z.real.infinite?.should eq(1)
      z.imag.zero?.should be_true
    end

    it "0 ** complex" do
      (Complex.zero**Complex.new(1, 1)).should eq(Complex.zero)

      z = Complex.zero ** Complex.new(-1, 1)
      z.real.nan?.should be_true
      z.imag.nan?.should be_true
    end

    it "i ** 1" do
      (Complex.new(0, 1)**1).should eq(Complex.new(0, 1))
      (Complex.new(0, 1)**1.0).should eq(Complex.new(0, 1))
      (Complex.new(0, 1)**1.to_c).should eq(Complex.new(0, 1))
      (Complex.new(0, 1)**BigInt.new(1)).should eq(Complex.new(0, 1))
      (Complex.new(0, 1)**BigFloat.new(1)).should eq(Complex.new(0, 1))
      (Complex.new(0, 1)**BigDecimal.new(1)).should eq(Complex.new(0, 1))
      (Complex.new(0, 1)**BigRational.new(1)).should eq(Complex.new(0, 1))
    end

    it "i ** 2" do
      (Complex.new(0, 1)**2).should eq(Complex.new(-1))
      (Complex.new(0, 1)**2.0).should eq(Complex.new(-1))
      (Complex.new(0, 1)**2.to_c).should eq(Complex.new(-1))
      (Complex.new(0, 1)**BigInt.new(2)).should eq(Complex.new(-1))
      (Complex.new(0, 1)**BigFloat.new(2)).should eq(Complex.new(-1))
      (Complex.new(0, 1)**BigDecimal.new(2)).should eq(Complex.new(-1))
      (Complex.new(0, 1)**BigRational.new(2)).should eq(Complex.new(-1))
    end

    it "-1 ** 1" do
      (Complex.new(-1)**1).should eq(Complex.new(-1))
      (Complex.new(-1)**1.0).should eq(Complex.new(-1))
      (Complex.new(-1)**1.to_c).should eq(Complex.new(-1))
      (Complex.new(-1)**BigInt.new(1)).should eq(Complex.new(-1))
      (Complex.new(-1)**BigFloat.new(1)).should eq(Complex.new(-1))
      (Complex.new(-1)**BigDecimal.new(1)).should eq(Complex.new(-1))
      (Complex.new(-1)**BigRational.new(1)).should eq(Complex.new(-1))
    end

    it "-1 ** 2" do
      (Complex.new(-1)**2).should eq(Complex.new(1))
      (Complex.new(-1)**2.0).should eq(Complex.new(1))
      (Complex.new(-1)**2.to_c).should eq(Complex.new(1))
      (Complex.new(-1)**BigInt.new(2)).should eq(Complex.new(1))
      (Complex.new(-1)**BigFloat.new(2)).should eq(Complex.new(1))
      (Complex.new(-1)**BigDecimal.new(2)).should eq(Complex.new(1))
      (Complex.new(-1)**BigRational.new(2)).should eq(Complex.new(1))
    end

    it "-1 ** 0.5" do
      (Complex.new(-1)**0.5_f64).should eq(Complex.new(0, 1))
      (Complex.new(-1)**0.5_f32).should eq(Complex.new(0, 1))
      (Complex.new(-1)**0.5.to_c).should eq(Complex.new(0, 1))
      (Complex.new(-1)**BigFloat.new(0.5)).should eq(Complex.new(0, 1))
      (Complex.new(-1)**BigDecimal.new(0.5)).should eq(Complex.new(0, 1))
      (Complex.new(-1)**BigRational.new(1, 2)).should eq(Complex.new(0, 1))
    end

    it "(-inf) ** 2" do
      z = (-Float64::INFINITY).to_c ** 2
      z.real.infinite?.should eq(1)
      z.imag.zero?.should be_true

      z = (-Float64::INFINITY).to_c ** 2.0
      z.real.infinite?.should eq(1)
      z.imag.zero?.should be_true

      z = (-Float64::INFINITY).to_c ** 2.to_c
      z.real.infinite?.should eq(1)
      z.imag.zero?.should be_true

      z = (-Float64::INFINITY).to_c ** BigInt.new(2)
      z.real.infinite?.should eq(1)
      z.imag.zero?.should be_true

      z = (-Float64::INFINITY).to_c ** BigFloat.new(2)
      z.real.infinite?.should eq(1)
      z.imag.zero?.should be_true

      z = (-Float64::INFINITY).to_c ** BigDecimal.new(2)
      z.real.infinite?.should eq(1)
      z.imag.zero?.should be_true

      z = (-Float64::INFINITY).to_c ** BigRational.new(2)
      z.real.infinite?.should eq(1)
      z.imag.zero?.should be_true
    end
  end

  it "clones" do
    c = Complex.new(4, 6.2)
    c.clone.should eq(c)
  end

  it "hashes real without imag like real only" do
    c = Complex.new(4, 0)
    c.hash.should eq(4_f64.hash)
  end

  it "test zero" do
    Complex.zero.should eq(Complex.new(0, 0))
  end

  it "test zero?" do
    Complex.new(0, 0).zero?.should eq true
    Complex.new(0, 3.4).zero?.should eq false
    Complex.new(1.2, 0).zero?.should eq false
    Complex.new(1.2, 3.4).zero?.should eq false
  end

  it "test additive_identity" do
    Complex.additive_identity.should eq(Complex.new(0, 0))
  end

  it "test multiplicative_identity" do
    Complex.multiplicative_identity.should eq(Complex.new(1, 0))
  end

  it "rounds" do
    (Complex.new(1.125, 0.875).round(2)).should eq(Complex.new(1.12, 0.88))
    (Complex.new(1.135, 0.865).round(2)).should eq(Complex.new(1.14, 0.86))
    (Complex.new(1.125, 0.875).round(digits: 1)).should eq(Complex.new(1.1, 0.9))
  end

  describe "Math" do
    it "exp" do
      Math.exp(Complex.new(1.15, -5.1)).should be_close(Complex.new(1.1937266270566773, 2.923901365414129), 1e-15)
    end

    it "log" do
      Math.log(Complex.new(1.25, -4.7)).should eq(Complex.new(1.5817344087982312, -1.3108561866063686))
    end

    it "log2" do
      Math.log2(Complex.new(-9.1, 3.2)).should eq(Complex.new(3.2699671225858946, +4.044523592551345))
    end

    it "log10" do
      Math.log10(Complex.new(2.11, 1.21)).should eq(Complex.new(0.38602142355392594, +0.22612668967405536))
    end

    it "sqrt" do
      Math.sqrt(Complex.new(1.32, 7.25)).should be_close(Complex.new(2.0843687106374236, 1.739135682425128), 1e-15)
      Math.sqrt(Complex.new(7.11, -0.9)).should be_close(Complex.new(2.671772413453534, -0.1684275194002508), 1e-15)
      Math.sqrt(Complex.new(-2.2, 6.22)).should be_close(Complex.new(1.4828360708935342, 2.0973323087062226), 1e-15)
      Math.sqrt(Complex.new(-8.3, -1.11)).should be_close(Complex.new(0.1922159681400434, -2.8873771797962275), 1e-15)
    end
  end
end
