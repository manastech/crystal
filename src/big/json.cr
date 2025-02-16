require "json"
require "big"

class JSON::Builder
  # Writes a big decimal.
  def number(number : BigDecimal) : Nil
    scalar do
      @io << number
    end
  end
end

struct BigInt
  def self.new(pull : JSON::PullParser)
    case pull.kind
    when .int?, .int_as_string?
      value = pull.raw_value
      pull.read_next.int_as_string?
    else
      p "hi"
      value = pull.read_string
    end
    new(value)
  end

  def self.from_json_object_key?(key : String) : BigInt?
    new(key)
  rescue ArgumentError
    nil
  end

  def to_json_object_key : String
    to_s
  end

  def to_json(json : JSON::Builder) : Nil
    json.number(self)
  end
end

struct BigFloat
  def self.new(pull : JSON::PullParser)
    case pull.kind
    when .int?, .float?, .int_as_string?
      value = pull.raw_value
      pull.read_next
    else
      value = pull.read_string
    end
    new(value)
  end

  def self.from_json_object_key?(key : String) : BigFloat?
    new(key)
  rescue ArgumentError
    nil
  end

  def to_json_object_key
    to_s
  end

  def to_json(json : JSON::Builder) : Nil
    json.number(self)
  end
end

struct BigDecimal
  def self.new(pull : JSON::PullParser)
    case pull.kind
    when .int?, .float?, .int_as_string?
      value = pull.raw_value
      pull.read_next
    else
      value = pull.read_string
    end
    new(value)
  end

  def self.from_json_object_key?(key : String) : BigDecimal?
    new(key)
  rescue InvalidBigDecimalException
    nil
  end

  def to_json_object_key
    to_s
  end

  def to_json(json : JSON::Builder) : Nil
    json.number(self)
  end
end
