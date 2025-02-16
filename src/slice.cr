require "c/string"
require "slice/sort"

# A `Slice` is a `Pointer` with an associated size.
#
# While a pointer is unsafe because no bound checks are performed when reading from and writing to it,
# reading from and writing to a slice involve bound checks.
# In this way, a slice is a safe alternative to `Pointer`.
#
# A Slice can be created as read-only: trying to write to it
# will raise. For example the slice of bytes returned by
# `String#to_slice` is read-only.
struct Slice(T)
  include Indexable::Mutable(T)
  include Comparable(Slice)

  # Creates a new `Slice` with the given *args*. The type of the
  # slice will be the union of the type of the given *args*.
  #
  # The slice is allocated on the heap.
  #
  # ```
  # slice = Slice[1, 'a']
  # slice[0]    # => 1
  # slice[1]    # => 'a'
  # slice.class # => Slice(Char | Int32)
  # ```
  #
  # If `T` is a `Number` then this is equivalent to
  # `Number.slice` (numbers will be coerced to the type `T`)
  #
  # * `Number.slice` is a convenient alternative for designating a
  #   specific numerical item type.
  macro [](*args, read_only = false)
    # TODO: there should be a better way to check this, probably
    # asking if @type was instantiated or if T is defined
    {% if @type.name != "Slice(T)" && T < ::Number %}
      {{T}}.slice({{args.splat(", ")}}read_only: {{read_only}})
    {% else %}
      %ptr = ::Pointer(typeof({{args.splat}})).malloc({{args.size}})
      {% for arg, i in args %}
        %ptr[{{i}}] = {{arg}}
      {% end %}
      ::Slice.new(%ptr, {{args.size}}, read_only: {{read_only}})
    {% end %}
  end

  # Returns the size of this slice.
  #
  # ```
  # Slice(UInt8).new(3).size # => 3
  # ```
  getter size : Int32

  # Returns `true` if this slice cannot be written to.
  getter? read_only : Bool

  # Creates a slice to the given *pointer*, bounded by the given *size*. This
  # method does not allocate heap memory.
  #
  # ```
  # ptr = Pointer.malloc(9) { |i| ('a'.ord + i).to_u8 }
  #
  # slice = Slice.new(ptr, 3)
  # slice.size # => 3
  # slice      # => Bytes[97, 98, 99]
  #
  # String.new(slice) # => "abc"
  # ```
  def initialize(@pointer : Pointer(T), size : Int, *, @read_only = false)
    @size = size.to_i32
  end

  # Allocates `size * sizeof(T)` bytes of heap memory initialized to zero
  # and returns a slice pointing to that memory.
  #
  # The memory is allocated by the `GC`, so when there are
  # no pointers to this memory, it will be automatically freed.
  #
  # Only works for primitive integers and floats (`UInt8`, `Int32`, `Float64`, etc.)
  #
  # ```
  # slice = Slice(UInt8).new(3)
  # slice # => Bytes[0, 0, 0]
  # ```
  def self.new(size : Int, *, read_only = false)
    {% unless Number::Primitive.union_types.includes?(T) %}
      {% raise "Can only use primitive integers and floats with Slice.new(size), not #{T}" %}
    {% end %}

    pointer = Pointer(T).malloc(size)
    new(pointer, size, read_only: read_only)
  end

  # Allocates `size * sizeof(T)` bytes of heap memory initialized to the value
  # returned by the block (which is invoked once with each index in the range `0...size`)
  # and returns a slice pointing to that memory.
  #
  # The memory is allocated by the `GC`, so when there are
  # no pointers to this memory, it will be automatically freed.
  #
  # ```
  # slice = Slice.new(3) { |i| i + 10 }
  # slice # => Slice[10, 11, 12]
  # ```
  def self.new(size : Int, *, read_only = false, &)
    pointer = Pointer.malloc(size) { |i| yield i }
    new(pointer, size, read_only: read_only)
  end

  # Allocates `size * sizeof(T)` bytes of heap memory initialized to *value*
  # and returns a slice pointing to that memory.
  #
  # The memory is allocated by the `GC`, so when there are
  # no pointers to this memory, it will be automatically freed.
  #
  # ```
  # slice = Slice.new(3, 10)
  # slice # => Slice[10, 10, 10]
  # ```
  def self.new(size : Int, value : T, *, read_only = false)
    new(size, read_only: read_only) { value }
  end

  # Returns a deep copy of this slice.
  #
  # This method allocates memory for the slice copy and stores the return values
  # from calling `#clone` on each item.
  def clone
    pointer = Pointer(T).malloc(size)
    copy = self.class.new(pointer, size)
    each_with_index do |item, i|
      copy[i] = item.clone
    end
    copy
  end

  # Returns a shallow copy of this slice.
  #
  # This method allocates memory for the slice copy and duplicates the values.
  def dup
    pointer = Pointer(T).malloc(size)
    copy = self.class.new(pointer, size)
    copy.copy_from(self)
    copy
  end

  # Creates an empty slice.
  #
  # ```
  # slice = Slice(UInt8).empty
  # slice.size # => 0
  # ```
  def self.empty : self
    new(Pointer(T).null, 0)
  end

  # Returns a new slice that is *offset* elements apart from this slice.
  #
  # ```
  # slice = Slice.new(5) { |i| i + 10 }
  # slice # => Slice[10, 11, 12, 13, 14]
  #
  # slice2 = slice + 2
  # slice2 # => Slice[12, 13, 14]
  # ```
  def +(offset : Int) : Slice(T)
    check_size(offset)

    Slice.new(@pointer + offset, @size - offset, read_only: @read_only)
  end

  # Returns a new slice that has `self`'s elements followed by *other*'s
  # elements.
  #
  # ```
  # Slice[1, 2] + Slice[3, 4, 5]          # => Slice[1, 2, 3, 4, 5]
  # Slice[1, 2, 3] + Slice['a', 'b', 'c'] # => Slice[1, 2, 3, 'a', 'b', 'c']
  # ```
  #
  # See also: `Slice.join` to join multiple slices at once without creating
  # intermediate results.
  def +(other : Slice) : Slice
    Slice.join({self, other})
  end

  # Returns a new slice that has the elements from *slices* joined together.
  #
  # ```
  # Slice.join([Slice[1, 2], Slice[3, 4, 5]])        # => Slice[1, 2, 3, 4, 5]
  # Slice.join({Slice[1], Slice['a'], Slice["xyz"]}) # => Slice[1, 'a', "xyz"]
  # ```
  #
  # See also: `#+(other : Slice)`.
  def self.join(slices : Indexable(Slice)) : Slice
    total_size = slices.sum(&.size)
    buf = Pointer(typeof(Enumerable.element_type Enumerable.element_type slices)).malloc(total_size)

    ptr = buf
    slices.each do |slice|
      slice.to_unsafe.copy_to(ptr, slice.size)
      ptr += slice.size
    end

    Slice.new(buf, total_size)
  end

  # Returns the additive identity of this type.
  #
  # This is an empty slice.
  def self.additive_identity : self
    self.new(0)
  end

  # :inherit:
  #
  # Raises if this slice is read-only.
  @[AlwaysInline]
  def []=(index : Int, value : T) : T
    check_writable
    super
  end

  # Returns a new slice that starts at *start* elements from this slice's start,
  # and of exactly *count* size.
  #
  # Negative *start* is added to `#size`, thus it's treated as index counting
  # from the end of the array, `-1` designating the last element.
  #
  # Raises `ArgumentError` if *count* is negative.
  # Returns `nil` if the new slice falls outside this slice.
  #
  # ```
  # slice = Slice.new(5) { |i| i + 10 }
  # slice # => Slice[10, 11, 12, 13, 14]
  #
  # slice[1, 3]?   # => Slice[11, 12, 13]
  # slice[1, 33]?  # => nil
  # slice[-3, 2]?  # => Slice[12, 13]
  # slice[-3, 10]? # => nil
  # ```
  def []?(start : Int, count : Int) : Slice(T)?
    # we skip the calculated count because the subslice must contain exactly
    # *count* elements
    start, _ = Indexable.normalize_start_and_count(start, count, size) { return }
    return unless count <= @size - start

    Slice.new(@pointer + start, count, read_only: @read_only)
  end

  # Returns a new slice that starts at *start* elements from this slice's start,
  # and of exactly *count* size.
  #
  # Negative *start* is added to `#size`, thus it's treated as index counting
  # from the end of the array, `-1` designating the last element.
  #
  # Raises `ArgumentError` if *count* is negative.
  # Raises `IndexError` if the new slice falls outside this slice.
  #
  # ```
  # slice = Slice.new(5) { |i| i + 10 }
  # slice # => Slice[10, 11, 12, 13, 14]
  #
  # slice[1, 3]   # => Slice[11, 12, 13]
  # slice[1, 33]  # raises IndexError
  # slice[-3, 2]  # => Slice[12, 13]
  # slice[-3, 10] # raises IndexError
  # ```
  def [](start : Int, count : Int) : Slice(T)
    self[start, count]? || raise IndexError.new
  end

  # Returns a new slice with the elements in the given range.
  #
  # Negative indices count backward from the end of the slice (`-1` is the last
  # element). Additionally, an empty slice is returned when the starting index
  # for an element range is at the end of the slice.
  #
  # Returns `nil` if the new slice falls outside this slice.
  #
  # ```
  # slice = Slice.new(5) { |i| i + 10 }
  # slice # => Slice[10, 11, 12, 13, 14]
  #
  # slice[1..3]?  # => Slice[11, 12, 13]
  # slice[1..33]? # => nil
  # ```
  def []?(range : Range)
    start, count = Indexable.range_to_index_and_count(range, size) || return nil
    self[start, count]?
  end

  # Returns a new slice with the elements in the given range.
  #
  # The first element in the returned slice is `self[range.begin]` followed
  # by the next elements up to index `range.end` (or `self[range.end - 1]` if
  # the range is exclusive).
  # If there are fewer elements in `self`, the returned slice is shorter than
  # `range.size`.
  #
  # ```
  # a = Slice["a", "b", "c", "d", "e"]
  # a[1..3] # => Slice["b", "c", "d"]
  # ```
  #
  # Negative indices count backward from the end of the slice (`-1` is the last
  # element). Additionally, an empty slice is returned when the starting index
  # for an element range is at the end of the slice.
  #
  # Raises `IndexError` if the new slice falls outside this slice.
  #
  # ```
  # slice = Slice.new(5) { |i| i + 10 }
  # slice # => Slice[10, 11, 12, 13, 14]
  #
  # slice[1..3]  # => Slice[11, 12, 13]
  # slice[1..33] # raises IndexError
  # ```
  def [](range : Range) : Slice(T)
    start, count = Indexable.range_to_index_and_count(range, size) || raise IndexError.new
    self[start, count]
  end

  @[AlwaysInline]
  def unsafe_fetch(index : Int) : T
    @pointer[index]
  end

  @[AlwaysInline]
  def unsafe_put(index : Int, value : T)
    @pointer[index] = value
  end

  # :inherit:
  #
  # Raises if this slice is read-only.
  def update(index : Int, & : T -> _) : T
    check_writable
    super { |elem| yield elem }
  end

  # :inherit:
  #
  # Raises if this slice is read-only.
  def swap(index0 : Int, index1 : Int) : self
    check_writable
    super
  end

  # :inherit:
  #
  # Raises if this slice is read-only.
  def reverse! : self
    check_writable
    super
  end

  # :inherit:
  #
  # Raises if this slice is read-only.
  def shuffle!(random : Random = Random::DEFAULT) : self
    check_writable
    super
  end

  # :inherit:
  #
  # Raises if this slice is read-only.
  def rotate!(n : Int = 1) : self
    check_writable

    return self if size == 0
    n %= size

    if n == 0
    elsif n == 1
      tmp = self[0]
      @pointer.move_from(@pointer + n, size - n)
      self[-1] = tmp
    elsif n == (size - 1)
      tmp = self[-1]
      (@pointer + size - n).move_from(@pointer, n)
      self[0] = tmp
    elsif n <= SMALL_SLICE_SIZE
      tmp_buffer = uninitialized T[SMALL_SLICE_SIZE]
      tmp_buffer.to_unsafe.copy_from(@pointer, n)
      @pointer.move_from(@pointer + n, size - n)
      (@pointer + size - n).copy_from(tmp_buffer.to_unsafe, n)
    elsif size - n <= SMALL_SLICE_SIZE
      tmp_buffer = uninitialized T[SMALL_SLICE_SIZE]
      tmp_buffer.to_unsafe.copy_from(@pointer + n, size - n)
      (@pointer + size - n).move_from(@pointer, n)
      @pointer.copy_from(tmp_buffer.to_unsafe, size - n)
    elsif n <= size // 2
      tmp = self[...n].dup
      @pointer.move_from(@pointer + n, size - n)
      (@pointer + size - n).copy_from(tmp.to_unsafe, n)
    else
      tmp = self[n..].dup
      (@pointer + size - n).move_from(@pointer, n)
      @pointer.copy_from(tmp.to_unsafe, size - n)
    end
    self
  end

  private SMALL_SLICE_SIZE = 16 # same as Array::SMALL_ARRAY_SIZE

  # :inherit:
  #
  # Raises if this slice is read-only.
  def map!(& : T -> _) : self
    check_writable
    super { |elem| yield elem }
  end

  # Returns a new slice where elements are mapped by the given block.
  #
  # ```
  # slice = Slice[1, 2.5, "a"]
  # slice.map &.to_s # => Slice["1", "2.5", "a"]
  # ```
  def map(*, read_only = false, & : T -> _)
    Slice.new(size, read_only: read_only) { |i| yield @pointer[i] }
  end

  # :inherit:
  #
  # Raises if this slice is read-only.
  def map_with_index!(offset = 0, & : T, Int32 -> _) : self
    check_writable
    super { |elem, i| yield elem, i }
  end

  # Like `map`, but the block gets passed both the element and its index.
  #
  # Accepts an optional *offset* parameter, which tells it to start counting
  # from there.
  def map_with_index(offset = 0, *, read_only = false, & : (T, Int32) -> _)
    Slice.new(size, read_only: read_only) { |i| yield @pointer[i], offset + i }
  end

  # :inherit:
  #
  # Raises if this slice is read-only.
  def fill(value : T) : self
    check_writable

    {% if T == UInt8 %}
      Intrinsics.memset(to_unsafe.as(Void*), value, size, false)
      self
    {% else %}
      {% if Number::Primitive.union_types.includes?(T) %}
        if value == 0
          to_unsafe.clear(size)
          return self
        end
      {% end %}

      fill { value }
    {% end %}
  end

  # :inherit:
  #
  # Raises if this slice is read-only.
  def fill(value : T, start : Int, count : Int) : self
    # since `#[]` requires exactly *count* elements but we allow fewer here, we
    # must normalize the indices beforehand
    start, count = normalize_start_and_count(start, count)
    self[start, count].fill(value)
    self
  end

  # :inherit:
  #
  # Raises if this slice is read-only.
  def fill(value : T, range : Range) : self
    fill(value, *Indexable.range_to_index_and_count(range, size) || raise IndexError.new)
  end

  # :inherit:
  #
  # Raises if this slice is read-only.
  def fill(*, offset : Int = 0, & : Int32 -> T) : self
    check_writable
    super { |i| yield i }
  end

  # :inherit:
  #
  # Raises if this slice is read-only.
  def fill(start : Int, count : Int, & : Int32 -> T) : self
    check_writable
    super(start, count) { |i| yield i }
  end

  # :inherit:
  #
  # Raises if this slice is read-only.
  def fill(range : Range, & : Int32 -> T) : self
    check_writable
    super(range) { |i| yield i }
  end

  def copy_from(source : Pointer(T), count) : Nil
    check_writable
    check_size(count)

    @pointer.copy_from(source, count)
  end

  def copy_to(target : Pointer(T), count) : Nil
    check_size(count)

    @pointer.copy_to(target, count)
  end

  # Copies the contents of this slice into *target*.
  #
  # Raises `IndexError` if the destination slice cannot fit the data being transferred
  # e.g. `dest.size < self.size`.
  #
  # ```
  # src = Slice['a', 'a', 'a']
  # dst = Slice['b', 'b', 'b', 'b', 'b']
  # src.copy_to dst
  # dst             # => Slice['a', 'a', 'a', 'b', 'b']
  # dst.copy_to src # raises IndexError
  # ```
  def copy_to(target : self) : Nil
    target.check_writable
    raise IndexError.new if target.size < size

    @pointer.copy_to(target.to_unsafe, size)
  end

  # Copies the contents of *source* into this slice.
  #
  # Raises `IndexError` if the destination slice cannot fit the data being transferred.
  @[AlwaysInline]
  def copy_from(source : self) : Nil
    source.copy_to(self)
  end

  def move_from(source : Pointer(T), count) : Nil
    check_writable
    check_size(count)

    @pointer.move_from(source, count)
  end

  def move_to(target : Pointer(T), count) : Nil
    @pointer.move_to(target, count)
  end

  # Moves the contents of this slice into *target*. *target* and `self` may
  # overlap; the copy is always done in a non-destructive manner.
  #
  # Raises `IndexError` if the destination slice cannot fit the data being transferred
  # e.g. `dest.size < self.size`.
  #
  # ```
  # src = Slice['a', 'a', 'a']
  # dst = Slice['b', 'b', 'b', 'b', 'b']
  # src.move_to dst
  # dst             # => Slice['a', 'a', 'a', 'b', 'b']
  # dst.move_to src # raises IndexError
  # ```
  #
  # See also: `Pointer#move_to`.
  def move_to(target : self) : Nil
    target.check_writable
    raise IndexError.new if target.size < size

    @pointer.move_to(target.to_unsafe, size)
  end

  # Moves the contents of *source* into this slice. *source* and `self` may
  # overlap; the copy is always done in a non-destructive manner.
  #
  # Raises `IndexError` if the destination slice cannot fit the data being transferred.
  @[AlwaysInline]
  def move_from(source : self) : Nil
    source.move_to(self)
  end

  def inspect(io : IO) : Nil
    to_s(io)
  end

  # Returns a new `Slice` pointing at the same contents as `self`, but
  # reinterpreted as elements of the given *type*.
  #
  # The returned slice never refers to more memory than `self`; if the last
  # bytes of `self` do not fit into a `U`, they are excluded from the returned
  # slice.
  #
  # WARNING: This method is **unsafe**: elements are reinterpreted using
  # `#unsafe_as`, and the resulting slice may not be properly aligned.
  # Additionally, the same elements may produce different results depending on
  # the system endianness.
  #
  # ```
  # # assume little-endian system
  # bytes = Bytes[0x01, 0x02, 0x03, 0x04, 0xFF, 0xFE]
  # bytes.unsafe_slice_of(Int8)  # => Slice[1_i8, 2_i8, 3_i8, 4_i8, -1_i8, -2_i8]
  # bytes.unsafe_slice_of(Int16) # => Slice[513_i16, 1027_i16, -257_i16]
  # bytes.unsafe_slice_of(Int32) # => Slice[0x04030201]
  # ```
  def unsafe_slice_of(type : U.class) : Slice(U) forall U
    Slice.new(to_unsafe.unsafe_as(Pointer(U)), bytesize // sizeof(U), read_only: @read_only)
  end

  # Returns a new `Bytes` pointing at the same contents as `self`.
  #
  # WARNING: This method is **unsafe**: the returned slice is writable if `self`
  # is also writable, and modifications through the returned slice may violate
  # the binary representations of Crystal objects. Additionally, the same
  # elements may produce different results depending on the system endianness.
  #
  # ```
  # # assume little-endian system
  # ints = Slice[0x01020304, 0x05060708]
  # bytes = ints.to_unsafe_bytes # => Bytes[0x04, 0x03, 0x02, 0x01, 0x08, 0x07, 0x06, 0x05]
  # bytes[2] = 0xAD
  # ints # => Slice[0x01AD0304, 0x05060708]
  # ```
  def to_unsafe_bytes : Bytes
    unsafe_slice_of(UInt8)
  end

  # Returns a hexstring representation of this slice.
  #
  # `self` must be a `Slice(UInt8)`. To call this method on other `Slice`s,
  # `#to_unsafe_bytes` should be used first.
  #
  # ```
  # UInt8.slice(97, 62, 63, 8, 255).hexstring # => "613e3f08ff"
  #
  # # assume little-endian system
  # Int16.slice(97, 62, 1000, -2).to_unsafe_bytes.hexstring # => "61003e00e803feff"
  # ```
  def hexstring : String
    {% unless T == UInt8 %}
      {% raise "Can only call `#hexstring` on Slice(UInt8), not #{@type}" %}
    {% end %}

    str_size = size * 2
    String.new(str_size) do |buffer|
      hexstring(buffer)
      {str_size, str_size}
    end
  end

  # :nodoc:
  def hexstring(buffer) : Nil
    {% unless T == UInt8 %}
      {% raise "Can only call `#hexstring` on Slice(UInt8), not #{@type}" %}
    {% end %}

    offset = 0
    each do |v|
      buffer[offset] = to_hex(v >> 4)
      buffer[offset + 1] = to_hex(v & 0x0f)
      offset += 2
    end

    nil
  end

  # Returns a hexdump of this slice.
  #
  # `self` must be a `Slice(UInt8)`. To call this method on other `Slice`s,
  # `#to_unsafe_bytes` should be used first.
  #
  # This method is specially useful for debugging binary data and
  # incoming/outgoing data in protocols.
  #
  # ```
  # slice = UInt8.slice(97, 62, 63, 8, 255)
  # slice.hexdump # => "00000000  61 3e 3f 08 ff                                    a>?..\n"
  #
  # # assume little-endian system
  # slice = Int16.slice(97, 62, 1000, -2)
  # slice.to_unsafe_bytes.hexdump # => "00000000  61 00 3e 00 e8 03 fe ff                           a.>.....\n"
  # ```
  def hexdump : String
    {% unless T == UInt8 %}
      {% raise "Can only call `#hexdump` on Slice(UInt8), not #{@type}" %}
    {% end %}

    return "" if empty?

    full_lines, leftover = size.divmod(16)
    if leftover == 0
      str_size = full_lines * 77
    else
      str_size = (full_lines + 1) * 77 - (16 - leftover)
    end

    String.new(str_size) do |buf|
      pos = 0
      offset = 0

      while pos < size
        # Ensure we don't write outside the buffer:
        # slower, but safer (speed is not very important when hexdump is used)
        hexdump_line(Slice.new(buf + offset, {77, str_size - offset}.min), pos)
        pos += 16
        offset += 77
      end

      {str_size, str_size}
    end
  end

  # Writes a hexdump of this slice to the given *io*.
  #
  # `self` must be a `Slice(UInt8)`. To call this method on other `Slice`s,
  # `#to_unsafe_bytes` should be used first.
  #
  # This method is specially useful for debugging binary data and
  # incoming/outgoing data in protocols.
  #
  # Returns the number of bytes written to *io*.
  #
  # ```
  # slice = UInt8.slice(97, 62, 63, 8, 255)
  # slice.hexdump(STDOUT)
  # ```
  #
  # Prints:
  #
  # ```text
  # 00000000  61 3e 3f 08 ff                                    a>?..
  # ```
  def hexdump(io : IO)
    {% unless T == UInt8 %}
      {% raise "Can only call `#hexdump` on Slice(UInt8), not #{@type}" %}
    {% end %}

    return 0 if empty?

    line = uninitialized UInt8[77]
    line_slice = line.to_slice
    count = 0

    pos = 0
    while pos < size
      line_bytes = hexdump_line(line_slice, pos)
      io.write_string(line_slice[0, line_bytes])
      count += line_bytes
      pos += 16
    end

    io.flush
    count
  end

  private def hexdump_line(line, start_pos)
    hex_offset = 10
    ascii_offset = 60

    0.upto(7) do |j|
      line[7 - j] = to_hex((start_pos >> (4 * j)) & 0xf)
    end
    line[8] = 0x20_u8
    line[9] = 0x20_u8

    pos = start_pos
    16.times do |i|
      break if pos >= size
      v = unsafe_fetch(pos)
      pos += 1

      line[hex_offset] = to_hex(v >> 4)
      line[hex_offset + 1] = to_hex(v & 0x0f)
      line[hex_offset + 2] = 0x20_u8
      hex_offset += 3

      if i == 7
        line[hex_offset] = 0x20_u8
        hex_offset += 1
      end

      line[ascii_offset] = 0x20_u8 <= v <= 0x7e_u8 ? v : 0x2e_u8
      ascii_offset += 1
    end

    while hex_offset < 60
      line[hex_offset] = 0x20_u8
      hex_offset += 1
    end

    if ascii_offset < line.size
      line[ascii_offset] = 0x0a_u8
      ascii_offset += 1
    end

    ascii_offset
  end

  private def to_hex(c)
    ((c < 10 ? 48_u8 : 87_u8) + c)
  end

  def bytesize : Int32
    sizeof(T) * size
  end

  # Combined comparison operator.
  #
  # Returns a negative number, `0`, or a positive number depending on
  # whether `self` is less than *other*, equals *other*.
  #
  # It compares the elements of both slices in the same position using the
  # `<=>` operator. As soon as one of such comparisons returns a non-zero
  # value, that result is the return value of the comparison.
  #
  # If all elements are equal, the comparison is based on the size of the arrays.
  #
  # ```
  # Bytes[8] <=> Bytes[1, 2, 3] # => 7
  # Bytes[2] <=> Bytes[4, 2, 3] # => -2
  # Bytes[1, 2] <=> Bytes[1, 2] # => 0
  # ```
  def <=>(other : Slice(U)) forall U
    # If both slices are identical references, we can skip the memory comparison.
    return 0 if same?(other)

    min_size = Math.min(size, other.size)
    {% if T == UInt8 && U == UInt8 %}
      cmp = to_unsafe.memcmp(other.to_unsafe, min_size)
      return cmp if cmp != 0
    {% else %}
      0.upto(min_size - 1) do |i|
        n = to_unsafe[i] <=> other.to_unsafe[i]
        return n if n != 0
      end
    {% end %}
    size <=> other.size
  end

  # Returns `true` if `self` and *other* have the same size and all their
  # elements are equal, `false` otherwise.
  #
  # ```
  # Bytes[1, 2] == Bytes[1, 2]    # => true
  # Bytes[1, 3] == Bytes[1, 2]    # => false
  # Bytes[1, 2] == Bytes[1, 2, 3] # => false
  # ```
  #
  # Slices of different types are considered equal if the elements compare equal:
  # The only exception is `Slice(UInt8)` which does not compare equal to any
  # other `Slice(X)` because `Slice(UInt8)#hash` uses a different implementation
  # and equality implies hash equality.
  #
  # ```
  # Slice[1, 2, 3] == Slice[1.0, 2.0, 3.0] # => true
  # Slice[1, 2, 3] == Bytes[1, 2, 3]       # => false
  # ```
  def ==(other : Slice(U)) : Bool forall U
    # If both slices are of different sizes, they cannot be equal.
    return false if size != other.size

    # If both slices are identical references, we can skip the memory comparison.
    # Not using `same?` here because we have already compared sizes.
    return true if to_unsafe == other.to_unsafe

    {% if T == UInt8 && U == UInt8 %}
      to_unsafe.memcmp(other.to_unsafe, size) == 0
    {% elsif T == UInt8 || U == UInt8 %}
      # ensure that Slice(UInt8) is never considered equal to any other Slice(X)
      false
    {% else %}
      each_with_index do |elem, i|
        return false unless elem == other.to_unsafe[i]
      end
      true
    {% end %}
  end

  # Returns `true` if `self` and *other* point to the same memory, i.e. pointer
  # and size are identical.
  #
  # ```
  # slice = Slice[1, 2, 3]
  # slice.same?(slice)           # => true
  # slice == Slice[1, 2, 3]      # => false
  # slice.same?(slice + 1)       # => false
  # (slice + 1).same?(slice + 1) # => true
  # slice.same?(slice[0, 2])     # => false
  # ```
  def same?(other : self) : Bool
    to_unsafe == other.to_unsafe && size == other.size
  end

  def to_slice : self
    self
  end

  def to_s(io : IO) : Nil
    if T == UInt8
      io << "Bytes["
      # Inspect using to_s because we know this is a UInt8.
      join io, ", ", &.to_s(io)
      io << ']'
    else
      io << "Slice["
      join io, ", ", &.inspect(io)
      io << ']'
    end
  end

  def pretty_print(pp) : Nil
    prefix = T == UInt8 ? "Bytes[" : "Slice["
    pp.list(prefix, self, "]")
  end

  def to_a
    Array(T).build(@size) do |pointer|
      pointer.copy_from(@pointer, @size)
      @size
    end
  end

  # Returns this slice's pointer.
  #
  # ```
  # slice = Slice.new(3, 10)
  # slice.to_unsafe[0] # => 10
  # ```
  def to_unsafe : Pointer(T)
    @pointer
  end

  # Returns a new instance with all elements sorted based on the return value of
  # their comparison method `T#<=>` (see `Comparable#<=>`), using a stable sort algorithm.
  #
  # ```
  # a = Slice[3, 1, 2]
  # a.sort # => Slice[1, 2, 3]
  # a      # => Slice[3, 1, 2]
  # ```
  #
  # See `#sort!` for details on the sorting mechanism.
  #
  # Raises `ArgumentError` if the comparison between any two elements returns `nil`.
  def sort : self
    dup.sort!
  end

  # Returns a new instance with all elements sorted based on the return value of
  # their comparison method `T#<=>` (see `Comparable#<=>`), using an unstable sort algorithm.
  #
  # ```
  # a = Slice[3, 1, 2]
  # a.unstable_sort # => Slice[1, 2, 3]
  # a               # => Slice[3, 1, 2]
  # ```
  #
  # See `Indexable::Mutable#unstable_sort!` for details on the sorting mechanism.
  #
  # Raises `ArgumentError` if the comparison between any two elements returns `nil`.
  def unstable_sort : self
    dup.unstable_sort!
  end

  # Returns a new instance with all elements sorted based on the comparator in the
  # given block, using a stable sort algorithm.
  #
  # ```
  # a = Slice[3, 1, 2]
  # b = a.sort { |a, b| b <=> a }
  #
  # b # => Slice[3, 2, 1]
  # a # => Slice[3, 1, 2]
  # ```
  #
  # See `Indexable::Mutable#sort!(&block : T, T -> U)` for details on the sorting mechanism.
  #
  # Raises `ArgumentError` if for any two elements the block returns `nil`.
  def sort(&block : T, T -> U) : self forall U
    {% unless U <= Int32? %}
      {% raise "Expected block to return Int32 or Nil, not #{U}.\nThe block is supposed to be a custom comparison operation, compatible with `Comparable#<=>`.\nDid you mean to use `#sort_by`?" %}
    {% end %}

    dup.sort! &block
  end

  # Returns a new instance with all elements sorted based on the comparator in the
  # given block, using an unstable sort algorithm.
  #
  # ```
  # a = Slice[3, 1, 2]
  # b = a.unstable_sort { |a, b| b <=> a }
  #
  # b # => Slice[3, 2, 1]
  # a # => Slice[3, 1, 2]
  # ```
  #
  # See `Indexable::Mutable#unstable_sort!(&block : T, T -> U)` for details on the sorting mechanism.
  #
  # Raises `ArgumentError` if for any two elements the block returns `nil`.
  def unstable_sort(&block : T, T -> U) : self forall U
    {% unless U <= Int32? %}
      {% raise "Expected block to return Int32 or Nil, not #{U}.\nThe block is supposed to be a custom comparison operation, compatible with `Comparable#<=>`.\nDid you mean to use `#unstable_sort_by`?" %}
    {% end %}

    dup.unstable_sort!(&block)
  end

  # Sorts all elements in `self` based on the return value of the comparison
  # method `T#<=>` (see `Comparable#<=>`), using a stable sort algorithm.
  #
  # ```
  # slice = Slice[3, 1, 2]
  # slice.sort!
  # slice # => Slice[1, 2, 3]
  # ```
  #
  # This sort operation modifies `self`. See `#sort` for a non-modifying option
  # that allocates a new instance.
  #
  # The sort mechanism is implemented as [*merge sort*](https://en.wikipedia.org/wiki/Merge_sort).
  # It is stable, which is typically a good default.
  #
  # Stability means that two elements which compare equal (i.e. `a <=> b == 0`)
  # keep their original relation. Stable sort guarantees that `[a, b].sort!`
  # always results in `[a, b]` (given they compare equal). With unstable sort,
  # the result could also be `[b, a]`.
  #
  # If stability is expendable, `#unstable_sort!` provides a performance
  # advantage over stable sort. As an optimization, if `T` is any primitive
  # integer type, `Char`, any enum type, any `Pointer` instance, `Symbol`, or
  # `Time::Span`, then an unstable sort is automatically used.
  #
  # Raises `ArgumentError` if the comparison between any two elements returns `nil`.
  def sort! : self
    # If two values `x, y : T` have the same binary representation whenever they
    # compare equal, i.e. `x <=> y == 0` implies
    # `pointerof(x).memcmp(pointerof(y), 1) == 0`, then swapping the two values
    # is a no-op and therefore a stable sort isn't required
    {% if T.union_types.size == 1 && (T <= Int::Primitive || T <= Char || T <= Enum || T <= Pointer || T <= Symbol || T <= Time::Span) %}
      unstable_sort!
    {% else %}
      Slice.merge_sort!(self)

      self
    {% end %}
  end

  # Sorts all elements in `self` based on the return value of the comparison
  # method `T#<=>` (see `Comparable#<=>`), using an unstable sort algorithm..
  #
  # ```
  # slice = Slice[3, 1, 2]
  # slice.unstable_sort!
  # slice # => Slice[1, 2, 3]
  # ```
  #
  # This sort operation modifies `self`. See `#unstable_sort` for a non-modifying
  # option that allocates a new instance.
  #
  # The sort mechanism is implemented as [*introsort*](https://en.wikipedia.org/wiki/Introsort).
  # It does not guarantee stability between equally comparing elements.
  # This offers higher performance but may be unexpected in some situations.
  #
  # Stability means that two elements which compare equal (i.e. `a <=> b == 0`)
  # keep their original relation. Stable sort guarantees that `[a, b].sort!`
  # always results in `[a, b]` (given they compare equal). With unstable sort,
  # the result could also be `[b, a]`.
  #
  # If stability is necessary, use  `#sort!` instead.
  #
  # Raises `ArgumentError` if the comparison between any two elements returns `nil`.
  def unstable_sort! : self
    Slice.intro_sort!(to_unsafe, size)

    self
  end

  # Sorts all elements in `self` based on the comparator in the given block, using
  # a stable sort algorithm.
  #
  # ```
  # slice = Slice[3, 1, 2]
  # # This is a reverse sort (forward sort would be `a <=> b`)
  # slice.sort! { |a, b| b <=> a }
  # slice # => Slice[3, 2, 1]
  # ```
  #
  # The block must implement a comparison between two elements *a* and *b*,
  # where `a < b` outputs a negative value, `a == b` outputs `0`, and `a > b`
  # outputs a positive value.
  # The comparison operator (`Comparable#<=>`) can be used for this.
  #
  # The block's output type must be `<= Int32?`, but returning an actual `nil`
  # value is an error.
  #
  # This sort operation modifies `self`. See `#sort(&block : T, T -> U)` for a
  # non-modifying option that allocates a new instance.
  #
  # The sort mechanism is implemented as [*merge sort*](https://en.wikipedia.org/wiki/Merge_sort).
  # It is stable, which is typically a good default.
  #
  # Stability means that two elements which compare equal (i.e. `a <=> b == 0`)
  # keep their original relation. Stable sort guarantees that `[a, b].sort!`
  # always results in `[a, b]` (given they compare equal). With unstable sort,
  # the result could also be `[b, a]`.
  #
  # If stability is expendable, `#unstable_sort!(&block : T, T -> U)` provides a
  # performance advantage over stable sort.
  #
  # Raises `ArgumentError` if for any two elements the block returns `nil`.
  def sort!(&block : T, T -> U) : self forall U
    {% unless U <= Int32? %}
      {% raise "Expected block to return Int32 or Nil, not #{U}.\nThe block is supposed to be a custom comparison operation, compatible with `Comparable#<=>`.\nDid you mean to use `#sort_by!`?" %}
    {% end %}

    Slice.merge_sort!(self, block)

    self
  end

  # Sorts all elements in `self` based on the comparator in the given block,
  # using an unstable sort algorithm.
  #
  # ```
  # slice = Slice[3, 1, 2]
  # # This is a reverse sort (forward sort would be `a <=> b`)
  # slice.unstable_sort! { |a, b| b <=> a }
  # slice # => Slice[3, 2, 1]
  # ```
  #
  # The block must implement a comparison between two elements *a* and *b*,
  # where `a < b` outputs a negative value, `a == b` outputs `0`, and `a > b`
  # outputs a positive value.
  # The comparison operator (`Comparable#<=>`) can be used for this.
  #
  # The block's output type must be `<= Int32?`, but returning an actual `nil`
  # value is an error.
  #
  # This sort operation modifies `self`. See `#unstable_sort(&block : T, T -> U)`
  # for a non-modifying option that allocates a new instance.
  #
  # The sort mechanism is implemented as [*introsort*](https://en.wikipedia.org/wiki/Introsort).
  # It does not guarantee stability between equally comparing elements.
  # This offers higher performance but may be unexpected in some situations.
  #
  # Stability means that two elements which compare equal (i.e. `a <=> b == 0`)
  # keep their original relation. Stable sort guarantees that `[a, b].sort!`
  # always results in `[a, b]` (given they compare equal). With unstable sort,
  # the result could also be `[b, a]`.
  #
  # If stability is necessary, use  `#sort!(&block : T, T -> U)` instead.
  #
  # Raises `ArgumentError` if for any two elements the block returns `nil`.
  def unstable_sort!(&block : T, T -> U) : self forall U
    {% unless U <= Int32? %}
      {% raise "Expected block to return Int32 or Nil, not #{U}.\nThe block is supposed to be a custom comparison operation, compatible with `Comparable#<=>`.\nDid you mean to use `#unstable_sort_by!`?" %}
    {% end %}

    Slice.intro_sort!(to_unsafe, size, block)

    self
  end

  # Returns a new instance with all elements sorted by the output value of the
  # block. The output values are compared via the comparison method `T#<=>`
  # (see `Comparable#<=>`), using a stable sort algorithm.
  #
  # ```
  # a = Slice["apple", "pear", "fig"]
  # b = a.sort_by { |word| word.size }
  # b # => Slice["fig", "pear", "apple"]
  # a # => Slice["apple", "pear", "fig"]
  # ```
  #
  # If stability is expendable, `#unstable_sort_by(&block : T -> _)` provides a
  # performance advantage over stable sort.
  #
  # See `Indexable::Mutable#sort_by!(&block : T -> _)` for details on the sorting mechanism.
  #
  # Raises `ArgumentError` if the comparison between any two comparison values returns `nil`.
  def sort_by(&block : T -> _) : self
    dup.sort_by! { |e| yield(e) }
  end

  # Returns a new instance with all elements sorted by the output value of the
  # block. The output values are compared via the comparison method `#<=>`
  # (see `Comparable#<=>`), using an unstable sort algorithm.
  #
  # ```
  # a = Slice["apple", "pear", "fig"]
  # b = a.unstable_sort_by { |word| word.size }
  # b # => Slice["fig", "pear", "apple"]
  # a # => Slice["apple", "pear", "fig"]
  # ```
  #
  # If stability is necessary, use `#sort_by(&block : T -> _)` instead.
  #
  # See `Indexable::Mutable#unstable_sort!(&block : T -> _)` for details on the sorting mechanism.
  #
  # Raises `ArgumentError` if the comparison between any two comparison values returns `nil`.
  def unstable_sort_by(&block : T -> _) : self
    dup.unstable_sort_by! { |e| yield(e) }
  end

  # Modifies `self` by sorting all elements. The given block is called for
  # each element, then the comparison method `<=>` is called on the object
  # returned from the block to determine sort order.
  #
  # ```
  # a = Slice["apple", "pear", "fig"]
  # a.sort_by! { |word| word.size }
  # a # => Slice["fig", "pear", "apple"]
  # ```
  def sort_by!(&block : T -> _) : Slice(T)
    sorted = map { |e| {e, yield(e)} }.sort! { |x, y| x[1] <=> y[1] }
    size.times do |i|
      to_unsafe[i] = sorted.to_unsafe[i][0]
    end
    self
  end

  # :ditto:
  #
  # This method does not guarantee stability between equally sorting elements.
  # Which results in a performance advantage over stable sort.
  def unstable_sort_by!(&block : T -> _) : Slice(T)
    sorted = map { |e| {e, yield(e)} }.unstable_sort! { |x, y| x[1] <=> y[1] }
    size.times do |i|
      to_unsafe[i] = sorted.to_unsafe[i][0]
    end
    self
  end

  def index(object, offset : Int = 0)
    # Optimize for the case of looking for a byte in a byte slice
    if T.is_a?(UInt8.class) &&
       (object.is_a?(UInt8) || (object.is_a?(Int) && 0 <= object < 256))
      return fast_index(object, offset)
    end

    super
  end

  # :nodoc:
  def fast_index(object, offset) : Int32?
    offset = check_index_out_of_bounds(offset) { return nil }
    result = LibC.memchr(to_unsafe + offset, object, size - offset)
    if result
      return (result - to_unsafe.as(Void*)).to_i32
    end
  end

  # See `Object#hash(hasher)`
  def hash(hasher)
    {% if T == UInt8 %}
      hasher.bytes(self)
    {% else %}
      super hasher
    {% end %}
  end

  protected def check_writable
    raise "Can't write to read-only Slice" if @read_only
  end

  private def check_size(count : Int)
    unless 0 <= count <= size
      raise IndexError.new
    end
  end
end

# A convenient alias for the most common slice type,
# a slice of bytes, used for example in `IO#read` and `IO#write`.
alias Bytes = Slice(UInt8)
