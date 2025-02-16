# This class allows you to consume JSON on demand, token by token.
#
# Each *read_** method consumes the next token.
# Sometimes it consumes only one token (like `read_begin_array`), sometimes it consumes a full valid value (like `read_array`).
#
# You must be careful when calling those methods, as they move forward into the JSON input you are pulling.
# Calling `read_string` twice will return the next two strings (if possible), not twice the same.
#
# If you try to read a token which is not the one currently under the cursor location, an exception `ParseException` will be raised.
#
# Example:
# ```
# input = %(
#   {
#     "type": "event",
#     "values": [1, 4, "three", 10]
#   }
# )
# pull = JSON::PullParser.new(input)
# pull.read_begin_object
# pull.read_object_key # => "type"
# pull.read_string     # => "event"
# # Actually you can also use `read_string` to read a key
# pull.read_string # => "values"
# pull.read_begin_array
# pull.read_int    # => 1
# pull.read_int    # => 4
# pull.read_string # => "three"
# pull.read_int    # => 10
# pull.read_end_array
# pull.read_end_object
# ```
#
# Another example reading the same object:
# ```
# pull = JSON::PullParser.new(input)
# pull.read_object do |key|
#   case key
#   when "type"
#     pull.read_string # => "event"
#   when "values"
#     pull.read_array do
#       if v = pull.read?(Int8)
#         v
#       else
#         pull.read_string
#       end
#     end
#   end
# end
# ```
#
# This example fails:
# ```
# pull = JSON::PullParser.new(input)
# pull.read_begin_object
# pull.read_object_key # => "type"
# pull.read_string     # => "event"
# pull.read_end_object # => raise an exception. The current token is a string ("values"), not the end of an object.
# ```
class JSON::PullParser
  enum Kind
    Null
    Bool
    Int
    Float
    String
    BeginArray
    EndArray
    BeginObject
    EndObject
    EOF
    IntAsString
  end

  private enum ObjectStackKind
    Object
    Array
  end

  getter kind : Kind
  getter bool_value : Bool

  def int_value : Int64
    token.int_value
  end

  def int_as_string_value : String
    token.int_as_string_value
  end

  def float_value : Float64
    token.float_value
  end

  getter string_value : String
  getter raw_value : String

  property max_nesting = 512

  # Creates a PullParser which will consume the JSON *input*.
  #
  # *input* must be a `String` or an `IO`.
  def initialize(input)
    @lexer = Lexer.new input
    @kind = :EOF
    @bool_value = false
    @string_value = ""
    @raw_value = ""
    @object_stack = [] of ObjectStackKind
    @skip_count = 0
    @location = {0, 0}

    next_token
    case token.kind
    in .null?
      @kind = :null
    in .false?
      @kind = :bool
      @bool_value = false
    in .true?
      @kind = :bool
      @bool_value = true
    in .int?
      @kind = :int
      @raw_value = token.raw_value
    in .float?
      @kind = :float
      @raw_value = token.raw_value
    in .string?
      @kind = :string
      @string_value = token.string_value
    in .int_as_string?
      @kind = :int_as_string
      @raw_value = token.raw_value
    in .begin_array?
      begin_array
    in .begin_object?
      begin_object
    in .eof?
      @kind = :eof
    in .end_array?, .end_object?, .comma?, .colon?
      unexpected_token
    end
  end

  # Reads the beginning of an array.
  def read_begin_array
    expect_kind :begin_array
    read_next
  end

  # Reads the end of an array.
  def read_end_array
    expect_kind :end_array
    read_next
  end

  # Reads a whole array.
  #
  # It reads the beginning of the array, yield each value of the array, and reads the end of the array.
  # You have to consumes the values, if any, so the pull parser does not fail when reading the end of the array.
  #
  # If the array is empty, it does not yield.
  def read_array(&)
    read_begin_array
    until kind.end_array?
      yield
    end
    read_end_array
  end

  # Reads the beginning of an object.
  def read_begin_object
    expect_kind :begin_object
    read_next
  end

  # Reads the end of an object.
  def read_end_object
    expect_kind :end_object
    read_next
  end

  # Reads an object's key and returns it.
  def read_object_key : String
    read_string
  end

  # Reads a whole object.
  #
  # It reads the beginning of the object, yield each key and key location, and reads the end of the object.
  # You have to consumes the values, if any, so the pull parser does not fail when reading the end of the object.
  #
  # If the object is empty, it does not yield.
  def read_object(&)
    read_begin_object
    until kind.end_object?
      key_location = location
      key = read_object_key
      yield key, key_location
    end
    read_end_object
  end

  # Reads a null value and returns it.
  def read_null : Nil
    expect_kind :null
    read_next
    nil
  end

  # Reads a `Bool` value.
  def read_bool : Bool
    expect_kind :bool
    @bool_value.tap { read_next }
  end

  # Reads an integer value.
  def read_int : Int64
    expect_kind :int
    int_value.tap { read_next }
  end

  # Reads a float value.
  #
  # If the value is actually an integer, it is converted to float.
  def read_float : Float64
    case @kind
    when .int?
      int_value.to_f.tap { read_next }
    when .float?
      float_value.tap { read_next }
    else
      raise "Expecting int or float but was #{@kind}"
    end
  end

  # Read the next value and returns it.
  #
  # The value is returned as a json string.
  # If the value is an array or an object, it returns a string representing the full value.
  # If the value in unknown, it raises a `ParseException`.
  #
  # ```
  # pull = JSON::PullParser.new %([null, true, 1, "foo", [1, "two"], {"foo": "bar"}])
  # pull.read_begin_array
  # pull.read_raw # => "null"
  # pull.read_raw # => "true"
  # pull.read_raw # => "1"
  # pull.read_raw # => "\"foo\""
  # pull.read_raw # => "[1,\"two\"]"
  # pull.read_raw # => "{\"foo\":\"bar\"}"
  # pull.read_end_array
  # ```
  def read_raw : String
    case @kind
    when .null?
      read_next
      "null"
    when .bool?
      @bool_value.to_s.tap { read_next }
    when .int?, .float?, .int_as_string?
      @raw_value.tap { read_next }
    when .string?
      @string_value.to_json.tap { read_next }
    when .begin_array?
      JSON.build { |json| read_raw(json) }
    when .begin_object?
      JSON.build { |json| read_raw(json) }
    else
      unexpected_token
    end
  end

  # Reads the new value and fill the a JSON builder with it.
  #
  # Use this method with a `JSON::Builder` to read a JSON while building another one.
  def read_raw(json) : Nil
    case @kind
    when .null?
      read_next
      json.null
    when .bool?
      json.bool(@bool_value)
      read_next
    when .int?, .float?
      json.raw(@raw_value)
      read_next
    when .string?, .int_as_string?
      json.string(@string_value)
      read_next
    when .begin_array?
      json.array do
        read_begin_array
        until kind.end_array?
          read_raw(json)
        end
        read_end_array
      end
    when .begin_object?
      json.object do
        read_begin_object
        until kind.end_object?
          json.string(@string_value)
          read_object_key
          read_raw(json)
        end
        read_end_object
      end
    else
      unexpected_token
    end
  end

  # Reads a int_as_string and returns it.
  def read_int_as_string : String
    expect_kind :int_as_string
    @string_value.tap { read_next }
  end

  # Reads a string and returns it.
  def read_string : String
    expect_kind :string
    @string_value.tap { read_next }
  end

  # Reads a `Bool` or a null value, and returns it.
  def read_bool_or_null : Bool?
    read_null_or { read_bool }
  end

  # Reads an integer or a null value, and returns it.
  def read_int_or_null : Int64?
    read_null_or { read_int }
  end

  # Reads a float or a null value, and returns it.
  def read_float_or_null : Float64?
    read_null_or { read_float }
  end

  # Reads a string or a null value, and returns it.
  def read_string_or_null : String?
    read_null_or { read_string }
  end

  # Reads an array or a null value, and returns it.
  def read_array_or_null(&)
    read_null_or { read_array { yield } }
  end

  # Reads an object or a null value, and returns it.
  def read_object_or_null(&)
    read_null_or { read_object { |key| yield key } }
  end

  # Reads a null value and returns it, or executes the given block if the value is not null.
  def read_null_or(&)
    unless read_null?
      yield
    end
  end

  # Reads the current token if its value is null.
  #
  # Returns `true` if the token was read.
  def read_null? : Bool
    if @kind.null?
      read_next
      true
    else
      false
    end
  end

  # Reads an object keys and yield when *key* is found.
  #
  # All the other object keys are skipped.
  #
  # Returns the return value of the block or `Nil` if the key was not read.
  def on_key(key, & : self -> _)
    result = nil
    read_object do |some_key|
      if some_key == key
        result = yield self
      else
        skip
      end
    end
    result
  end

  # Reads an object keys and yield when *key* is found. If not found, raise an `Exception`.
  #
  # All the other object keys are skipped.
  #
  # Returns the return value of the block.
  def on_key!(key, & : self -> _)
    found = false
    value = uninitialized typeof(yield self)

    read_object do |some_key|
      if some_key == key
        found = true
        value = yield self
      else
        skip
      end
    end

    unless found
      raise "JSON key not found: #{key}"
    end

    value
  end

  # Reads the next lexer's token.
  #
  # Contrary to `read_raw`, it does not read a full value.
  # For example if the next token is the beginning of an array, it will stop there, while `read_raw` would have read the whole array.
  def read_next : Kind
    read_next_internal
    @kind
  end

  # Reads a `Bool` value and returns it.
  #
  # If the value is not a `Bool`, returns `nil`.
  def read?(klass : Bool.class) : Bool?
    read_bool if kind.bool?
  end

  {% begin %}
    # types that don't fit into `Int64` (integer type for `JSON::Any`)'s range
    {% large_ints = [UInt64, Int128, UInt128] %}

    {% for int in Int::Primitive.union_types %}
      {% is_large_int = large_ints.includes?(int) %}

      # Reads an `{{int}}` value and returns it.
      #
      # If the value is not an integer or does not fit in an `{{int}}`, it
      # returns `nil`.
      def read?(klass : {{int}}.class) : {{int}}?
        if kind.int?
          {{int}}.new({{ is_large_int ? "raw_value".id : "int_value".id }}).tap { read_next }
        end
      rescue JSON::ParseException | {{ is_large_int ? ArgumentError : OverflowError }}
        nil
      end
    {% end %}
  {% end %}

  # Reads an `Float32` value and returns it.
  #
  # If the value is not an integer or does not fit in an `Float32`, it returns `nil`.
  # If the value was actually an integer, it is converted to a float.
  def read?(klass : Float32.class) : Float32?
    return read_int.to_f32 if kind.int?
    return raw_value.to_f32.tap { read_next } if kind.float?
  rescue exc : JSON::ParseException | ArgumentError
    nil
  end

  # Reads an `Float64` value and returns it.
  #
  # If the value is not an integer or does not fit in a `Float64` variable, it returns `nil`.
  # If the value was actually an integer, it is converted to a float.
  def read?(klass : Float64.class) : Float64?
    return read_int.to_f64 if kind.int?
    return read_float.to_f64 if kind.float?
  rescue JSON::ParseException
    nil
  end

  # Reads a `String` value and returns it.
  #
  # If the value is not a `String`, returns `nil`.
  def read?(klass : String.class) : String?
    read_string if kind.string?
  end

  private def read_next_internal
    current_kind = @kind

    while true
      case token.kind
      when .null?
        @kind = :null
        next_token_after_value
        return
      when .true?
        @kind = :bool
        @bool_value = true
        next_token_after_value
        return
      when .false?
        @kind = :bool
        @bool_value = false
        next_token_after_value
        return
      when .int?
        @kind = :int
        @raw_value = token.raw_value
        next_token_after_value
        return
      when .float?
        @kind = :float
        @raw_value = token.raw_value
        next_token_after_value
        return
      when .int_as_string?
        @kind = :int_as_string
        @raw_value = token.raw_value
        next_token_after_value
        return
      when .string?
        @kind = :string
        @string_value = token.string_value
        if current_kind.begin_object?
          unless next_token.kind.colon?
            unexpected_token
          end
        else
          next_token_after_value
        end
        return
      when .begin_array?
        begin_array
        return
      when .end_array?
        @kind = :end_array
        next_token_after_array_or_object
        return
      when .begin_object?
        begin_object
        return
      when .end_object?
        @kind = :end_object
        next_token_after_array_or_object
        return
      when .comma?
        obj = current_object()

        @lexer.skip = false if @skip_count == 1

        if obj.try(&.object?)
          next_token_expect_object_key
        else
          next_token
        end

        @lexer.skip = true if @skip_count == 1

        case token.kind
        when .comma?, .end_array?, .end_object?, .eof?
          unexpected_token
        else
          # okay
        end

        if obj.try(&.object?) && token.kind.string?
          @kind = :string
          @string_value = token.string_value
          unless next_token.kind.colon?
            unexpected_token
          end
          return
        end
      when .colon?
        case next_token.kind
        when .comma?, .colon?, .end_array?, .end_object?, .eof?
          unexpected_token
        else
          # okay
        end
      when .eof?
        @kind = :EOF
        return
      else
        unexpected_token
      end
    end
  end

  # Skips the next value.
  #
  # It skips the whole value, not only the next lexer's token.
  # For example if the next value is an array, the whole array will be skipped.
  def skip : Nil
    @lexer.skip = true
    skip_internal
    @lexer.skip = false
  end

  # Returns the current line number.
  def line_number
    @location[0]
  end

  # Returns the current column number.
  def column_number
    @location[1]
  end

  # Returns the current location.
  #
  # The location is a tuple `{line number, column number}`.
  def location : Tuple(Int32, Int32)
    @location
  end

  private def skip_internal
    @skip_count += 1
    case @kind
    when .null?, .bool?, .int?, .float?, .string?, .int_as_string?
      read_next
    when .begin_array?
      @skip_count += 1
      read_begin_array
      until kind.end_array?
        skip_internal
      end
      @skip_count -= 1
      read_end_array
    when .begin_object?
      @skip_count += 1
      read_begin_object
      until kind.end_object?
        read_object_key
        skip_internal
      end
      @skip_count -= 1
      read_end_object
    else
      unexpected_token
    end
    @skip_count -= 1
  end

  private def begin_array
    @kind = :begin_array
    push_in_object_stack :array

    case next_token.kind
    when .comma?, .end_object?, .colon?, .eof?
      unexpected_token
    else
      # okay
    end
  end

  private def begin_object
    @kind = :begin_object
    push_in_object_stack :object

    case next_token_expect_object_key.kind
    when .string?, .end_object?
      # OK
    else
      unexpected_token
    end
  end

  private def current_object
    @object_stack.last?
  end

  private def token
    @lexer.token
  end

  private def next_token
    @location = {@lexer.token.line_number, @lexer.token.column_number}
    @lexer.next_token
  end

  private def next_token_expect_object_key
    @location = {@lexer.token.line_number, @lexer.token.column_number}
    @lexer.next_token_expect_object_key
  end

  private def next_token_after_value
    case next_token.kind
    when .comma?, .end_array?, .end_object?
      # Ok
    else
      if @object_stack.empty?
        @kind = :EOF
      else
        unexpected_token
      end
    end
  end

  private def next_token_after_array_or_object
    unless @object_stack.pop?
      unexpected_token
    end
    case next_token.kind
    when .comma?, .end_array?, .end_object?
      # OK
    when .eof?
      unless @object_stack.empty?
        unexpected_token
      end
    else
      unexpected_token
    end
  end

  private def expect_kind(kind : Kind)
    raise "Expected #{kind} but was #{@kind}" unless @kind == kind
  end

  private def unexpected_token
    raise "Unexpected token: #{token}"
  end

  # Raises `ParseException` with *message* at current location.
  def raise(message : String) : NoReturn
    ::raise ParseException.new(message, token.line_number, token.column_number)
  end

  private def push_in_object_stack(kind : ObjectStackKind)
    if @object_stack.size >= @max_nesting
      raise "Nesting of #{@object_stack.size + 1} is too deep"
    end

    @object_stack.push(kind)
  end
end
