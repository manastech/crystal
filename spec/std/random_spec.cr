require "./spec_helper"
require "big"

# Copied here from compiler-rt's spec-helper
def make_tu(a : UInt128, b : UInt128)
  (a.to_u128! << 64) + b
end

private class TestRNG(T)
  include Random

  def initialize(@data : Array(T))
    @i = 0
  end

  def next_u : T
    i = @i
    @i = (i + 1) % @data.size
    @data[i]
  end

  def reset
    @i = 0
  end
end

private RNG_DATA_8  = [234u8, 153u8, 0u8, 0u8, 127u8, 128u8, 255u8, 255u8]
private RNG_DATA_32 = [31541451u32, 0u32, 1u32, 234u32, 342475672u32, 863u32, 0xffffffffu32, 50967465u32]
private RNG_DATA_64 = [148763248732657823u64, 18446744073709551615u64, 0u64,
                       32456325635673576u64, 2456245614625u64, 32452456246u64, 3956529762u64,
                       9823674982364u64, 234253464546456u64, 14345435645646u64]
private RNG_DATA_128 = [make_tu(1101449320907785530u128, 6979810955129606772u128), make_tu(12369252765162302003u128, 15575142252968787416u128),
                        make_tu(13441498024203764035u128, 7030046732498433846u128), make_tu(6222142093523402848u128, 17154318143782852173u128),
                        make_tu(9998452933988559113u128, 7429084970167000187u128), make_tu(14848715232994466871u128, 16710636589464800780u128),
                        make_tu(16766909356445913125u128, 789971150692021876u128), make_tu(13481304315125825423u128, 16449966857661152872u128)]

