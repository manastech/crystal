# The `Enumerable` mixin provides collection classes with several traversal, searching,
# filtering and querying methods.
#
# Including types must provide an `each` method, which yields successive members
# of the collection.
#
# For example:
#
# ```
# class Three
#   include Enumerable(Int32)
#
#   def each(&)
#     yield 1
#     yield 2
#     yield 3
#   end
# end
#
# three = Three.new
# three.to_a                # => [1, 2, 3]
# three.select &.odd?       # => [1, 3]
# three.all? { |x| x < 10 } # => true
# ```
#
# Note that most search and filter methods traverse an Enumerable eagerly,
# producing an `Array` as the result. For a lazy alternative refer to
# the `Iterator` and `Iterable` modules.
module Enumerable(T)
  class EmptyError < Exception
    def initialize(message = "Empty enumerable")
      super(message)
    end
  end

  class NotFoundError < Exception
    def initialize(message = "Element not found")
      super(message)
    end
  end

  # Must yield this collection's elements to the block.
  abstract def each(& : T ->)

  # Returns `true` if the passed block is truthy
  # for all elements of the collection.
  #
  # ```
  # ["ant", "bear", "cat"].all? { |word| word.size >= 3 } # => true
  # ["ant", "bear", "cat"].all? { |word| word.size >= 4 } # => false
  # ```
  def all?(& : T ->) : Bool
    each { |e| return false unless yield e }
    true
  end

  # Returns `true` if `pattern === element` for all elements in
  # this enumerable.
  #
  # ```
  # [2, 3, 4].all?(1..5)        # => true
  # [2, 3, 4].all?(Int32)       # => true
  # [2, "a", 3].all?(String)    # => false
  # %w[foo bar baz].all?(/o|a/) # => true
  # ```
  def all?(pattern) : Bool
    all? { |e| pattern === e }
  end

  # Returns `true` if all of the elements of the collection are truthy.
  #
  # ```
  # [nil, true, 99].all? # => false
  # [15].all?            # => true
  # ```
  def all? : Bool
    all? &.itself
  end

  # Returns `true` if the passed block is truthy
  # for at least one element of the collection.
  #
  # ```
  # ["ant", "bear", "cat"].any? { |word| word.size >= 4 } # => true
  # ["ant", "bear", "cat"].any? { |word| word.size > 4 }  # => false
  # ```
  def any?(& : T ->) : Bool
    each { |e| return true if yield e }
    false
  end

  # Returns `true` if `pattern === element` for at least one
  # element in this enumerable.
  #
  # ```
  # [2, 3, 4].any?(1..3)      # => true
  # [2, 3, 4].any?(5..10)     # => false
  # [2, "a", 3].any?(String)  # => true
  # %w[foo bar baz].any?(/a/) # => true
  # ```
  def any?(pattern) : Bool
    any? { |e| pattern === e }
  end

  # Returns `true` if at least one of the collection's members is truthy.
  #
  # ```
  # [nil, true, 99].any? # => true
  # [nil, false].any?    # => false
  # ([] of Int32).any?   # => false
  # ```
  #
  # * `#present?` does not consider truthiness of elements.
  # * `#any?(&)` and `#any(pattern)` allow custom conditions.
  #
  # NOTE: `#any?` usually has the same semantics as `#present?`. They only
  # differ if the element type can be falsey (i.e. `T <= Nil || T <= Pointer || T <= Bool`).
  # It's typically advised to prefer `#present?` unless these specific truthiness
  # semantics are required.
  def any? : Bool
    any? &.itself
  end

  # Enumerates over the items, chunking them together based on
  # the return value of the block.
  #
  # Consecutive elements which return the same block value are chunked together.
  #
  # For example, consecutive even numbers and odd numbers can be chunked as follows.
  #
  # ```
  # ary = [3, 1, 4, 1, 5, 9, 2, 6, 5, 3, 5].chunks { |n| n.even? }
  # ary # => [{false, [3, 1]}, {true, [4]}, {false, [1, 5, 9]}, {true, [2, 6]}, {false, [5, 3, 5]}]
  # ```
  #
  # The following key values have special meaning:
  #
  # * `Enumerable::Chunk::Drop` specifies that the elements should be dropped
  # * `Enumerable::Chunk::Alone` specifies that the element should be chunked by itself
  #
  # See also: `Iterator#chunk`.
  def chunks(&block : T -> U) forall U
    res = [] of Tuple(typeof(Chunk.key_type(self, block)), Array(T))
    chunks_internal(block) { |*kv| res << kv }
    res
  end

  module Chunk
    # Can be used in `Enumerable#chunks` and specifies that the elements should be dropped.
    record Drop

    # Can be used in `Enumerable#chunks` and specifies that the element should be chunked by itself.
    record Alone

    # :nodoc:
    struct Accumulator(T, U)
      @data : Array(T)
      @reuse : Bool

      def initialize(reuse = false)
        @key = uninitialized U
        @initialized = false

        if reuse
          if reuse.is_a?(Array)
            @data = reuse
          else
            @data = [] of T
          end
          @reuse = true
        else
          @data = [] of T
          @reuse = false
        end
      end

      def init(key, val)
        @key = key

        if @reuse
          @data.clear
          @data << val
        else
          @data = [val]
        end
        @initialized = true
      end

      def add(d)
        @data << d
      end

      def fetch
        if @initialized
          {@key, @data}.tap { @initialized = false }
        end
      end

      def same_as?(key) : Bool
        return false unless @initialized
        return false if key.is_a?(Alone.class) || key.is_a?(Drop.class)
        @key == key
      end

      def acc(key, val, &)
        if same_as?(key)
          add(val)
        else
          if tuple = fetch
            yield *tuple
          end

          init(key, val) unless key.is_a?(Drop.class)
        end
      end
    end

    def self.key_type(ary, block)
      ary.each do |item|
        key = block.call(item)
        ::raise "" if key.is_a?(Drop.class)
        return key
      end
      ::raise ""
    end
  end

  private def chunks_internal(original_block : T -> U, &) forall U
    acc = Chunk::Accumulator(T, typeof(Chunk.key_type(self, original_block))).new
    each do |val|
      key = original_block.call(val)
      acc.acc(key, val) do |*tuple|
        yield *tuple
      end
    end

    if tuple = acc.fetch
      yield *tuple
    end
  end

  # Returns an `Array` with the results of running the block against each element
  # of the collection, removing `nil` values.
  #
  # ```
  # ["Alice", "Bob"].map { |name| name.match(/^A./) }         # => [Regex::MatchData("Al"), nil]
  # ["Alice", "Bob"].compact_map { |name| name.match(/^A./) } # => [Regex::MatchData("Al")]
  # ```
  def compact_map(& : T -> _)
    ary = [] of typeof((yield Enumerable.element_type(self)).not_nil!)
    each do |e|
      v = yield e
      unless v.nil?
        ary << v
      end
    end
    ary
  end

  # Returns the number of elements in the collection for which
  # the passed block is truthy.
  #
  # ```
  # [1, 2, 3, 4].count { |i| i % 2 == 0 } # => 2
  # ```
  def count(& : T ->) : Int32
    count = 0
    each { |e| count += 1 if yield e }
    count
  end

  # Returns the number of times that the passed item is present in the collection.
  #
  # ```
  # [1, 2, 3, 4].count(3) # => 1
  # ```
  def count(item) : Int32
    count { |e| e == item }
  end

  # Calls the given block for each element in this enumerable forever.
  def cycle(& : T ->) : Nil
    loop { each { |x| yield x } }
  end

  # Calls the given block for each element in this enumerable *n* times.
  def cycle(n, & : T ->) : Nil
    n.times { each { |x| yield x } }
  end

  # Iterates over the collection yielding chunks of size *count*,
  # but advancing one by one.
  #
  # ```
  # [1, 2, 3, 4, 5].each_cons(2) do |cons|
  #   puts cons
  # end
  # ```
  #
  # Prints:
  #
  # ```text
  # [1, 2]
  # [2, 3]
  # [3, 4]
  # [4, 5]
  # ```
  #
  # By default, a new array is created and yielded for each consecutive slice of elements.
  # * If *reuse* is given, the array can be reused
  # * If *reuse* is `true`, the method will create a new array and reuse it.
  # * If *reuse*  is an instance of `Array`, `Deque` or a similar collection type (implementing `#<<`, `#shift` and `#size`) it will be used.
  # * If *reuse* is falsey, the array will not be reused.
  #
  # This can be used to prevent many memory allocations when each slice of
  # interest is to be used in a read-only fashion.
  #
  # Chunks of two items can be iterated using `#each_cons_pair`, an optimized
  # implementation for the special case of `count == 2` which avoids heap
  # allocations.
  def each_cons(count : Int, reuse = false, &)
    raise ArgumentError.new "Invalid cons size: #{count}" if count <= 0
    if reuse.nil? || reuse.is_a?(Bool)
      # we use an initial capacity of double the count, because a second
      # iteration would have reallocated the array to that capacity anyway
      each_cons_internal(count, reuse, Array(T).new(count * 2)) { |slice| yield slice }
    else
      each_cons_internal(count, true, reuse) { |slice| yield slice }
    end
  end

  private def each_cons_internal(count : Int, reuse, cons, &)
    each do |elem|
      cons << elem
      cons.shift if cons.size > count
      if cons.size == count
        if reuse
          yield cons
        else
          yield cons.dup
        end
      end
    end
    nil
  end

  # Iterates over the collection yielding pairs of adjacent items,
  # but advancing one by one.
  #
  # ```
  # [1, 2, 3, 4, 5].each_cons_pair do |a, b|
  #   puts "#{a}, #{b}"
  # end
  # ```
  #
  # Prints:
  #
  # ```text
  # 1, 2
  # 2, 3
  # 3, 4
  # 4, 5
  # ```
  #
  # Chunks of more than two items can be iterated using `#each_cons`.
  # This method is just an optimized implementation for the special case of
  # `count == 2` to avoid heap allocations.
  def each_cons_pair(& : (T, T) ->) : Nil
    last_elem = uninitialized T
    first_iteration = true
    each do |elem|
      if first_iteration
        first_iteration = false
      else
        yield last_elem, elem
      end
      last_elem = elem
    end
  end

  # Iterates over the collection in slices of size *count*,
  # and runs the block for each of those.
  #
  # ```
  # [1, 2, 3, 4, 5].each_slice(2) do |slice|
  #   puts slice
  # end
  # ```
  #
  # Prints:
  #
  # ```text
  # [1, 2]
  # [3, 4]
  # [5]
  # ```
  #
  # Note that the last one can be smaller.
  #
  # By default, a new array is created and yielded for each slice.
  # * If *reuse* is given, the array can be reused
  # * If *reuse* is an `Array`, this array will be reused
  # * If *reuse* is truthy, the method will create a new array and reuse it.
  #
  # This can be used to prevent many memory allocations when each slice of
  # interest is to be used in a read-only fashion.
  def each_slice(count : Int, reuse = false, &)
    each_slice_internal(count, Array(T), reuse) { |slice| yield slice }
  end

  private def each_slice_internal(count : Int, type, reuse, &)
    if reuse
      unless reuse.is_a?(Array)
        reuse = type.new(count)
      end
      reuse.clear
      slice = reuse
    else
      slice = type.new(count)
    end

    each do |elem|
      slice << elem
      if slice.size == count
        yield slice

        if reuse
          slice.clear
        else
          slice = type.new(count)
        end
      end
    end
    yield slice unless slice.empty?
    nil
  end

  # Iterates over the collection, yielding every *n*th element, starting with the first.
  #
  # ```
  # %w[Alice Bob Charlie David].each_step(2) do |user|
  #   puts "User: #{user}"
  # end
  # ```
  #
  # Prints:
  #
  # ```text
  # User: Alice
  # User: Charlie
  # ```
  #
  # Accepts an optional *offset* parameter
  #
  # ```
  # %w[Alice Bob Charlie David].each_step(2, offset: 1) do |user|
  #   puts "User: #{user}"
  # end
  # ```
  #
  # Which would print:
  #
  # ```text
  # User: Bob
  # User: David
  # ```
  def each_step(n : Int, *, offset : Int = 0, & : T ->) : Nil
    raise ArgumentError.new("Invalid n size: #{n}") if n <= 0
    raise ArgumentError.new("Invalid offset size: #{offset}") if offset < 0
    offset_mod = offset % n
    each_with_index do |elem, i|
      yield elem if i >= offset && i % n == offset_mod
    end
  end

  # Iterates over the collection, yielding both the elements and their index.
  #
  # ```
  # ["Alice", "Bob"].each_with_index do |user, i|
  #   puts "User ##{i}: #{user}"
  # end
  # ```
  #
  # Prints:
  #
  # ```text
  # User # 0: Alice
  # User # 1: Bob
  # ```
  #
  # Accepts an optional *offset* parameter, which tells it to start counting
  # from there. So, a more human friendly version of the previous snippet would be:
  #
  # ```
  # ["Alice", "Bob"].each_with_index(1) do |user, i|
  #   puts "User ##{i}: #{user}"
  # end
  # ```
  #
  # Which would print:
  #
  # ```text
  # User # 1: Alice
  # User # 2: Bob
  # ```
  def each_with_index(offset = 0, &)
    i = offset
    each do |elem|
      yield elem, i
      i += 1
    end
  end

  # Iterates over the collection, passing each element and the initial object *obj*.
  # Returns that object.
  #
  # ```
  # hash = ["Alice", "Bob"].each_with_object({} of String => Int32) do |user, sizes|
  #   sizes[user] = user.size
  # end
  # hash # => {"Alice" => 5, "Bob" => 3}
  # ```
  def each_with_object(obj : U, & : T, U ->) : U forall U
    each do |elem|
      yield elem, obj
    end
    obj
  end

  # Returns the first element in the collection for which the passed block is truthy.
  #
  # Accepts an optional parameter *if_none*, to set what gets returned if
  # no element is found (defaults to `nil`).
  #
  # ```
  # [1, 2, 3, 4].find { |i| i > 2 }     # => 3
  # [1, 2, 3, 4].find { |i| i > 8 }     # => nil
  # [1, 2, 3, 4].find(-1) { |i| i > 8 } # => -1
  # ```
  def find(if_none = nil, & : T ->)
    each do |elem|
      return elem if yield elem
    end
    if_none
  end

  # Returns the first element in the collection for which the passed block is truthy.
  # Raises `Enumerable::NotFoundError` if there is no element for which the block is truthy.
  #
  # ```
  # [1, 2, 3, 4].find! { |i| i > 2 } # => 3
  # [1, 2, 3, 4].find! { |i| i > 8 } # => raises Enumerable::NotFoundError
  # ```
  def find!(& : T ->) : T
    each do |elem|
      return elem if yield elem
    end
    raise Enumerable::NotFoundError.new
  end

  # Yields each value until the first truthy block result and returns that result.
  #
  # Accepts an optional parameter `if_none`, to set what gets returned if
  # no element is found (defaults to `nil`).
  #
  # ```
  # [1, 2, 3, 4].find_value { |i| i > 2 }     # => true
  # [1, 2, 3, 4].find_value { |i| i > 8 }     # => nil
  # [1, 2, 3, 4].find_value(-1) { |i| i > 8 } # => -1
  # ```
  def find_value(if_none = nil, & : T ->)
    each do |i|
      if result = yield i
        return result
      end
    end
    if_none
  end

  # Returns the first element in the collection,
  # If the collection is empty, calls the block and returns its value.
  #
  # ```
  # ([1, 2, 3]).first { 4 }   # => 1
  # ([] of Int32).first { 4 } # => 4
  # ```
  def first(& : ->)
    each { |e| return e }
    yield
  end

  # Returns the first element in the collection. Raises `Enumerable::EmptyError`
  # if the collection is empty.
  #
  # ```
  # ([1, 2, 3]).first   # => 1
  # ([] of Int32).first # raises Enumerable::EmptyError
  # ```
  def first : T
    first { raise Enumerable::EmptyError.new }
  end

  # Returns the first element in the collection.
  # When the collection is empty, returns `nil`.
  #
  # ```
  # ([1, 2, 3]).first?   # => 1
  # ([] of Int32).first? # => nil
  # ```
  def first? : T?
    first { nil }
  end

  # Returns a new array with the concatenated results of running the block
  # once for every element in the collection.
  # Only `Array` and `Iterator` results are concatenated; every other value is
  # directly appended to the new array.
  #
  # ```
  # array = ["Alice", "Bob"].flat_map do |user|
  #   user.chars
  # end
  # array # => ['A', 'l', 'i', 'c', 'e', 'B', 'o', 'b']
  # ```
  def flat_map(& : T -> _)
    ary = [] of typeof(flat_map_type(yield Enumerable.element_type(self)))
    each do |e|
      case v = yield e
      when Array, Iterator
        ary.concat(v)
      else
        ary.push(v)
      end
    end
    ary
  end

  private def flat_map_type(elem)
    case elem
    when Array, Iterator
      elem.first
    else
      elem
    end
  end

  # Returns a `Hash` whose keys are each different value that the passed block
  # returned when run for each element in the collection, and which values are
  # an `Array` of the elements for which the block returned that value.
  #
  # ```
  # ["Alice", "Bob", "Ary"].group_by { |name| name.size } # => {5 => ["Alice"], 3 => ["Bob", "Ary"]}
  # ```
  def group_by(& : T -> U) forall U
    h = Hash(U, Array(T)).new
    each do |e|
      v = yield e
      h.put_if_absent(v) { Array(T).new } << e
    end
    h
  end

  # Returns an `Array` with chunks in the given size, eventually filled up
  # with given value or `nil`.
  #
  # ```
  # [1, 2, 3].in_groups_of(2, 0) # => [[1, 2], [3, 0]]
  # [1, 2, 3].in_groups_of(2)    # => [[1, 2], [3, nil]]
  # ```
  def in_groups_of(size : Int, filled_up_with : U = nil) forall U
    raise ArgumentError.new("Size must be positive") if size <= 0

    ary = Array(Array(T | U)).new
    in_groups_of(size, filled_up_with) do |group|
      ary << group
    end
    ary
  end

  # Yields a block with the chunks in the given size.
  #
  # ```
  # [1, 2, 4].in_groups_of(2, 0) { |e| p e.sum }
  # # => 3
  # # => 4
  # ```
  #
  # By default, a new array is created and yielded for each group.
  # * If *reuse* is given, the array can be reused
  # * If *reuse* is an `Array`, this array will be reused
  # * If *reuse* is truthy, the method will create a new array and reuse it.
  #
  # This can be used to prevent many memory allocations when each slice of
  # interest is to be used in a read-only fashion.
  def in_groups_of(size : Int, filled_up_with : U = nil, reuse = false, &) forall U
    raise ArgumentError.new("Size must be positive") if size <= 0

    each_slice_internal(size, Array(T | U), reuse) do |slice|
      (size - slice.size).times { slice << filled_up_with }
      yield slice
    end
  end

  # Returns an `Array` with chunks in the given size.
  # Last chunk can be smaller depending on the number of remaining items.
  #
  # ```
  # [1, 2, 3].in_slices_of(2) # => [[1, 2], [3]]
  # ```
  def in_slices_of(size : Int) : Array(Array(T))
    raise ArgumentError.new("Size must be positive") if size <= 0

    ary = Array(Array(T)).new
    each_slice_internal(size, Array(T), false) do |slice|
      ary << slice
    end
    ary
  end

  # Returns `true` if the collection contains *obj*, `false` otherwise.
  #
  # ```
  # [1, 2, 3].includes?(2) # => true
  # [1, 2, 3].includes?(5) # => false
  # ```
  def includes?(obj) : Bool
    any? { |e| e == obj }
  end

  # Returns the index of the first element for which the passed block is truthy.
  #
  # ```
  # ["Alice", "Bob"].index { |name| name.size < 4 } # => 1 (Bob's index)
  # ```
  #
  # Returns `nil` if the block is not truthy for any element.
  def index(& : T ->) : Int32?
    each_with_index do |e, i|
      return i if yield e
    end
    nil
  end

  # Returns the first index of *obj* in the collection.
  #
  # ```
  # ["Alice", "Bob"].index("Alice") # => 0
  # ```
  #
  # Returns `nil` if *obj* is not in the collection.
  def index(obj) : Int32?
    index { |e| e == obj }
  end

  # Returns the index of the first element for which the passed block is truthy.
  #
  # ```
  # ["Alice", "Bob"].index! { |name| name.size < 4 } # => 1 (Bob's index)
  # ```
  #
  # Raises `Enumerable::NotFoundError` if there is no element for which the block is truthy.
  def index!(& : T ->) : Int32
    index { |e| yield e } || raise Enumerable::NotFoundError.new
  end

  # Returns the first index of *obj* in the collection.
  #
  # ```
  # ["Alice", "Bob"].index!("Alice") # => 0
  # ```
  #
  # Raises `Enumerable::NotFoundError` if *obj* is not in the collection.
  def index!(obj) : Int32
    index! { |e| e == obj }
  end

  # Converts an `Enumerable` to a `Hash` by using the value returned by the block
  # as the hash key.
  # Be aware, if two elements return the same value as a key one will override
  # the other. If you want to keep all values, then you should probably use
  # `group_by` instead.
  #
  # ```
  # ["Anna", "Ary", "Alice"].index_by { |e| e.size }
  # # => {4 => "Anna", 3 => "Ary", 5 => "Alice"}
  # ["Anna", "Ary", "Alice", "Bob"].index_by { |e| e.size }
  # # => {4 => "Anna", 3 => "Bob", 5 => "Alice"}
  # ```
  def index_by(& : T -> U) : Hash(U, T) forall U
    hash = {} of U => T
    each do |elem|
      hash[yield elem] = elem
    end
    hash
  end

  # Combines all elements in the collection by applying a binary operation, specified by a block, so as
  # to reduce them to a single value.
  #
  # For each element in the collection the block is passed an accumulator value (*memo*) and the element. The
  # result becomes the new value for *memo*. At the end of the iteration, the final value of *memo* is
  # the return value for the method. The initial value for the accumulator is the first element in the collection.
  # If the collection has only one element, that element is returned.
  #
  # Raises `Enumerable::EmptyError` if the collection is empty.
  #
  # ```
  # [1, 2, 3, 4, 5].reduce { |acc, i| acc + i } # => 15
  # [1].reduce { |acc, i| acc + i }             # => 1
  # ([] of Int32).reduce { |acc, i| acc + i }   # raises Enumerable::EmptyError
  # ```
  #
  # The block is not required to return a `T`, in which case the accumulator's
  # type includes whatever the block returns.
  #
  # ```
  # # `acc` is an `Int32 | String`
  # [1, 2, 3, 4, 5].reduce { |acc, i| "#{acc}-#{i}" } # => "1-2-3-4-5"
  # [1].reduce { |acc, i| "#{acc}-#{i}" }             # => 1
  # ```
  def reduce(&)
    memo = uninitialized typeof(reduce(Enumerable.element_type(self)) { |acc, i| yield acc, i })
    found = false

    each do |elem|
      memo = found ? (yield memo, elem) : elem
      found = true
    end

    found ? memo : raise Enumerable::EmptyError.new
  end

  # Just like the other variant, but you can set the initial value of the accumulator.
  #
  # ```
  # [1, 2, 3, 4, 5].reduce(10) { |acc, i| acc + i }             # => 25
  # [1, 2, 3].reduce([] of Int32) { |memo, i| memo.unshift(i) } # => [3, 2, 1]
  # ```
  def reduce(memo, &)
    each do |elem|
      memo = yield memo, elem
    end
    memo
  end

  # Similar to `reduce`, but instead of raising when the input is empty,
  # return `nil`
  #
  # ```
  # ([] of Int32).reduce? { |acc, i| acc + i } # => nil
  # ```
  def reduce?(&)
    memo = uninitialized typeof(reduce(Enumerable.element_type(self)) { |acc, i| yield acc, i })
    found = false

    each do |elem|
      memo = found ? (yield memo, elem) : elem
      found = true
    end

    found ? memo : nil
  end

  # Returns an array of the prefix sums of the elements in this collection. The
  # first element of the returned array is same as the first element of `self`.
  #
  # Expects all element types to respond to the `#+` method.
  #
  # ```
  # [1, 2, 3, 4, 5, 6].accumulate # => [1, 3, 6, 10, 15, 21]
  # ```
  def accumulate : Array(T)
    accumulate { |x, y| x + y }
  end

  # Returns an array containing *initial* and its prefix sums with the elements
  # in this collection.
  #
  # Expects `U` to respond to the `#+` method.
  #
  # ```
  # [1, 2, 3, 4, 5].accumulate(6) # => [6, 7, 9, 12, 16, 21]
  # ```
  def accumulate(initial : U) : Array(U) forall U
    accumulate(initial) { |x, y| x + y }
  end

  # Returns an array containing the successive values of applying a binary
  # operation, specified by the given *block*, to this collection's elements.
  #
  # For each element in the collection the block is passed an accumulator value
  # and the element. The result becomes the new value for the accumulator and is
  # also appended to the returned array. The initial value for the accumulator
  # is the first element in the collection.
  #
  # ```
  # [2, 3, 4, 5].accumulate { |x, y| x * y } # => [2, 6, 24, 120]
  # ```
  def accumulate(&block : T, T -> T) : Array(T)
    values = [] of T
    memo = uninitialized T

    each do |elem|
      memo = values.empty? ? elem : (yield memo, elem)
      values << memo
    end

    values
  end

  # Returns an array containing *initial* and the successive values of applying
  # a binary operation, specified by the given *block*, to this collection's
  # elements.
  #
  # Similar to `#accumulate(&block : T, T -> T)`, except the initial value is
  # provided by an argument and needs not have the same type as the elements in
  # the collection. This initial value is always present in the returned array.
  #
  # ```
  # [1, 3, 5, 7].accumulate(9) { |x, y| x * y } # => [9, 9, 27, 135, 945]
  # ```
  def accumulate(initial : U, &block : U, T -> U) : Array(U) forall U
    values = [initial]

    each do |elem|
      initial = yield initial, elem
      values << initial
    end

    values
  end

  # Returns a `String` created by concatenating the elements in the collection,
  # separated by *separator* (defaults to none).
  #
  # ```
  # [1, 2, 3, 4, 5].join(", ") # => "1, 2, 3, 4, 5"
  # ```
  def join(separator = "") : String
    String.build do |io|
      join io, separator
    end
  end

  # Returns a `String` created by concatenating the results of passing the elements
  # in the collection to the passed block, separated by *separator* (defaults to none).
  #
  # ```
  # [1, 2, 3, 4, 5].join(", ") { |i| -i } # => "-1, -2, -3, -4, -5"
  # ```
  def join(separator = "", & : T ->)
    String.build do |io|
      join(io, separator) do |elem|
        io << yield elem
      end
    end
  end

  # Prints to *io* all the elements in the collection, separated by *separator*.
  #
  # ```
  # [1, 2, 3, 4, 5].join(STDOUT, ", ")
  # ```
  #
  # Prints:
  #
  # ```text
  # 1, 2, 3, 4, 5
  # ```
  def join(io : IO, separator = "") : Nil
    join(io, separator) do |elem|
      elem.to_s(io)
    end
  end

  # Prints to *io* all the elements in the collection, separated by *separator*.
  #
  # ```
  # [1, 2, 3, 4, 5].join(STDOUT, ", ")
  # ```
  #
  # Prints:
  #
  # ```text
  # 1, 2, 3, 4, 5
  # ```
  @[Deprecated(%(Use `#join(io : IO, separator = "") instead`))]
  def join(separator, io : IO) : Nil
    join(io, separator)
  end

  # Prints to *io* the concatenation of the elements, with the possibility of
  # controlling how the printing is done via a block.
  #
  # ```
  # [1, 2, 3, 4, 5].join(STDOUT, ", ") { |i, io| io << "(#{i})" }
  # ```
  #
  # Prints:
  #
  # ```text
  # (1), (2), (3), (4), (5)
  # ```
  def join(io : IO, separator = "", & : T, IO ->)
    each_with_index do |elem, i|
      io << separator if i > 0
      yield elem, io
    end
  end

  # Prints to *io* the concatenation of the elements, with the possibility of
  # controlling how the printing is done via a block.
  #
  # ```
  # [1, 2, 3, 4, 5].join(STDOUT, ", ") { |i, io| io << "(#{i})" }
  # ```
  #
  # Prints:
  #
  # ```text
  # (1), (2), (3), (4), (5)
  # ```
  @[Deprecated(%(Use `#join(io : IO, separator = "", & : T, IO ->) instead`))]
  def join(separator, io : IO, &)
    join(io, separator) do |elem, io|
      yield elem, io
    end
  end

  # Returns an `Array` with the results of running the block against each element of the collection.
  #
  # ```
  # [1, 2, 3].map { |i| i * 10 } # => [10, 20, 30]
  # ```
  def map(& : T -> U) : Array(U) forall U
    map_with_index do |e|
      yield e
    end
  end

  # Like `map`, but the block gets passed both the element and its index.
  #
  # ```
  # ["Alice", "Bob"].map_with_index { |name, i| "User ##{i}: #{name}" }
  # # => ["User #0: Alice", "User #1: Bob"]
  # ```
  #
  # Accepts an optional *offset* parameter, which tells it to start counting
  # from there.
  def map_with_index(offset = 0, & : T, Int32 -> U) : Array(U) forall U
    ary = [] of U
    each_with_index(offset) { |e, i| ary << yield e, i }
    ary
  end

  private def quickselect_internal(data : Array(T), left : Int, right : Int, k : Int) : T
    loop do
      return data[left] if left == right
      pivot_index = left + (right - left)//2
      pivot_index = quickselect_partition_internal(data, left, right, pivot_index)
      if k == pivot_index
        return data[k]
      elsif k < pivot_index
        right = pivot_index - 1
      else
        left = pivot_index + 1
      end
    end
  end

  private def quickselect_partition_internal(data : Array(T), left : Int, right : Int, pivot_index : Int) : Int
    pivot_value = data[pivot_index]
    data.swap(pivot_index, right)
    store_index = left
    (left...right).each do |i|
      if compare_or_raise(data[i], pivot_value) < 0
        data.swap(store_index, i)
        store_index += 1
      end
    end
    data.swap(right, store_index)
    store_index
  end

  # Returns the element with the maximum value in the collection.
  #
  # It compares using `>` so it will work for any type that supports that method.
  #
  # ```
  # [1, 2, 3].max        # => 3
  # ["Alice", "Bob"].max # => "Bob"
  # ```
  #
  # Raises `Enumerable::EmptyError` if the collection is empty.
  def max : T
    max_by &.itself
  end

  # Like `max` but returns `nil` if the collection is empty.
  def max? : T?
    max_by? &.itself
  end

  # Returns an array of the maximum *count* elements, sorted descending.
  #
  # It compares using `<=>` so it will work for any type that supports that method.
  #
  # ```
  # [7, 5, 2, 4, 9].max(3)                 # => [9, 7, 5]
  # %w[Eve Alice Bob Mallory Carol].max(2) # => ["Mallory", "Eve"]
  # ```
  #
  # Returns all elements sorted descending if *count* is greater than the number
  # of elements in the source.
  #
  # Raises `Enumerable::ArgumentError` if *count* is negative or if any elements
  # are not comparable.
  def max(count : Int) : Array(T)
    raise ArgumentError.new("Count must be positive") if count < 0
    data = self.is_a?(Array) ? self.dup : self.to_a
    n = data.size
    count = n if count > n
    (0...count).map do |i|
      quickselect_internal(data, 0, n - 1, n - 1 - i)
    end
  end

  # Returns the element for which the passed block returns with the maximum value.
  #
  # It compares using `>` so the block must return a type that supports that method
  #
  # ```
  # ["Alice", "Bob"].max_by { |name| name.size } # => "Alice"
  # ```
  #
  # Raises `Enumerable::EmptyError` if the collection is empty.
  def max_by(& : T -> U) : T forall U
    found, value = max_by_internal { |value| yield value }
    raise Enumerable::EmptyError.new unless found
    value
  end

  # Like `max_by` but returns `nil` if the collection is empty.
  def max_by?(& : T -> U) : T? forall U
    found, value = max_by_internal { |value| yield value }
    found ? value : nil
  end

  private def max_by_internal(& : T -> U) forall U
    max = uninitialized U
    obj = uninitialized T
    found = false

    each_with_index do |elem, i|
      value = yield elem
      if i == 0 || compare_or_raise(value, max) > 0
        max = value
        obj = elem
      end
      found = true
    end

    {found, obj}
  end

  # Like `max_by` but instead of the element, returns the value returned by the block.
  #
  # ```
  # ["Alice", "Bob"].max_of { |name| name.size } # => 5 (Alice's size)
  # ```
  def max_of(& : T -> U) : U forall U
    found, value = max_of_internal { |value| yield value }
    raise Enumerable::EmptyError.new unless found
    value
  end

  # Like `max_of` but returns `nil` if the collection is empty.
  def max_of?(& : T -> U) : U? forall U
    found, value = max_of_internal { |value| yield value }
    found ? value : nil
  end

  private def max_of_internal(& : T -> U) forall U
    max = uninitialized U
    found = false

    each_with_index do |elem, i|
      value = yield elem
      if i == 0 || compare_or_raise(value, max) > 0
        max = value
      end
      found = true
    end

    {found, max}
  end

  # Returns the element with the minimum value in the collection.
  #
  # It compares using `<` so it will work for any type that supports that method.
  #
  # ```
  # [1, 2, 3].min        # => 1
  # ["Alice", "Bob"].min # => "Alice"
  # ```
  #
  # Raises `Enumerable::EmptyError` if the collection is empty.
  def min : T
    min_by &.itself
  end

  # Like `min` but returns `nil` if the collection is empty.
  def min? : T?
    min_by? &.itself
  end

  # Returns an array of the minimum *count* elements, sorted ascending.
  #
  # It compares using `<=>` so it will work for any type that supports that method.
  #
  # ```
  # [7, 5, 2, 4, 9].min(3)                 # => [2, 4, 5]
  # %w[Eve Alice Bob Mallory Carol].min(2) # => ["Alice", "Bob"]
  # ```
  #
  # Returns all elements sorted ascending if *count* is greater than the number
  # of elements in the source.
  #
  # Raises `Enumerable::ArgumentError` if *count* is negative or if any elements
  # are not comparable.
  def min(count : Int) : Array(T)
    raise ArgumentError.new("Count must be positive") if count < 0
    data = self.is_a?(Array) ? self.dup : self.to_a
    n = data.size
    count = n if count > n
    (0...count).map do |i|
      quickselect_internal(data, 0, n - 1, i)
    end
  end

  # Returns the element for which the passed block returns with the minimum value.
  #
  # It compares using `<` so the block must return a type that supports that method
  #
  # ```
  # ["Alice", "Bob"].min_by { |name| name.size } # => "Bob"
  # ```
  #
  # Raises `Enumerable::EmptyError` if the collection is empty.
  def min_by(& : T -> U) : T forall U
    found, value = min_by_internal { |value| yield value }
    raise Enumerable::EmptyError.new unless found
    value
  end

  # Like `min_by` but returns `nil` if the collection is empty.
  def min_by?(& : T -> U) : T? forall U
    found, value = min_by_internal { |value| yield value }
    found ? value : nil
  end

  private def min_by_internal(& : T -> U) forall U
    min = uninitialized U
    obj = uninitialized T
    found = false

    each_with_index do |elem, i|
      value = yield elem
      if i == 0 || compare_or_raise(value, min) < 0
        min = value
        obj = elem
      end
      found = true
    end

    {found, obj}
  end

  # Like `min_by` but instead of the element, returns the value returned by the block.
  #
  # ```
  # ["Alice", "Bob"].min_of { |name| name.size } # => 3 (Bob's size)
  # ```
  def min_of(& : T -> U) : U forall U
    found, value = min_of_internal { |value| yield value }
    raise Enumerable::EmptyError.new unless found
    value
  end

  # Like `min_of` but returns `nil` if the collection is empty.
  def min_of?(& : T -> U) : U? forall U
    found, value = min_of_internal { |value| yield value }
    found ? value : nil
  end

  private def min_of_internal(& : T -> U) forall U
    min = uninitialized U
    found = false

    each_with_index do |elem, i|
      value = yield elem
      if i == 0 || compare_or_raise(value, min) < 0
        min = value
      end
      found = true
    end

    {found, min}
  end

  # Returns a `Tuple` with both the minimum and maximum value.
  #
  # ```
  # [1, 2, 3].minmax # => {1, 3}
  # ```
  #
  # Raises `Enumerable::EmptyError` if the collection is empty.
  def minmax : {T, T}
    minmax_by &.itself
  end

  # Like `minmax` but returns `{nil, nil}` if the collection is empty.
  def minmax? : {T?, T?}
    minmax_by? &.itself
  end

  # Returns a `Tuple` with both the minimum and maximum values according to the passed block.
  #
  # ```
  # ["Alice", "Bob", "Carl"].minmax_by { |name| name.size } # => {"Bob", "Alice"}
  # ```
  #
  # Raises `Enumerable::EmptyError` if the collection is empty.
  def minmax_by(& : T -> U) : {T, T} forall U
    found, value = minmax_by_internal { |value| yield value }
    raise Enumerable::EmptyError.new unless found
    value
  end

  # Like `minmax_by` but returns `{nil, nil}` if the collection is empty.
  def minmax_by?(& : T -> U) : {T, T} | {Nil, Nil} forall U
    found, value = minmax_by_internal { |value| yield value }
    found ? value : {nil, nil}
  end

  private def minmax_by_internal(& : T -> U) forall U
    min = uninitialized U
    max = uninitialized U
    objmin = uninitialized T
    objmax = uninitialized T
    found = false

    each_with_index do |elem, i|
      value = yield elem
      if i == 0 || compare_or_raise(value, min) < 0
        min = value
        objmin = elem
      end
      if i == 0 || compare_or_raise(value, max) > 0
        max = value
        objmax = elem
      end
      found = true
    end

    {found, {objmin, objmax}}
  end

  # Returns a `Tuple` with both the minimum and maximum value
  # the block returns when passed the elements in the collection.
  #
  # ```
  # ["Alice", "Bob", "Carl"].minmax_of { |name| name.size } # => {3, 5}
  # ```
  #
  # Raises `Enumerable::EmptyError` if the collection is empty.
  def minmax_of(& : T -> U) : {U, U} forall U
    found, value = minmax_of_internal { |value| yield value }
    raise Enumerable::EmptyError.new unless found
    value
  end

  # Like `minmax_of` but returns `{nil, nil}` if the collection is empty.
  def minmax_of?(& : T -> U) : {U, U} | {Nil, Nil} forall U
    found, value = minmax_of_internal { |value| yield value }
    found ? value : {nil, nil}
  end

  private def minmax_of_internal(& : T -> U) forall U
    min = uninitialized U
    max = uninitialized U
    found = false

    each_with_index do |elem, i|
      value = yield elem
      if i == 0 || compare_or_raise(value, min) < 0
        min = value
      end
      if i == 0 || compare_or_raise(value, max) > 0
        max = value
      end
      found = true
    end

    {found, {min, max}}
  end

  private def compare_or_raise(value, memo)
    value <=> memo || raise ArgumentError.new("Comparison of #{value} and #{memo} failed")
  end

  # Returns `true` if the passed block is truthy
  # for none of the elements of the collection.
  #
  # ```
  # [1, 2, 3].none? { |i| i > 5 } # => true
  # ```
  #
  # It's the opposite of `all?`.
  def none?(& : T ->) : Bool
    each { |e| return false if yield(e) }
    true
  end

  # Returns `true` if `pattern === element` for no element in
  # this enumerable.
  #
  # ```
  # [2, 3, 4].none?(5..7)      # => true
  # [2, "a", 3].none?(String)  # => false
  # %w[foo bar baz].none?(/e/) # => true
  # ```
  def none?(pattern) : Bool
    none? { |e| pattern === e }
  end

  # Returns `true` if all of the elements of the collection are falsey.
  #
  # ```
  # [nil, false].none?       # => true
  # [nil, false, true].none? # => false
  # ```
  #
  # It's the opposite of `all?`.
  def none? : Bool
    none? &.itself
  end

  # Returns `true` if the passed block is truthy
  # for exactly one of the elements of the collection.
  #
  # ```
  # [1, 2, 3].one? { |i| i > 2 } # => true
  # [1, 2, 3].one? { |i| i > 1 } # => false
  # ```
  def one?(& : T ->) : Bool
    c = 0
    each do |e|
      c += 1 if yield(e)
      return false if c > 1
    end
    c == 1
  end

  # Returns `true` if `pattern === element` for just one element
  # in this enumerable.
  #
  # ```
  # [1, 10, 100].one?(7..14)   # => true
  # [2, "a", 3].one?(Int32)    # => false
  # %w[foo bar baz].one?(/oo/) # => true
  # ```
  def one?(pattern) : Bool
    one? { |e| pattern === e }
  end

  # Returns `true` if only one element in this enumerable
  # is truthy.
  #
  # ```
  # [1, false, false].one? # => true
  # [1, false, 3].one?     # => false
  # [1].one?               # => true
  # [false].one?           # => false
  # ```
  def one? : Bool
    one? &.itself
  end

  # Returns a `Tuple` with two arrays. The first one contains the elements
  # in the collection for which the passed block is truthy,
  # and the second one those for which the block is falsey.
  #
  # ```
  # [1, 2, 3, 4, 5, 6].partition { |i| i % 2 == 0 } # => {[2, 4, 6], [1, 3, 5]}
  # ```
  def partition(& : T ->) : {Array(T), Array(T)}
    a, b = [] of T, [] of T
    each do |e|
      value = yield(e)
      value ? a.push(e) : b.push(e)
    end
    {a, b}
  end

  # Returns a `Tuple` with two arrays. The first one contains the elements
  # in the collection that are of the given *type*,
  # and the second one that are **not** of the given *type*.
  #
  # ```
  # ints, others = [1, true, nil, 3, false, "string", 'c'].partition(Int32)
  # ints           # => [1, 3]
  # others         # => [true, nil, false, "string", 'c']
  # typeof(ints)   # => Array(Int32)
  # typeof(others) # => Array(String | Char | Nil)
  # ```
  def partition(type : U.class) forall U
    a = [] of U
    b = [] of typeof(begin
      e = Enumerable.element_type(self)
      e.is_a?(U) ? raise("") : e
    end)
    each do |e|
      e.is_a?(U) ? a.push(e) : b.push(e)
    end
    {a, b}
  end

  # Returns an `Array` with all the elements in the collection for which
  # the passed block is falsey.
  #
  # ```
  # [1, 2, 3, 4, 5, 6].reject { |i| i % 2 == 0 } # => [1, 3, 5]
  # ```
  def reject(& : T ->)
    ary = [] of T
    each { |e| ary << e unless yield e }
    ary
  end

  # Returns an `Array` with all the elements in the collection
  # that are **not** of the given *type*.
  #
  # ```
  # ints = [1, true, 3, false].reject(Bool)
  # ints         # => [1, 3]
  # typeof(ints) # => Array(Int32)
  # ```
  def reject(type : U.class) forall U
    ary = [] of typeof(begin
      e = Enumerable.element_type(self)
      e.is_a?(U) ? raise("") : e
    end)
    each { |e| ary << e unless e.is_a?(U) }
    ary
  end

  # Returns an `Array` with all the elements in the collection for which
  # `pattern === element` is false.
  #
  # ```
  # [1, 3, 2, 5, 4, 6].reject(3..5) # => [1, 2, 6]
  # ```
  def reject(pattern) : Array(T)
    reject { |e| pattern === e }
  end

  # Returns an `Array` of *n* random elements from `self`, using the given
  # *random* number generator. All elements have equal probability of being
  # drawn. Sampling is done without replacement; if *n* is larger than the size
  # of this collection, the returned `Array` has the same size as `self`.
  #
  # Raises `ArgumentError` if *n* is negative.
  #
  # ```
  # [1, 2, 3, 4, 5].sample(2)                # => [3, 5]
  # {1, 2, 3, 4, 5}.sample(2)                # => [3, 4]
  # {1, 2, 3, 4, 5}.sample(2, Random.new(1)) # => [1, 5]
  # ```
  def sample(n : Int, random : Random = Random::DEFAULT) : Array(T)
    raise ArgumentError.new("Can't sample negative number of elements") if n < 0

    # Unweighted reservoir sampling:
    # https://en.wikipedia.org/wiki/Reservoir_sampling#Simple_algorithm
    # "Algorithm L" does not provide any performance improvements on Enumerable,
    # because it is not possible to discard multiple elements at once

    ary = Array(T).new(n)
    return ary if n == 0

    each_with_index do |elem, i|
      if i < n
        ary << elem
      else
        j = random.rand(i + 1)
        if j < n
          ary.to_unsafe[j] = elem
        end
      end
    end

    ary.shuffle!(random)
  end

  # Returns a random element from `self`, using the given *random* number
  # generator. All elements have equal probability of being drawn.
  #
  # Raises `IndexError` if `self` is empty.
  #
  # ```
  # a = [1, 2, 3]
  # a.sample                # => 2
  # a.sample                # => 1
  # a.sample(Random.new(1)) # => 3
  # ```
  def sample(random : Random = Random::DEFAULT) : T
    value = uninitialized T
    found = false

    each_with_index do |elem, i|
      if !found
        value = elem
        found = true
      elsif random.rand(i + 1) == 0
        value = elem
      end
    end

    found ? value : raise IndexError.new("Can't sample empty collection")
  end

  # Returns an `Array` with all the elements in the collection for which
  # the passed block is truthy.
  #
  # ```
  # [1, 2, 3, 4, 5, 6].select { |i| i % 2 == 0 } # => [2, 4, 6]
  # ```
  def select(& : T ->)
    ary = [] of T
    each { |e| ary << e if yield e }
    ary
  end

  # Returns an `Array` with all the elements in the collection
  # that are of the given *type*.
  #
  # ```
  # ints = [1, true, nil, 3, false].select(Int32)
  # ints         # => [1, 3]
  # typeof(ints) # => Array(Int32)
  # ```
  def select(type : U.class) : Array(U) forall U
    ary = [] of U
    each { |e| ary << e if e.is_a?(U) }
    ary
  end

  # Returns an `Array` with all the elements in the collection for which
  # `pattern === element`.
  #
  # ```
  # [1, 3, 2, 5, 4, 6].select(3..5) # => [3, 5, 4]
  # ["Alice", "Bob"].select(/^A/)   # => ["Alice"]
  # ```
  def select(pattern) : Array(T)
    self.select { |elem| pattern === elem }
  end

  # Returns the number of elements in the collection.
  #
  # ```
  # [1, 2, 3, 4].size # => 4
  # ```
  def size : Int32
    count { true }
  end

  # Returns `true` if `self` does not contain any element.
  #
  # ```
  # ([] of Int32).empty? # => true
  # ([1]).empty?         # => false
  # [nil, false].empty?  # => false
  # ```
  #
  # * `#present?` returns the inverse.
  def empty? : Bool
    each { return false }
    true
  end

  # Returns `true` if `self` contains at least one element.
  #
  # ```
  # ([] of Int32).present? # => false
  # ([1]).present?         # => true
  # [nil, false].present?  # => true
  # ```
  #
  # * `#empty?` returns the inverse.
  # * `#any?` considers only truthy elements.
  # * `#any?(&)` and `#any(pattern)` allow custom conditions.
  def present? : Bool
    !empty?
  end

  # Returns an `Array` with the first *count* elements removed
  # from the original collection.
  #
  # If *count* is bigger than the number of elements in the collection, returns an empty array.
  #
  # ```
  # [1, 2, 3, 4, 5, 6].skip(3) # => [4, 5, 6]
  # ```
  def skip(count : Int)
    raise ArgumentError.new("Attempt to skip negative size") if count < 0

    array = Array(T).new
    each_with_index do |e, i|
      array << e if i >= count
    end
    array
  end

  # Skips elements up to, but not including, the first element for which
  # the block is falsey, and returns an `Array`
  # containing the remaining elements.
  #
  # ```
  # [1, 2, 3, 4, 5, 0].skip_while { |i| i < 3 } # => [3, 4, 5, 0]
  # ```
  def skip_while(& : T ->) : Array(T)
    result = Array(T).new
    block_returned_false = false
    each do |x|
      block_returned_false = true unless block_returned_false || yield x
      result << x if block_returned_false
    end
    result
  end

  # Adds all the elements in the collection together.
  #
  # Expects all element types to respond to `#+` method.
  #
  # ```
  # [1, 2, 3, 4, 5, 6].sum # => 21
  # ```
  #
  # This method calls `.additive_identity` on the yielded type to determine the
  # type of the sum value.
  #
  # If the collection is empty, returns `additive_identity`.
  #
  # ```
  # ([] of Int32).sum # => 0
  # ```
  def sum
    {% if T == String %}
      # optimize for string
      join
    {% elsif T < Array %}
      # optimize for array
      flat_map &.itself
    {% elsif T < Slice && @type < Indexable %}
      # optimize for slice
      Slice.join(self)
    {% else %}
      sum additive_identity(Reflect(T))
    {% end %}
  end

  private def additive_identity(reflect)
    type = reflect.type
    if type.responds_to? :additive_identity
      type.additive_identity
    else
      type.zero
    end
  end

  # Adds *initial* and all the elements in the collection together.
  # The type of *initial* will be the type of the sum, so use this if
  # (for instance) you need to specify a large enough type to avoid
  # overflow.
  #
  # Expects all element types to respond to `#+` method.
  #
  # ```
  # [1, 2, 3, 4, 5, 6].sum(7) # => 28
  # ```
  #
  # If the collection is empty, returns *initial*.
  #
  # ```
  # ([] of Int32).sum(7) # => 7
  # ```
  def sum(initial)
    sum initial, &.itself
  end

  # Adds all results of the passed block for each element in the collection.
  #
  # ```
  # ["Alice", "Bob"].sum { |name| name.size } # => 8 (5 + 3)
  # ```
  #
  # Expects all types returned from the block to respond to `#+` method.
  #
  # This method calls `.additive_identity` on the yielded type to determine the
  # type of the sum value.  Hence, it can fail to compile if
  # `.additive_identity` fails to determine a safe type, e.g., in case of
  # union types.  In such cases, use `sum(initial)` with an initial value of
  # the expected type of the sum value.
  #
  # If the collection is empty, returns `additive_identity`.
  #
  # ```
  # ([] of Int32).sum { |x| x + 1 } # => 0
  # ```
  def sum(& : T ->)
    sum(additive_identity(Reflect(typeof(yield Enumerable.element_type(self))))) do |value|
      yield value
    end
  end

  # Adds *initial* and all results of the passed block for each element in the collection.
  #
  # ```
  # ["Alice", "Bob"].sum(1) { |name| name.size } # => 9 (1 + 5 + 3)
  # ```
  #
  # Expects all types returned from the block to respond to `#+` method.
  #
  # If the collection is empty, returns *initial*.
  #
  # ```
  # ([] of String).sum(1) { |name| name.size } # => 1
  # ```
  def sum(initial, & : T ->)
    reduce(initial) { |memo, e| memo + (yield e) }
  end

  # Multiplies all the elements in the collection together.
  #
  # Expects all element types to respond to `#*` method.
  #
  # ```
  # [1, 2, 3, 4, 5, 6].product # => 720
  # ```
  #
  # This method calls `.multiplicative_identity` on the element type to determine the
  # type of the product value.
  #
  # If the collection is empty, returns `multiplicative_identity`.
  #
  # ```
  # ([] of Int32).product # => 1
  # ```
  def product
    product Reflect(T).type.multiplicative_identity
  end

  # Multiplies *initial* and all the elements in the collection
  # together.  The type of *initial* will be the type of the product,
  # so use this if (for instance) you need to specify a large enough
  # type to avoid overflow.
  #
  # Expects all element types to respond to `#*` method.
  #
  # ```
  # [1, 2, 3, 4, 5, 6].product(7) # => 5040
  # ```
  #
  # If the collection is empty, returns *initial*.
  #
  # ```
  # ([] of Int32).product(7) # => 7
  # ```
  def product(initial : Number)
    product initial, &.itself
  end

  # Multiplies all results of the passed block for each element in the collection.
  #
  # ```
  # ["Alice", "Bob"].product { |name| name.size } # => 15 (5 * 3)
  # ```
  #
  # Expects all types returned from the block to respond to `#*` method.
  #
  # This method calls `.multiplicative_identity` on the element type to
  # determine the type of the product value.  Hence, it can fail to compile if
  # `.multiplicative_identity` fails to determine a safe type, e.g., in case
  # of union types.  In such cases, use `product(initial)` with an initial
  # value of the expected type of the product value.
  #
  # If the collection is empty, returns `multiplicative_identity`.
  #
  # ```
  # ([] of Int32).product { |x| x + 1 } # => 1
  # ```
  def product(& : T -> _)
    product(Reflect(typeof(yield Enumerable.element_type(self))).type.multiplicative_identity) do |value|
      yield value
    end
  end

  # Multiplies *initial* and all results of the passed block for each element
  # in the collection.
  #
  # ```
  # ["Alice", "Bob"].product(2) { |name| name.size } # => 30 (2 * 5 * 3)
  # ```
  #
  # Expects all types returned from the block to respond to `#*` method.
  #
  # If the collection is empty, returns `1`.
  #
  # ```
  # ([] of String).product(1) { |name| name.size } # => 1
  # ```
  def product(initial : Number, & : T ->)
    reduce(initial) { |memo, e| memo * (yield e) }
  end

  # Returns an `Array` with the first *count* elements in the collection.
  #
  # If *count* is bigger than the number of elements in the collection,
  # returns as many as possible. This include the case of calling it over
  # an empty collection, in which case it returns an empty array.
  def first(count : Int) : Array(T)
    raise ArgumentError.new("Attempt to take negative size") if count < 0

    ary = Array(T).new(count)
    each_with_index do |e, i|
      break if i == count
      ary << e
    end
    ary
  end

  # Passes elements to the block until the block returns a falsey value,
  # then stops iterating and returns an `Array` of all prior elements.
  #
  # ```
  # [1, 2, 3, 4, 5, 0].take_while { |i| i < 3 } # => [1, 2]
  # ```
  def take_while(& : T ->) : Array(T)
    result = Array(T).new
    each do |x|
      break unless yield x
      result << x
    end
    result
  end

  # Tallies the collection.  Returns a hash where the keys are the
  # elements and the values are numbers of elements in the collection
  # that correspond to the key after transformation by the given block.
  #
  # ```
  # ["a", "A", "b", "B"].tally_by(&.downcase) # => {"a" => 2, "b" => 2}
  # ```
  def tally_by(&block : T -> U) : Hash(U, Int32) forall U
    tally_by(Hash(U, Int32).new, &block)
  end

  # Tallies the collection. Accepts a *hash* to count occurrences.
  # The value corresponding to each element must be an integer.
  # Returns *hash* where the keys are the
  # elements and the values are numbers of elements in the collection
  # that correspond to the key after transformation by the given block.
  #
  # ```
  # hash = {} of Char => Int32
  # words = ["Crystal", "Ruby"]
  # words.each { |word| word.chars.tally_by(hash, &.downcase) }
  # hash # => {'c' => 1, 'r' => 2, 'y' => 2, 's' => 1, 't' => 1, 'a' => 1, 'l' => 1, 'u' => 1, 'b' => 1}
  # ```
  def tally_by(hash, &)
    each_with_object(hash) do |item, hash|
      value = yield item

      count = hash.fetch(value) { typeof(hash[value]).zero }
      hash[value] = count + 1
    end
  end

  # Tallies the collection.  Returns a hash where the keys are the
  # elements and the values are numbers of elements in the collection
  # that correspond to the key.
  #
  # ```
  # ["a", "b", "c", "b"].tally # => {"a"=>1, "b"=>2, "c"=>1}
  # ```
  def tally : Hash(T, Int32)
    tally_by(Hash(T, Int32).new, &.itself)
  end

  # Tallies the collection. Accepts a *hash* to count occurrences.
  # The value corresponding to each element must be an integer.
  # The number of occurrences is added to each value in *hash*,
  # and *hash* is returned.
  #
  # ```
  # hash = {} of Char => Int32
  # words = ["crystal", "ruby"]
  # words.each { |word| word.chars.tally(hash) }
  # hash # => {'c' => 1, 'r' => 2, 'y' => 2, 's' => 1, 't' => 1, 'a' => 1, 'l' => 1, 'u' => 1, 'b' => 1}
  # ```
  def tally(hash)
    tally_by(hash, &.itself)
  end

  # Returns an `Array` with all the elements in the collection.
  #
  # ```
  # (1..5).to_a # => [1, 2, 3, 4, 5]
  # ```
  def to_a : Array(T)
    to_a(&.as(T))
  end

  # Returns an `Array` with the results of running *block* against each element of the collection.
  #
  # ```
  # (1..5).to_a { |i| i * 2 } # => [2, 4, 6, 8, 10]
  # ```
  def to_a(& : T -> U) : Array(U) forall U
    ary = [] of U
    each { |e| ary << yield e }
    ary
  end

  # Creates a `Hash` out of an Enumerable where each element is a
  # 2 element structure (for instance a `Tuple` or an `Array`).
  #
  # ```
  # [[:a, :b], [:c, :d]].to_h        # => {:a => :b, :c => :d}
  # Tuple.new({:a, 1}, {:c, 2}).to_h # => {:a => 1, :c => 2}
  # ```
  def to_h
    each_with_object(Hash(typeof(Enumerable.element_type(self)[0]), typeof(Enumerable.element_type(self)[1])).new) do |item, hash|
      hash[item[0]] = item[1]
    end
  end

  # Creates a `Hash` out of `Tuple` pairs (key, value) returned from the *block*.
  #
  # ```
  # (1..3).to_h { |i| {i, i ** 2} } # => {1 => 1, 2 => 4, 3 => 9}
  # ```
  def to_h(& : T -> Tuple(K, V)) forall K, V
    each_with_object({} of K => V) do |item, hash|
      key, value = yield item
      hash[key] = value
    end
  end

  # Yields elements of `self` and *others* in tandem to the given block.
  #
  # Raises an `IndexError` if any of *others* doesn't have as many elements
  # as `self`. See `zip?` for a version that yields `nil` instead of raising.
  #
  # ```
  # a = [1, 2, 3]
  # b = ["a", "b", "c"]
  #
  # a.zip(b) { |x, y| puts "#{x} -- #{y}" }
  # ```
  #
  # The above produces:
  #
  # ```text
  # 1 -- a
  # 2 -- b
  # 3 -- c
  # ```
  #
  # An example with multiple arguments:
  #
  # ```
  # (1..3).zip(4..6, 7..9) do |x, y, z|
  #   puts "#{x} -- #{y} -- #{z}"
  # end
  # ```
  #
  # The above produces:
  #
  # ```text
  # 1 -- 4 -- 7
  # 2 -- 5 -- 8
  # 3 -- 6 -- 9
  # ```
  def zip(*others : Indexable | Iterable | Iterator, &)
    Enumerable.zip(self, others) do |elems|
      yield elems
    end
  end

  # Returns an `Array` of tuples populated with the elements of `self` and
  # *others* traversed in tandem.
  #
  # Raises an `IndexError` if any of *others* doesn't have as many elements
  # as `self`. See `zip?` for a version that yields `nil` instead of raising.
  #
  # ```
  # a = [1, 2, 3]
  # b = ["a", "b", "c"]
  #
  # a.zip(b) # => [{1, "a"}, {2, "b"}, {3, "c"}]
  # ```
  #
  # An example with multiple arguments:
  #
  # ```
  # a = [1, 2, 3]
  # b = (4..6)
  # c = 8.downto(3)
  #
  # a.zip(b, c) # => [{1, 4, 8}, {2, 5, 7}, {3, 6, 6}]
  # ```
  def zip(*others : Indexable | Iterable | Iterator)
    size = self.is_a?(Indexable) ? self.size : 0
    pairs = Array(typeof(zip(*others) { |e| break e }.not_nil!)).new(size)
    zip(*others) { |e| pairs << e }
    pairs
  end

  # Yields elements of `self` and *others* in tandem to the given block.
  #
  # All of the elements in `self` will be yielded: if *others* don't have
  # that many elements they will be returned as `nil`.
  #
  # ```
  # a = [1, 2, 3]
  # b = ["a", "b"]
  #
  # a.zip?(b) { |x, y| puts "#{x.inspect} -- #{y.inspect}" }
  # ```
  #
  # The above produces:
  #
  # ```text
  # 1 -- "a"
  # 2 -- "b"
  # 3 -- nil
  # ```
  #
  # An example with multiple arguments:
  #
  # ```
  # (1..3).zip?(4..5, 7..8) do |x, y, z|
  #   puts "#{x.inspect} -- #{y.inspect} -- #{z.inspect}"
  # end
  # ```
  #
  # The above produces:
  #
  # ```text
  # 1 -- 4 -- 7
  # 2 -- 5 -- 8
  # 3 -- nil -- nil
  # ```
  def zip?(*others : Indexable | Iterable | Iterator, &)
    Enumerable.zip?(self, others) do |elems|
      yield elems
    end
  end

  # Returns an `Array` of tuples populated with the elements of `self` and
  # *others* traversed in tandem.
  #
  # All elements in `self` are returned in the Array. If matching elements
  # in *others* are missing (because they don't have that many elements)
  # `nil` is returned inside that tuple index.
  #
  # ```
  # a = [1, 2, 3]
  # b = ["a", "b"]
  #
  # a.zip?(b) # => [{1, "a"}, {2, "b"}, {3, nil}]
  # ```
  #
  # An example with multiple arguments:
  #
  # ```
  # a = [1, 2, 3]
  # b = (4..5)
  # c = 8.downto(7)
  #
  # a.zip?(b, c) # => [{1, 4, 8}, {2, 5, 7}, {3, nil, nil}]
  # ```
  def zip?(*others : Indexable | Iterable | Iterator)
    size = self.is_a?(Indexable) ? self.size : 0
    pairs = Array(typeof(zip?(*others) { |e| break e }.not_nil!)).new(size)
    zip?(*others) { |e| pairs << e }
    pairs
  end

  # :nodoc:
  def self.zip(main, others : U, &) forall U
    {% begin %}
      {% for type, type_index in U %}
        other{{type_index}} = others[{{type_index}}]
      {% end %}

      # Try to see if we need to create iterators (or treat as iterators)
      # for every element in `others`.
      {% for type, type_index in U %}
        case other{{type_index}}
        when Indexable
          # Nothing to do, but needed because many Indexables are Iterable/Iterator
        when Iterable
          iter{{type_index}} = other{{type_index}}.each
        else
          iter{{type_index}} = other{{type_index}}
        end
      {% end %}

      main.each_with_index do |elem, i|
        {% for type, type_index in U %}
          if other{{type_index}}.is_a?(Indexable)
            # Index into those we can
            other_elem{{type_index}} = other{{type_index}}[i]
          else
            # Otherwise advance the iterator
            other_elem{{type_index}} = iter{{type_index}}.not_nil!.next
            if other_elem{{type_index}}.is_a?(Iterator::Stop)
              raise IndexError.new
            end
          end
        {% end %}

        # Yield all elements as a tuple
        yield({
          elem,
          {% for _t, type_index in U %}
            other_elem{{type_index}},
          {% end %}
        })
      end
    {% end %}
  end

  # :nodoc:
  def self.zip?(main, others : U, &) forall U
    {% begin %}
      {% for type, type_index in U %}
        other{{type_index}} = others[{{type_index}}]
      {% end %}

      # Try to see if we need to create iterators (or treat as iterators)
      # for every element in `others`.
      {% for type, type_index in U %}
        case other{{type_index}}
        when Indexable
          # Nothing to do, but needed because many Indexables are Iterable/Iterator
        when Iterable
          iter{{type_index}} = other{{type_index}}.each
        else
          iter{{type_index}} = other{{type_index}}
        end
      {% end %}

      main.each_with_index do |elem, i|
        {% for type, type_index in U %}
          if other{{type_index}}.is_a?(Indexable)
            # Index into those we can
            other_elem{{type_index}} = other{{type_index}}[i]?
          else
            # Otherwise advance the iterator
            other_elem{{type_index}} = iter{{type_index}}.not_nil!.next
            if other_elem{{type_index}}.is_a?(Iterator::Stop)
              other_elem{{type_index}} = nil
            end
          end
        {% end %}

        # Yield all elements as a tuple
        yield({
          elem,
          {% for _t, type_index in U %}
            other_elem{{type_index}},
          {% end %}
        })
      end
    {% end %}
  end

  # :nodoc:
  private struct Reflect(X)
    # For now, Reflect is used to reject union types in `#sum()` and
    # `#product()` methods.
    def self.type
      {% if X.union? %}
        {{
          raise("`Enumerable#sum()` and `#product()` do not support Union " +
                "types. Instead, use `Enumerable#sum(initial)` and " +
                "`#product(initial)`, respectively, with an initial value " +
                "of the intended type of the call.")
        }}
      {% else %}
        X
      {% end %}
    end
  end

  # Returns a value with the same type as an element of *x*, even if *x* is not
  # an `Enumerable`.
  #
  # Used by splat expansion inside array literals. For example, this code
  #
  # ```
  # [1, *{2, 3.5}, 4]
  # ```
  #
  # will end up calling `typeof(1, ::Enumerable.element_type({2, 3.5}), 4)`.
  #
  # NOTE: there should never be a need to call this method outside the standard library.
  def self.element_type(x)
    x.each { |elem| return elem }
    ::raise ""
  end
end
