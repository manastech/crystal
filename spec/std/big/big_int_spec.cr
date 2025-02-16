require "spec"
require "big"

private def it_converts_to_s(num, str, *, file = __FILE__, line = __LINE__, **opts)
  it file: file, line: line do
    num.to_s(**opts).should eq(str), file: file, line: line
    String.build { |io| num.to_s(io, **opts) }.should eq(str), file: file, line: line
  end
end

describe "BigInt" do
  describe "#integer?" do
    it { BigInt.zero.integer?.should be_true }
    it { 12345.to_big_i.integer?.should be_true }
  end

  it "creates with a value of zero" do
    BigInt.new.to_s.should eq("0")
  end

  it "creates from signed ints" do
    BigInt.new(-1_i8).to_s.should eq("-1")
    BigInt.new(-1_i16).to_s.should eq("-1")
    BigInt.new(-1_i32).to_s.should eq("-1")
    BigInt.new(-1_i64).to_s.should eq("-1")
  end

  it "creates from unsigned ints" do
    BigInt.new(1_u8).to_s.should eq("1")
    BigInt.new(1_u16).to_s.should eq("1")
    BigInt.new(1_u32).to_s.should eq("1")
    BigInt.new(1_u64).to_s.should eq("1")
  end

  it "creates from string" do
    BigInt.new("12345678").to_s.should eq("12345678")
    BigInt.new("123_456_78").to_s.should eq("12345678")
    BigInt.new("+12345678").to_s.should eq("12345678")
    BigInt.new("-12345678").to_s.should eq("-12345678")
  end

  it "raises if creates from string but invalid" do
    expect_raises ArgumentError, "Invalid BigInt: 123 hello 456" do
      BigInt.new("123 hello 456")
    end
  end

  it "raises if creating from infinity" do
    expect_raises(ArgumentError, "Can only construct from a finite number") { BigInt.new(Float32::INFINITY) }
    expect_raises(ArgumentError, "Can only construct from a finite number") { BigInt.new(Float64::INFINITY) }
  end

  it "raises if creating from NaN" do
    expect_raises(ArgumentError, "Can only construct from a finite number") { BigInt.new(Float32::NAN) }
    expect_raises(ArgumentError, "Can only construct from a finite number") { BigInt.new(Float64::NAN) }
  end

  it "creates from float" do
    BigInt.new(12.3).to_s.should eq("12")
  end

  it "compares" do
    1.to_big_i.should eq(1.to_big_i)
    1.to_big_i.should eq(1)
    1.to_big_i.should eq(1_u8)

    [3.to_big_i, 2.to_big_i, 10.to_big_i, 4, 8_u8].sort.should eq([2, 3, 4, 8, 10])
  end

  it "compares against float" do
    1.to_big_i.should eq(1.0)
    1.to_big_i.should eq(1.0_f32)
    1.to_big_i.should_not eq(1.1)
    1.0.should eq(1.to_big_i)
    1.0_f32.should eq(1.to_big_i)
    1.1.should_not eq(1.to_big_i)

    [1.1, 1.to_big_i, 3.to_big_i, 2.2].sort.should eq([1, 1.1, 2.2, 3])

    (1.to_big_i <=> Float64::NAN).should be_nil
    (1.to_big_i <=> Float32::NAN).should be_nil
    (Float64::NAN <=> 1.to_big_i).should be_nil
    (Float32::NAN <=> 1.to_big_i).should be_nil

    typeof(1.to_big_i <=> Float64::NAN).should eq(Int32?)
    typeof(1.to_big_i <=> Float32::NAN).should eq(Int32?)
    typeof(Float64::NAN <=> 1.to_big_i).should eq(Int32?)
    typeof(Float32::NAN <=> 1.to_big_i).should eq(Int32?)

    typeof(1.to_big_i <=> 1.to_big_f).should eq(Int32)
    typeof(1.to_big_f <=> 1.to_big_i).should eq(Int32)
  end

  it "divides and calculates the modulo" do
    11.to_big_i.divmod(3.to_big_i).should eq({3, 2})
    11.to_big_i.divmod(-3.to_big_i).should eq({-4, -1})

    11.to_big_i.divmod(3_i32).should eq({3, 2})
    11.to_big_i.divmod(-3_i32).should eq({-4, -1})

    10.to_big_i.divmod(2).should eq({5, 0})
    11.to_big_i.divmod(2).should eq({5, 1})

    10.to_big_i.divmod(2.to_big_i).should eq({5, 0})
    11.to_big_i.divmod(2.to_big_i).should eq({5, 1})

    10.to_big_i.divmod(-2).should eq({-5, 0})
    11.to_big_i.divmod(-2).should eq({-6, -1})

    -10.to_big_i.divmod(2).should eq({-5, 0})
    -11.to_big_i.divmod(2).should eq({-6, 1})

    -10.to_big_i.divmod(-2).should eq({5, 0})
    -11.to_big_i.divmod(-2).should eq({5, -1})
  end

  it "adds" do
    (1.to_big_i + 2.to_big_i).should eq(3.to_big_i)
    (1.to_big_i + 2).should eq(3.to_big_i)
    (1.to_big_i + 2_u8).should eq(3.to_big_i)
    (5.to_big_i + (-2_i64)).should eq(3.to_big_i)
    (5.to_big_i + Int64::MAX).should be > Int64::MAX.to_big_i
    (5.to_big_i + Int64::MAX).should eq(Int64::MAX.to_big_i + 5)

    (2 + 1.to_big_i).should eq(3.to_big_i)

    (1.to_big_i &+ 2.to_big_i).should eq(3.to_big_i)
    (1.to_big_i &+ 2).should eq(3.to_big_i)
    (1.to_big_i &+ 2_u8).should eq(3.to_big_i)
    (5.to_big_i &+ (-2_i64)).should eq(3.to_big_i)
    (5.to_big_i &+ Int64::MAX).should be > Int64::MAX.to_big_i
    (5.to_big_i &+ Int64::MAX).should eq(Int64::MAX.to_big_i &+ 5)

    (2 &+ 1.to_big_i).should eq(3.to_big_i)
  end

  it "subs" do
    (5.to_big_i - 2.to_big_i).should eq(3.to_big_i)
    (5.to_big_i - 2).should eq(3.to_big_i)
    (5.to_big_i - 2_u8).should eq(3.to_big_i)
    (5.to_big_i - (-2_i64)).should eq(7.to_big_i)
    (-5.to_big_i - Int64::MAX).should be < -Int64::MAX.to_big_i
    (-5.to_big_i - Int64::MAX).should eq(-Int64::MAX.to_big_i - 5)

    (5 - 1.to_big_i).should eq(4.to_big_i)
    (-5 - 1.to_big_i).should eq(-6.to_big_i)

    (5.to_big_i &- 2.to_big_i).should eq(3.to_big_i)
    (5.to_big_i &- 2).should eq(3.to_big_i)
    (5.to_big_i &- 2_u8).should eq(3.to_big_i)
    (5.to_big_i &- (-2_i64)).should eq(7.to_big_i)
    (-5.to_big_i &- Int64::MAX).should be < -Int64::MAX.to_big_i
    (-5.to_big_i &- Int64::MAX).should eq(-Int64::MAX.to_big_i &- 5)

    (5 &- 1.to_big_i).should eq(4.to_big_i)
    (-5 &- 1.to_big_i).should eq(-6.to_big_i)
  end

  it "negates" do
    (-(-123.to_big_i)).should eq(123.to_big_i)
  end

  it "multiplies" do
    (2.to_big_i * 3.to_big_i).should eq(6.to_big_i)
    (2.to_big_i * 3).should eq(6.to_big_i)
    (2.to_big_i * 3_u8).should eq(6.to_big_i)
    (3 * 2.to_big_i).should eq(6.to_big_i)
    (3_u8 * 2.to_big_i).should eq(6.to_big_i)
    (2.to_big_i * Int64::MAX).should eq(2.to_big_i * Int64::MAX.to_big_i)

    (2.to_big_i &* 3.to_big_i).should eq(6.to_big_i)
    (2.to_big_i &* 3).should eq(6.to_big_i)
    (2.to_big_i &* 3_u8).should eq(6.to_big_i)
    (3 &* 2.to_big_i).should eq(6.to_big_i)
    (3_u8 &* 2.to_big_i).should eq(6.to_big_i)
    (2.to_big_i &* Int64::MAX).should eq(2.to_big_i &* Int64::MAX.to_big_i)
  end

  it "gets absolute value" do
    (-10.to_big_i.abs).should eq(10.to_big_i)
  end

  it "gets factorial value" do
    0.to_big_i.factorial.should eq(1.to_big_i)
    5.to_big_i.factorial.should eq(120.to_big_i)
    100.to_big_i.factorial.should eq("93326215443944152681699238856266700490715968264381621468592963895217599993229915608941463976156518286253697920827223758251185210916864000000000000000000000000".to_big_i)
  end

  it "raises if factorial of negative" do
    expect_raises ArgumentError do
      -1.to_big_i.factorial
    end

    expect_raises ArgumentError do
      "-93326215443944152681699238856266700490715968264381621468592963895217599993229915608941463976156518286253697920827223758251185210916864000000000000000000000000".to_big_i.factorial
    end
  end

  it "raises if factorial of 2^64" do
    expect_raises ArgumentError do
      (LibGMP::UI::MAX.to_big_i + 1).factorial
    end
  end

  it "divides" do
    (10.to_big_i / 3.to_big_i).should be_close(3.3333.to_big_f, 0.0001)
    (10.to_big_i / 3).should be_close(3.3333.to_big_f, 0.0001)
    (10 / 3.to_big_i).should be_close(3.3333.to_big_f, 0.0001)
    ((Int64::MAX.to_big_i * 2.to_big_i) / Int64::MAX).should eq(2.to_big_i)
  end

  it "divides" do
    (10.to_big_i // 3.to_big_i).should eq(3.to_big_i)
    (10.to_big_i // 3).should eq(3.to_big_i)
    (10 // 3.to_big_i).should eq(3.to_big_i)
    ((Int64::MAX.to_big_i * 2.to_big_i) // Int64::MAX).should eq(2.to_big_i)
  end

  it "divides with negative numbers" do
    (7.to_big_i / 2).should eq(3.5.to_big_f)
    (7.to_big_i / 2.to_big_i).should eq(3.5.to_big_f)
    (7.to_big_i / -2).should eq(-3.5.to_big_f)
    (7.to_big_i / -2.to_big_i).should eq(-3.5.to_big_f)
    (-7.to_big_i / 2).should eq(-3.5.to_big_f)
    (-7.to_big_i / 2.to_big_i).should eq(-3.5.to_big_f)
    (-7.to_big_i / -2).should eq(3.5.to_big_f)
    (-7.to_big_i / -2.to_big_i).should eq(3.5.to_big_f)

    (-6.to_big_i / 2).should eq(-3.to_big_f)
    (6.to_big_i / -2).should eq(-3.to_big_f)
    (-6.to_big_i / -2).should eq(3.to_big_f)
  end

  it "divides with negative numbers" do
    (7.to_big_i // 2).should eq(3.to_big_i)
    (7.to_big_i // 2.to_big_i).should eq(3.to_big_i)
    (7.to_big_i // -2).should eq(-4.to_big_i)
    (7.to_big_i // -2.to_big_i).should eq(-4.to_big_i)
    (-7.to_big_i // 2).should eq(-4.to_big_i)
    (-7.to_big_i // 2.to_big_i).should eq(-4.to_big_i)
    (-7.to_big_i // -2).should eq(3.to_big_i)
    (-7.to_big_i // -2.to_big_i).should eq(3.to_big_i)

    (-6.to_big_i // 2).should eq(-3.to_big_i)
    (6.to_big_i // -2).should eq(-3.to_big_i)
    (-6.to_big_i // -2).should eq(3.to_big_i)
  end

  it "tdivs" do
    5.to_big_i.tdiv(3).should eq(1)
    -5.to_big_i.tdiv(3).should eq(-1)
    5.to_big_i.tdiv(-3).should eq(-1)
    -5.to_big_i.tdiv(-3).should eq(1)
  end

  it "does modulo" do
    (10.to_big_i % 3.to_big_i).should eq(1.to_big_i)
    (10.to_big_i % 3).should eq(1.to_big_i)
    (10.to_big_i % 3u8).should eq(1.to_big_i)
    (10 % 3.to_big_i).should eq(1.to_big_i)
  end

  it "does modulo with negative numbers" do
    (7.to_big_i % 2).should eq(1.to_big_i)
    (7.to_big_i % 2.to_big_i).should eq(1.to_big_i)
    (7.to_big_i % -2).should eq(-1.to_big_i)
    (7.to_big_i % -2.to_big_i).should eq(-1.to_big_i)
    (-7.to_big_i % 2).should eq(1.to_big_i)
    (-7.to_big_i % 2.to_big_i).should eq(1.to_big_i)
    (-7.to_big_i % -2).should eq(-1.to_big_i)
    (-7.to_big_i % -2.to_big_i).should eq(-1.to_big_i)

    (6.to_big_i % 2).should eq(0.to_big_i)
    (6.to_big_i % -2).should eq(0.to_big_i)
    (-6.to_big_i % 2).should eq(0.to_big_i)
    (-6.to_big_i % -2).should eq(0.to_big_i)
  end

  it "does remainder with negative numbers" do
    5.to_big_i.remainder(3).should eq(2)
    -5.to_big_i.remainder(3).should eq(-2)
    5.to_big_i.remainder(-3).should eq(2)
    -5.to_big_i.remainder(-3).should eq(-2)
  end

  it "#bit" do
    x = 123.to_big_i
    x.bit(-10.to_big_i ** 99).should eq(0)
    x.bit(-(2.to_big_i ** 64)).should eq(0)
    x.bit(-1).should eq(0)
    x.bit(0).should eq(1)
    x.bit(2).should eq(0)
    x.bit(3).should eq(1)
    x.bit(6).should eq(1)
    x.bit(7).should eq(0)
    x.bit(64).should eq(0)
    x.bit(2.to_big_i ** 64).should eq(0)
    x.bit(10.to_big_i ** 99).should eq(0)

    x = ~(123.to_big_i)
    x.bit(-10.to_big_i ** 99).should eq(0)
    x.bit(-(2.to_big_i ** 64)).should eq(0)
    x.bit(-1).should eq(0)
    x.bit(0).should eq(0)
    x.bit(2).should eq(1)
    x.bit(3).should eq(0)
    x.bit(6).should eq(0)
    x.bit(7).should eq(1)
    x.bit(64).should eq(1)
    x.bit(2.to_big_i ** 64).should eq(1)
    x.bit(10.to_big_i ** 99).should eq(1)
  end

  it "does bitwise and" do
    (123.to_big_i & 321).should eq(65)
    (BigInt.new("96238761238973286532") & 86325735648).should eq(69124358272)
  end

  it "does bitwise or" do
    (123.to_big_i | 4).should eq(127)
    (BigInt.new("96238761238986532") | 8632573).should eq(96238761247506429)
  end

  it "does bitwise xor" do
    (123.to_big_i ^ 50).should eq(73)
    (BigInt.new("96238761238986532") ^ 8632573).should eq(96238761247393753)
  end

  it "does bitwise not" do
    (~123).should eq(-124)

    a = BigInt.new("192623876123689865327")
    b = BigInt.new("-192623876123689865328")
    (~a).should eq(b)
  end

  it "does bitwise right shift" do
    (123.to_big_i >> 4).should eq(7)
    (123456.to_big_i >> 8).should eq(482)
  end

  it "does bitwise left shift" do
    (123.to_big_i << 4).should eq(1968)
    (123456.to_big_i << 8).should eq(31604736)
  end

  it "raises if divides by zero" do
    expect_raises DivisionByZeroError do
      10.to_big_i / 0.to_big_i
    end

    expect_raises DivisionByZeroError do
      10.to_big_i / 0
    end

    expect_raises DivisionByZeroError do
      10 / 0.to_big_i
    end
  end

  it "raises if divides by zero" do
    expect_raises DivisionByZeroError do
      10.to_big_i // 0.to_big_i
    end

    expect_raises DivisionByZeroError do
      10.to_big_i // 0
    end

    expect_raises DivisionByZeroError do
      10 // 0.to_big_i
    end
  end

  it "raises if mods by zero" do
    expect_raises DivisionByZeroError do
      10.to_big_i % 0.to_big_i
    end

    expect_raises DivisionByZeroError do
      10.to_big_i % 0
    end

    expect_raises DivisionByZeroError do
      10 % 0.to_big_i
    end
  end

  it "exponentiates" do
    result = (2.to_big_i ** 1000)
    result.should be_a(BigInt)
    result.to_s.should eq("10715086071862673209484250490600018105614048117055336074437503883703510511249361224931983788156958581275946729175531468251871452856923140435984577574698574803934567774824230985421074605062371141877954182153046474983581941267398767559165543946077062914571196477686542167660429831652624386837205668069376")
  end

  describe "#to_s" do
    context "base and upcase parameters" do
      a = BigInt.new("1234567890123456789")
      it_converts_to_s a, "1000100100010000100001111010001111101111010011000000100010101", base: 2
      it_converts_to_s a, "112210f47de98115", base: 16
      it_converts_to_s a, "112210F47DE98115", base: 16, upcase: true
      it_converts_to_s a, "128gguhuuj08l", base: 32
      it_converts_to_s a, "128GGUHUUJ08L", base: 32, upcase: true
      it_converts_to_s a, "1tckI1NfUnH", base: 62

      # ensure case is same as for primitive integers
      it_converts_to_s 10.to_big_i, 10.to_s(62), base: 62

      it_converts_to_s (-a), "-1000100100010000100001111010001111101111010011000000100010101", base: 2
      it_converts_to_s (-a), "-112210f47de98115", base: 16
      it_converts_to_s (-a), "-112210F47DE98115", base: 16, upcase: true
      it_converts_to_s (-a), "-128gguhuuj08l", base: 32
      it_converts_to_s (-a), "-128GGUHUUJ08L", base: 32, upcase: true
      it_converts_to_s (-a), "-1tckI1NfUnH", base: 62

      it_converts_to_s 16.to_big_i ** 1000, "1#{"0" * 1000}", base: 16

      it "raises on base 1" do
        expect_raises(ArgumentError, "Invalid base 1") { a.to_s(1) }
        expect_raises(ArgumentError, "Invalid base 1") { a.to_s(IO::Memory.new, 1) }
      end

      it "raises on base 37" do
        expect_raises(ArgumentError, "Invalid base 37") { a.to_s(37) }
        expect_raises(ArgumentError, "Invalid base 37") { a.to_s(IO::Memory.new, 37) }
      end

      it "raises on base 62 with upcase" do
        expect_raises(ArgumentError, "upcase must be false for base 62") { a.to_s(62, upcase: true) }
        expect_raises(ArgumentError, "upcase must be false for base 62") { a.to_s(IO::Memory.new, 62, upcase: true) }
      end
    end

    context "precision parameter" do
      it_converts_to_s 0.to_big_i, "", precision: 0
      it_converts_to_s 0.to_big_i, "0", precision: 1
      it_converts_to_s 0.to_big_i, "00", precision: 2
      it_converts_to_s 0.to_big_i, "00000", precision: 5
      it_converts_to_s 0.to_big_i, "0" * 200, precision: 200

      it_converts_to_s 1.to_big_i, "1", precision: 0
      it_converts_to_s 1.to_big_i, "1", precision: 1
      it_converts_to_s 1.to_big_i, "01", precision: 2
      it_converts_to_s 1.to_big_i, "00001", precision: 5
      it_converts_to_s 1.to_big_i, "#{"0" * 199}1", precision: 200

      it_converts_to_s 2.to_big_i, "2", precision: 0
      it_converts_to_s 2.to_big_i, "2", precision: 1
      it_converts_to_s 2.to_big_i, "02", precision: 2
      it_converts_to_s 2.to_big_i, "00002", precision: 5
      it_converts_to_s 2.to_big_i, "#{"0" * 199}2", precision: 200

      it_converts_to_s (-1).to_big_i, "-1", precision: 0
      it_converts_to_s (-1).to_big_i, "-1", precision: 1
      it_converts_to_s (-1).to_big_i, "-01", precision: 2
      it_converts_to_s (-1).to_big_i, "-00001", precision: 5
      it_converts_to_s (-1).to_big_i, "-#{"0" * 199}1", precision: 200

      it_converts_to_s 85.to_big_i, "85", precision: 0
      it_converts_to_s 85.to_big_i, "85", precision: 1
      it_converts_to_s 85.to_big_i, "85", precision: 2
      it_converts_to_s 85.to_big_i, "085", precision: 3
      it_converts_to_s 85.to_big_i, "0085", precision: 4
      it_converts_to_s 85.to_big_i, "00085", precision: 5
      it_converts_to_s 85.to_big_i, "#{"0" * 198}85", precision: 200

      it_converts_to_s (-85).to_big_i, "-85", precision: 0
      it_converts_to_s (-85).to_big_i, "-85", precision: 1
      it_converts_to_s (-85).to_big_i, "-85", precision: 2
      it_converts_to_s (-85).to_big_i, "-085", precision: 3
      it_converts_to_s (-85).to_big_i, "-0085", precision: 4
      it_converts_to_s (-85).to_big_i, "-00085", precision: 5
      it_converts_to_s (-85).to_big_i, "-#{"0" * 198}85", precision: 200

      it_converts_to_s 123.to_big_i, "123", precision: 0
      it_converts_to_s 123.to_big_i, "123", precision: 1
      it_converts_to_s 123.to_big_i, "123", precision: 2
      it_converts_to_s 123.to_big_i, "00123", precision: 5
      it_converts_to_s 123.to_big_i, "#{"0" * 197}123", precision: 200

      a = 2.to_big_i ** 1024 - 1
      it_converts_to_s a, "#{"1" * 1024}", base: 2, precision: 1023
      it_converts_to_s a, "#{"1" * 1024}", base: 2, precision: 1024
      it_converts_to_s a, "0#{"1" * 1024}", base: 2, precision: 1025
      it_converts_to_s a, "#{"0" * 976}#{"1" * 1024}", base: 2, precision: 2000

      it_converts_to_s (-a), "-#{"1" * 1024}", base: 2, precision: 1023
      it_converts_to_s (-a), "-#{"1" * 1024}", base: 2, precision: 1024
      it_converts_to_s (-a), "-0#{"1" * 1024}", base: 2, precision: 1025
      it_converts_to_s (-a), "-#{"0" * 976}#{"1" * 1024}", base: 2, precision: 2000
    end
  end

  it "does to_big_f" do
    a = BigInt.new("1234567890123456789")
    a.to_big_f.should eq(BigFloat.new("1234567890123456789.0"))
  end

  describe "#inspect" do
    it { "2".to_big_i.inspect.should eq("2") }
  end

  it "does gcd and lcm" do
    # 3 primes
    a = BigInt.new("48112959837082048697")
    b = BigInt.new("12764787846358441471")
    c = BigInt.new("36413321723440003717")
    abc = a * b * c
    a_17 = a * 17

    (abc * b).gcd(abc * c).should eq(abc)
    abc.gcd(a_17).should eq(a)
    (abc * b).lcm(abc * c).should eq(abc * b * c)
    (abc * b).gcd(abc * c).should be_a(BigInt)

    (a_17).gcd(17).should eq(17)
    (-a_17).gcd(17).should eq(17)
    (17).gcd(a_17).should eq(17)
    (17).gcd(-a_17).should eq(17)

    (a_17).lcm(17).should eq(a_17)
    (-a_17).lcm(17).should eq(a_17)
    (17).lcm(a_17).should eq(a_17)
    (17).lcm(-a_17).should eq(a_17)

    (a_17).gcd(17).should be_a(Int::Unsigned)
  end

  it "calculates the modulo inverse" do
    a = BigInt.new("48112959837082048697")
    b = BigInt.new("12764787846358441471")
    c = a.mod_invert(b)

    (a*c % b).should eq(1)
  end

  it "can use Number::[]" do
    a = BigInt[146, "3464", 97, "545"]
    b = [BigInt.new(146), BigInt.new(3464), BigInt.new(97), BigInt.new(545)]
    a.should eq(b)
  end

  describe "#to_i" do
    it "converts to Int32" do
      BigInt.new(1234567890).to_i.should(be_a(Int32)).should eq(1234567890)
      expect_raises(OverflowError) { BigInt.new(2147483648).to_i }
      expect_raises(OverflowError) { BigInt.new(-2147483649).to_i }
    end
  end

  describe "#to_i!" do
    it "converts to Int32" do
      BigInt.new(1234567890).to_i!.should(be_a(Int32)).should eq(1234567890)
      BigInt.new(2147483648).to_i!.should eq(Int32::MIN)
      BigInt.new(-2147483649).to_i!.should eq(Int32::MAX)
    end
  end

  describe "#to_u" do
    it "converts to UInt32" do
      BigInt.new(1234567890).to_u.should(be_a(UInt32)).should eq(1234567890_u32)
      expect_raises(OverflowError) { BigInt.new(4294967296).to_u }
      expect_raises(OverflowError) { BigInt.new(-1).to_u }
    end
  end

  describe "#to_u!" do
    it "converts to UInt32" do
      BigInt.new(1234567890).to_u!.should(be_a(UInt32)).should eq(1234567890_u32)
      BigInt.new(4294967296).to_u!.should eq(0_u32)
      BigInt.new(-1).to_u!.should eq(UInt32::MAX)
    end
  end

  {% for n in [8, 16, 32, 64, 128] %}
    describe "#to_u{{n}}" do
      it "converts to UInt{{n}}" do
        (0..{{n - 1}}).each do |i|
          (1.to_big_i << i).to_u{{n}}.should eq(UInt{{n}}.new(1) << i)
        end

        UInt{{n}}::MIN.to_big_i.to_u{{n}}.should eq(UInt{{n}}::MIN)
        UInt{{n}}::MAX.to_big_i.to_u{{n}}.should eq(UInt{{n}}::MAX)
      end

      it "raises OverflowError" do
        expect_raises(OverflowError) { (1.to_big_i << {{n}}).to_u{{n}} }
        expect_raises(OverflowError) { (-1.to_big_i).to_u{{n}} }
        expect_raises(OverflowError) { (-1.to_big_i << {{n}}).to_u{{n}} }
      end
    end

    describe "#to_i{{n}}" do
      it "converts to Int{{n}}" do
        (0..{{n - 2}}).each do |i|
          (1.to_big_i << i).to_i{{n}}.should eq(Int{{n}}.new(1) << i)
          (-1.to_big_i << i).to_i{{n}}.should eq(Int{{n}}.new(-1) << i)
        end

        Int{{n}}.zero.to_big_i.to_i{{n}}.should eq(Int{{n}}.zero)
        Int{{n}}::MAX.to_big_i.to_i{{n}}.should eq(Int{{n}}::MAX)
        Int{{n}}::MIN.to_big_i.to_i{{n}}.should eq(Int{{n}}::MIN)
      end

      it "raises OverflowError" do
        expect_raises(OverflowError) { (Int{{n}}::MAX.to_big_i + 1).to_i{{n}} }
        expect_raises(OverflowError) { (Int{{n}}::MIN.to_big_i - 1).to_i{{n}} }
        expect_raises(OverflowError) { (1.to_big_i << {{n}}).to_i{{n}} }
        expect_raises(OverflowError) { (-1.to_big_i << {{n}}).to_i{{n}} }
      end
    end

    describe "#to_u{{n}}!" do
      it "converts to UInt{{n}}" do
        (0..{{n - 1}}).each do |i|
          (1.to_big_i << i).to_u{{n}}!.should eq(UInt{{n}}.new(1) << i)
        end

        UInt{{n}}::MAX.to_big_i.to_u{{n}}!.should eq(UInt{{n}}::MAX)
      end

      it "converts modulo (2 ** {{n}})" do
        (1.to_big_i << {{n}}).to_u{{n}}!.should eq(UInt{{n}}.new(0))
        (-1.to_big_i).to_u{{n}}!.should eq(UInt{{n}}::MAX)
        (-1.to_big_i << {{n}}).to_u{{n}}!.should eq(UInt{{n}}.new(0))
        (123.to_big_i - (1.to_big_i << {{n}})).to_u{{n}}!.should eq(UInt{{n}}.new(123))
        (123.to_big_i + (1.to_big_i << {{n}})).to_u{{n}}!.should eq(UInt{{n}}.new(123))
        (123.to_big_i - (1.to_big_i << {{n + 2}})).to_u{{n}}!.should eq(UInt{{n}}.new(123))
        (123.to_big_i + (1.to_big_i << {{n + 2}})).to_u{{n}}!.should eq(UInt{{n}}.new(123))
      end
    end

    describe "#to_i{{n}}!" do
      it "converts to Int{{n}}" do
        (0..126).each do |i|
          (1.to_big_i << i).to_i{{n}}!.should eq(Int{{n}}.new(1) << i)
          (-1.to_big_i << i).to_i{{n}}!.should eq(Int{{n}}.new(-1) << i)
        end

        Int{{n}}::MAX.to_big_i.to_i{{n}}!.should eq(Int{{n}}::MAX)
        Int{{n}}::MIN.to_big_i.to_i{{n}}!.should eq(Int{{n}}::MIN)
      end

      it "converts modulo (2 ** {{n}})" do
        (1.to_big_i << {{n - 1}}).to_i{{n}}!.should eq(Int{{n}}::MIN)
        (1.to_big_i << {{n}}).to_i{{n}}!.should eq(Int{{n}}.new(0))
        (-1.to_big_i << {{n}}).to_i{{n}}!.should eq(Int{{n}}.new(0))
        (123.to_big_i - (1.to_big_i << {{n}})).to_i{{n}}!.should eq(Int{{n}}.new(123))
        (123.to_big_i + (1.to_big_i << {{n}})).to_i{{n}}!.should eq(Int{{n}}.new(123))
        (123.to_big_i - (1.to_big_i << {{n + 2}})).to_i{{n}}!.should eq(Int{{n}}.new(123))
        (123.to_big_i + (1.to_big_i << {{n + 2}})).to_i{{n}}!.should eq(Int{{n}}.new(123))
      end
    end
  {% end %}

  it "does String#to_big_i" do
    "123456789123456789".to_big_i.should eq(BigInt.new("123456789123456789"))
    "abcabcabcabcabcabc".to_big_i(base: 16).should eq(BigInt.new("3169001976782853491388"))
  end

  it "does popcount" do
    5.to_big_i.popcount.should eq(2)
  end

  it "#trailing_zeros_count" do
    "00000000000000001000000000001000".to_big_i(base: 2).trailing_zeros_count.should eq(3)
  end

  it "#hash" do
    b1 = 5.to_big_i
    b2 = 5.to_big_i
    b3 = -6.to_big_i

    b1.hash.should eq(b2.hash)
    b1.hash.should_not eq(b3.hash)

    b3.hash.should eq((-6).hash)
  end

  it "clones" do
    x = 1.to_big_i
    x.clone.should eq(x)
  end

  describe "#humanize_bytes" do
    it { BigInt.new("1180591620717411303424").humanize_bytes.should eq("1.0ZiB") }
    it { BigInt.new("1208925819614629174706176").humanize_bytes.should eq("1.0YiB") }
  end

  it "has unsafe_shr (#8691)" do
    BigInt.new(8).unsafe_shr(1).should eq(4)
  end

  describe "#digits" do
    it "works for positive numbers or zero" do
      0.to_big_i.digits.should eq([0])
      1.to_big_i.digits.should eq([1])
      10.to_big_i.digits.should eq([0, 1])
      123.to_big_i.digits.should eq([3, 2, 1])
      123456789.to_big_i.digits.should eq([9, 8, 7, 6, 5, 4, 3, 2, 1])
    end

    it "works with a base" do
      123.to_big_i.digits(16).should eq([11, 7])
    end

    it "raises for invalid base" do
      [1, 0, -1].each do |base|
        expect_raises(ArgumentError, "Invalid base #{base}") do
          123.to_big_i.digits(base)
        end
      end
    end

    it "raises for negative numbers" do
      expect_raises(ArgumentError, "Can't request digits of negative number") do
        -123.to_big_i.digits
      end
    end
  end

  describe "#divisible_by?" do
    it { 0.to_big_i.divisible_by?(0).should be_true }
    it { 0.to_big_i.divisible_by?(1).should be_true }
    it { 0.to_big_i.divisible_by?(-1).should be_true }
    it { 0.to_big_i.divisible_by?(0.to_big_i).should be_true }
    it { 0.to_big_i.divisible_by?(1.to_big_i).should be_true }
    it { 0.to_big_i.divisible_by?((-1).to_big_i).should be_true }

    it { 135.to_big_i.divisible_by?(0).should be_false }
    it { 135.to_big_i.divisible_by?(1).should be_true }
    it { 135.to_big_i.divisible_by?(2).should be_false }
    it { 135.to_big_i.divisible_by?(3).should be_true }
    it { 135.to_big_i.divisible_by?(4).should be_false }
    it { 135.to_big_i.divisible_by?(5).should be_true }
    it { 135.to_big_i.divisible_by?(135).should be_true }
    it { 135.to_big_i.divisible_by?(270).should be_false }

    it { "100000000000000000000000000000000".to_big_i.divisible_by?("4294967296".to_big_i).should be_true }
    it { "100000000000000000000000000000000".to_big_i.divisible_by?("8589934592".to_big_i).should be_false }
    it { "100000000000000000000000000000000".to_big_i.divisible_by?("23283064365386962890625".to_big_i).should be_true }
    it { "100000000000000000000000000000000".to_big_i.divisible_by?("116415321826934814453125".to_big_i).should be_false }
  end
end

describe "BigInt Math" do
  it "sqrt" do
    Math.sqrt(BigInt.new("1" + "0"*48)).should eq(BigFloat.new("1" + "0"*24))
  end

  it "isqrt" do
    Math.isqrt(BigInt.new("1" + "0"*48)).should eq(BigInt.new("1" + "0"*24))
  end

  it "pw2ceil" do
    Math.pw2ceil("-100000000000000000000000000000000".to_big_i).should eq(1.to_big_i)
    Math.pw2ceil(-1234567.to_big_i).should eq(1.to_big_i)
    Math.pw2ceil(-1.to_big_i).should eq(1.to_big_i)
    Math.pw2ceil(0.to_big_i).should eq(1.to_big_i)
    Math.pw2ceil(1.to_big_i).should eq(1.to_big_i)
    Math.pw2ceil(2.to_big_i).should eq(2.to_big_i)
    Math.pw2ceil(3.to_big_i).should eq(4.to_big_i)
    Math.pw2ceil(4.to_big_i).should eq(4.to_big_i)
    Math.pw2ceil(5.to_big_i).should eq(8.to_big_i)
    Math.pw2ceil(32.to_big_i).should eq(32.to_big_i)
    Math.pw2ceil(33.to_big_i).should eq(64.to_big_i)
    Math.pw2ceil(64.to_big_i).should eq(64.to_big_i)
    Math.pw2ceil(2.to_big_i ** 12345 - 1).should eq(2.to_big_i ** 12345)
    Math.pw2ceil(2.to_big_i ** 12345).should eq(2.to_big_i ** 12345)
    Math.pw2ceil(2.to_big_i ** 12345 + 1).should eq(2.to_big_i ** 12346)
  end
end
