require "spec"
require "../spec_helper"
require "spec/helpers/iterate"

module SomeInterface; end

private record One do
  include SomeInterface
end

private record Two do
  include SomeInterface
end

private struct InterfaceEnumerable
  include Enumerable(SomeInterface)

  def each(&)
    yield One.new
    yield Two.new
  end
end

private class SpecEnumerable
  include Enumerable(Int32)

  def each(&)
    yield 1
    yield 2
    yield 3
  end
end

private class SpecEmptyEnumerable
  include Enumerable(Int32)

  def each(&block : T -> _)
  end
end

private class SpecCountUpIterator
  include Iterator(Int32)

  def initialize(@size : Int32, @count = 0)
  end

  def next
    (@count += 1) <= @size ? (@count - 1) : stop
  end
end

describe "Enumerable" do
  describe "all? with block" do
    it "returns true" do
      ["ant", "bear", "cat"].all? { |word| word.size >= 3 }.should be_true
    end

    it "returns false" do
      ["ant", "bear", "cat"].all? { |word| word.size >= 4 }.should be_false
    end
  end

  describe "all? without block" do
    it "returns true" do
      [15].all?.should be_true
    end

    it "returns false" do
      [nil, true, 99].all?.should be_false
    end
  end

  describe "all? with pattern" do
    it "returns true" do
      [2, 3, 4].all?(1..5).should be_true
    end

    it "returns false" do
      [2, 3, 4].all?(1..3).should be_false
    end
  end

  describe "any? with block" do
    it "returns true if at least one element fulfills the condition" do
      ["ant", "bear", "cat"].any? { |word| word.size >= 4 }.should be_true
    end

    it "returns false if all elements does not fulfill the condition" do
      ["ant", "bear", "cat"].any? { |word| word.size > 4 }.should be_false
    end
  end

  describe "any? without block" do
    it "returns true if at least one element is truthy" do
      [nil, true, 99].any?.should be_true
    end

    it "returns false if all elements are falsey" do
      [nil, false].any?.should be_false
    end
  end

  describe "any? with pattern" do
    it "returns true" do
      [nil, true, 99].any?(Int32).should be_true
    end

    it "returns false" do
      [nil, false].any?(Int32).should be_false
    end
  end

  describe "compact map" do
    it { Set{1, nil, 2, nil, 3}.compact_map { |x| x.try &.+(1) }.should eq([2, 3, 4]) }
  end

  describe "size without block" do
    it "returns the number of elements in the Enumerable" do
      SpecEnumerable.new.size.should eq 3
    end
  end

  describe "count with block" do
    it "returns the number of the times the item is present" do
      %w(a b c a d A).count("a").should eq 2
    end
  end

  describe "cycle" do
    it "calls forever if we don't break" do
      called = 0
      elements = [] of Int32
      (1..2).cycle do |e|
        elements << e
        called += 1
        break if called == 6
      end
      called.should eq 6
      elements.should eq [1, 2, 1, 2, 1, 2]
    end

    it "calls the block n times given the optional argument" do
      called = 0
      elements = [] of Int32
      (1..2).cycle(3) do |e|
        elements << e
        called += 1
      end
      called.should eq 6
      elements.should eq [1, 2, 1, 2, 1, 2]
    end
  end

  describe "to_a" do
    it "with a block" do
      SpecEnumerable.new.to_a { |e| e*2 }.should eq [2, 4, 6]
    end

    it "without a block" do
      SpecEnumerable.new.to_a.should eq [1, 2, 3]
    end

    it "without a block of an interface type" do
      InterfaceEnumerable.new.to_a.should eq [One.new, Two.new]
    end
  end

  describe "#to_set" do
    context "without block" do
      it "creates a Set from the unique elements of the collection" do
        {1, 1, 2, 3}.to_set.should eq Set{1, 2, 3}
      end
    end

    context "with block" do
      it "creates a Set from running the block against the collection's elements" do
        {1, 2, 3, 4, 5}.to_set { |i| i // 2 }.should eq Set{0, 1, 2}
      end
    end
  end

  describe "chunk" do
    it "works" do
      [1].chunk { true }.to_a.should eq [{true, [1]}]
      [1, 2].chunk { false }.to_a.should eq [{false, [1, 2]}]
      [1, 1, 2, 3, 3].chunk(&.itself).to_a.should eq [{1, [1, 1]}, {2, [2]}, {3, [3, 3]}]
      [1, 1, 2, 3, 3].chunk(&.<=(2)).to_a.should eq [{true, [1, 1, 2]}, {false, [3, 3]}]
      (0..10).chunk(&.//(3)).to_a.should eq [{0, [0, 1, 2]}, {1, [3, 4, 5]}, {2, [6, 7, 8]}, {3, [9, 10]}]
    end

    it "work with class" do
      [1, 1, 2, 3, 3].chunk(&.class).to_a.should eq [{Int32, [1, 1, 2, 3, 3]}]
    end

    it "works with block" do
      res = [] of Tuple(Bool, Array(Int32))
      [1, 2, 3].chunk { |x| x < 3 }.each { |(k, v)| res << {k, v} }
      res.should eq [{true, [1, 2]}, {false, [3]}]
    end

    it "rewind" do
      i = (0..10).chunk(&.//(3))
      i.next.should eq({0, [0, 1, 2]})
      i.next.should eq({1, [3, 4, 5]})
    end

    it "returns elements of the Enumerable in an Array of Tuple, {v, ary}, where 'ary' contains the consecutive elements for which the block returned the value 'v'" do
      result = [1, 2, 3, 2, 3, 2, 1].chunk { |x| x < 3 ? 1 : 0 }.to_a
      result.should eq [{1, [1, 2]}, {0, [3]}, {1, [2]}, {0, [3]}, {1, [2, 1]}]
    end

    it "returns elements for which the block returns Enumerable::Chunk::Alone in separate Arrays" do
      result = [1, 2, 3, 2, 1].chunk { |x| x < 2 ? Enumerable::Chunk::Alone : false }.to_a
      result.should eq [{Enumerable::Chunk::Alone, [1]}, {false, [2, 3, 2]}, {Enumerable::Chunk::Alone, [1]}]
    end

    it "alone all" do
      result = [1, 2].chunk { Enumerable::Chunk::Alone }.to_a
      result.should eq [{Enumerable::Chunk::Alone, [1]}, {Enumerable::Chunk::Alone, [2]}]
    end

    it "does not return elements for which the block returns Enumerable::Chunk::Drop" do
      result = [1, 2, 3, 3, 2, 1].chunk { |x| x == 2 ? Enumerable::Chunk::Drop : 1 }.to_a
      result.should eq [{1, [1]}, {1, [3, 3]}, {1, [1]}]
    end

    it "drop all" do
      result = [1, 2].chunk { Enumerable::Chunk::Drop }.to_a
      result.should be_a(Array(Tuple(NoReturn, Array(Int32))))
      result.size.should eq 0
    end

    it "nil allowed as value" do
      result = [1, 2, 3, 2, 1].chunk { |x| x == 2 ? nil : 1 }.to_a
      result.should eq [{1, [1]}, {nil, [2]}, {1, [3]}, {nil, [2]}, {1, [1]}]
    end

    it "nil 2 case" do
      result = [nil, nil, 1, 1, nil].chunk(&.itself).to_a
      result.should eq [{nil, [nil, nil]}, {1, [1, 1]}, {nil, [nil]}]
    end

    it "reuses true" do
      iter = [1, 1, 2, 3, 3].chunk(reuse: true, &.itself)
      a = iter.next.should be_a(Tuple(Int32, Array(Int32)))
      a.should eq({1, [1, 1]})

      b = iter.next.should be_a(Tuple(Int32, Array(Int32)))
      b.should eq({2, [2]})
      b[1].should be(a[1])

      c = iter.next.should be_a(Tuple(Int32, Array(Int32)))
      c.should eq({3, [3, 3]})
      c[1].should be(a[1])
    end
  end

  describe "chunks" do
    it "works" do
      [1].chunks { true }.should eq [{true, [1]}]
      [1, 2].chunks { false }.should eq [{false, [1, 2]}]
      [1, 1, 2, 3, 3].chunks(&.itself).should eq [{1, [1, 1]}, {2, [2]}, {3, [3, 3]}]
      [1, 1, 2, 3, 3].chunks(&.<=(2)).should eq [{true, [1, 1, 2]}, {false, [3, 3]}]
      (0..10).chunks(&.//(3)).should eq [{0, [0, 1, 2]}, {1, [3, 4, 5]}, {2, [6, 7, 8]}, {3, [9, 10]}]
    end

    it "work with class" do
      [1, 1, 2, 3, 3].chunks(&.class).should eq [{Int32, [1, 1, 2, 3, 3]}]
    end

    it "work with pure enumerable" do
      SpecEnumerable.new.chunks(&.//(2)).should eq [{0, [1]}, {1, [2, 3]}]
    end

    it "returns elements for which the block returns Enumerable::Chunk::Alone in separate Arrays" do
      result = [1, 2, 3, 2, 1].chunks { |x| x < 2 ? Enumerable::Chunk::Alone : false }
      result.should eq [{Enumerable::Chunk::Alone, [1]}, {false, [2, 3, 2]}, {Enumerable::Chunk::Alone, [1]}]
    end

    it "alone all" do
      result = [1, 2].chunks { Enumerable::Chunk::Alone }
      result.should eq [{Enumerable::Chunk::Alone, [1]}, {Enumerable::Chunk::Alone, [2]}]
    end

    it "does not return elements for which the block returns Enumerable::Chunk::Drop" do
      result = [1, 2, 3, 3, 2, 1].chunks { |x| x == 2 ? Enumerable::Chunk::Drop : 1 }
      result.should eq [{1, [1]}, {1, [3, 3]}, {1, [1]}]
    end

    it "drop all" do
      result = [1, 2].chunks { Enumerable::Chunk::Drop }
      result.should be_a(Array(Tuple(NoReturn, Array(Int32))))
      result.size.should eq 0
    end

    it "nil allowed as value" do
      result = [1, 2, 3, 2, 1].chunks { |x| x == 2 ? nil : 1 }
      result.should eq [{1, [1]}, {nil, [2]}, {1, [3]}, {nil, [2]}, {1, [1]}]
    end

    it "nil 2 case" do
      result = [nil, nil, 1, 1, nil].chunks(&.itself)
      result.should eq [{nil, [nil, nil]}, {1, [1, 1]}, {nil, [nil]}]
    end
  end

  describe "#each_cons" do
    context "iterator" do
      it "iterates" do
        iter = [1, 2, 3, 4, 5].each_cons(3)
        iter.next.should eq([1, 2, 3])
        iter.next.should eq([2, 3, 4])
        iter.next.should eq([3, 4, 5])
        iter.next.should be_a(Iterator::Stop)
      end

      it "iterates with reuse = true" do
        iter = [1, 2, 3, 4, 5].each_cons(3, reuse: true)

        a = iter.next
        a.should eq([1, 2, 3])

        b = iter.next
        b.should be(a)
      end

      it "iterates with reuse = array" do
        reuse = [] of Int32
        iter = [1, 2, 3, 4, 5].each_cons(3, reuse: reuse)

        a = iter.next
        a.should eq([1, 2, 3])
        a.should be(reuse)
      end

      it "iterates with reuse = deque" do
        reuse = Deque(Int32).new
        iter = [1, 2, 3, 4, 5].each_cons(3, reuse: reuse)

        a = iter.next
        a.should eq(Deque{1, 2, 3})
        a.should be(reuse)
      end
    end

    context "yield" do
      it "returns running pairs" do
        array = [] of Array(Int32)
        [1, 2, 3, 4].each_cons(2) { |pair| array << pair }
        array.should eq([[1, 2], [2, 3], [3, 4]])
      end

      it "returns running triples" do
        array = [] of Array(Int32)
        [1, 2, 3, 4, 5].each_cons(3) { |triple| array << triple }
        array.should eq([[1, 2, 3], [2, 3, 4], [3, 4, 5]])
      end

      it "yields running pairs with reuse = true" do
        array = [] of Array(Int32)
        object_ids = Set(UInt64).new
        [1, 2, 3, 4].each_cons(2, reuse: true) do |pair|
          object_ids << pair.object_id
          array << pair.dup
        end
        array.should eq([[1, 2], [2, 3], [3, 4]])
        object_ids.size.should eq(1)
      end

      it "yields running pairs with reuse = array" do
        array = [] of Array(Int32)
        reuse = [] of Int32
        [1, 2, 3, 4].each_cons(2, reuse: reuse) do |pair|
          pair.should be(reuse)
          array << pair.dup
        end
        array.should eq([[1, 2], [2, 3], [3, 4]])
      end

      it "yields running pairs with reuse = deque" do
        array = [] of Deque(Int32)
        reuse = Deque(Int32).new
        [1, 2, 3, 4].each_cons(2, reuse: reuse) do |pair|
          pair.should be(reuse)
          array << pair.dup
        end
        array.should eq([Deque{1, 2}, Deque{2, 3}, Deque{3, 4}])
      end
    end
  end

  describe "#each_cons_pair" do
    it "returns running pairs" do
      array = [] of Array(Int32)
      [1, 2, 3, 4].each_cons_pair { |a, b| array << [a, b] }
      array.should eq([[1, 2], [2, 3], [3, 4]])
    end
  end

  describe "each_slice" do
    it "returns partial slices" do
      array = [] of Array(Int32)
      [1, 2, 3].each_slice(2) { |slice| array << slice }
      array.should eq([[1, 2], [3]])
      array[0].should_not be(array[1])
    end

    it "returns full slices" do
      array = [] of Array(Int32)
      [1, 2, 3, 4].each_slice(2) { |slice| array << slice }
      array.should eq([[1, 2], [3, 4]])
      array[0].should_not be(array[1])
    end

    it "reuses with true" do
      array = [] of Array(Int32)
      object_ids = Set(UInt64).new
      [1, 2, 3, 4].each_slice(2, reuse: true) do |slice|
        object_ids << slice.object_id
        array << slice.dup
      end
      array.should eq([[1, 2], [3, 4]])
      object_ids.size.should eq(1)
    end

    it "reuses with existing array" do
      array = [] of Array(Int32)
      reuse = [] of Int32
      [1, 2, 3, 4].each_slice(2, reuse: reuse) do |slice|
        slice.should be(reuse)
        array << slice.dup
      end
      array.should eq([[1, 2], [3, 4]])
    end

    it "returns each_slice iterator" do
      iter = [1, 2, 3, 4, 5].each_slice(2)
      iter.next.should eq([1, 2])
      iter.next.should eq([3, 4])
      iter.next.should eq([5])
      iter.next.should be_a(Iterator::Stop)
    end
  end

  describe "each_step" do
    it_iterates "yields every 2nd element", %w[a c e], %w[a b c d e f].each_step(2)
    it_iterates "accepts an optional offset parameter", %w[b d f], %w[a b c d e f].each_step(2, offset: 1)
    it_iterates "accepts an offset of 0", %w[a c e], %w[a b c d e f].each_step(2, offset: 0)
    it_iterates "accepts an offset larger then the step size", %w[d f], %w[a b c d e f].each_step(2, offset: 3)

    it_iterates "accepts a step larger then the enumerable size", %w[a], %w[a b c d e f].each_step(7)
    it_iterates "accepts an offset larger then the enumerable size", %w[], %w[a b c d e f].each_step(1, offset: 7)

    it "doesn't accept a negative step" do
      expect_raises(ArgumentError) do
        %w[a b c d e f].each_step(-2)
      end
      expect_raises(ArgumentError) do
        %w[a b c d e f].each_step(-2) { }
      end
    end

    it "doesn't accept a step of 0" do
      expect_raises(ArgumentError) do
        %w[a b c d e f].each_step(0)
      end
      expect_raises(ArgumentError) do
        %w[a b c d e f].each_step(0) { }
      end
    end

    it "doesn't accept a negative offset" do
      expect_raises(ArgumentError) do
        %w[a b c d e f].each_step(2, offset: -2)
      end
      expect_raises(ArgumentError) do
        %w[a b c d e f].each_step(2, offset: -2) { }
      end
    end
  end

  describe "each_with_index" do
    it "yields the element and the index" do
      collection = [] of {String, Int32}
      ["a", "b", "c"].each_with_index do |e, i|
        collection << {e, i}
      end
      collection.should eq [{"a", 0}, {"b", 1}, {"c", 2}]
    end

    it "accepts an optional offset parameter" do
      collection = [] of {String, Int32}
      ["Alice", "Bob"].each_with_index(1) do |e, i|
        collection << {e, i}
      end
      collection.should eq [{"Alice", 1}, {"Bob", 2}]
    end

    it "gets each_with_index iterator" do
      iter = [1, 2].each_with_index
      iter.next.should eq({1, 0})
      iter.next.should eq({2, 1})
      iter.next.should be_a(Iterator::Stop)
    end
  end

  describe "each_with_object" do
    it "yields the element and the given object" do
      collection = [] of {Int32, String}
      object = "a"
      (1..3).each_with_object(object) do |e, o|
        collection << {e, o}
      end.should be(object)
      collection.should eq [{1, object}, {2, object}, {3, object}]
    end

    it "gets each_with_object iterator" do
      iter = [1, 2].each_with_object("a")
      iter.next.should eq({1, "a"})
      iter.next.should eq({2, "a"})
      iter.next.should be_a(Iterator::Stop)
    end
  end

  describe "#empty?" do
    it { SpecEnumerable.new.empty?.should be_false }
    it { SpecEmptyEnumerable.new.empty?.should be_true }
  end

  describe "#present?" do
    it { SpecEnumerable.new.present?.should be_true }
    it { SpecEmptyEnumerable.new.present?.should be_false }
  end

  describe "find" do
    it "finds" do
      [1, 2, 3].find { |x| x > 2 }.should eq(3)
    end

    it "doesn't find" do
      [1, 2, 3].find { |x| x > 3 }.should be_nil
    end

    it "doesn't find with default value" do
      [1, 2, 3].find(-1) { |x| x > 3 }.should eq(-1)
    end
  end

  describe "find!" do
    it "finds" do
      [1, 2, 3].find! { |x| x > 2 }.should eq(3)
    end

    it "raises if not found" do
      expect_raises Enumerable::NotFoundError do
        [1, 2, 3].find! { false }
      end
    end
  end

  describe "find_value" do
    it "finds and returns the first truthy block result" do
      [1, 2, 3].find_value { |i| "1" if i == 1 }.should eq "1"
      {1, 2, 3}.find_value { |i| "2" if i == 2 }.should eq "2"
      (1..3).find_value { |i| "3" if i == 3 }.should eq "3"

      # Block returns `true && expression` vs the above `expression if true`.
      # Same idea, but a different idiom. It serves as an allegory for the next
      # test which checks `false` vs `nil`.
      [1, 2, 3].find_value { |i| i == 1 && "1" }.should eq "1"
      {1, 2, 3}.find_value { |i| i == 2 && "2" }.should eq "2"
      (1..3).find_value { |i| i == 3 && "3" }.should eq "3"
    end

    it "returns the default value if there are no truthy block results" do
      {1, 2, 3}.find_value { |i| "4" if i == 4 }.should eq nil
      {1, 2, 3}.find_value "nope" { |i| "4" if i == 4 }.should eq "nope"
      ([] of Int32).find_value false { true }.should eq false

      # Same as above but returns `false` instead of `nil`.
      {1, 2, 3}.find_value { |i| i == 4 && "4" }.should eq nil
      {1, 2, 3}.find_value "nope" { |i| i == 4 && "4" }.should eq "nope"
    end
  end

  describe "first" do
    it "calls block if empty" do
      (1...1).first { 10 }.should eq(10)
    end

    it "gets first" do
      (1..3).first.should eq(1)
    end

    it "raises if enumerable empty" do
      expect_raises Enumerable::EmptyError do
        (1...1).first
      end
    end

    it { [-1, -2, -3].first.should eq(-1) }
  end

  describe "first?" do
    it "gets first?" do
      (1..3).first?.should eq(1)
    end

    it "returns nil if enumerable empty" do
      (1...1).first?.should be_nil
    end
  end

  describe "flat_map" do
    it "does example 1" do
      [1, 2, 3, 4].flat_map { |e| [e, -e] }.should eq([1, -1, 2, -2, 3, -3, 4, -4])
    end

    it "does example 2" do
      [[1, 2], [3, 4]].flat_map { |e| e + [100] }.should eq([1, 2, 100, 3, 4, 100])
    end

    it "does example 3" do
      [[1, 2, 3], 4, 5].flat_map { |e| e }.should eq([1, 2, 3, 4, 5])
    end

    it "does example 4" do
      [{1 => 2}, {3 => 4}].flat_map { |e| e }.should eq([{1 => 2}, {3 => 4}])
    end

    it "flattens iterators" do
      [[1, 2], [3, 4]].flat_map(&.each).should eq([1, 2, 3, 4])
    end

    it "accepts mixed element types" do
      [[1, 2, 3], ['a', 'b'].each, "cde"].flat_map { |e| e }.should eq([1, 2, 3, 'a', 'b', "cde"])
    end
  end

  describe "group_by" do
    it { [1, 2, 2, 3].group_by { |x| x == 2 }.should eq({true => [2, 2], false => [1, 3]}) }

    it "groups can group by size (like the doc example)" do
      %w(Alice Bob Ary).group_by(&.size).should eq({3 => ["Bob", "Ary"],
                                                    5 => ["Alice"]})
    end
  end

  describe "in_groups_of" do
    it { [1, 2, 3].in_groups_of(1).should eq([[1], [2], [3]]) }
    it { [1, 2, 3].in_groups_of(2).should eq([[1, 2], [3, nil]]) }
    it { [1, 2, 3, 4].in_groups_of(3).should eq([[1, 2, 3], [4, nil, nil]]) }
    it { ([] of Int32).in_groups_of(2).should eq([] of Array(Array(Int32 | Nil))) }
    it { [1, 2, 3].in_groups_of(2, "x").should eq([[1, 2], [3, "x"]]) }

    it "raises argument error if size is less than 0" do
      expect_raises ArgumentError, "Size must be positive" do
        [1, 2, 3].in_groups_of(0)
      end
    end

    it "takes a block" do
      sums = [] of Int32
      [1, 2, 4, 5].in_groups_of(3, 10) { |a| sums << a.sum }
      sums.should eq([7, 25])
    end

    it "reuses with true" do
      array = [] of Array(Int32)
      object_ids = Set(UInt64).new
      [1, 2, 4, 5].in_groups_of(3, 10, reuse: true) do |group|
        object_ids << group.object_id
        array << group.dup
      end
      array.should eq([[1, 2, 4], [5, 10, 10]])
      object_ids.size.should eq(1)
    end

    it "reuses with existing array" do
      array = [] of Array(Int32)
      reuse = [] of Int32
      [1, 2, 4, 5].in_groups_of(3, 10, reuse: reuse) do |slice|
        slice.should be(reuse)
        array << slice.dup
      end
      array.should eq([[1, 2, 4], [5, 10, 10]])
    end
  end

  describe "in slices of" do
    it { [1, 2, 3].in_slices_of(1).should eq([[1], [2], [3]]) }
    it { [1, 2, 3].in_slices_of(2).should eq([[1, 2], [3]]) }
    it { [1, 2, 3, 4].in_slices_of(3).should eq([[1, 2, 3], [4]]) }
    it { ([] of Int32).in_slices_of(2).should eq([] of Array(Int32)) }

    it "raises argument error if size is less than 0" do
      expect_raises ArgumentError, "Size must be positive" do
        [1, 2, 3].in_slices_of(0)
      end
    end
  end

  describe "includes?" do
    it "is true if the object exists in the collection" do
      [1, 2, 3].includes?(2).should be_true
    end

    it "is false if the object is not part of the collection" do
      [1, 2, 3].includes?(5).should be_false
    end
  end

  describe "index with a block" do
    it "returns the index of the first element where the block returns true" do
      ["Alice", "Bob"].index { |name| name.size < 4 }.should eq 1
    end

    it "returns nil if no object could be found" do
      ["Alice", "Bob"].index { |name| name.size < 3 }.should eq nil
    end
  end

  describe "index with an object" do
    it "returns the index of that object if found" do
      ["Alice", "Bob"].index("Alice").should eq 0
    end

    it "returns nil if the object was not found" do
      ["Alice", "Bob"].index("Mallory").should be_nil
    end
  end

  describe "index! with a block" do
    it "returns the index of the first element where the block returns true" do
      ["Alice", "Bob"].index! { |name| name.size < 4 }.should eq 1
    end

    it "raises if not found" do
      expect_raises Enumerable::NotFoundError do
        ["Alice", "Bob"].index! { |name| name.size < 3 }
      end
    end
  end

  describe "index! with an object" do
    it "returns the index of that object if found" do
      ["Alice", "Bob"].index!("Alice").should eq 0
    end

    it "raises if not found" do
      expect_raises Enumerable::NotFoundError do
        ["Alice", "Bob"].index!("Mallory")
      end
    end
  end

  describe "index_by" do
    it "creates a hash indexed by the value returned by the block" do
      hash = ["Anna", "Ary", "Alice"].index_by(&.size)
      hash.should eq({4 => "Anna", 3 => "Ary", 5 => "Alice"})
    end

    it "overrides values if a value is returned twice" do
      hash = ["Anna", "Ary", "Alice", "Bob"].index_by(&.size)
      hash.should eq({4 => "Anna", 3 => "Bob", 5 => "Alice"})
    end
  end

  describe "reduce" do
    it { [1, 2, 3].reduce { |memo, i| memo + i }.should eq(6) }
    it { [1, 2, 3].reduce(10) { |memo, i| memo + i }.should eq(16) }
    it { [1, 2, 3].reduce([] of Int32) { |memo, i| memo.unshift(i) }.should eq([3, 2, 1]) }
    it { [[0, 1], [2, 3], [4, 5]].reduce([] of Int32) { |memo, i| memo.concat(i) }.should eq([0, 1, 2, 3, 4, 5]) }

    it "raises if empty" do
      expect_raises Enumerable::EmptyError do
        ([] of Int32).reduce { |memo, i| memo + i }
      end
    end

    it "does not raise if empty if there is a memo argument" do
      result = ([] of Int32).reduce(10) { |memo, i| memo + i }
      result.should eq 10
    end

    it "allows block return type to be different from element type" do
      [1, 2, 3].reduce { |x, y| "#{x}-#{y}" }.should eq("1-2-3")
      [1].reduce { |x, y| "#{x}-#{y}" }.should eq(1)
      {1}.reduce { |x, y| "#{x}-#{y}" }.should eq(1)

      expect_raises Enumerable::EmptyError do
        ([] of Int32).reduce { |x, y| "#{x}-#{y}" }
      end

      expect_raises Enumerable::EmptyError do
        Tuple.new.reduce { |x, y| "#{x}-#{y}" }
      end
    end
  end

  describe "reduce?" do
    it { [1, 2, 3].reduce? { |memo, i| memo + i }.should eq(6) }

    it "returns nil if empty" do
      ([] of Int32).reduce? { |memo, i| memo + i }.should be_nil
    end

    it "allows block return type to be different from element type" do
      [1, 2, 3].reduce? { |x, y| "#{x}-#{y}" }.should eq("1-2-3")
      [1].reduce? { |x, y| "#{x}-#{y}" }.should eq(1)
      {1}.reduce? { |x, y| "#{x}-#{y}" }.should eq(1)
      ([] of Int32).reduce? { |x, y| "#{x}-#{y}" }.should be_nil
      Tuple.new.reduce? { |x, y| "#{x}-#{y}" }.should be_nil
    end
  end

  describe "#accumulate" do
    context "prefix sums" do
      it { SpecEnumerable.new.accumulate.should eq([1, 3, 6]) }
      it { [1.5, 3.75, 6.125].accumulate.should eq([1.5, 5.25, 11.375]) }
      it { Array(Int32).new.accumulate.should eq(Array(Int32).new) }
    end

    context "prefix sums, with init" do
      it { SpecEnumerable.new.accumulate(0).should eq([0, 1, 3, 6]) }
      it { [1.5, 3.75, 6.125].accumulate(0.5).should eq([0.5, 2.0, 5.75, 11.875]) }
      it { Array(Int32).new.accumulate(7).should eq([7]) }

      it "preserves initial type" do
        x = SpecEnumerable.new.accumulate(4.0)
        x.should be_a(Array(Float64))
        x.should eq([4.0, 5.0, 7.0, 10.0])
      end
    end

    context "generic cumulative fold" do
      it { SpecEnumerable.new.accumulate { |x, y| x * 10 + y }.should eq([1, 12, 123]) }
      it { Array(Int32).new.accumulate { raise "" }.should eq(Array(Int32).new) }
    end

    context "generic cumulative fold, with init" do
      it { SpecEnumerable.new.accumulate(4) { |x, y| x * 10 + y }.should eq([4, 41, 412, 4123]) }
      it { Array(Int32).new.accumulate(7) { raise "" }.should eq([7]) }

      it "preserves initial type" do
        x = [4, 3, 2].accumulate("X") { |x, y| x * y }
        x.should be_a(Array(String))
        x.should eq(%w(X XXXX XXXXXXXXXXXX XXXXXXXXXXXXXXXXXXXXXXXX))
      end
    end
  end

  describe "#join" do
    it "()" do
      [1, 2, 3].join.should eq("123")
    end

    it "(separator)" do
      ["Ruby", "Crystal", "Python"].join(", ").should eq "Ruby, Crystal, Python"
    end

    it "(&)" do
      str = [1, 2, 3].join { |x| x + 1 }
      str.should eq("234")
    end

    it "(separator, &)" do
      str = [1, 2, 3].join(", ") { |x| x + 1 }
      str.should eq("2, 3, 4")
    end

    it "(io)" do
      io = IO::Memory.new
      [1, 2, 3].join(io)
      io.to_s.should eq("123")
    end

    it "(io, separator)" do
      io = IO::Memory.new
      ["Ruby", "Crystal", "Python"].join(io, ", ")
      io.to_s.should eq "Ruby, Crystal, Python"
    end

    it "(separator, io) (deprecated)" do
      io = IO::Memory.new
      ["Ruby", "Crystal", "Python"].join(", ", io)
      io.to_s.should eq "Ruby, Crystal, Python"
    end

    it "(io, &)" do
      io = IO::Memory.new
      [1, 2, 3].join(io) { |x, io| io << x + 1 }
      io.to_s.should eq("234")
    end

    it "(io, separator, &)" do
      io = IO::Memory.new
      [1, 2, 3].join(io, ", ") { |x, io| io << x + 1 }
      io.to_s.should eq("2, 3, 4")
    end

    it "(separator, io, &) (deprecated)" do
      str = IO::Memory.new
      [1, 2, 3].join(", ", str) { |x, io| io << x + 1 }
      str.to_s.should eq("2, 3, 4")
    end
  end

  describe "map" do
    it "applies the function to each element and returns a new array" do
      result = [1, 2, 3].map { |i| i * 10 }
      result.should eq [10, 20, 30]
    end

    it "leaves the original unmodified" do
      original = [1, 2, 3]
      original.map { |i| i * 10 }
      original.should eq [1, 2, 3]
    end
  end

  describe "map_with_index" do
    it "yields the element and the index" do
      result = SpecEnumerable.new.map_with_index { |e, i| "Value ##{i}: #{e}" }
      result.should eq ["Value #0: 1", "Value #1: 2", "Value #2: 3"]
    end

    it "yields the element and the index of an iterator" do
      str = "hello"
      result = str.each_char.map_with_index { |char, i| "#{char}#{i}" }
      result.should eq ["h0", "e1", "l2", "l3", "o4"]
    end
  end

  describe "max" do
    it { [1, 2, 3].max.should eq(3) }
    it { [1, 2, 3].max(0).should eq([] of Int32) }
    it { [1, 2, 3].max(1).should eq([3]) }
    it { [1, 2, 3].max(2).should eq([3, 2]) }
    it { [1, 2, 3].max(3).should eq([3, 2, 1]) }
    it { [1, 2, 3].max(4).should eq([3, 2, 1]) }
    it { ([] of Int32).max(0).should eq([] of Int32) }
    it { ([] of Int32).max(5).should eq([] of Int32) }
    it {
      (0..1000).map { |x| (x*137 + x*x*139) % 5000 }.max(10).should eq([
        4992, 4990, 4980, 4972, 4962, 4962, 4960, 4960, 4952, 4952,
      ])
    }

    it "does not modify the array" do
      xs = [7, 5, 2, 4, 9]
      xs.max(2).should eq([9, 7])
      xs.should eq([7, 5, 2, 4, 9])
    end

    it "raises if empty" do
      expect_raises Enumerable::EmptyError do
        ([] of Int32).max
      end
    end

    it "raises if n is negative" do
      expect_raises ArgumentError do
        ([1, 2, 3] of Int32).max(-1)
      end
    end

    it "raises if not comparable" do
      expect_raises ArgumentError do
        [Float64::NAN, 1.0, 2.0, Float64::NAN].max
      end
    end

    it "raises if not comparable in max(n)" do
      expect_raises ArgumentError do
        [Float64::NAN, 1.0, 2.0, Float64::NAN].max(2)
      end
    end
  end

  describe "max?" do
    it "returns nil if empty" do
      ([] of Int32).max?.should be_nil
    end
  end

  describe "max_by" do
    it { [-1, -2, -3].max_by { |x| -x }.should eq(-3) }
  end

  describe "max_by?" do
    it "returns nil if empty" do
      ([] of Int32).max_by? { |x| -x }.should be_nil
    end
  end

  describe "max_of" do
    it { [-1, -2, -3].max_of { |x| -x }.should eq(3) }

    it "raises if not comparable" do
      expect_raises ArgumentError do
        [-1.0, Float64::NAN, -3.0].max_of { |x| -x }
      end
    end
  end

  describe "max_of?" do
    it "returns nil if empty" do
      ([] of Int32).max_of? { |x| -x }.should be_nil
    end
  end

  describe "min" do
    it { [1, 2, 3].min.should eq(1) }
    it { [1, 2, 3].min(0).should eq([] of Int32) }
    it { [1, 2, 3].min(1).should eq([1]) }
    it { [1, 2, 3].min(2).should eq([1, 2]) }
    it { [1, 2, 3].min(3).should eq([1, 2, 3]) }
    it { [1, 2, 3].min(4).should eq([1, 2, 3]) }
    it { ([] of Int32).min(0).should eq([] of Int32) }
    it { ([] of Int32).min(1).should eq([] of Int32) }
    it {
      (0..1000).map { |x| (x*137 + x*x*139) % 5000 }.min(10).should eq([
        0, 10, 20, 26, 26, 26, 26, 30, 32, 32,
      ])
    }

    it "does not modify the array" do
      xs = [7, 5, 2, 4, 9]
      xs.min(2).should eq([2, 4])
      xs.should eq([7, 5, 2, 4, 9])
    end

    it "raises if empty" do
      expect_raises Enumerable::EmptyError do
        ([] of Int32).min
      end
    end

    it "raises if n is negative" do
      expect_raises ArgumentError do
        ([1, 2, 3] of Int32).min(-1)
      end
    end

    it "raises if not comparable" do
      expect_raises ArgumentError do
        [-1.0, Float64::NAN, -3.0].min
      end
    end

    it "raises if not comparable in min(n)" do
      expect_raises ArgumentError do
        [Float64::NAN, 1.0, 2.0, Float64::NAN].min(2)
      end
    end
  end

  describe "min?" do
    it "returns nil if empty" do
      ([] of Int32).min?.should be_nil
    end
  end

  describe "min_by" do
    it { [1, 2, 3].min_by { |x| -x }.should eq(3) }
  end

  describe "min_by?" do
    it "returns nil if empty" do
      ([] of Int32).min_by? { |x| -x }.should be_nil
    end
  end

  describe "min_of" do
    it { [1, 2, 3].min_of { |x| -x }.should eq(-3) }

    it "raises if not comparable" do
      expect_raises ArgumentError do
        [-1.0, Float64::NAN, -3.0].min_of { |x| -x }
      end
    end
  end

  describe "min_of?" do
    it "returns nil if empty" do
      ([] of Int32).min_of? { |x| -x }.should be_nil
    end
  end

  describe "minmax" do
    it { [1, 2, 3].minmax.should eq({1, 3}) }

    it "raises if empty" do
      expect_raises Enumerable::EmptyError do
        ([] of Int32).minmax
      end
    end
  end

  describe "minmax?" do
    it "returns two nils if empty" do
      ([] of Int32).minmax?.should eq({nil, nil})
    end

    it "raises if not comparable" do
      expect_raises ArgumentError do
        [-1.0, Float64::NAN, -3.0].minmax
      end
    end
  end

  describe "minmax_by" do
    it { [-1, -2, -3].minmax_by { |x| -x }.should eq({-1, -3}) }
  end

  describe "minmax_by?" do
    it "returns two nils if empty" do
      ([] of Int32).minmax_by? { |x| -x }.should eq({nil, nil})
    end
  end

  describe "minmax_of" do
    it { [-1, -2, -3].minmax_of { |x| -x }.should eq({1, 3}) }

    it "raises if not comparable" do
      expect_raises ArgumentError do
        [-1.0, Float64::NAN, -3.0].minmax_of { |x| -x }
      end
    end
  end

  describe "minmax_of?" do
    it "returns two nils if empty" do
      ([] of Int32).minmax_of? { |x| -x }.should eq({nil, nil})
    end
  end

  describe "none?" do
    it { [1, 2, 2, 3].none? { |x| x == 1 }.should eq(false) }
    it { [1, 2, 2, 3].none? { |x| x == 0 }.should eq(true) }
  end

  describe "none? without block" do
    it { [nil, false].none?.should be_true }
    it { [nil, false, true].none?.should be_false }
  end

  describe "none? with pattern" do
    it { [2, 3, 4].none?(5..7).should be_true }
    it { [1, false, nil].none?(Bool).should be_false }
  end

  describe "one?" do
    it { [1, 2, 2, 3].one? { |x| x == 1 }.should eq(true) }
    it { [1, 2, 2, 3].one? { |x| x == 2 }.should eq(false) }
    it { [1, 2, 2, 3].one? { |x| x == 0 }.should eq(false) }
    it { [1, 2, false].one?.should be_false }
    it { [1, false, false].one?.should be_true }
    it { [false].one?.should be_false }
    it { [1, 5, 9].one?(3..6).should be_true }
    it { [1, false, 2].one?(Int32).should be_false }
  end

  describe "partition" do
    it { [1, 2, 2, 3].partition { |x| x == 2 }.should eq({[2, 2], [1, 3]}) }
    it { [1, 2, 3, 4, 5, 6].partition(&.even?).should eq({[2, 4, 6], [1, 3, 5]}) }

    it "with mono type on union type" do
      ints, others = [1, true, nil, 3, false, "string", 'c'].partition(Int32)
      ints.should eq([1, 3])
      others.should eq([true, nil, false, "string", 'c'])
      ints.should be_a(Array(Int32))
      others.should be_a(Array(Bool | String | Char | Nil))
    end

    it "with union type on union type" do
      ints_bools, others = [1, true, nil, 3, false, "string", 'c'].partition(Int32 | Bool)
      ints_bools.should eq([1, true, 3, false])
      others.should eq([nil, "string", 'c'])
      ints_bools.should be_a(Array(Int32 | Bool))
      others.should be_a(Array(String | Char | Nil))
    end

    it "with missing type on union type" do
      symbols, others = [1, true, nil, 3, false, "string", 'c'].partition(Symbol)
      symbols.empty?.should be_true
      others.should eq([1, true, nil, 3, false, "string", 'c'])
      symbols.should be_a(Array(Symbol))
      others.should be_a(Array(Int32 | Bool | String | Char | Nil))
    end

    it "with mono type on mono type" do
      ints, others = [1, 3].partition(Int32)
      ints.should eq([1, 3])
      others.empty?.should be_true
      ints.should be_a(Array(Int32))
      others.should be_a(Array(NoReturn))
    end
  end

  describe "reject" do
    it "rejects the values for which the block returns true" do
      [1, 2, 3, 4].reject(&.even?).should eq([1, 3])
    end

    it "rejects with pattern" do
      [1, 2, 3, 4, 5, 6].reject(2..4).should eq([1, 5, 6])
    end

    it "with type" do
      ints = [1, true, false, 3].reject(Bool)
      ints.should eq([1, 3])
      ints.should be_a(Array(Int32))
    end

    it "with type, for tuples" do
      ints = {1, true, false, 3}.reject(Int32)
      ints.should eq([true, false])
      ints.should be_a(Array(Bool))
    end
  end

  describe "sample" do
    describe "single-element" do
      it "samples without random" do
        [1].sample.should eq(1)

        x = SpecEnumerable.new.sample
        [1, 2, 3].should contain(x)
      end

      it "samples with random" do
        SpecEnumerable.new.sample(Random.new(1)).should eq(1)
        [1, 2, 3].sample(Random.new(1)).should eq(2)
      end

      it "raises on empty self" do
        expect_raises(IndexError) { Array(Int32).new.sample }
        expect_raises(IndexError) { SpecEmptyEnumerable.new.sample }
      end
    end

    describe "multiple-element" do
      it "samples 0 elements" do
        ary = [1].sample(0)
        ary.should eq([] of Int32)
        ary.should be_a(Array(Int32))

        ary = SpecEmptyEnumerable.new.sample(0)
        ary.should eq([] of Int32)
        ary.should be_a(Array(Int32))
      end

      it "samples 1 element" do
        [1].sample(1).should eq([1])

        x = [1, 2, 3].sample(1)
        x.size.should eq(1)
        x = x.first
        [1, 2, 3].should contain(x)
      end

      it "samples k elements out of n" do
        ary = [1].sample(1)
        ary.should eq([1])

        a = {1, 2, 3, 4, 5}
        b = a.sample(3)
        set = Set.new(b)
        set.size.should eq(3)

        set.each do |e|
          a.should contain(e)
        end
      end

      it "raises on k < 0" do
        expect_raises(ArgumentError) { Array(Int32).new.sample(-1) }
        expect_raises(ArgumentError) { SpecEnumerable.new.sample(-1) }
      end

      it "samples k elements out of n, where k > n" do
        a = SpecEnumerable.new
        b = a.sample(10)
        b.size.should eq(3)
        set = Set.new(b)
        set.size.should eq(3)

        set.each do |e|
          a.should contain(e)
        end

        SpecEmptyEnumerable.new.sample(1).should eq([] of Int32)
      end

      it "samples k elements out of n, with random" do
        a = (1..5)
        b = a.sample(3, Random.new(1))
        b.should eq([4, 3, 1])
      end
    end
  end

  describe "select" do
    it "selects the values for which the block returns true" do
      [1, 2, 3, 4].select(&.even?).should eq([2, 4])
    end

    it "with pattern" do
      [1, 2, 3, 4, 5].select(2..4).should eq([2, 3, 4])
    end

    it "with type" do
      ints = [1, true, nil, 3, false].select(Int32)
      ints.should eq([1, 3])
      ints.should be_a(Array(Int32))
    end
  end

  describe "skip" do
    it "returns an array without the skipped elements" do
      [1, 2, 3, 4, 5, 6].skip(3).should eq [4, 5, 6]
    end

    it "returns an empty array when skipping more elements than array size" do
      [1, 2].skip(3).should eq [] of Int32
    end

    it "raises if count is negative" do
      expect_raises(ArgumentError) do
        [1, 2].skip(-1)
      end
    end
  end

  describe "skip_while" do
    it "skips elements while the condition holds true" do
      result = [1, 2, 3, 4, 5, 0].skip_while { |i| i < 3 }
      result.should eq [3, 4, 5, 0]
    end

    it "returns an empty array if the condition is always true" do
      [1, 2, 3].skip_while { true }.should eq [] of Int32
    end

    it "returns the full Array if the first check is false" do
      [5, 0, 1, 2, 3].skip_while { |x| x < 4 }.should eq [5, 0, 1, 2, 3]
    end

    it "does not yield to the block anymore once it returned false" do
      called = 0
      [1, 2, 3, 4, 4].skip_while do |i|
        called += 1
        i < 3
      end
      called.should eq 3
    end
  end

  describe "sum" do
    it { ([] of Int32).sum.should eq(0) }
    it { [1, 2, 3].sum.should eq(6) }
    it { [1, 2, 3].sum(4).should eq(10) }
    it { [1, 2, 3].sum(4.5).should eq(10.5) }
    it { (1..3).sum { |x| x * 2 }.should eq(12) }
    it { (1..3).sum(1.5) { |x| x * 2 }.should eq(13.5) }
    it { [1, 3_u64].sum(0_i32).should eq(4_u32) }
    it { [1, 3].sum(0_u64).should eq(4_u64) }
    it { [1, 10000000000_u64].sum(0_u64).should eq(10000000001) }
    it "raises if union types are summed", tags: %w[slow] do
      exc = assert_error <<-CRYSTAL,
        require "prelude"
        [1, 10000000000_u64].sum
        CRYSTAL
        "`Enumerable#sum()` and `#product()` do not support Union " +
        "types. Instead, use `Enumerable#sum(initial)` and " +
        "`#product(initial)`, respectively, with an initial value " +
        "of the intended type of the call."
    end

    it "uses additive_identity from type" do
      typeof([1, 2, 3].sum).should eq(Int32)
      typeof([1.5, 2.5, 3.5].sum).should eq(Float64)
      typeof([1, 2, 3].sum(&.to_f)).should eq(Float64)
      typeof(([1, 2, 3] of Float32).sum).should eq(Float32)
    end

    it "array of arrays" do
      [[1, 2, 3], [3, 4, 5]].sum.should eq [1, 2, 3, 3, 4, 5]
      [[[1, 2], [3]], [[1, 2], [3, 4, 5]]].sum.should eq [[1, 2], [3], [1, 2], [3, 4, 5]]
      Deque{[1, 2, 3], [3, 4, 5]}.sum.should eq [1, 2, 3, 3, 4, 5]
    end

    it "strings" do
      ["foo", "bar"].sum.should eq "foobar"
    end

    it "float" do
      [1.0, 2.0, 3.5, 4.5].sum.should eq 11.0
      ([1.0, 2.0, 3.5, 4.5] of Float32).sum.should eq 11.0
    end

    it "slices" do
      [Slice[1, 2], Slice[3, 'a', 'b', 'c']].sum.should eq(Slice[1, 2, 3, 'a', 'b', 'c'])
    end
  end

  describe "product" do
    it { ([] of Int32).product.should eq(1) }
    it { [1, 2, 3].product.should eq(6) }
    it { [1, 2, 3].product(4).should eq(24) }
    it { [1, 2, 3].product(4.5).should eq(27) }
    it { (1..3).product { |x| x * 2 }.should eq(48) }
    it { (1..3).product(1.5) { |x| x * 2 }.should eq(72) }

    it "uses zero from type" do
      typeof([1, 2, 3].product).should eq(Int32)
      typeof([1.5, 2.5, 3.5].product).should eq(Float64)
      typeof([1, 2, 3].product(&.to_f)).should eq(Float64)
    end

    it { [1, 3_u64].product(3_i32).should eq(9_u32) }
    it { [1, 3].product(3_u64).should eq(9_u64) }
    it { [1, 10000000000_u64].product(3_u64).should eq(30000000000_u64) }
    it "raises if union types are multiplied", tags: %w[slow] do
      exc = assert_error <<-CRYSTAL,
        require "prelude"
        [1, 10000000000_u64].product
        CRYSTAL
        "`Enumerable#sum()` and `#product()` do not support Union " +
        "types. Instead, use `Enumerable#sum(initial)` and " +
        "`#product(initial)`, respectively, with an initial value " +
        "of the intended type of the call."
    end
  end

  describe "first" do
    it { (1..3).first(1).should eq([1]) }
    it { (1..3).first(4).should eq([1, 2, 3]) }

    it "raises if count is negative" do
      expect_raises(ArgumentError) do
        (1..2).first(-1)
      end
    end
  end

  describe "take_while" do
    it "keeps elements while the block returns true" do
      [1, 2, 3, 4, 5, 0].take_while { |i| i < 3 }.should eq [1, 2]
    end

    it "returns the full Array if the condition is always true" do
      [1, 2, 3, -3].take_while { true }.should eq [1, 2, 3, -3]
    end

    it "returns an empty Array if the block is false for the first element" do
      [1, 2, -1, 0].take_while { |i| i <= 0 }.should eq [] of Int32
    end

    it "does not call the block again once it returned false" do
      called = 0
      [1, 2, 3, 4, 0].take_while do |i|
        called += 1
        i < 3
      end
      called.should eq 3
    end
  end

  describe "tally_by" do
    it "returns a hash with counts according to the value returned by the block" do
      %w[a A b B c C C].tally_by(&.downcase).should eq({"a" => 2, "b" => 2, "c" => 3})
    end

    context "with hash" do
      it "returns a hash with counts according to the value returned by the block" do
        hash = {} of Char => Int32
        words = ["Crystal", "Ruby"]
        words.each { |word| word.chars.tally_by(hash, &.downcase) }

        hash.should eq(
          {'c' => 1, 'r' => 2, 'y' => 2, 's' => 1, 't' => 1, 'a' => 1, 'l' => 1, 'u' => 1, 'b' => 1}
        )
      end
    end
  end

  describe "tally" do
    it "returns a hash with counts according to the value" do
      %w[1 2 3 3 3 2].tally.should eq({"1" => 1, "2" => 2, "3" => 3})
    end

    context "with hash" do
      it "returns a hash with counts according to the value" do
        hash = {} of Char => Int32
        words = ["crystal", "ruby"]
        words.each(&.chars.tally(hash))

        hash.should eq(
          {'c' => 1, 'r' => 2, 'y' => 2, 's' => 1, 't' => 1, 'a' => 1, 'l' => 1, 'u' => 1, 'b' => 1}
        )
      end

      it "updates existing hash with counts according to the value" do
        hash = {'a' => 1, 'b' => 1, 'c' => 1, 'd' => 1}
        words = ["crystal", "ruby"]
        words.each(&.chars.tally(hash))

        hash.should eq(
          {'a' => 2, 'b' => 2, 'c' => 2, 'd' => 1, 'r' => 2, 'y' => 2, 's' => 1, 't' => 1, 'l' => 1, 'u' => 1}
        )
      end

      it "ignores the default value" do
        hash = Hash(Char, Int32).new(100)
        words = ["crystal", "ruby"]
        words.each(&.chars.tally(hash))

        hash.should eq(
          {'c' => 1, 'r' => 2, 'y' => 2, 's' => 1, 't' => 1, 'a' => 1, 'l' => 1, 'u' => 1, 'b' => 1}
        )
      end

      it "returns a hash with Int64 counts according to the value" do
        hash = {} of Char => Int64
        words = ["crystal", "ruby"]
        words.each(&.chars.tally(hash))

        hash.should eq(
          {'c' => 1, 'r' => 2, 'y' => 2, 's' => 1, 't' => 1, 'a' => 1, 'l' => 1, 'u' => 1, 'b' => 1}
        )
      end

      it "tallies an interface type" do
        InterfaceEnumerable.new.tally.should eq({One.new => 1, Two.new => 1})
      end
    end
  end

  describe "to_a" do
    it "converts to an Array" do
      (1..3).to_a.should eq [1, 2, 3]
    end
  end

  describe "to_h" do
    it "for tuples" do
      hash = Tuple.new({"a", 1}, {"c", 2}).to_h
      hash.should be_a(Hash(String, Int32))
      hash.should eq({"a" => 1, "c" => 2})

      hash = Tuple.new({1, 1.0}, {'a', "aaa"}).to_h
      hash.should be_a(Hash(Int32 | Char, Float64 | String))
      hash.should eq({1 => 1.0, 'a' => "aaa"})
    end

    it "for array" do
      [['a', 'b'], ['c', 'd']].to_h.should eq({'a' => 'b', 'c' => 'd'})
    end

    it "with block" do
      (1..3).to_h { |i| {i, i ** 2} }.should eq({1 => 1, 2 => 4, 3 => 9})
    end
  end

  describe "zip" do
    it "works for Iterators as receiver" do
      SpecCountUpIterator.new(3).zip(1..3, 2..4).should eq([{0, 1, 2}, {1, 2, 3}, {2, 3, 4}])
    end
  end

  describe "zip?" do
    it "works for Iterators as receiver" do
      SpecCountUpIterator.new(3).zip?(1..2, 2..4).should eq([{0, 1, 2}, {1, 2, 3}, {2, nil, 4}])
    end
  end
end
