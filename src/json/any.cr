# `JSON::Any` is a convenient wrapper around all possible JSON types (`JSON::Any::Type`)
# and can be used for traversing dynamic or unknown JSON structures.
#
# ```
# require "json"
#
# obj = JSON.parse(%({"access": [{"name": "mapping", "speed": "fast"}, {"name": "any", "speed": "slow"}]}))
# obj["access"][1]["name"].as_s  # => "any"
# obj["access"][1]["speed"].as_s # => "slow"
# ```
#
# Note that methods used to traverse a JSON structure, `#[]` and `#[]?`,
# always return a `JSON::Any` to allow further traversal. To convert them to `String`,
# `Int32`, etc., use the `as_` methods, such as `#as_s`, `#as_i`, which perform
# a type check against the raw underlying value. This means that invoking `#as_s`
# when the underlying value is not a String will raise: the value won't automatically
# be converted (parsed) to a `String`. There are also nil-able variants (`#as_i?`, `#as_s?`, ...),
# which return `nil` when the underlying value type won't match.
struct JSON::Any
  # All possible JSON types.
  alias Type = Nil | Bool | Int64 | Float64 | String | Array(JSON::Any) | Hash(String, JSON::Any) | Int128

  # Reads a `JSON::Any` value from the given pull parser.
  def self.new(pull : JSON::PullParser)
    case pull.kind
    when .null?
      new pull.read_null
    when .bool?
      new pull.read_bool
    when .int?
      new pull.read_int
    when .float?
      new pull.read_float
    when .int_as_string?
      new pull.read_int_as_string
    when .string?
      new pull.read_string
    when .begin_array?
      ary = [] of JSON::Any
      pull.read_array do
        ary << new(pull)
      end
      new ary
    when .begin_object?
      hash = {} of String => JSON::Any
      pull.read_object do |key|
        hash[key] = new(pull)
      end
      new hash
    else
      raise "Unknown pull kind: #{pull.kind}"
    end
  end

  # Returns the raw underlying value.
  getter raw : Type

  # Creates a `JSON::Any` that wraps the given value.
  def initialize(@raw : Type)
  end

  # :ditto:
  def self.new(raw : Int)
    # FIXME: Workaround for https://github.com/crystal-lang/crystal/issues/11645
    new(raw.to_i64)
  end

  # :ditto:
  def self.new(raw : Float)
    # FIXME: Workaround for https://github.com/crystal-lang/crystal/issues/11645
    new(raw.to_f64)
  end

  # Assumes the underlying value is an `Array` or `Hash` and returns its size.
  # Raises if the underlying value is not an `Array` or `Hash`.
  def size : Int
    case object = @raw
    when Array, Hash
      object.size
    else
      raise "Expected Array or Hash for #size, not #{object.class}"
    end
  end

  # Assumes the underlying value is an `Array` and returns the element
  # at the given index.
  # Raises if the underlying value is not an `Array`.
  def [](index : Int) : JSON::Any
    case object = @raw
    when Array
      object[index]
    else
      raise "Expected Array for #[](index : Int), not #{object.class}"
    end
  end

  # Assumes the underlying value is an `Array` and returns the element
  # at the given index, or `nil` if out of bounds.
  # Raises if the underlying value is not an `Array`.
  def []?(index : Int) : JSON::Any?
    case object = @raw
    when Array
      object[index]?
    else
      raise "Expected Array for #[]?(index : Int), not #{object.class}"
    end
  end

  # Assumes the underlying value is a `Hash` and returns the element
  # with the given key.
  # Raises if the underlying value is not a `Hash`.
  def [](key : String) : JSON::Any
    case object = @raw
    when Hash
      object[key]
    else
      raise "Expected Hash for #[](key : String), not #{object.class}"
    end
  end

  # Assumes the underlying value is a `Hash` and returns the element
  # with the given key, or `nil` if the key is not present.
  # Raises if the underlying value is not a `Hash`.
  def []?(key : String) : JSON::Any?
    case object = @raw
    when Hash
      object[key]?
    else
      raise "Expected Hash for #[]?(key : String), not #{object.class}"
    end
  end

  # Traverses the depth of a structure and returns the value.
  # Returns `nil` if not found.
  def dig?(index_or_key : String | Int, *subkeys) : JSON::Any?
    self[index_or_key]?.try &.dig?(*subkeys)
  end

  # :nodoc:
  def dig?(index_or_key : String | Int) : JSON::Any?
    case @raw
    when Hash, Array
      self[index_or_key]?
    else
      nil
    end
  end

  # Traverses the depth of a structure and returns the value, otherwise raises.
  def dig(index_or_key : String | Int, *subkeys) : JSON::Any
    self[index_or_key].dig(*subkeys)
  end

  # :nodoc:
  def dig(index_or_key : String | Int) : JSON::Any
    self[index_or_key]
  end

  # Checks that the underlying value is `Nil`, and returns `nil`.
  # Raises otherwise.
  def as_nil : Nil
    @raw.as(Nil)
  end

  # Checks that the underlying value is `Bool`, and returns its value.
  # Raises otherwise.
  def as_bool : Bool
    @raw.as(Bool)
  end

  # Checks that the underlying value is `Bool`, and returns its value.
  # Returns `nil` otherwise.
  def as_bool? : Bool?
    as_bool if @raw.is_a?(Bool)
  end

  # Checks that the underlying value is `Int`, and returns its value as an `Int32`.
  # Raises otherwise.
  def as_i : Int32
    @raw.as(Int).to_i
  end

  # Checks that the underlying value is `Int`, and returns its value as an `Int32`.
  # Returns `nil` otherwise.
  def as_i? : Int32?
    as_i if @raw.is_a?(Int)
  end

  # Checks that the underlying value is `Int`, and returns its value as an `Int64`.
  # Raises otherwise.
  def as_i64 : Int64
    @raw.as(Int).to_i64
  end

  # Checks that the underlying value is `Int`, and returns its value as an `Int64`.
  # Returns `nil` otherwise.
  def as_i64? : Int64?
    as_i64 if @raw.is_a?(Int64)
  end

  # Checks that the underlying value is `Int`, and returns its value as an `Int128`.
  # Raises otherwise.
  def as_i128 : Int128
    @raw.as(String).to_i128
  end

  # Checks that the underlying value is `Int`, and returns its value as an `Int128`.
  # Returns `nil` otherwise.
  def as_i128? : Int128?
    as_i128 if @raw.is_a?(Int128)
  end

  # Checks that the underlying value is `Float` (or `Int`), and returns its value as an `Float64`.
  # Raises otherwise.
  def as_f : Float64
    case raw = @raw
    when Int
      raw.to_f
    else
      raw.as(Float64)
    end
  end

  # Checks that the underlying value is `Float` (or `Int`), and returns its value as an `Float64`.
  # Returns `nil` otherwise.
  def as_f? : Float64?
    case raw = @raw
    when Int
      raw.to_f
    else
      raw.as?(Float64)
    end
  end

  # Checks that the underlying value is `Float` (or `Int`), and returns its value as an `Float32`.
  # Raises otherwise.
  def as_f32 : Float32
    case raw = @raw
    when Int
      raw.to_f32
    else
      raw.as(Float).to_f32
    end
  end

  # Checks that the underlying value is `Float` (or `Int`), and returns its value as an `Float32`.
  # Returns `nil` otherwise.
  def as_f32? : Float32?
    case raw = @raw
    when Int
      raw.to_f32
    when Float
      raw.to_f32
    else
      nil
    end
  end

  # Checks that the underlying value is `String`, and returns its value.
  # Raises otherwise.
  def as_s : String
    @raw.as(String)
  end

  # Checks that the underlying value is `String`, and returns its value.
  # Returns `nil` otherwise.
  def as_s? : String?
    as_s if @raw.is_a?(String)
  end

  # Checks that the underlying value is `Array`, and returns its value.
  # Raises otherwise.
  def as_a : Array(JSON::Any)
    @raw.as(Array)
  end

  # Checks that the underlying value is `Array`, and returns its value.
  # Returns `nil` otherwise.
  def as_a? : Array(JSON::Any)?
    as_a if @raw.is_a?(Array)
  end

  # Checks that the underlying value is `Hash`, and returns its value.
  # Raises otherwise.
  def as_h : Hash(String, JSON::Any)
    @raw.as(Hash)
  end

  # Checks that the underlying value is `Hash`, and returns its value.
  # Returns `nil` otherwise.
  def as_h? : Hash(String, JSON::Any)?
    as_h if @raw.is_a?(Hash)
  end

  def inspect(io : IO) : Nil
    @raw.inspect(io)
  end

  def to_s(io : IO) : Nil
    @raw.to_s(io)
  end

  # :nodoc:
  def pretty_print(pp)
    @raw.pretty_print(pp)
  end

  # Returns `true` if both `self` and *other*'s raw object are equal.
  def ==(other : JSON::Any)
    raw == other.raw
  end

  # Returns `true` if the raw object is equal to *other*.
  def ==(other)
    raw == other
  end

  # See `Object#hash(hasher)`
  def_hash raw

  # :nodoc:
  def to_json(json : JSON::Builder)
    raw.to_json(json)
  end

  def to_yaml(yaml : YAML::Nodes::Builder) : Nil
    raw.to_yaml(yaml)
  end

  # Returns a new JSON::Any instance with the `raw` value `dup`ed.
  def dup
    JSON::Any.new(raw.dup)
  end

  # Returns a new JSON::Any instance with the `raw` value `clone`ed.
  def clone
    JSON::Any.new(raw.clone)
  end
end

class Object
  def ===(other : JSON::Any)
    self === other.raw
  end
end

struct Value
  def ==(other : JSON::Any)
    self == other.raw
  end
end

class Reference
  def ==(other : JSON::Any)
    self == other.raw
  end
end

class Array
  def ==(other : JSON::Any)
    self == other.raw
  end
end

class Hash
  def ==(other : JSON::Any)
    self == other.raw
  end
end

class Regex
  def ===(other : JSON::Any)
    value = self === other.raw
    $~ = $~
    value
  end
end
