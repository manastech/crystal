require "./object/properties"

# `Object` is the base type of all Crystal objects.
#
# ## Getters
#
# Multiple macros are available to easily declare, initialize and expose
# instance variables as well as class variables on an `Object` by generating
# simple accessor methods.
#
# For example writing:
#
# ```
# class Person
#   getter name
# end
# ```
#
# Is the same as writing:
#
# ```
# class Person
#   def name
#     @name
#   end
# end
# ```
#
# For class variables we'd have called `class_getter name` that would have
# generated a `def self.name` class method returning `@@name`.
#
# We can define as many variables as necessary in a single call. For example
# `getter name, age, city` will create a getter method for each of `name`, `age`
# and `city`.
#
# ### Type and initial value
#
# Instead of plain arguments, we can specify a type as well as an initial value.
# If the initial value is simple enough Crystal should be able to infer the type
# of the instance or class variable!
#
# Specifying a type will also declare the instance or class variable with said
# type and type the accessor method arguments and return type accordingly.
#
# For example writing:
#
# ```
# class Person
#   getter name : String
#   getter age = 0
#   getter city : String = "unspecified"
# end
# ```
#
# Is the same as writing:
#
# ```
# class Person
#   @name : String
#   @age = 0
#   @city : String = "unspecified"
#
#   def name : String
#     @name
#   end
#
#   def age
#     @age
#   end
#
#   def city : String
#     @city
#   end
# end
# ```
#
# The initial value of an instance variable is automatically set when the object
# is constructed. The initial value of a class variable will be set when the
# program starts up.
#
# ### Lazy initialization
#
# Instead of eagerly initializing the value, we can lazily initialize it the
# first time the accessor method is called.
#
# Since the variable will be lazily initialized the type of the variable will be
# a nilable type. The generated method however will return the specified type
# only (not a nilable).
#
# For example writing:
#
# ```
# class Person
#   getter(city : City) { City.unspecified }
# end
# ```
#
# Is equivalent to writing:
#
# ```
# class Person
#   @city : City?
#
#   def city : City
#     if (city == @city).nil?
#       @city = City.unspecified
#     else
#       city
#     end
#   end
# end
# ```
#
# ### Variants
#
# Please refer to the different variants to understand how they differ from the
# general overview presented above:
#
# - `getter`
# - `getter?`
# - `getter!`
# - `class_getter`
# - `class_getter?`
# - `class_getter!`
#
# ## Setters
#
# The `setter` and `class_setter` macros are the write counterparts of the
# getter macros. They declare `name=(value)` accessor methods. The arguments
# behave just as for the getter macros.
#
# For example writing:
#
# ```
# class Person
#   setter name
#   setter age = 0
#   setter city : String = "unspecified"
# end
# ```
#
# Is the same as writing:
#
# ```
# class Person
#   @age = 0
#   @city : String = "unspecified"
#
#   def name=(@name)
#   end
#
#   def age=(@age)
#   end
#
#   def city=(@city : String) : String
#   end
# end
# ```
#
# For class variables we'd have called `class_setter name` that would have
# generated a `def self.name=(@@name)` class method instead.
#
# ## Properties
#
# The property macros define both getter and setter methods at once.
#
# For example writing:
#
# ```
# class Person
#   property name
# end
# ```
#
# Is equivalent to writing:
#
# ```
# class Person
#   getter name
#   setter name
# end
# ```
#
# Which is the same as writing:
#
# ```
# class Person
#   def name
#     @name
#   end
#
#   def name=(@name)
#   end
# end
# ```
#
# Refer to [Getters](#getters) and [Setters](#setters) above for details. The
# macros take the exact same arguments.
class Object
  # Returns `true` if this object is equal to *other*.
  #
  # Subclasses override this method to provide class-specific meaning.
  abstract def ==(other)

  # Returns `true` if this object is not equal to *other*.
  #
  # By default this method is implemented as `!(self == other)`
  # so there's no need to override this unless there's a more efficient
  # way to do it.
  def !=(other)
    !(self == other)
  end

  # Shortcut to `!(self =~ other)`.
  def !~(other)
    !(self =~ other)
  end

  # Case equality.
  #
  # The `===` method is used in a `case ... when ... end` expression.
  #
  # For example, this code:
  #
  # ```
  # case value
  # when x
  #   # something when x
  # when y
  #   # something when y
  # end
  # ```
  #
  # Is equivalent to this code:
  #
  # ```
  # if x === value
  #   # something when x
  # elsif y === value
  #   # something when y
  # end
  # ```
  #
  # Object simply implements `===` by invoking `==`, but subclasses
  # (notably `Regex`) can override it to provide meaningful case-equality semantics.
  def ===(other)
    self == other
  end

  # Pattern match.
  #
  # Overridden by descendants (notably `Regex` and `String`) to provide meaningful
  # pattern-match semantics.
  def =~(other)
    nil
  end

  # Appends this object's value to *hasher*, and returns the modified *hasher*.
  #
  # Usually the macro `def_hash` can be used to generate this method.
  # Otherwise, invoke `hash(hasher)` on each object's instance variables to
  # accumulate the result:
  #
  # ```
  # def hash(hasher)
  #   hasher = @some_ivar.hash(hasher)
  #   hasher = @some_other_ivar.hash(hasher)
  #   hasher
  # end
  # ```
  abstract def hash(hasher)

  # Generates an `UInt64` hash value for this object.
  #
  # This method must have the property that `a == b` implies `a.hash == b.hash`.
  #
  # The hash value is used along with `==` by the `Hash` class to determine if two objects
  # reference the same hash key.
  #
  # Subclasses must not override this method. Instead, they must define `hash(hasher)`,
  # though usually the macro `def_hash` can be used to generate this method.
  def hash
    hash(Crystal::Hasher.new).result
  end

  # Returns a nicely readable and concise string representation of this object,
  # typically intended for users.
  #
  # This method should usually **not** be overridden. It delegates to
  # `#to_s(IO)` which can be overridden for custom implementations.
  #
  # Also see `#inspect`.
  def to_s : String
    String.build do |io|
      to_s io
    end
  end

  # Prints a nicely readable and concise string representation of this object,
  # typically intended for users, to *io*.
  #
  # This method is called when an object is interpolated in a string literal:
  # ```
  # "foo #{bar} baz" # calls bar.to_io with the builder for this string
  # ```
  #
  # `IO#<<` calls this method to append an object to itself:
  # ```
  # io << bar # calls bar.to_s(io)
  # ```
  #
  # Thus implementations must not interpolate `self` in a string literal or call
  # `io << self` which both would lead to an endless loop.
  #
  # Also see `#inspect(IO)`.
  abstract def to_s(io : IO) : Nil

  # Returns an unambiguous and information-rich string representation of this
  # object, typically intended for developers.
  #
  # This method should usually **not** be overridden. It delegates to
  # `#inspect(IO)` which can be overridden for custom implementations.
  #
  # Also see `#to_s`.
  def inspect : String
    String.build do |io|
      inspect io
    end
  end

  # Prints to *io* an unambiguous and information-rich string representation of this
  # object, typically intended for developers.
  #
  # It is similar to `#to_s(IO)`, but often provides more information. Ideally, it should
  # contain sufficient information to be able to recreate an object with the same value
  # (given an identical environment).
  #
  # For types that don't provide a custom implementation of this method,
  # default implementation delegates to `#to_s(IO)`. This said, it is advisable to
  # have an appropriate `#inspect` implementation on every type. Default
  # implementations are provided by `Struct#inspect` and `Reference#inspect`.
  #
  # `::p` and `::p!` use this method to print an object in `STDOUT`.
  def inspect(io : IO) : Nil
    to_s io
  end

  # Pretty prints `self` into the given printer.
  #
  # By default appends a text that is the result of invoking
  # `#inspect` on `self`. Subclasses should override
  # for custom pretty printing.
  def pretty_print(pp : PrettyPrint) : Nil
    pp.text(inspect)
  end

  # Returns a pretty printed version of `self`.
  def pretty_inspect(width = 79, newline = "\n", indent = 0) : String
    String.build do |io|
      PrettyPrint.format(self, io, width, newline, indent)
    end
  end

  # Yields `self` to the block, and then returns `self`.
  #
  # The primary purpose of this method is to "tap into" a method chain,
  # in order to perform operations on intermediate results within the chain.
  #
  # ```
  # (1..10).tap { |x| puts "original: #{x.inspect}" }
  #   .to_a.tap { |x| puts "array: #{x.inspect}" }
  #   .select { |x| x % 2 == 0 }.tap { |x| puts "evens: #{x.inspect}" }
  #   .map { |x| x*x }.tap { |x| puts "squares: #{x.inspect}" }
  # ```
  def tap(&)
    yield self
    self
  end

  # Yields `self`. `Nil` overrides this method and doesn't yield.
  #
  # This method is useful for dealing with nilable types, to safely
  # perform operations only when the value is not `nil`.
  #
  # ```
  # # First program argument in downcase, or nil
  # ARGV[0]?.try &.downcase
  # ```
  def try(&)
    yield self
  end

  # Returns `true` if `self` is included in the *collection* argument.
  #
  # ```
  # 10.in?(0..100)     # => true
  # 10.in?({0, 1, 10}) # => true
  # 10.in?(0, 1, 10)   # => true
  # 10.in?(:foo, :bar) # => false
  # ```
  def in?(collection : Object) : Bool
    collection.includes?(self)
  end

  # :ditto:
  def in?(*values : Object) : Bool
    in?(values)
  end

  # Returns `self`.
  #
  # `Nil` overrides this method and raises `NilAssertionError`, see `Nil#not_nil!`.
  #
  # This method can be used to remove `Nil` from a union type.
  # However, it should be avoided if possible and is often considered a code smell.
  # Usually, you can write code in a way that the compiler can safely exclude `Nil` types,
  # for example using [`if var`](https://crystal-lang.org/reference/syntax_and_semantics/if_var.html).
  # `not_nil!` is only meant as a last resort when there's no other way to explain this to the compiler.
  # Either way, consider instead raising a concrete exception with a descriptive message.
  def not_nil!
    self
  end

  # :ditto:
  #
  # *message* has no effect. It is only used by `Nil#not_nil!(message = nil)`.
  def not_nil!(message)
    # FIXME: the above param-less overload cannot be expressed as an optional
    # parameter here, because that would copy the receiver if it is a struct;
    # see https://github.com/crystal-lang/crystal/issues/13263#issuecomment-1492885817
    # and also #13265
    self
  end

  # Returns `self`.
  #
  # ```
  # str = "hello"
  # str.itself.object_id == str.object_id # => true
  # ```
  def itself
    self
  end

  # Returns a shallow copy (“duplicate”) of this object.
  #
  # In order to create a new object with the same value as an existing one, there
  # are two possible routes:
  #
  # * create a *shallow copy* (`#dup`): Constructs a new object with all its
  #   properties' values identical to the original object's properties. They
  #   are shared references. That means for mutable values that changes to
  #   either object's values will be present in both's.
  # * create a *deep copy* (`#clone`): Constructs a new object with all its
  #   properties' values being recursive deep copies of the original object's
  #   properties.
  #   There is no shared state and the new object is a completely independent
  #   copy, including everything inside it. This may not be available for every
  #   type.
  #
  # A shallow copy is only one level deep whereas a deep copy copies everything
  # below.
  #
  # This distinction is only relevant for compound values. Primitive types
  # do not have any properties that could be shared or cloned.
  # In that case, `dup` and `clone` are exactly the same.
  #
  # The `#clone` method can't be defined on `Object`. It's not
  # generically available for every type because cycles could be involved, and
  # the clone logic might not need to clone everything.
  #
  # Many types in the standard library, like `Array`, `Hash`, `Set` and
  # `Deque`, and all primitive types, define `dup` and `clone`.
  #
  # Example:
  #
  # ```
  # original = {"foo" => [1, 2, 3]}
  # shallow_copy = original.dup
  # deep_copy = original.clone
  #
  # # "foo" references the same array object for both original and shallow copy,
  # # but not for a deep copy:
  # original["foo"] << 4
  # shallow_copy["foo"] # => [1, 2, 3, 4]
  # deep_copy["foo"]    # => [1, 2, 3]
  #
  # # Assigning new value does not share it to either copy:
  # original["foo"] = [1]
  # shallow_copy["foo"] # => [1, 2, 3, 4]
  # deep_copy["foo"]    # => [1, 2, 3]
  # ```
  abstract def dup

  # Unsafely reinterprets the bytes of an object as being of another `type`.
  #
  # This method is useful to treat a type that is represented as a chunk of
  # bytes as another type where those bytes convey useful information. As an
  # example, you can check the individual bytes of an `Int32`:
  #
  # ```
  # 0x01020304.unsafe_as(StaticArray(UInt8, 4)) # => StaticArray[4, 3, 2, 1]
  # ```
  #
  # Or treat the bytes of a `Float64` as an `Int64`:
  #
  # ```
  # 1.234_f64.unsafe_as(Int64) # => 4608236261112822104
  # ```
  #
  # This method is **unsafe** because it behaves unpredictably when the given
  # `type` doesn't have the same bytesize as the receiver, or when the given
  # `type` representation doesn't semantically match the underlying bytes.
  #
  # Also note that because `unsafe_as` is a regular method, unlike the pseudo-method
  # `as`, you can't specify some types in the type grammar using a short notation, so
  # specifying a static array must always be done as `StaticArray(T, N)`, a tuple
  # as `Tuple(...)` and so on, never as `UInt8[4]` or `{Int32, Int32}`.
  def unsafe_as(type : T.class) forall T
    x = self
    pointerof(x).as(T*).value
  end

  # Delegate *methods* to *to*.
  #
  # Note that due to current language limitations this is only useful
  # when no captured blocks are involved.
  #
  # ```
  # class StringWrapper
  #   def initialize(@string : String)
  #   end
  #
  #   delegate downcase, to: @string
  #   delegate gsub, to: @string
  #   delegate empty?, capitalize, to: @string
  #   delegate :[], to: @string
  # end
  #
  # wrapper = StringWrapper.new "HELLO"
  # wrapper.downcase       # => "hello"
  # wrapper.gsub(/E/, "A") # => "HALLO"
  # wrapper.empty?         # => false
  # wrapper.capitalize     # => "Hello"
  # ```
  macro delegate(*methods, to object)
    {% if compare_versions(::Crystal::VERSION, "1.12.0-dev") >= 0 %}
      {% eq_operators = %w(<= >= == != []= ===) %}
      {% for method in methods %}
        {% if method.id.ends_with?('=') && !eq_operators.includes?(method.id.stringify) %}
          def {{method.id}}(arg)
            {{object.id}}.{{method.id}} arg
          end
        {% else %}
          def {{method.id}}(*args, **options)
            {{object.id}}.{{method.id}}(*args, **options)
          end

          def {{method.id}}(*args, **options)
            {{object.id}}.{{method.id}}(*args, **options) do |*yield_args|
              yield *yield_args
            end
          end
        {% end %}
      {% end %}
    {% else %}
      {% for method in methods %}
        {% if method.id.ends_with?('=') && method.id != "[]=" %}
          def {{method.id}}(arg)
            {{object.id}}.{{method.id}} arg
          end
        {% else %}
          def {{method.id}}(*args, **options)
            {{object.id}}.{{method.id}}(*args, **options)
          end

          {% if method.id != "[]=" %}
            def {{method.id}}(*args, **options)
              {{object.id}}.{{method.id}}(*args, **options) do |*yield_args|
                yield *yield_args
              end
            end
          {% end %}
        {% end %}
      {% end %}
    {% end %}
  end

  # Defines a `hash(hasher)` that will append a hash value for the given fields.
  #
  # ```
  # class Person
  #   def initialize(@name, @age)
  #   end
  #
  #   # Define a hash(hasher) method based on @name and @age
  #   def_hash @name, @age
  # end
  # ```
  macro def_hash(*fields)
    def hash(hasher)
      {% for field in fields %}
        hasher = {{field.id}}.hash(hasher)
      {% end %}
      hasher
    end
  end

  # Defines an `==` method by comparing the given fields.
  #
  # The generated `==` method has a `self` restriction.
  # For classes it will first compare by reference and return `true`
  # when an object instance is compared with itself, without comparing
  # any of the fields.
  #
  # ```
  # class Person
  #   def initialize(@name, @age)
  #   end
  #
  #   # Define a `==` method that compares @name and @age
  #   def_equals @name, @age
  # end
  # ```
  macro def_equals(*fields)
    def ==(other : self)
      {% if @type.class? %}
        return true if same?(other)
      {% end %}
      {% for field in fields %}
        return false unless {{field.id}} == other.{{field.id}}
      {% end %}
      true
    end
  end

  # Defines `hash` and `==` method from the given fields.
  #
  # The generated `==` method has a `self` restriction.
  #
  # ```
  # class Person
  #   def initialize(@name, @age)
  #   end
  #
  #   # Define a hash method based on @name and @age
  #   # Define a `==` method that compares @name and @age
  #   def_equals_and_hash @name, @age
  # end
  # ```
  macro def_equals_and_hash(*fields)
    def_equals {{fields.splat}}
    def_hash {{fields.splat}}
  end

  # Forwards missing methods to *delegate*.
  #
  # ```
  # class StringWrapper
  #   def initialize(@string : String)
  #   end
  #
  #   forward_missing_to @string
  # end
  #
  # wrapper = StringWrapper.new "HELLO"
  # wrapper.downcase       # => "hello"
  # wrapper.gsub(/E/, "A") # => "HALLO"
  # ```
  macro forward_missing_to(delegate)
    macro method_missing(call)
      {{delegate}}.\{{call}}
    end
  end

  # Defines a `clone` method that returns a copy of this object with all
  # instance variables cloned (`clone` is in turn invoked on them).
  macro def_clone
    # Returns a copy of `self` with all instance variables cloned.
    def clone
      \{% if @type < ::Reference && !@type.instance_vars.map(&.type).all? { |t| t == ::Bool || t == ::Char || t == ::Symbol || t == ::String || t < ::Number::Primitive } %}
        exec_recursive_clone do |hash|
          clone = \{{@type}}.allocate
          hash[object_id] = clone.object_id
          clone.initialize_copy(self)
          ::GC.add_finalizer(clone) if clone.responds_to?(:finalize)
          clone
        end
      \{% else %}
        clone = \{{@type}}.allocate
        clone.initialize_copy(self)
        ::GC.add_finalizer(clone) if clone.responds_to?(:finalize)
        clone
      \{% end %}
    end

    protected def initialize_copy(other)
      \{% for ivar in @type.instance_vars %}
        @\{{ivar.id}} = other.@\{{ivar.id}}.clone
      \{% end %}
    end
  end

  protected def self.set_crystal_type_id(ptr)
    ptr.as(Pointer(typeof(crystal_instance_type_id))).value = crystal_instance_type_id
    ptr
  end
end
