# An `Array` is an ordered, integer-indexed collection of objects of type T.
#
# Array indexing starts at 0. A negative index is assumed to be
# relative to the end of the array: -1 indicates the last element,
# -2 is the next to last element, and so on.
#
# An `Array` can be created using the usual `new` method (several are provided), or with an array literal:
#
# ```
# Array(Int32).new  # => []
# [1, 2, 3]         # Array(Int32)
# [1, "hello", 'x'] # Array(Int32 | String | Char)
# ```
#
# See [`Array` literals](https://crystal-lang.org/reference/syntax_and_semantics/literals/array.html) in the language reference.
#
# An `Array` can have mixed types, meaning T will be a union of types, but these are determined
# when the array is created, either by specifying T or by using an array literal. In the latter
# case, T will be set to the union of the array literal elements' types.
#
# When creating an empty array you must always specify T:
#
# ```
# [] of Int32 # same as Array(Int32)
# []          # syntax error
# ```
#
# An `Array` is implemented using an internal buffer of some capacity
# and is reallocated when elements are pushed to it when more capacity
# is needed. This is normally known as a [dynamic array](http://en.wikipedia.org/wiki/Dynamic_array).
#
# You can use a special array literal syntax with other types too, as long as they define an argless
# `new` method and a `<<` method. `Set` is one such type:
#
# ```
# set = Set{1, 2, 3} # => Set{1, 2, 3}
# set.class          # => Set(Int32)
# ```
#
# The above is the same as this:
#
# ```
# set = Set(typeof(1, 2, 3)).new
# set << 1
# set << 2
# set << 3
# ```
class Array(T)
  include Indexable::Mutable(T)
  include Comparable(Array)

  # Size of an Array that we consider small to do linear scans or other optimizations.
  private SMALL_ARRAY_SIZE = 16

  # The initial capacity reserved for new arrays; just a lucky number
  private INITIAL_CAPACITY = 3

  # The capacity threshold before we stop doubling array during resize.
  private CAPACITY_THRESHOLD = 256

  # The size of this array.
  @size : Int32

  # The capacity of `@buffer`.
  # Note that, because `@buffer` moves on shift, the actual
  # capacity (the allocated memory) starts at `@buffer - @offset_to_buffer`.
  # The actual capacity is also given by the `remaining_capacity` internal method.
  @capacity : Int32

  # Offset to the buffer that was originally allocated, and which needs to
  # be reallocated on resize. On shift this value gets increased, together with
  # `@buffer`. To reach the root buffer you have to do `@buffer - @offset_to_buffer`,
  # and this is also provided by the `root_buffer` internal method.
  @offset_to_buffer : Int32 = 0

  # The buffer where elements start.
  @buffer : Pointer(T)

  # In 64 bits the Array is composed then by:
  # - type_id            : Int32   # 4 bytes -|
  # - size               : Int32   # 4 bytes  |- packed as 8 bytes
  #
  # - capacity           : Int32   # 4 bytes -|
  # - offset_to_buffer   : Int32   # 4 bytes  |- packed as 8 bytes
  #
  # - buffer             : Pointer # 8 bytes  |- another 8 bytes
  #
  # So in total 24 bytes. Without offset_to_buffer it's the same,
  # because of aligning to 8 bytes (at least in 64 bits), and that's
  # why we chose to include this value, because with it we can optimize
  # `shift` to let Array be used as a queue/deque.

  # Creates a new empty `Array`.
  def initialize
    @size = 0
    @capacity = 0
    @buffer = Pointer(T).null
  end

  # Creates a new empty `Array` backed by a buffer that is initially
  # `initial_capacity` big.
  #
  # The *initial_capacity* is useful to avoid unnecessary reallocations
  # of the internal buffer in case of growth. If you have an estimate
  # of the maximum number of elements an array will hold, the array should
  # be initialized with that capacity for improved performance.
  #
  # ```
  # ary = Array(Int32).new(5)
  # ary.size # => 0
  # ```
  def initialize(initial_capacity : Int)
    if initial_capacity < 0
      raise ArgumentError.new("Negative array size: #{initial_capacity}")
    end

    @size = 0
    @capacity = initial_capacity.to_i
    if initial_capacity == 0
      @buffer = Pointer(T).null
    else
      @buffer = Pointer(T).malloc(initial_capacity)
    end
  end

  # Creates a new `Array` of the given *size* filled with the same *value* in each position.
  #
  # ```
  # Array.new(3, 'a') # => ['a', 'a', 'a']
  # ```
  #
  # WARNING: The initial value is filled into the array as-is. It gets neither
  # duplicated nor cloned. For types with reference semantics this means every
  # item will point to the *same* object.
  #
  # ```
  # ary = Array.new(3, [1])
  # ary # => [[1], [1], [1]]
  # ary[0][0] = 2
  # ary # => [[2], [2], [2]]
  # ```
  #
  # * `.new(Int, & : Int32 -> T)` is an alternative that allows using a
  #   different initial value for each position.
  def initialize(size : Int, value : T)
    if size < 0
      raise ArgumentError.new("Negative array size: #{size}")
    end

    @size = size.to_i
    @capacity = size.to_i

    if size == 0
      @buffer = Pointer(T).null
    else
      @buffer = Pointer(T).malloc(size, value)
    end
  end

  # Creates a new `Array` of the given *size* and invokes the given block once
  # for each index of `self`, assigning the block's value in that index.
  #
  # ```
  # Array.new(3) { |i| (i + 1) ** 2 } # => [1, 4, 9]
  #
  # ary = Array.new(3) { [1] }
  # ary # => [[1], [1], [1]]
  # ary[0][0] = 2
  # ary # => [[2], [1], [1]]
  # ```
  def self.new(size : Int, & : Int32 -> T)
    Array(T).build(size) do |buffer|
      size.to_i.times do |i|
        buffer[i] = yield i
      end
      size
    end
  end

  # Creates a new `Array`, allocating an internal buffer with the given *capacity*,
  # and yielding that buffer. The given block must return the desired size of the array.
  #
  # This method is **unsafe**, but is usually used to initialize the buffer
  # by passing it to a C function.
  #
  # ```
  # Array.build(3) do |buffer|
  #   LibSome.fill_buffer_and_return_number_of_elements_filled(buffer)
  # end
  # ```
  def self.build(capacity : Int, & : Pointer(T) ->) : self
    ary = Array(T).new(capacity)
    ary.size = (yield ary.to_unsafe).to_i
    ary
  end

  # :nodoc:
  #
  # This method is used by LiteralExpander to efficiently create an Array
  # instance from a literal.
  def self.unsafe_build(capacity : Int) : self
    ary = Array(T).new(capacity)
    ary.size = capacity
    ary
  end

  # Returns the number of elements in the array.
  #
  # ```
  # [:foo, :bar].size # => 2
  # ```
  getter size : Int32

  # Equality. Returns `true` if each element in `self` is equal to each
  # corresponding element in *other*.
  #
  # ```
  # ary = [1, 2, 3]
  # ary == [1, 2, 3] # => true
  # ary == [2, 3]    # => false
  # ```
  def ==(other : Array) : Bool
    equals?(other) { |x, y| x == y }
  end

  def ==(other) : Bool
    false
  end

  # Combined comparison operator.
  #
  # Returns `-1`, `0` or `1` depending on whether `self` is less than *other*, equals *other*
  # or is greater than *other*.
  #
  # It compares the elements of both arrays in the same position using the
  # `<=>` operator. As soon as one of such comparisons returns a non-zero
  # value, that result is the return value of the comparison.
  #
  # If all elements are equal, the comparison is based on the size of the arrays.
  #
  # ```
  # [8] <=> [1, 2, 3] # => 1
  # [2] <=> [4, 2, 3] # => -1
  # [1, 2] <=> [1, 2] # => 0
  # ```
  def <=>(other : Array)
    min_size = Math.min(size, other.size)
    0.upto(min_size - 1) do |i|
      n = @buffer[i] <=> other.to_unsafe[i]
      return n if n != 0
    end
    size <=> other.size
  end

  # Set intersection: returns a new `Array` containing elements common to `self`
  # and *other*, excluding any duplicates. The order is preserved from `self`.
  #
  # ```
  # [1, 1, 3, 5] & [1, 2, 3]               # => [ 1, 3 ]
  # ['a', 'b', 'b', 'z'] & ['a', 'b', 'c'] # => [ 'a', 'b' ]
  # ```
  #
  # See also: `#uniq`.
  def &(other : Array(U)) : Array(T) forall U
    return Array(T).new if self.empty? || other.empty?

    # Heuristic: for small arrays we do a linear scan, which is usually
    # faster than creating an intermediate Set.
    if self.size + other.size <= SMALL_ARRAY_SIZE * 2
      ary = Array(T).new
      each do |elem|
        ary << elem if !ary.includes?(elem) && other.includes?(elem)
      end
      return ary
    end

    set = other.to_set
    Array(T).build(Math.min(size, other.size)) do |buffer|
      appender = buffer.appender
      each do |obj|
        appender << obj if set.delete(obj)
      end
      appender.size.to_i
    end
  end

  # Set union: returns a new `Array` by joining `self` with *other*, excluding
  # any duplicates, and preserving the order from `self`.
  #
  # ```
  # ["a", "b", "c"] | ["c", "d", "a"] # => [ "a", "b", "c", "d" ]
  # ```
  #
  # See also: `#uniq`.
  def |(other : Array(U)) : Array(T | U) forall U
    # Heuristic: if the combined size is small we just do a linear scan
    # instead of using a Set for lookup.
    if size + other.size <= SMALL_ARRAY_SIZE
      ary = Array(T | U).new
      each do |elem|
        ary << elem unless ary.includes?(elem)
      end
      other.each do |elem|
        ary << elem unless ary.includes?(elem)
      end
      return ary
    end

    Array(T | U).build(size + other.size) do |buffer|
      set = Set(T).new
      appender = buffer.appender
      each do |obj|
        appender << obj if set.add?(obj)
      end
      other.each do |obj|
        appender << obj if set.add?(obj)
      end
      appender.size.to_i
    end
  end

  # Concatenation. Returns a new `Array` built by concatenating `self` and *other*.
  # The type of the new array is the union of the types of both the original arrays.
  #
  # ```
  # [1, 2] + ["a"]  # => [1,2,"a"] of (Int32 | String)
  # [1, 2] + [2, 3] # => [1,2,2,3]
  # ```
  def +(other : Array(U)) : Array(T | U) forall U
    new_size = size + other.size
    Array(T | U).build(new_size) do |buffer|
      buffer.copy_from(@buffer, size)
      (buffer + size).copy_from(other.to_unsafe, other.size)
      new_size
    end
  end

  # Returns the additive identity of this type.
  #
  # This is an empty array.
  def self.additive_identity : self
    self.new
  end

  # Difference. Returns a new `Array` that is a copy of `self`, removing any items
  # that appear in *other*. The order of `self` is preserved.
  #
  # ```
  # [1, 2, 3] - [2, 1] # => [3]
  # ```
  def -(other : Array(U)) : Array(T) forall U
    # Heuristic: if any of the arrays is small we just do a linear scan
    # instead of using a Set for lookup.
    if size <= SMALL_ARRAY_SIZE || other.size <= SMALL_ARRAY_SIZE
      ary = Array(T).new
      each do |elem|
        ary << elem unless other.includes?(elem)
      end
      return ary
    end

    ary = Array(T).new(Math.max(size - other.size, 0))
    set = other.to_set
    each do |obj|
      ary << obj unless set.includes?(obj)
    end
    ary
  end

  # Repetition: Returns a new `Array` built by concatenating *times* copies of `self`.
  #
  # ```
  # ["a", "b", "c"] * 2 # => [ "a", "b", "c", "a", "b", "c" ]
  # ```
  def *(times : Int) : Array(T)
    if times == 0 || empty?
      return Array(T).new
    end

    if times == 1
      return dup
    end

    if size == 1
      return Array(T).new(times, first)
    end

    new_size = size * times
    Array(T).build(new_size) do |buffer|
      buffer.copy_from(to_unsafe, size)
      n = size

      while n <= new_size // 2
        (buffer + n).copy_from(buffer, n)
        n *= 2
      end

      (buffer + n).copy_from(buffer, new_size - n)
      new_size
    end
  end

  # Append. Alias for `push`.
  #
  # ```
  # a = [1, 2]
  # a << 3 # => [1,2,3]
  # ```
  def <<(value : T) : self
    push(value)
  end

  # Replaces a subrange with a single value. All elements in the range
  # `start...start+count` are removed and replaced by a single element
  # *value*.
  #
  # If *count* is zero, *value* is inserted at *start*.
  #
  # Negative values of *start* count from the end of the array.
  #
  # ```
  # a = [1, 2, 3, 4, 5]
  # a[1, 3] = 6
  # a # => [1, 6, 5]
  #
  # a = [1, 2, 3, 4, 5]
  # a[1, 0] = 6
  # a # => [1, 6, 2, 3, 4, 5]
  # ```
  def []=(start : Int, count : Int, value : T) : T
    start, count = normalize_start_and_count(start, count)

    case count
    when 0
      insert start, value
    when 1
      @buffer[start] = value
    else
      diff = count - 1

      # If *start* is 0 we can avoid a memcpy by doing a shift.
      # For example if we have:
      #
      #    a = ['a', 'b', 'c', 'd']
      #
      # and someone does:
      #
      #    a[0..2] = 'x'
      #
      # we can change the value at 2 to 'x' and repoint `@offset_to_buffer`:
      #
      #    [-, -, 'x', 'd']
      #           ^
      #
      # (we also have to clear the elements before that)
      if start == 0
        @buffer.clear(diff)
        shift_buffer_by(diff)
        @buffer.value = value
      else
        (@buffer + start + 1).move_from(@buffer + start + count, size - start - count)
        (@buffer + @size - diff).clear(diff)
        @buffer[start] = value
      end

      @size -= diff
    end

    value
  end

  # :ditto:
  @[Deprecated("Use `#[]=(start, count, value)` instead")]
  def []=(value : T, *, index start : Int, count : Int)
    self[start, count] = value
  end

  # Replaces a subrange with a single value.
  #
  # ```
  # a = [1, 2, 3, 4, 5]
  # a[1..3] = 6
  # a # => [1, 6, 5]
  #
  # a = [1, 2, 3, 4, 5]
  # a[1...1] = 6
  # a # => [1, 6, 2, 3, 4, 5]
  #
  # a = [1, 2, 3, 4, 5]
  # a[2...] = 6
  # a # => [1, 2, 6]
  # ```
  def []=(range : Range, value : T)
    self[*Indexable.range_to_index_and_count(range, size) || raise IndexError.new] = value
  end

  # Replaces a subrange with the elements of the given array.
  #
  # ```
  # a = [1, 2, 3, 4, 5]
  # a[1, 3] = [6, 7, 8]
  # a # => [1, 6, 7, 8, 5]
  #
  # a = [1, 2, 3, 4, 5]
  # a[1, 3] = [6, 7]
  # a # => [1, 6, 7, 5]
  #
  # a = [1, 2, 3, 4, 5]
  # a[1, 3] = [6, 7, 8, 9, 10]
  # a # => [1, 6, 7, 8, 9, 10, 5]
  # ```
  def []=(start : Int, count : Int, values : Array(T))
    start, count = normalize_start_and_count(start, count)
    diff = values.size - count

    if diff == 0
      # Replace values directly
      (@buffer + start).copy_from(values.to_unsafe, values.size)
    elsif diff < 0
      # Need to shrink
      diff = -diff
      (@buffer + start).copy_from(values.to_unsafe, values.size)
      (@buffer + start + values.size).move_from(@buffer + start + count, size - start - count)
      (@buffer + @size - diff).clear(diff)
      @size -= diff
    else
      # Need to grow
      resize_if_cant_insert(diff)
      (@buffer + start + values.size).move_from(@buffer + start + count, size - start - count)
      (@buffer + start).copy_from(values.to_unsafe, values.size)
      @size += diff
    end

    values
  end

  # :ditto:
  @[Deprecated("Use `#[]=(start, count, values)` instead")]
  def []=(values : Array(T), *, index start : Int, count : Int)
    self[start, count] = values
  end

  # Replaces a subrange with the elements of the given array.
  #
  # ```
  # a = [1, 2, 3, 4, 5]
  # a[1..3] = [6, 7, 8]
  # a # => [1, 6, 7, 8, 5]
  #
  # a = [1, 2, 3, 4, 5]
  # a[1..3] = [6, 7]
  # a # => [1, 6, 7, 5]
  #
  # a = [1, 2, 3, 4, 5]
  # a[1..3] = [6, 7, 8, 9, 10]
  # a # => [1, 6, 7, 8, 9, 10, 5]
  #
  # a = [1, 2, 3, 4, 5]
  # a[2..] = [6, 7, 8, 9, 10]
  # a # => [1, 2, 6, 7, 8, 9, 10]
  # ```
  def []=(range : Range, values : Array(T))
    self[*Indexable.range_to_index_and_count(range, size) || raise IndexError.new] = values
  end

  # Returns all elements that are within the given range.
  #
  # The first element in the returned array is `self[range.begin]` followed
  # by the next elements up to index `range.end` (or `self[range.end - 1]` if
  # the range is exclusive).
  # If there are fewer elements in `self`, the returned array is shorter than
  # `range.size`.
  #
  # ```
  # a = ["a", "b", "c", "d", "e"]
  # a[1..3] # => ["b", "c", "d"]
  # # range.end > array.size
  # a[3..7] # => ["d", "e"]
  # ```
  #
  # Open ended ranges are clamped at the start and end of the array, respectively.
  #
  # ```
  # # open ended ranges
  # a[2..] # => ["c", "d", "e"]
  # a[..2] # => ["a", "b", "c"]
  # ```
  #
  # Negative range values are added to `self.size`, thus they are treated as
  # indices counting from the end of the array, `-1` designating the last element.
  #
  # ```
  # # negative indices, both ranges are equivalent for `a`
  # a[1..3]   # => ["b", "c", "d"]
  # a[-4..-2] # => ["b", "c", "d"]
  # # Mixing negative and positive indices, both ranges are equivalent for `a`
  # a[1..-2] # => ["b", "c", "d"]
  # a[-4..3] # => ["b", "c", "d"]
  # ```
  #
  # Raises `IndexError` if the start index is out of range (`range.begin >
  # self.size || range.begin < -self.size`). If `range.begin == self.size` an
  # empty array is returned. If `range.begin > range.end`, an empty array is
  # returned.
  #
  # ```
  # # range.begin > array.size
  # a[6..10] # raise IndexError
  # # range.begin == array.size
  # a[5..10] # => []
  # # range.begin > range.end
  # a[3..1]   # => []
  # a[-2..-4] # => []
  # a[-2..1]  # => []
  # a[3..-4]  # => []
  # ```
  def [](range : Range) : Array(T)
    self[*Indexable.range_to_index_and_count(range, size) || raise IndexError.new]
  end

  # Like `#[](Range)`, but returns `nil` if `range.begin` is out of range.
  #
  # ```
  # a = ["a", "b", "c", "d", "e"]
  # a[6..10]? # => nil
  # a[6..]?   # => nil
  # ```
  def []?(range : Range) : Array(T)?
    self[*Indexable.range_to_index_and_count(range, size) || return nil]?
  end

  # Returns count or less (if there aren't enough) elements starting at the
  # given start index.
  #
  # Negative *start* is added to `self.size`, thus it's treated as
  # index counting from the end of the array, `-1` designating the last element.
  #
  # Raises `IndexError` if *start* index is out of bounds.
  # Raises `ArgumentError` if *count* is negative.
  #
  # ```
  # a = ["a", "b", "c", "d", "e"]
  # a[-3, 3] # => ["c", "d", "e"]
  # a[1, 2]  # => ["b", "c"]
  # a[5, 1]  # => []
  # a[6, 1]  # raises IndexError
  # ```
  def [](start : Int, count : Int) : Array(T)
    self[start, count]? || raise IndexError.new
  end

  # Like `#[](Int, Int)` but returns `nil` if the *start* index is out of range.
  def []?(start : Int, count : Int) : Array(T)?
    start, count = normalize_start_and_count(start, count) { return nil }
    return Array(T).new if count == 0

    Array(T).build(count) do |buffer|
      buffer.copy_from(@buffer + start, count)
      count
    end
  end

  @[AlwaysInline]
  def unsafe_fetch(index : Int) : T
    @buffer[index]
  end

  @[AlwaysInline]
  def unsafe_put(index : Int, value : T)
    @buffer[index] = value
  end

  # Removes all elements from `self`.
  #
  # ```
  # a = ["a", "b", "c", "d", "e"]
  # a.clear # => []
  # ```
  def clear : self
    @buffer.clear(@size)
    @size = 0
    self
  end

  # Returns a new `Array` that has `self`'s elements cloned.
  # That is, it returns a deep copy of `self`.
  #
  # Use `#dup` if you want a shallow copy.
  #
  # ```
  # ary = [[1, 2], [3, 4]]
  # ary2 = ary.clone
  # ary[0][0] = 5
  # ary  # => [[5, 2], [3, 4]]
  # ary2 # => [[1, 2], [3, 4]]
  #
  # ary2 << [7, 8]
  # ary  # => [[5, 2], [3, 4]]
  # ary2 # => [[1, 2], [3, 4], [7, 8]]
  # ```
  def clone : Array(T)
    {% if T == ::Bool || T == ::Char || T == ::String || T == ::Symbol || T < ::Number::Primitive %}
      Array(T).new(size) { |i| @buffer[i].clone.as(T) }
    {% else %}
      exec_recursive_clone do |hash|
        clone = Array(T).new(size)
        hash[object_id] = clone.object_id
        each do |element|
          clone << element.clone.as(T)
        end
        clone
      end
    {% end %}
  end

  # Returns a copy of `self` with all `nil` elements removed.
  #
  # ```
  # ["a", nil, "b", nil, "c", nil].compact # => ["a", "b", "c"]
  # ```
  def compact
    compact_map &.itself
  end

  # Removes all `nil` elements from `self` and returns `self`.
  #
  # ```
  # ary = ["a", nil, "b", nil, "c"]
  # ary.compact!
  # ary # => ["a", "b", "c"]
  # ```
  def compact! : self
    reject! &.nil?
  end

  # Appends the elements of *other* to `self`, and returns `self`.
  #
  # ```
  # ary = ["a", "b"]
  # ary.concat(["c", "d"])
  # ary # => ["a", "b", "c", "d"]
  # ```
  def concat(other : Indexable) : self
    other_size = other.size

    resize_if_cant_insert(other_size)

    insert_elements_at(other, @size)

    @size += other_size

    self
  end

  # :ditto:
  def concat(other : Enumerable) : self
    left_before_resize = remaining_capacity - @size
    len = @size
    buf = @buffer + len
    other.each do |elem|
      if left_before_resize == 0
        increase_capacity
        left_before_resize = remaining_capacity - len
        buf = @buffer + len
      end
      buf.value = elem
      buf += 1
      len += 1
      left_before_resize -= 1
    end

    @size = len

    self
  end

  # Removes all items from `self` that are equal to *obj*.
  #
  # Returns the last found element that was equal to *obj*,
  # if any, or `nil` if not found.
  #
  # ```
  # a = ["a", "b", "b", "b", "c"]
  # a.delete("b") # => "b"
  # a             # => ["a", "c"]
  #
  # a.delete("x") # => nil
  # a             # => ["a", "c"]
  # ```
  def delete(obj) : T?
    internal_delete { |e| e == obj }[1]
  end

  # Removes the element at *index*, returning that element.
  # Raises `IndexError` if *index* is out of range.
  #
  # ```
  # a = ["ant", "bat", "cat", "dog"]
  # a.delete_at(2)  # => "cat"
  # a               # => ["ant", "bat", "dog"]
  # a.delete_at(99) # raises IndexError
  # ```
  def delete_at(index : Int) : T
    index = check_index_out_of_bounds index

    # Deleting the first element is the same as a shift
    if index == 0
      return shift_when_not_empty
    end

    elem = @buffer[index]
    (@buffer + index).move_from(@buffer + index + 1, size - index - 1)
    @size -= 1
    (@buffer + @size).clear
    elem
  end

  # Removes all elements within the given *range*.
  # Returns an array of the removed elements with the original order of `self` preserved.
  # Raises `IndexError` if the index is out of range.
  #
  # ```
  # a = ["ant", "bat", "cat", "dog"]
  # a.delete_at(1..2)    # => ["bat", "cat"]
  # a                    # => ["ant", "dog"]
  # a.delete_at(99..100) # raises IndexError
  # ```
  def delete_at(range : Range) : self
    delete_at(*Indexable.range_to_index_and_count(range, size) || raise IndexError.new)
  end

  # Removes *count* elements from `self` starting at *start*.
  # If the size of `self` is less than *count*, removes values to the end of the array without error.
  # Returns an array of the removed elements with the original order of `self` preserved.
  # Raises `IndexError` if *start* is out of range.
  #
  # ```
  # a = ["ant", "bat", "cat", "dog"]
  # a.delete_at(1, 2)  # => ["bat", "cat"]
  # a                  # => ["ant", "dog"]
  # a.delete_at(99, 1) # raises IndexError
  # ```
  def delete_at(start : Int, count : Int) : self
    start, count = normalize_start_and_count(start, count)

    val = self[start, count]
    (@buffer + start).move_from(@buffer + start + count, size - start - count)
    @size -= count
    (@buffer + @size).clear(count)
    val
  end

  # :ditto:
  @[Deprecated("Use `#delete_at(start, count)` instead")]
  def delete_at(*, index start : Int, count : Int) : self
    delete_at(start, count)
  end

  # Returns a new `Array` that has exactly `self`'s elements.
  # That is, it returns a shallow copy of `self`.
  #
  # Use `#clone` if you want a deep copy.
  #
  # ```
  # ary = [[1, 2], [3, 4]]
  # ary2 = ary.dup
  # ary[0][0] = 5
  # ary  # => [[5, 2], [3, 4]]
  # ary2 # => [[5, 2], [3, 4]]
  #
  # ary2 << [7, 8]
  # ary  # => [[5, 2], [3, 4]]
  # ary2 # => [[5, 2], [3, 4], [7, 8]]
  # ```
  def dup : Array(T)
    Array(T).build(@size) do |buffer|
      buffer.copy_from(@buffer, size)
      size
    end
  end

  # Yields each index of `self`, starting at *start*, to the given block and then assigns
  # the block's value in that position. Returns `self`.
  #
  # Negative values of *start* count from the end of the array.
  #
  # Raises `IndexError` if *start* is outside the array range.
  #
  # ```
  # a = [1, 2, 3, 4]
  # a.fill(2) { |i| i * i } # => [1, 2, 4, 9]
  # ```
  @[Deprecated("Use `fill(start.., &)` instead")]
  def fill(start : Int, & : Int32 -> T) : self
    fill(start..) { |i| yield i }
  end

  # :ditto:
  @[Deprecated("Use `fill(start.., &)` instead")]
  def fill(*, from start : Int, & : Int32 -> T) : self
    fill(start..) { |i| yield i }
  end

  # Yields each index of `self`, starting at *start* and just *count* times,
  # to the given block and then assigns the block's value in that position. Returns `self`.
  #
  # Negative values of *start* count from the end of the array.
  #
  # Raises `IndexError` if *start* is outside the array range.
  #
  # Has no effect if *count* is zero or negative.
  #
  # ```
  # a = [1, 2, 3, 4, 5, 6]
  # a.fill(2, 2) { |i| i * i } # => [1, 2, 4, 9, 5, 6]
  # ```
  @[Deprecated("Use `Indexable::Mutable#fill(start, count, &)` instead")]
  def fill(*, from start : Int, count : Int, & : Int32 -> T) : self
    fill(start, count) { |i| yield i }
  end

  # :inherit:
  def fill(value : T) : self
    # enable memset optimization
    to_unsafe_slice.fill(value)
    self
  end

  # Replaces every element in `self`, starting at *start*, with the given *value*. Returns `self`.
  #
  # Negative values of *start* count from the end of the array.
  #
  # ```
  # a = [1, 2, 3, 4, 5]
  # a.fill(9, 2) # => [1, 2, 9, 9, 9]
  # ```
  @[Deprecated("Use `fill(value, start..)` instead")]
  def fill(value : T, start : Int) : self
    fill(value, start..)
  end

  # :ditto:
  @[Deprecated("Use `fill(value, start..)` instead")]
  def fill(value : T, *, from start : Int) : self
    fill(value, start..)
  end

  # Replaces *count* or less (if there aren't enough) elements starting at the
  # given *start* index with *value*. Returns `self`.
  #
  # Negative values of *start* count from the end of the container.
  #
  # Raises `IndexError` if the *start* index is out of range.
  #
  # Raises `ArgumentError` if *count* is negative.
  #
  # ```
  # array = [1, 2, 3, 4, 5]
  # array.fill(9, 2, 2) # => [1, 2, 9, 9, 5]
  # array               # => [1, 2, 9, 9, 5]
  # ```
  def fill(value : T, start : Int, count : Int) : self
    to_unsafe_slice.fill(value, start, count)
    self
  end

  # :ditto:
  @[Deprecated("Use `#fill(value, start, count)` instead")]
  def fill(value : T, *, from start : Int, count : Int) : self
    fill(value, start, count)
  end

  # Replaces every element in *range* with *value*. Returns `self`.
  #
  # Negative values of *from* count from the end of the array.
  #
  # ```
  # a = [1, 2, 3, 4, 5]
  # a.fill(9, 2..3) # => [1, 2, 9, 9, 5]
  # ```
  def fill(value : T, range : Range) : self
    to_unsafe_slice.fill(value, range)
    self
  end

  # Returns the first *n* elements of the array.
  #
  # ```
  # [1, 2, 3].first(2) # => [1, 2]
  # [1, 2, 3].first(4) # => [1, 2, 3]
  # ```
  def first(n : Int) : Array(T)
    self[0, n]
  end

  # Insert *object* before the element at *index* and shifting successive elements, if any.
  # Returns `self`.
  #
  # Negative values of *index* count from the end of the array.
  #
  # ```
  # a = ["a", "b", "c"]
  # a.insert(0, "x")  # => ["x", "a", "b", "c"]
  # a.insert(2, "y")  # => ["x", "a", "y", "b", "c"]
  # a.insert(-1, "z") # => ["x", "a", "y", "b", "c", "z"]
  # ```
  def insert(index : Int, object : T) : self
    if index == 0
      return unshift(object)
    end

    if index < 0
      index += size + 1
    end

    unless 0 <= index <= size
      raise IndexError.new
    end

    check_needs_resize
    (@buffer + index + 1).move_from(@buffer + index, size - index)
    @buffer[index] = object

    @size += 1

    self
  end

  # Inserts all of the elements from *other* before the element at *index*.
  #
  # This method shifts the element currently at *index* (if any) and any
  # subsequent elements to the right, increasing their indices. If the value
  # of *index* is negative, counting starts from the end of the array.
  # For example, `-1` indicates insertion after the last element, `-2` before
  # the last element.
  #
  # Raises `IndexError` if the *index* is out of bounds.
  #
  # ```
  # fruits = ["Apple"]
  # newFruits = ["Dragonfruit", "Elderberry"]
  #
  # fruits.insert_all(1, newFruits)             # => ["Apple", "Dragonfruit", "Elderberry"]
  # fruits.insert_all(-3, ["Banana", "Cherry"]) # => ["Apple", "Banana", "Cherry", "Dragonfruit", "Elderberry"]
  #
  # fruits.insert_all(6, ["invalid"])  # raises IndexError
  # fruits.insert_all(-7, ["indices"]) # raises IndexError
  # ```
  def insert_all(index : Int, other : Indexable) : self
    other_size = other.size

    return self if other_size == 0

    if index < 0
      index += size + 1
    end

    unless 0 <= index <= size
      raise IndexError.new
    end

    resize_if_cant_insert(other_size)
    (@buffer + index).move_to(@buffer + index + other_size, @size - index)

    insert_elements_at(other, index)

    @size += other_size

    self
  end

  private def insert_elements_at(other : Array | Slice | StaticArray, index : Int) : Nil
    (@buffer + index).copy_from(other.to_unsafe, other.size)
  end

  private def insert_elements_at(other : Deque, index : Int) : Nil
    ptr = @buffer + index
    Deque.half_slices(other) do |slice|
      ptr.copy_from(slice.to_unsafe, slice.size)
      ptr += slice.size
    end
  end

  private def insert_elements_at(other, index : Int) : Nil
    appender = (@buffer + index).appender
    other.each do |elem|
      appender << elem
    end
  end

  def inspect(io : IO) : Nil
    to_s io
  end

  # Returns the last *n* elements of the array.
  #
  # ```
  # [1, 2, 3].last(2) # => [2, 3]
  # [1, 2, 3].last(4) # => [1, 2, 3]
  # ```
  def last(n : Int) : Array(T)
    if n < @size
      self[@size - n, n]
    else
      dup
    end
  end

  # :nodoc:
  protected def size=(size : Int)
    @size = size.to_i
  end

  # :inherit:
  def each_slice(count : Int, &)
    to_unsafe_slice.each_slice(count) { |elems| yield elems }
  end

  # Optimized version of `Enumerable#map`.
  def map(& : T -> U) : Array(U) forall U
    Array(U).new(size) { |i| yield @buffer[i] }
  end

  # Modifies `self`, keeping only the elements in the collection for which the
  # passed block is truthy. Returns `self`.
  #
  # ```
  # ary = [1, 6, 2, 4, 8]
  # ary.select! { |x| x > 3 }
  # ary # => [6, 4, 8]
  # ```
  #
  # See also: `Array#select`.
  def select!(& : T ->) : self
    reject! { |elem| !yield(elem) }
  end

  # Modifies `self`, keeping only the elements in the collection for which
  # `pattern === element`.
  #
  # ```
  # ary = [1, 6, 2, 4, 8]
  # ary.select!(3..7)
  # ary # => [6, 4]
  # ```
  #
  # See also: `Array#reject!`.
  def select!(pattern) : self
    self.select! { |elem| pattern === elem }
  end

  # Modifies `self`, deleting the elements in the collection for which the
  # passed block is truthy. Returns `self`.
  #
  # ```
  # ary = [1, 6, 2, 4, 8]
  # ary.reject! { |x| x > 3 }
  # ary # => [1, 2]
  # ```
  #
  # See also: `Array#reject`.
  def reject!(& : T ->) : self
    internal_delete { |e| yield e }
    self
  end

  # Modifies `self`, deleting the elements in the collection for which
  # `pattern === element`.
  #
  # ```
  # ary = [1, 6, 2, 4, 8]
  # ary.reject!(3..7)
  # ary # => [1, 2, 8]
  # ```
  #
  # See also: `Array#select!`.
  def reject!(pattern) : self
    reject! { |elem| pattern === elem }
    self
  end

  # `reject!` and `delete` implementation: returns a tuple {x, y}
  # with x being self/nil (modified, not modified)
  # and y being the last matching element, or nil
  private def internal_delete(&)
    i1 = 0
    i2 = 0
    match = nil
    while i1 < @size
      e = @buffer[i1]
      if yield e, i1
        match = e
      else
        if i1 != i2
          @buffer[i2] = e
        end
        i2 += 1
      end

      i1 += 1
    end

    if i2 != i1
      count = i1 - i2
      @size -= count
      (@buffer + @size).clear(count)
      {self, match}
    else
      {nil, match}
    end
  end

  # Optimized version of `Enumerable#map_with_index`.
  #
  # Accepts an optional *offset* parameter, which tells it to start counting
  # from there.
  #
  # ```
  # gems = ["crystal", "pearl", "diamond"]
  # results = gems.map_with_index { |gem, i| "#{i}: #{gem}" }
  # results # => ["0: crystal", "1: pearl", "2: diamond"]
  # ```
  def map_with_index(offset = 0, & : T, Int32 -> _)
    Array.new(size) { |i| yield @buffer[i], offset + i }
  end

  # Returns an `Array` with the first *count* elements removed
  # from the original array.
  #
  # If *count* is bigger than the number of elements in the array, returns an empty array.
  #
  # ```
  # [1, 2, 3, 4, 5, 6].skip(3) # => [4, 5, 6]
  # ```
  def skip(count : Int) : Array(T)
    raise ArgumentError.new("Attempt to skip negative size") if count < 0

    new_size = Math.max(size - count, 0)
    Array(T).build(new_size) do |buffer|
      buffer.copy_from(to_unsafe + count, new_size)
      new_size
    end
  end

  # Returns a new `Array` that is a one-dimensional flattening of `self` (recursively).
  #
  # That is, for every element that is an array or an iterator, extract its elements into the new array.
  #
  # ```
  # s = [1, 2, 3]          # => [1, 2, 3]
  # t = [4, 5, 6, [7, 8]]  # => [4, 5, 6, [7, 8]]
  # u = [9, [10, 11].each] # => [9, #<Indexable::ItemIterator>]
  # a = [s, t, u, 12, 13]  # => [[1, 2, 3], [4, 5, 6, [7, 8]], 9, #<Indexable::ItemIterator>, 12, 13]
  # a.flatten              # => [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13]
  # ```
  def flatten
    FlattenHelper(typeof(FlattenHelper.element_type(self))).flatten(self)
  end

  # Returns an `Array` of all ordered combinations of elements taken from each
  # of the *arrays* as `Array`s.
  # Traversal of elements starts from the last given array.
  @[Deprecated("Use `Indexable.cartesian_product(indexables : Indexable(Indexable))` instead")]
  def self.product(arrays : Array(Array))
    Indexable.cartesian_product(arrays)
  end

  # :ditto:
  @[Deprecated("Use `Indexable.cartesian_product(indexables : Indexable(Indexable))` instead")]
  def self.product(*arrays : Array)
    Indexable.cartesian_product(arrays)
  end

  # Yields each ordered combination of the elements taken from each of the
  # *arrays* as `Array`s.
  # Traversal of elements starts from the last given array.
  @[Deprecated("Use `Indexable.each_cartesian(indexables : Indexable(Indexable), reuse = false, &block)` instead")]
  def self.each_product(arrays : Array(Array), reuse = false, &)
    Indexable.each_cartesian(arrays, reuse: reuse) { |r| yield r }
  end

  # :ditto:
  @[Deprecated("Use `Indexable.each_cartesian(indexables : Indexable(Indexable), reuse = false, &block)` instead")]
  def self.each_product(*arrays : Array, reuse = false, &)
    Indexable.each_cartesian(arrays, reuse: reuse) { |r| yield r }
  end

  def repeated_permutations(size : Int = self.size) : Array(Array(T))
    ary = [] of Array(T)
    each_repeated_permutation(size) do |a|
      ary << a
    end
    ary
  end

  def each_repeated_permutation(size : Int = self.size, reuse = false, &) : Nil
    n = self.size
    return if size != 0 && n == 0
    raise ArgumentError.new("Size must be positive") if size < 0

    if size == 0
      yield([] of T)
    else
      Indexable.each_cartesian(Array.new(size, self), reuse: reuse) { |r| yield r }
    end
  end

  # Removes the last value from `self`, at index *size - 1*.
  # This method returns the removed value.
  # Raises `IndexError` if array is of 0 size.
  #
  # ```
  # a = ["a", "b", "c"]
  # a.pop # => "c"
  # a     # => ["a", "b"]
  # ```
  #
  # See also: `#truncate`.
  def pop : T
    pop { raise IndexError.new }
  end

  # Removes the last value from `self`.
  # If the array is empty, the given block is called.
  #
  # ```
  # a = [1]
  # a.pop { "Testing" } # => 1
  # a.pop { "Testing" } # => "Testing"
  # ```
  #
  # See also: `#truncate`.
  def pop(&)
    if @size == 0
      yield
    else
      @size -= 1
      value = @buffer[@size]
      (@buffer + @size).clear

      # If we remain empty we also take the chance to
      # reset the buffer to its original position.
      if empty? && @offset_to_buffer != 0
        reset_buffer_to_root_buffer
      end

      value
    end
  end

  # Removes the last *n* values from `self`, at index *size - 1*.
  # This method returns an array of the removed values, with the original order preserved.
  #
  # If *n* is greater than the size of `self`, all values will be removed from `self`
  # without raising an error.
  #
  # ```
  # a = ["a", "b", "c"]
  # a.pop(2) # => ["b", "c"]
  # a        # => ["a"]
  #
  # a = ["a", "b", "c"]
  # a.pop(4) # => ["a", "b", "c"]
  # a        # => []
  # ```
  #
  # See also: `#truncate`.
  def pop(n : Int) : Array(T)
    if n < 0
      raise ArgumentError.new("Can't pop negative count")
    end

    n = Math.min(n, @size)
    ary = Array(T).new(n) { |i| @buffer[@size - n + i] }

    @size -= n
    (@buffer + @size).clear(n)

    ary
  end

  # Like `pop`, but returns `nil` if `self` is empty.
  #
  # See also: `#truncate`.
  def pop? : T?
    pop { nil }
  end

  # Returns an `Array` of all ordered combinations of elements taken from each
  # of `self` and *ary* as `Tuple`s.
  # Traversal of elements starts from *ary*.
  @[Deprecated("Use `Indexable#cartesian_product(*others : Indexable)` instead")]
  def product(ary : Array(U)) forall U
    cartesian_product(ary)
  end

  # Yields each ordered combination of the elements taken from each of `self`
  # and *enumerable* as a `Tuple`.
  # Traversal of elements starts from *enumerable*.
  @[Deprecated("Use `Indexable#each_cartesian(*others : Indexable, &block)` instead")]
  def product(enumerable : Enumerable, &)
    self.each { |a| enumerable.each { |b| yield a, b } }
  end

  # Append. Pushes one value to the end of `self`, given that the type of the value is *T*
  # (which might be a single type or a union of types).
  # This method returns `self`, so several calls can be chained.
  # See `pop` for the opposite effect.
  #
  # ```
  # a = ["a", "b"]
  # a.push("c") # => ["a", "b", "c"]
  # a.push(1)   # Errors, because the array only accepts String.
  #
  # a = ["a", "b"] of (Int32 | String)
  # a.push("c") # => ["a", "b", "c"]
  # a.push(1)   # => ["a", "b", "c", 1]
  # ```
  def push(value : T) : self
    check_needs_resize
    @buffer[@size] = value
    @size += 1
    self
  end

  # Append multiple values. The same as `push`, but takes an arbitrary number
  # of values to push into `self`. Returns `self`.
  #
  # ```
  # a = ["a"]
  # a.push("b", "c") # => ["a", "b", "c"]
  # ```
  def push(*values : T) : self
    resize_if_cant_insert(values.size)

    values.each_with_index do |value, i|
      @buffer[@size + i] = value
    end
    @size += values.size
    self
  end

  # Replaces the contents of `self` with the contents of *other*.
  # This resizes the Array to a greater capacity but does not free memory if the given array is smaller.
  #
  # ```
  # a1 = [1, 2, 3]
  # a1.replace([1])
  # a1                    # => [1]
  # a1.remaining_capacity # => 3
  # a2 = [1]
  # a2.replace([1, 2, 3])
  # a2 # => [1, 2, 3]
  # ```
  def replace(other : Array) : self
    if other.size > @capacity
      reset_buffer_to_root_buffer
      resize_to_capacity(calculate_new_capacity(other.size))
    elsif other.size > remaining_capacity
      shift_buffer_by(remaining_capacity - other.size)
    elsif other.size < @size
      (@buffer + other.size).clear(@size - other.size)
    end

    @buffer.copy_from(other.to_unsafe, other.size)
    @size = other.size
    self
  end

  # Returns an array with all the elements in the collection reversed.
  #
  # ```
  # a = [1, 2, 3]
  # a.reverse # => [3, 2, 1]
  # ```
  def reverse : Array(T)
    Array(T).new(size) { |i| @buffer[size - i - 1] }
  end

  # :inherit:
  def rotate!(n : Int = 1) : self
    to_unsafe_slice.rotate!(n)
    self
  end

  # Returns an array with all the elements shifted to the left `n` times.
  #
  # ```
  # a = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
  # a.rotate    # => [1, 2, 3, 4, 5, 6, 7, 8, 9, 0]
  # a.rotate(1) # => [1, 2, 3, 4, 5, 6, 7, 8, 9, 0]
  # a.rotate(3) # => [3, 4, 5, 6, 7, 8, 9, 0, 1, 2]
  # a           # => [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
  # ```
  def rotate(n = 1) : Array(T)
    return self if size == 0
    n %= size
    return self if n == 0
    res = Array(T).new(size)
    res.to_unsafe.copy_from(@buffer + n, size - n)
    (res.to_unsafe + size - n).copy_from(@buffer, n)
    res.size = size
    res
  end

  # Removes the first value of `self`, at index 0. This method returns the removed value.
  # If the array is empty, it raises `IndexError`.
  #
  # ```
  # a = ["a", "b", "c"]
  # a.shift # => "a"
  # a       # => ["b", "c"]
  # ```
  #
  # See also: `#truncate`.
  def shift : T
    shift { raise IndexError.new }
  end

  # Removes the first value of `self`, at index 0, or otherwise invokes the given block.
  # This method returns the removed value.
  # If the array is empty, it invokes the given block and returns its value.
  #
  # ```
  # a = ["a"]
  # a.shift { "empty!" } # => "a"
  # a                    # => []
  # a.shift { "empty!" } # => "empty!"
  # a                    # => []
  # ```
  #
  # See also: `#truncate`.
  def shift(&)
    if @size == 0
      yield
    else
      shift_when_not_empty
    end
  end

  # Internal implementation of shift when we are sure the array is not empty
  private def shift_when_not_empty
    value = @buffer[0]
    @size -= 1
    @buffer.clear(1)

    if empty?
      reset_buffer_to_root_buffer
    else
      shift_buffer_by(1)
    end

    value
  end

  # Removes the first *n* values of `self`, starting at index 0.
  # This method returns an array of the removed values.
  #
  # If *n* is greater than the size of `self`, all values will be removed from `self`
  # without raising an error.
  #
  # ```
  # a = ["a", "b", "c"]
  # a.shift # => "a"
  # a       # => ["b", "c"]
  #
  # a = ["a", "b", "c"]
  # a.shift(4) # => ["a", "b", "c"]
  # a          # => []
  # ```
  #
  # See also: `#truncate`.
  def shift(n : Int) : Array(T)
    if n < 0
      raise ArgumentError.new("Can't shift negative count")
    end

    n = Math.min(n, @size)
    ary = Array(T).new(n) { |i| @buffer[i] }

    @size -= n

    @buffer.clear(n)

    if empty?
      reset_buffer_to_root_buffer
    else
      shift_buffer_by(n)
    end

    ary
  end

  # Removes the first value of `self`, at index 0. This method returns the removed value.
  # If the array is empty, it returns `nil` without raising any error.
  #
  # ```
  # a = ["a", "b"]
  # a.shift? # => "a"
  # a        # => ["b"]
  # a.shift? # => "b"
  # a        # => []
  # a.shift? # => nil
  # a        # => []
  # ```
  #
  # See also: `#truncate`.
  def shift? : T?
    shift { nil }
  end

  # Returns an array with all the elements in the collection randomized
  # using the given *random* number generator.
  def shuffle(random : Random = Random::DEFAULT) : Array(T)
    dup.shuffle!(random)
  end

  # Returns a new instance with all elements sorted based on the return value of
  # their comparison method `T#<=>` (see `Comparable#<=>`), using a stable sort algorithm.
  #
  # ```
  # a = [3, 1, 2]
  # a.sort # => [1, 2, 3]
  # a      # => [3, 1, 2]
  # ```
  #
  # See `Indexable::Mutable#sort!` for details on the sorting mechanism.
  #
  # Raises `ArgumentError` if the comparison between any two elements returns `nil`.
  def sort : Array(T)
    dup.sort!
  end

  # Returns a new instance with all elements sorted based on the return value of
  # their comparison method `T#<=>` (see `Comparable#<=>`), using an unstable sort algorithm.
  #
  # ```
  # a = [3, 1, 2]
  # a.unstable_sort # => [1, 2, 3]
  # a               # => [3, 1, 2]
  # ```
  #
  # See `Indexable::Mutable#unstable_sort!` for details on the sorting mechanism.
  #
  # Raises `ArgumentError` if the comparison between any two elements returns `nil`.
  def unstable_sort : Array(T)
    dup.unstable_sort!
  end

  # Returns a new instance with all elements sorted based on the comparator in the
  # given block, using a stable sort algorithm.
  #
  # ```
  # a = [3, 1, 2]
  # b = a.sort { |a, b| b <=> a }
  #
  # b # => [3, 2, 1]
  # a # => [3, 1, 2]
  # ```
  #
  # See `Indexable::Mutable#sort!(&block : T, T -> U)` for details on the sorting mechanism.
  #
  # Raises `ArgumentError` if for any two elements the block returns `nil`.
  def sort(&block : T, T -> U) : Array(T) forall U
    {% unless U <= Int32? %}
      {% raise "Expected block to return Int32 or Nil, not #{U}.\nThe block is supposed to be a custom comparison operation, compatible with `Comparable#<=>`.\nDid you mean to use `#sort_by`?" %}
    {% end %}

    dup.sort! &block
  end

  # Returns a new instance with all elements sorted based on the comparator in the
  # given block, using an unstable sort algorithm.
  #
  # ```
  # a = [3, 1, 2]
  # b = a.unstable_sort { |a, b| b <=> a }
  #
  # b # => [3, 2, 1]
  # a # => [3, 1, 2]
  # ```
  #
  # See `Indexable::Mutable#unstable_sort!(&block : T, T -> U)` for details on the sorting mechanism.
  #
  # Raises `ArgumentError` if for any two elements the block returns `nil`.
  def unstable_sort(&block : T, T -> U) : Array(T) forall U
    {% unless U <= Int32? %}
      {% raise "Expected block to return Int32 or Nil, not #{U}.\nThe block is supposed to be a custom comparison operation, compatible with `Comparable#<=>`.\nDid you mean to use `#unstable_sort_by`?" %}
    {% end %}

    dup.unstable_sort!(&block)
  end

  # :inherit:
  def sort! : Array(T)
    to_unsafe_slice.sort!
    self
  end

  # :inherit:
  def unstable_sort! : self
    to_unsafe_slice.unstable_sort!
    self
  end

  # :inherit:
  def sort!(&block : T, T -> U) : self forall U
    {% unless U <= Int32? %}
      {% raise "Expected block to return Int32 or Nil, not #{U}.\nThe block is supposed to be a custom comparison operation, compatible with `Comparable#<=>`.\nDid you mean to use `#sort_by!`?" %}
    {% end %}

    to_unsafe_slice.sort!(&block)
    self
  end

  # :inherit:
  def unstable_sort!(&block : T, T -> U) : self forall U
    {% unless U <= Int32? %}
      {% raise "Expected block to return Int32 or Nil, not #{U}.\nThe block is supposed to be a custom comparison operation, compatible with `Comparable#<=>`.\nDid you mean to use `#unstable_sort_by!`?" %}
    {% end %}

    to_unsafe_slice.unstable_sort!(&block)
    self
  end

  # Returns a new instance with all elements sorted by the output value of the
  # block. The output values are compared via the comparison method `T#<=>`
  # (see `Comparable#<=>`), using a stable sort algorithm.
  #
  # ```
  # a = %w(apple pear fig)
  # b = a.sort_by { |word| word.size }
  # b # => ["fig", "pear", "apple"]
  # a # => ["apple", "pear", "fig"]
  # ```
  #
  # If stability is expendable, `#unstable_sort_by(&block : T -> _)` provides a
  # performance advantage over stable sort.
  #
  # See `Indexable::Mutable#sort_by!(&block : T -> _)` for details on the sorting mechanism.
  #
  # Raises `ArgumentError` if the comparison between any two comparison values returns `nil`.
  def sort_by(&block : T -> _) : Array(T)
    dup.sort_by! { |e| yield(e) }
  end

  # Returns a new instance with all elements sorted by the output value of the
  # block. The output values are compared via the comparison method `#<=>`
  # (see `Comparable#<=>`), using an unstable sort algorithm.
  #
  # ```
  # a = %w(apple pear fig)
  # b = a.unstable_sort_by { |word| word.size }
  # b # => ["fig", "pear", "apple"]
  # a # => ["apple", "pear", "fig"]
  # ```
  #
  # If stability is necessary, use `#sort_by(&block : T -> _)` instead.
  #
  # See `Indexable::Mutable#unstable_sort!(&block : T -> _)` for details on the sorting mechanism.
  #
  # Raises `ArgumentError` if the comparison between any two comparison values returns `nil`.
  def unstable_sort_by(&block : T -> _) : Array(T)
    dup.unstable_sort_by! { |e| yield(e) }
  end

  # :inherit:
  def sort_by!(&block : T -> _) : Array(T)
    sorted = map { |e| {e, yield(e)} }.sort! { |x, y| x[1] <=> y[1] }
    @size.times do |i|
      @buffer[i] = sorted.to_unsafe[i][0]
    end
    self
  end

  # :inherit:
  def unstable_sort_by!(&block : T -> _) : Array(T)
    sorted = map { |e| {e, yield(e)} }.unstable_sort! { |x, y| x[1] <=> y[1] }
    @size.times do |i|
      @buffer[i] = sorted.to_unsafe[i][0]
    end
    self
  end

  def to_a : self
    self
  end

  # Prints a nicely readable and concise string representation of this array
  # to *io*.
  #
  # The result resembles an array literal but it does not necessarily compile.
  #
  # Each element is presented using its `#inspect(io)` result to avoid ambiguity.
  def to_s(io : IO) : Nil
    executed = exec_recursive(:to_s) do
      io << '['
      join io, ", ", &.inspect(io)
      io << ']'
    end
    io << "[...]" unless executed
  end

  def pretty_print(pp) : Nil
    executed = exec_recursive(:pretty_print) do
      pp.list("[", self, "]")
    end
    pp.text "[...]" unless executed
  end

  # Returns a pointer to the internal buffer where `self`'s elements are stored.
  #
  # This method is **unsafe** because it returns a pointer, and the pointed might eventually
  # not be that of `self` if the array grows and its internal buffer is reallocated.
  #
  # ```
  # ary = [1, 2, 3]
  # ary.to_unsafe[0] # => 1
  # ```
  def to_unsafe : Pointer(T)
    @buffer
  end

  # Assumes that `self` is an array of arrays and transposes the rows and columns.
  #
  # ```
  # a = [[:a, :b], [:c, :d], [:e, :f]]
  # a.transpose # => [[:a, :c, :e], [:b, :d, :f]]
  # a           # => [[:a, :b], [:c, :d], [:e, :f]]
  # ```
  def transpose
    return Array(Array(typeof(Enumerable.element_type Enumerable.element_type self))).new if empty?

    len = self[0].size
    (1...@size).each do |i|
      l = self[i].size
      raise IndexError.new if len != l
    end

    Array(Array(typeof(Enumerable.element_type Enumerable.element_type self))).new(len) do |i|
      Array(typeof(Enumerable.element_type Enumerable.element_type self)).new(@size) do |j|
        self[j][i]
      end
    end
  end

  # Removes all elements except the *count* or less (if there aren't enough)
  # elements starting at the given *start* index. Returns `self`.
  #
  # Negative values of *start* count from the end of the array.
  #
  # Raises `IndexError` if the *start* index is out of range.
  #
  # Raises `ArgumentError` if *count* is negative.
  #
  # ```
  # a = [0, 1, 4, 9, 16, 25]
  # a.truncate(2, 3) # => [4, 9, 16]
  # a                # => [4, 9, 16]
  # ```
  #
  # See also: `#pop`, `#shift`.
  def truncate(start : Int, count : Int) : self
    start, count = normalize_start_and_count(start, count)

    if count == 0
      clear
      reset_buffer_to_root_buffer
    else
      @buffer.clear(start)
      (@buffer + start + count).clear(size - start - count)
      @size = count
      shift_buffer_by(start)
    end

    self
  end

  # Removes all elements except those within the given *range*. Returns `self`.
  #
  # ```
  # a = [0, 1, 4, 9, 16, 25]
  # a.truncate(1..-3) # => [1, 4, 9]
  # a                 # => [1, 4, 9]
  # ```
  def truncate(range : Range) : self
    truncate(*Indexable.range_to_index_and_count(range, size) || raise IndexError.new)
  end

  # Returns a new `Array` by removing duplicate values in `self`.
  #
  # ```
  # a = ["a", "a", "b", "b", "c"]
  # a.uniq # => ["a", "b", "c"]
  # a      # => [ "a", "a", "b", "b", "c" ]
  # ```
  def uniq : Array(T)
    if size <= 1
      return dup
    end

    # Heuristic: for a small array it's faster to do a linear scan
    # than creating a Set to find out duplicates.
    if size <= SMALL_ARRAY_SIZE
      ary = Array(T).new
      each do |elem|
        ary << elem unless ary.includes?(elem)
      end
      return ary
    end

    # Convert the Array into a Set and then ask for its values
    to_set.to_a
  end

  # Returns a new `Array` by removing duplicate values in `self`, using the block's
  # value for comparison.
  #
  # ```
  # a = [{"student", "sam"}, {"student", "george"}, {"teacher", "matz"}]
  # a.uniq { |s| s[0] } # => [{"student", "sam"}, {"teacher", "matz"}]
  # a                   # => [{"student", "sam"}, {"student", "george"}, {"teacher", "matz"}]
  # ```
  def uniq(& : T ->) : Array(T)
    if size <= 1
      dup
    else
      hash = to_lookup_hash { |elem| yield elem }
      hash.values
    end
  end

  # Removes duplicate elements from `self`. Returns `self`.
  #
  # ```
  # a = ["a", "a", "b", "b", "c"]
  # a.uniq! # => ["a", "b", "c"]
  # a       # => ["a", "b", "c"]
  # ```
  def uniq! : self
    if size <= 1
      return self
    end

    # Heuristic: for small arrays we do a linear scan, which is usually
    # faster than creating an intermediate Hash.
    if size <= SMALL_ARRAY_SIZE
      # We simply delete elements we've seen before
      internal_delete do |elem, index|
        (0...index).any? { |subindex| elem == to_unsafe[subindex] }
      end
      return self
    end

    uniq! &.itself
  end

  # Removes duplicate elements from `self`, using the block's value for comparison. Returns `self`.
  #
  # ```
  # a = [{"student", "sam"}, {"student", "george"}, {"teacher", "matz"}]
  # a.uniq! { |s| s[0] } # => [{"student", "sam"}, {"teacher", "matz"}]
  # a                    # => [{"student", "sam"}, {"teacher", "matz"}]
  # ```
  def uniq!(& : T ->) : self
    if size <= 1
      return self
    end

    hash = to_lookup_hash { |elem| yield elem }
    if size == hash.size
      return self
    end

    old_size = @size
    @size = hash.size
    removed = old_size - @size
    return self if removed == 0

    ptr = @buffer
    hash.each do |k, v|
      ptr.value = v
      ptr += 1
    end

    (@buffer + @size).clear(removed)

    self
  end

  # Prepend. Adds *object* to the beginning of `self`, given that the type of the value is *T*
  # (which might be a single type or a union of types).
  # This method returns `self`, so several calls can be chained.
  # See `shift` for the opposite effect.
  #
  # ```
  # a = ["a", "b"]
  # a.unshift("c") # => ["c", "a", "b"]
  # a.unshift(1)   # Errors, because the array only accepts String.
  #
  # a = ["a", "b"] of (Int32 | String)
  # a.unshift("c") # => ["c", "a", "b"]
  # a.unshift(1)   # => [1, "c", "a", "b"]
  # ```
  def unshift(object : T) : self
    check_needs_resize_for_unshift
    shift_buffer_by(-1)
    @buffer.value = object
    @size += 1

    self
  end

  # Prepend multiple values. The same as `unshift`, but takes an arbitrary number
  # of values to add to the array. Returns `self`.
  def unshift(*values : T) : self
    values.reverse_each do |value|
      unshift(value)
    end
    self
  end

  private def check_needs_resize
    # We have to compare against the actual capacity in case `@buffer` was moved
    return unless needs_resize?

    # If the array is not empty and more than half of the elements were shifted
    # then we avoid a resize and just move the elements to the left.
    # This is an heuristic. We could always try to move the elements if
    # `@offset_to_buffer` is positive but it might happen that a user does
    # `shift` + `push` in succession and it will produce a lot of memcopies.
    #
    # Note: `@offset_to_buffer != 0` is not redundant because `@capacity` might be 1.
    # and so `@capacity / 2` is 0 and `@offset_to_buffer >= @capacity / 2` would hold
    # without it.
    if @capacity != 0 && @offset_to_buffer != 0 && @offset_to_buffer >= @capacity / 2
      # Given
      #
      #     [-, -, -, 'c', 'd', -]
      #      |         |
      #      |         ^-- `@buffer`
      #      |
      #      ^-- root_buffer
      #
      # and:
      # - @size is 2
      # - @capacity is 6
      # - @offset_to_buffer is 3
      # - remaining_capacity is 3

      # First copy the remaining elements in the array to the front
      #
      #     [-, -, -, 'c', 'd', -]
      #               ^-------^
      #                   |
      #                   ^-- copy this
      #
      #     [-, -, -, 'c', 'd', -]
      #     ^----^
      #       |
      #       ^-- here
      #
      # We get:
      #
      #     ['c', 'd', '-', 'c', 'd', -]
      root_buffer.copy_from(@buffer, @size)

      # Then after that we have to clear the rest of the elements
      #
      #     ['c', 'd', '-', 'c', 'd', -]
      #              ^-------------^
      #                     |
      #                     ^-- clear this
      # We get:
      #
      #     ['c', 'd', -, -, -, -]
      (root_buffer + @size).clear(@offset_to_buffer)

      # Move the buffer pointer to where it was originally allocated,
      # and now we don't have any offset to the root buffer
      reset_buffer_to_root_buffer
    else
      increase_capacity
    end
  end

  private def needs_resize?
    @size == remaining_capacity
  end

  private def check_needs_resize_for_unshift
    return unless @offset_to_buffer == 0

    # If we have no more room left before the beginning of the array
    # we make the array larger, but point the buffer to start at the middle
    # of the entire allocated memory. In this way, if more elements are unshift
    # later we won't need a reallocation right away. This is similar to what
    # happens when we push and we don't have more room, except that toward
    # the beginning.

    half_capacity = @capacity // 2
    if @capacity != 0 && half_capacity != 0 && @size <= half_capacity
      # Apply the same heuristic as the case for pushing elements to the array,
      # but in backwards: (note that `@size` can be 0 here)

      # `['c', 'd', -, -, -, -] (@size = 2)`
      (root_buffer + half_capacity).copy_from(@buffer, @size)

      # `['c', 'd', -, 'c', 'd', -]`
      root_buffer.clear(@size)

      # `[-, -, -, 'c', 'd', -]`
      shift_buffer_by(half_capacity)
    else
      increase_capacity_for_unshift
    end
  end

  def remaining_capacity : Int32
    @capacity - @offset_to_buffer
  end

  # behaves like `calculate_new_capacity(@capacity + 1)`
  private def calculate_new_capacity
    return INITIAL_CAPACITY if @capacity == 0

    if @capacity < CAPACITY_THRESHOLD
      @capacity * 2
    else
      @capacity + (@capacity + 3 * CAPACITY_THRESHOLD) // 4
    end
  end

  private def calculate_new_capacity(new_size)
    # Resizing is done via `Pointer#realloc` on the root buffer, so the space
    # between the root and real buffers remains untouched
    new_size += @offset_to_buffer

    new_capacity = @capacity == 0 ? INITIAL_CAPACITY : @capacity
    while new_capacity < new_size
      if new_capacity < CAPACITY_THRESHOLD
        new_capacity *= 2
      else
        new_capacity += (new_capacity + 3 * CAPACITY_THRESHOLD) // 4
      end
    end
    new_capacity
  end

  private def increase_capacity
    resize_to_capacity(calculate_new_capacity)
  end

  private def resize_to_capacity(capacity)
    @capacity = capacity
    if @buffer
      @buffer = root_buffer.realloc(@capacity) + @offset_to_buffer
    else
      @buffer = Pointer(T).malloc(@capacity)
    end
  end

  # Similar to `increase_capacity`, except that after reallocating the buffer
  # we point it to the middle of the buffer in case more unshifts come right away.
  # This assumes @offset_to_buffer is zero.
  private def increase_capacity_for_unshift
    resize_to_capacity_for_unshift(calculate_new_capacity)
  end

  private def resize_to_capacity_for_unshift(capacity)
    old_capacity, @capacity = @capacity, capacity
    offset = @capacity - old_capacity

    if @buffer
      @buffer = root_buffer.realloc(@capacity)
      @buffer.move_to(@buffer + offset, old_capacity)
      @buffer.clear(offset)
    else
      @buffer = Pointer(T).malloc(@capacity)
    end

    shift_buffer_by(offset)
  end

  private def resize_if_cant_insert(insert_size)
    # Resize if we exceed the remaining capacity. This is less than `@capacity`
    # if the array has been shifted and `@offset_to_buffer` is nonzero
    new_size = @size + insert_size
    if new_size > remaining_capacity
      resize_to_capacity(calculate_new_capacity(new_size))
    end
  end

  # Returns a pointer to the buffer that was originally allocated/reallocated
  # for this array.
  private def root_buffer
    @buffer - @offset_to_buffer
  end

  # Moves `@buffer` by n while at the same time increments `@offset_to_buffer`
  private def shift_buffer_by(n)
    @offset_to_buffer += n
    @buffer += n
  end

  # Makes `@buffer` point at the original buffer that was allocated/reallocated.
  private def reset_buffer_to_root_buffer
    @buffer = root_buffer
    @offset_to_buffer = 0
  end

  private def to_unsafe_slice
    Slice.new(@buffer, size)
  end

  private def to_unsafe_slice(start : Int, count : Int)
    start, count = normalize_start_and_count(start, count)
    Slice.new(@buffer + start, count)
  end

  protected def to_lookup_hash(& : T -> U) forall U
    each_with_object(Hash(U, T).new) do |o, h|
      key = yield o
      unless h.has_key?(key)
        h[key] = o
      end
    end
  end

  def index(object, offset : Int = 0)
    # Optimize for the case of looking for a byte in a byte slice
    if T.is_a?(UInt8.class) &&
       (object.is_a?(UInt8) || (object.is_a?(Int) && 0 <= object < 256))
      return to_unsafe_slice.fast_index(object, offset)
    end

    super
  end

  private struct FlattenHelper(T)
    def self.flatten(ary)
      result = [] of T
      flatten ary, result
      result
    end

    def self.flatten(ary : Array, result)
      ary.each do |elem|
        flatten elem, result
      end
    end

    def self.flatten(iter : Iterator, result)
      iter.each do |elem|
        flatten elem, result
      end
    end

    def self.flatten(other : T, result)
      result << other
    end

    def self.element_type(ary)
      case ary
      when Array, Iterator
        ary.each { |elem| return element_type(elem) }
        ::raise ""
      else
        ary
      end
    end
  end
end
