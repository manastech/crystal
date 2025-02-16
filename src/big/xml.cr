require "xml"
require "big"

struct BigInt
  def self.new(parser : XML::PullParser)
    new(parser.read_string)
  end

  def self.from_xml_object_key?(key : String) : BigInt?
    new(key)
  rescue ArgumentError
    nil
  end

  def to_xml_object_key : String
    to_s
  end

  def to_xml(xml : XML::Builder) : Nil
    xml.text(self.to_s)
  end
end

struct BigFloat
  def self.new(parser : XML::PullParser)
    new(parser.read_string)
  end

  def self.from_xml_object_key?(key : String) : BigFloat?
    new(key)
  rescue ArgumentError
    nil
  end

  def to_xml_object_key
    to_s
  end

  def to_xml(xml : XML::Builder) : Nil
    xml.text(self.to_s)
  end
end

struct BigDecimal
  def self.new(parser : XML::PullParser)
    new(parser.read_string)
  end

  def self.from_xml_object_key?(key : String) : BigDecimal?
    new(key)
  rescue InvalidBigDecimalException
    nil
  end

  def to_xml_object_key
    to_s
  end

  def to_xml(xml : XML::Builder) : Nil
    xml.text(self.to_s)
  end
end
