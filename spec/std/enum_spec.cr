require "spec"
require "spec/helpers/string"

enum SpecEnum : Int8
  One
  Two
  Three
end

enum SpecEnum2
  FortyTwo
  FORTY_FOUR
end

private enum PrivateEnum
  FOO = 0
  BAR = 1
  BAZ = 2
  QUX = 0
end

@[Flags]
enum SpecEnumFlags
  One
  Two
  Three
end

@[Flags]
enum SpecEnumFlags8 : Int8
  One
  Two
  Three
end

@[Flags]
private enum PrivateFlagsEnum
  FOO
  BAR
  BAZ
end

enum SpecBigEnum : Int64
  TooBig = 4294967296i64 # == 2**32
end

private enum SpecEnumWithCaseSensitiveMembers
  FOO = 1
  Foo = 2
end

describe Enum do
  describe "#to_s" do
    it "for simple enum" do
      assert_prints SpecEnum::One.to_s, "One"
      assert_prints SpecEnum::Two.to_s, "Two"
      assert_prints SpecEnum::Three.to_s, "Three"
      assert_prints SpecEnum.new(127).to_s, "127"
    end

    it "for flags enum" do
      assert_prints SpecEnumFlags::None.to_s, "None"
      assert_prints SpecEnumFlags::All.to_s, "All"
      assert_prints (SpecEnumFlags::One | SpecEnumFlags::Two).to_s, "One | Two"
      assert_prints SpecEnumFlags.new(128).to_s, "128"
      assert_prints (SpecEnumFlags::One | SpecEnumFlags.new(128)).to_s, "One | 128"
      assert_prints (SpecEnumFlags::One | SpecEnumFlags.new(8) | SpecEnumFlags.new(16)).to_s, "One | 24"
      assert_prints (SpecEnumFlags::One | SpecEnumFlags::Two | SpecEnumFlags.new(16)).to_s, "One | Two | 16"
    end

    it "for private enum" do
      assert_prints PrivateEnum::FOO.to_s, "FOO"
      assert_prints PrivateFlagsEnum::FOO.to_s, "FOO"
      assert_prints PrivateEnum::QUX.to_s, "FOO"
      assert_prints (PrivateFlagsEnum::FOO | PrivateFlagsEnum::BAZ).to_s, "FOO | BAZ"
      assert_prints PrivateFlagsEnum.new(128).to_s, "128"
      assert_prints (PrivateFlagsEnum::FOO | PrivateFlagsEnum.new(128)).to_s, "FOO | 128"
    end
  end

  describe "#inspect" do
    it "for simple enum" do
      assert_prints SpecEnum::One.inspect, "SpecEnum::One"
      assert_prints SpecEnum::Two.inspect, "SpecEnum::Two"
      assert_prints SpecEnum::Three.inspect, "SpecEnum::Three"
      assert_prints SpecEnum.new(127).inspect, "SpecEnum[127]"
    end

    it "for flags enum" do
      assert_prints SpecEnumFlags::None.inspect, "SpecEnumFlags::None"
      assert_prints SpecEnumFlags::All.inspect, "SpecEnumFlags::All"
      assert_prints (SpecEnumFlags::One).inspect, "SpecEnumFlags::One"
      assert_prints (SpecEnumFlags::One | SpecEnumFlags::Two).inspect, "SpecEnumFlags[One, Two]"
      assert_prints SpecEnumFlags.new(128).inspect, "SpecEnumFlags[128]"
      assert_prints (SpecEnumFlags::One | SpecEnumFlags.new(128)).inspect, "SpecEnumFlags[One, 128]"
      assert_prints (SpecEnumFlags::One | SpecEnumFlags.new(8) | SpecEnumFlags.new(16)).inspect, "SpecEnumFlags[One, 24]"
      assert_prints (SpecEnumFlags::One | SpecEnumFlags::Two | SpecEnumFlags.new(16)).inspect, "SpecEnumFlags[One, Two, 16]"
    end

    it "for private enum" do
      assert_prints PrivateEnum::FOO.inspect, "PrivateEnum::FOO"
      assert_prints PrivateFlagsEnum::FOO.inspect, "PrivateFlagsEnum::FOO"
      assert_prints PrivateEnum::QUX.inspect, "PrivateEnum::FOO"
      assert_prints (PrivateFlagsEnum::FOO | PrivateFlagsEnum::BAZ).inspect, "PrivateFlagsEnum[FOO, BAZ]"
      assert_prints PrivateFlagsEnum.new(128).inspect, "PrivateFlagsEnum[128]"
      assert_prints (PrivateFlagsEnum::FOO | PrivateFlagsEnum.new(128)).inspect, "PrivateFlagsEnum[FOO, 128]"
    end
  end

  describe "#downcase_name" do
    it "for simple enum" do
      assert_prints SpecEnum::One.downcase_name, "one"
      assert_prints SpecEnum::Two.downcase_name, "two"
      assert_prints SpecEnum2::FortyTwo.downcase_name, "fortytwo"
    end
  end

  describe "#snakecase_name" do
    it "for simple enum" do
      assert_prints SpecEnum::One.snakecase_name, "one"
      assert_prints SpecEnum2::FortyTwo.snakecase_name, "forty_two"
      assert_prints SpecEnum2::FORTY_FOUR.snakecase_name, "forty_four"
    end
  end

  describe "#kebabcase_name" do
    it "for simple enum" do
      assert_prints SpecEnum::One.kebabcase_name, "one"
      assert_prints SpecEnum2::FortyTwo.kebabcase_name, "forty-two"
      assert_prints SpecEnum2::FORTY_FOUR.kebabcase_name, "forty-four"
    end
  end

  it "creates an enum instance from an auto-casted symbol (#8573)" do
    enum_value = SpecEnum.new(:two)
    enum_value.should eq SpecEnum::Two

    SpecEnumWithCaseSensitiveMembers.new(:foo).should eq SpecEnumWithCaseSensitiveMembers::FOO
    SpecEnumWithCaseSensitiveMembers.new(:Foo).should eq SpecEnumWithCaseSensitiveMembers::FOO
    SpecEnumWithCaseSensitiveMembers.new(:FOO).should eq SpecEnumWithCaseSensitiveMembers::FOO
  end

  it "gets value" do
    SpecEnum::Two.value.should eq(1)
    SpecEnum::Two.value.should be_a(Int8)
  end

  it "gets value with to_i" do
    SpecEnum::Two.to_i.should eq(1)
    SpecEnum::Two.to_i.should be_a(Int32)
  end

  it "gets value with to_i<bit>" do
    SpecEnum::Two.to_i8.should eq(1)
    SpecEnum::Two.to_i8.should be_a(Int8)

    SpecEnum::Two.to_i16.should eq(1)
    SpecEnum::Two.to_i16.should be_a(Int16)

    SpecEnum::Two.to_i32.should eq(1)
    SpecEnum::Two.to_i32.should be_a(Int32)

    SpecEnum::Two.to_i64.should eq(1)
    SpecEnum::Two.to_i64.should be_a(Int64)

    SpecEnum::Two.to_i128.should eq(1)
    SpecEnum::Two.to_i128.should be_a(Int128)
  end

  it "gets value with to_u<bit>" do
    SpecEnum::Two.to_u8.should eq(1)
    SpecEnum::Two.to_u8.should be_a(UInt8)

    SpecEnum::Two.to_u16.should eq(1)
    SpecEnum::Two.to_u16.should be_a(UInt16)

    SpecEnum::Two.to_u32.should eq(1)
    SpecEnum::Two.to_u32.should be_a(UInt32)

    SpecEnum::Two.to_u64.should eq(1)
    SpecEnum::Two.to_u64.should be_a(UInt64)

    SpecEnum::Two.to_u128.should eq(1)
    SpecEnum::Two.to_u128.should be_a(UInt128)
  end

  it "does +" do
    (SpecEnum::One + 1).should eq(SpecEnum::Two)
  end

  it "does -" do
    (SpecEnum::Two - 1).should eq(SpecEnum::One)
  end

  it "sorts" do
    [SpecEnum::Three, SpecEnum::One, SpecEnum::Two].sort.should eq([SpecEnum::One, SpecEnum::Two, SpecEnum::Three])
  end

  it "does includes?" do
    (SpecEnumFlags::One | SpecEnumFlags::Two).includes?(SpecEnumFlags::One).should be_true
    (SpecEnumFlags::One | SpecEnumFlags::Two).includes?(SpecEnumFlags::Three).should be_false
    SpecEnumFlags::One.includes?(SpecEnumFlags::None).should be_true
    SpecEnumFlags::None.includes?(SpecEnumFlags::None).should be_true
    SpecEnumFlags::None.includes?(SpecEnumFlags::One).should be_false
    SpecEnumFlags::One.includes?(SpecEnumFlags::One | SpecEnumFlags::Two).should be_false
    (SpecEnumFlags::One | SpecEnumFlags::Two).includes?(SpecEnumFlags::One | SpecEnumFlags::Two).should be_true
    (SpecEnumFlags::One | SpecEnumFlags::Two | SpecEnumFlags::Three).includes?(SpecEnumFlags::One | SpecEnumFlags::Two).should be_true
  end

  describe "each" do
    it "won't yield None" do
      SpecEnumFlags::None.each do |name|
        raise "unexpected yield"
      end
    end

    it "won't yield All" do
      SpecEnumFlags::All.each do |name|
        raise "unexpected yield" if name == SpecEnumFlags::All
      end
    end

    it "yields each member" do
      names = [] of SpecEnumFlags
      values = [] of Int32
      SpecEnumFlags.flags(One, Three).each do |name, value|
        names << name
        values << value
      end
      names.should eq([SpecEnumFlags::One, SpecEnumFlags::Three])
      values.should eq([SpecEnumFlags::One.value, SpecEnumFlags::Three.value])
    end

    it "private enum" do
      names = [] of PrivateFlagsEnum
      values = [] of Int32
      (PrivateFlagsEnum::FOO | PrivateFlagsEnum::BAZ).each do |name, value|
        names << name
        values << value
      end
      names.should eq([PrivateFlagsEnum::FOO, PrivateFlagsEnum::BAZ])
      values.should eq([PrivateFlagsEnum::FOO.value, PrivateFlagsEnum::BAZ.value])
    end
  end

  describe "names" do
    it "for simple enum" do
      SpecEnum.names.should eq(%w(One Two Three))
    end

    it "for flags enum" do
      SpecEnumFlags.names.should eq(%w(One Two Three))
    end
  end

  describe "values" do
    it "for simple enum" do
      SpecEnum.values.should eq([SpecEnum::One, SpecEnum::Two, SpecEnum::Three])
    end

    it "for flags enum" do
      SpecEnumFlags.values.should eq([SpecEnumFlags::One, SpecEnumFlags::Two, SpecEnumFlags::Three])
    end
  end

  describe "from_value?" do
    it "for simple enum" do
      SpecEnum.from_value?(0).should eq(SpecEnum::One)
      SpecEnum.from_value?(1).should eq(SpecEnum::Two)
      SpecEnum.from_value?(1_i8).should eq(SpecEnum::Two)
      SpecEnum.from_value?(2).should eq(SpecEnum::Three)
      SpecEnum.from_value?(3).should be_nil
    end

    it "for flags enum" do
      SpecEnumFlags.from_value?(0).should eq(SpecEnumFlags::None)
      SpecEnumFlags.from_value?(1).should eq(SpecEnumFlags::One)
      SpecEnumFlags.from_value?(1_i8).should eq(SpecEnumFlags::One)
      SpecEnumFlags.from_value?(2).should eq(SpecEnumFlags::Two)
      SpecEnumFlags.from_value?(3).should eq(SpecEnumFlags::One | SpecEnumFlags::Two)
      SpecEnumFlags.from_value?(8).should be_nil
      SpecEnumFlags8.from_value?(1_i8).should eq(SpecEnumFlags8::One)
    end
  end

  describe "from_value" do
    it "for simple enum" do
      SpecEnum.from_value(0).should eq(SpecEnum::One)
      SpecEnum.from_value(1).should eq(SpecEnum::Two)
      SpecEnum.from_value(2).should eq(SpecEnum::Three)
      expect_raises(Exception, "Unknown enum SpecEnum value: 3") { SpecEnum.from_value(3) }
    end

    it "for flags enum" do
      SpecEnumFlags.from_value(0).should eq(SpecEnumFlags::None)
      SpecEnumFlags.from_value(1).should eq(SpecEnumFlags::One)
      SpecEnumFlags.from_value(2).should eq(SpecEnumFlags::Two)
      SpecEnumFlags.from_value(3).should eq(SpecEnumFlags::One | SpecEnumFlags::Two)
      expect_raises(Exception, "Unknown enum SpecEnumFlags value: 8") { SpecEnumFlags.from_value(8) }
    end

    it "for private enum" do
      PrivateEnum.from_value(0).should eq(PrivateEnum::FOO)
    end
  end

  describe "valid?" do
    it "for simple enum" do
      SpecEnum.valid?(SpecEnum::One).should be_true
      SpecEnum.valid?(SpecEnum::Two).should be_true
      SpecEnum.valid?(SpecEnum::Three).should be_true
      SpecEnum.valid?(SpecEnum.new(3i8)).should be_false
    end

    it "for flags enum" do
      SpecEnumFlags.valid?(SpecEnumFlags::One).should be_true
      SpecEnumFlags.valid?(SpecEnumFlags::Two).should be_true
      SpecEnumFlags.valid?(SpecEnumFlags::One | SpecEnumFlags::Two).should be_true
      SpecEnumFlags.valid?(SpecEnumFlags.new(8)).should be_false
      SpecEnumFlags.valid?(SpecEnumFlags::None).should be_true
      SpecEnumFlags.valid?(SpecEnumFlags::All).should be_true
    end

    it "for Int64 enum" do
      SpecBigEnum.valid?(SpecBigEnum::TooBig).should be_true
      SpecBigEnum.valid?(SpecBigEnum.new(0i64)).should be_false
    end
  end

  it "has hash" do
    SpecEnum::Two.hash.should_not eq(SpecEnum::Three.hash)
  end

  it ".parse" do
    SpecEnum.parse("Two").should eq(SpecEnum::Two)
    SpecEnum2.parse("FortyTwo").should eq(SpecEnum2::FortyTwo)
    SpecEnum2.parse("forty_two").should eq(SpecEnum2::FortyTwo)
    expect_raises(ArgumentError, "Unknown enum SpecEnum value: Four") { SpecEnum.parse("Four") }

    SpecEnum.parse("TWO").should eq(SpecEnum::Two)
    SpecEnum.parse("TwO").should eq(SpecEnum::Two)
    SpecEnum2.parse("FORTY_TWO").should eq(SpecEnum2::FortyTwo)

    SpecEnum2.parse("FORTY_FOUR").should eq(SpecEnum2::FORTY_FOUR)
    SpecEnum2.parse("forty_four").should eq(SpecEnum2::FORTY_FOUR)
    SpecEnum2.parse("FORTY-FOUR").should eq(SpecEnum2::FORTY_FOUR)
    SpecEnum2.parse("forty-four").should eq(SpecEnum2::FORTY_FOUR)
    SpecEnum2.parse("FortyFour").should eq(SpecEnum2::FORTY_FOUR)
    SpecEnum2.parse("FORTYFOUR").should eq(SpecEnum2::FORTY_FOUR)
    SpecEnum2.parse("fortyfour").should eq(SpecEnum2::FORTY_FOUR)

    PrivateEnum.parse("FOO").should eq(PrivateEnum::FOO)
    PrivateEnum.parse("BAR").should eq(PrivateEnum::BAR)
    PrivateEnum.parse("QUX").should eq(PrivateEnum::QUX)

    SpecEnumWithCaseSensitiveMembers.parse("foo").should eq SpecEnumWithCaseSensitiveMembers::FOO
    SpecEnumWithCaseSensitiveMembers.parse("FOO").should eq SpecEnumWithCaseSensitiveMembers::FOO
    SpecEnumWithCaseSensitiveMembers.parse("Foo").should eq SpecEnumWithCaseSensitiveMembers::FOO
  end

  it ".parse?" do
    SpecEnum.parse?("Two").should eq(SpecEnum::Two)
    SpecEnum.parse?("Four").should be_nil
    SpecEnum.parse?("Fo-ur").should be_nil
  end

  it "clones" do
    SpecEnum::One.clone.should eq(SpecEnum::One)
  end

  describe ".[]" do
    it "non-flags enum" do
      SpecEnum[].should be_nil
      SpecEnum[One].should eq SpecEnum::One
      SpecEnum[1].should eq SpecEnum::Two
      SpecEnum[One, Two].should eq SpecEnum::One | SpecEnum::Two
      SpecEnum[One, :two].should eq SpecEnum::One | SpecEnum::Two
      SpecEnum[One, 1].should eq SpecEnum::One | SpecEnum::Two
    end

    it "flags enum" do
      SpecEnumFlags.flags.should be_nil
      SpecEnumFlags[One].should eq SpecEnumFlags::One
      SpecEnumFlags[2].should eq SpecEnumFlags::Two
      SpecEnumFlags[One, Two].should eq SpecEnumFlags::One | SpecEnumFlags::Two
      SpecEnumFlags[One, :two].should eq SpecEnumFlags::One | SpecEnumFlags::Two
      SpecEnumFlags[One, 2].should eq SpecEnumFlags::One | SpecEnumFlags::Two
    end

    it "private flags enum" do
      PrivateFlagsEnum.flags.should be_nil
      PrivateFlagsEnum[FOO].should eq PrivateFlagsEnum::FOO
      PrivateFlagsEnum[FOO, BAR].should eq PrivateFlagsEnum::FOO | PrivateFlagsEnum::BAR
    end
  end

  describe ".flags" do
    it "non-flags enum" do
      SpecEnum.flags.should be_nil
      SpecEnum.flags(One).should eq SpecEnum::One
      SpecEnum.flags(One, Two).should eq SpecEnum::One | SpecEnum::Two
    end

    it "flags enum" do
      SpecEnumFlags.flags.should be_nil
      SpecEnumFlags.flags(One).should eq SpecEnumFlags::One
      SpecEnumFlags.flags(One, Two).should eq SpecEnumFlags::One | SpecEnumFlags::Two
    end

    it "private flags enum" do
      PrivateFlagsEnum.flags.should be_nil
      PrivateFlagsEnum.flags(FOO).should eq PrivateFlagsEnum::FOO
      PrivateFlagsEnum.flags(FOO, BAR).should eq PrivateFlagsEnum::FOO | PrivateFlagsEnum::BAR
    end
  end

  describe "each" do
    it "iterates each member" do
      keys = [] of SpecEnum
      values = [] of Int8

      SpecEnum.each do |key, value|
        keys << key
        values << value
      end

      keys.should eq([SpecEnum::One, SpecEnum::Two, SpecEnum::Three])
      values.should eq([SpecEnum::One.value, SpecEnum::Two.value, SpecEnum::Three.value])
    end

    it "iterates each flag" do
      keys = [] of SpecEnumFlags
      values = [] of Int32

      SpecEnumFlags.each do |key, value|
        keys << key
        values << value
      end

      keys.should eq([SpecEnumFlags::One, SpecEnumFlags::Two, SpecEnumFlags::Three])
      values.should eq([SpecEnumFlags::One.value, SpecEnumFlags::Two.value, SpecEnumFlags::Three.value])
    end

    it "iterates private enum members" do
      keys = [] of PrivateEnum
      values = [] of Int32

      PrivateEnum.each do |key, value|
        keys << key
        values << value
      end

      keys.should eq([PrivateEnum::FOO, PrivateEnum::BAR, PrivateEnum::BAZ, PrivateEnum::QUX])
      values.should eq([PrivateEnum::FOO.value, PrivateEnum::BAR.value, PrivateEnum::BAZ.value, PrivateEnum::QUX.value])
    end
  end

  it "different enums classes not eq always" do
    SpecEnum::One.should_not eq SpecEnum2::FortyTwo
  end
end
