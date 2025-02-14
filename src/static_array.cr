# A fixed-size, stack allocated array.
#
# `StaticArray` is a generic type with type argument `T` specifying the type of
# its elements and `N` the fixed size. For example `StaticArray(Int32, 3)`
# is a static array of `Int32` with three elements.
#
# Instantiations of this static array type:
#
# ```
# StaticArray(Int32, 3).new(42)           # => StaticArray[42, 42, 42]
# StaticArray(Int32, 3).new { |i| i * 2 } # => StaticArray[0, 2, 4]
# StaticArray[0, 8, 15]                   # => StaticArray[0, 8, 15]
# ```
#
# This type can also be expressed as `Int32[3]` (only in type grammar). A typical use
# case is in combination with `uninitialized`:
#
# ```
# ints = uninitialized Int32[3]
# ints[0] = 0
# ints[1] = 8
# ints[2] = 15
# ```
#
# For number types there is also `Number.static_array` which can be used to initialize
# a static array:
#
# ```
# Int32.static_array(0, 8, 15) # => StaticArray[0, 8, 15]
# ```
#
# The generic argument type `N` is a special case in the type grammar as it
# doesn't specify a type but a size. Its value can be an `Int32` literal or
# constant.
struct StaticArray(T, N)
  include Comparable(StaticArray)
  include Indexable::Mutable(T)

  # Creates a new `StaticArray` with the given *args*. The type of the
  # static array will be the union of the type of the given *args*,
  # and its size will be the number of elements in *args*.
  #
  # ```
  # ary = StaticArray[1, 'a']
  # ary[0]    # => 1
  # ary[1]    # => 'a'
  # ary.class # => StaticArray(Char | Int32, 2)
  # ```
  #
  # * `Number.static_array` is a convenient alternative for designating a
  #   specific numerical item type.
  macro [](*args)
    %array = uninitialized ::StaticArray(typeof({{args.splat}}), {{args.size}})
    {% for arg, i in args %}
      %array.to_unsafe[{{i}}] = {{arg}}
    {% end %}
    %array
  end

  # Creates a new static array and invokes the
  # block once for each index of the array, assigning the
  # block's value in that index.
  #
  # ```
  # StaticArray(Int32, 3).new { |i| i * 2 } # => StaticArray[0, 2, 4]
  # ```
  def self.new(& : Int32 -> T)
    array = uninitialized self
    N.times do |i|
      array.to_unsafe[i] = yield i
    end
    array
  end

  # Creates a new static array filled with the given value.
  #
  # ```
  # StaticArray(Int32, 3).new(42) # => StaticArray[42, 42, 42]
  # ```
  def self.new(value : T)
    new { value }
  end

  # Disallow creating an uninitialized StaticArray with new.
  # If this is desired, one can use `array = uninitialized ...`
  # which makes it clear that it's unsafe.
  private def initialize
  end

  # Equality. Returns `true` if each element in `self` is equal to each
  # corresponding element in *other*.
  #
  # ```
  # array = StaticArray(Int32, 3).new 0  # => StaticArray[0, 0, 0]
  # array2 = StaticArray(Int32, 3).new 0 # => StaticArray[0, 0, 0]
  # array3 = StaticArray(Int32, 3).new 1 # => StaticArray[1, 1, 1]
  # array == array2                      # => true
  # array == array3                      # => false
  # ```
  def ==(other : StaticArray)
    return false unless size == other.size
    each_with_index do |e, i|
      return false unless e == other[i]
    end
    true
  end

  # Equality with another object. Always returns `false`.
  #
  # ```
  # array = StaticArray(Int32, 3).new 0 # => StaticArray[0, 0, 0]
  # array == nil                        # => false
  # ```
  def ==(other)
    false
  end

  def <=>(other : StaticArray)
    to_slice <=> other.to_slice
  end

  @[AlwaysInline]
  def unsafe_fetch(index : Int) : T
    to_unsafe[index]
  end

  @[AlwaysInline]
  def unsafe_put(index : Int, value : T)
    to_unsafe[index] = value
  end

  # Returns the size of `self`
  #
  # ```
  # array = StaticArray(Int32, 3).new { |i| i + 1 }
  # array.size # => 3
  # ```
  def size : Int32
    N
  end

  # :inherit:
  def fill(value : T) : self
    # enable memset optimization
    to_slice.fill(value)
    self
  end

  # :inherit:
  def fill(value : T, start : Int, count : Int) : self
    to_slice.fill(value, start, count)
    self
  end

  # :inherit:
  def fill(value : T, range : Range) : self
    to_slice.fill(value, range)
    self
  end

  # :inherit:
  def each_slice(count : Int, &)
    to_slice.each_slice(count) { |elems| yield elems }
  end

  # Returns a new static array where elements are mapped by the given block.
  #
  # ```
  # array = StaticArray[1, 2.5, "a"]
  # array.map &.to_s # => StaticArray["1", "2.5", "a"]
  # ```
  def map(&block : T -> U) : StaticArray(U, N) forall U
    StaticArray(U, N).new { |i| yield to_unsafe[i] }
  end

  # Like `map`, but the block gets passed both the element and its index.
  #
  # Accepts an optional *offset* parameter, which tells it to start counting
  # from there.
  def map_with_index(offset = 0, &block : (T, Int32) -> U) : StaticArray(U, N) forall U
    StaticArray(U, N).new { |i| yield to_unsafe[i], offset + i }
  end

  # Returns a new instance with all elements sorted based on the return value of
  # their comparison method `T#<=>` (see `Comparable#<=>`), using a stable sort algorithm.
  #
  # ```
  # a = StaticArray[3, 1, 2]
  # a.sort # => StaticArray[1, 2, 3]
  # a      # => StaticArray[3, 1, 2]
  # ```
  #
  # See `Indexable::Mutable#sort!` for details on the sorting mechanism.
  #
  # Raises `ArgumentError` if the comparison between any two elements returns `nil`.
  def sort : StaticArray(T, N)
    # the return value of `dup` must be assigned to a variable first, otherwise
    # `self` will be mutated if the `sort!` call is chained directly
    ary = dup
    ary.sort!
  end

  # Returns a new instance with all elements sorted based on the return value of
  # their comparison method `T#<=>` (see `Comparable#<=>`), using an unstable sort algorithm.
  #
  # ```
  # a = StaticArray[3, 1, 2]
  # a.unstable_sort # => StaticArray[1, 2, 3]
  # a               # => StaticArray[3, 1, 2]
  # ```
  #
  # See `Indexable::Mutable#unstable_sort!` for details on the sorting mechanism.
  #
  # Raises `ArgumentError` if the comparison between any two elements returns `nil`.
  def unstable_sort : StaticArray(T, N)
    ary = dup
    ary.unstable_sort!
  end

  # Returns a new instance with all elements sorted based on the comparator in the
  # given block, using a stable sort algorithm.
  #
  # ```
  # a = StaticArray[3, 1, 2]
  # b = a.sort { |a, b| b <=> a }
  #
  # b # => StaticArray[3, 2, 1]
  # a # => StaticArray[3, 1, 2]
  # ```
  #
  # See `Indexable::Mutable#sort!(&block : T, T -> U)` for details on the sorting mechanism.
  #
  # Raises `ArgumentError` if for any two elements the block returns `nil`.=
  def sort(&block : T, T -> U) : StaticArray(T, N) forall U
    {% unless U <= Int32? %}
      {% raise "Expected block to return Int32 or Nil, not #{U}.\nThe block is supposed to be a custom comparison operation, compatible with `Comparable#<=>`.\nDid you mean to use `#sort_by`?" %}
    {% end %}

    ary = dup
    ary.sort!(&block)
  end

  # Returns a new instance with all elements sorted based on the comparator in the
  # given block, using an unstable sort algorithm.
  #
  # ```
  # a = StaticArray[3, 1, 2]
  # b = a.unstable_sort { |a, b| b <=> a }
  #
  # b # => StaticArray[3, 2, 1]
  # a # => StaticArray[3, 1, 2]
  # ```
  #
  # See `Indexable::Mutable#unstable_sort!(&block : T, T -> U)` for details on the sorting mechanism.
  #
  # Raises `ArgumentError` if for any two elements the block returns `nil`.
  def unstable_sort(&block : T, T -> U) : StaticArray(T, N) forall U
    {% unless U <= Int32? %}
      {% raise "Expected block to return Int32 or Nil, not #{U}.\nThe block is supposed to be a custom comparison operation, compatible with `Comparable#<=>`.\nDid you mean to use `#unstable_sort_by`?" %}
    {% end %}

    ary = dup
    ary.unstable_sort!(&block)
  end

  # :inherit:
  def sort! : self
    to_slice.sort!
    self
  end

  # :inherit:
  def unstable_sort! : self
    to_slice.unstable_sort!
    self
  end

  # :inherit:
  def sort!(&block : T, T -> U) : self forall U
    {% unless U <= Int32? %}
      {% raise "Expected block to return Int32 or Nil, not #{U}.\nThe block is supposed to be a custom comparison operation, compatible with `Comparable#<=>`.\nDid you mean to use `#sort_by!`?" %}
    {% end %}

    to_slice.sort!(&block)
    self
  end

  # :inherit:
  def unstable_sort!(&block : T, T -> U) : self forall U
    {% unless U <= Int32? %}
      {% raise "Expected block to return Int32 or Nil, not #{U}.\nThe block is supposed to be a custom comparison operation, compatible with `Comparable#<=>`.\nDid you mean to use `#unstable_sort_by!`?" %}
    {% end %}

    to_slice.unstable_sort!(&block)
    self
  end

  # Returns a new instance with all elements sorted by the output value of the
  # block. The output values are compared via the comparison method `T#<=>`
  # (see `Comparable#<=>`), using a stable sort algorithm.
  #
  # ```
  # a = StaticArray["apple", "pear", "fig"]
  # b = a.sort_by { |word| word.size }
  # b # => StaticArray["fig", "pear", "apple"]
  # a # => StaticArray["apple", "pear", "fig"]
  # ```
  #
  # If stability is expendable, `#unstable_sort_by(&block : T -> _)` provides a
  # performance advantage over stable sort.
  #
  # See `Indexable::Mutable#sort_by!(&block : T -> _)` for details on the sorting mechanism.
  #
  # Raises `ArgumentError` if the comparison between any two comparison values returns `nil`.
  def sort_by(&block : T -> _) : StaticArray(T, N)
    ary = dup
    ary.sort_by! { |e| yield(e) }
  end

  # Returns a new instance with all elements sorted by the output value of the
  # block. The output values are compared via the comparison method `#<=>`
  # (see `Comparable#<=>`), using an unstable sort algorithm.
  #
  # ```
  # a = StaticArray["apple", "pear", "fig"]
  # b = a.unstable_sort_by { |word| word.size }
  # b # => StaticArray["fig", "pear", "apple"]
  # a # => StaticArray["apple", "pear", "fig"]
  # ```
  #
  # If stability is necessary, use `#sort_by(&block : T -> _)` instead.
  #
  # See `Indexable::Mutable#unstable_sort!(&block : T -> _)` for details on the sorting mechanism.
  #
  # Raises `ArgumentError` if the comparison between any two comparison values returns `nil`.
  def unstable_sort_by(&block : T -> _) : StaticArray(T, N)
    ary = dup
    ary.unstable_sort_by! { |e| yield(e) }
  end

  # :inherit:
  def sort_by!(&block : T -> _) : self
    sorted = map { |e| {e, yield(e)} }.sort! { |x, y| x[1] <=> y[1] }
    N.times do |i|
      to_unsafe[i] = sorted.to_unsafe[i][0]
    end
    self
  end

  # :inherit:
  def unstable_sort_by!(&block : T -> _) : self
    sorted = map { |e| {e, yield(e)} }.unstable_sort! { |x, y| x[1] <=> y[1] }
    N.times do |i|
      to_unsafe[i] = sorted.to_unsafe[i][0]
    end
    self
  end

  # :inherit:
  def rotate!(n : Int = 1) : self
    to_slice.rotate!(n)
    self
  end

  # Returns a slice that points to the elements of this static array.
  # Changes made to the returned slice also affect this static array.
  #
  # ```
  # array = StaticArray(Int32, 3).new(2)
  # slice = array.to_slice # => Slice[2, 2, 2]
  # slice[0] = 3
  # array # => StaticArray[3, 2, 2]
  # ```
  def to_slice : Slice(T)
    Slice.new(to_unsafe, size)
  end

  # Returns a pointer to this static array's data.
  #
  # ```
  # ary = StaticArray(Int32, 3).new(42)
  # ary.to_unsafe[0] # => 42
  # ```
  def to_unsafe : Pointer(T)
    pointerof(@buffer)
  end

  # Appends a string representation of this static array to the given `IO`.
  #
  # ```
  # array = StaticArray(Int32, 3).new { |i| i + 1 }
  # array.to_s # => "StaticArray[1, 2, 3]"
  # ```
  def to_s(io : IO) : Nil
    io << "StaticArray["
    join io, ", ", &.inspect(io)
    io << ']'
  end

  def pretty_print(pp)
    # Don't pass `self` here because we'll pass `self` by
    # value and for big static arrays that seems to make
    # LLVM really slow.
    # TODO: investigate why, maybe report a bug to LLVM?
    pp.list("StaticArray[", to_slice, "]")
  end

  # Returns a new `StaticArray` where each element is cloned from elements in `self`.
  def clone
    array = uninitialized self
    N.times do |i|
      array.to_unsafe[i] = to_unsafe[i].clone
    end
    array
  end

  def index(object, offset : Int = 0)
    # Optimize for the case of looking for a byte in a byte slice
    if T.is_a?(UInt8.class) &&
       (object.is_a?(UInt8) || (object.is_a?(Int) && 0 <= object < 256))
      return to_slice.fast_index(object, offset)
    end

    super
  end
end
