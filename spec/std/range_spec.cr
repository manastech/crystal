require "./spec_helper"
require "spec/helpers/iterate"
require "big"

struct RangeSpecIntWrapper
  include Comparable(self)

  getter value : Int32

  def initialize(@value)
  end

  def succ
    RangeSpecIntWrapper.new(@value + 1)
  end

  def <=>(other)
    value <=> other.value
  end

  def self.additive_identity
    RangeSpecIntWrapper.new(0)
  end

  def +(other : RangeSpecIntWrapper)
    RangeSpecIntWrapper.new(value + other.value)
  end
end

private def range_endless_each
  (2..).each do |x|
    return x
  end
end

private def range_beginless_reverse_each
  (..2).reverse_each do |x|
    return x
  end
end

describe "Range" do
  it "initialized with new method" do
    Range.new(1, 10).should eq(1..10)
    Range.new(1, 10, false).should eq(1..10)
    Range.new(1, 10, true).should eq(1...10)
  end

  it "gets basic properties" do
    r = 1..5
    r.begin.should eq(1)
    r.end.should eq(5)
    r.excludes_end?.should be_false

    r = 1...5
    r.begin.should eq(1)
    r.end.should eq(5)
    r.excludes_end?.should be_true
  end

  it "#==" do
    ((1..1) == (1..1)).should be_true
    ((1...1) == (1..1)).should be_false
    ((1...1) == (1...1)).should be_true
    ((1..1) == (1...1)).should be_false

    ((1..nil) == (1..nil)).should be_true

    (1..1).should eq Range(Int32?, Int32?).new(1, 1)
    ((1..1) == Range(Int32?, Int32?).new(1, 1)).should be_true
    ((1.0..1.0) == (1..1)).should be_true
  end

  it "includes?" do
    (1..5).includes?(1).should be_true
    (1..5).includes?(5).should be_true

    (1...5).includes?(1).should be_true
    (1...5).includes?(5).should be_false
  end

  it "does union" do
    # Int ranges
    (1..5).union(3..7).should eq(1..7)    # Overlapping integer ranges
    (1..5).union(6..10).should eq(1..10)  # Adjacent ranges
    (1..5).union(10..15).should eq(1...1) # Disjoint integer ranges

    # Float ranges
    (1.0..5.5).union(3.2..7.8).should eq(1.0..7.8)  # Overlapping float ranges
    (1.0..2.5).union(3.0..4.0).should eq(1.0...1.0) # Non-overlapping float ranges

    # String ranges
    ('a'..'e').union('c'..'g').should eq('a'..'g')  # Overlapping string ranges
    ('a'..'c').union('e'..'f').should eq('a'...'a') # Non-overlapping string ranges
    ('a'..'c').union('d'..'f').should eq('a'..'f')  # Adjacent string ranges

    # Time ranges
    t1 = Time.local(2024, 10, 1)
    t2 = Time.local(2024, 10, 5)
    t3 = Time.local(2024, 10, 10)
    t4 = Time.local(2024, 10, 15)
    (t1..t2).union(t2..t3).should eq(t1..t3)  # Adjacent time ranges
    (t1..t2).union(t3..t4).should eq(t1...t1) # Disjoint time ranges

    # Exclusive ranges
    (1...5).union(5...10).should eq(1...10)           # Adjacent exclusive integer ranges
    (1.0...5.5).union(3.2...7.8).should eq(1.0...7.8) # Overlapping exclusive float ranges
    ('a'...'e').union('c'...'g').should eq('a'...'g') # Overlapping exclusive string ranges
    (t1...t2).union(t2...t3).should eq(t1...t3)       # Adjacent exclusive time ranges

  end

  it "does intersection" do
    # Int ranges
    (1..5).intersection(3..7).should eq(3..5)   # Overlapping integer ranges
    (1..5).intersection(6..10).should eq(1...1) # Non-overlapping integer ranges
    (1..5).intersection(5..10).should eq(5..5)
    (1...1).intersection(0..10).should eq(1...1)

    # Float ranges
    (1.0..5.5).intersection(3.2..7.8).should eq(3.2..5.5)  # Overlapping float ranges
    (1.0..2.5).intersection(3.0..4.0).should eq(1.0...1.0) # Non-overlapping float ranges

    # String ranges
    ('a'..'e').intersection('c'..'g').should eq('c'..'e')  # Overlapping string ranges
    ('a'..'c').intersection('d'..'f').should eq('a'...'a') # Non-overlapping string ranges

    # Time ranges
    t1 = Time.local(2024, 10, 1)
    t2 = Time.local(2024, 10, 5)
    t3 = Time.local(2024, 10, 10)
    t4 = Time.local(2024, 10, 15)
    (t1..t3).intersection(t2..t4).should eq(t2..t3)  # Overlapping time ranges
    (t1..t2).intersection(t3..t4).should eq(t1...t1) # Non-overlapping time ranges

    # Exclusive ranges
    (1...5).intersection(3...7).should eq(3...5)             # Overlapping exclusive integer ranges
    (1.0...5.5).intersection(3.2...7.8).should eq(3.2...5.5) # Overlapping exclusive float ranges
    ('a'...'e').intersection('c'...'g').should eq('c'...'e') # Overlapping exclusive string ranges
    (t1...t3).intersection(t2...t4).should eq(t2...t3)       # Overlapping exclusive time ranges
  end

  it "overlaps?" do
    # Int ranges
    (1..5).overlaps?(3..7).should eq(true)   # Overlapping integer ranges
    (1..5).overlaps?(6..10).should eq(false) # Non-overlapping integer ranges

    # Float ranges
    (1.0..5.5).overlaps?(3.2..7.8).should eq(true)  # Overlapping float ranges
    (1.0..2.5).overlaps?(3.0..4.0).should eq(false) # Non-overlapping float ranges

    # String ranges
    ('a'..'e').overlaps?('c'..'g').should eq(true)  # Overlapping string ranges
    ('a'..'c').overlaps?('d'..'f').should eq(false) # Non-overlapping string ranges

    # Time ranges
    t1 = Time.local(2024, 10, 1)
    t2 = Time.local(2024, 10, 5)
    t3 = Time.local(2024, 10, 10)
    t4 = Time.local(2024, 10, 15)
    (t1..t3).overlaps?(t2..t4).should eq(true)  # Overlapping time ranges
    (t1..t2).overlaps?(t3..t4).should eq(false) # Non-overlapping time ranges
  end

  it "does to_s" do
    (1...5).to_s.should eq("1...5")
    (1..5).to_s.should eq("1..5")
    (1..nil).to_s.should eq("1..")
    (nil..3).to_s.should eq("..3")
    (nil..nil).to_s.should eq("..")
  end

  it "does inspect" do
    (1...5).inspect.should eq("1...5")
  end

  it "is empty with .. and begin > end" do
    (1..0).to_a.should be_empty
  end

  it "is empty with ... and begin > end" do
    (1...0).to_a.should be_empty
  end

  it "is not empty with .. and begin == end" do
    (1..1).to_a.should eq([1])
  end

  it "is not empty with ... and begin.succ == end" do
    (1...2).to_a.should eq([1])
  end

  describe "sum" do
    it "called with no block is specialized for performance" do
      (1..3).sum.should eq 6
      (1...3).sum.should eq 3
      (1..3).sum(4).should eq 10
      (3..1).sum(4).should eq 4
      (1..11).step(2).sum.should eq 36
      (1...11).step(2).sum.should eq 25
    end

    it "called with no block is specialized for performance (BigInt)" do
      (BigInt.new("1")..BigInt.new("1 000 000 000")).sum.should eq BigInt.new("500 000 000 500 000 000")
      (BigInt.new("1")..BigInt.new("1 000 000 000")).step(2).sum.should eq BigInt.new("250 000 000 000 000 000")
    end

    it "is equivalent to Enumerable#sum" do
      (1..3).sum { |x| x * 2 }.should eq 12
      (1..3).step(2).sum { |x| x * 2 }.should eq 8
      (RangeSpecIntWrapper.new(1)..RangeSpecIntWrapper.new(3)).sum.should eq RangeSpecIntWrapper.new(6)
      (RangeSpecIntWrapper.new(1)..RangeSpecIntWrapper.new(3)).step(2).sum.should eq RangeSpecIntWrapper.new(4)
    end
  end

  describe "bsearch" do
    it "Int" do
      ary = [3, 4, 7, 9, 12]
      (0...ary.size).bsearch { |i| ary[i] >= 2 }.should eq 0
      (0...ary.size).bsearch { |i| ary[i] >= 4 }.should eq 1
      (0...ary.size).bsearch { |i| ary[i] >= 6 }.should eq 2
      (0...ary.size).bsearch { |i| ary[i] >= 8 }.should eq 3
      (0...ary.size).bsearch { |i| ary[i] >= 10 }.should eq 4
      (0...ary.size).bsearch { |i| ary[i] >= 100 }.should eq nil
      (0...ary.size).bsearch { |i| true }.should eq 0
      (0...ary.size).bsearch { |i| false }.should eq nil

      (0...ary.size).bsearch { |i| ary[i] >= 10 ? 1 : nil }.should eq 4

      ary = [0, 100, 100, 100, 200]
      (0...ary.size).bsearch { |i| ary[i] >= 100 }.should eq 1

      (0_i8..10_i8).bsearch { |x| x >= 10 }.should eq 10_i8
      (0_i8...10_i8).bsearch { |x| x >= 10 }.should eq nil
      (-10_i8...10_i8).bsearch { |x| x >= -5 }.should eq -5_i8

      (0_u8..10_u8).bsearch { |x| x >= 10 }.should eq 10_u8
      (0_u8...10_u8).bsearch { |x| x >= 10 }.should eq nil
      (0_u32..10_u32).bsearch { |x| x >= 10 }.should eq 10_u32
      (0_u32...10_u32).bsearch { |x| x >= 10 }.should eq nil
    end

    it "BigInt" do
      (BigInt.new("-10")...BigInt.new("10")).bsearch { |x| x >= -5 }.should eq BigInt.new("-5")
    end

    it "Float" do
      inf = Float64::INFINITY
      (0.0...100.0).bsearch { |x| x > 0 && Math.log(x / 10) >= 0 }.not_nil!.should be_close(10.0, 0.0001)
      (0.0...inf).bsearch { |x| x > 0 && Math.log(x / 10) >= 0 }.not_nil!.should be_close(10.0, 0.0001)
      (-inf..100.0).bsearch { |x| x >= 0 || Math.log(-x / 10) < 0 }.not_nil!.should be_close(-10.0, 0.0001)
      (-inf..inf).bsearch { |x| x > 0 && Math.log(x / 10) >= 0 }.not_nil!.should be_close(10.0, 0.0001)
      (-inf..5).bsearch { |x| x > 0 && Math.log(x / 10) >= 0 }.should be_nil

      (-inf..10).bsearch { |x| x > 0 && Math.log(x / 10) >= 0 }.not_nil!.should be_close(10.0, 0.0001)
      (inf...10).bsearch { |x| x > 0 && Math.log(x / 10) >= 0 }.should be_nil

      (-inf..inf).bsearch { false }.should be_nil
      (-inf..inf).bsearch { true }.should eq -inf

      (0..inf).bsearch { |x| x == inf }.should eq inf
      (0...inf).bsearch { |x| x == inf }.should be_nil

      v = (0.0..1.0).bsearch { |x| x > 0 }.not_nil!
      v.should be_close(0, 0.0001)
      v.should be > 0

      (-1.0..0.0).bsearch { |x| x >= 0 }.should eq 0.0
      (-1.0...0.0).bsearch { |x| x >= 0 }.should be_nil

      (0.0..inf).bsearch { |x| Math.log(x) >= 0 }.not_nil!.should be_close(1.0, 0.0001)

      (0.0..10).bsearch { |x| x >= 3.5 }.not_nil!.should be_close(3.5, 0.0001)
      (0..10.0).bsearch { |x| x >= 3.5 }.not_nil!.should be_close(3.5, 0.0001)

      (0_f32..5_f32).bsearch { |x| x >= 5_f32 }.not_nil!.should be_close(5_f32, 0.0001_f32)
      (0_f32...5_f32).bsearch { |x| x >= 5_f32 }.should be_nil
      (0_f32..5.0).bsearch { |x| x >= 5.0 }.not_nil!.should be_close(5.0, 0.0001)
      (0..5.0_f32).bsearch { |x| x >= 5.0 }.not_nil!.should be_close(5.0, 0.0001)

      inf32 = Float32::INFINITY
      (0..inf32).bsearch { |x| x == inf32 }.should eq inf32
      (0_f32..inf).bsearch { |x| x == inf }.should eq inf
      (0.0..inf32).bsearch { |x| x == inf32 }.should eq inf32
      (0_f32...5_f32).bsearch { |x| x >= 5_f32 }.should be_nil
    end
  end

  describe "#each" do
    it "gives correct values with inclusive range" do
      range = -1..3
      arr = [] of Int32
      range.each { |x| arr << x }
      arr.should eq([-1, 0, 1, 2, 3])
    end

    it "gives correct values with exclusive range" do
      range = 'a'...'c'
      arr = [] of Char
      range.each { |x| arr << x }
      arr.should eq(['a', 'b'])
    end

    it "is empty with empty inclusive range" do
      range = 0..-1
      any = false
      range.each { any = true }
      any.should eq(false)
    end

    it "endless" do
      range = (3..nil)
      ary = [] of Int32
      range.each do |x|
        ary << x
        break if ary.size == 5
      end
      ary.should eq([3, 4, 5, 6, 7])
    end

    it "raises on beginless" do
      expect_raises(ArgumentError, "Can't each beginless range") do
        (..4).each { }
      end
      typeof((..4).each { |x| break x }).should eq Nil
      expect_raises(ArgumentError, "Can't each beginless range") do
        (nil.as(Int32?)..4).each { }
      end
      typeof((nil.as(Int32?)..4).each { |x| break x }).should eq Int32?
    end

    it "doesn't have Nil as a type for endless each" do
      typeof(range_endless_each).should eq(Int32)
    end

    it "doesn't have Nil as a type for beginless each" do
      typeof(range_beginless_reverse_each).should eq(Int32)
    end
  end

  describe "#reverse_each" do
    it "gives correct values with inclusive range" do
      range = 'a'..'c'
      arr = [] of Char
      range.reverse_each { |x| arr << x }
      arr.should eq(['c', 'b', 'a'])
    end

    it "gives correct values with exclusive range" do
      range = -1...3
      arr = [] of Int32
      range.reverse_each { |x| arr << x }
      arr.should eq([2, 1, 0, -1])
    end

    it "is empty with empty inclusive range" do
      range = 0..-1
      any = false
      range.reverse_each { any = true }
      any.should eq(false)
    end

    it "raises on endless range" do
      expect_raises(ArgumentError, "Can't reverse_each endless range") do
        (3..).reverse_each { }
      end
      expect_raises(ArgumentError, "Can't reverse_each endless range") do
        (3..nil.as(Int32?)).reverse_each { }
      end
    end

    it "iterators on beginless range" do
      range = nil..2
      arr = [] of Int32
      range.reverse_each do |x|
        arr << x
        break if arr.size == 5
      end
      arr.should eq([2, 1, 0, -1, -2])
    end
  end

  describe "#each iterator" do
    it "does next with inclusive range" do
      a = 1..3
      iter = a.each
      iter.next.should eq(1)
      iter.next.should eq(2)
      iter.next.should eq(3)
      iter.next.should be_a(Iterator::Stop)
    end

    it "does next with exclusive range" do
      r = 1...3
      iter = r.each
      iter.next.should eq(1)
      iter.next.should eq(2)
      iter.next.should be_a(Iterator::Stop)
    end

    it "does with endless range" do
      r = (3..nil)
      iter = r.each
      iter.next.should eq(3)
      iter.next.should eq(4)
    end

    it "raises on beginless range" do
      expect_raises(ArgumentError, "Can't each beginless range") do
        (..3).each
      end
      expect_raises(ArgumentError, "Can't each beginless range") do
        (nil.as(Int32?)..3).each
      end
    end

    it "cycles" do
      (1..3).cycle.first(8).join.should eq("12312312")
    end

    it "is empty with .. and begin > end" do
      (1..0).each.to_a.should be_empty
    end

    it "is empty with ... and begin > end" do
      (1...0).each.to_a.should be_empty
    end

    it "is not empty with .. and begin == end" do
      (1..1).each.to_a.should eq([1])
    end

    it "is not empty with ... and begin.succ == end" do
      (1...2).each.to_a.should eq([1])
    end
  end

  describe "#reverse_each iterator" do
    it "does next with inclusive range" do
      a = 1..3
      iter = a.reverse_each
      iter.next.should eq(3)
      iter.next.should eq(2)
      iter.next.should eq(1)
      iter.next.should be_a(Iterator::Stop)
    end

    it "does next with exclusive range" do
      r = 1...3
      iter = r.reverse_each
      iter.next.should eq(2)
      iter.next.should eq(1)
      iter.next.should be_a(Iterator::Stop)
    end

    it "does next with beginless range" do
      r = nil...3
      iter = r.reverse_each
      iter.next.should eq(2)
      iter.next.should eq(1)
      iter.next.should eq(0)
      iter.next.should eq(-1)
    end

    it "reverse cycles" do
      (1..3).reverse_each.cycle.first(8).join.should eq("32132132")
    end

    it "is empty with .. and begin > end" do
      (1..0).reverse_each.to_a.should be_empty
    end

    it "is empty with ... and begin > end" do
      (1...0).reverse_each.to_a.should be_empty
    end

    it "is not empty with .. and begin == end" do
      (1..1).reverse_each.to_a.should eq([1])
    end

    it "is not empty with ... and begin.succ == end" do
      (1...2).reverse_each.to_a.should eq([1])
    end

    it "raises on endless range" do
      expect_raises(ArgumentError, "Can't reverse_each endless range") do
        (1..).reverse_each
      end
      expect_raises(ArgumentError, "Can't reverse_each endless range") do
        (1..nil.as(Int32?)).reverse_each
      end
    end
  end

  describe "#sample" do
    it "raises on open range" do
      expect_raises(ArgumentError, "Can't sample an open range") do
        (1..).sample
      end
      expect_raises(ArgumentError, "Can't sample an open range") do
        (1..nil.as(Int32?)).sample
      end
      expect_raises(ArgumentError, "Can't sample an open range") do
        (..1).sample
      end
      expect_raises(ArgumentError, "Can't sample an open range") do
        (nil.as(Int32?)..1).sample
      end
      expect_raises(ArgumentError, "Can't sample an open range") do
        (..).sample
      end
      expect_raises(ArgumentError, "Can't sample an open range") do
        (nil.as(Int32?)..nil.as(Int32?)).sample
      end
    end

    it "samples a float range as a distribution" do
      r = (1.2..3.4)
      x = r.sample
      r.should contain(x)

      r.sample(Random.new(1)).should be_close(2.9317256017544837, 1e-12)
    end

    it "samples a range with nilable types" do
      r = ((true ? 1 : nil)..(true ? 4 : nil))
      x = r.sample
      r.should contain(x)

      ((true ? 1 : nil)...(true ? 2 : nil)).sample.should eq(1)

      r = ((true ? 1.2 : nil)..(true ? 3.4 : nil))
      x = r.sample
      r.should contain(x)
    end

    it "samples with n = 0" do
      (1..3).sample(0).empty?.should be_true
    end

    context "for an integer range" do
      it "samples an inclusive range without n" do
        value = (1..3).sample
        (1 <= value <= 3).should be_true
      end

      it "samples an exclusive range without n" do
        value = (1...3).sample
        (1 <= value <= 2).should be_true
      end

      it "samples an inclusive range with n = 1" do
        values = (1..3).sample(1)
        values.size.should eq(1)
        (1 <= values.first <= 3).should be_true
      end

      it "samples an exclusive range with n = 1" do
        values = (1...3).sample(1)
        values.size.should eq(1)
        (1 <= values.first <= 2).should be_true
      end

      it "samples an inclusive range with n > 1" do
        values = (1..10).sample(5)
        values.size.should eq(5)
        values.uniq.size.should eq(5)
        values.all? { |value| 1 <= value <= 10 }.should be_true
      end

      it "samples an exclusive range with n > 1" do
        values = (1...10).sample(5)
        values.size.should eq(5)
        values.uniq.size.should eq(5)
        values.all? { |value| 1 <= value <= 9 }.should be_true
      end

      it "samples an inclusive range with n > 16" do
        values = (1..1000).sample(100)
        values.size.should eq(100)
        values.uniq.size.should eq(100)
        values.all? { |value| 1 <= value <= 1000 }.should be_true
      end

      it "samples an inclusive range with n equal to or bigger than the available values" do
        values = (1..10).sample(20)
        values.size.should eq(10)
        values.uniq.size.should eq(10)
        values.all? { |value| 1 <= value <= 10 }.should be_true
      end

      it "raises on invalid range without n" do
        expect_raises ArgumentError do
          (1..0).sample
        end
      end

      it "raises on invalid range with n = 0" do
        expect_raises ArgumentError do
          (1..0).sample(0)
        end
      end

      it "raises on invalid range with n = 1" do
        expect_raises ArgumentError do
          (1..0).sample(1)
        end
      end

      it "raises on invalid range with n > 1" do
        expect_raises ArgumentError do
          (1..0).sample(10)
        end
      end

      it "raises on exclusive range that would underflow" do
        expect_raises ArgumentError do
          (1_u8...0_u8).sample(10)
        end
      end
    end

    context "for a float range" do
      it "samples an inclusive range without n" do
        value = (1.0..2.0).sample
        (1.0 <= value <= 2.0).should be_true
      end

      it "samples an exclusive range without n" do
        value = (1.0...2.0).sample
        (1.0 <= value < 2.0).should be_true
      end

      it "samples an inclusive range with n = 1" do
        values = (1.0..2.0).sample(1)
        values.size.should eq(1)
        (1.0 <= values.first <= 2.0).should be_true
      end

      it "samples an exclusive range with n = 1" do
        values = (1.0..2.0).sample(1)
        values.size.should eq(1)
        (1.0 <= values.first < 2.0).should be_true
      end

      it "samples an inclusive range with n > 1" do
        values = (1.0..2.0).sample(10)
        values.size.should eq(10)
        values.all? { |value| 1.0 <= value <= 2.0 }.should be_true
      end

      it "samples an exclusive range with n > 1" do
        values = (1.0...2.0).sample(10)
        values.size.should eq(10)
        values.all? { |value| 1.0 <= value < 2.0 }.should be_true
      end

      it "samples an inclusive range with n >= 1 and begin == end" do
        values = (1.0..1.0).sample(3)
        values.size.should eq(1)
        values.first.should eq(1.0)
      end

      it "samples an inclusive range with n > 16" do
        values = (1.0..2.0).sample(100)
        values.size.should eq(100)
        values.all? { |value| 1.0 <= value <= 2.0 }.should be_true
      end

      it "raises on invalid range with n = 0" do
        expect_raises ArgumentError do
          (1.0..0.0).sample(0)
        end
      end

      it "raises on invalid range with n = 1" do
        expect_raises ArgumentError do
          (1.0..0.0).sample(1)
        end
      end

      it "raises on invalid range with n > 1" do
        expect_raises ArgumentError do
          (1.0..0.0).sample(10)
        end
      end
    end
  end

  describe "#step" do
    it_iterates "inclusive default", [1, 2, 3, 4, 5], (1..5).step
    it_iterates "inclusive step", [1, 3, 5], (1..5).step(2)
    it_iterates "inclusive step over", [1, 3, 5], (1..6).step(2)

    it_iterates "exclusive default", [1, 2, 3, 4], (1...5).step
    it_iterates "exclusive step", [1, 3], (1...5).step(2)
    it_iterates "exclusive step over", [1, 3, 5], (1...6).step(2)

    it_iterates "endless range", [1, 3, 5, 7, 9], (1...nil).step(2), infinite: true

    it "raises on beginless range" do
      expect_raises(ArgumentError, "Can't step beginless range") do
        (nil..3).step(2) { }
      end
    end

    it_iterates "begin > end inclusive", [] of Int32, (1..0).step(1)
    it_iterates "begin > end exclusive", [] of Int32, (1...0).step(1)

    it_iterates "begin == end inclusive", [1], (1..1).step(1)
    it_iterates "begin == end exclusive", [] of Int32, (1...1).step(1)
    it_iterates "begin.succ == end inclusive", [1, 2] of Int32, (1..2).step(1)
    it_iterates "begin.succ == end exclusive", [1] of Int32, (1...2).step(1)

    it_iterates "Float step", [1.0, 1.5, 2.0, 2.5, 3.0], (1..3).step(by: 0.5)
    it_iterates "Time::Span step", [1.minutes, 2.minutes, 3.minutes], (1.minutes..3.minutes).step(by: 1.minutes)

    describe "with #succ type" do
      range_basic = RangeSpecIntWrapper.new(1)..RangeSpecIntWrapper.new(5)
      it_iterates "basic", [1, 2, 3, 4, 5].map(&->RangeSpecIntWrapper.new(Int32)), range_basic.step
      it_iterates "basic by", [1, 3, 5].map(&->RangeSpecIntWrapper.new(Int32)), range_basic.step(by: 2)
      it_iterates "missing end by", [1, 4].map(&->RangeSpecIntWrapper.new(Int32)), range_basic.step(by: 3)

      it_iterates "at definition range",
        [Int32::MAX - 2, Int32::MAX - 1, Int32::MAX].map(&->RangeSpecIntWrapper.new(Int32)),
        (RangeSpecIntWrapper.new(Int32::MAX - 2)..RangeSpecIntWrapper.new(Int32::MAX)).step
      it_iterates "at definition range by",
        [RangeSpecIntWrapper.new(Int32::MAX - 2), RangeSpecIntWrapper.new(Int32::MAX)],
        (RangeSpecIntWrapper.new(Int32::MAX - 2)..RangeSpecIntWrapper.new(Int32::MAX)).step(by: 2)
      it_iterates "at definition range missing by",
        [RangeSpecIntWrapper.new(Int32::MAX - 1)],
        (RangeSpecIntWrapper.new(Int32::MAX - 1)..RangeSpecIntWrapper.new(Int32::MAX)).step(by: 2)
      it_iterates "at definition range by",
        [RangeSpecIntWrapper.new(Int32::MAX - 3), RangeSpecIntWrapper.new(Int32::MAX - 1)],
        (RangeSpecIntWrapper.new(Int32::MAX - 3)..RangeSpecIntWrapper.new(Int32::MAX - 1)).step(by: 2)
      it_iterates "at definition range missing by",
        [RangeSpecIntWrapper.new(Int32::MAX - 2)],
        (RangeSpecIntWrapper.new(Int32::MAX - 2)..RangeSpecIntWrapper.new(Int32::MAX - 1)).step(by: 2)
    end
  end

  describe "map" do
    it "optimizes for int range" do
      (5..12).map(&.itself).should eq([5, 6, 7, 8, 9, 10, 11, 12])
      (5...12).map(&.itself).should eq([5, 6, 7, 8, 9, 10, 11])
      (5..4).map(&.itself).size.should eq(0)
    end

    it "works for other types" do
      ('a'..'c').map(&.itself).should eq(['a', 'b', 'c'])
    end
  end

  describe "#size" do
    it "optimizes for int range" do
      (5..12).size.should eq(8)
      (5...12).size.should eq(7)
      (5..4).size.should eq(0)
    end

    it "works for other types" do
      ('a'..'c').size.should eq(3)
    end

    it "raises on beginless range" do
      expect_raises(ArgumentError, "Can't calculate size of an open range") do
        (..3).size
      end
      expect_raises(ArgumentError, "Can't calculate size of an open range") do
        (nil.as(Int32?)..3).size
      end
    end

    it "raises on endless range" do
      expect_raises(ArgumentError, "Can't calculate size of an open range") do
        (3..).size
      end
      expect_raises(ArgumentError, "Can't calculate size of an open range") do
        (3..nil.as(Int32?)).size
      end
    end
  end

  it "clones" do
    range = [1]..[2]
    clone = range.clone
    clone.should eq(range)
    clone.begin.should_not be(range.begin)
    clone.end.should_not be(range.end)
  end

  describe "===" do
    it "inclusive" do
      ((1..2) === 0).should be_false
      ((1..2) === 1).should be_true
      ((1..2) === 2).should be_true
      ((1..2) === 3).should be_false
    end

    it "exclusive" do
      ((1...2) === 0).should be_false
      ((1...2) === 1).should be_true
      ((1...2) === 2).should be_false
    end

    it "endless" do
      ((1...nil) === 0).should be_false
      ((1...nil) === 1).should be_true
      ((1...nil) === 2).should be_true
      ((1..nil) === 2).should be_true
    end

    it "beginless" do
      ((nil..3) === -1).should be_true
      ((nil..3) === 3).should be_true
      ((nil..3) === 4).should be_false
      ((nil...3) === 2).should be_true
      ((nil...3) === 3).should be_false
    end

    it "no limits" do
      ((nil..nil) === 1).should be_true
    end
  end
end
