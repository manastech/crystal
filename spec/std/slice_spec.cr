require "spec"
require "spec/helpers/iterate"
require "spec/helpers/string"

private class BadSortingClass
  include Comparable(self)

  def <=>(other)
    1
  end
end

private class Spaceship
  getter value : Float64

  def initialize(@value : Float64, @return_nil = false)
  end

  def <=>(other : Spaceship)
    return nil if @return_nil

    value <=> other.value
  end
end

private def is_stable_sort(mutable, &block)
  n = 42
  # [Spaceship.new(0), ..., Spaceship.new(n - 1), Spaceship.new(0), ..., Spaceship.new(n - 1)]
  slice = Slice.new(n * 2) { |i| Spaceship.new((i % n).to_f) }
  # [Spaceship.new(0), Spaceship.new(0), ..., Spaceship.new(n - 1), Spaceship.new(n - 1)]
  expected = Slice.new(n * 2) { |i| slice[i % 2 * n + i // 2] }

  if mutable
    yield slice
    result = slice
  else
    result = yield slice
    result.should_not eq(slice)
  end

  result.size.should eq(expected.size)
  expected.zip(result) do |exp, res|
    res.should be(exp) # reference-equality is necessary to check sorting is stable.
  end
end

describe "Slice" do
  it "gets pointer and size" do
    pointer = Pointer.malloc(1, 0)
    slice = Slice.new(pointer, 1)
    slice.to_unsafe.should eq(pointer)
    slice.size.should eq(1)
  end

  it "does []?" do
    slice = Slice.new(3) { |i| i + 1 }
    3.times do |i|
      slice[i]?.should eq(i + 1)
    end
    slice[-1]?.should eq(3)
    slice[-2]?.should eq(2)
    slice[-3]?.should eq(1)

    slice[-4]?.should be_nil
    slice[3]?.should be_nil
  end

  it "does []" do
    slice = Slice.new(3) { |i| i + 1 }
    3.times do |i|
      slice[i].should eq(i + 1)
    end
    slice[-1].should eq(3)
    slice[-2].should eq(2)
    slice[-3].should eq(1)

    expect_raises(IndexError) { slice[-4] }
    expect_raises(IndexError) { slice[3] }
  end

  it "does []=" do
    slice = Slice.new(3, 0)
    slice[0] = 1
    slice[0].should eq(1)

    expect_raises(IndexError) { slice[-4] = 1 }
    expect_raises(IndexError) { slice[3] = 1 }
  end

  it "#+(Int)" do
    slice = Slice.new(3) { |i| i + 1 }

    slice1 = slice + 1
    slice1.size.should eq(2)
    slice1[0].should eq(2)
    slice1[1].should eq(3)

    slice3 = slice + 3
    slice3.size.should eq(0)

    expect_raises(IndexError) { slice + 4 }
    expect_raises(IndexError) { slice + (-1) }
  end

  it "does []? with start and count" do
    slice = Slice.new(4) { |i| i + 1 }

    slice1 = slice[1, 2]?
    slice1.should_not be_nil
    slice1 = slice1.not_nil!
    slice1.size.should eq(2)
    slice1.to_unsafe.should eq(slice.to_unsafe + 1)
    slice1[0].should eq(2)
    slice1[1].should eq(3)

    slice2 = slice[-1, 1]?
    slice2.should_not be_nil
    slice2 = slice2.not_nil!
    slice2.size.should eq(1)
    slice2.to_unsafe.should eq(slice.to_unsafe + 3)

    slice[3, 2]?.should be_nil
    slice[0, 5]?.should be_nil
    expect_raises(ArgumentError, "Negative count: -1") { slice[3, -1]? }
  end

  it "does []? with range" do
    slice = Slice.new(4) { |i| i + 1 }

    slice1 = slice[1..2]?
    slice1.should_not be_nil
    slice1 = slice1.not_nil!
    slice1.size.should eq(2)
    slice1.to_unsafe.should eq(slice.to_unsafe + 1)
    slice1[0].should eq(2)
    slice1[1].should eq(3)

    slice[4..7]?.should be_nil
    slice[3..4]?.should be_nil
    slice[-2..4]?.should be_nil
    slice[-6..-5]?.should be_nil
  end

  it "does [] with start and count" do
    slice = Slice.new(4) { |i| i + 1 }

    slice1 = slice[1, 2]
    slice1.size.should eq(2)
    slice1.to_unsafe.should eq(slice.to_unsafe + 1)
    slice1[0].should eq(2)
    slice1[1].should eq(3)

    slice2 = slice[-1, 1]
    slice2.size.should eq(1)
    slice2.to_unsafe.should eq(slice.to_unsafe + 3)

    expect_raises(IndexError) { slice[3, 2] }
    expect_raises(IndexError) { slice[0, 5] }
    expect_raises(ArgumentError, "Negative count: -1") { slice[3, -1] }
  end

  it "does empty?" do
    Slice.new(0, 0).empty?.should be_true
    Slice.new(1, 0).empty?.should be_false
  end

  it "raises if size is negative on new" do
    expect_raises(ArgumentError) { Slice.new(-1, 0) }
  end

  it "does to_s" do
    slice = Slice.new(4) { |i| i + 1 }
    slice.to_s.should eq("Slice[1, 2, 3, 4]")
  end

  it "does to_s for bytes" do
    slice = Bytes[1, 2, 3]
    slice.to_s.should eq("Bytes[1, 2, 3]")
  end

  describe "#fill" do
    it "replaces values in a subrange" do
      slice = Slice[0, 1, 2, 3, 4]
      slice.fill(7)
      slice.should eq(Slice[7, 7, 7, 7, 7])

      slice = Slice[0, 1, 2, 3, 4]
      slice.fill(7, 1, 2)
      slice.should eq(Slice[0, 7, 7, 3, 4])
      slice.fill(8, 4, 10)
      slice.should eq(Slice[0, 7, 7, 3, 8])

      slice = Slice[0, 1, 2, 3, 4]
      slice.fill(7, 2..3)
      slice.should eq(Slice[0, 1, 7, 7, 4])
      slice.fill(8, -2..10)
      slice.should eq(Slice[0, 1, 7, 8, 8])

      slice = Slice[0, 0, 0, 0, 0]
      slice.fill { |i| i + 7 }
      slice.should eq(Slice[7, 8, 9, 10, 11])

      slice = Slice[0, 0, 0, 0, 0]
      slice.fill(offset: 2) { |i| i * i }
      slice.should eq(Slice[4, 9, 16, 25, 36])

      slice = Slice[0, 0, 0, 0, 0]
      slice.fill(1, 2) { |i| i + 7 }
      slice.should eq(Slice[0, 8, 9, 0, 0])

      slice = Slice[0, 0, 0, 0, 0]
      slice.fill(2..3) { |i| i + 7 }
      slice.should eq(Slice[0, 0, 9, 10, 0])
      slice.fill(-2..10, &.itself)
      slice.should eq(Slice[0, 0, 9, 3, 4])
    end

    it "works for bytes" do
      slice = Bytes[0, 1, 2, 3, 4]
      slice.fill(7)
      slice.should eq(Bytes[7, 7, 7, 7, 7])

      slice = Bytes[0, 1, 2, 3, 4]
      slice.fill(7, 1, 2)
      slice.should eq(Bytes[0, 7, 7, 3, 4])

      slice = Bytes[0, 1, 2, 3, 4]
      slice.fill(7, 2..3)
      slice.should eq(Bytes[0, 1, 7, 7, 4])
    end
  end

  it "does copy_from pointer" do
    pointer = Pointer.malloc(4) { |i| i + 1 }
    slice = Slice.new(4, 0)
    slice.copy_from(pointer, 4)
    4.times { |i| slice[i].should eq(i + 1) }

    expect_raises(IndexError) { slice.copy_from(pointer, 5) }
  end

  it "does copy_to pointer" do
    pointer = Pointer.malloc(4, 0)
    slice = Slice.new(4) { |i| i + 1 }
    slice.copy_to(pointer, 4)
    4.times { |i| pointer[i].should eq(i + 1) }

    expect_raises(IndexError) { slice.copy_to(pointer, 5) }
  end

  describe ".copy_to(Slice)" do
    it "copies bytes" do
      src = Slice.new(4) { 'a' }
      dst = Slice.new(4) { 'b' }

      src.copy_to(dst)
      dst.should eq(src)
    end

    it "raises if dst is smaller" do
      src = Slice.new(8) { 'a' }
      dst = Slice.new(4) { 'b' }

      expect_raises(IndexError) { src.copy_to(dst) }
    end

    it "copies at most src.size" do
      src = Slice.new(4) { 'a' }
      dst = Slice.new(8) { 'b' }

      src.copy_to(dst)
      dst.should eq(Slice['a', 'a', 'a', 'a', 'b', 'b', 'b', 'b'])
    end
  end

  describe ".copy_from(Slice)" do
    it "copies bytes" do
      src = Slice.new(4) { 'a' }
      dst = Slice.new(4) { 'b' }

      dst.copy_from(src)
      dst.should eq(src)
    end

    it "raises if dst is smaller" do
      src = Slice.new(8) { 'a' }
      dst = Slice.new(4) { 'b' }

      expect_raises(IndexError) { dst.copy_from(src) }
    end

    it "copies at most src.size" do
      src = Slice.new(4) { 'a' }
      dst = Slice.new(8) { 'b' }

      dst.copy_from(src)
      dst.should eq(Slice['a', 'a', 'a', 'a', 'b', 'b', 'b', 'b'])
    end
  end

  describe ".move_to(Slice)" do
    it "moves bytes" do
      src = Slice.new(4) { 'a' }
      dst = Slice.new(4) { 'b' }

      src.move_to(dst)
      dst.should eq(src)
    end

    it "raises if dst is smaller" do
      src = Slice.new(8) { 'a' }
      dst = Slice.new(4) { 'b' }

      expect_raises(IndexError) { src.move_to(dst) }
    end

    it "moves most src.size" do
      src = Slice.new(4) { 'a' }
      dst = Slice.new(8) { 'b' }

      src.move_to(dst)
      dst.should eq(Slice['a', 'a', 'a', 'a', 'b', 'b', 'b', 'b'])
    end

    it "handles intersecting ranges" do
      # Test with ranges offset by 0 to 8 bytes
      (0..8).each do |offset|
        buf = Slice.new(16) { |i| 'a' + i }
        dst = buf[0, 8]
        src = buf[offset, 8]

        src.move_to(dst)

        result = (0..7).map { |i| 'a' + i + offset }
        dst.should eq(Slice.new(result.to_unsafe, result.size))
      end
    end
  end

  describe ".move_from(Slice)" do
    it "moves bytes" do
      src = Slice.new(4) { 'a' }
      dst = Slice.new(4) { 'b' }

      dst.move_from(src)
      dst.should eq(src)
    end

    it "raises if dst is smaller" do
      src = Slice.new(8) { 'a' }
      dst = Slice.new(4) { 'b' }

      expect_raises(IndexError) { dst.move_from(src) }
    end

    it "moves at most src.size" do
      src = Slice.new(4) { 'a' }
      dst = Slice.new(8) { 'b' }

      dst.move_from(src)
      dst.should eq(Slice['a', 'a', 'a', 'a', 'b', 'b', 'b', 'b'])
    end

    it "handles intersecting ranges" do
      # Test with ranges offset by 0 to 8 bytes
      (0..8).each do |offset|
        buf = Slice.new(16) { |i| 'a' + i }
        dst = buf[0, 8]
        src = buf[offset, 8]

        dst.move_from(src)

        result = (0..7).map { |i| 'a' + i + offset }
        dst.should eq(Slice.new(result.to_unsafe, result.size))
      end
    end
  end

  describe "#unsafe_slice_of" do
    it "reinterprets a slice's elements" do
      slice = Bytes.new(10) { |i| i.to_u8 + 1 }

      {% if IO::ByteFormat::SystemEndian == IO::ByteFormat::LittleEndian %}
        slice.unsafe_slice_of(Int16).should eq(Int16.slice(0x0201, 0x0403, 0x0605, 0x0807, 0x0A09))
        slice.unsafe_slice_of(Int32).should eq(Int32.slice(0x04030201, 0x08070605))

        slice.unsafe_slice_of(UInt64)[0] = 0x1122_3344_5566_7788_u64
        slice.should eq(Bytes[0x88, 0x77, 0x66, 0x55, 0x44, 0x33, 0x22, 0x11, 0x09, 0x0A])
      {% else %}
        slice.unsafe_slice_of(Int16).should eq(Int16.slice(0x0102, 0x0304, 0x0506, 0x0708, 0x090A))
        slice.unsafe_slice_of(Int32).should eq(Int32.slice(0x01020304, 0x05060708))

        slice.unsafe_slice_of(UInt64)[0] = 0x1122_3344_5566_7788_u64
        slice.should eq(Bytes[0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88, 0x09, 0x0A])
      {% end %}
    end
  end

  describe "#to_unsafe_bytes" do
    it "reinterprets a slice's elements as bytes" do
      slice = Slice[0x01020304, -0x01020304]
      bytes = slice.to_unsafe_bytes

      {% if IO::ByteFormat::SystemEndian == IO::ByteFormat::LittleEndian %}
        bytes.should eq(Bytes[0x04, 0x03, 0x02, 0x01, 0xFC, 0xFC, 0xFD, 0xFE])
        bytes[3] = 0x55
        slice[0].should eq(0x55020304)
      {% else %}
        bytes.should eq(Bytes[0x01, 0x02, 0x03, 0x04, 0xFE, 0xFD, 0xFC, 0xFC])
        bytes[3] = 0x55
        slice[0].should eq(0x01020355)
      {% end %}
    end
  end

  describe "#hexstring" do
    it "works for Bytes" do
      slice = Bytes.new(4) { |i| i.to_u8 + 1 }
      slice.hexstring.should eq("01020304")
    end
  end

  describe "#hexdump" do
    it "works for empty slice" do
      Bytes.empty.hexdump.should eq("")

      io = IO::Memory.new
      Bytes.empty.hexdump(io).should eq(0)
      io.to_s.should eq("")
    end

    it "works for Bytes" do
      slice = Bytes.new(96) { |i| i.to_u8 + 32 }
      assert_prints slice.hexdump, <<-EOF
        00000000  20 21 22 23 24 25 26 27  28 29 2a 2b 2c 2d 2e 2f   !"#$%&'()*+,-./
        00000010  30 31 32 33 34 35 36 37  38 39 3a 3b 3c 3d 3e 3f  0123456789:;<=>?
        00000020  40 41 42 43 44 45 46 47  48 49 4a 4b 4c 4d 4e 4f  @ABCDEFGHIJKLMNO
        00000030  50 51 52 53 54 55 56 57  58 59 5a 5b 5c 5d 5e 5f  PQRSTUVWXYZ[\\]^_
        00000040  60 61 62 63 64 65 66 67  68 69 6a 6b 6c 6d 6e 6f  `abcdefghijklmno
        00000050  70 71 72 73 74 75 76 77  78 79 7a 7b 7c 7d 7e 7f  pqrstuvwxyz{|}~.\n
        EOF

      plus = Bytes.new(101) { |i| i.to_u8 + 32 }
      assert_prints plus.hexdump, <<-EOF
        00000000  20 21 22 23 24 25 26 27  28 29 2a 2b 2c 2d 2e 2f   !"#$%&'()*+,-./
        00000010  30 31 32 33 34 35 36 37  38 39 3a 3b 3c 3d 3e 3f  0123456789:;<=>?
        00000020  40 41 42 43 44 45 46 47  48 49 4a 4b 4c 4d 4e 4f  @ABCDEFGHIJKLMNO
        00000030  50 51 52 53 54 55 56 57  58 59 5a 5b 5c 5d 5e 5f  PQRSTUVWXYZ[\\]^_
        00000040  60 61 62 63 64 65 66 67  68 69 6a 6b 6c 6d 6e 6f  `abcdefghijklmno
        00000050  70 71 72 73 74 75 76 77  78 79 7a 7b 7c 7d 7e 7f  pqrstuvwxyz{|}~.
        00000060  80 81 82 83 84                                    .....\n
        EOF

      num = Bytes.new(10) { |i| i.to_u8 + 48 }
      assert_prints num.hexdump, <<-EOF
        00000000  30 31 32 33 34 35 36 37  38 39                    0123456789\n
        EOF
    end
  end

  it_iterates "#each", [1, 2, 3], Slice[1, 2, 3].each
  it_iterates "#reverse_each", [3, 2, 1], Slice[1, 2, 3].reverse_each
  it_iterates "#each_index", [0, 1, 2], Slice[1, 2, 3].each_index

  it "does to_a" do
    slice = Slice.new(3) { |i| i }
    ary = slice.to_a
    ary.should eq([0, 1, 2])
  end

  it "does rindex" do
    slice = "foobar".to_slice
    slice.rindex('o'.ord.to_u8).should eq(2)
    slice.rindex('z'.ord.to_u8).should be_nil
  end

  it "does bytesize" do
    slice = Slice(Int32).new(2)
    slice.bytesize.should eq(8)
  end

  describe "==" do
    it "does ==" do
      a = Slice.new(3) { |i| i }
      b = Slice.new(3) { |i| i }
      c = Slice.new(3) { |i| i + 1 }
      a.should eq(b)
      a.should_not eq(c)
    end

    it "does == with same type, different runtime instances" do
      a = Slice.new(3, &.to_s)
      b = Slice.new(3, &.to_s)
      a.should eq(b)
    end

    it "does == for bytes" do
      a = Bytes[1, 2, 3]
      b = Bytes[1, 2, 3]
      c = Bytes[1, 2, 4]
      a.should eq(b)
      a.should_not eq(c)
    end

    it "different types" do
      a = Slice[1, 2, 3]
      b = Slice[1.0, 2.0, 3.0]
      c = Slice[1.0, 2.0, 2.9]
      a.should eq(b)
      a.should_not eq(c)
    end
  end

  it "#same?" do
    slice = Slice[1, 2, 3]

    slice.should be slice
    slice.should_not be slice.dup
    slice.should_not be Slice[1, 2, 3]

    (slice + 1).should be slice + 1
    slice.should_not be slice + 1

    (slice[0, 2]).should be slice[0, 2]
    slice.should_not be slice[0, 2]
  end

  it "does macro []" do
    slice = Slice[1, 'a', "foo"]
    slice.should be_a(Slice(Int32 | Char | String))
    slice.size.should eq(3)
    slice[0].should eq(1)
    slice[1].should eq('a')
    slice[2].should eq("foo")
  end

  it "does macro [] with numbers (#3055)" do
    slice = Bytes[1, 2, 3]
    slice.should be_a(Bytes)
    slice.to_a.should eq([1, 2, 3])
  end

  it "does Bytes[]" do
    slice = Bytes[]
    slice.should be_a(Bytes)
    slice.should be_empty
  end

  it "uses percent vars in [] macro (#2954)" do
    slices = itself(Slice[1, 2], Slice[3])
    slices[0].to_a.should eq([1, 2])
    slices[1].to_a.should eq([3])
  end

  it "reverses" do
    slice = Bytes[1, 2, 3]
    slice.reverse!
    slice.to_a.should eq([3, 2, 1])
  end

  it "shuffles" do
    a = Bytes[1, 2, 3]
    a.shuffle!
    b = [1, 2, 3]
    3.times { a.should contain(b.shift) }
  end

  it "does map" do
    a = Slice[1, 2, 3]
    b = a.map { |x| x * 2 }
    b.should eq(Slice[2, 4, 6])
  end

  it "does map!" do
    a = Slice[1, 2, 3]
    b = a.map! { |x| x * 2 }
    a.should eq(Slice[2, 4, 6])
    a.to_unsafe.should eq(b.to_unsafe)
  end

  it "does map_with_index" do
    a = Slice[1, 1, 2, 2]
    b = a.map_with_index { |e, i| e + i }
    b.should eq(Slice[1, 2, 4, 5])
  end

  it "does map_with_index, with offset" do
    a = Slice[1, 1, 2, 2]
    b = a.map_with_index(10) { |e, i| e + i }
    b.should eq(Slice[11, 12, 14, 15])
  end

  it "does map_with_index!" do
    a = Slice[1, 1, 2, 2]
    b = a.map_with_index! { |e, i| e + i }
    a.should eq(Slice[1, 2, 4, 5])
    a.to_unsafe.should eq(b.to_unsafe)
  end

  it "does map_with_index!, with offset" do
    a = Slice[1, 1, 2, 2]
    b = a.map_with_index!(10) { |e, i| e + i }
    a.should eq(Slice[11, 12, 14, 15])
    a.to_unsafe.should eq(b.to_unsafe)
  end

  describe "rotate!" do
    it do
      a = Slice[1, 2, 3]
      a.rotate!.to_unsafe.should eq(a.to_unsafe); a.should eq(Slice[2, 3, 1])
      a.rotate!.to_unsafe.should eq(a.to_unsafe); a.should eq(Slice[3, 1, 2])
      a.rotate!.to_unsafe.should eq(a.to_unsafe); a.should eq(Slice[1, 2, 3])
      a.rotate!.to_unsafe.should eq(a.to_unsafe); a.should eq(Slice[2, 3, 1])
    end

    it { a = Slice[1, 2, 3]; a.rotate!(0); a.should eq(Slice[1, 2, 3]) }
    it { a = Slice[1, 2, 3]; a.rotate!(1); a.should eq(Slice[2, 3, 1]) }
    it { a = Slice[1, 2, 3]; a.rotate!(2); a.should eq(Slice[3, 1, 2]) }
    it { a = Slice[1, 2, 3]; a.rotate!(3); a.should eq(Slice[1, 2, 3]) }
    it { a = Slice[1, 2, 3]; a.rotate!(4); a.should eq(Slice[2, 3, 1]) }
    it { a = Slice[1, 2, 3]; a.rotate!(3001); a.should eq(Slice[2, 3, 1]) }
    it { a = Slice[1, 2, 3]; a.rotate!(-1); a.should eq(Slice[3, 1, 2]) }
    it { a = Slice[1, 2, 3]; a.rotate!(-3001); a.should eq(Slice[3, 1, 2]) }

    it do
      a = Slice(Int32).new(50) { |i| i }
      a.rotate!(5)
      a.should eq(Slice[5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 0, 1, 2, 3, 4])
    end

    it do
      a = Slice(Int32).new(50) { |i| i }
      a.rotate!(-5)
      a.should eq(Slice[45, 46, 47, 48, 49, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44])
    end

    it do
      a = Slice(Int32).new(50) { |i| i }
      a.rotate!(20)
      a.should eq(Slice[20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19])
    end

    it do
      a = Slice(Int32).new(50) { |i| i }
      a.rotate!(-20)
      a.should eq(Slice[30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29])
    end
  end

  it "creates empty slice" do
    slice = Slice(Int32).empty
    slice.should be_empty
  end

  it "creates read-only slice" do
    slice = Slice.new(3, 0, read_only: true)
    slice.read_only?.should be_true
    expect_raises(Exception, "Can't write to read-only Slice") { slice[0] = 1 }
    expect_raises(Exception, "Can't write to read-only Slice") { slice.update(0, &.itself) }
    expect_raises(Exception, "Can't write to read-only Slice") { slice.swap(0, 1) }
    expect_raises(Exception, "Can't write to read-only Slice") { slice.reverse! }
    expect_raises(Exception, "Can't write to read-only Slice") { slice.fill(0) }
    expect_raises(Exception, "Can't write to read-only Slice") { slice.fill(0, 0, 0) }
    expect_raises(Exception, "Can't write to read-only Slice") { slice.fill(0, 0..0) }
    expect_raises(Exception, "Can't write to read-only Slice") { slice.fill(&.itself) }
    expect_raises(Exception, "Can't write to read-only Slice") { slice.fill(offset: 0, &.itself) }
    expect_raises(Exception, "Can't write to read-only Slice") { slice.fill(0, 0, &.itself) }
    expect_raises(Exception, "Can't write to read-only Slice") { slice.fill(0..0, &.itself) }
    expect_raises(Exception, "Can't write to read-only Slice") { slice.map!(&.itself) }
    expect_raises(Exception, "Can't write to read-only Slice") { slice.map_with_index! { |v, i| v } }
    expect_raises(Exception, "Can't write to read-only Slice") { slice.map_with_index!(offset: 0) { |v, i| v } }
    expect_raises(Exception, "Can't write to read-only Slice") { slice.shuffle! }
    expect_raises(Exception, "Can't write to read-only Slice") { slice.rotate!(0) }
    expect_raises(Exception, "Can't write to read-only Slice") { slice.copy_from(slice) }

    subslice = slice[0, 1]
    subslice.read_only?.should be_true
    expect_raises(Exception, "Can't write to read-only Slice") { subslice[0] = 1 }

    slice = Bytes[1, 2, 3, read_only: true]
    slice.read_only?.should be_true
    expect_raises(Exception, "Can't write to read-only Slice") { slice[0] = 0_u8 }
  end

  it "hashes each item in collection" do
    Slice[1, 2, 3].hash.should eq(Slice[1_u64, 2_u64, 3_u64].hash)
  end

  it "optimizes hash for Bytes" do
    Bytes[1, 2, 3].hash.should_not eq(Slice[1, 2, 3].hash)
    Bytes[1, 2, 3].should_not eq(Slice[1, 2, 3])
    Slice[1, 2, 3].should_not eq(Bytes[1, 2, 3])
  end

  it "#[]" do
    slice = Slice.new(6) { |i| i + 1 }
    subslice = slice[2..4]
    subslice.read_only?.should be_false
    subslice.size.should eq(3)
    subslice.to_unsafe.should eq(slice.to_unsafe + 2)
    subslice.should eq(Slice.new(3) { |i| i + 3 })
  end

  it "#[] keeps read-only value" do
    slice = Slice.new(6, read_only: true) { |i| i + 1 }
    slice[2..4].read_only?.should be_true
  end

  describe "#clone" do
    it "clones primitive" do
      slice = Slice[1, 2]
      slice.clone.should eq slice
    end

    it "clones non-primitive" do
      slice = Slice["abc", "a"]
      slice.clone.should eq slice
    end

    it "buffer copy" do
      slice = Slice["foo"]
      copy = slice.clone
      slice[0] = "bar"
      copy.should_not eq slice
    end

    it "deep copy" do
      slice = Slice[["foo"]]
      copy = slice.clone
      slice[0] << "bar"
      copy.should_not eq slice
    end
  end

  describe "#dup" do
    it "buffer copy" do
      slice = Slice["foo"]
      copy = slice.dup
      slice[0] = "bar"
      copy.should_not eq slice
    end

    it "don't deep copy" do
      slice = Slice[["foo"]]
      copy = slice.dup
      slice[0] << "bar"
      copy.should eq slice
    end
  end

  describe "sort" do
    {% for sort in ["sort".id, "unstable_sort".id] %}
      describe {{ "##{sort}" }} do
        it "without block" do
          slice = Slice[3, 4, 1, 2, 5, 6]
          sorted_slice = slice.{{ sort }}
          sorted_slice.to_a.should eq([1, 2, 3, 4, 5, 6])
          slice.should_not eq(sorted_slice)
        end

        it "with a block" do
          a = Slice["foo", "a", "hello"]
          b = a.{{ sort }} { |x, y| x.size <=> y.size }
          b.to_a.should eq(["a", "foo", "hello"])
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
          a.{{ sort }}!
          a.should eq([1, 2, 3, 4, 5, 6])
        end

        it "with a block" do
          a = ["foo", "a", "hello"]
          a.{{ sort }}! { |x, y| x.size <=> y.size }
          a.should eq(["a", "foo", "hello"])
        end

        it "sorts with invalid block (#4379)" do
          a = [1] * 17
          b = a.{{ sort }} { -1 }
          a.should eq(b)
        end

        it "can sort! just by using <=> (#6608)" do
          spaceships = Slice[
            Spaceship.new(2),
            Spaceship.new(0),
            Spaceship.new(1),
            Spaceship.new(3),
          ]

          spaceships.{{ sort }}!
          4.times do |i|
            spaceships[i].value.should eq(i)
          end
        end

        it "raises if <=> returns nil" do
          spaceships = Slice[
            Spaceship.new(2, return_nil: true),
            Spaceship.new(0, return_nil: true),
          ]

          expect_raises(ArgumentError) do
            spaceships.{{ sort }}!
          end
        end

        it "raises if sort! block returns nil" do
          expect_raises(ArgumentError) do
            Slice[1, 2].{{ sort }}! { nil }
          end
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
          a = Slice["foo", "a", "hello"]
          b = a.{{ sort }}_by(&.size)
          b.to_a.should eq(["a", "foo", "hello"])
          a.should_not eq(b)
        end

        {% if sort == "sort" %}
          it "stable sort" do
            is_stable_sort(mutable: false, &.sort_by(&.value))
          end
        {% end %}
      end

      describe {{ "##{sort}_by" }} do
        it "sorts" do
          a = Slice["foo", "a", "hello"]
          a.{{ sort }}_by!(&.size)
          a.to_a.should eq(["a", "foo", "hello"])
        end

        it "calls given block exactly once for each element" do
          calls = Hash(String, Int32).new(0)
          a = Slice["foo", "a", "hello"]
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

  describe "<=>" do
    it "is comparable" do
      Bytes[1].is_a?(Comparable).should be_true
    end

    it "compares" do
      (Int32.slice(1, 2, 3) <=> Int32.slice(1, 2, 3)).should eq(0)
      (Int32.slice(1, 2, 3) <=> Int32.slice(1, 3, 3)).should be < 0
      (Int32.slice(1, 3, 3) <=> Int32.slice(1, 2, 3)).should be > 0
      (Int32.slice(1, 2, 3) <=> Int32.slice(1, 2, 3, 4)).should be < 0
      (Int32.slice(1, 2, 3, 4) <=> Int32.slice(1, 2, 3)).should be > 0
    end

    it "compares (UInt8)" do
      (Bytes[1, 2, 3] <=> Bytes[1, 2, 3]).should eq(0)
      (Bytes[1, 2, 3] <=> Bytes[1, 3, 3]).should be < 0
      (Bytes[1, 3, 3] <=> Bytes[1, 2, 3]).should be > 0
      (Bytes[1, 2, 3] <=> Bytes[1, 2, 3, 4]).should be < 0
      (Bytes[1, 2, 3, 4] <=> Bytes[1, 2, 3]).should be > 0
    end
  end

  describe "#+(Slice)" do
    it "concatenates two slices" do
      a = Slice[1, 2]
      b = a + Slice[3, 4, 5]
      b.should be_a(Slice(Int32))
      b.should eq(Slice[1, 2, 3, 4, 5])
      a.should eq(Slice[1, 2])

      c = Slice[1, 2] + Slice['a', 'b', 'c']
      c.should be_a(Slice(Int32 | Char))
      c.should eq(Slice[1, 2, 'a', 'b', 'c'])
    end
  end

  describe ".join" do
    it "concatenates an indexable of slices" do
      a = Slice.join([Slice[1, 2], Slice[3, 4, 5]])
      a.should be_a(Slice(Int32))
      a.should eq(Slice[1, 2, 3, 4, 5])

      b = Slice.join({Slice[1, 2], Slice['a', 'b', 'c']})
      b.should be_a(Slice(Int32 | Char))
      b.should eq(Slice[1, 2, 'a', 'b', 'c'])

      c = Slice.join(Deque{Slice[1, 2], Slice['a', 'b', 'c'], Slice["d", "e"], Slice[3, "f"]})
      c.should be_a(Slice(Int32 | Char | String))
      c.should eq(Slice[1, 2, 'a', 'b', 'c', "d", "e", 3, "f"])
    end

    it "concatenates a slice of slices" do
      a = Slice[1]
      b = Slice['a']
      c = Slice["xyz"]

      Slice.join(Slice[a, b, c]).should eq(Slice[1, 'a', "xyz"])
    end

    it "concatenates an empty indexable of slices" do
      a = Slice.join(Array(Slice(Int32)).new)
      a.should be_a(Slice(Int32))
      a.should be_empty

      b = Slice.join(Deque(Slice(Int32)).new)
      b.should be_a(Slice(Int32))
      b.should be_empty
    end
  end

  describe ".additive_identity" do
    it "returns an empty slice" do
      a = Slice(Int32).additive_identity
      a.should be_a(Slice(Int32))
      a.should be_empty
    end
  end
end

private def itself(*args)
  args
end
