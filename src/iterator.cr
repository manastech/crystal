require "./enumerable"

# An `Iterator` allows processing sequences lazily, as opposed to `Enumerable` which processes
# sequences eagerly and produces an `Array` in most of its methods.
#
# As an example, let's compute the first three numbers in the range `1..10_000_000` that are even,
# multiplied by three. One way to do this is:
#
# ```
# (1..10_000_000).select(&.even?).map { |x| x * 3 }.first(3) # => [6, 12, 18]
# ```
#
# The above works, but creates many intermediate arrays: one for the `select` call,
# one for the `map` call and one for the `first` call. A more efficient way is to invoke
# `Range#each` without a block, which gives us an `Iterator` so we can process the operations
# lazily:
#
# ```
# (1..10_000_000).each.select(&.even?).map { |x| x * 3 }.first(3) # => #< Iterator(T)::First...
# ```
#
# `Iterator` redefines many of `Enumerable`'s method in a lazy way, returning iterators
# instead of arrays.
#
# At the end of the call chain we get back a new iterator: we need to consume it, either
# using `each` or `Enumerable#to_a`:
#
# ```
# (1..10_000_000).each.select(&.even?).map { |x| x * 3 }.first(3).to_a # => [6, 12, 18]
# ```
#
# Because iterators only go forward, when using methods that consume it entirely or partially –
# `to_a`, `any?`, `count`, `none?`, `one?` and `size` – subsequent calls will give a different
# result as there will be less elements to consume.
#
# ```
# iter = (0...100).each
# iter.size # => 100
# iter.size # => 0
# ```
#
# ### Iterating step-by-step
#
# An iterator returns its next element on the method `#next`.
# Its return type is a union of the iterator's element type and the `Stop` type:
# `T | Iterator::Stop`.
# The stop type is a sentinel value which indicates that the iterator has
# reached its end. It usually needs to be handled and filtered out in order to
# use the element value for anything useful.
# Unlike `Nil` it's not an implicitly falsey type.
#
# ```
# iter = (1..5).each
#
# # Unfiltered elements contain `Iterator::Stop` type
# iter.next + iter.next # Error: expected argument #1 to 'Int32#+' to be Int32, not (Int32 | Iterator::Stop)
#
# # Type filtering eliminates the stop type
# a = iter.next
# b = iter.next
# unless a.is_a?(Iterator::Stop) || b.is_a?(Iterator::Stop)
#   a + b # => 3
# end
# ```
#
# `Iterator::Stop` is only present in the return type of `#next`. All other
# methods remove it from their return types.
#
# Iterators can be used to build a loop.
#
# ```
# iter = (1..5).each
# sum = 0
# while !(elem = iter.next).is_a?(Iterator::Stop)
#   sum += elem
# end
# sum # => 15
# ```
#
# ### Implementing an Iterator
#
# To implement an `Iterator` you need to define a `next` method that must return the next
# element in the sequence or `Iterator::Stop::INSTANCE`, which signals the end of the sequence
# (you can invoke `stop` inside an iterator as a shortcut).
#
# For example, this is an iterator that returns a sequence of `N` zeros:
#
# ```
# class Zeros
#   include Iterator(Int32)
#
#   def initialize(@size : Int32)
#     @produced = 0
#   end
#
#   def next
#     if @produced < @size
#       @produced += 1
#       0
#     else
#       stop
#     end
#   end
# end
#
# zeros = Zeros.new(5)
# zeros.to_a # => [0, 0, 0, 0, 0]
# ```
#
# The standard library provides iterators for many classes, like `Array`, `Hash`, `Range`, `String` and `IO`.
# Usually to get an iterator you invoke a method that would usually yield elements to a block,
# but without passing a block: `Array#each`, `Array#each_index`, `Hash#each`, `String#each_char`,
# `IO#each_line`, etc.
#
# ### Built-in iterator semantics
#
# All iterators in the standard library have reference semantics, regardless of
# whether they are defined as classes or structs. That means if an iterator is
# assigned to multiple variables, calling `#next` on any variable will affect
# the internal state of the other variables simultaneously:
#
# ```
# iter1 = (1..5).each.cons_pair
# iter2 = iter1
# iter1.next             # => {1, 2}
# iter2.next             # => {2, 3}
# iter1.is_a?(Reference) # => true
#
# iter1 = (1..5).each.step(2)
# iter2 = iter1
# iter1.next             # => 1
# iter2.next             # => 3
# iter1.is_a?(Reference) # => false
# ```
#
# For this reason, when chaining iterators, the standard library assumes that
# all input iterators also have reference semantics. One common cause of
# exhibiting value semantics is reassigning to an instance variable in `#next`'s
# body when an iterator is defined as a struct. Those iterators are not
# guaranteed to behave properly when chained:
#
# ```
# struct Zeros
#   # same definition as above
# end
#
# iter1 = Zeros.new(1)
# iter2 = iter1
# iter1.next # => 0
# iter2.next # returns 0, but should be Iterator::Stop::INSTANCE
# ```
module Iterator(T)
  include Enumerable(T)

  # The class that signals that there are no more elements in an `Iterator`.
  class Stop
    INSTANCE = new
  end

  # `IteratorWrapper` eliminates some boilerplate when defining
  # an `Iterator` that wraps another iterator.
  #
  # To use it, include this module in your iterator and make sure that the wrapped
  # iterator is stored in the `@iterator` instance variable.
  module IteratorWrapper
    # Invokes `next` on the wrapped iterator and returns `stop` if
    # the given value was a `Iterator::Stop`. Otherwise, returns the value.
    macro wrapped_next
      %value = @iterator.next
      return stop if %value.is_a?(Stop)
      %value
    end
  end

  # Shortcut for `Iterator::Stop::INSTANCE`, to signal that there are no more elements in an iterator.
  def stop
    Iterator.stop
  end

  # :ditto:
  def self.stop
    Stop::INSTANCE
  end

  # Returns an empty iterator.
  def self.empty
    EmptyIterator(T).new
  end

  private struct EmptyIterator(T)
    include Iterator(T)

    def next
      stop
    end
  end

  def self.of(element : T)
    SingletonIterator(T).new(element)
  end

  private struct SingletonIterator(T)
    include Iterator(T)

    def initialize(@element : T)
    end

    def next
      @element
    end
  end

  def self.of(&block : -> T)
    SingletonProcIterator(typeof(without_stop(&block))).new(block)
  end

  private def self.without_stop(&block : -> T)
    e = block.call
    raise "" if e.is_a?(Iterator::Stop)
    e
  end

  private struct SingletonProcIterator(T)
    include Iterator(T)

    def initialize(@proc : (-> (T | Iterator::Stop)) | (-> T))
    end

    def next
      @proc.call
    end
  end

  # Returns the next element in this iterator, or `Iterator::Stop::INSTANCE` if there
  # are no more elements.
  abstract def next

  # Returns an iterator that returns the prefix sums of the original iterator's
  # elements.
  #
  # Expects `T` to respond to the `#+` method.
  #
  # ```
  # iter = (3..6).each.accumulate
  # iter.next # => 3
  # iter.next # => 7
  # iter.next # => 12
  # iter.next # => 18
  # iter.next # => Iterator::Stop::INSTANCE
  # ```
  def accumulate
    accumulate { |x, y| x + y }
  end

  # Returns an iterator that returns *initial* and its prefix sums with the
  # original iterator's elements.
  #
  # Expects `U` to respond to the `#+` method.
  #
  # ```
  # iter = (3..6).each.accumulate(7)
  # iter.next # => 7
  # iter.next # => 10
  # iter.next # => 14
  # iter.next # => 19
  # iter.next # => 25
  # iter.next # => Iterator::Stop::INSTANCE
  # ```
  def accumulate(initial : U) forall U
    accumulate(initial) { |x, y| x + y }
  end

  # Returns an iterator that accumulates the original iterator's elements by
  # the given *block*.
  #
  # For each element of the original iterator the block is passed an accumulator
  # value and the element. The result becomes the new value for the accumulator
  # and is then returned. The initial value for the accumulator is the first
  # element of the original iterator.
  #
  # ```
  # iter = %w(the quick brown fox).each.accumulate { |x, y| "#{x}, #{y}" }
  # iter.next # => "the"
  # iter.next # => "the, quick"
  # iter.next # => "the, quick, brown"
  # iter.next # => "the, quick, brown, fox"
  # iter.next # => Iterator::Stop::INSTANCE
  # ```
  def accumulate(&block : T, T -> T)
    AccumulateIterator(typeof(self), T).new(self, block)
  end

  # Returns an iterator that accumulates *initial* with the original iterator's
  # elements by the given *block*.
  #
  # Similar to `#accumulate(&block : T, T -> T)`, except the initial value is
  # provided by an argument and needs not have the same type as the elements of
  # the original iterator. This initial value is returned first.
  #
  # ```
  # iter = [4, 3, 2].each.accumulate("X") { |x, y| x * y }
  # iter.next # => "X"
  # iter.next # => "XXXX"
  # iter.next # => "XXXXXXXXXXXX"
  # iter.next # => "XXXXXXXXXXXXXXXXXXXXXXXX"
  # iter.next # => Iterator::Stop::INSTANCE
  # ```
  def accumulate(initial : U, &block : U, T -> U) forall U
    AccumulateInitIterator(typeof(self), T, U).new(self, initial, block)
  end

  private class AccumulateInitIterator(I, T, U)
    include Iterator(U)

    @acc : U | Iterator::Stop

    def initialize(@iterator : I, @acc : U, @func : U, T -> U)
    end

    def next
      old_acc = @acc
      return old_acc if old_acc.is_a?(Iterator::Stop)
      elem = @iterator.next
      @acc = elem.is_a?(Iterator::Stop) ? elem : @func.call(old_acc, elem)
      old_acc
    end
  end

  private class AccumulateIterator(I, T)
    include Iterator(T)
    include IteratorWrapper

    @acc : T | Iterator::Stop = Iterator::Stop::INSTANCE

    def initialize(@iterator : I, @func : T, T -> T)
    end

    def next
      elem = wrapped_next
      old_acc = @acc
      @acc = old_acc.is_a?(Iterator::Stop) ? elem : @func.call(old_acc, elem)
    end
  end

  # Returns an iterator that returns elements from the original iterator until
  # it is exhausted and then returns the elements of the second iterator.
  # Compared to `.chain(Iterator(Iter))`, it has better performance when the quantity of
  # iterators to chain is small (usually less than 4).
  # This method also cannot chain iterators in a loop, for that see `.chain(Iterator(Iter))`.
  #
  # ```
  # iter = (1..2).each.chain(('a'..'b').each)
  # iter.next # => 1
  # iter.next # => 2
  # iter.next # => 'a'
  # iter.next # => 'b'
  # iter.next # => Iterator::Stop::INSTANCE
  # ```
  def chain(other : Iterator(U)) forall U
    ChainIterator(typeof(self), typeof(other), T, U).new(self, other)
  end

  private class ChainIterator(I1, I2, T1, T2)
    include Iterator(T1 | T2)

    def initialize(@iterator1 : I1, @iterator2 : I2)
      @iterator1_consumed = false
    end

    def next
      unless @iterator1_consumed
        value = @iterator1.next
        if value.is_a?(Stop)
          @iterator1_consumed = true
        else
          return value
        end
      end
      @iterator2.next
    end
  end

  # The same as `#chain`, but have better performance when the quantity of
  # iterators to chain is large (usually greater than 4) or undetermined.
  #
  # ```
  # array_of_iters = [[1], [2, 3], [4, 5, 6]].each.map &.each
  # iter = Iterator(Int32).chain array_of_iters
  # iter.next # => 1
  # iter.next # => 2
  # iter.next # => 3
  # iter.next # => 4
  # ```
  def self.chain(iters : Iterator(Iter)) forall Iter
    ChainsAllIterator(Iter, typeof(iters.first.first)).new iters
  end

  # the same as `.chain(Iterator(Iter))`
  def self.chain(iters : Iterable(Iter)) forall Iter
    chain iters.each
  end

  private class ChainsAllIterator(Iter, T)
    include Iterator(T)
    @iterators : Iterator(Iter)
    @current : Iter | Stop

    def initialize(@iterators)
      @current = @iterators.next
    end

    def next : T | Stop
      return Stop::INSTANCE if (c = @current).is_a? Stop
      ret = c.next
      while ret.is_a? Stop
        c = @current = @iterators.next
        return Stop::INSTANCE if c.is_a? Stop
        ret = c.next
      end
      ret
    end
  end

  # Returns an iterator that applies the given function to the element and then
  # returns it unless it is `nil`. If the returned value would be `nil` it instead
  # returns the next non `nil` value.
  #
  # ```
  # iter = [1, nil, 2, nil].each.compact_map { |e| e.try &.*(2) }
  # iter.next # => 2
  # iter.next # => 4
  # iter.next # => Iterator::Stop::INSTANCE
  # ```
  def compact_map(&func : T -> _)
    CompactMapIterator(typeof(self), T, typeof(func.call(first).not_nil!)).new(self, func)
  end

  private struct CompactMapIterator(I, T, U)
    include Iterator(U)
    include IteratorWrapper

    def initialize(@iterator : I, @func : T -> U?)
    end

    def next
      while true
        value = wrapped_next
        mapped_value = @func.call(value)

        return mapped_value unless mapped_value.nil?
      end
    end
  end

  # Returns an iterator that returns consecutive chunks of the size *n*.
  #
  # ```
  # iter = (1..5).each.cons(3)
  # iter.next # => [1, 2, 3]
  # iter.next # => [2, 3, 4]
  # iter.next # => [3, 4, 5]
  # iter.next # => Iterator::Stop::INSTANCE
  # ```
  #
  # By default, a new array is created and returned for each consecutive call of `next`.
  # * If *reuse* is given, the array can be reused
  # * If *reuse* is `true`, the method will create a new array and reuse it.
  # * If *reuse*  is an instance of `Array`, `Deque` or a similar collection type (implementing `#<<`, `#shift` and `#size`) it will be used.
  # * If *reuse* is falsey, the array will not be reused.
  #
  # This can be used to prevent many memory allocations when each slice of
  # interest is to be used in a read-only fashion.
  #
  # Chunks of two items can be iterated using `#cons_pair`, an optimized
  # implementation for the special case of `n == 2` which avoids heap
  # allocations.
  def cons(n : Int, reuse = false)
    raise ArgumentError.new "Invalid cons size: #{n}" if n <= 0
    if reuse.nil? || reuse.is_a?(Bool)
      # we use an initial capacity of n * 2, because a second iteration would
      # have reallocated the array to that capacity anyway
      ConsIterator(typeof(self), T, typeof(n), Array(T)).new(self, n, Array(T).new(n * 2), reuse)
    else
      ConsIterator(typeof(self), T, typeof(n), typeof(reuse)).new(self, n, reuse, reuse)
    end
  end

  private struct ConsIterator(I, T, N, V)
    include Iterator(Array(T))
    include IteratorWrapper

    def initialize(@iterator : I, @n : N, values : V, reuse)
      @values = values
      @reuse = !!reuse
    end

    def next
      loop do
        elem = wrapped_next
        @values << elem
        @values.shift if @values.size > @n
        break if @values.size == @n
      end

      if @reuse
        @values
      else
        @values.dup
      end
    end
  end

  # Returns an iterator that returns consecutive pairs of adjacent items.
  #
  # ```
  # iter = (1..5).each.cons_pair
  # iter.next # => {1, 2}
  # iter.next # => {2, 3}
  # iter.next # => {3, 4}
  # iter.next # => {4, 5}
  # iter.next # => Iterator::Stop::INSTANCE
  # ```
  #
  # Chunks of more than two items can be iterated using `#cons`.
  # This method is just an optimized implementation for the special case of
  # `n == 2` to avoid heap allocations.
  def cons_pair : Iterator({T, T})
    ConsTupleIterator(typeof(self), T).new(self)
  end

  private class ConsTupleIterator(I, T)
    include Iterator({T, T})
    include IteratorWrapper

    @last_elem : T | Iterator::Stop = Iterator::Stop::INSTANCE

    def initialize(@iterator : I)
    end

    def next : {T, T} | Iterator::Stop
      elem = wrapped_next
      last_elem = @last_elem

      if last_elem.is_a?(Iterator::Stop)
        @last_elem = elem
        self.next
      else
        value = {last_elem, elem}
        @last_elem = elem
        value
      end
    end
  end

  # Returns an iterator that repeatedly returns the elements of the original
  # iterator forever starting back at the beginning when the end was reached.
  #
  # ```
  # iter = ["a", "b", "c"].each.cycle
  # iter.next # => "a"
  # iter.next # => "b"
  # iter.next # => "c"
  # iter.next # => "a"
  # iter.next # => "b"
  # iter.next # => "c"
  # iter.next # => "a"
  # # and so an and so on
  # ```
  def cycle
    CycleIterator(typeof(self), T).new(self)
  end

  private class CycleIterator(I, T)
    include Iterator(T)
    include IteratorWrapper

    def initialize(@iterator : I)
      @values = [] of T
      @use_values = false
      @index = 0
    end

    def next
      if @use_values
        return stop if @values.empty?

        if @index >= @values.size
          @index = 1
          return @values.first
        end

        @index += 1
        return @values[@index - 1]
      end

      value = @iterator.next

      if value.is_a?(Stop)
        @use_values = true
        return stop if @values.empty?

        @index = 1
        return @values.first
      end

      @values << value
      value
    end
  end

  # Returns an iterator that repeatedly returns the elements of the original
  # iterator starting back at the beginning when the end was reached,
  # but only *n* times.
  #
  # ```
  # iter = ["a", "b", "c"].each.cycle(2)
  # iter.next # => "a"
  # iter.next # => "b"
  # iter.next # => "c"
  # iter.next # => "a"
  # iter.next # => "b"
  # iter.next # => "c"
  # iter.next # => Iterator::Stop::INSTANCE
  # ```
  def cycle(n : Int)
    CycleNIterator(typeof(self), T, typeof(n)).new(self, n)
  end

  private class CycleNIterator(I, T, N)
    include Iterator(T)
    include IteratorWrapper

    def initialize(@iterator : I, @n : N)
      @count = 0
      @values = [] of T
      @use_values = false
      @index = 0
    end

    def next
      return stop if @count >= @n

      if @count > 0
        return stop if @values.empty?

        if @index >= @values.size
          @count += 1
          return stop if @count >= @n

          @index = 1
          return @values.first
        end

        @index += 1
        return @values[@index - 1]
      end

      value = @iterator.next

      if value.is_a?(Stop)
        @count += 1
        return stop if @count >= @n
        return stop if @values.empty?

        @index = 1
        return @values.first
      end

      @values << value
      value
    end
  end

  def each
    self
  end

  # Calls the given block once for each element, passing that element
  # as a parameter.
  #
  # ```
  # iter = ["a", "b", "c"].each
  # iter.each { |x| print x, " " } # Prints "a b c"
  # ```
  def each(& : T ->) : Nil
    while true
      value = self.next
      break if value.is_a?(Stop)
      yield value
    end
  end

  # Returns an iterator that then returns slices of *n* elements of the initial
  # iterator.
  #
  # ```
  # iter = (1..9).each.each_slice(3)
  # iter.next # => [1, 2, 3]
  # iter.next # => [4, 5, 6]
  # iter.next # => [7, 8, 9]
  # iter.next # => Iterator::Stop::INSTANCE
  # ```
  #
  # By default, a new array is created and yielded for each consecutive when invoking `next`.
  # * If *reuse* is given, the array can be reused
  # * If *reuse* is an `Array`, this array will be reused
  # * If *reuse* is truthy, the method will create a new array and reuse it.
  #
  # This can be used to prevent many memory allocations when each slice of
  # interest is to be used in a read-only fashion.
  def each_slice(n, reuse = false)
    slice(n, reuse)
  end

  # Returns an iterator that flattens nested iterators and arrays into a single iterator
  # whose type is the union of the simple types of all of the nested iterators and arrays
  # (and their nested iterators and arrays, and so on).
  #
  # ```
  # iter = [(1..2).each, ('a'..'b').each].each.flatten
  # iter.next # => 1
  # iter.next # => 2
  # iter.next # => 'a'
  # iter.next # => 'b'
  # iter.next # => Iterator::Stop::INSTANCE
  # ```
  def flatten
    FlattenIterator(typeof(FlattenIterator.iterator_type(self)), typeof(FlattenIterator.element_type(self))).new(self)
  end

  private class FlattenIterator(I, T)
    include Iterator(T)

    @iterator : I
    @stopped : Array(I)
    @generators : Array(I)

    def initialize(@iterator)
      @generators = [] of I
      @stopped = [] of I
    end

    def next
      case value = @iterator.next
      when Iterator
        @generators.push @iterator
        @iterator = value
        self.next
      when Array
        @generators.push @iterator
        @iterator = value.each
        self.next
      when Stop
        @stopped << @iterator
        if @generators.empty?
          stop
        else
          @iterator = @generators.pop
          self.next
        end
      else
        value
      end
    end

    def self.element_type(element)
      case element
      when Stop
        raise ""
      when Iterator
        element_type(element.next)
      when Array
        element_type(element.each)
      else
        element
      end
    end

    def self.iterator_type(iter)
      case iter
      when Iterator
        iter || iterator_type iter.next
      when Array
        iterator_type iter.each
      else
        raise ""
      end
    end
  end

  # Returns a new iterator with the concatenated results of running the block
  # once for every element in the collection.
  # Only `Array` and `Iterator` results are concatenated; every other value is
  # returned once in the new iterator.
  #
  # ```
  # iter = [1, 2, 3].each.flat_map { |x| [x, x] }
  #
  # iter.next # => 1
  # iter.next # => 1
  # iter.next # => 2
  #
  # iter = [1, 2, 3].each.flat_map { |x| [x, x].each }
  #
  # iter.to_a # => [1, 1, 2, 2, 3, 3]
  # ```
  def flat_map(&func : T -> _)
    FlatMapIterator(typeof(self), typeof(FlatMapIterator.element_type(self, func)), typeof(FlatMapIterator.iterator_type(self, func)), typeof(func)).new self, func
  end

  private class FlatMapIterator(I0, T, I, F)
    include Iterator(T)
    include IteratorWrapper

    @iterator : I0
    @func : F
    @nest_iterator : I?
    @stopped : Array(I)

    def initialize(@iterator, @func)
      @nest_iterator = nil
      @stopped = [] of I
    end

    def next
      if iter = @nest_iterator
        value = iter.next
        if value.is_a?(Stop)
          @stopped << iter
          @nest_iterator = nil
          self.next
        else
          value
        end
      else
        case value = @func.call wrapped_next
        when Array
          @nest_iterator = value.each
          self.next
        when Iterator
          @nest_iterator = value
          self.next
        else
          value
        end
      end
    end

    def self.element_type(iter, func)
      value = iter.next
      raise "" if value.is_a?(Stop)

      case value = func.call value
      when Array, Iterator
        value.first
      else
        value
      end
    end

    def self.iterator_type(iter, func)
      value = iter.next
      raise "" if value.is_a?(Stop)

      case value = func.call value
      when Array
        value.each
      when Iterator
        value
      else
        raise ""
      end
    end
  end

  # Returns an iterator that chunks the iterator's elements in arrays of *size*
  # filling up the remaining elements if no element remains with `nil` or a given
  # optional parameter.
  #
  # ```
  # iter = (1..3).each.in_groups_of(2)
  # iter.next # => [1, 2]
  # iter.next # => [3, nil]
  # iter.next # => Iterator::Stop::INSTANCE
  # ```
  # ```
  # iter = (1..3).each.in_groups_of(2, 'z')
  # iter.next # => [1, 2]
  # iter.next # => [3, 'z']
  # iter.next # => Iterator::Stop::INSTANCE
  # ```
  #
  # By default, a new array is created and yielded for each group.
  # * If *reuse* is given, the array can be reused
  # * If *reuse* is an `Array`, this array will be reused
  # * If *reuse* is truthy, the method will create a new array and reuse it.
  #
  # This can be used to prevent many memory allocations when each slice of
  # interest is to be used in a read-only fashion.
  def in_groups_of(size : Int, filled_up_with = nil, reuse = false)
    raise ArgumentError.new("Size must be positive") if size <= 0
    InGroupsOfIterator(typeof(self), T, typeof(size), typeof(filled_up_with)).new(self, size, filled_up_with, reuse)
  end

  private struct InGroupsOfIterator(I, T, N, U)
    include Iterator(Array(T | U))
    include IteratorWrapper

    @reuse : Array(T | U)?

    def initialize(@iterator : I, @size : N, @filled_up_with : U, reuse)
      if reuse
        if reuse.is_a?(Array)
          @reuse = reuse
        else
          @reuse = Array(T | U).new(@size)
        end
      else
        @reuse = nil
      end
    end

    def next
      value = wrapped_next

      if reuse = @reuse
        reuse.clear
        array = reuse
      else
        array = Array(T | U).new(@size)
      end

      array << value
      (@size - 1).times do
        new_value = @iterator.next
        new_value = @filled_up_with if new_value.is_a?(Stop)
        array << new_value
      end
      array
    end
  end

  # Returns an iterator that applies the given block to the next element and
  # returns the result.
  #
  # ```
  # iter = [1, 2, 3].each.map &.*(2)
  # iter.next # => 2
  # iter.next # => 4
  # iter.next # => 6
  # iter.next # => Iterator::Stop::INSTANCE
  # ```
  def map(&func : T -> U) forall U
    MapIterator(typeof(self), T, U).new(self, func)
  end

  private struct MapIterator(I, T, U)
    include Iterator(U)
    include IteratorWrapper

    def initialize(@iterator : I, @func : T -> U)
    end

    def next
      value = wrapped_next
      @func.call(value)
    end
  end

  # Returns an iterator that only returns elements for which the passed in
  # block returns a falsey value.
  #
  # ```
  # iter = [1, 2, 3].each.reject &.odd?
  # iter.next # => 2
  # iter.next # => Iterator::Stop::INSTANCE
  # ```
  def reject(&func : T -> U) forall U
    RejectIterator(typeof(self), T, U).new(self, func)
  end

  # Returns an iterator that only returns elements
  # that are **not** of the given *type*.
  #
  # ```
  # iter = [1, false, 3, true].each.reject(Bool)
  # iter.next # => 1
  # iter.next # => 3
  # iter.next # => Iterator::Stop::INSTANCE
  # ```
  def reject(type : U.class) forall U
    SelectTypeIterator(typeof(self), typeof(begin
      e = first
      e.is_a?(U) ? raise("") : e
    end)).new(self)
  end

  # Returns an iterator that only returns elements
  # where `pattern === element` does not hold.
  #
  # ```
  # iter = [2, 3, 1, 5, 4, 6].each.reject(3..5)
  # iter.next # => 2
  # iter.next # => 1
  # iter.next # => 6
  # iter.next # => Iterator::Stop::INSTANCE
  # ```
  def reject(pattern)
    reject { |elem| pattern === elem }
  end

  private struct RejectIterator(I, T, B)
    include Iterator(T)
    include IteratorWrapper

    def initialize(@iterator : I, @func : T -> B)
    end

    def next
      while true
        value = wrapped_next
        unless @func.call(value)
          return value
        end
      end
    end
  end

  # Returns an iterator that only returns elements for which the passed
  # in block returns a truthy value.
  #
  # ```
  # iter = [1, 2, 3].each.select &.odd?
  # iter.next # => 1
  # iter.next # => 3
  # iter.next # => Iterator::Stop::INSTANCE
  # ```
  def select(&func : T -> U) forall U
    SelectIterator(typeof(self), T, U).new(self, func)
  end

  # Returns an iterator that only returns elements
  # of the given *type*.
  #
  # ```
  # iter = [1, false, 3, nil].each.select(Int32)
  # iter.next # => 1
  # iter.next # => 3
  # iter.next # => Iterator::Stop::INSTANCE
  # ```
  def select(type : U.class) forall U
    SelectTypeIterator(typeof(self), U).new(self)
  end

  # Returns an iterator that only returns elements
  # where `pattern === element`.
  #
  # ```
  # iter = [1, 3, 2, 5, 4, 6].each.select(3..5)
  # iter.next # => 3
  # iter.next # => 5
  # iter.next # => 4
  # iter.next # => Iterator::Stop::INSTANCE
  # ```
  def select(pattern)
    self.select { |elem| pattern === elem }
  end

  private struct SelectIterator(I, T, B)
    include Iterator(T)
    include IteratorWrapper

    def initialize(@iterator : I, @func : T -> B)
    end

    def next
      while true
        value = wrapped_next
        if @func.call(value)
          return value
        end
      end
    end
  end

  private struct SelectTypeIterator(I, T)
    include Iterator(T)
    include IteratorWrapper

    def initialize(@iterator : I)
    end

    def next
      while true
        value = wrapped_next
        if value.is_a?(T)
          return value
        end
      end
    end
  end

  # Returns an iterator that skips the first *n* elements and only returns
  # the elements after that.
  #
  # ```
  # iter = (1..3).each.skip(2)
  # iter.next # -> 3
  # iter.next # -> Iterator::Stop::INSTANCE
  # ```
  def skip(n : Int)
    raise ArgumentError.new "Attempted to skip negative size: #{n}" if n < 0
    SkipIterator(typeof(self), T, typeof(n)).new(self, n)
  end

  private class SkipIterator(I, T, N)
    include Iterator(T)
    include IteratorWrapper

    def initialize(@iterator : I, @n : N)
      @original = @n
    end

    def next
      while @n > 0
        @n -= 1
        wrapped_next
      end
      @iterator.next
    end
  end

  # Returns an iterator that only starts to return elements once the given block
  # has returned falsey value for one element.
  #
  # ```
  # iter = [1, 2, 3, 4, 0].each.skip_while { |i| i < 3 }
  # iter.next # => 3
  # iter.next # => 4
  # iter.next # => 0
  # iter.next # => Iterator::Stop::INSTANCE
  # ```
  def skip_while(&func : T -> U) forall U
    SkipWhileIterator(typeof(self), T, U).new(self, func)
  end

  private class SkipWhileIterator(I, T, U)
    include Iterator(T)
    include IteratorWrapper

    def initialize(@iterator : I, @func : T -> U)
      @returned_false = false
    end

    def next
      while true
        value = wrapped_next
        return value if @returned_false
        unless @func.call(value)
          @returned_false = true
          return value
        end
      end
    end
  end

  # Alias of `each_slice`.
  def slice(n : Int, reuse = false)
    raise ArgumentError.new "Invalid slice size: #{n}" if n <= 0
    SliceIterator(typeof(self), T, typeof(n)).new(self, n, reuse)
  end

  private struct SliceIterator(I, T, N)
    include Iterator(Array(T))
    include IteratorWrapper

    @reuse : Array(T)?

    def initialize(@iterator : I, @n : N, reuse)
      if reuse
        if reuse.is_a?(Array)
          @reuse = reuse
        else
          @reuse = Array(T).new(@n)
        end
      else
        @reuse = nil
      end
    end

    def next
      if reuse = @reuse
        reuse.clear
        values = reuse
      else
        values = Array(T).new(@n)
      end

      @n.times do
        value = @iterator.next
        break if value.is_a?(Stop)

        values << value
      end

      if values.empty?
        stop
      else
        values
      end
    end
  end

  # Returns an iterator that only returns every *n*th element, starting with the
  # first.
  #
  # ```
  # iter = (1..6).each.step(2)
  # iter.next # => 1
  # iter.next # => 3
  # iter.next # => 5
  # iter.next # => Iterator::Stop::INSTANCE
  # ```
  def step(n : Int)
    StepByIterator(self, T, typeof(n)).new(self, n)
  end

  private struct StepByIterator(I, T, N)
    include Iterator(T)
    include IteratorWrapper

    def initialize(@iterator : I, @by : N)
      raise ArgumentError.new("n must be greater or equal 1") if @by < 1
    end

    def next
      value = @iterator.next
      return stop if value.is_a?(Stop)

      (@by - 1).times do
        @iterator.next
      end

      value
    end
  end

  # Returns an iterator that only returns the first *n* elements of the
  # initial iterator.
  #
  # ```
  # iter = ["a", "b", "c"].each.first 2
  # iter.next # => "a"
  # iter.next # => "b"
  # iter.next # => Iterator::Stop::INSTANCE
  # ```
  def first(n : Int)
    raise ArgumentError.new "Attempted to take negative size: #{n}" if n < 0
    FirstIterator(typeof(self), T, typeof(n)).new(self, n)
  end

  private class FirstIterator(I, T, N)
    include Iterator(T)
    include IteratorWrapper

    def initialize(@iterator : I, @n : N)
      @original = @n
    end

    def next
      if @n > 0
        @n -= 1
        wrapped_next
      else
        stop
      end
    end
  end

  # Returns an iterator that returns elements while the given block returns a
  # truthy value.
  #
  # ```
  # iter = (1..5).each.take_while { |i| i < 3 }
  # iter.next # => 1
  # iter.next # => 2
  # iter.next # => Iterator::Stop::INSTANCE
  # ```
  def take_while(&func : T -> U) forall U
    TakeWhileIterator(typeof(self), T, U).new(self, func)
  end

  private class TakeWhileIterator(I, T, U)
    include Iterator(T)
    include IteratorWrapper

    def initialize(@iterator : I, @func : T -> U)
      @returned_false = false
    end

    def next
      return stop if @returned_false
      value = wrapped_next
      if @func.call(value)
        value
      else
        @returned_false = true
        stop
      end
    end
  end

  # Returns an iterator that calls the given block with the next element of the
  # iterator when calling `next`, still returning the original element.
  #
  # ```
  # a = 0
  # iter = (1..3).each.tap { |x| a += x }
  # iter.next # => 1
  # a         # => 1
  # iter.next # => 2
  # a         # => 3
  # iter.next # => 3
  # a         # => 6
  # iter.next # => Iterator::Stop::INSTANCE
  # ```
  def tap(&block : T ->)
    TapIterator(typeof(self), T).new(self, block)
  end

  private struct TapIterator(I, T)
    include Iterator(T)
    include IteratorWrapper

    def initialize(@iterator : I, @proc : T ->)
    end

    def next
      value = wrapped_next
      @proc.call(value)
      value
    end
  end

  # Returns an iterator that only returns unique values of the original
  # iterator.
  #
  # ```
  # iter = [1, 2, 1].each.uniq
  # iter.next # => 1
  # iter.next # => 2
  # iter.next # => Iterator::Stop::INSTANCE
  # ```
  def uniq
    uniq &.itself
  end

  # Returns an iterator that only returns unique values of the original
  # iterator. The provided block is applied to the elements to determine the
  # value to be checked for uniqueness.
  #
  # ```
  # iter = [["a", "a"], ["b", "a"], ["a", "c"]].each.uniq &.first
  # iter.next # => ["a", "a"]
  # iter.next # => ["b", "a"]
  # iter.next # => Iterator::Stop::INSTANCE
  # ```
  def uniq(&func : T -> U) forall U
    UniqIterator(typeof(self), T, U).new(self, func)
  end

  private struct UniqIterator(I, T, U)
    include Iterator(T)
    include IteratorWrapper

    def initialize(@iterator : I, @func : T -> U)
      @set = Set(U).new
    end

    def next
      while true
        value = wrapped_next
        transformed = @func.call value
        return value if @set.add?(transformed)
      end
    end
  end

  # Returns an iterator that returns a `Tuple` of the element and its index.
  #
  # ```
  # iter = (1..3).each.with_index
  # iter.next # => {1, 0}
  # iter.next # => {2, 1}
  # iter.next # => {3, 2}
  # iter.next # => Iterator::Stop::INSTANCE
  # ```
  def with_index(offset : Int = 0)
    WithIndexIterator(typeof(self), T, typeof(offset)).new(self, offset)
  end

  # Yields each element in this iterator together with its index.
  def with_index(offset : Int = 0, &)
    index = offset
    each do |value|
      yield value, index
      index += 1
    end
  end

  private class WithIndexIterator(I, T, O)
    include Iterator({T, O})
    include IteratorWrapper

    def initialize(@iterator : I, @offset : O, @index : O = offset)
    end

    def next
      v = wrapped_next
      value = {v, @index}
      @index += 1
      value
    end
  end

  # Returns an iterator that returns a `Tuple` of the element and a given object.
  #
  # ```
  # iter = (1..3).each.with_object("a")
  # iter.next # => {1, "a"}
  # iter.next # => {2, "a"}
  # iter.next # => {3, "a"}
  # iter.next # => Iterator::Stop::INSTANCE
  # ```
  def with_object(obj)
    WithObjectIterator(typeof(self), T, typeof(obj)).new(self, obj)
  end

  # Yields each element in this iterator together with *obj*. Returns that object.
  def with_object(obj, &)
    each do |value|
      yield value, obj
    end
    obj
  end

  private struct WithObjectIterator(I, T, O)
    include Iterator({T, O})
    include IteratorWrapper

    def initialize(@iterator : I, @object : O)
    end

    def next
      v = wrapped_next
      {v, @object}
    end
  end

  # Returns an iterator that returns the elements of this iterator and *others*
  # traversed in tandem as `Tuple`s.
  #
  # Iteration stops when any of the iterators runs out of elements.
  #
  # ```
  # iter1 = [4, 5, 6].each
  # iter2 = [7, 8, 9].each
  # iter3 = ['a', 'b', 'c', 'd'].each
  # iter = iter1.zip(iter2, iter3)
  # iter.next # => {4, 7, 'a'}
  # iter.next # => {5, 8, 'b'}
  # iter.next # => {6, 9, 'c'}
  # iter.next # => Iterator::Stop::INSTANCE
  # ```
  def zip(*others : Iterator) : Iterator
    Iterator.zip_impl(self, *others)
  end

  protected def self.zip_impl(*iterators : *U) forall U
    {% begin %}
      ZipIterator(U, Tuple(
        {% for i in 0...U.size %}
          typeof(iterators[{{ i }}].first),
        {% end %}
      )).new(iterators)
    {% end %}
  end

  private struct ZipIterator(Is, Ts)
    include Iterator(Ts)

    def initialize(@iterators : Is)
    end

    def next
      {% begin %}
        {% for i in 0...Is.size %}
          %v{i} = @iterators[{{ i }}].next
          return stop if %v{i}.is_a?(Stop)
        {% end %}

        Tuple.new(
          {% for i in 0...Is.size %}
            %v{i},
          {% end %}
        )
      {% end %}
    end
  end

  # Returns an Iterator that enumerates over the items,
  # chunking them together based on the return value of the block.
  #
  # Consecutive elements which return the same block value are chunked together.
  #
  # For example, consecutive even numbers and odd numbers can be chunked as follows.
  #
  # ```
  # [3, 1, 4, 1, 5, 9, 2, 6, 5, 3, 5].chunk(&.even?).each do |even, ary|
  #   p [even, ary]
  # end
  #
  # # => [false, [3, 1]]
  # #    [true, [4]]
  # #    [false, [1, 5, 9]]
  # #    [true, [2, 6]]
  # #    [false, [5, 3, 5]]
  # ```
  #
  # The following key values have special meaning:
  #
  # * `Enumerable::Chunk::Drop` specifies that the elements should be dropped
  # * `Enumerable::Chunk::Alone` specifies that the element should be chunked by itself
  #
  # By default, a new array is created and yielded for each chunk when invoking `next`.
  # * If *reuse* is given, the array can be reused
  # * If *reuse* is an `Array`, this array will be reused
  # * If *reuse* is truthy, the method will create a new array and reuse it.
  #
  # This can be used to prevent many memory allocations when each slice of
  # interest is to be used in a read-only fashion.
  #
  # See also: `Enumerable#chunks`.
  def chunk(reuse = false, &block : T -> U) forall T, U
    ChunkIterator(typeof(self), T, U, typeof(::Enumerable::Chunk.key_type(self, block))).new(self, reuse, &block)
  end

  private class ChunkIterator(I, T, U, V)
    include Iterator(Tuple(V, Array(T)))
    @iterator : I
    @init : {V, T}?

    def initialize(@iterator : Iterator(T), reuse, &@original_block : T -> U)
      @acc = ::Enumerable::Chunk::Accumulator(T, V).new(reuse)
    end

    def next
      if init = @init
        k, v = init
        @acc.init(k, v)
        @init = nil
      end

      @iterator.each do |val|
        key = @original_block.call(val)

        if @acc.same_as?(key)
          @acc.add(val)
        else
          tuple = @acc.fetch
          if tuple
            @init = {key, val} unless key.is_a?(::Enumerable::Chunk::Drop.class)
            return tuple
          else
            @acc.init(key, val) unless key.is_a?(::Enumerable::Chunk::Drop.class)
          end
        end
      end

      if tuple = @acc.fetch
        return tuple
      end

      stop
    end
  end

  # Returns an iterator over chunks of elements, where each
  # chunk ends right **after** the given block's value is _truthy_.
  #
  # For example, to get chunks that end at each uppercase letter:
  #
  # ```
  # ary = ['a', 'b', 'C', 'd', 'E', 'F', 'g', 'h']
  # #                   ^         ^    ^
  # iter = ary.slice_after(&.uppercase?)
  # iter.next # => ['a', 'b', 'C']
  # iter.next # => ['d', 'E']
  # iter.next # => ['F']
  # iter.next # => ['g', 'h']
  # iter.next # => Iterator::Stop::INSTANCE
  # ```
  #
  # By default, a new array is created and yielded for each slice when invoking `next`.
  # * If *reuse* is `false`, the method will create a new array for each chunk
  # * If *reuse* is `true`, the method will create a new array and reuse it.
  # * If *reuse* is an `Array`, that array will be reused
  #
  # This can be used to prevent many memory allocations when each slice of
  # interest is to be used in a read-only fashion.
  def slice_after(reuse : Bool | Array(T) = false, &block : T -> B) forall B
    SliceAfterIterator(typeof(self), T, B).new(self, block, reuse)
  end

  # Returns an iterator over chunks of elements, where each
  # chunk ends right **after** the given pattern is matched
  # with `pattern === element`.
  #
  # For example, to get chunks that end at each ASCII uppercase letter:
  #
  # ```
  # ary = ['a', 'b', 'C', 'd', 'E', 'F', 'g', 'h']
  # #                   ^         ^    ^
  # iter = ary.slice_after('A'..'Z')
  # iter.next # => ['a', 'b', 'C']
  # iter.next # => ['d', 'E']
  # iter.next # => ['F']
  # iter.next # => ['g', 'h']
  # iter.next # => Iterator::Stop::INSTANCE
  # ```
  #
  # By default, a new array is created and yielded for each slice when invoking `next`.
  # * If *reuse* is `false`, the method will create a new array for each chunk
  # * If *reuse* is `true`, the method will create a new array and reuse it.
  # * If *reuse* is an `Array`, that array will be reused
  #
  # This can be used to prevent many memory allocations when each slice of
  # interest is to be used in a read-only fashion.
  def slice_after(pattern, reuse : Bool | Array(T) = false)
    slice_after(reuse) { |elem| pattern === elem }
  end

  private class SliceAfterIterator(I, T, B)
    include Iterator(Array(T))

    def initialize(@iterator : I, @block : T -> B, reuse)
      @end = false
      @clear_on_next = false

      if reuse
        if reuse.is_a?(Array)
          @values = reuse
        else
          @values = [] of T
        end
        @reuse = true
      else
        @values = [] of T
        @reuse = false
      end
    end

    def next
      return stop if @end

      if @clear_on_next
        @values.clear
        @clear_on_next = false
      end

      while true
        value = @iterator.next

        if value.is_a?(Stop)
          @end = true
          if @values.empty?
            return stop
          else
            return @reuse ? @values : @values.dup
          end
        end

        @values << value

        if @block.call(value)
          @clear_on_next = true
          return @reuse ? @values : @values.dup
        end
      end
    end
  end

  # Returns an iterator over chunks of elements, where each
  # chunk ends right **before** the given block's value is _truthy_.
  #
  # For example, to get chunks that end just before each uppercase letter:
  #
  # ```
  # ary = ['a', 'b', 'C', 'd', 'E', 'F', 'g', 'h']
  # #              ^         ^    ^
  # iter = ary.slice_before(&.uppercase?)
  # iter.next # => ['a', 'b']
  # iter.next # => ['C', 'd']
  # iter.next # => ['E']
  # iter.next # => ['F', 'g', 'h']
  # iter.next # => Iterator::Stop::INSTANCE
  # ```
  #
  # By default, a new array is created and yielded for each slice when invoking `next`.
  # * If *reuse* is `false`, the method will create a new array for each chunk
  # * If *reuse* is `true`, the method will create a new array and reuse it.
  # * If *reuse* is an `Array`, that array will be reused
  #
  # This can be used to prevent many memory allocations when each slice of
  # interest is to be used in a read-only fashion.
  def slice_before(reuse : Bool | Array(T) = false, &block : T -> B) forall B
    SliceBeforeIterator(typeof(self), T, B).new(self, block, reuse)
  end

  # Returns an iterator over chunks of elements, where each
  # chunk ends right **before** the given pattern is matched
  # with `pattern === element`.
  #
  # For example, to get chunks that end just before each ASCII uppercase letter:
  #
  # ```
  # ary = ['a', 'b', 'C', 'd', 'E', 'F', 'g', 'h']
  # #              ^         ^    ^
  # iter = ary.slice_before('A'..'Z')
  # iter.next # => ['a', 'b']
  # iter.next # => ['C', 'd']
  # iter.next # => ['E']
  # iter.next # => ['F', 'g', 'h']
  # iter.next # => Iterator::Stop::INSTANCE
  # ```
  #
  # By default, a new array is created and yielded for each slice when invoking `next`.
  # * If *reuse* is `false`, the method will create a new array for each chunk
  # * If *reuse* is `true`, the method will create a new array and reuse it.
  # * If *reuse* is an `Array`, that array will be reused
  #
  # This can be used to prevent many memory allocations when each slice of
  # interest is to be used in a read-only fashion.
  def slice_before(pattern, reuse : Bool | Array(T) = false)
    slice_before(reuse) { |elem| pattern === elem }
  end

  private class SliceBeforeIterator(I, T, B)
    include Iterator(Array(T))

    @has_value_to_add = false
    @value_to_add : T?

    def initialize(@iterator : I, @block : T -> B, reuse)
      @end = false

      if reuse
        if reuse.is_a?(Array)
          @values = reuse
        else
          @values = [] of T
        end
        @reuse = true
      else
        @values = [] of T
        @reuse = false
      end
    end

    def next
      return stop if @end

      if @has_value_to_add
        @has_value_to_add = false
        @values.clear
        @values << @value_to_add.as(T)
        @value_to_add = nil
      end

      while true
        value = @iterator.next

        if value.is_a?(Stop)
          @end = true
          if @values.empty?
            return stop
          else
            return @reuse ? @values : @values.dup
          end
        end

        if !@values.empty? && @block.call(value)
          @has_value_to_add = true
          @value_to_add = value
          return @reuse ? @values : @values.dup
        end

        @values << value
      end
    end
  end

  # Returns an iterator for each chunked elements where the ends
  # of chunks are defined by the block, when the block's value
  # over a pair of elements is _truthy_.
  #
  # For example, one-by-one increasing subsequences can be chunked as follows:
  #
  # ```
  # ary = [1, 2, 4, 9, 10, 11, 12, 15, 16, 19, 20, 21]
  # iter = ary.slice_when { |i, j| i + 1 != j }
  # iter.next # => [1, 2]
  # iter.next # => [4]
  # iter.next # => [9, 10, 11, 12]
  # iter.next # => [15, 16]
  # iter.next # => [19, 20, 21]
  # iter.next # => Iterator::Stop::INSTANCE
  # ```
  #
  # By default, a new array is created and yielded for each slice when invoking `next`.
  # * If *reuse* is `false`, the method will create a new array for each chunk
  # * If *reuse* is `true`, the method will create a new array and reuse it.
  # * If *reuse* is an `Array`, that array will be reused
  #
  # This can be used to prevent many memory allocations when each slice of
  # interest is to be used in a read-only fashion.
  #
  # See also `#chunk_while`, which works similarly but the block's condition is inverted.
  def slice_when(reuse : Bool | Array(T) = false, &block : T, T -> B) forall B
    SliceWhenIterator(typeof(self), T, B).new(self, block, reuse)
  end

  # Returns an iterator for each chunked elements where elements
  # are kept in a given chunk as long as the block's value over
  # a pair of elements is _truthy_.
  #
  # For example, one-by-one increasing subsequences can be chunked as follows:
  #
  # ```
  # ary = [1, 2, 4, 9, 10, 11, 12, 15, 16, 19, 20, 21]
  # iter = ary.chunk_while { |i, j| i + 1 == j }
  # iter.next # => [1, 2]
  # iter.next # => [4]
  # iter.next # => [9, 10, 11, 12]
  # iter.next # => [15, 16]
  # iter.next # => [19, 20, 21]
  # iter.next # => Iterator::Stop::INSTANCE
  # ```
  #
  # By default, a new array is created and yielded for each slice when invoking `next`.
  # * If *reuse* is `false`, the method will create a new array for each chunk
  # * If *reuse* is `true`, the method will create a new array and reuse it.
  # * If *reuse* is an `Array`, that array will be reused
  #
  # This can be used to prevent many memory allocations when each slice of
  # interest is to be used in a read-only fashion.
  #
  # See also `#slice_when`, which works similarly but the block's condition is inverted.
  def chunk_while(reuse : Bool | Array(T) = false, &block : T, T -> B) forall B
    SliceWhenIterator(typeof(self), T, B).new(self, block, reuse, negate: true)
  end

  private class SliceWhenIterator(I, T, B)
    include Iterator(Array(T))

    @has_previous_value = false
    @previous_value : T?

    def initialize(@iterator : I, @block : T, T -> B, reuse, @negate = false)
      @end = false

      if reuse
        if reuse.is_a?(Array)
          @values = reuse
        else
          @values = [] of T
        end
        @reuse = true
      else
        @values = [] of T
        @reuse = false
      end
    end

    def next
      return stop if @end

      if @has_previous_value
        v1 = @previous_value.as(T)
        @has_previous_value = false
        @previous_value = nil
        @values.clear
      else
        v1 = @iterator.next
        return end_value if v1.is_a?(Stop)
      end

      while true
        @values << v1

        v2 = @iterator.next
        return end_value if v2.is_a?(Stop)

        cond = @block.call(v1, v2)
        cond = !cond if @negate
        if cond
          @has_previous_value = true
          @previous_value = v2
          return @reuse ? @values : @values.dup
        end

        v1 = v2
      end
    end

    private def end_value
      @end = true
      if @values.empty?
        stop
      else
        @reuse ? @values : @values.dup
      end
    end
  end
end
