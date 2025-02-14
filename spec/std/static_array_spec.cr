require "spec"
require "spec/helpers/iterate"

describe "StaticArray" do
  it "creates with new" do
    a = StaticArray(Int32, 3).new 0
    a.size.should eq(3)
  end

  it "creates with new and value" do
    a = StaticArray(Int32, 3).new 1
    a.size.should eq(3)
    a[0].should eq(1)
    a[1].should eq(1)
    a[2].should eq(1)
  end

  it "creates with new and block" do
    a = StaticArray(Int32, 3).new { |i| i + 1 }
    a.size.should eq(3)
    a[0].should eq(1)
    a[1].should eq(2)
    a[2].should eq(3)
  end

  it "raises index out of bounds on read" do
    a = StaticArray(Int32, 3).new 0
    expect_raises IndexError do
      a[4]
    end
  end

  it "raises index out of bounds on write" do
    a = StaticArray(Int32, 3).new 0
    expect_raises IndexError do
      a[4] = 1
    end
  end

  it "allows using negative indices" do
    a = StaticArray(Int32, 3).new 0
    a[-1] = 2
    a[-1].should eq(2)
    a[2].should eq(2)
  end

  describe "==" do
    it "compares empty" do
      (StaticArray(Int32, 0).new(0)).should eq(StaticArray(Int32, 0).new(0))
      (StaticArray(Int32, 1).new(0)).should_not eq(StaticArray(Int32, 0).new(0))
      (StaticArray(Int32, 0).new(0)).should_not eq(StaticArray(Int32, 1).new(0))
    end

    it "compares elements" do
      a = StaticArray(Int32, 3).new { |i| i * 2 }
      a.should eq(StaticArray(Int32, 3).new { |i| i * 2 })
      a.should_not eq(StaticArray(Int32, 3).new { |i| i * 3 })
    end

    it "compares other" do
      (StaticArray(Int32, 0).new(0)).should_not eq(nil)
      (StaticArray(Int32, 3).new(0)).should eq(StaticArray(Int8, 3).new(0_i8))
    end
  end

  describe "<=>" do
    it "correctly compares two static arrays" do
      array1 = StaticArray(Int32, 3).new(5)
      array2 = StaticArray(Int32, 3).new(7)
      (array1 <=> array2).should be < 0
      (array2 <=> array1).should be > 0
      (array1 <=> array1).should eq 0
    end
  end

  describe "values_at" do
    it "returns the given indexes" do
      StaticArray(Int32, 4).new { |i| i + 1 }.values_at(1, 0, 2).should eq({2, 1, 3})
    end

    it "raises when passed an invalid index" do
      expect_raises IndexError do
        StaticArray(Int32, 1).new { |i| i + 1 }.values_at(10)
      end
    end
  end

  it "does to_s" do
    a = StaticArray(Int32, 3).new { |i| i + 1 }
    a.to_s.should eq("StaticArray[1, 2, 3]")
  end

  describe "#fill" do
    it "replaces values in a subrange" do
      a = StaticArray[0, 1, 2, 3, 4]
      a.fill(7)
      a.should eq(StaticArray[7, 7, 7, 7, 7])

      a = StaticArray[0, 1, 2, 3, 4]
      a.fill(7, 1, 2)
      a.should eq(StaticArray[0, 7, 7, 3, 4])

      a = StaticArray[0, 1, 2, 3, 4]
      a.fill(7, 2..3)
      a.should eq(StaticArray[0, 1, 7, 7, 4])

      a = StaticArray[0, 0, 0, 0, 0]
      a.fill { |i| i + 7 }
      a.should eq(StaticArray[7, 8, 9, 10, 11])

      a = StaticArray[0, 0, 0, 0, 0]
      a.fill(offset: 2) { |i| i * i }
      a.should eq(StaticArray[4, 9, 16, 25, 36])

      a = StaticArray[0, 0, 0, 0, 0]
      a.fill(1, 2) { |i| i + 7 }
      a.should eq(StaticArray[0, 8, 9, 0, 0])

      a = StaticArray[0, 0, 0, 0, 0]
      a.fill(2..3) { |i| i + 7 }
      a.should eq(StaticArray[0, 0, 9, 10, 0])
    end
  end

  it "shuffles" do
    a = StaticArray(Int32, 3).new { |i| i + 1 }
    a.shuffle!

    (a[0] + a[1] + a[2]).should eq(6)

    3.times do |i|
      a.should contain(i + 1)
    end
  end

  it "shuffles with a seed" do
    a = StaticArray(Int32, 10).new { |i| i + 1 }
    b = StaticArray(Int32, 10).new { |i| i + 1 }
    a.shuffle!(Random.new(42))
    b.shuffle!(Random.new(42))

    10.times do |i|
      a[i].should eq(b[i])
    end
  end

  it "reverse" do
    a = StaticArray(Int32, 3).new { |i| i + 1 }
    a.reverse!
    a[0].should eq(3)
    a[1].should eq(2)
    a[2].should eq(1)
  end

  it "does map" do
    a = StaticArray[0, 1, 2]
    b = a.map { |e| e * 2 }
    b.should eq(StaticArray[0, 2, 4])
  end

  it "does map!" do
    a = StaticArray(Int32, 3).new { |i| i + 1 }
    a.map! { |i| i + 1 }
    a[0].should eq(2)
    a[1].should eq(3)
    a[2].should eq(4)
  end

  it "does map_with_index" do
    a = StaticArray[1, 1, 2, 2]
    b = a.map_with_index { |e, i| e + i }
    b.should eq(StaticArray[1, 2, 4, 5])
  end

  it "does map_with_index, with offset" do
    a = StaticArray[1, 1, 2, 2]
    b = a.map_with_index(10) { |e, i| e + i }
    b.should eq(StaticArray[11, 12, 14, 15])
  end

  it "does map_with_index!" do
    a = StaticArray(Int32, 3).new { |i| i + 1 }
    a.map_with_index! { |e, i| i * 2 }
    a[0].should eq(0)
    a[1].should eq(2)
    a[2].should eq(4)
    a.should be_a(StaticArray(Int32, 3))
  end

  it "does map_with_index!, with offset" do
    a = StaticArray(Int32, 3).new { |i| i + 1 }
    a.map_with_index!(10) { |e, i| i * 2 }
    a[0].should eq(20)
    a[1].should eq(22)
    a[2].should eq(24)
    a.should be_a(StaticArray(Int32, 3))
  end

  describe "rotate!" do
    it do
      a = StaticArray[1, 2, 3]
      a.rotate!; a.should eq(StaticArray[2, 3, 1])
      a.rotate!; a.should eq(StaticArray[3, 1, 2])
      a.rotate!; a.should eq(StaticArray[1, 2, 3])
      a.rotate!; a.should eq(StaticArray[2, 3, 1])
    end

    it { a = StaticArray[1, 2, 3]; a.rotate!(0); a.should eq(StaticArray[1, 2, 3]) }
    it { a = StaticArray[1, 2, 3]; a.rotate!(1); a.should eq(StaticArray[2, 3, 1]) }
    it { a = StaticArray[1, 2, 3]; a.rotate!(2); a.should eq(StaticArray[3, 1, 2]) }
    it { a = StaticArray[1, 2, 3]; a.rotate!(3); a.should eq(StaticArray[1, 2, 3]) }
    it { a = StaticArray[1, 2, 3]; a.rotate!(4); a.should eq(StaticArray[2, 3, 1]) }
    it { a = StaticArray[1, 2, 3]; a.rotate!(3001); a.should eq(StaticArray[2, 3, 1]) }
    it { a = StaticArray[1, 2, 3]; a.rotate!(-1); a.should eq(StaticArray[3, 1, 2]) }
    it { a = StaticArray[1, 2, 3]; a.rotate!(-3001); a.should eq(StaticArray[3, 1, 2]) }

    it do
      a = StaticArray(Int32, 50).new { |i| i }
      a.rotate!(5)
      a.should eq(StaticArray[5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 0, 1, 2, 3, 4])
    end

    it do
      a = StaticArray(Int32, 50).new { |i| i }
      a.rotate!(-5)
      a.should eq(StaticArray[45, 46, 47, 48, 49, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44])
    end

    it do
      a = StaticArray(Int32, 50).new { |i| i }
      a.rotate!(20)
      a.should eq(StaticArray[20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19])
    end

    it do
      a = StaticArray(Int32, 50).new { |i| i }
      a.rotate!(-20)
      a.should eq(StaticArray[30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29])
    end
  end

  it "updates value" do
    a = StaticArray(Int32, 3).new { |i| i + 1 }
    a.update(1) { |x| x * 2 }
    a[0].should eq(1)
    a[1].should eq(4)
    a[2].should eq(3)
  end

  it "clones" do
    a = StaticArray(Array(Int32), 1).new { |i| [1] }
    b = a.clone
    b[0].should eq(a[0])
    b[0].should_not be(a[0])
  end

  {% for sort in ["sort".id, "unstable_sort".id] %}
    describe {{ "##{sort}" }} do
      it "sort without block" do
        a = StaticArray[3, 4, 1, 2, 5, 6]
        b = a.{{ sort }}
        b.should eq(StaticArray[1, 2, 3, 4, 5, 6])
        a.should_not eq(b)
      end

      it "sort with a block" do
        a = StaticArray["foo", "a", "hello"]
        b = a.{{ sort }} { |x, y| x.size <=> y.size }
        b.should eq(StaticArray["a", "foo", "hello"])
        a.should_not eq(b)
      end
    end

    describe {{ "##{sort}!" }} do
      it "sort! without block" do
        a = StaticArray[3, 4, 1, 2, 5, 6]
        a.{{ sort }}!
        a.should eq(StaticArray[1, 2, 3, 4, 5, 6])
      end

      it "sort! with a block" do
        a = StaticArray["foo", "a", "hello"]
        a.{{ sort }}! { |x, y| x.size <=> y.size }
        a.should eq(StaticArray["a", "foo", "hello"])
      end
    end

    # StaticArray#sort_by and #sort_by! don't compile on aarch64-darwin and
    # aarch64-linux-musl due to a codegen error caused by LLVM < 13.0.0.
    # See https://github.com/crystal-lang/crystal/issues/11358 for details.
    {% unless compare_versions(Crystal::LLVM_VERSION, "13.0.0") < 0 && flag?(:aarch64) && (flag?(:musl) || flag?(:darwin) || flag?(:android)) %}
      describe "{{ sort }}_by" do
        it "sorts by" do
          a = StaticArray["foo", "a", "hello"]
          b = a.{{ sort }}_by(&.size)
          b.should eq(StaticArray["a", "foo", "hello"])
          a.should_not eq(b)
        end
      end

      describe "{{ sort }}_by!" do
        it "sorts by!" do
          a = StaticArray["foo", "a", "hello"]
          a.{{ sort }}_by!(&.size)
          a.should eq(StaticArray["a", "foo", "hello"])
        end

        it "calls given block exactly once for each element" do
          calls = Hash(String, Int32).new(0)
          a = StaticArray["foo", "a", "hello"]
          a.{{ sort }}_by! { |e| calls[e] += 1; e.size }
          calls.should eq({"foo" => 1, "a" => 1, "hello" => 1})
        end
      end
    {% else %}
      pending "{{ sort }}_by"
      pending "{{ sort }}_by!"
    {% end %}
  {% end %}

  it_iterates "#each", [1, 2, 3], StaticArray[1, 2, 3].each
  it_iterates "#reverse_each", [3, 2, 1], StaticArray[1, 2, 3].reverse_each
  it_iterates "#each_index", [0, 1, 2], StaticArray[1, 2, 3].each_index
  it_iterates "#each_slice", [[0, 1], [2, 3], [4, 5], [6]], StaticArray[0, 1, 2, 3, 4, 5, 6].each_slice(2)
  it_iterates "#each_slice", [[0, 1, 2], [3, 4, 5], [6, 7, 8]], StaticArray[0, 1, 2, 3, 4, 5, 6, 7, 8].each_slice(3)
  it_iterates "#each_slice", [(0..15).to_a, (16..31).to_a, (32..47).to_a], StaticArray(Int32, 48).new(&.itself).each_slice(16)
  it_iterates "#each_slice", [(0..18).to_a, (19..37).to_a, (38..47).to_a], StaticArray(Int32, 48).new(&.itself).each_slice(19)
end
