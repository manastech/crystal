require "spec"
require "spec/helpers/iterate"

private alias RecursiveArray = Array(RecursiveArray)

private class Spaceship
  getter value : Float64

  def initialize(@value : Float64, @return_nil = false)
  end

  def <=>(other : Spaceship)
    return nil if @return_nil

    value <=> other.value
  end
end

private def is_stable_sort(*, mutable, &block)
  n = 42
  # [Spaceship.new(0), ..., Spaceship.new(n - 1), Spaceship.new(0), ..., Spaceship.new(n - 1)]
  arr = Array.new(n * 2) { |i| Spaceship.new((i % n).to_f) }
  # [Spaceship.new(0), Spaceship.new(0), ..., Spaceship.new(n - 1), Spaceship.new(n - 1)]
  expected = Array.new(n * 2) { |i| arr[i % 2 * n + i // 2] }

  if mutable
    yield arr
    result = arr
  else
    result = yield arr
    result.should_not eq(arr)
  end

  result.size.should eq(expected.size)
  expected.zip(result) do |exp, res|
    res.should be(exp) # reference-equality is necessary to check sorting is stable.
  end
end

describe "Array" do
  describe "new" do
    it "creates with default value" do
      ary = Array.new(5, 3)
      ary.should eq([3, 3, 3, 3, 3])
    end

    it "creates with default value in block" do
      ary = Array.new(5) { |i| i * 2 }
      ary.should eq([0, 2, 4, 6, 8])

      ary = Array.new(5_u32) { |i| i * 2 }
      ary.should eq([0, 2, 4, 6, 8])
    end

    it "raises on negative count" do
      expect_raises(ArgumentError, "Negative array size") do
        Array.new(-1, 3)
      end
    end

    it "raises on negative capacity" do
      expect_raises(ArgumentError, "Negative array size") do
        Array(Int32).new(-1)
      end
    end
  end

  describe "==" do
    it "compares empty" do
      ([] of Int32).should eq([] of Int32)
      [1].should_not eq([] of Int32)
      ([] of Int32).should_not eq([1])
    end

    it "compares elements" do
      [1, 2, 3].should eq([1, 2, 3])
      [1, 2, 3].should_not eq([3, 2, 1])
    end

    it "compares other" do
      a = [1, 2, 3]
      b = [1, 2, 3]
      c = [1, 2, 3, 4]
      d = [1, 2, 4]
      (a == b).should be_true
      (b == c).should be_false
      (a == d).should be_false
    end
  end

  describe "&" do
    it "small arrays" do
      ([1, 2, 3] & [] of Int32).should eq([] of Int32)
      ([] of Int32 & [1, 2, 3]).should eq([] of Int32)
      ([1, 2, 3] & [3, 2, 4]).should eq([2, 3])
      ([1, 2, 3, 1, 2, 3] & [3, 2, 4, 3, 2, 4]).should eq([2, 3])
      ([1, 2, 3, 1, 2, 3, nil, nil] & [3, 2, 4, 3, 2, 4, nil]).should eq([2, 3, nil])
    end

    it "big arrays" do
      a1 = (1..64).to_a
      a2 = (33..96).to_a
      (a1 & a2).should eq((33..64).to_a)
    end
  end

  describe "|" do
    it "small arrays" do
      ([1, 2, 3, 2, 3] | ([] of Int32)).should eq([1, 2, 3])
      (([] of Int32) | [1, 2, 3, 2, 3]).should eq([1, 2, 3])
      ([1, 2, 3] | [5, 3, 2, 4]).should eq([1, 2, 3, 5, 4])
      ([1, 1, 2, 3, 3] | [4, 5, 5, 6]).should eq([1, 2, 3, 4, 5, 6])
    end

    it "large arrays" do
      a = [1, 2, 3] * 10
      b = [4, 5, 6] * 10
      (a | b).should eq([1, 2, 3, 4, 5, 6])
    end
  end

  it "does +" do
    a = [1, 2, 3]
    b = [4, 5]
    c = a + b
    c.size.should eq(5)
    0.upto(4) { |i| c[i].should eq(i + 1) }
  end

  it "does + with empty tuple converted to array (#909)" do
    ([1, 2] + Tuple.new.to_a).should eq([1, 2])
    (Tuple.new.to_a + [1, 2]).should eq([1, 2])
  end

  describe "-" do
    it "does it" do
      ([1, 2, 3, 4, 5] - [4, 2]).should eq([1, 3, 5])
    end

    it "does with larger array coming second" do
      ([4, 2] - [1, 2, 3]).should eq([4])
    end

    it "does with even larger arrays" do
      ((1..64).to_a - (1..32).to_a).should eq((33..64).to_a)
    end

    context "with different types" do
      it "small array" do
        ([1, 2, 3, 'c'] - [2, nil]).should eq [1, 3, 'c']
      end

      it "big array" do
        (((1..64).to_a + ['c']) - ((2..63).to_a + [nil])).should eq [1, 64, 'c']
      end
    end
  end

  it "does *" do
    (([] of Int32) * 10).should be_empty
    ([1, 2, 3] * 0).should be_empty
    ([1] * 3).should eq([1, 1, 1])
    ([1, 2, 3] * 3).should eq([1, 2, 3, 1, 2, 3, 1, 2, 3])
    ([1, 2] * 10).should eq([1, 2, 1, 2, 1, 2, 1, 2, 1, 2, 1, 2, 1, 2, 1, 2, 1, 2, 1, 2])
  end

  describe "[]" do
    it "gets on positive index" do
      [1, 2, 3][1].should eq(2)
    end

    it "gets on negative index" do
      [1, 2, 3][-1].should eq(3)
    end

    it "gets on inclusive range" do
      [1, 2, 3, 4, 5, 6][1..4].should eq([2, 3, 4, 5])
    end

    it "gets on inclusive range with negative indices" do
      [1, 2, 3, 4, 5, 6][-5..-2].should eq([2, 3, 4, 5])
    end

    it "gets on exclusive range" do
      [1, 2, 3, 4, 5, 6][1...4].should eq([2, 3, 4])
    end

    it "gets on exclusive range with negative indices" do
      [1, 2, 3, 4, 5, 6][-5...-2].should eq([2, 3, 4])
    end

    it "gets on range with start higher than end" do
      [1, 2, 3][2..1].should eq([] of Int32)
      [1, 2, 3][3..1].should eq([] of Int32)
      expect_raises IndexError do
        [1, 2, 3][4..1]
      end
    end

    it "gets on range with start higher than negative end" do
      [1, 2, 3][1..-1].should eq([2, 3] of Int32)
      [1, 2, 3][2..-2].should eq([] of Int32)
    end

    it "gets on range without end" do
      [1, 2, 3][1..nil].should eq([2, 3])
    end

    it "gets on range without begin" do
      [1, 2, 3][nil..1].should eq([1, 2])
    end

    it "raises on index out of bounds with range" do
      expect_raises IndexError do
        [1, 2, 3][4..6]
      end
    end

    it "raises on index out of bounds with range without end" do
      expect_raises IndexError do
        [1, 2, 3][4..nil]
      end
    end

    it "gets with start and count" do
      [1, 2, 3, 4, 5, 6][1, 3].should eq([2, 3, 4])
    end

    it "gets with start and count exceeding size" do
      [1, 2, 3][1, 3].should eq([2, 3])
    end

    it "gets with negative start" do
      [1, 2, 3, 4, 5, 6][-4, 2].should eq([3, 4])
    end

    it "raises on index out of bounds with start and count" do
      expect_raises IndexError do
        [1, 2, 3][4, 0]
      end
    end

    it "raises on negative count" do
      expect_raises ArgumentError do
        [1, 2, 3][3, -1]
      end
    end

    it "raises on index out of bounds" do
      expect_raises IndexError do
        [1, 2, 3][-4, 2]
      end
    end

    it "raises on negative count" do
      expect_raises ArgumentError, /Negative count: -1/ do
        [1, 2, 3][1, -1]
      end
    end

    it "raises on negative count on empty Array" do
      expect_raises ArgumentError, /Negative count: -1/ do
        Array(Int32).new[0, -1]
      end
    end

    it "gets 0, 0 on empty array" do
      a = [] of Int32
      a[0, 0].should eq(a)
    end

    it "gets 0 ... 0 on empty array" do
      a = [] of Int32
      a[0..0].should eq(a)
    end

    it "doesn't exceed limits" do
      [1][0..3].should eq([1])
    end

    it "returns empty if at end" do
      [1][1, 0].should eq([] of Int32)
      [1][1, 10].should eq([] of Int32)
    end

    it "raises on too negative left bound" do
      expect_raises IndexError do
        [1, 2, 3][-4..0]
      end
    end
  end

  describe "[]?" do
    it "gets with index" do
      [1, 2, 3][2]?.should eq(3)
      [1, 2, 3][3]?.should be_nil
    end

    it "gets with range" do
      [1, 2, 3][1..2]?.should eq([2, 3])
      [1, 2, 3][4..-1]?.should be_nil
    end

    it "gets with start and count" do
      [1, 2, 3][1, 3]?.should eq([2, 3])
      [1, 2, 3][4, 0]?.should be_nil
    end

    it "gets with range without end" do
      [1, 2, 3][1..nil]?.should eq([2, 3])
      [1, 2, 3][4..nil]?.should be_nil
    end

    it "gets with range without beginning" do
      [1, 2, 3][nil..1]?.should eq([1, 2])
    end
  end

  describe "[]=" do
    it "sets on positive index" do
      a = [1, 2, 3]
      a[1] = 4
      a[1].should eq(4)
    end

    it "sets on negative index" do
      a = [1, 2, 3]
      a[-1] = 4
      a[2].should eq(4)
    end

    it "replaces a subrange with a single value" do
      a = [1, 2, 3, 4, 5]
      a[1, 3] = 6
      a.should eq([1, 6, 5])

      a = [1, 2, 3, 4, 5]
      a[1, 1] = 6
      a.should eq([1, 6, 3, 4, 5])

      a = [1, 2, 3, 4, 5]
      a[1, 0] = 6
      a.should eq([1, 6, 2, 3, 4, 5])

      a = [1, 2, 3, 4, 5]
      a[1, 10] = 6
      a.should eq([1, 6])

      a = [1, 2, 3, 4, 5]
      a[-3, 2] = 6
      a.should eq([1, 2, 6, 5])

      a = [1, 2, 3, 4, 5, 6, 7, 8]
      a[1, 3] = 6
      a.should eq([1, 6, 5, 6, 7, 8])

      expect_raises ArgumentError, "Negative count" do
        [1, 2, 3][0, -1]
      end

      a = [1, 2, 3, 4, 5]
      a[1..3] = 6
      a.should eq([1, 6, 5])

      a = [1, 2, 3, 4, 5]
      a[2..3] = 6
      a.should eq([1, 2, 6, 5])

      a = [1, 2, 3, 4, 5]
      a[1...1] = 6
      a.should eq([1, 6, 2, 3, 4, 5])

      a = [1, 2, 3, 4, 5]
      a[2..nil] = 6
      a.should eq([1, 2, 6])

      a = [1, 2, 3, 4, 5]
      a[nil..2] = 6
      a.should eq([6, 4, 5])
    end

    it "replaces a subrange with an array" do
      a = [1, 2, 3, 4, 5]
      a[1, 3] = [6, 7, 8]
      a.should eq([1, 6, 7, 8, 5])

      a = [1, 2, 3, 4, 5]
      a[1, 3] = [6, 7]
      a.should eq([1, 6, 7, 5])

      a = [1, 2, 3, 4, 5, 6, 7, 8]
      a[1, 3] = [6, 7]
      a.should eq([1, 6, 7, 5, 6, 7, 8])

      a = [1, 2, 3, 4, 5]
      a[1, 3] = [6, 7, 8, 9, 10]
      a.should eq([1, 6, 7, 8, 9, 10, 5])

      a = [1, 2, 3, 4, 5]
      a[1, 2] = [6, 7, 8, 9, 10]
      a.should eq([1, 6, 7, 8, 9, 10, 4, 5])

      a = [1, 2, 3, 4, 5]
      a[1..3] = [6, 7, 8]
      a.should eq([1, 6, 7, 8, 5])

      a = [1, 2, 3, 4, 5]
      a[2..nil] = [6, 7]
      a.should eq([1, 2, 6, 7])

      a = [1, 2, 3, 4, 5]
      a[nil..2] = [6, 7]
      a.should eq([6, 7, 4, 5])
    end

    it "optimizes when index is 0" do
      a = [1, 2, 3, 4, 5, 6, 7, 8]
      buffer = a.@buffer
      a[0..2] = 10
      a.should eq([10, 4, 5, 6, 7, 8])
      a.@offset_to_buffer.should eq(2)
      a.@buffer.should eq(buffer + 2)
    end

    it "replaces entire range with a value for empty array (#8341)" do
      a = [] of Int32
      a[..] = 6
      a.should eq([6])
    end

    it "pushes a new value with []=(...)" do
      a = [1, 2, 3]
      a[3..] = 4
      a.should eq([1, 2, 3, 4])
    end

    it "replaces entire range with an array for empty array (#8341)" do
      a = [] of Int32
      a[..] = [1, 2, 3]
      a.should eq([1, 2, 3])
    end

    it "concats a new array with []=(...)" do
      a = [1, 2, 3]
      a[3..] = [4, 5, 6]
      a.should eq([1, 2, 3, 4, 5, 6])
    end

    it "reuses the buffer if possible" do
      a = [1, 2, 3, 4, 5]
      a.pop
      a[4, 0] = [6]
      a.should eq([1, 2, 3, 4, 6])
      a.@capacity.should eq(5)
      a.@offset_to_buffer.should eq(0)
    end

    it "resizes the buffer if capacity is not enough" do
      a = [1, 2, 3, 4, 5]
      a.shift
      a[4, 0] = [6, 7, 8, 9]
      a.should eq([2, 3, 4, 5, 6, 7, 8, 9])
      a.@capacity.should eq(10)
      a.@offset_to_buffer.should eq(1)
    end
  end

  describe "values_at" do
    it "returns the given indexes" do
      ["a", "b", "c", "d"].values_at(1, 0, 2).should eq({"b", "a", "c"})
    end

    it "raises when passed an invalid index" do
      expect_raises IndexError do
        ["a"].values_at(10)
      end
    end

    it "works with mixed types" do
      [1, "a", 1.0, 'a'].values_at(0, 1, 2, 3).should eq({1, "a", 1.0, 'a'})
    end
  end

  it "find the element by using binary search" do
    [2, 5, 7, 10].bsearch { |x| x >= 4 }.should eq 5
    [2, 5, 7, 10].bsearch { |x| x > 10 }.should be_nil
    [2, 5, 7, 10].bsearch { |x| x >= 4 ? 1 : nil }.should eq 5
  end

  it "find the index by using binary search" do
    [2, 5, 7, 10].bsearch_index { |x, i| x >= 4 }.should eq 1
    [2, 5, 7, 10].bsearch_index { |x, i| x > 10 }.should be_nil

    [2, 5, 7, 10].bsearch_index { |x, i| i >= 3 }.should eq 3
    [2, 5, 7, 10].bsearch_index { |x, i| i > 3 }.should be_nil
  end

  it "does clear" do
    a = [1, 2, 3]
    a.clear
    a.should eq([] of Int32)
  end

  it "does clone" do
    x = {1 => 2}
    a = [x]
    b = a.clone
    b.should eq(a)
    a.should_not be(b)
    a[0].should_not be(b[0])
  end

  it "does clone with recursive array" do
    ary = [] of RecursiveArray
    ary << ary
    clone = ary.clone
    clone[0].should be(clone)
  end

  it "does compact" do
    a = [1, nil, 2, nil, 3]
    b = a.compact.should eq([1, 2, 3])
    a.should eq([1, nil, 2, nil, 3])
  end

  it "does compact!" do
    a = [1, nil, 2, nil, 3]
    b = a.compact!
    b.should eq([1, 2, 3])
    b.should be(a)
  end

  describe "concat" do
    it "concats small arrays" do
      a = [1, 2, 3]
      a.concat([4, 5, 6])
      a.should eq([1, 2, 3, 4, 5, 6])
    end

    it "concats large arrays" do
      a = [1, 2, 3]
      a.concat((4..1000).to_a)
      a.should eq((1..1000).to_a)
    end

    it "concats enumerable" do
      a = [1, 2, 3]
      a.concat((4..1000))
      a.should eq((1..1000).to_a)
    end

    it "concats enumerable to empty array (#2047)" do
      a = [] of Int32
      a.concat(1..1)
      a.@capacity.should eq(3)

      a = [] of Int32
      a.concat(1..4)
      a.@capacity.should eq(6)
    end

    it "concats indexable" do
      a = [1, 2, 3]
      a.concat(Slice.new(97) { |i| i + 4 })
      a.should eq((1..100).to_a)

      a = [1, 2, 3]
      a.concat(StaticArray(Int32, 97).new { |i| i + 4 })
      a.should eq((1..100).to_a)

      a = [1, 2, 3]
      a.concat(Deque.new(97) { |i| i + 4 })
      a.should eq((1..100).to_a)
    end

    it "concats a union of arrays" do
      a = [1, '2']
      a.concat([3] || ['4'])
      a.should eq([1, '2', 3])
    end
  end

  describe "delete" do
    it "deletes many" do
      a = [1, 2, 3, 1, 2, 3]
      a.delete(2).should eq(2)
      a.should eq([1, 3, 1, 3])
    end

    it "delete not found" do
      a = [1, 2]
      a.delete(4).should be_nil
      a.should eq([1, 2])
    end
  end

  describe "delete_at" do
    it "deletes positive index" do
      a = [1, 2, 3, 4]
      a.delete_at(1).should eq(2)
      a.should eq([1, 3, 4])
    end

    it "deletes at beginning is same as shift" do
      a = [1, 2, 3, 4]
      buffer = a.@buffer
      a.delete_at(0)
      a.should eq([2, 3, 4])
      a.@offset_to_buffer.should eq(1)
      a.@buffer.should eq(buffer + 1)
    end

    it "deletes use range" do
      a = [1, 2, 3]
      a.delete_at(1).should eq(2)
      a.should eq([1, 3])

      a = [1, 2, 3]
      a.delete_at(-1).should eq(3)
      a.should eq([1, 2])

      a = [1, 2, 3]
      a.delete_at(-2..-1).should eq([2, 3])
      a.should eq([1])

      a = [1, 2, 3]
      a.delete_at(1, 2).should eq([2, 3])
      a.should eq([1])

      a = [1, 2, 3]
      a.delete_at(1..5).should eq([2, 3])
      a.should eq([1])
      a.size.should eq(1)

      a = [1, 2, 3, 4, 5]
      a.delete_at(1..2)
      a.should eq([1, 4, 5])

      a = [1, 2, 3, 4, 5, 6, 7]
      a.delete_at(1..2)
      a.should eq([1, 4, 5, 6, 7])

      a = [1, 2, 3, 4, 5, 6, 7]
      a.delete_at(3..nil)
      a.should eq([1, 2, 3])
    end

    it "deletes with index and count" do
      a = [1, 2, 3, 4, 5]
      a.delete_at(1, 2)
      a.should eq([1, 4, 5])

      a = [1, 2, 3, 4, 5, 6, 7]
      a.delete_at(1, 2)
      a.should eq([1, 4, 5, 6, 7])
    end

    it "returns empty if at end" do
      a = [1]
      a.delete_at(1, 0).should eq([] of Int32)
      a.delete_at(1, 10).should eq([] of Int32)
      a.delete_at(1..0).should eq([] of Int32)
      a.delete_at(1..10).should eq([] of Int32)
      a.should eq([1])
    end

    it "deletes negative index" do
      a = [1, 2, 3, 4]
      a.delete_at(-3).should eq(2)
      a.should eq([1, 3, 4])
    end

    it "deletes negative index with range" do
      a = [1, 2, 3, 4, 5, 6]
      a.delete_at(-3, 2).should eq([4, 5])
      a.should eq([1, 2, 3, 6])
    end

    it "deletes negative index with range, out of bounds" do
      a = [1, 2, 3, 4, 5, 6]

      expect_raises IndexError do
        a.delete_at(-7, 2)
      end
    end

    it "deletes out of bounds" do
      expect_raises IndexError do
        [1].delete_at(2)
      end
      expect_raises IndexError do
        [1].delete_at(2, 1)
      end
      expect_raises IndexError do
        [1].delete_at(2..3)
      end
      expect_raises IndexError do
        [1].delete_at(-2..-1)
      end
    end
  end

  it "does dup" do
    x = {1 => 2}
    a = [x]
    b = a.dup
    b.should eq([x])
    a.should_not be(b)
    a[0].should be(b[0])
    b << {3 => 4}
    a.should eq([x])
  end

  it "does each_index" do
    a = [1, 1, 1]
    b = 0
    a.each_index { |i| b += i }.should be_nil
    b.should eq(3)
  end

  describe "empty" do
    it "is empty" do
      ([] of Int32).empty?.should be_true
    end

    it "is not empty" do
      [1].empty?.should be_false
    end
  end

  it "does equals? with custom block" do
    a = [1, 3, 2]
    b = [3, 9, 4]
    c = [5, 7, 3]
    d = [1, 3, 2, 4]
    f = ->(x : Int32, y : Int32) { (x % 2) == (y % 2) }
    a.equals?(b, &f).should be_true
    a.equals?(c, &f).should be_false
    a.equals?(d, &f).should be_false
  end

  describe "#fill" do
    it "replaces values in a subrange" do
      a = [0, 1, 2, 3, 4]
      a.fill(7).should be(a)
      a.should eq([7, 7, 7, 7, 7])

      a = [0, 1, 2, 3, 4]
      a.fill(7, 1, 2).should be(a)
      a.should eq([0, 7, 7, 3, 4])

      a = [0, 1, 2, 3, 4]
      a.fill(7, 2..3).should be(a)
      a.should eq([0, 1, 7, 7, 4])

      a = [0, 0, 0, 0, 0]
      a.fill { |i| i + 7 }.should be(a)
      a.should eq([7, 8, 9, 10, 11])

      a = [0, 0, 0, 0, 0]
      a.fill(offset: 2) { |i| i * i }.should be(a)
      a.should eq([4, 9, 16, 25, 36])

      a = [0, 0, 0, 0, 0]
      a.fill(1, 2) { |i| i + 7 }.should be(a)
      a.should eq([0, 8, 9, 0, 0])

      a = [0, 0, 0, 0, 0]
      a.fill(2..3) { |i| i + 7 }.should be(a)
      a.should eq([0, 0, 9, 10, 0])
    end
  end

  describe "first" do
    it "gets first when non empty" do
      a = [1, 2, 3]
      a.first.should eq(1)
    end

    it "raises when empty" do
      expect_raises Enumerable::EmptyError do
        ([] of Int32).first
      end
    end

    it "returns a sub array with given number of elements" do
      arr = [1, 2, 3]
      arr.first(0).should eq([] of Int32)
      arr.first(1).should eq [1]
      arr.first(2).should eq [1, 2]
      arr.first(3).should eq [1, 2, 3]
      arr.first(4).should eq [1, 2, 3]
    end
  end

  describe "first?" do
    it "gets first? when non empty" do
      a = [1, 2, 3]
      a.first?.should eq(1)
    end

    it "gives nil when empty" do
      ([] of Int32).first?.should be_nil
    end
  end

  it "does hash" do
    a = [1, 2, [3]]
    b = [1, 2, [3]]
    a.hash.should eq(b.hash)
  end

  describe "index" do
    it "performs without a block" do
      a = [1, 2, 3]
      a.index(3).should eq(2)
      a.index(4).should be_nil
    end

    it "performs without a block and offset" do
      a = [1, 2, 3, 1, 2, 3]
      a.index(3, offset: 3).should eq(5)
      a.index(3, offset: -3).should eq(5)
    end

    it "performs with a block" do
      a = [1, 2, 3]
      a.index { |i| i > 1 }.should eq(1)
      a.index { |i| i > 3 }.should be_nil
    end

    it "performs with a block and offset" do
      a = [1, 2, 3, 1, 2, 3]
      a.index(offset: 3) { |i| i > 1 }.should eq(4)
      a.index(offset: -3) { |i| i > 1 }.should eq(4)
    end

    it "raises if out of bounds" do
      expect_raises IndexError do
        [1, 2, 3][4]
      end
    end
  end

  describe "insert" do
    it "inserts with positive index" do
      a = [1, 3, 4]
      expected = [1, 2, 3, 4]
      a.insert(1, 2).should eq(expected)
      a.should eq(expected)
    end

    it "inserts with negative index" do
      a = [1, 2, 3]
      expected = [1, 2, 3, 4]
      a.insert(-1, 4).should eq(expected)
      a.should eq(expected)
    end

    it "inserts with negative index (2)" do
      a = [1, 2, 3]
      expected = [4, 1, 2, 3]
      a.insert(-4, 4).should eq(expected)
      a.should eq(expected)
    end

    it "inserts out of range" do
      a = [1, 3, 4]

      expect_raises IndexError do
        a.insert(4, 1)
      end
    end
  end

  describe "insert_all" do
    it "inserts with index 0" do
      a = [2, 3]
      a.insert_all(0, [0, 1]).should be a
      a.should eq([0, 1, 2, 3])
    end

    it "inserts with positive index" do
      a = [1, 2, 5, 6]
      a.insert_all(2, [3, 4]).should be a
      a.should eq([1, 2, 3, 4, 5, 6])
    end

    it "inserts with index of #size" do
      a = [1, 2, 3]
      a.insert_all(a.size, [4, 5]).should be a
      a.should eq([1, 2, 3, 4, 5])
    end

    it "inserts with negative index" do
      a = [1, 2, 3]
      a.insert_all(-1, [4, 5]).should be a
      a.should eq([1, 2, 3, 4, 5])
    end

    it "inserts with negative index (2)" do
      a = [1, 2, 5, 6]
      a.insert_all(-3, [3, 4]).should be a
      a.should eq([1, 2, 3, 4, 5, 6])
    end

    it "inserts when empty" do
      a = [] of Int32
      a.insert_all(0, [1, 2, 3]).should be a
      a.should eq([1, 2, 3])
    end

    it "inserts when other is empty" do
      a = [1, 2, 3]
      a.insert_all(1, [] of Int32).should be a
      a.should eq([1, 2, 3])
    end

    it "raises with index greater than size" do
      a = [1, 2, 3]
      expect_raises IndexError do
        a.insert_all(4, [4, 5])
      end
    end

    it "raises with negative index greater than size" do
      a = [1, 2, 3]
      expect_raises IndexError do
        a.insert_all(-5, [4, 5])
      end
    end

    it "inserts indexable" do
      a = [1, 9, 10]
      a.insert_all(1, Slice.new(3, 8)).should be a
      a.should eq([1, 8, 8, 8, 9, 10])

      a.insert_all(-6, StaticArray(Int32, 3).new { |i| i + 2 }).should be a
      a.should eq([1, 2, 3, 4, 8, 8, 8, 9, 10])

      a.insert_all(4, Deque{5, 6, 7}).should be a
      a.should eq([1, 2, 3, 4, 5, 6, 7, 8, 8, 8, 9, 10])
    end
  end

  describe "inspect" do
    it { [1, 2, 3].inspect.should eq("[1, 2, 3]") }
  end

  describe "last" do
    it "gets last when non empty" do
      a = [1, 2, 3]
      a.last.should eq(3)
    end

    it "raises when empty" do
      expect_raises IndexError do
        ([] of Int32).last
      end
    end

    it "returns a sub array with given number of elements" do
      arr = [1, 2, 3]
      arr.last(0).should eq([] of Int32)
      arr.last(1).should eq [3]
      arr.last(2).should eq [2, 3]
      arr.last(3).should eq [1, 2, 3]
      arr.last(4).should eq [1, 2, 3]
    end
  end

  describe "size" do
    it "has size 0" do
      ([] of Int32).size.should eq(0)
    end

    it "has size 2" do
      [1, 2].size.should eq(2)
    end
  end

  it "does map" do
    a = [1, 2, 3]
    a.map { |x| x * 2 }.should eq([2, 4, 6])
    a.should eq([1, 2, 3])
  end

  it "does map!" do
    a = [1, 2, 3]
    a.map! { |x| x * 2 }
    a.should eq([2, 4, 6])
  end

  describe "pop" do
    it "pops when non empty" do
      a = [1, 2, 3]
      a.pop.should eq(3)
      a.should eq([1, 2])
    end

    it "raises when empty" do
      expect_raises IndexError do
        ([] of Int32).pop
      end
    end

    it "pops many elements" do
      a = [1, 2, 3, 4, 5]
      b = a.pop(3)
      b.should eq([3, 4, 5])
      a.should eq([1, 2])
    end

    it "pops more elements that what is available" do
      a = [1, 2, 3, 4, 5]
      b = a.pop(10)
      b.should eq([1, 2, 3, 4, 5])
      a.should eq([] of Int32)
    end

    it "pops negative count raises" do
      a = [1, 2]
      expect_raises ArgumentError do
        a.pop(-1)
      end
    end
  end

  it "does product with block" do
    r = [] of Int32
    [1, 2, 3].product([5, 6]) { |a, b| r << a; r << b }
    r.should eq([1, 5, 1, 6, 2, 5, 2, 6, 3, 5, 3, 6])
  end

  it "does product without block" do
    [1, 2, 3].product(['a', 'b']).should eq([{1, 'a'}, {1, 'b'}, {2, 'a'}, {2, 'b'}, {3, 'a'}, {3, 'b'}])
  end

  describe "push" do
    it "pushes one element" do
      a = [1, 2]
      a.push(3).should be(a)
      a.should eq [1, 2, 3]
    end

    it "pushes multiple elements" do
      a = [1, 2]
      a.push(3, 4).should be(a)
      a.should eq [1, 2, 3, 4]
    end

    it "pushes multiple elements to an empty array" do
      a = [] of Int32
      a.push(1, 2, 3).should be(a)
      a.should eq([1, 2, 3])
    end

    it "has the << alias" do
      a = [1, 2]
      a << 3
      a.should eq [1, 2, 3]
    end
  end

  describe "#replace" do
    it "replaces all elements" do
      a = [1, 2, 3]
      b = [4, 5, 6]
      a.replace(b).should be(a)
      a.should eq(b)
    end

    it "reuses the buffer if possible" do
      a = [1, 2, 3, 4, 5]
      a.shift
      b = [6, 7, 8, 9, 10]
      a.replace(b).should be(a)
      a.should eq(b)
      a.@capacity.should eq(5)
      a.@offset_to_buffer.should eq(0)

      a = [1, 2, 3, 4, 5]
      a.shift(2)
      b = [6, 7, 8, 9]
      a.replace(b).should be(a)
      a.should eq(b)
      a.@capacity.should eq(5)
      a.@offset_to_buffer.should eq(1)
    end

    it "resizes the buffer if capacity is not enough" do
      a = [1, 2, 3, 4, 5]
      b = [6, 7, 8, 9, 10, 11]
      a.replace(b).should be(a)
      a.should eq(b)
      a.@capacity.should eq(10)
      a.@offset_to_buffer.should eq(0)
    end

    it "clears unused elements if new size is smaller" do
      a = [1, 2, 3, 4, 5]
      b = [6, 7, 8]
      a.replace(b).should be(a)
      a.should eq(b)
      a.@capacity.should eq(5)
      a.@offset_to_buffer.should eq(0)
      a.unsafe_fetch(3).should eq(0)
      a.unsafe_fetch(4).should eq(0)
    end
  end

  it "does reverse with an odd number of elements" do
    a = [1, 2, 3]
    a.reverse.should eq([3, 2, 1])
    a.should eq([1, 2, 3])
  end

  it "does reverse with an even number of elements" do
    a = [1, 2, 3, 4]
    a.reverse.should eq([4, 3, 2, 1])
    a.should eq([1, 2, 3, 4])
  end

  it "does reverse! with an odd number of elements" do
    a = [1, 2, 3, 4, 5]
    a.reverse!
    a.should eq([5, 4, 3, 2, 1])
  end

  it "does reverse! with an even number of elements" do
    a = [1, 2, 3, 4, 5, 6]
    a.reverse!
    a.should eq([6, 5, 4, 3, 2, 1])
  end

  describe "rindex" do
    it "performs without a block" do
      a = [1, 2, 3, 4, 5, 3, 6]
      a.rindex(3).should eq(5)
      a.rindex(7).should be_nil
    end

    it "performs without a block and an offset" do
      a = [1, 2, 3, 4, 5, 3, 6]
      a.rindex(3, offset: 4).should eq(2)
      a.rindex(6, offset: 4).should be_nil
      a.rindex(3, offset: -2).should eq(5)
      a.rindex(3, offset: -3).should eq(2)
      a.rindex(3, offset: -100).should be_nil
    end

    it "performs with a block" do
      a = [1, 2, 3, 4, 5, 3, 6]
      a.rindex { |i| i > 1 }.should eq(6)
      a.rindex { |i| i > 6 }.should be_nil
    end

    it "performs with a block and offset" do
      a = [1, 2, 3, 4, 5, 3, 6]
      a.rindex { |i| i > 1 }.should eq(6)
      a.rindex { |i| i > 6 }.should be_nil
      a.rindex(offset: 4) { |i| i == 3 }.should eq(2)
      a.rindex(offset: -3) { |i| i == 3 }.should eq(2)
    end
  end

  describe "shift" do
    it "shifts when non empty" do
      a = [1, 2, 3]
      a.shift.should eq(1)
      a.should eq([2, 3])
    end

    it "raises when empty" do
      expect_raises IndexError do
        ([] of Int32).shift
      end
    end

    it "shifts many elements" do
      a = [1, 2, 3, 4, 5]
      b = a.shift(3)
      b.should eq([1, 2, 3])
      a.should eq([4, 5])
    end

    it "shifts more than what is available" do
      a = [1, 2, 3, 4, 5]
      b = a.shift(10)
      b.should eq([1, 2, 3, 4, 5])
      a.should eq([] of Int32)
    end

    it "shifts negative count raises" do
      a = [1, 2]
      expect_raises ArgumentError do
        a.shift(-1)
      end
    end

    it "shifts one and resizes" do
      a = [1, 2, 3, 4]
      old_capacity = a.@capacity
      a.shift.should eq(1)
      a.@offset_to_buffer.should eq(1)
      a << 5
      a.@capacity.should eq(old_capacity * 2)
      a.@offset_to_buffer.should eq(1)
      a.size.should eq(4)
      a.should eq([2, 3, 4, 5])
    end

    it "shifts almost all and then avoid resize" do
      a = [1, 2, 3, 4]
      old_capacity = a.@capacity
      (1..3).each do |i|
        a.shift.should eq(i)
      end
      a.@offset_to_buffer.should eq(3)
      a << 5
      a.@capacity.should eq(old_capacity)
      a.@offset_to_buffer.should eq(0)
      a.size.should eq(2)
      a.should eq([4, 5])
    end

    it "shifts and then concats Array" do
      size = 10_000
      a = (1..size).to_a
      (size - 1).times do
        a.shift
      end
      a.size.should eq(1)
      a.concat((1..size).to_a)
      a.size.should eq(size + 1)
      a.should eq([size] + (1..size).to_a)
    end

    it "shifts and then concats Enumerable" do
      size = 10_000
      a = (1..size).to_a
      (size - 1).times do
        a.shift
      end
      a.size.should eq(1)
      a.concat((1..size))
      a.size.should eq(size + 1)
      a.should eq([size] + (1..size).to_a)
    end

    it "shifts all" do
      a = [1, 2, 3, 4]
      buffer = a.@buffer
      4.times do
        a.shift
      end
      a.size.should eq(0)
      a.@offset_to_buffer.should eq(0)
      a.@buffer.should eq(buffer)
    end

    it "shifts all after pop" do
      a = [1, 2, 3, 4]
      buffer = a.@buffer
      a.pop
      3.times do
        a.shift
      end
      a.size.should eq(0)
      a.@offset_to_buffer.should eq(0)
      a.@buffer.should eq(buffer)
    end

    it "pops after shift" do
      a = [1, 2, 3, 4]
      buffer = a.@buffer
      3.times do
        a.shift
      end
      a.pop
      a.size.should eq(0)
      a.@offset_to_buffer.should eq(0)
      a.@buffer.should eq(buffer)
    end

    it "shifts all with shift(n)" do
      a = [1, 2, 3, 4]
      buffer = a.@buffer
      a.shift
      a.shift(3)
      a.size.should eq(0)
      a.@offset_to_buffer.should eq(0)
      a.@buffer.should eq(buffer)
    end
  end

  describe "shuffle" do
    it "shuffle!" do
      a = [1, 2, 3]
      a.shuffle!
      b = [1, 2, 3]
      3.times { a.should contain(b.shift) }
    end

    it "shuffle" do
      a = [1, 2, 3]
      b = a.shuffle
      a.should_not be(b)
      a.should eq([1, 2, 3])

      3.times { b.should contain(a.shift) }
    end

    it "shuffle! with random" do
      a = [1, 2, 3]
      a.shuffle!(Random.new(1))
      a.should eq([1, 3, 2])
    end

    it "shuffle with random" do
      a = [1, 2, 3]
      b = a.shuffle(Random.new(1))
      b.should eq([1, 3, 2])
    end
  end

  describe "sort" do
    {% for sort in ["sort".id, "unstable_sort".id] %}
      describe {{ "##{sort}" }} do
        it "without block" do
          a = [3, 4, 1, 2, 5, 6]
          b = a.{{ sort }}
          b.should eq([1, 2, 3, 4, 5, 6])
          a.should_not eq(b)
        end

        it "with a block" do
          a = ["foo", "a", "hello"]
          b = a.{{ sort }} { |x, y| x.size <=> y.size }
          b.should eq(["a", "foo", "hello"])
          a.should_not eq(b)
        end

        {% if sort == "sort" %}
          it "stable sort without a block" do
            is_stable_sort(mutable: false, &.sort)
          end

          it "stable sort with a block" do
            is_stable_sort(mutable: false, &.sort { |a, b| a.value <=> b.value })
          end
        {% end %}
      end

      describe {{ "##{sort}!" }} do
        it "without block" do
          a = [3, 4, 1, 2, 5, 6]
          a.{{ sort.id }}!
          a.should eq([1, 2, 3, 4, 5, 6])
        end

        it "with a block" do
          a = ["foo", "a", "hello"]
          a.{{ sort.id }}! { |x, y| x.size <=> y.size }
          a.should eq(["a", "foo", "hello"])
        end

        {% if sort == "sort" %}
          it "stable sort without a block" do
            is_stable_sort(mutable: true, &.sort!)
          end

          it "stable sort with a block" do
            is_stable_sort(mutable: true, &.sort! { |a, b| a.value <=> b.value })
          end
        {% end %}
      end

      describe {{ "##{sort}_by" }} do
        it "sorts" do
          a = ["foo", "a", "hello"]
          b = a.{{ sort }}_by(&.size)
          b.should eq(["a", "foo", "hello"])
          a.should_not eq(b)
        end

        it "unpacks tuple" do
          a = [{"d", 4}, {"a", 1}, {"c", 3}, {"e", 5}, {"b", 2}]
          b = a.{{ sort }}_by { |x, y| y }
          b.should eq([{"a", 1}, {"b", 2}, {"c", 3}, {"d", 4}, {"e", 5}])
          a.should_not eq(b)
        end

        {% if sort == "sort" %}
          it "stable sort" do
            is_stable_sort(mutable: false, &.sort_by(&.value))
          end
        {% end %}
      end

      describe {{ "##{sort}_by!" }} do
        it "sorts" do
          a = ["foo", "a", "hello"]
          a.{{ sort }}_by!(&.size)
          a.should eq(["a", "foo", "hello"])
        end

        it "calls given block exactly once for each element" do
          calls = Hash(String, Int32).new(0)
          a = ["foo", "a", "hello"]
          a.{{ sort }}_by! { |e| calls[e] += 1; e.size }
          calls.should eq({"foo" => 1, "a" => 1, "hello" => 1})
        end

        {% if sort == "sort" %}
          it "stable sort" do
            is_stable_sort(mutable: true, &.sort_by!(&.value))
          end
        {% end %}
      end
    {% end %}
  end

  describe "swap" do
    it "swaps" do
      a = [1, 2, 3]
      a.swap(0, 2)
      a.should eq([3, 2, 1])
    end

    it "swaps with negative indices" do
      a = [1, 2, 3]
      a.swap(-3, -1)
      a.should eq([3, 2, 1])
    end

    it "swaps but raises out of bounds on left" do
      a = [1, 2, 3]
      expect_raises IndexError do
        a.swap(3, 0)
      end
    end

    it "swaps but raises out of bounds on right" do
      a = [1, 2, 3]
      expect_raises IndexError do
        a.swap(0, 3)
      end
    end
  end

  describe "to_s" do
    it "does to_s" do
      [1, 2, 3].to_s.should eq("[1, 2, 3]")
    end

    it "does with recursive" do
      ary = [] of RecursiveArray
      ary << ary
      ary.to_s.should eq("[[...]]")
    end
  end

  describe "#truncate" do
    it "truncates with index and count" do
      a = [0, 1, 4, 9, 16, 25]
      a.truncate(2, 3).should be(a)
      a.should eq([4, 9, 16])
    end

    it "truncates with index and count == 0" do
      a = [0, 1, 4, 9, 16, 25]
      a.truncate(2, 0).should be(a)
      a.should be_empty
    end

    it "truncates with index and count, not enough elements" do
      a = [0, 1, 4, 9, 16, 25]
      a.truncate(4, 4).should be(a)
      a.should eq([16, 25])
    end

    it "truncates with index == size and count" do
      a = [0, 1, 4, 9, 16, 25]
      a.truncate(6, 1).should be(a)
      a.should be_empty
    end

    it "truncates with index < 0 and count" do
      a = [0, 1, 4, 9, 16, 25]
      a.truncate(-5, 3).should be(a)
      a.should eq([1, 4, 9])
    end

    it "raises on out of bound index" do
      a = [0, 1, 4, 9, 16, 25]
      expect_raises(IndexError) { a.truncate(-7, 1) }
    end

    it "raises on negative count" do
      a = [0, 1, 4, 9, 16, 25]
      expect_raises(ArgumentError) { a.truncate(0, -1) }
    end

    it "truncates with range" do
      a = [0, 1, 4, 9, 16, 25]
      a.truncate(2..4).should be(a)
      a.should eq([4, 9, 16])

      b = [0, 1, 4, 9, 16, 25]
      b.truncate(-5..-3).should be(b)
      b.should eq([1, 4, 9])
    end
  end

  describe "uniq" do
    it "uniqs without block" do
      a = [1, 2, 2, 3, 1, 4, 5, 3]
      b = a.uniq
      b.should eq([1, 2, 3, 4, 5])
      a.should_not be(b)
    end

    it "uniqs with block" do
      a = [-1, 1, 0, 2, -2]
      b = a.uniq &.abs
      b.should eq([-1, 0, 2])
      a.should_not be(b)
    end

    it "uniqs with true" do
      a = [1, 2, 3]
      b = a.uniq { true }
      b.should eq([1])
      a.should_not be(b)
    end

    it "uniqs large array" do
      a = (1..32).to_a
      (a * 4).uniq.should eq(a)
    end
  end

  describe "uniq!" do
    it "uniqs without block" do
      a = [1, 2, 2, 3, 1, 4, 5, 3]
      a.uniq!
      a.should eq([1, 2, 3, 4, 5])
    end

    it "uniqs with block" do
      a = [-1, 1, 0, 2, -2]
      a.uniq! &.abs
      a.should eq([-1, 0, 2])
    end

    it "uniqs with true" do
      a = [1, 2, 3]
      a.uniq! { true }
      a.should eq([1])
    end

    it "uniqs large array" do
      a = (1..32).to_a
      b = a * 2
      b.uniq!
      b.should eq(a)
    end
  end

  describe "unshift" do
    it "unshifts one element" do
      a = [1, 2]
      a.unshift(3).should be(a)
      a.should eq [3, 1, 2]
    end

    it "unshifts one elements three times" do
      a = [] of Int32
      3.times do |i|
        a.unshift(i)
      end
      a.should eq([2, 1, 0])
    end

    it "unshifts one element multiple times" do
      a = [1, 2]
      (3..100).each do |i|
        a.unshift(i)
      end
      a.should eq((3..100).to_a.reverse + [1, 2])
    end

    it "unshifts multiple elements" do
      a = [1, 2]
      a.unshift(3, 4).should be(a)
      a.should eq [3, 4, 1, 2]
    end

    it "unshifts multiple elements to an empty array" do
      a = [] of Int32
      a.unshift(1, 2, 3).should be(a)
      a.should eq([1, 2, 3])
    end

    it "unshifts after shift" do
      a = [1, 2, 3, 4]
      buffer = a.@buffer
      a.shift
      a.unshift(10)
      a.should eq([10, 2, 3, 4])
      a.@offset_to_buffer.should eq(0)
      a.@buffer.should eq(buffer)
    end

    it "unshifts many after many shifts" do
      a = [1, 2, 3, 4, 5, 6, 7, 8]
      buffer = a.@buffer
      3.times { a.shift }
      a.unshift(10, 20, 30)
      a.should eq([10, 20, 30, 4, 5, 6, 7, 8])
      a.@offset_to_buffer.should eq(0)
      a.@buffer.should eq(buffer)
    end

    it "repeated unshift/shift does not exhaust memory" do
      a = [] of Int32
      10.times do
        a.unshift(1)
        a.shift
      end
      a.@capacity.should eq(3)
    end

    it "repeated unshift/pop does not exhaust memory (#10748)" do
      a = [] of Int32
      10.times do
        a.unshift(1)
        a.pop
      end
      a.@capacity.should eq(3)
    end

    it "repeated unshift/clear does not exhaust memory" do
      a = [] of Int32
      10.times do
        a.unshift(1)
        a.clear
      end
      a.@capacity.should eq(3)
    end

    it "unshift of large array does not corrupt elements" do
      a = Array.new(300, &.itself)
      a.@capacity.should eq(300)
      a.unshift 1
      a.@capacity.should be > 300
      a[-1].should eq(299)
    end
  end

  it "does update" do
    a = [1, 2, 3]
    a.update(1) { |x| x * 2 }
    a.should eq([1, 4, 3])
  end

  it "does <=>" do
    a = [1, 2, 3]
    b = [4, 5, 6]
    c = [1, 2]

    (a <=> b).should be < 0
    (a <=> c).should be > 0
    (b <=> c).should be > 0
    (b <=> a).should be > 0
    (c <=> a).should be < 0
    (c <=> b).should be < 0
    (a <=> a).should eq(0)

    ([8] <=> [1, 2, 3]).should be > 0
    ([8] <=> [8, 1, 2]).should be < 0

    [[1, 2, 3], [4, 5], [8], [1, 2, 3, 4]].sort.should eq([[1, 2, 3], [1, 2, 3, 4], [4, 5], [8]])
  end

  it "does each while modifying array" do
    a = [1, 2, 3]
    count = 0
    a.each do
      count += 1
      a.clear
    end.should be_nil
    count.should eq(1)
  end

  it "does each index while modifying array" do
    a = [1, 2, 3]
    count = 0
    a.each_index do
      count += 1
      a.clear
    end.should be_nil
    count.should eq(1)
  end

  describe "zip" do
    describe "when a block is provided" do
      it "yields pairs of self's elements and passed array" do
        a, b, r = [1, 2, 3], [4, 5, 6], ""
        a.zip(b) { |x, y| r += "#{x}:#{y}," }
        r.should eq("1:4,2:5,3:6,")
      end

      it "works with iterable" do
        a = [1, 2, 3]
        b = ('a'..'c')
        r = [] of {Int32, Char}
        a.zip(b) do |x, y|
          r << {x, y}
        end
        r.should eq([{1, 'a'}, {2, 'b'}, {3, 'c'}])
      end

      it "works with iterator" do
        a = [1, 2, 3]
        b = ('a'..'c').each
        r = [] of {Int32, Char}
        a.zip(b) do |x, y|
          r << {x, y}
        end
        r.should eq([{1, 'a'}, {2, 'b'}, {3, 'c'}])
      end
    end

    describe "when no block is provided" do
      describe "and the arrays have different typed elements" do
        it "returns an array of paired elements (tuples)" do
          a, b = [1, 2, 3], ["a", "b", "c"]
          r = a.zip(b)
          r.should be_a(Array({Int32, String}))
          r.should eq([{1, "a"}, {2, "b"}, {3, "c"}])
        end

        it "works with iterable" do
          a = [1, 2, 3]
          b = ('a'..'c')
          r = a.zip(b)
          r.should be_a(Array({Int32, Char}))
          r.should eq([{1, 'a'}, {2, 'b'}, {3, 'c'}])
        end

        it "works with iterator" do
          a = [1, 2, 3]
          b = ('a'..'c').each
          r = a.zip(b)
          r.should be_a(Array({Int32, Char}))
          r.should eq([{1, 'a'}, {2, 'b'}, {3, 'c'}])
        end

        it "zips three things" do
          a = [1, 2, 3]
          b = 'a'..'c'
          c = ('x'..'z').each
          r = a.zip(b, c)
          r.should be_a(Array({Int32, Char, Char}))
          r.should eq([{1, 'a', 'x'}, {2, 'b', 'y'}, {3, 'c', 'z'}])
        end

        it "zips union type (#8608)" do
          a = [1, 2, 3]
          b = 'a'..'c'
          c = ('x'..'z').each
          r = a.zip(a || b || c)
          r.should be_a(Array({Int32, Int32 | Char}))
          r.should eq([{1, 1}, {2, 2}, {3, 3}])
        end
      end
    end
  end

  describe "zip?" do
    describe "when a block is provided" do
      describe "and size of an arg is less than receiver" do
        it "yields pairs of self's elements and passed array (with nil)" do
          a, b, r = [1, 2, 3], [4, 5], ""
          a.zip?(b) { |x, y| r += "#{x}:#{y}," }
          r.should eq("1:4,2:5,3:,")
        end

        it "works with iterable" do
          a = [1, 2, 3]
          b = ('a'..'b')
          r = [] of {Int32, Char?}
          a.zip?(b) do |x, y|
            r << {x, y}
          end
          r.should eq([{1, 'a'}, {2, 'b'}, {3, nil}])
        end

        it "works with iterator" do
          a = [1, 2, 3]
          b = ('a'..'b').each
          r = [] of {Int32, Char?}
          a.zip?(b) do |x, y|
            r << {x, y}
          end
          r.should eq([{1, 'a'}, {2, 'b'}, {3, nil}])
        end
      end
    end

    describe "when no block is provided" do
      describe "and the arrays have different typed elements" do
        describe "and size of an arg is less than receiver" do
          it "returns an array of paired elements (tuples with nil)" do
            a, b = [1, 2, 3], ["a", "b"]
            r = a.zip?(b)
            r.should eq([{1, "a"}, {2, "b"}, {3, nil}])
          end

          it "works with iterable" do
            a = [1, 2, 3]
            b = ('a'..'b')
            r = a.zip?(b)
            r.should be_a(Array({Int32, Char?}))
            r.should eq([{1, 'a'}, {2, 'b'}, {3, nil}])
          end

          it "works with iterator" do
            a = [1, 2, 3]
            b = ('a'..'b').each
            r = a.zip?(b)
            r.should be_a(Array({Int32, Char?}))
            r.should eq([{1, 'a'}, {2, 'b'}, {3, nil}])
          end

          it "zips three things" do
            a = [1, 2, 3]
            b = 'a'..'b'
            c = ('x'..'y').each
            r = a.zip?(b, c)
            r.should be_a(Array({Int32, Char?, Char?}))
            r.should eq([{1, 'a', 'x'}, {2, 'b', 'y'}, {3, nil, nil}])
          end

          it "zips union type (#8608)" do
            a = [1, 2, 3]
            b = 'a'..'c'
            c = ('x'..'z').each
            r = a.zip?(a || b || c)
            r.should be_a(Array({Int32, Int32 | Char | Nil}))
            r.should eq([{1, 1}, {2, 2}, {3, 3}])
          end
        end
      end
    end
  end

  it "does compact_map" do
    a = [1, 2, 3, 4, 5]
    b = a.compact_map { |e| e.divisible_by?(2) ? e : nil }
    b.size.should eq(2)
    b.should eq([2, 4])
  end

  it "does compact_map with false" do
    a = [1, 2, 3]
    b = a.compact_map do |e|
      case e
      when 1 then 1
      when 2 then nil
      else        false
      end
    end
    b.size.should eq(2)
    b.should eq([1, false])
  end

  it "builds from buffer" do
    ary = Array(Int32).build(4) do |buffer|
      buffer[0] = 1
      buffer[1] = 2
      2
    end
    ary.size.should eq(2)
    ary.should eq([1, 2])
  end

  it "selects!" do
    ary1 = [1, 2, 3, 4, 5]

    ary2 = ary1.select! { |elem| elem % 2 == 0 }
    ary2.should eq([2, 4])
    ary2.should be(ary1)
  end

  it "selects! with pattern" do
    ary1 = [1, 2, 3, 4, 5]

    ary2 = ary1.select!(2..4)
    ary2.should eq([2, 3, 4])
    ary2.should be(ary1)
  end

  it "rejects!" do
    ary1 = [1, 2, 3, 4, 5]

    ary2 = ary1.reject! { |elem| elem % 2 == 0 }
    ary2.should eq([1, 3, 5])
    ary2.should be(ary1)
  end

  it "rejects! with pattern" do
    ary1 = [1, 2, 3, 4, 5]

    ary2 = ary1.reject!(2..4)
    ary2.should eq([1, 5])
    ary2.should be(ary1)
  end

  it "does map_with_index" do
    ary = [1, 1, 2, 2]
    ary2 = ary.map_with_index { |e, i| e + i }
    ary2.should eq([1, 2, 4, 5])
  end

  it "does map_with_index, with offset" do
    ary = [1, 1, 2, 2]
    ary2 = ary.map_with_index(10) { |e, i| e + i }
    ary2.should eq([11, 12, 14, 15])
  end

  it "does map_with_index!" do
    ary = [0, 1, 2]
    ary2 = ary.map_with_index! { |e, i| i * 2 }
    ary.should eq([0, 2, 4])
    ary2.should be(ary)
  end

  it "does map_with_index!, with offset" do
    ary = [0, 1, 2]
    ary2 = ary.map_with_index!(10) { |e, i| i * 2 }
    ary.should eq([20, 22, 24])
    ary2.should be(ary)
  end

  it "does + with different types (#568)" do
    a = [1, 2, 3]
    a += ["hello"]
    a.should eq([1, 2, 3, "hello"])
  end

  it_iterates "#each", [1, 2, 3], [1, 2, 3].each
  it_iterates "#reverse_each", [3, 2, 1], [1, 2, 3].reverse_each

  it_iterates "#cycle", [1, 2, 3, 1, 2, 3, 1, 2], [1, 2, 3].cycle, infinite: true
  it_iterates "#cycle(limit)", [1, 2, 3, 1, 2, 3], [1, 2, 3].cycle(2), infinite: true

  it_iterates "#each_index", [0, 1, 2], [1, 2, 3].each_index

  describe "transpose" do
    it "transposes elements" do
      [['a', 'b'], ['c', 'd'], ['e', 'f']].transpose.should eq([['a', 'c', 'e'], ['b', 'd', 'f']])
      [['a', 'c', 'e'], ['b', 'd', 'f']].transpose.should eq([['a', 'b'], ['c', 'd'], ['e', 'f']])
      [['a']].transpose.should eq([['a']])
    end

    it "transposes union of arrays" do
      [[1, 2], [1.0, 2.0]].transpose.should eq([[1, 1.0], [2, 2.0]])
      [[1, 2.0], [1, 2.0]].transpose.should eq([[1, 1], [2.0, 2.0]])
      [[1, 1.0], ['a', "aaa"]].transpose.should eq([[1, 'a'], [1.0, "aaa"]])

      typeof([[1.0], [1]].transpose).should eq(Array(Array(Int32 | Float64)))
      typeof([[1, 1.0], ['a', "aaa"]].transpose).should eq(Array(Array(String | Int32 | Float64 | Char)))
    end

    it "transposes empty array" do
      e = [] of Array(Int32)
      e.transpose.should be_empty
      [e].transpose.should be_empty
      [e, e, e].transpose.should be_empty
    end

    it "raises IndexError error when size of element is invalid" do
      expect_raises(IndexError) { [[1], [1, 2]].transpose }
      expect_raises(IndexError) { [[1, 2], [1]].transpose }
    end

    it "transposes array of tuples" do
      [{1, 1.0}].transpose.should eq([[1], [1.0]])
      [{1}, {1.0}].transpose.should eq([[1, 1.0]])
      [{1, 1.0}, {'a', "aaa"}].transpose.should eq([[1, 'a'], [1.0, "aaa"]])

      typeof([{1, 1.0}].transpose).should eq(Array(Array(Int32 | Float64)))
      typeof([{1}, {1.0}].transpose).should eq(Array(Array(Int32 | Float64)))
      typeof([{1, 1.0}, {'a', "aaa"}].transpose).should eq(Array(Array(String | Int32 | Float64 | Char)))
    end
  end

  describe "rotate" do
    it "rotate!" do
      a = [1, 2, 3]
      a.rotate!.should be(a); a.should eq([2, 3, 1])
      a.rotate!.should be(a); a.should eq([3, 1, 2])
      a.rotate!.should be(a); a.should eq([1, 2, 3])
      a.rotate!.should be(a); a.should eq([2, 3, 1])
    end

    it "rotate" do
      a = [1, 2, 3]
      a.rotate.should eq([2, 3, 1])
      a.should eq([1, 2, 3])
      a.rotate.should eq([2, 3, 1])
    end

    it { a = [1, 2, 3]; a.rotate!(0); a.should eq([1, 2, 3]) }
    it { a = [1, 2, 3]; a.rotate!(1); a.should eq([2, 3, 1]) }
    it { a = [1, 2, 3]; a.rotate!(2); a.should eq([3, 1, 2]) }
    it { a = [1, 2, 3]; a.rotate!(3); a.should eq([1, 2, 3]) }
    it { a = [1, 2, 3]; a.rotate!(4); a.should eq([2, 3, 1]) }
    it { a = [1, 2, 3]; a.rotate!(3001); a.should eq([2, 3, 1]) }
    it { a = [1, 2, 3]; a.rotate!(-1); a.should eq([3, 1, 2]) }
    it { a = [1, 2, 3]; a.rotate!(-3001); a.should eq([3, 1, 2]) }

    it { a = [1, 2, 3]; a.rotate(0).should eq([1, 2, 3]); a.should eq([1, 2, 3]) }
    it { a = [1, 2, 3]; a.rotate(1).should eq([2, 3, 1]); a.should eq([1, 2, 3]) }
    it { a = [1, 2, 3]; a.rotate(2).should eq([3, 1, 2]); a.should eq([1, 2, 3]) }
    it { a = [1, 2, 3]; a.rotate(3).should eq([1, 2, 3]); a.should eq([1, 2, 3]) }
    it { a = [1, 2, 3]; a.rotate(4).should eq([2, 3, 1]); a.should eq([1, 2, 3]) }
    it { a = [1, 2, 3]; a.rotate(3001).should eq([2, 3, 1]); a.should eq([1, 2, 3]) }
    it { a = [1, 2, 3]; a.rotate(-1).should eq([3, 1, 2]); a.should eq([1, 2, 3]) }
    it { a = [1, 2, 3]; a.rotate(-3001).should eq([3, 1, 2]); a.should eq([1, 2, 3]) }

    it do
      a = Array(Int32).new(50) { |i| i }
      a.rotate!(5)
      a.should eq([5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 0, 1, 2, 3, 4])
    end

    it do
      a = Array(Int32).new(50) { |i| i }
      a.rotate!(-5)
      a.should eq([45, 46, 47, 48, 49, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44])
    end

    it do
      a = Array(Int32).new(50) { |i| i }
      a.rotate!(20)
      a.should eq([20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19])
    end

    it do
      a = Array(Int32).new(50) { |i| i }
      a.rotate!(-20)
      a.should eq([30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29])
    end
  end

  describe "repeated_permutations" do
    it { [1, 2, 2].repeated_permutations.should eq([[1, 1, 1], [1, 1, 2], [1, 1, 2], [1, 2, 1], [1, 2, 2], [1, 2, 2], [1, 2, 1], [1, 2, 2], [1, 2, 2], [2, 1, 1], [2, 1, 2], [2, 1, 2], [2, 2, 1], [2, 2, 2], [2, 2, 2], [2, 2, 1], [2, 2, 2], [2, 2, 2], [2, 1, 1], [2, 1, 2], [2, 1, 2], [2, 2, 1], [2, 2, 2], [2, 2, 2], [2, 2, 1], [2, 2, 2], [2, 2, 2]]) }
    it { [1, 2, 3].repeated_permutations.should eq([[1, 1, 1], [1, 1, 2], [1, 1, 3], [1, 2, 1], [1, 2, 2], [1, 2, 3], [1, 3, 1], [1, 3, 2], [1, 3, 3], [2, 1, 1], [2, 1, 2], [2, 1, 3], [2, 2, 1], [2, 2, 2], [2, 2, 3], [2, 3, 1], [2, 3, 2], [2, 3, 3], [3, 1, 1], [3, 1, 2], [3, 1, 3], [3, 2, 1], [3, 2, 2], [3, 2, 3], [3, 3, 1], [3, 3, 2], [3, 3, 3]]) }
    it { [1, 2, 3].repeated_permutations(1).should eq([[1], [2], [3]]) }
    it { [1, 2, 3].repeated_permutations(2).should eq([[1, 1], [1, 2], [1, 3], [2, 1], [2, 2], [2, 3], [3, 1], [3, 2], [3, 3]]) }
    it { [1, 2, 3].repeated_permutations(3).should eq([[1, 1, 1], [1, 1, 2], [1, 1, 3], [1, 2, 1], [1, 2, 2], [1, 2, 3], [1, 3, 1], [1, 3, 2], [1, 3, 3], [2, 1, 1], [2, 1, 2], [2, 1, 3], [2, 2, 1], [2, 2, 2], [2, 2, 3], [2, 3, 1], [2, 3, 2], [2, 3, 3], [3, 1, 1], [3, 1, 2], [3, 1, 3], [3, 2, 1], [3, 2, 2], [3, 2, 3], [3, 3, 1], [3, 3, 2], [3, 3, 3]]) }
    it { [1, 2, 3].repeated_permutations(0).should eq([[] of Int32]) }
    it { [1, 2, 3].repeated_permutations(4).should eq([[1, 1, 1, 1], [1, 1, 1, 2], [1, 1, 1, 3], [1, 1, 2, 1], [1, 1, 2, 2], [1, 1, 2, 3], [1, 1, 3, 1], [1, 1, 3, 2], [1, 1, 3, 3], [1, 2, 1, 1], [1, 2, 1, 2], [1, 2, 1, 3], [1, 2, 2, 1], [1, 2, 2, 2], [1, 2, 2, 3], [1, 2, 3, 1], [1, 2, 3, 2], [1, 2, 3, 3], [1, 3, 1, 1], [1, 3, 1, 2], [1, 3, 1, 3], [1, 3, 2, 1], [1, 3, 2, 2], [1, 3, 2, 3], [1, 3, 3, 1], [1, 3, 3, 2], [1, 3, 3, 3], [2, 1, 1, 1], [2, 1, 1, 2], [2, 1, 1, 3], [2, 1, 2, 1], [2, 1, 2, 2], [2, 1, 2, 3], [2, 1, 3, 1], [2, 1, 3, 2], [2, 1, 3, 3], [2, 2, 1, 1], [2, 2, 1, 2], [2, 2, 1, 3], [2, 2, 2, 1], [2, 2, 2, 2], [2, 2, 2, 3], [2, 2, 3, 1], [2, 2, 3, 2], [2, 2, 3, 3], [2, 3, 1, 1], [2, 3, 1, 2], [2, 3, 1, 3], [2, 3, 2, 1], [2, 3, 2, 2], [2, 3, 2, 3], [2, 3, 3, 1], [2, 3, 3, 2], [2, 3, 3, 3], [3, 1, 1, 1], [3, 1, 1, 2], [3, 1, 1, 3], [3, 1, 2, 1], [3, 1, 2, 2], [3, 1, 2, 3], [3, 1, 3, 1], [3, 1, 3, 2], [3, 1, 3, 3], [3, 2, 1, 1], [3, 2, 1, 2], [3, 2, 1, 3], [3, 2, 2, 1], [3, 2, 2, 2], [3, 2, 2, 3], [3, 2, 3, 1], [3, 2, 3, 2], [3, 2, 3, 3], [3, 3, 1, 1], [3, 3, 1, 2], [3, 3, 1, 3], [3, 3, 2, 1], [3, 3, 2, 2], [3, 3, 2, 3], [3, 3, 3, 1], [3, 3, 3, 2], [3, 3, 3, 3]]) }
    it { expect_raises(ArgumentError, "Size must be positive") { [1].repeated_permutations(-1) } }

    it "accepts a block" do
      sums = [] of Int32
      [1, 2, 3].each_repeated_permutation(2) do |a|
        sums << a.sum
      end.should be_nil
      sums.should eq([2, 3, 4, 3, 4, 5, 4, 5, 6])
    end

    it "yielding dup of arrays" do
      sums = [] of Int32
      [1, 2, 3].each_repeated_permutation(3) do |a|
        a.map! &.+(1)
        sums << a.sum
      end.should be_nil
      sums.should eq([6, 7, 8, 7, 8, 9, 8, 9, 10, 7, 8, 9, 8, 9, 10, 9, 10, 11, 8, 9, 10, 9, 10, 11, 10, 11, 12])
    end

    it "yields with reuse = true" do
      sums = [] of Int32
      object_ids = Set(UInt64).new
      [1, 2, 3].each_repeated_permutation(3, reuse: true) do |a|
        object_ids << a.object_id
        a.map! &.+(1)
        sums << a.sum
      end.should be_nil
      sums.should eq([6, 7, 8, 7, 8, 9, 8, 9, 10, 7, 8, 9, 8, 9, 10, 9, 10, 11, 8, 9, 10, 9, 10, 11, 10, 11, 12])
      object_ids.size.should eq(1)
    end

    it "yields with reuse = array" do
      sums = [] of Int32
      reuse = [] of Int32
      [1, 2, 3].each_repeated_permutation(3, reuse: reuse) do |a|
        a.should be(reuse)
        a.map! &.+(1)
        sums << a.sum
      end.should be_nil
      sums.should eq([6, 7, 8, 7, 8, 9, 8, 9, 10, 7, 8, 9, 8, 9, 10, 9, 10, 11, 8, 9, 10, 9, 10, 11, 10, 11, 12])
    end

    it { expect_raises(ArgumentError, "Size must be positive") { [1].each_repeated_permutation(-1) { } } }
  end

  describe "Array.each_product" do
    it "one empty array" do
      empty = [] of Int32
      res = [] of Array(Int32)
      Array.each_product([empty, [1, 2, 3]]) { |r| res << r }
      Array.each_product([[1, 2, 3], empty]) { |r| res << r }
      res.size.should eq(0)
    end

    it "single array" do
      res = [] of Array(Int32)
      Array.each_product([[1]]) { |r| res << r }
      res.should eq([[1]])
    end

    it "2 arrays" do
      res = [] of Array(Int32)
      Array.each_product([[1, 2], [3, 4]]) { |r| res << r }
      res.should eq([[1, 3], [1, 4], [2, 3], [2, 4]])
    end

    it "2 arrays different types" do
      res = [] of Array(Int32 | Char)
      Array.each_product([[1, 2], ['a', 'b']]) { |r| res << r }
      res.should eq([[1, 'a'], [1, 'b'], [2, 'a'], [2, 'b']])
    end

    it "more arrays" do
      res = [] of Array(Int32)
      Array.each_product([[1, 2], [3], [5, 6]]) { |r| res << r }
      res.should eq([[1, 3, 5], [1, 3, 6], [2, 3, 5], [2, 3, 6]])
    end

    it "more arrays, reuse = true" do
      res = [] of Array(Int32)
      object_ids = Set(UInt64).new
      Array.each_product([[1, 2], [3], [5, 6]], reuse: true) do |r|
        object_ids << r.object_id
        res << r.dup
      end
      res.should eq([[1, 3, 5], [1, 3, 6], [2, 3, 5], [2, 3, 6]])
      object_ids.size.should eq(1)
    end

    it "with splat" do
      res = [] of Array(Int32 | Char)
      Array.each_product([1, 2], ['a', 'b']) { |r| res << r }
      res.should eq([[1, 'a'], [1, 'b'], [2, 'a'], [2, 'b']])
    end
  end

  describe "Array.product" do
    it "with array" do
      Array.product([[1, 2], ['a', 'b']]).should eq([[1, 'a'], [1, 'b'], [2, 'a'], [2, 'b']])
    end

    it "with splat" do
      Array.product([1, 2], ['a', 'b']).should eq([[1, 'a'], [1, 'b'], [2, 'a'], [2, 'b']])
    end
  end

  it "doesn't overflow buffer with Array.new(size, value) (#1209)" do
    a = Array.new(1, 1_i64)
    b = Array.new(1, 1_i64)
    b << 2_i64 << 3_i64
    a.should eq([1])
    b.should eq([1, 2, 3])
  end

  it "flattens" do
    [[1, 'a'], [[[[true], "hi"]]]].flatten.should eq([1, 'a', true, "hi"])

    s = [1, 2, 3]
    t = [4, 5, 6, [7, 8]]
    u = [9, [10, 11].each]
    a = [s, t, u, 12, 13]
    result = a.flatten.to_a
    result.should eq([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13])
    result.should be_a(Array(Int32))
  end

  it "#skip" do
    ary = [1, 2, 3]
    ary.skip(0).should eq([1, 2, 3])
    ary.skip(1).should eq([2, 3])
    ary.skip(2).should eq([3])
    ary.skip(3).should eq([] of Int32)
    ary.skip(4).should eq([] of Int32)

    expect_raises(ArgumentError, "Attempt to skip negative size") do
      ary.skip(-1)
    end
  end

  describe "#ensure_capacity" do
    it "does nothing if it fits" do
      ary = [1, 2, 3]
      capacity1 = ary.remaining_capacity
      ary.ensure_capacity(3)
      ary.should eq([1, 2, 3])
      ary.remaining_capacity.should eq(capacity1)
    end

    it "grows the array if it doesn't fit" do
      ary = [1, 2, 3]
      ary.ensure_capacity(4).should eq([1, 2, 3])
      ary.remaining_capacity.should eq(4)
    end

    it "doesn't rewinds the array" do
      ary = [1, 2, 3]
      ary.shift
      ary.ensure_capacity(3).should eq([2, 3])
      ary.remaining_capacity.should eq(2)
    end

    it "does nothing if there's not enough capacity" do
      ary = [1, 2, 3]
      ary.ensure_capacity(2).should eq([1, 2, 3])
      ary.remaining_capacity.should eq(3)
    end
  end

  describe "trim_to_size" do
    it "trims" do
      a = Array(Int32).new(10)
      a << 1 << 2 << 3
      a.trim_to_size.should eq([1, 2, 3])
      a.remaining_capacity.should eq(3)
    end

    it "trims with extra capacity" do
      a = Array(Int32).new(10)
      a << 1 << 2 << 3
      a.trim_to_size(extra: 2).should eq([1, 2, 3])
      a.remaining_capacity.should eq(5)
    end

    it "rewinds the array" do
      a = Array(Int32).new(10)
      a << 1 << 2 << 3
      a.shift
      a.trim_to_size.should eq([2, 3])
      a.remaining_capacity.should eq(2)
    end

    it "raises on negative extra capacity" do
      expect_raises(ArgumentError, "Negative extra capacity: -1") do
        a = [1, 2, 3]
        a.trim_to_size(extra: -1)
      end
    end
  end

  describe "capacity re-sizing" do
    it "initializes an array capacity to INITIAL_CAPACITY" do
      a = [] of Int32
      a.push(1)
      a.@capacity.should eq(3)
    end

    it "doubles capacity for arrays smaller than CAPACITY_THRESHOLD" do
      a = Array.new(255, 1)
      a.push(1)
      a.@capacity.should eq(255 * 2)
    end

    it "uses slow growth heuristic for arrays larger than CAPACITY_THRESHOLD" do
      a = Array.new(512, 1)
      a.push(1)
      # ~63% larger
      a.@capacity.should eq(832)

      b = Array.new(4096, 1)
      b.push(1)
      # ~30% larger, starts converging toward 25%
      b.@capacity.should eq(5312)
    end
  end
end
