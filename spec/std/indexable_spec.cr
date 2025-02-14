require "spec"
require "spec/helpers/iterate"

module OtherInterface; end

private record Three do
  include OtherInterface
end

private record Four do
  include OtherInterface
end

private struct InterfaceIndexable
  include Indexable(OtherInterface)

  def size
    2
  end

  def unsafe_fetch(index : Int) : OtherInterface
    case index
    when 0 then Three.new
    when 1 then Four.new
    else
      raise ""
    end
  end
end

private class SafeIndexable
  include Indexable(Int32)

  property size

  def initialize(@size : Int32, @offset = 0_i32)
  end

  def unsafe_fetch(index) : Int32
    raise IndexError.new unless 0 <= index < size
    (index + @offset).to_i
  end
end

private class SafeNestedIndexable
  include Indexable(Indexable(Int32))

  property size

  def initialize(@size : Int32, @inner_size : Int32)
  end

  def unsafe_fetch(index)
    raise IndexError.new unless 0 <= index < size
    SafeIndexable.new(@inner_size)
  end
end

private class SafeStringIndexable
  include Indexable(String)

  property size

  def initialize(@size : Int32)
  end

  def unsafe_fetch(index) : String
    raise IndexError.new unless 0 <= index < size
    index.to_s
  end
end

private class SafeMixedIndexable
  include Indexable(String | Int32)

  property size

  def initialize(@size : Int32)
  end

  def unsafe_fetch(index) : String | Int32
    raise IndexError.new unless 0 <= index < size
    index.to_s
  end
end

private class SafeRecursiveIndexable
  include Indexable(SafeRecursiveIndexable | Int32)

  property size

  def initialize(@size : Int32)
  end

  def unsafe_fetch(index) : SafeRecursiveIndexable | Int32
    raise IndexError.new unless 0 <= index < size
    if (index % 2) == 0
      SafeRecursiveIndexable.new(index)
    else
      index
    end
  end
end

