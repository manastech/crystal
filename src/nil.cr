# The `Nil` type has only one possible value: `nil`.
#
# `nil` is commonly used to represent the absence of a value.
# For example, `String#index` returns the position of the character or `nil` if it's not
# in the string:
#
# ```
# str = "Hello world"
# str.index 'e' # => 1
# str.index 'a' # => nil
# ```
#
# In the above example, trying to invoke a method on the returned value will
# give a compile time error unless both `Int32` and `Nil` define that method:
#
# ```
# str = "Hello world"
# idx = str.index 'e'
# idx + 1 # Error: undefined method '+' for Nil
# ```
#
# The language and the standard library provide short, readable, easy ways to deal with `nil`,
# such as `Object#try` and `Object#not_nil!`:
#
# ```
# str = "Hello world"
#
# # The index of 'e' in str or 0 if not found
# idx1 = str.index('e') || 0
#
# idx2 = str.index('a')
# if idx2
#   # Compiles: idx2 can't be nil here
#   idx2 + 1
# end
#
# # Tell the compiler that we are sure the returned
# # value is not nil: raises a runtime exception
# # if our assumption doesn't hold.
# idx3 = str.index('o').not_nil!
# ```
#
# See [`Nil` literal](https://crystal-lang.org/reference/syntax_and_semantics/literals/nil.html) in the language reference.
struct Nil
  # Returns `0_u64`. Even though `Nil` is not a `Reference` type, it is usually
  # mixed with them to form nilable types so it's useful to have an
  # object id for `nil`.
  def object_id : UInt64
    0_u64
  end

  # :nodoc:
  def crystal_type_id
    0
  end

  # Returns `true`: `Nil` has only one singleton value: `nil`.
  def ==(other : Nil)
    true
  end

  # Returns `true`: `Nil` has only one singleton value: `nil`.
  def same?(other : Nil)
    true
  end

  # Returns `false`.
  def same?(other : Object) : Bool
    false
  end

  # See `Object#hash(hasher)`
  def hash(hasher)
    hasher.nil
  end

  # Returns an empty string.
  def to_s : String
    ""
  end

  # Doesn't write anything to the given `IO`.
  def to_s(io : IO) : Nil
    # Nothing to do
  end

  # Returns `"nil"`.
  def inspect : String
    "nil"
  end

  # Writes `"nil"` to the given `IO`.
  def inspect(io : IO) : Nil
    io << "nil"
  end

  # Doesn't yield to the block.
  #
  # See also: `Object#try`.
  def try(&block)
    self
  end

  # Raises `NilAssertionError`.
  #
  # If *message* is given, it is forwarded as error message of `NilAssertionError`.
  #
  # See also: `Object#not_nil!`.
  def not_nil!(message = nil) : NoReturn
    if message
      raise NilAssertionError.new(message)
    else
      raise NilAssertionError.new
    end
  end

  # Returns `self`.
  # This method enables to call the `presence` method (see `String#presence`) on a union with `Nil`.
  # The idea is to return `nil` when the value is `nil` or empty.
  #
  # ```
  # config = {"empty" => ""}
  # config["empty"]?.presence   # => nil
  # config["missing"]?.presence # => nil
  # ```
  def presence : Nil
    self
  end

  def clone
    self
  end
end