describe "Random" do
  it "limited number" do
    rand(1).should eq(0)

    x = rand(2)
    x.should be >= 0
    x.should be < 2

    # issue 3350
    5.times do
      rand(Int64::MAX).should be >= 0
    end
  end

  it "limited BigInt" do
    rand(1.to_big_i).should eq(0.to_big_i)

    x = rand(2.to_big_i)
    x.should be >= 0
    x.should be < 2
  end

  it "limited large BigInt" do
    max = "1234567890123456789012345".to_big_i
    x = rand(max)
    x.should be >= 0
    x.should be < max
  end

  it "float number" do
    x = rand
    x.should be >= 0
    x.should be <= 1
  end

  it "limited Float32 number" do
    x = rand(3.5_f32)
    x.should be_a Float32
    x.should be >= 0
    x.should be < 3.5
  end

  it "limited Float64 number" do
    x = rand(3.5_f64)
    x.should be_a Float64
    x.should be >= 0
    x.should be < 3.5
  end

  it "raises on invalid number" do
    expect_raises ArgumentError, "Invalid bound for rand: 0" do
      rand(0)
    end
    expect_raises ArgumentError, "Invalid bound for rand: -1" do
      rand(-1)
    end
  end

  it "raises on invalid float number" do
    expect_raises ArgumentError, "Invalid bound for rand: 0.0" do
      rand(0.0)
    end
    expect_raises ArgumentError, "Invalid bound for rand: -1.0" do
      rand(-1.0)
    end
  end

  it "does with inclusive range" do
    [1..1, 1..3, 0u8..255u8, -1..1, Int64::MIN..7i64,
     -7i64..Int64::MAX, 0u64..0u64].each do |range|
      x = rand(range)
      x.should be >= range.begin
      x.should be <= range.end
    end
  end

  it "does with exclusive range" do
    [1...2, 1...4, 0u8...255u8, -1...1, Int64::MIN...7i64,
     -7i64...Int64::MAX, -1i8...0i8].each do |range|
      x = rand(range)
      x.should be >= range.begin
      x.should be < range.end
    end
  end

  it "does with BigInt range" do
    [1.to_big_i...2.to_big_i,
     -"1234567890123456789012345".to_big_i...7.to_big_i,
     -7.to_big_i..."1234567890123456789012345".to_big_i].each do |range|
      x = rand(range)
      x.should be >= range.begin
      x.should be < range.end
    end
  end

  it "does with inclusive range of floats" do
    rand(1.0..1.0).should eq(1.0)

    x = rand(1.8..3.2)
    x.should be >= 1.8
    x.should be <= 3.2

    x = rand(Float64::MIN..Float64::MAX)
    x.should be >= Float64::MIN
    x.should be <= Float64::MAX

    rand(1.0_f32..1.0_f32).should eq(1.0_f32)

    x = rand(1.8_f32..3.2_f32)
    x.should be >= 1.8_f32
    x.should be <= 3.2_f32

    x = rand(Float32::MIN..Float32::MAX)
    x.should be >= Float32::MIN
    x.should be <= Float32::MAX
  end

  it "does with exclusive range of floats" do
    x = rand(1.8...3.3)
    x.should be >= 1.8
    x.should be < 3.3

    x = rand(Float64::MIN...Float64::MAX)
    x.should be >= Float64::MIN
    x.should be < Float64::MAX

    x = rand(1.8_f32...3.3_f32)
    x.should be >= 1.8_f32
    x.should be < 3.3_f32

    x = rand(Float32::MIN...Float32::MAX)
    x.should be >= Float32::MIN
    x.should be < Float32::MAX
  end

  describe "raises on invalid range" do
    it "Int32 range" do
      expect_raises ArgumentError, "Invalid range for rand: 1...1" do
        rand(1...1)
      end
      expect_raises ArgumentError, "Invalid range for rand: 1..0" do
        rand(1..0)
      end
    end

    it "BigInt range" do
      expect_raises ArgumentError, "Invalid range for rand: #{1.to_big_i...1.to_big_i}" do
        rand(1.to_big_i...1.to_big_i)
      end
      expect_raises ArgumentError, "Invalid range for rand: #{1.to_big_i..0.to_big_i}" do
        rand(1.to_big_i..0.to_big_i)
      end
    end

    it "Float64 range" do
      expect_raises ArgumentError, "Invalid range for rand: 1.0...1.0" do
        rand(1.0...1.0)
      end
      expect_raises ArgumentError, "Invalid range for rand: 1.0..0.0" do
        rand(1.0..0.0)
      end
    end

    it "infinite range" do
      expect_raises ArgumentError, "Invalid range for rand: 0.0..Infinity" do
        rand(0.0..Float64::INFINITY)
      end
      expect_raises ArgumentError, "Invalid range for rand: -Infinity..0.0" do
        rand(-Float64::INFINITY..0.0)
      end
      expect_raises ArgumentError, "Invalid range for rand: -Infinity..Infinity" do
        rand(-Float64::INFINITY..Float64::INFINITY)
      end
    end

    it "nan range" do
      expect_raises ArgumentError, "Invalid range for rand: 0.0..NaN" do
        rand(0.0..Float64::NAN)
      end
      expect_raises ArgumentError, "Invalid range for rand: NaN..0.0" do
        rand(Float64::NAN..0.0)
      end
      expect_raises ArgumentError, "Invalid range for rand: NaN..NaN" do
        rand(Float64::NAN..Float64::NAN)
      end
    end
  end

  it "allows creating a new default random" do
    rand = Random.new
    value = rand.rand
    (0 <= value < 1).should be_true
  end

  it "allows creating a new default random with a seed" do
    values = Array.new(2) do
      rand = Random.new(1234)
      {rand.rand, rand.rand(0xffffffffffffffffu64), rand.rand(2), rand.rand(-5i8..5i8)}
    end

    values[0].should eq values[1]
  end

  it "gets a random bool" do
    Random::DEFAULT.next_bool.should be_a(Bool)
  end

  it "generates by accumulation" do
    rng = TestRNG.new([234u8, 153u8, 0u8, 0u8, 127u8, 128u8, 255u8, 255u8])
    rng.rand(65536).should eq 60057    # 234*0x100 + 153
    rng.rand(60000).should eq 0        # 0*0x100 + 0
    rng.rand(30000).should eq 2640     # (127*0x100 + 128) % 30000
    rng.rand(65535u16).should eq 60057 # 255*0x100 + 255 [skip]-> 234*0x100 + 153
    rng.reset
    rng.rand(65537).should eq 38934 # (234*0x10000 + 153*0x100 + 0) % 65537
    rng.reset
    rng.rand(32768u16).should eq 27289 # (234*0x100 + 153) % 32768
  end

  it "generates by truncation" do
    rng = TestRNG.new([31541451u32, 0u32, 1u32, 234u32, 342475672u32])
    rng.rand(1).should eq 0
    rng.rand(10).should eq 0
    rng.rand(2).should eq 1
    rng.rand(256u64).should eq 234
    rng.rand(255u8).should eq 217   # 342475672 % 255
    rng.rand(65536).should eq 18635 # 31541451 % 65536
    rng = TestRNG.new([0xffffffffu32, 0u32])
    rng.rand(0x7fffffff).should eq 0
  end

  it "generates full-range" do
    rng = TestRNG.new(RNG_DATA_64)
    RNG_DATA_64.each do |a|
      rng.rand(UInt64::MIN..UInt64::MAX).should eq a
    end
  end

  it "generates full-range by accumulation" do
    rng = TestRNG.new(RNG_DATA_8)
    RNG_DATA_8.each_slice(2) do |(a, b)|
      expected = a.to_u16 * 0x100u16 + b.to_u16
      rng.rand(UInt16::MIN..UInt16::MAX).should eq expected
    end
  end

  it "generates full-range by truncation" do
    rng = TestRNG.new(RNG_DATA_32)
    RNG_DATA_32.each do |a|
      expected = a % 0x10000
      rng.rand(UInt16::MIN..UInt16::MAX).should eq expected
    end
  end

  it "generates full-range by negation" do
    rng = TestRNG.new(RNG_DATA_8)
    RNG_DATA_8.each do |a|
      expected = a.to_i
      expected -= 0x100 if a >= 0x80
      rng.rand(Int8::MIN..Int8::MAX).should eq expected
    end
  end

  it "works with span exceeding int type's range" do
    rng = TestRNG.new(RNG_DATA_8)
    rng.rand(-100_i8..100_i8).should eq(53_i8)
  end

  it "works using U/Int128" do
    rng = TestRNG.new(RNG_DATA_128)
    RNG_DATA_128.each do |a|
      rng.rand(UInt128::MIN..UInt128::MAX).should eq a
    end

    # (234_u128 << 96) + (1_u128 << 64) + 31541451_u128
    TestRNG.new(RNG_DATA_32).rand(UInt128).should eq make_tu(1005022347265u128, 31541451u128)

    rand_in_range = TestRNG.new(RNG_DATA_32).rand(600_u128..700_u128)
    (600..700).should contain(rand_in_range)
  end

  describe "random_bytes" do
    it "generates random bytes" do
      rng = TestRNG.new([0xfa19443eu32, 1u32, 0x12345678u32])
      rng.random_bytes(9).should eq Bytes[0x3e, 0x44, 0x19, 0xfa, 1, 0, 0, 0, 0x78]
      rng.random_bytes(1).should eq Bytes[0x3e]
      rng.random_bytes(4).should eq Bytes[1, 0, 0, 0]
      rng.random_bytes(3).should eq Bytes[0x78, 0x56, 0x34]
      rng.random_bytes(0).should eq Bytes[]

      rng = TestRNG.new([12u8, 255u8, 11u8, 5u8, 122u8, 200u8, 192u8])
      rng.random_bytes(7).should eq Bytes[12, 255, 11, 5, 122, 200, 192]
    end

    it "gets random bytes with default number of digits" do
      bytes = TestRNG.new(RNG_DATA_32).random_bytes
      bytes.size.should eq(16)
    end

    it "gets random bytes with requested number of digits" do
      bytes = TestRNG.new(RNG_DATA_32).random_bytes(50)
      bytes.size.should eq(50)
    end

    it "fills given buffer with random bytes" do
      bytes = Bytes.new(2000)
      TestRNG.new(RNG_DATA_32).random_bytes(bytes)
      bytes.size.should eq 2000
      bytes[1990, 10].should eq(UInt8.slice(0, 0, 1, 0, 0, 0, 234, 0, 0, 0))
    end
  end

  describe "base64" do
    it "gets base64 with default number of digits" do
      base64 = TestRNG.new(RNG_DATA_32).base64
      base64.should eq("y0jhAQAAAAABAAAA6gAAAA==")
    end

    it "gets base64 with requested number of digits" do
      base64 = TestRNG.new(RNG_DATA_64).base64(50)
      base64.should eq("n9hX9GKDEAL//////////wAAAAAAAAAA6I06MNtOcwAhuKXjOwIAADYvUY4HAAAAYto=")
    end
  end

  describe "urlsafe_base64" do
    it "gets urlsafe base64 with default number of digits" do
      base64 = TestRNG.new(RNG_DATA_32).urlsafe_base64
      base64.should eq("y0jhAQAAAAABAAAA6gAAAA")
    end

    it "gets urlsafe base64 with requested number of digits" do
      base64 = TestRNG.new(RNG_DATA_64).urlsafe_base64(50)
      base64.should eq("n9hX9GKDEAL__________wAAAAAAAAAA6I06MNtOcwAhuKXjOwIAADYvUY4HAAAAYto")
    end

    it "keeps padding" do
      base64 = TestRNG.new(RNG_DATA_32).urlsafe_base64(padding: true)
      base64.should eq("y0jhAQAAAAABAAAA6gAAAA==")
    end
  end

  describe "hex" do
    it "gets hex with default number of digits" do
      hex = TestRNG.new(RNG_DATA_32).hex
      hex.should eq("cb48e1010000000001000000ea000000")
    end

    it "gets hex with requested number of digits" do
      hex = TestRNG.new(RNG_DATA_64).hex(50)
      hex.should eq("9fd857f462831002ffffffffffffffff0000000000000000e88d3a30db4e730021b8a5e33b020000362f518e0700000062da")
    end
  end

  it "returns a random integer" do
    {% for type in %w(Int8 UInt8 Int16 UInt16 Int32 UInt32 Int64 UInt64).map(&.id) %}
      value = TestRNG.new(RNG_DATA_32).rand({{type}})
      typeof(value).should eq({{type}})
    {% end %}
  end

  it "returns a random static array" do
    {% for type in %w(Int8 UInt8 Int16 UInt16 Int32 UInt32 Int64 UInt64).map(&.id) %}
      array = TestRNG.new(RNG_DATA_32).rand(StaticArray({{type}}, 4))
      typeof(array).should eq(StaticArray({{type}}, 4))
    {% end %}
  end
end