describe Indexable do
  describe "#index" do
    it "does index with big negative offset" do
      indexable = SafeIndexable.new(3)
      indexable.index(0, -100).should be_nil
    end

    it "does index with big offset" do
      indexable = SafeIndexable.new(3)
      indexable.index(0, 100).should be_nil
    end

    it "offset type" do
      indexable = SafeIndexable.new(3)
      indexable.index(1, 0_i64).should eq 1
      indexable.index(1, 0_i64).should be_a(Int64)
    end
  end

  describe "#index!" do
    it "offset type" do
      indexable = SafeIndexable.new(3)
      indexable.index!(1, 0_i64).should eq 1
      indexable.index!(1, 0_i64).should be_a(Int64)
    end

    it "raises if no element is found" do
      indexable = SafeIndexable.new(3)
      expect_raises(Enumerable::NotFoundError) { indexable.index!(0, -100) }
      expect_raises(Enumerable::NotFoundError) { indexable.index!(0, -4) }
      expect_raises(Enumerable::NotFoundError) { indexable.index!(0, 1) }
      expect_raises(Enumerable::NotFoundError) { indexable.index!(0, 3) }
      expect_raises(Enumerable::NotFoundError) { indexable.index!(0, 100) }

      expect_raises(Enumerable::NotFoundError) { indexable.index!(-4) { true } }
      expect_raises(Enumerable::NotFoundError) { indexable.index!(3) { true } }
      expect_raises(Enumerable::NotFoundError) { indexable.index!(2) { false } }
      expect_raises(Enumerable::NotFoundError) { indexable.index!(-3) { false } }
    end
  end

  describe "#rindex" do
    it "does rindex with big negative offset" do
      indexable = SafeIndexable.new(3)
      indexable.rindex(0, -100).should be_nil
    end

    it "does rindex with big offset" do
      indexable = SafeIndexable.new(3)
      indexable.rindex(0, 100).should be_nil
    end

    it "offset type" do
      indexable = SafeIndexable.new(3)
      indexable.rindex(1, 2_i64).should eq 1
      indexable.rindex(1, 2_i64).should be_a(Int64)
    end
  end

  describe "#rindex!" do
    it "does rindex with big negative offset" do
      indexable = SafeIndexable.new(3)
      expect_raises Enumerable::NotFoundError do
        indexable.rindex!(0, -100)
      end
    end

    it "does rindex with big offset" do
      indexable = SafeIndexable.new(3)
      expect_raises Enumerable::NotFoundError do
        indexable.rindex!(0, 100)
      end
    end

    it "offset type" do
      indexable = SafeIndexable.new(3)
      indexable.rindex!(1, 2_i64).should eq 1
      indexable.rindex!(1, 2_i64).should be_a(Int64)
    end
  end

  it "does each" do
    indexable = SafeIndexable.new(3)
    is = [] of Int32
    indexable.each do |i|
      is << i
    end.should be_nil
    is.should eq([0, 1, 2])
  end

  it "does each_index" do
    indexable = SafeIndexable.new(3)
    is = [] of Int32
    indexable.each_index do |i|
      is << i
    end.should be_nil
    is.should eq([0, 1, 2])
  end

  it "does each_slice" do
    indexable = SafeIndexable.new(7)
    is = [] of Array(Int32)
    indexable.each_slice(2) { |i| is << i }.should be_nil
    is.should eq([[0, 1], [2, 3], [4, 5], [6]])

    indexable = SafeIndexable.new(9)
    is = [] of Array(Int32)
    indexable.each_slice(3) { |i| is << i }.should be_nil
    is.should eq([[0, 1, 2], [3, 4, 5], [6, 7, 8]])
  end

  it "iterates through a subset of its elements (#3386)" do
    indexable = SafeIndexable.new(5)
    elems = [] of Int32

    return_value = indexable.each(start: 2, count: 3) do |elem|
      elems << elem
    end

    elems.should eq([2, 3, 4])
    return_value.should eq(indexable)
  end

  it "iterates until its size (#3386)" do
    indexable = SafeIndexable.new(5)
    elems = [] of Int32

    indexable.each(start: 3, count: 999) do |elem|
      elems << elem
    end

    elems.should eq([3, 4])
  end

  it "iterates until its size, having mutated (#3386)" do
    indexable = SafeIndexable.new(10)
    elems = [] of Int32

    indexable.each(start: 3, count: 999) do |elem|
      # size is incremented 3 times
      indexable.size += 1 if elem <= 5
      elems << elem
    end

    # last was 9, but now is 12.
    elems.should eq([3, 4, 5, 6, 7, 8, 9, 10, 11, 12])
  end

  it "iterates until its size, having mutated (#3386)" do
    indexable = SafeIndexable.new(10)
    elems = [] of Int32

    indexable.each(start: 3, count: 5) do |elem|
      indexable.size += 1
      elems << elem
    end

    # last element iterated is still 7.
    elems.should eq([3, 4, 5, 6, 7])
  end

  it "iterates within a range of indices (#3386)" do
    indexable = SafeIndexable.new(5)
    elems = [] of Int32

    return_value = indexable.each(within: 2..3) do |elem|
      elems << elem
    end

    elems.should eq([2, 3])
    return_value.should eq(indexable)
  end

  it "iterates within a range of indices, no end" do
    indexable = SafeIndexable.new(5)
    elems = [] of Int32

    return_value = indexable.each(within: 2..nil) do |elem|
      elems << elem
    end

    elems.should eq([2, 3, 4])
    return_value.should eq(indexable)
  end

  it "iterates within a range of indices, no beginning" do
    indexable = SafeIndexable.new(5)

    elems = [] of Int32
    return_value = indexable.each(within: nil..2) do |elem|
      elems << elem
    end

    elems.should eq([0, 1, 2])
    return_value.should eq(indexable)
  end

  describe "#join" do
    it "joins strings (empty case)" do
      indexable = SafeStringIndexable.new(0)
      indexable.join.should eq("")
      indexable.join(", ").should eq("")
    end

    it "joins strings (non-empty case)" do
      indexable = SafeStringIndexable.new(12)
      indexable.join(", ").should eq("0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11")
      indexable.join(98).should eq("098198298398498598698798898998109811")
    end

    it "joins non-strings" do
      indexable = SafeIndexable.new(12)
      indexable.join(", ").should eq("0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11")
      indexable.join(98).should eq("098198298398498598698798898998109811")
    end

    it "joins when T has String" do
      indexable = SafeMixedIndexable.new(12)
      indexable.join(", ").should eq("0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11")
      indexable.join(98).should eq("098198298398498598698798898998109811")
    end

    it "with IO" do
      String.build do |io|
        indexable = SafeStringIndexable.new(12)
        indexable.join(io)
      end.should eq "01234567891011"
    end
  end

  describe "dig?" do
    it "gets the value at given path given splat" do
      indexable = SafeRecursiveIndexable.new(30)
      indexable.dig?(20, 10, 4, 3).should eq(3)
    end

    it "returns nil if not found" do
      indexable = SafeRecursiveIndexable.new(30)
      indexable.dig?(2, 4).should be_nil
      indexable.dig?(3, 7).should be_nil
    end
  end

  describe "dig" do
    it "gets the value at given path given splat" do
      indexable = SafeRecursiveIndexable.new(30)
      indexable.dig(20, 10, 4, 3).should eq(3)
    end

    it "raises IndexError if not found" do
      indexable = SafeRecursiveIndexable.new(30)
      expect_raises IndexError, %(Index out of bounds) do
        indexable.dig(2, 4)
      end
      expect_raises IndexError, %(Indexable value not diggable for index: 3) do
        indexable.dig(3, 7)
      end
    end
  end

  describe "fetch" do
    it "fetches with default value" do
      indexable = SafeIndexable.new(3)
      a = indexable.to_a

      indexable.fetch(2, 4).should eq(2)
      indexable.fetch(3, 4).should eq(4)
      a.should eq([0, 1, 2])
    end

    it "fetches with block" do
      indexable = SafeIndexable.new(3)
      a = indexable.to_a

      indexable.fetch(2) { |k| k * 3 }.should eq(2)
      indexable.fetch(3) { |k| k * 3 }.should eq(9)
      a.should eq([0, 1, 2])
    end
  end

  describe "#cartesian_product" do
    it "does with 1 other Indexable" do
      elems = SafeIndexable.new(2).cartesian_product(SafeIndexable.new(3))
      elems.should eq([{0, 0}, {0, 1}, {0, 2}, {1, 0}, {1, 1}, {1, 2}])

      elems = SafeIndexable.new(2).cartesian_product(SafeIndexable.new(0))
      elems.should be_empty

      elems = SafeIndexable.new(0).cartesian_product(SafeIndexable.new(3))
      elems.should be_empty
    end

    it "does with >1 other Indexables" do
      elems = SafeIndexable.new(2).cartesian_product(SafeStringIndexable.new(2), SafeIndexable.new(2))
      elems.should eq([
        {0, "0", 0}, {0, "0", 1}, {0, "1", 0}, {0, "1", 1},
        {1, "0", 0}, {1, "0", 1}, {1, "1", 0}, {1, "1", 1},
      ])
    end
  end

  describe ".cartesian_product" do
    it "does with an Indexable of Indexables" do
      elems = Indexable.cartesian_product(SafeNestedIndexable.new(2, 3))
      elems.should eq([[0, 0], [0, 1], [0, 2], [1, 0], [1, 1], [1, 2], [2, 0], [2, 1], [2, 2]])

      elems = Indexable.cartesian_product(SafeNestedIndexable.new(2, 0))
      elems.should be_empty

      elems = Indexable.cartesian_product(SafeNestedIndexable.new(0, 3))
      elems.should eq([[] of Int32])

      elems = Indexable.cartesian_product(SafeNestedIndexable.new(0, 0))
      elems.should eq([[] of Int32])
    end

    it "does with a Tuple of Tuples with mixed types" do
      elems = Indexable.cartesian_product({ {1, 'a'}, {"", 4}, {5, 6} })
      elems.should be_a(Array(Array(Int32 | Char | String)))
      elems.should eq([[1, "", 5], [1, "", 6], [1, 4, 5], [1, 4, 6], ['a', "", 5], ['a', "", 6], ['a', 4, 5], ['a', 4, 6]])
    end
  end

  describe "#each_cartesian" do
    it "does with 1 other Indexable, with block" do
      r = [] of Int32 | String
      indexable = SafeIndexable.new(3)
      indexable.each_cartesian(SafeStringIndexable.new(2)) { |a, b| r << a; r << b }
      r.should eq([0, "0", 0, "1", 1, "0", 1, "1", 2, "0", 2, "1"])

      r = [] of Int32 | String
      indexable = SafeIndexable.new(3)
      indexable.each_cartesian(SafeStringIndexable.new(0)) { |a, b| r << a; r << b }
      r.should be_empty

      r = [] of Int32 | String
      indexable = SafeIndexable.new(0)
      indexable.each_cartesian(SafeStringIndexable.new(2)) { |a, b| r << a; r << b }
      r.should be_empty
    end

    it "does with 1 other Indexable, without block" do
      iter = SafeIndexable.new(3).each_cartesian(SafeStringIndexable.new(2))
      iter.next.should eq({0, "0"})
      iter.next.should eq({0, "1"})
      iter.next.should eq({1, "0"})
      iter.next.should eq({1, "1"})
      iter.next.should eq({2, "0"})
      iter.next.should eq({2, "1"})
      iter.next.should be_a(Iterator::Stop)
    end

    it "does with 1 other Indexable, without block, combined with select" do
      iter = SafeIndexable.new(3).each_cartesian(SafeStringIndexable.new(2))
      iter = iter.select { |(x, y)| x > 0 }
      iter.next.should eq({1, "0"})
      iter.next.should eq({1, "1"})
      iter.next.should eq({2, "0"})
      iter.next.should eq({2, "1"})
      iter.next.should be_a(Iterator::Stop)
    end

    it "does with >1 other Indexables, with block" do
      r = [] of Int32 | String
      i1 = SafeIndexable.new(2)
      i2 = SafeIndexable.new(3)
      i3 = SafeIndexable.new(4)
      i1.each_cartesian(i2, i3) { |a, b, c| r << a + b + c }
      r.should eq([0, 1, 2, 3, 1, 2, 3, 4, 2, 3, 4, 5, 1, 2, 3, 4, 2, 3, 4, 5, 3, 4, 5, 6])
    end

    it "does with >1 other Indexables, without block" do
      i1 = SafeStringIndexable.new(2)
      i2 = SafeStringIndexable.new(2)
      i3 = SafeIndexable.new(2)
      iter = i1.each_cartesian(i2, i3)
      iter.next.should eq({"0", "0", 0})
      iter.next.should eq({"0", "0", 1})
      iter.next.should eq({"0", "1", 0})
      iter.next.should eq({"0", "1", 1})
      iter.next.should eq({"1", "0", 0})
      iter.next.should eq({"1", "0", 1})
      iter.next.should eq({"1", "1", 0})
      iter.next.should eq({"1", "1", 1})
      iter.next.should be_a(Iterator::Stop)
    end
  end

  describe ".each_cartesian" do
    it "does with an Indexable of Indexables, with block" do
      r = [] of Int32
      Indexable.each_cartesian(SafeNestedIndexable.new(3, 2)) { |v| r.concat(v) }
      r.should eq([0, 0, 0, 0, 0, 1, 0, 1, 0, 0, 1, 1, 1, 0, 0, 1, 0, 1, 1, 1, 0, 1, 1, 1])

      r = [] of Int32
      Indexable.each_cartesian(SafeNestedIndexable.new(3, 0)) { |v| r.concat(v) }
      r.should be_empty

      r = [] of Int32
      Indexable.each_cartesian(SafeNestedIndexable.new(0, 2)) { |v| r.concat(v) }
      r.should be_empty

      r = [] of Int32
      Indexable.each_cartesian(SafeNestedIndexable.new(0, 0)) { |v| r.concat(v) }
      r.should be_empty
    end

    it "does with reuse = true, with block" do
      r = [] of Int32
      object_ids = Set(UInt64).new
      indexables = SafeNestedIndexable.new(3, 2)

      Indexable.each_cartesian(indexables, reuse: true) do |v|
        object_ids << v.object_id
        r.concat(v)
      end

      r.should eq([0, 0, 0, 0, 0, 1, 0, 1, 0, 0, 1, 1, 1, 0, 0, 1, 0, 1, 1, 1, 0, 1, 1, 1])
      object_ids.size.should eq(1)
    end

    it "does with reuse = array, with block" do
      r = [] of Int32
      buf = [] of Int32
      indexables = SafeNestedIndexable.new(3, 2)

      Indexable.each_cartesian(indexables, reuse: buf) do |v|
        v.should be(buf)
        r.concat(v)
      end

      r.should eq([0, 0, 0, 0, 0, 1, 0, 1, 0, 0, 1, 1, 1, 0, 0, 1, 0, 1, 1, 1, 0, 1, 1, 1])
    end

    it "does with an Indexable of Indexables, without block" do
      iter = Indexable.each_cartesian(SafeNestedIndexable.new(2, 3))
      iter.next.should eq([0, 0])
      iter.next.should eq([0, 1])
      iter.next.should eq([0, 2])
      iter.next.should eq([1, 0])
      iter.next.should eq([1, 1])
      iter.next.should eq([1, 2])
      iter.next.should eq([2, 0])
      iter.next.should eq([2, 1])
      iter.next.should eq([2, 2])
      iter.next.should be_a(Iterator::Stop)

      iter = Indexable.each_cartesian(SafeNestedIndexable.new(0, 3))
      iter.next.should eq([] of Int32)
      iter.next.should be_a(Iterator::Stop)
    end

    it "does with an Indexable of Indexables, without block, combined with select" do
      iter = Indexable.each_cartesian(SafeNestedIndexable.new(2, 3))
      iter = iter.select { |(x, y)| x > 0 }
      iter.next.should eq([1, 0])
      iter.next.should eq([1, 1])
      iter.next.should eq([1, 2])
      iter.next.should eq([2, 0])
      iter.next.should eq([2, 1])
      iter.next.should eq([2, 2])
      iter.next.should be_a(Iterator::Stop)

      iter = Indexable.each_cartesian(SafeNestedIndexable.new(0, 3))
      iter.next.should eq([] of Int32)
      iter.next.should be_a(Iterator::Stop)
    end

    it "does with reuse = true, without block" do
      iter = Indexable.each_cartesian(SafeNestedIndexable.new(2, 2), reuse: true)
      buf = iter.next
      buf.should eq([0, 0])
      iter.next.should be(buf)
      buf.should eq([0, 1])
      iter.next.should be(buf)
      buf.should eq([1, 0])
      iter.next.should be(buf)
      buf.should eq([1, 1])
      iter.next.should be_a(Iterator::Stop)
    end

    it "does with reuse = array, without block" do
      buf = [] of Int32
      iter = Indexable.each_cartesian(SafeNestedIndexable.new(2, 2), reuse: buf)
      iter.next.should be(buf)
      buf.should eq([0, 0])
      iter.next.should be(buf)
      buf.should eq([0, 1])
      iter.next.should be(buf)
      buf.should eq([1, 0])
      iter.next.should be(buf)
      buf.should eq([1, 1])
    end
  end

  describe "permutations" do
    it { [1, 2, 2].permutations.should eq([[1, 2, 2], [1, 2, 2], [2, 1, 2], [2, 2, 1], [2, 1, 2], [2, 2, 1]]) }
    it { SafeIndexable.new(3, 1).permutations.should eq([[1, 2, 3], [1, 3, 2], [2, 1, 3], [2, 3, 1], [3, 1, 2], [3, 2, 1]]) }
    it { SafeIndexable.new(3, 1).permutations(1).should eq([[1], [2], [3]]) }
    it { SafeIndexable.new(3, 1).permutations(2).should eq([[1, 2], [1, 3], [2, 1], [2, 3], [3, 1], [3, 2]]) }
    it { SafeIndexable.new(3, 1).permutations(3).should eq([[1, 2, 3], [1, 3, 2], [2, 1, 3], [2, 3, 1], [3, 1, 2], [3, 2, 1]]) }
    it { SafeIndexable.new(3, 1).permutations(0).should eq([[] of Int32]) }
    it { SafeIndexable.new(3, 1).permutations(4).should eq([] of Array(Int32)) }
    it { expect_raises(ArgumentError, "Size must be positive") { [1].permutations(-1) } }

    it "accepts a block" do
      sums = [] of Int32
      SafeIndexable.new(3, 1).each_permutation(2) do |perm|
        sums << perm.sum
      end.should be_nil
      sums.should eq([3, 4, 3, 5, 4, 5])
    end

    it "yielding dup of arrays" do
      sums = [] of Int32
      SafeIndexable.new(3, 1).each_permutation(3) do |perm|
        perm.map! &.+(1)
        sums << perm.sum
      end.should be_nil
      sums.should eq([9, 9, 9, 9, 9, 9])
    end

    it "yields with reuse = true" do
      sums = [] of Int32
      object_ids = Set(UInt64).new
      SafeIndexable.new(3, 1).each_permutation(3, reuse: true) do |perm|
        object_ids << perm.object_id
        perm.map! &.+(1)
        sums << perm.sum
      end.should be_nil
      sums.should eq([9, 9, 9, 9, 9, 9])
      object_ids.size.should eq(1)
    end

    it { expect_raises(ArgumentError, "Size must be positive") { [1].each_permutation(-1) { } } }

    it "returns iterator" do
      a = SafeIndexable.new(3, 1)
      perms = a.permutations
      iter = a.each_permutation
      perms.each do |perm|
        iter.next.should eq(perm)
      end
      iter.next.should be_a(Iterator::Stop)
    end

    it "returns iterator with given size" do
      a = SafeIndexable.new(3, 1)
      perms = a.permutations(2)
      iter = a.each_permutation(2)
      perms.each do |perm|
        iter.next.should eq(perm)
      end
      iter.next.should be_a(Iterator::Stop)
    end

    it "returns iterator with reuse = true" do
      a = SafeIndexable.new(3, 1)
      object_ids = Set(UInt64).new
      perms = a.permutations
      iter = a.each_permutation(reuse: true)
      perms.each do |perm|
        b = iter.next.as(Array)
        object_ids << b.object_id
        b.should eq(perm)
      end
      iter.next.should be_a(Iterator::Stop)
      object_ids.size.should eq(1)
    end
  end

  describe "combinations" do
    it { [1, 2, 2].combinations.should eq([[1, 2, 2]]) }
    it { SafeIndexable.new(3, 1).combinations.should eq([[1, 2, 3]]) }
    it { SafeIndexable.new(3, 1).combinations(1).should eq([[1], [2], [3]]) }
    it { SafeIndexable.new(3, 1).combinations(2).should eq([[1, 2], [1, 3], [2, 3]]) }
    it { SafeIndexable.new(3, 1).combinations(3).should eq([[1, 2, 3]]) }
    it { SafeIndexable.new(3, 1).combinations(0).should eq([[] of Int32]) }
    it { SafeIndexable.new(3, 1).combinations(4).should eq([] of Array(Int32)) }
    it { SafeIndexable.new(4, 1).combinations(3).should eq([[1, 2, 3], [1, 2, 4], [1, 3, 4], [2, 3, 4]]) }
    it { SafeIndexable.new(4, 1).combinations(2).should eq([[1, 2], [1, 3], [1, 4], [2, 3], [2, 4], [3, 4]]) }
    it { expect_raises(ArgumentError, "Size must be positive") { [1].combinations(-1) } }

    it "accepts a block" do
      sums = [] of Int32
      SafeIndexable.new(3, 1).each_combination(2) do |comb|
        sums << comb.sum
      end.should be_nil
      sums.should eq([3, 4, 5])
    end

    it "yielding dup of arrays" do
      sums = [] of Int32
      SafeIndexable.new(3, 1).each_combination(3) do |comb|
        comb.map! &.+(1)
        sums << comb.sum
      end.should be_nil
      sums.should eq([9])
    end

    it "does with reuse = true" do
      sums = [] of Int32
      object_ids = Set(UInt64).new
      SafeIndexable.new(3, 1).each_combination(2, reuse: true) do |comb|
        sums << comb.sum
        object_ids << comb.object_id
      end.should be_nil
      sums.should eq([3, 4, 5])
      object_ids.size.should eq(1)
    end

    it "does with reuse = array" do
      sums = [] of Int32
      reuse = [] of Int32
      SafeIndexable.new(3, 1).each_combination(2, reuse: reuse) do |comb|
        sums << comb.sum
        comb.should be(reuse)
      end.should be_nil
      sums.should eq([3, 4, 5])
    end

    it { expect_raises(ArgumentError, "Size must be positive") { [1].each_combination(-1) { } } }

    it "returns iterator" do
      a = [1, 2, 3, 4]
      combs = a.combinations(2)
      iter = a.each_combination(2)
      combs.each do |comb|
        iter.next.should eq(comb)
      end
      iter.next.should be_a(Iterator::Stop)
    end

    it "returns iterator with reuse = true" do
      a = [1, 2, 3, 4]
      combs = a.combinations(2)
      object_ids = Set(UInt64).new
      iter = a.each_combination(2, reuse: true)
      combs.each do |comb|
        b = iter.next
        object_ids << b.object_id
        b.should eq(comb)
      end
      iter.next.should be_a(Iterator::Stop)
      object_ids.size.should eq(1)
    end

    it "returns iterator with reuse = array" do
      a = [1, 2, 3, 4]
      reuse = [] of Int32
      combs = a.combinations(2)
      iter = a.each_combination(2, reuse: reuse)
      combs.each do |comb|
        b = iter.next
        b.should be(reuse)
        b.should eq(comb)
      end
      iter.next.should be_a(Iterator::Stop)
    end
  end

  describe "repeated_combinations" do
    it { [1, 2, 2].repeated_combinations.should eq([[1, 1, 1], [1, 1, 2], [1, 1, 2], [1, 2, 2], [1, 2, 2], [1, 2, 2], [2, 2, 2], [2, 2, 2], [2, 2, 2], [2, 2, 2]]) }
    it { SafeIndexable.new(3, 1).repeated_combinations.should eq([[1, 1, 1], [1, 1, 2], [1, 1, 3], [1, 2, 2], [1, 2, 3], [1, 3, 3], [2, 2, 2], [2, 2, 3], [2, 3, 3], [3, 3, 3]]) }
    it { SafeIndexable.new(3, 1).repeated_combinations(1).should eq([[1], [2], [3]]) }
    it { SafeIndexable.new(3, 1).repeated_combinations(2).should eq([[1, 1], [1, 2], [1, 3], [2, 2], [2, 3], [3, 3]]) }
    it { SafeIndexable.new(3, 1).repeated_combinations(3).should eq([[1, 1, 1], [1, 1, 2], [1, 1, 3], [1, 2, 2], [1, 2, 3], [1, 3, 3], [2, 2, 2], [2, 2, 3], [2, 3, 3], [3, 3, 3]]) }
    it { SafeIndexable.new(3, 1).repeated_combinations(0).should eq([[] of Int32]) }
    it { SafeIndexable.new(3, 1).repeated_combinations(4).should eq([[1, 1, 1, 1], [1, 1, 1, 2], [1, 1, 1, 3], [1, 1, 2, 2], [1, 1, 2, 3], [1, 1, 3, 3], [1, 2, 2, 2], [1, 2, 2, 3], [1, 2, 3, 3], [1, 3, 3, 3], [2, 2, 2, 2], [2, 2, 2, 3], [2, 2, 3, 3], [2, 3, 3, 3], [3, 3, 3, 3]]) }
    it { expect_raises(ArgumentError, "Size must be positive") { [1].repeated_combinations(-1) } }

    it "accepts a block" do
      sums = [] of Int32
      SafeIndexable.new(3, 1).each_repeated_combination(2) do |comb|
        sums << comb.sum
      end.should be_nil
      sums.should eq([2, 3, 4, 4, 5, 6])
    end

    it "yielding dup of arrays" do
      sums = [] of Int32
      SafeIndexable.new(3, 1).each_repeated_combination(3) do |comb|
        comb.map! &.+(1)
        sums << comb.sum
      end.should be_nil
      sums.should eq([6, 7, 8, 8, 9, 10, 9, 10, 11, 12])
    end

    it { expect_raises(ArgumentError, "Size must be positive") { [1].each_repeated_combination(-1) { } } }

    it "yields with reuse = true" do
      sums = [] of Int32
      object_ids = Set(UInt64).new
      SafeIndexable.new(3, 1).each_repeated_combination(3, reuse: true) do |comb|
        object_ids << comb.object_id
        comb.map! &.+(1)
        sums << comb.sum
      end.should be_nil
      sums.should eq([6, 7, 8, 8, 9, 10, 9, 10, 11, 12])
      object_ids.size.should eq(1)
    end

    it "yields with reuse = array" do
      sums = [] of Int32
      reuse = [] of Int32
      SafeIndexable.new(3, 1).each_repeated_combination(3, reuse: reuse) do |comb|
        comb.should be(reuse)
        comb.map! &.+(1)
        sums << comb.sum
      end.should be_nil
      sums.should eq([6, 7, 8, 8, 9, 10, 9, 10, 11, 12])
    end

    it "returns iterator" do
      a = [1, 2, 3, 4]
      combs = a.repeated_combinations(2)
      iter = a.each_repeated_combination(2)
      combs.each do |comb|
        iter.next.should eq(comb)
      end
      iter.next.should be_a(Iterator::Stop)
    end

    it "returns iterator with reuse = true" do
      a = [1, 2, 3, 4]
      object_ids = Set(UInt64).new
      combs = a.repeated_combinations(2)
      iter = a.each_repeated_combination(2, reuse: true)
      combs.each do |comb|
        b = iter.next
        object_ids << b.object_id
        b.should eq(comb)
      end
      iter.next.should be_a(Iterator::Stop)
      object_ids.size.should eq(1)
    end

    it "returns iterator with reuse = array" do
      a = [1, 2, 3, 4]
      reuse = [] of Int32
      combs = a.repeated_combinations(2)
      iter = a.each_repeated_combination(2, reuse: reuse)
      combs.each do |comb|
        b = iter.next
        b.should be(reuse)
        b.should eq(comb)
      end
      iter.next.should be_a(Iterator::Stop)
    end

    describe "n > size (#14088)" do
      it_iterates "#each_repeated_combination", [[1, 1, 1], [1, 1, 2], [1, 2, 2], [2, 2, 2]], SafeIndexable.new(2, 1).each_repeated_combination(3)
      it_iterates "#each_repeated_combination", [[1, 1, 1, 1], [1, 1, 1, 2], [1, 1, 2, 2], [1, 2, 2, 2], [2, 2, 2, 2]], SafeIndexable.new(2, 1).each_repeated_combination(4)
    end
  end

  describe "#to_a" do
    it "without a block of an interface type" do
      InterfaceIndexable.new.to_a.should eq [Three.new, Four.new]
    end
  end
end
