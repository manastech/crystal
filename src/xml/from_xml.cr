require "uuid"

def Object.from_xml(string : String)
  new XML::PullParser.new string
end

def Array.from_xml(stirng : String) : Nil
  parser = XML::PullParser.new string
  new(parser) do |reader|
    yield reader
  end
  nil
end

def Array.new(parser : XML::PullParser)
  parser.read_array
end

def Enum.new(reader : XML::Reader)
  puts "TODO: EMUN"
end

module Iterator(T)
  def self.from_xml(string_or_io)
    puts "FROM XML"
    iterator(T).new(XML::Reader.new(string_or_io))
  end

  def self.new(reader : XML::Reader)
    puts "NEW"
    FromXml(T).new(reader)
  end

  private class FromXml(T)
    include Iterator(T)

    def initialize(@reader : XML::Reader)
      puts "INIT"
      @reader.read
      @end = false
    end

    def next
      puts "NEXT"
      loop do
        break if @end

        case @reader.node_type
        when .end_element? # NOTE: go to end of element
          @reader.read
          @end = true
        else
          return T.new(@reader)
        end
        @reader.read
      end
    end
  end
end

def Bool.new(parser : XML::PullParser) : Bool
  parser.read_bool
end

def Union.new(parser : XML::PullParser)
  location = parser.location
  value = parser.read_raw

  {% begin %}
    case value
    {% if T.includes? Nil %}
    when ""
      return nil
    {% end %}
    {% if T.includes? Bool %}
    when "true"
      return true
    when "false"
      return false
    {% end %}
    {%
      numeral_methods = {
        Int64   => "i64",
        UInt64  => "u64",
        Int32   => "i32",
        UInt32  => "u32",
        Int16   => "i16",
        UInt16  => "u16",
        Int8    => "i8",
        UInt8   => "u8",
        Float64 => "f64",
        Float32 => "f32",
      }
    %}
    {% type_order = [Int64, UInt64, Int32, UInt32, Int16, UInt16, Int8, UInt8, Float64, Float32] %}
    {% for type in type_order.select { |t| T.includes? t } %}
      when .to_{{numeral_methods[type].id}}?
        return value.not_nil!.to_{{numeral_methods[type].id}}
    {% end %}
    {% if T.includes? String %}
    else
      return value.to_s
    {% else %}
    else
      # no priority type
    {% end %}
    end
  {% end %}

  {% begin %}
    {% primitive_types = [Nil, Bool, String] + Number::Primitive.union_types %}
    {% non_primitives = T.reject { |t| primitive_types.includes? t } %}

    # If after traversing all the types we are left with just one
    # non-primitive type, we can parse it directly (no need to use `read_raw`)
    {% if non_primitives.size == 1 %}
      return {{non_primitives[0]}}.new(node)
    {% else %}
      string = parser.read_string
      {% for type in non_primitives %}
        begin
          return {{type}}.from_xml(string)
        rescue XML::Error
          # Ignore
        end
      {% end %}
      raise XML::Error.new("Couldn't parse #{self} from #{string}", *location)
    {% end %}
  {% end %}
end

def Time.new(parser : XML::PullParser)
  Time::Format::ISO_8601_DATE_TIME.parse(parser.read_string)
end

struct Time::Format
  def from_xml(parser : XML::PullParser) : Time
    parse(parser.read_string, Time::Location::UTC)
  end
end

{% for type, method in {
                         "Int8"   => "i8",
                         "Int16"  => "i16",
                         "Int32"  => "i32",
                         "Int64"  => "i64",
                         "UInt8"  => "u8",
                         "UInt16" => "u16",
                         "UInt32" => "u32",
                         "UInt64" => "u64",
                       } %}
  def {{type.id}}.new(parser : XML::PullParser)
    value = {% if type == "UInt64" %}
      parser.read_raw
    {% else %}
      parser.read_int
    {% end %}

    begin
      value.to_{{method.id}}
    rescue ex : OverflowError | ArgumentError
      raise XML::ParseException.new("Can't read {{type.id}}", parser.line_number, parser.column_number, ex)
    end
  end

  def {{type.id}}.from_xml_object_key?(key : String)
    key.to_{{method.id}}?
  end
{% end %}

def Nil.new(parser : XML::PullParser) : Nil
  nil
end

def Int32.new(parser : XML::PullParser) : Int32
  parser.read_int.to_i32
end

def Array.new(reader : XML::Reader)
  ary = new
  new(reader) do |element|
    ary << element
  end
  ary
end

def Array.new(reader : XML::Reader)
  results = Array(T).new

  loop do
    case reader.node_type
    when .element?
      reader.read
      results << T.new(reader)
    when .end_element?
      reader.read
      break
    when .none?
      break
    end
    reader.read
  end

  results
end

def String.new(parser : XML::PullParser) : String
  parser.read_string
end

def Object.from_xml(string_or_io, root : String)
  parser = XML::Reader.new(string_or_io)
  parser.on_key!(root) do
    new parser
  end
end

def UUID.new(parser : XML::PullParser)
  UUID.new(parser.read_string)
end

def Hash.new(node : XML::Node)
  hash = new

  element = node.children
  if element.nil?
    raise XML::SerializableError.new(
      "Can't convert #{node.inspect} into Hash",
      self.class.to_s,
      nil,
      Int32::MIN
    )
  end

  element.each do |child|
    next unless child.element?

    parsed_key = child.name
    if parsed_key.nil?
      raise XML::SerializableError.new(
        "Can't convert #{parsed_key.inspect} into #{K}",
        self.class.to_s,
        nil,
        Int32::MIN
      )
    end
    hash[parsed_key] = V.new(child)
  end
  hash
end

module Time::EpochConverter
  def self.from_xml(parser : XML::PullParser) : Time
    Time.unix(parser.read_int)
  end
end

module Time::EpochMillisConverter
  def self.from_xml(parser : XML::PullParser) : Time
    Time.unix_ms(parser.read_int)
  end
end

module String::RawConverter
  def self.from_xml(parser : XML::PullParser) : String
    parser.read_raw
  end
end
