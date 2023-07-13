require "spec"
require "set"
require "spec/helpers/iterate"

describe "Set" do
  describe "an empty set" do
    it "is empty" do
      Set(Nil).new.empty?.should be_true
    end

    it "has size 0" do
      Set(Nil).new.size.should eq(0)
    end
  end

  describe "new" do
    it "creates new set with enumerable without block" do
      set_from_array = Set.new([2, 4, 6, 4])
      set_from_array.size.should eq(3)
      set_from_array.to_a.sort.should eq([2, 4, 6])

      set_from_tuple = Set.new({1, "hello", 'x'})
      set_from_tuple.size.should eq(3)
      set_from_tuple.to_a.should contain(1)
      set_from_tuple.to_a.should contain("hello")
      set_from_tuple.to_a.should contain('x')
    end
  end

  describe "add" do
    it "adds and includes" do
      set = Set(Int32).new
      set.add 1
      set.includes?(1).should be_true
      set.size.should eq(1)
    end

    it "returns self" do
      set = Set(Int32).new
      set.add(1).should be(set)
    end
  end

  describe "add?" do
    it "returns true when object is not in the set" do
      set = Set(Int32).new
      set.add?(1).should be_true
    end

    it "returns false when object is in the set" do
      set = Set(Int32).new
      set.add?(1).should be_true
      set.should contain(1)
      set.add?(1).should be_false
    end
  end

  describe "delete" do
    it "deletes an object" do
      set = Set{1, 2, 3}
      set.delete 2
      set.size.should eq(2)
      set.should contain(1)
      set.should contain(3)
    end

    it "returns true when the object was present" do
      set = Set{1, 2, 3}
      set.delete(2).should be_true
    end

    it "returns false when the object was absent" do
      set = Set{1, 2, 3}
      set.delete(0).should be_false
    end
  end

  describe "dup" do
    it "creates a dup" do
      set1 = Set{[1, 2]}
      set2 = set1.dup

      set1.should eq(set2)
      set1.should_not be(set2)

      set1.to_a.first.should be(set2.to_a.first)

      set1 << [3]
      set2 << [4]

      set2.should eq(Set{[1, 2], [4]})
    end
  end

  describe "clone" do
    it "creates a clone" do
      set1 = Set{[1, 2]}
      set2 = set1.clone

      set1.should eq(set2)
      set1.should_not be(set2)

      set1.to_a.first.should_not be(set2.to_a.first)

      set1 << [3]
      set2 << [4]

      set2.should eq(Set{[1, 2], [4]})
    end
  end

  describe "==" do
    it "compares two sets" do
      set1 = Set{1, 2, 3}
      set2 = Set{1, 2, 3}
      set3 = Set{1, 2, 3, 4}

      set1.should eq(set1)
      set1.should eq(set2)
      set1.should_not eq(set3)
    end
  end

  describe "concat" do
    it "adds all the other elements" do
      set = Set{1, 4, 8}
      set.concat [1, 9, 10]
      set.should eq(Set{1, 4, 8, 9, 10})
    end

    it "returns self" do
      set = Set{1, 4, 8}
      set.concat([1, 9, 10]).should be(set)
    end
  end

  it "does &" do
    set1 = Set{1, 2, 3}
    set2 = Set{4, 2, 5, 3}
    set3 = set1 & set2
    set3.should eq(Set{2, 3})
  end

  it "does |" do
    set1 = Set{1, 2, 3}
    set2 = Set{4, 2, 5, "3"}
    set3 = set1 | set2
    set3.should eq(Set{1, 2, 3, 4, 5, "3"})
  end

  it "aliases + to |" do
    set1 = Set{1, 1, 2, 3}
    set2 = Set{3, 4, 5}
    set3 = set1 + set2
    set4 = set1 | set2
    set3.should eq(set4)
  end

  it "does -" do
    set1 = Set{1, 2, 3, 4, 5}
    set2 = Set{2, 4, 6}
    set3 = set1 - set2
    set3.should eq(Set{1, 3, 5})
  end

  it "does -" do
    set1 = Set{1, 2, 3, 4, 5}
    set2 = Set{2, 4, 'a'}
    set3 = set1 - set2
    set3.should eq(Set{1, 3, 5})
  end

  it "does -" do
    set1 = Set{1, 2, 3, 4, 'b'}
    set2 = Set{2, 4, 5}
    set3 = set1 - set2
    set3.should eq(Set{1, 3, 'b'})
  end

  it "does -" do
    set1 = Set{1, 2, 3, 4, 5}
    set2 = [2, 4, 6]
    set3 = set1 - set2
    set3.should eq(Set{1, 3, 5})
  end

  it "does -" do
    set1 = Set{1, 2, 3, 4, 5}
    set2 = [2, 4, 'a']
    set3 = set1 - set2
    set3.should eq(Set{1, 3, 5})
  end

  it "does -" do
    set1 = Set{1, 2, 3, 4, 'b'}
    set2 = [2, 4, 5]
    set3 = set1 - set2
    set3.should eq(Set{1, 3, 'b'})
  end

  it "does ^" do
    set1 = Set{1, 2, 3, 4, 5}
    set2 = Set{2, 4, 6}
    set3 = set1 ^ set2
    set3.should eq(Set{1, 3, 5, 6})
  end

  it "does ^" do
    set1 = Set{1, 2, 3, 4, 5}
    set2 = Set{2, 4, 'a'}
    set3 = set1 ^ set2
    set3.should eq(Set{1, 3, 5, 'a'})
  end

  it "does ^" do
    set1 = Set{1, 2, 3, 4, 'b'}
    set2 = Set{2, 4, 5}
    set3 = set1 ^ set2
    set3.should eq(Set{1, 3, 5, 'b'})
  end

  it "does ^" do
    set1 = Set{1, 2, 3, 4, 5}
    set2 = [2, 4, 6]
    set3 = set1 ^ set2
    set3.should eq(Set{1, 3, 5, 6})
  end

  it "does ^" do
    set1 = Set{1, 2, 3, 4, 5}
    set2 = [2, 4, 'a']
    set3 = set1 ^ set2
    set3.should eq(Set{1, 3, 5, 'a'})
  end

  it "does ^" do
    set1 = Set{1, 2, 3, 4, 'b'}
    set2 = [2, 4, 5]
    set3 = set1 ^ set2
    set3.should eq(Set{1, 3, 5, 'b'})
  end

  it "does subtract" do
    set1 = Set{1, 2, 3, 4, 5}
    set2 = Set{2, 4, 6}
    set1.subtract set2
    set1.should eq(Set{1, 3, 5})
  end

  it "does subtract" do
    set1 = Set{1, 2, 3, 4, 5}
    set2 = Set{2, 4, 'a'}
    set1.subtract set2
    set1.should eq(Set{1, 3, 5})
  end

  it "does subtract" do
    set1 = Set{1, 2, 3, 4, 'b'}
    set2 = Set{2, 4, 5}
    set1.subtract set2
    set1.should eq(Set{1, 3, 'b'})
  end

  it "does subtract" do
    set1 = Set{1, 2, 3, 4, 5}
    set2 = [2, 4, 6]
    set1.subtract set2
    set1.should eq(Set{1, 3, 5})
  end

  it "does subtract" do
    set1 = Set{1, 2, 3, 4, 5}
    set2 = [2, 4, 'a']
    set1.subtract set2
    set1.should eq(Set{1, 3, 5})
  end

  it "does subtract" do
    set1 = Set{1, 2, 3, 4, 'b'}
    set2 = [2, 4, 5]
    set1.subtract set2
    set1.should eq(Set{1, 3, 'b'})
  end

  it "does to_a" do
    Set{1, 2, 3}.to_a.should eq([1, 2, 3])
  end

  it "does to_s" do
    Set{1, 2, 3}.to_s.should eq("Set{1, 2, 3}")
    Set{"foo"}.to_s.should eq(%(Set{"foo"}))
  end

  it "does clear" do
    x = Set{1, 2, 3}
    x.to_a.should eq([1, 2, 3])
    x.clear.should be(x)
    x << 1
    x.to_a.should eq([1])
  end

  it "checks intersects" do
    set = Set{3, 4, 5}
    empty_set = Set(Int32).new

    set.intersects?(set).should be_true
    set.intersects?(Set{2, 4}).should be_true
    set.intersects?(Set{5, 6, 7}).should be_true
    set.intersects?(Set{1, 2, 6, 8, 4}).should be_true

    set.intersects?(empty_set).should be_false
    set.intersects?(Set{0, 2}).should be_false
    set.intersects?(Set{0, 2, 6}).should be_false
    set.intersects?(Set{0, 2, 6, 8, 10}).should be_false

    # Make sure set hasn't changed
    set.should eq(Set{3, 4, 5})
  end

  it "compares hashes of sets" do
    h1 = {Set{1, 2, 3} => 1}
    h2 = {Set{1, 2, 3} => 1}
    h1.should eq(h2)
  end

  it "does each" do
    set = Set{1, 2, 3}
    i = 1
    set.each do |v|
      v.should eq(i)
      i += 1
    end.should be_nil
    i.should eq(4)
  end

  it_iterates "#each", [1, 2, 3], Set{1, 2, 3}.each

  it "#subset_of?" do
    set = Set{1, 2, 3}
    empty_set = Set(Int32).new

    set.subset_of?(Set{1, 2, 3, 4}).should be_true
    set.subset_of?(Set{1, 2, 3, "4"}).should be_true
    set.subset_of?(Set{1, 2, 3}).should be_true
    set.subset_of?(Set{1, 2}).should be_false
    set.subset_of?(empty_set).should be_false

    empty_set.subset_of?(Set{1}).should be_true
    empty_set.subset_of?(empty_set).should be_true
  end

  it "#proper_subset_of?" do
    set = Set{1, 2, 3}
    empty_set = Set(Int32).new

    set.proper_subset_of?(Set{1, 2, 3, 4}).should be_true
    set.proper_subset_of?(Set{1, 2, 3, "4"}).should be_true
    set.proper_subset_of?(Set{1, 2, 3}).should be_false
    set.proper_subset_of?(Set{1, 2}).should be_false
    set.proper_subset_of?(empty_set).should be_false

    empty_set.proper_subset_of?(Set{1}).should be_true
    empty_set.proper_subset_of?(empty_set).should be_false
  end

  it "#superset_of?" do
    set = Set{1, 2, "3"}
    empty_set = Set(Int32).new

    set.superset_of?(empty_set).should be_true
    set.superset_of?(Set{1, 2}).should be_true
    set.superset_of?(Set{1, 2, "3"}).should be_true
    set.superset_of?(Set{1, 2, 3}).should be_false
    set.superset_of?(Set{1, 2, 3, 4}).should be_false
    set.superset_of?(Set{1, 4}).should be_false

    empty_set.superset_of?(empty_set).should be_true
  end

  it "#proper_superset_of?" do
    set = Set{1, 2, "3"}
    empty_set = Set(Int32).new

    set.proper_superset_of?(empty_set).should be_true
    set.proper_superset_of?(Set{1, 2}).should be_true
    set.proper_superset_of?(Set{1, 2, "3"}).should be_false
    set.proper_superset_of?(Set{1, 2, 3}).should be_false
    set.proper_superset_of?(Set{1, 2, 3, 4}).should be_false
    set.proper_superset_of?(Set{1, 4}).should be_false

    empty_set.proper_superset_of?(empty_set).should be_false
  end

  it "has object_id" do
    Set(Int32).new.object_id.should be > 0
  end

  typeof(Set(Int32).new(initial_capacity: 1234))

  describe "compare_by_identity" do
    it "compares by identity" do
      string = "foo"
      set = Set{string, "bar", "baz"}
      set.compare_by_identity?.should be_false
      set.should contain(string)

      set.compare_by_identity
      set.compare_by_identity?.should be_true

      set.should_not contain("fo" + "o")
      set.should contain(string)
    end

    it "retains compare_by_identity on dup" do
      set = Set(String).new.compare_by_identity
      set.dup.compare_by_identity?.should be_true
    end

    it "retains compare_by_identity on clone" do
      set = Set(String).new.compare_by_identity
      set.clone.compare_by_identity?.should be_true
    end
  end

  describe "keep_if" do
    it "keeps only elements that evaluate to true" do
      set = Set{1, 2, 3}
      set.keep_if { |n| n < 2 }
      set.should eq(Set{1})
    end

    it "returns self" do
      set = Set{1, 2, 3}
      set.keep_if { |n| n < 2 }.should be(set)
    end
  end

  describe "select!" do
    it "keeps only elements that evaluate to true" do
      set = Set{1, 2, 3}
      set.select! { |n| n < 2 }
      set.should eq(Set{1})
    end

    it "returns self if changes were made" do
      set = Set{1, 2, 3}
      set.select! { |n| n < 2 }.should eq(set)
    end

    it "returns nil if no changes were made" do
      set = Set{1, 2, 3}
      set.select! { |n| n < 4 }.should be_nil
    end
  end

  describe "filter!" do
    it "keeps only elements that evaluate to true" do
      set = Set{1, 2, 3}
      set.filter! { |n| n < 2 }
      set.should eq(Set{1})
    end

    it "returns self if changes were made" do
      set = Set{1, 2, 3}
      set.filter! { |n| n < 2 }.should eq(set)
    end

    it "returns nil if no changes were made" do
      set = Set{1, 2, 3}
      set.filter! { |n| n < 4 }.should be_nil
    end
  end

  describe "delete_if" do
    it "keeps only elements that evaluate to false" do
      set = Set{1, 2, 3}
      set.delete_if { |n| n < 2 }
      set.should eq(Set{2, 3})
    end

    it "returns self" do
      set = Set{1, 2, 3}
      set.delete_if { |n| n < 2 }.should be(set)
    end
  end

  describe "reject!" do
    it "keeps only elements that evaluate to false" do
      set = Set{1, 2, 3}
      set.reject! { |n| n < 2 }
      set.should eq(Set{2, 3})
    end

    it "returns self if changes were made" do
      set = Set{1, 2, 3}
      set.reject! { |n| n < 2 }.should eq(set)
    end

    it "returns nil if no changes were made" do
      set = Set{1, 2, 3}
      set.reject! { |n| n > 4 }.should be_nil
    end
  end

  describe "map!" do
    it "transforms elements" do
      set = Set{1, 2, 3}
      set.map! { |n| n + 1 }
      set.should eq(Set{2, 3, 4})
    end

    it "returns nil" do
      set = Set{1, 2, 3}
      set.map! { |n| n + 1 }.should be_nil
    end
  end
end
