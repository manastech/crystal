struct Int
  def to_xml(xml : XML::Builder) : Nil
    xml.text(self.to_s)
  end

  def to_xml_object_key : String
    to_s
  end
end

struct Nil
  def to_xml(xml : XML::Builder) : Nil
    xml.text("")
  end

  def to_json_object_key : String
    ""
  end
end

class String
  def to_xml(xml : XML::Builder) : Nil
    xml.text(self)
  end

  def to_xml_object_key : String
    self
  end
end

struct Bool
  def to_xml(xml : XML::Builder) : Nil
    xml.text(self.to_s)
  end
end

class Hash
  # Serializes this Hash into XML.
  #
  # Keys are serialized by invoking `to_xml_object_key` on them.
  # Values are serialized with the usual `to_xml(xml : XML::Node)`
  # method.
  def to_xml(name : String, xml : XML::Builder) : Nil
    xml.element(name) do
      each do |key, value|
        xml.element(key) do
          value.to_xml(value, xml)
        end
      end
    end
  end
end

struct Time::Format
  def to_xml(value : Time, xml : XML::Builder) : Nil
    format(value).to_xml(xml)
  end
end

# Converter to be used with `XML::Serializable` and `YAML::Serializable`
# to serialize a `Time` instance as the number of seconds
# since the unix epoch. See `Time#to_unix`.
#
# ```
# require "xml"
#
# class Person
#   include XML::Serializable
#
#   @[XML::Field(converter: Time::EpochConverter)]
#   property birth_date : Time
# end
#
# person = Person.from_xml(%({"birth_date": 1459859781}))
# person.birth_date # => 2016-04-05 12:36:21 UTC
# person.to_xml     # => %({"birth_date":1459859781})
# ```
module Time::EpochConverter
  def self.to_xml(value : Time, xml : XML::Builder) : Nil
    xml.text(value.to_unix.to_s)
  end
end

# Converter to be used with `XML::Serializable` and `YAML::Serializable`
# to serialize a `Time` instance as the number of milliseconds
# since the unix epoch. See `Time#to_unix_ms`.
#
# ```
# require "xml"
#
# class Timestamp
#   include XML::Serializable
#
#   @[XML::Field(converter: Time::EpochMillisConverter)]
#   property value : Time
# end
#
# timestamp = Timestamp.from_xml(%({"value": 1459860483856}))
# timestamp.value  # => 2016-04-05 12:48:03.856 UTC
# timestamp.to_xml # => %({"value":1459860483856})
# ```
module Time::EpochMillisConverter
  def self.to_xml(value : Time, xml : XML::Builder) : Nil
    xml.text(value.to_unix_ms.to_s)
  end
end

# Converter to be used with `XML::Serializable` to read the raw
# value of a XML object property as a `String`.
#
# It can be useful to read ints and floats without losing precision,
# or to read an object and deserialize it later based on some
# condition.
#
# ```
# require "xml"
#
# class Raw
#   include XML::Serializable
#
#   @[XML::Element(converter: String::RawConverter)]
#   property value : String
# end
#
# raw = Raw.from_xml(%({"value": 123456789876543212345678987654321}))
# raw.value  # => "123456789876543212345678987654321"
# raw.to_xml # => %({"value":123456789876543212345678987654321})
# ```
module String::RawConverter
  def self.to_xml(value : String, xml : XML::Builder) : Nil
    xml.text(value.to_s)
  end
end
