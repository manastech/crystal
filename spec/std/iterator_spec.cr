require "spec"
require "spec/helpers/iterate"
require "iterator"

struct StructIter
  include Iterator(Int32)

  def initialize(@a : Int32, @b : Int32); end

  def next
    if @a > @b
      stop
    else
      cur = @a
      @a += 1
      cur
    end
  end
end

private class MockIterator
  include Iterator(Int32)

  def initialize
    @x = 0
    @y = Slice(Int32).new(5)
  end

  def next
    return stop if @x >= 3
    @x += 1
  end
end

describe Iterator do
  describe "Iterator.empty" do
    it "creates empty iterator" do
      iter = Iterator(String).empty
      iter.next.should be_a(Iterator::Stop)
    end
  end

  describe "Iterator.of" do
    it "creates singleton" do
      iter = Iterator.of(42)
      iter.first(3).to_a.should eq([42, 42, 42])
    end

    it "creates singleton from block" do
      a = 0
      iter = Iterator.of { a += 1 }
      iter.first(3).to_a.should eq([1, 2, 3])
    end

    it "creates singleton from block can call Iterator.stop" do
      a = 0
      iter = Iterator.of do
        if a >= 5
          Iterator.stop
        else
          a += 1
        end
      end
      iter.should be_a(Iterator(Int32))
      iter.first(10).to_a.should eq([1, 2, 3, 4, 5])
    end
  end

  describe "#accumulate" do
    context "prefix sums" do
      it "returns prefix sums" do
        iter = (1..4).each.accumulate
        iter.next.should eq(1)
        iter.next.should eq(3)
        iter.next.should eq(6)
        iter.next.should eq(10)
        iter.next.should be_a(Iterator::Stop)
      end

      it "empty iterator stops immediately" do
        (1..0).each.accumulate.next.should be_a(Iterator::Stop)
      end
    end

    context "prefix sums, with init" do
      it "returns prefix sums" do
        iter = (1..4).each.accumulate(5)
        iter.next.should eq(5)
        iter.next.should eq(6)
        iter.next.should eq(8)
        iter.next.should eq(11)
        iter.next.should eq(15)
        iter.next.should be_a(Iterator::Stop)
      end

      it "preserves initial type" do
        iter = {'a', 'b', 'c'}.each.accumulate("def")
        iter.next.should eq("def")
        iter.next.should eq("defa")
        iter.next.should eq("defab")
        iter.next.should eq("defabc")
        iter.next.should be_a(Iterator::Stop)
      end

      it "empty iterator returns only initial value" do
        iter = (1..0).each.accumulate(7)
        iter.next.should eq(7)
        iter.next.should be_a(Iterator::Stop)
      end
    end

    context "generic cumulative fold" do
      it "accumulates values" do
        iter = (4..7).each.accumulate { |x, y| x * 10 + y }
        iter.next.should eq(4)
        iter.next.should eq(45)
        iter.next.should eq(456)
        iter.next.should eq(4567)
        iter.next.should be_a(Iterator::Stop)
      end

      it "empty iterator stops immediately" do
        (1..0).each.accumulate { raise "" }.next.should be_a(Iterator::Stop)
      end
    end

    context "generic cumulative fold, with init" do
      it "accumulates values" do
        iter = (4..7).each.accumulate(8) { |x, y| x * 10 + y }
        iter.next.should eq(8)
        iter.next.should eq(84)
        iter.next.should eq(845)
        iter.next.should eq(8456)
        iter.next.should eq(84567)
        iter.next.should be_a(Iterator::Stop)
      end

      it "preserves initial type" do
        iter = {4, 3, 2}.each.accumulate("X") { |x, y| x * y }
        iter.next.should eq("X")
        iter.next.should eq("XXXX")
        iter.next.should eq("XXXXXXXXXXXX")
        iter.next.should eq("XXXXXXXXXXXXXXXXXXXXXXXX")
        iter.next.should be_a(Iterator::Stop)
      end

      it "empty iterator returns only initial value" do
        iter = (1..0).each.accumulate(7) { raise "" }
        iter.next.should eq(7)
        iter.next.should be_a(Iterator::Stop)
      end
    end
  end

  describe "compact_map" do
    it "applies the function and removes nil values" do
      assert_iterates_iterator [1, 3], (1..3).each.compact_map { |e| e.odd? ? e : nil }
    end

    it "sums after compact_map to_a" do
      (1..3).each.compact_map { |e| e.odd? ? e : nil }.to_a.sum.should eq(4)
    end
  end

  describe "chain" do
    it "chains" do
      iter = (1..2).each.chain(('a'..'b').each)
      iter.next.should eq(1)
      iter.next.should eq(2)
      iter.next.should eq('a')
      iter.next.should eq('b')
      iter.next.should be_a(Iterator::Stop)
    end

    # NOTE: This spec would only fail in release mode.
    it "does not experience tuple upcase bug of #13411" do
      [{true}].each.chain([{1}].each).first(3).to_a.should eq [{true}, {1}]
    end

    describe "chain indeterminate number of iterators" do
      it "chains all together" do
        iters = [[0], [1], [2, 3], [4, 5, 6]].each.map &.each
        iter = Iterator.chain iters
        7.times { |i| iter.next.should eq i }
        iter.next.should be_a Iterator::Stop
      end

      it "chains empty" do
        arrs = [] of Array(Int32)
        iter = Iterator.chain arrs.map(&.each)
        iter.next.should be_a Iterator::Stop
      end

      it "chains array of empty" do
        iters = [[0], [1], ([] of Int32), [2, 3], ([] of Int32), [4, 5, 6]].each.map &.each
        iter = Iterator.chain iters
        7.times { |i| iter.next.should eq i }
        iter.next.should be_a Iterator::Stop
      end

      it "rewinds" do
        iters = [[0], [1], ([] of Int32), [2, 3], ([] of Int32), [4, 5, 6]].each.map &.each
        iter = Iterator.chain iters
        7.times { |i| iter.next.should eq i }
        iter.next.should be_a Iterator::Stop
      end

      it "chains iterators of different type" do
        iters = [[1, 2], ["string"], ["and number", 3], [] of String,
                 ["or float", 4.0_f64]].each.map &.each
        iter = Iterator.chain iters
        iter.next.should eq 1
        iter.next.should eq 2
        iter.next.should eq "string"
        iter.next.should eq "and number"
        iter.next.should eq 3
        iter.next.should eq "or float"
        iter.next.should eq 4.0_f64
        iter.next.should be_a Iterator::Stop
      end
    end
  end

  describe "compact_map" do
    it "does not return nil values" do
      iter = [1, nil, 2, nil].each.compact_map { |e| e.try &.*(2) }
      iter.next.should eq 2
      iter.next.should eq 4
      iter.next.should be_a(Iterator::Stop)
    end
  end

  describe "#cons" do
    it "conses" do
      iter = (1..5).each.cons(3)
      iter.next.should eq([1, 2, 3])
      iter.next.should eq([2, 3, 4])
      iter.next.should eq([3, 4, 5])
      iter.next.should be_a(Iterator::Stop)
    end

    describe "reuse" do
      it "reuse as nil" do
        iter = (1..5).each.cons(3, reuse: nil)
        first = iter.next
        first.should eq([1, 2, 3])
        second = iter.next
        second.should eq([2, 3, 4])
        first.should_not be(second)
        iter.next.should eq([3, 4, 5])
        iter.next.should be_a(Iterator::Stop)
      end

      it "reuse as Bool" do
        iter = (1..5).each.cons(3, reuse: true)
        first = iter.next
        first.should eq([1, 2, 3])
        second = iter.next
        second.should eq([2, 3, 4])
        first.should be(second)
        iter.next.should eq([3, 4, 5])
        iter.next.should be_a(Iterator::Stop)
      end

      it "reuse as Array" do
        reuse = [] of Int32
        iter = (1..5).each.cons(3, reuse: reuse)
        value = iter.next
        value.should be(reuse)
        value.should eq([1, 2, 3])
        value = iter.next
        value.should be(reuse)
        value.should eq([2, 3, 4])
        value = iter.next
        value.should be(reuse)
        value.should eq([3, 4, 5])
        iter.next.should be_a(Iterator::Stop)
      end

      it "reuse as deque" do
        reuse = Deque(Int32).new
        iter = (1..5).each.cons(3, reuse: reuse)
        value = iter.next
        value.should be(reuse)
        value.should eq(Deque{1, 2, 3})
        value = iter.next
        value.should be(reuse)
        value.should eq(Deque{2, 3, 4})
        value = iter.next
        value.should be(reuse)
        value.should eq(Deque{3, 4, 5})
        iter.next.should be_a(Iterator::Stop)
      end
    end
  end

  describe "#cons_pair" do
    it "conses" do
      iter = (1..5).each.cons_pair
      iter.next.should eq({1, 2})
      iter.next.should eq({2, 3})
      iter.next.should eq({3, 4})
      iter.next.should eq({4, 5})
      iter.next.should be_a(Iterator::Stop)
    end

    it "doesn't include stop in return type" do
      (1..3).each.cons_pair.to_a.should eq([{1, 2}, {2, 3}])
    end
  end

  describe "cycle" do
    it "does cycle from range" do
      iter = (1..3).each.cycle
      iter.next.should eq(1)
      iter.next.should eq(2)
      iter.next.should eq(3)
      iter.next.should eq(1)
      iter.next.should eq(2)
    end

    it "cycles an empty array" do
      ary = [] of Int32
      values = ary.each.cycle.to_a
      values.should be_empty
    end

    it "cycles N times" do
      iter = (1..2).each.cycle(2)
      iter.next.should eq(1)
      iter.next.should eq(2)
      iter.next.should eq(1)
      iter.next.should eq(2)
      iter.next.should be_a(Iterator::Stop)
    end

    it "does not cycle provided 0" do
      iter = (1..2).each.cycle(0)
      iter.next.should be_a(Iterator::Stop)
    end

    it "does not cycle provided a negative size" do
      iter = (1..2).each.cycle(-1)
      iter.next.should be_a(Iterator::Stop)
    end
  end

  describe "each" do
    it "yields the individual elements to the block" do
      iter = ["a", "b", "c"].each
      concatenated = ""
      iter.each { |e| concatenated += e }.should be_nil
      concatenated.should eq "abc"
    end
  end

  describe "each_slice" do
    it "gets all the slices of the size n" do
      iter = (1..9).each.each_slice(3)
      iter.next.should eq [1, 2, 3]
      iter.next.should eq [4, 5, 6]
      iter.next.should eq [7, 8, 9]
      iter.next.should be_a Iterator::Stop
    end

    it "also works if it does not add up" do
      iter = (1..4).each.each_slice(3)
      iter.next.should eq [1, 2, 3]
      iter.next.should eq [4]
      iter.next.should be_a Iterator::Stop
    end

    it "returns each_slice iterator with reuse = true" do
      iter = (1..5).each.each_slice(2, reuse: true)

      a = iter.next
      a.should eq([1, 2])

      b = iter.next
      b.should eq([3, 4])
      b.should be(a)
    end

    it "returns each_slice iterator with reuse = array" do
      reuse = [] of Int32
      iter = (1..5).each.each_slice(2, reuse: reuse)

      a = iter.next
      a.should eq([1, 2])
      a.should be(reuse)

      b = iter.next
      b.should eq([3, 4])
      b.should be(reuse)
    end
  end

  describe "in_groups_of" do
    it "creates groups of one" do
      iter = (1..3).each.in_groups_of(1)
      iter.next.should eq([1])
      iter.next.should eq([2])
      iter.next.should eq([3])
      iter.next.should be_a(Iterator::Stop)
    end

    it "creates a group of two" do
      iter = (1..3).each.in_groups_of(2)
      iter.next.should eq([1, 2])
      iter.next.should eq([3, nil])
      iter.next.should be_a(Iterator::Stop)
    end

    it "fills up with the fill up argument" do
      iter = (1..3).each.in_groups_of(2, 'z')
      iter.next.should eq([1, 2])
      iter.next.should eq([3, 'z'])
      iter.next.should be_a(Iterator::Stop)
    end

    it "raises argument error if size is less than 0" do
      expect_raises ArgumentError, "Size must be positive" do
        [1, 2, 3].each.in_groups_of(0)
      end
    end

    it "still works with other iterator methods like to_a" do
      iter = (1..3).each.in_groups_of(2, 'z')
      iter.to_a.should eq [[1, 2], [3, 'z']]
    end

    it "creates a group of two with reuse = true" do
      iter = (1..3).each.in_groups_of(2, reuse: true)

      a = iter.next
      a.should eq([1, 2])

      b = iter.next
      b.should eq([3, nil])
      b.should be(a)

      iter.next.should be_a(Iterator::Stop)
    end
  end

  describe "map" do
    it "does map with Range iterator" do
      iter = (1..3).each.map &.*(2)
      iter.next.should eq(2)
      iter.next.should eq(4)
      iter.next.should eq(6)
      iter.next.should be_a(Iterator::Stop)
    end
  end

  describe "reject" do
    it "does reject with Range iterator" do
      iter = (1..3).each.reject &.>=(2)
      iter.next.should eq(1)
      iter.next.should be_a(Iterator::Stop)
    end

    it "does with pattern" do
      iter = (1..5).each.reject(2..4)
      iter.next.should eq(1)
      iter.next.should eq(5)
      iter.next.should be_a(Iterator::Stop)
    end

    it "does with type" do
      ary = [1, false, 3, true].each.reject(Bool).to_a
      ary.should eq([1, 3])
      ary.should be_a(Array(Int32))
    end
  end

  describe "select" do
    it "does select with Range iterator" do
      iter = (1..3).each.select &.>=(2)
      iter.next.should eq(2)
      iter.next.should eq(3)
      iter.next.should be_a(Iterator::Stop)
    end

    it "does with pattern" do
      iter = (1..10).each.select(3..5)
      iter.next.should eq(3)
      iter.next.should eq(4)
      iter.next.should eq(5)
      iter.next.should be_a(Iterator::Stop)
    end

    it "does with type" do
      ary = [1, nil, 3, false].each.select(Int32).to_a
      ary.should eq([1, 3])
      ary.should be_a(Array(Int32))
    end
  end

  describe "skip" do
    it "does skip with Range iterator" do
      iter = (1..3).each.skip(2)
      iter.next.should eq(3)
      iter.next.should be_a(Iterator::Stop)
    end

    it "is cool to skip 0 elements" do
      (1..3).each.skip(0).to_a.should eq [1, 2, 3]
    end

    it "raises ArgumentError if negative size is provided" do
      expect_raises(ArgumentError) do
        (1..3).each.skip(-1)
      end
    end
  end

  describe "skip_while" do
    it "does skip_while with an array" do
      iter = [1, 2, 3, 4, 0].each.skip_while { |i| i < 3 }
      iter.next.should eq(3)
      iter.next.should eq(4)
      iter.next.should eq(0)
      iter.next.should be_a(Iterator::Stop)
    end

    it "can skip everything" do
      iter = (1..3).each.skip_while { true }
      iter.to_a.should eq [] of Int32
    end

    it "returns the full array if the condition is false for the first item" do
      iter = (1..2).each.skip_while { false }
      iter.to_a.should eq [1, 2]
    end

    it "only calls the block as much as needed" do
      called = 0
      iter = (1..5).each.skip_while do |i|
        called += 1
        i < 3
      end
      5.times { iter.next }
      called.should eq 3
    end
  end

  describe "slice" do
    it "slices" do
      iter = (1..8).each.slice(3)
      iter.next.should eq([1, 2, 3])
      iter.next.should eq([4, 5, 6])
      iter.next.should eq([7, 8])
      iter.next.should be_a(Iterator::Stop)
    end

    it "doesnt conflict with `::Slice` type" do
      assert_iterates_iterator [1, 2, 3], MockIterator.new.each
    end
  end

  describe "step" do
    it "returns every element" do
      iter = (1..3).each.step(1)
      iter.next.should eq(1)
      iter.next.should eq(2)
      iter.next.should eq(3)
      iter.next.should be_a(Iterator::Stop)
    end

    it "returns every other element" do
      iter = (1..5).each.step(2)
      iter.next.should eq(1)
      iter.next.should eq(3)
      iter.next.should eq(5)
      iter.next.should be_a(Iterator::Stop)
    end

    it "returns every third element" do
      iter = (1..12).each.step(3)
      iter.next.should eq(1)
      iter.next.should eq(4)
      iter.next.should eq(7)
      iter.next.should eq(10)
      iter.next.should be_a(Iterator::Stop)
    end

    it "raises with nonsensical steps" do
      expect_raises(ArgumentError) do
        (1..2).each.step(0)
      end

      expect_raises(ArgumentError) do
        (1..2).each.step(-1)
      end
    end
  end

  describe "first" do
    it "does first with Range iterator" do
      iter = (1..3).each.first(2)
      iter.next.should eq(1)
      iter.next.should eq(2)
      iter.next.should be_a(Iterator::Stop)
    end

    it "does first with more than available" do
      (1..3).each.first(10).to_a.should eq([1, 2, 3])
    end

    it "is cool to first 0 elements" do
      iter = (1..3).each.first(0)
      iter.next.should be_a Iterator::Stop
    end

    it "raises ArgumentError if negative size is provided" do
      expect_raises(ArgumentError) do
        (1..3).each.first(-1)
      end
    end
  end

  describe "take_while" do
    it "does take_while with Range iterator" do
      iter = (1..5).each.take_while { |i| i < 3 }
      iter.next.should eq(1)
      iter.next.should eq(2)
      iter.next.should be_a(Iterator::Stop)
    end

    it "does take_while with more than available" do
      (1..3).each.take_while { true }.to_a.should eq([1, 2, 3])
    end

    it "only calls the block as much as needed" do
      called = 0
      iter = (1..5).each.take_while do |i|
        called += 1
        i < 3
      end
      5.times { iter.next }
      called.should eq 3
    end
  end

  describe "tap" do
    it "taps" do
      a = 0

      iter = (1..3).each.tap { |x| a += x }
      iter.next.should eq(1)
      a.should eq(1)

      iter.next.should eq(2)
      a.should eq(3)

      iter.next.should eq(3)
      a.should eq(6)

      iter.next.should be_a(Iterator::Stop)
    end
  end

  describe "uniq" do
    it "without block" do
      iter = (1..8).each.map { |x| x % 3 }.uniq
      iter.next.should eq(1)
      iter.next.should eq(2)
      iter.next.should eq(0)
      iter.next.should be_a(Iterator::Stop)
    end

    it "with block" do
      iter = (1..8).each.uniq { |x| (x % 3).to_s }
      iter.next.should eq(1)
      iter.next.should eq(2)
      iter.next.should eq(3)
      iter.next.should be_a(Iterator::Stop)
    end
  end

  describe "#with_index" do
    it_iterates "with default offset", [{1, 0}, {2, 1}, {3, 2}], (1..3).each.with_index, tuple: true
    it_iterates "with explicit offset", [{1, 10}, {2, 11}, {3, 12}], (1..3).each.with_index(10), tuple: true
    it_iterates "with non-Int32 offset", [{1, Int64::MIN}, {2, Int64::MIN + 1}, {3, Int64::MIN + 2}], (1..3).each.with_index(Int64::MIN), tuple: true
  end

  describe "with object" do
    it "does with object" do
      iter = (1..3).each.with_object("a")
      iter.next.should eq({1, "a"})
      iter.next.should eq({2, "a"})
      iter.next.should eq({3, "a"})
      iter.next.should be_a(Iterator::Stop)
    end

    it "does with object, with block" do
      tuples = [] of {Int32, String}
      object = "a"
      (1..3).each.with_object(object) do |value, obj|
        tuples << {value, obj}
      end.should be(object)
      tuples.should eq([{1, object}, {2, object}, {3, object}])
    end
  end

  describe "zip" do
    it "does skip with Range iterator" do
      r1 = (1..3).each
      r2 = ('a'..'c').each
      iter = r1.zip(r2)
      iter.next.should eq({1, 'a'})
      iter.next.should eq({2, 'b'})
      iter.next.should eq({3, 'c'})
      iter.next.should be_a(Iterator::Stop)
    end

    it "takes multiple Iterators" do
      r1 = (1..4).each
      r2 = ('a'..'c').each
      r3 = ("U".."Z").each
      iter = r1.zip(r2, r3)
      iter.next.should eq({1, 'a', "U"})
      iter.next.should eq({2, 'b', "V"})
      iter.next.should eq({3, 'c', "W"})
      iter.next.should be_a(Iterator::Stop)
    end
  end

  describe "integration" do
    it "combines many iterators" do
      (1..100).each
        .select { |x| 50 <= x < 60 }
        .map { |x| x * 2 }
        .first(3)
        .to_a
        .should eq([100, 102, 104])
    end
  end

  describe "flatten" do
    it "flattens an iterator of mixed-type iterators" do
      iter = [(1..2).each, ('a'..'b').each, {"c" => 3}.each].each.flatten

      iter.next.should eq(1)
      iter.next.should eq(2)
      iter.next.should eq('a')
      iter.next.should eq('b')
      iter.next.should eq({"c", 3})

      iter.next.should be_a(Iterator::Stop)
    end

    it "flattens an iterator of mixed-type elements and iterators" do
      iter = [(1..2).each, 'a'].each.flatten

      iter.next.should eq(1)
      iter.next.should eq(2)
      iter.next.should eq('a')

      iter.next.should be_a(Iterator::Stop)
    end

    it "flattens an iterator of mixed-type elements and iterators and iterators of iterators" do
      iter = [(1..2).each, [['a', 'b'].each].each, "foo"].each.flatten

      iter.next.should eq(1)
      iter.next.should eq(2)
      iter.next.should eq('a')
      iter.next.should eq('b')
      iter.next.should eq("foo")

      iter.next.should be_a(Iterator::Stop)
    end

    it "flattens deeply-nested and mixed type iterators" do
      iter = [[[1], 2], [3, [[4, 5], 6], 7], "a"].each.flatten

      iter.next.should eq(1)
      iter.next.should eq(2)
      iter.next.should eq(3)
      iter.next.should eq(4)
      iter.next.should eq(5)
      iter.next.should eq(6)
      iter.next.should eq(7)
      iter.next.should eq("a")

      iter.next.should be_a(Iterator::Stop)
    end

    it "flattens a variety of edge cases" do
      ([] of Nil).each.flatten.to_a.should eq([] of Nil)
      ['a'].each.flatten.to_a.should eq(['a'])
      [[[[[["hi"]]]]]].each.flatten.to_a.should eq(["hi"])
    end

    it "flattens a deeply-nested iterables and arrays (#3703)" do
      iter = [[1, {2, 3}, 4], [{5 => 6}, 7]].each.flatten

      iter.next.should eq(1)
      iter.next.should eq({2, 3})
      iter.next.should eq(4)
      iter.next.should eq({5 => 6})
      iter.next.should eq(7)
      iter.next.should be_a(Iterator::Stop)
    end

    it "flattens nested struct iterators with internal state being value types" do
      iter = (1..2).each.map { |i| StructIter.new(10 * i + 1, 10 * i + 3) }.flatten

      iter.next.should eq(11)
      iter.next.should eq(12)
      iter.next.should eq(13)
      iter.next.should eq(21)
      iter.next.should eq(22)
      iter.next.should eq(23)
      iter.next.should be_a(Iterator::Stop)
    end

    it "return iterator itself by rewind" do
      iter = [1, [2, 3], 4].each.flatten

      iter.to_a.should eq([1, 2, 3, 4])
    end
  end

  describe "#flat_map" do
    it "flattens returned arrays" do
      iter = [1, 2, 3].each.flat_map { |x| [x, x] }

      iter.next.should eq(1)
      iter.next.should eq(1)
      iter.next.should eq(2)
      iter.next.should eq(2)
      iter.next.should eq(3)
      iter.next.should eq(3)
      iter.next.should be_a(Iterator::Stop)
    end

    it "flattens returned items" do
      iter = [1, 2, 3].each.flat_map { |x| x }

      iter.next.should eq(1)
      iter.next.should eq(2)
      iter.next.should eq(3)
      iter.next.should be_a(Iterator::Stop)
    end

    it "flattens returned iterators" do
      iter = [1, 2, 3].each.flat_map { |x| [x, x].each }

      iter.next.should eq(1)
      iter.next.should eq(1)
      iter.next.should eq(2)
      iter.next.should eq(2)
      iter.next.should eq(3)
      iter.next.should eq(3)
      iter.next.should be_a(Iterator::Stop)
    end

    it "flattens returned values" do
      iter = [1, 2, 3].each.flat_map do |x|
        case x
        when 1
          x
        when 2
          [x, x]
        else
          [x, x].each
        end
      end

      iter.next.should eq(1)
      iter.next.should eq(2)
      iter.next.should eq(2)
      iter.next.should eq(3)
      iter.next.should eq(3)
      iter.next.should be_a(Iterator::Stop)
    end

    it "flattens returned values of mixed element types in #to_a" do
      iter = [1, 'a', ""].each.flat_map do |x|
        case x
        when Int32
          x
        when Char
          [x, x]
        else
          [x, x].each
        end
      end
      iter.to_a.should eq([1, 'a', 'a', "", ""])
    end
  end

  describe "#slice_after" do
    it "slices after" do
      ary = [1, 3, 5, 8, 10, 11, 13, 15, 16, 17]
      iter = ary.slice_after(&.even?)
      iter.next.should eq([1, 3, 5, 8])
      iter.next.should eq([10])
      iter.next.should eq([11, 13, 15, 16])
      iter.next.should eq([17])
      iter.next.should be_a(Iterator::Stop)
    end

    it "slices after: #to_a" do
      ary = [1, 3, 5, 8, 10, 11, 13, 15, 16, 17]
      ary.slice_after(&.even?).to_a.should eq([
        [1, 3, 5, 8],
        [10],
        [11, 13, 15, 16],
        [17],
      ])
    end

    it "slices after: #rewind" do
      ary = [1, 3, 5, 8, 10, 11, 13, 15, 16, 17]
      iter = ary.slice_after(&.even?)
      iter.next.should eq([1, 3, 5, 8])
      iter.next.should eq([10])
    end

    it "slices after with reuse = true" do
      ary = [1, 3, 5, 8, 10, 11, 13, 15, 16, 17]
      iter = ary.slice_after(reuse: true, &.even?)
      a = iter.next
      a.should eq([1, 3, 5, 8])

      b = iter.next
      b.should eq([10])

      a.should be(b)
    end

    it "slices after with reuse = array" do
      reuse = [] of Int32
      ary = [1, 3, 5, 8, 10, 11, 13, 15, 16, 17]
      iter = ary.slice_after(reuse: reuse, &.even?)
      a = iter.next
      a.should eq([1, 3, 5, 8])

      b = iter.next
      b.should eq([10])

      a.should be(b)
      a.should be(reuse)
    end

    it "slices after: non-bool block" do
      ary = [1, nil, nil, 2, 3, nil]
      iter = ary.slice_after(&.itself)
      iter.next.should eq([1])
      iter.next.should eq([nil, nil, 2])
      iter.next.should eq([3])
      iter.next.should eq([nil])
      iter.next.should be_a(Iterator::Stop)
    end

    it "slices after pattern" do
      ary = ["foo", "bar", "baz\n", "qux", "other\n", "end"]
      iter = ary.slice_after(/\n/)
      iter.next.should eq(["foo", "bar", "baz\n"])
      iter.next.should eq(["qux", "other\n"])
      iter.next.should eq(["end"])
      iter.next.should be_a(Iterator::Stop)
    end

    it "slices after pattern with reuse = true" do
      ary = ["foo", "bar", "baz\n", "qux", "other\n", "end"]
      iter = ary.slice_after(/\n/, reuse: true)

      a = iter.next
      a.should eq(["foo", "bar", "baz\n"])

      b = iter.next
      b.should eq(["qux", "other\n"])

      a.should be(b)
    end
  end

  describe "#slice_before" do
    it "slices before" do
      ary = [1, 3, 5, 8, 10, 11, 13, 15, 16, 17]
      iter = ary.slice_before(&.even?)
      iter.next.should eq([1, 3, 5])
      iter.next.should eq([8])
      iter.next.should eq([10, 11, 13, 15])
      iter.next.should eq([16, 17])
      iter.next.should be_a(Iterator::Stop)
    end

    it "slices before: first element matches" do
      ary = [2, 3, 4]
      iter = ary.slice_before(&.even?)
      iter.next.should eq([2, 3])
      iter.next.should eq([4])
      iter.next.should be_a(Iterator::Stop)
    end

    it "slices before nil" do
      ary = [1, 2, nil, 3, nil]
      iter = ary.slice_before(&.nil?)
      iter.next.should eq([1, 2])
      iter.next.should eq([nil, 3])
      iter.next.should eq([nil])
      iter.next.should be_a(Iterator::Stop)
    end

    it "slices before: #to_a" do
      ary = [1, 3, 5, 8, 10, 11, 13, 15, 16, 17]
      ary.slice_before(&.even?).to_a.should eq([
        [1, 3, 5],
        [8],
        [10, 11, 13, 15],
        [16, 17],
      ])
    end

    it "slices before: #rewind" do
      ary = [1, 3, 5, 8, 10, 11, 13, 15, 16, 17]
      iter = ary.slice_before(&.even?)
      iter.next.should eq([1, 3, 5])
      iter.next.should eq([8])
    end

    it "slices before with reuse = true" do
      ary = [1, 3, 5, 8, 10, 11, 13, 15, 16, 17]
      iter = ary.slice_before(reuse: true, &.even?)
      a = iter.next
      a.should eq([1, 3, 5])

      b = iter.next
      b.should eq([8])

      a.should be(b)
    end

    it "slices before with reuse = array" do
      reuse = [] of Int32
      ary = [1, 3, 5, 8, 10, 11, 13, 15, 16, 17]
      iter = ary.slice_before(reuse: reuse, &.even?)
      a = iter.next
      a.should eq([1, 3, 5])

      b = iter.next
      b.should eq([8])

      a.should be(b)
      a.should be(reuse)
    end

    it "slices before: non-bool block" do
      ary = [1, nil, nil, 2, 3, nil]
      iter = ary.slice_before(&.itself)
      iter.next.should eq([1, nil, nil])
      iter.next.should eq([2])
      iter.next.should eq([3, nil])
    end

    it "slices before pattern" do
      ary = ["foo", "bar", "baz\n", "qux", "other\n", "end"]
      iter = ary.slice_before(/\n/)
      iter.next.should eq(["foo", "bar"])
      iter.next.should eq(["baz\n", "qux"])
      iter.next.should eq(["other\n", "end"])
      iter.next.should be_a(Iterator::Stop)
    end

    it "slices before pattern with reuse = true" do
      ary = ["foo", "bar", "baz\n", "qux", "other\n", "end"]
      iter = ary.slice_before(/\n/, reuse: true)

      a = iter.next
      a.should eq(["foo", "bar"])

      b = iter.next
      b.should eq(["baz\n", "qux"])

      a.should be(b)
    end
  end

  describe "#slice_when" do
    it "slices when" do
      ary = [1, 1, 1, 2, 2, 3, 4, 4]
      iter = ary.slice_when { |x, y| x != y }
      iter.next.should eq([1, 1, 1])
      iter.next.should eq([2, 2])
      iter.next.should eq([3])
      iter.next.should eq([4, 4])
      iter.next.should be_a(Iterator::Stop)
    end

    it "slices when: single value" do
      ary = [1]
      iter = ary.slice_when { |x, y| x != y }
      iter.next.should eq([1])
      iter.next.should be_a(Iterator::Stop)
    end

    it "slices when: two values" do
      ary = [1, 2]
      iter = ary.slice_when { |x, y| x != y }
      iter.next.should eq([1])
      iter.next.should eq([2])
      iter.next.should be_a(Iterator::Stop)
    end

    it "slices when: #to_a" do
      ary = [1, 1, 1, 2, 2, 3, 4, 4]
      ary.slice_when { |x, y| x != y }.to_a.should eq([
        [1, 1, 1],
        [2, 2],
        [3],
        [4, 4],
      ])
    end

    it "slices when: #rewind" do
      ary = [1, 1, 1, 2, 2, 3, 4, 4]
      iter = ary.slice_when { |x, y| x != y }
      iter.next.should eq([1, 1, 1])
      iter.next.should eq([2, 2])
    end

    it "slices when with reuse = true" do
      ary = [1, 1, 1, 2, 2, 3, 4, 4]
      iter = ary.slice_when(reuse: true) { |x, y| x != y }
      a = iter.next
      a.should eq([1, 1, 1])

      b = iter.next
      b.should eq([2, 2])

      a.should be(b)
    end

    it "slices when with reuse = array" do
      reuse = [] of Int32
      ary = [1, 1, 1, 2, 2, 3, 4, 4]
      iter = ary.slice_when(reuse) { |x, y| x != y }
      a = iter.next
      a.should eq([1, 1, 1])

      b = iter.next
      b.should eq([2, 2])

      a.should be(b)
      a.should be(reuse)
    end

    it "slices when: non-bool block" do
      ary = [1, 2, nil, 3, nil, nil, 4]
      ary.slice_when { |x, y| y }.to_a.should eq([
        [1],
        [2, nil],
        [3, nil, nil],
        [4],
      ])
    end
  end

  describe "#chunk_while" do
    it "chunks while" do
      ary = [1, 1, 1, 2, 2, 3, 4, 4]
      iter = ary.chunk_while { |x, y| x == y }
      iter.next.should eq([1, 1, 1])
      iter.next.should eq([2, 2])
      iter.next.should eq([3])
      iter.next.should eq([4, 4])
      iter.next.should be_a(Iterator::Stop)
    end
  end

  describe "reference semantics (#12975)" do
    it "#cycle" do
      ary = [1, 2, 3]
      iter1 = ary.each.cycle
      iter2 = iter1
      iter1.next
      iter1.next
      iter1.next
      iter2.next.should eq(1)
      iter1.next.should eq(2)
      iter2.next.should eq(3)
    end

    it "#cons_pair" do
      ary = [1, 2, 3]
      iter1 = ary.each.cons_pair
      iter2 = iter1
      iter1.next
      iter2.next.should eq({2, 3})
      iter1.next.should be_a(Iterator::Stop)
    end

    it "#flatten" do
      ary = [(1..2).each, ('a'..'b').each]
      iter1 = ary.each.flatten
      iter2 = iter1
      iter1.next
      iter2.next.should eq(2)
      iter1.next.should eq('a')
    end
  end
end
