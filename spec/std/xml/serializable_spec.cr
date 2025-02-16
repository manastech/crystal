require "../spec_helper"
require "big"
require "xml"
require "big/xml"
require "uuid"

# record XMLAttrPoint, x : Int32, y : Int32 do
#   include XML::Serializable
# end

# class XMLAttrEmptyClass
#   include XML::Serializable

#   def initialize; end
# end

# class XMLAttrEmptyClassWithUnmapped
#   include XML::Serializable
#   include XML::Serializable::Unmapped

#   def initialize; end
# end

class XMLAttrPerson
  include XML::Serializable

  property name : String
  property age : Int32?

  def_equals name, age

  def initialize(@name : String)
  end
end

struct XMLAttrPersonWithTwoFieldInInitialize
  include XML::Serializable

  property name : String
  property age : Int32

  def initialize(@name, @age)
  end
end

# class StrictXMLAttrPerson
#   include XML::Serializable
#   include XML::Serializable::Strict

#   property name : String
#   property age : Int32?
# end

# class XMLAttrPersonExtraFields
#   include XML::Serializable
#   include XML::Serializable::Unmapped

#   property name : String
#   property age : Int32?
# end

class XMLAttrPersonEmittingNull
  include XML::Serializable

  property name : String

  @[XML::Element(emit_null: true)]
  property age : Int32?
end

@[XML::Serializable::Options(emit_nulls: true)]
class XMLAttrPersonEmittingNullsByOptions
  include XML::Serializable

  property name : String
  property age : Int32?
  property value1 : Int32?

  @[XML::Element(emit_null: false)]
  property value2 : Int32?
end

class XMLAttrWithBool
  include XML::Serializable

  property value : Bool
end

class XMLAttrWithUUID
  include XML::Serializable

  property value : UUID
end

class XMLAttrWithBigDecimal
  include XML::Serializable

  property value : BigDecimal
end

class XMLAttrWithSimpleMapping
  include XML::Serializable

  property name : String
  property age : Int32
end

class XMLAttrWithTime
  include XML::Serializable

  @[XML::Element(converter: Time::Format.new("%F %T"))]
  property value : Time
end

class XMLAttrWithNilableTime
  include XML::Serializable

  @[XML::Element(converter: Time::Format.new("%F"))]
  property value : Time?

  def initialize
  end
end

class XMLAttrWithNilableTimeEmittingNull
  include XML::Serializable

  @[XML::Element(converter: Time::Format.new("%F"), emit_null: true)]
  property value : Time?

  def initialize
  end
end

class XMLAttrWithPropertiesKey
  include XML::Serializable

  property properties : Hash(String, String)
end

class XMLAttrWithKeywordsMapping
  include XML::Serializable

  property end : Int32
  property abstract : Int32
end

class XMLAttrWithProblematicKeys
  include XML::Serializable

  property key : Int32
  property pull : Int32
end

class XMLAttrWithSet
  include XML::Serializable

  property set : Set(String)
end

class XMLAttrWithSmallIntegers
  include XML::Serializable

  property foo : Int16
  property bar : Int8
end

class XMLAttrWithDefaults
  include XML::Serializable

  property a = 11
  property b = "Haha"
  property c = true
  property d = false
  property e : Bool? = false
  property f : Int32? = 1
  property g : Int32?
  property h = [1, 2, 3]
end

class XMLAttrWithTimeEpoch
  include XML::Serializable

  @[XML::Element(converter: Time::EpochConverter)]
  property value : Time
end

class XMLAttrWithTimeEpochMillis
  include XML::Serializable

  @[XML::Element(converter: Time::EpochMillisConverter)]
  property value : Time
end

class XMLAttrWithRaw
  include XML::Serializable

  @[XML::Element(converter: String::RawConverter)]
  property value : String
end

class XMLAttrWithPresence
  include XML::Serializable

  @[XML::Element(presence: true)]
  property first_name : String?

  @[XML::Element(presence: true)]
  property last_name : String?

  @[XML::Element(ignore: true)]
  getter? first_name_present : Bool

  @[XML::Element(ignore: true)]
  getter? last_name_present : Bool
end

class XMLAttrWithPresenceAndIgnoreSerialize
  include XML::Serializable

  @[XML::Element(presence: true, ignore_serialize: ignore_first_name?)]
  property first_name : String?

  @[XML::Element(presence: true, ignore_serialize: last_name.nil? && !last_name_present?, emit_null: true)]
  property last_name : String?

  @[XML::Element(ignore: true)]
  getter? first_name_present : Bool = false

  @[XML::Element(ignore: true)]
  getter? last_name_present : Bool = false

  def initialize(@first_name : String? = nil, @last_name : String? = nil)
  end

  def ignore_first_name?
    first_name.nil? || first_name == ""
  end
end

class XMLAttrWithQueryAttributes
  include XML::Serializable

  property? foo : Bool

  @[XML::Element(key: "is_bar", presence: true)]
  property? bar : Bool = false

  @[XML::Element(ignore: true)]
  getter? bar_present : Bool
end

module XMLAttrModule
  property moo : Int32 = 10
end

class XMLAttrModuleTest
  include XMLAttrModule
  include XML::Serializable

  @[XML::Element(key: "phoo")]
  property foo = 15

  def initialize; end

  def to_tuple
    {@moo, @foo}
  end
end

class XMLAttrModuleTest2 < XMLAttrModuleTest
  property bar : Int32

  def initialize(@bar : Int32); end

  def to_tuple
    {@moo, @foo, @bar}
  end
end

# module XMLNamespace
#   struct FooRequest
#     include XML::Serializable

#     getter foo : Foo
#     getter bar = Bar.new
#   end

#   struct Foo
#     include XML::Serializable
#     getter id = "id:foo"
#   end

#   struct Bar
#     include XML::Serializable
#     getter id = "id:bar"

#     def initialize # Allow for default value above
#     end
#   end
# end

# abstract class XMLShape
#   include XML::Serializable

#   use_xml_discriminator "type", {point: XMLPoint, circle: XMLCircle}

#   property type : String
# end

# class XMLPoint < XMLShape
#   property x : Int32
#   property y : Int32
# end

# class XMLCircle < XMLShape
#   property x : Int32
#   property y : Int32
#   property radius : Int32
# end

# enum XMLVariableDiscriminatorEnumFoo
#   Foo = 4
# end

# enum XMLVariableDiscriminatorEnumFoo8 : UInt8
#   Foo = 1_8
# end

# class XMLVariableDiscriminatorValueType
#   include XML::Serializable

#   use_xml_discriminator "type", {
#                                         0 => XMLVariableDiscriminatorNumber,
#     "1"                                   => XMLVariableDiscriminatorString,
#     true                                  => XMLVariableDiscriminatorBool,
#     XMLVariableDiscriminatorEnumFoo::Foo  => XMLVariableDiscriminatorEnum,
#     XMLVariableDiscriminatorEnumFoo8::Foo => XMLVariableDiscriminatorEnum8,
#   }
# end

# class XMLVariableDiscriminatorNumber < XMLVariableDiscriminatorValueType
# end

# class XMLVariableDiscriminatorString < XMLVariableDiscriminatorValueType
# end

# class XMLVariableDiscriminatorBool < XMLVariableDiscriminatorValueType
# end

# class XMLVariableDiscriminatorEnum < XMLVariableDiscriminatorValueType
# end

# class XMLVariableDiscriminatorEnum8 < XMLVariableDiscriminatorValueType
# end

describe "XML mapping" do
  # it "works with record" do
  #   xml = <<-XML
  #     <?xml version="1.0"?>
  #     <XMLAttrPoint><x>1</x><y>2</y></XMLAttrPoint>\n
  #     XML

  #   XMLAttrPoint.new(1, 2).to_xml.should eq(xml)
  #   XMLAttrPoint.from_xml(xml).should eq(XMLAttrPoint.new(1, 2))
  # end

  # it "empty class" do
  #   xml = <<-XML
  #     <?xml version="1.0"?>
  #     <XMLAttrEmptyClass/>\n
  #     XML

  #   e = XMLAttrEmptyClass.new
  #   e.to_xml.should eq(xml)
  #   XMLAttrEmptyClass.from_xml(xml)
  # end

  # it "empty class with unmapped" do
  #   xml = <<-XML
  #     <?xml version="1.0"?>
  #     <XMLAttrEmptyClassWithUnmapped>
  #       <name>John</name>
  #       <age>30</age>
  #     </XMLAttrEmptyClassWithUnmapped>\n
  #     XML

  #   XMLAttrEmptyClassWithUnmapped.from_xml(xml).xml_unmapped.should eq(
  #     {
  #       "name" => XML::Any.new("John"),
  #       "age"  => XML::Any.new("30"),
  #     }
  #   )
  # end

  it "parses person" do
    xml = String.build do |str|
      str << "<?xml version=\"1.0\"?>\n"
      str << "<XMLAttrPerson>"
      str << "<name>John</name>"
      str << "<age>30</age>"
      str << "</XMLAttrPerson>\n"
    end

    person = XMLAttrPerson.from_xml(xml)
    person.should be_a(XMLAttrPerson)
    person.name.should eq("John")
    person.age.should eq(30)
  end

  it "parses person without age" do
    xml = String.build do |str|
      str << "<?xml version=\"1.0\"?>\n"
      str << "<XMLAttrPerson>"
      str << "<name>John</name>"
      str << "</XMLAttrPerson>\n"
    end

    person = XMLAttrPerson.from_xml(xml)
    person.should be_a(XMLAttrPerson)
    person.name.should eq("John")
    person.name.size.should eq(4) # This verifies that name is not nilable
    person.age.should be_nil
  end

  # it "parses array of people" do
  #   xml = String.build do |str|
  #     str << "<?xml version=\"1.0\"?>" << "\n"
  #     str << "<People>"
  #     str << "  <XMLAttrPerson>"
  #     str << "    <name>John</name>"
  #     str << "  </XMLAttrPerson>\n"
  #     str << "  <XMLAttrPerson>"
  #     str << "    <name>Doe</name>"
  #     str << "  </XMLAttrPerson>"
  #     str << "</People>" << "\n"
  #   end

  #   people = Array(XMLAttrPerson).from_xml(xml)
  #   people.size.should eq(2)
  # end

  it "works with class with two fields" do
    xml = String.build do |str|
      str << "<?xml version=\"1.0\"?>" << "\n"
      str << "<XMLAttrPersonWithTwoFieldInInitialize>"
      str << "  <name>John</name>"
      str << "  <age>30</age>"
      str << "</XMLAttrPersonWithTwoFieldInInitialize>" << "\n"
    end

    person1 = XMLAttrPersonWithTwoFieldInInitialize.from_xml(xml)
    person2 = XMLAttrPersonWithTwoFieldInInitialize.new("John", 30)
    person1.should eq person2
  end

  it "does to_xml" do
    xml = String.build do |str|
      str << "<?xml version=\"1.0\"?>" << "\n"
      str << "<XMLAttrPerson>"
      str << "  <name>John</name>"
      str << "  <age>30</age>"
      str << "</XMLAttrPerson>" << "\n"
    end

    person = XMLAttrPerson.from_xml(xml)
    person2 = XMLAttrPerson.from_xml(person.to_xml)
    person2.should eq(person)
  end

  it "parses person with unknown attributes" do
    xml = String.build do |str|
      str << "<?xml version=\"1.0\"?>" << "\n"
      str << "<XMLAttrPerson>"
      str << "  <name>John</name>"
      str << "  <age>30</age>"
      str << "  <foo>bar</foo>"
      str << "</XMLAttrPerson>" << "\n"
    end

    person = XMLAttrPerson.from_xml(xml)
    person.should be_a(XMLAttrPerson)
    person.name.should eq("John")
    person.age.should eq(30)
  end

  pending "parses strict person with unknown attributes" do
    xml = String.build do |str|
      str << "<?xml version=\"1.0\"?>" << "\n"
      str << "<XMLAttrPerson>"
      str << "  <name>John</name>"
      str << "  <age>30</age>"
      str << "  <foo>bar</foo>"
      str << "</XMLAttrPerson>" << "\n"
    end

    error_message = <<-'MSG'
      Unknown XML attribute: foo
        parsing StrictXMLAttrPerson
      MSG

    ex = expect_raises ::XML::SerializableError, error_message do
      StrictXMLAttrPerson.from_xml(xml)
    end
    ex.location.should eq({4, 3})
  end

  pending "should parse extra fields (XMLAttrPersonExtraFields with on_unknown_xml_attribute)" do
    xml = String.build do |str|
      str << "<?xml version=\"1.0\"?>" << "\n"
      str << "<XMLAttrPersonExtraFields>"
      str << "  <name>John</name>"
      str << "  <age>30</age>"
      str << "  <x>1</x>"
      str << "  <y>2</y>"
      str << "</XMLAttrPersonExtraFields>" << "\n"
    end
    # TODO: <z>1,2,3</z>

    person = XMLAttrPersonExtraFields.from_xml xml
    person.name.should eq("John")
    person.age.should eq(30)
    # TODO: "z" => [1, 2, 3]
    person.xml_unmapped.should eq({"x" => "1", "y" => 2_i64})
  end

  pending "should to store extra fields (XMLAttrPersonExtraFields with on_to_xml)" do
    original_xml = String.build do |str|
      str << "<?xml version=\"1.0\"?>" << "\n"
      str << "<XMLAttrPersonExtraFields>"
      str << "  <name>John</name>"
      str << "  <age>30</age>"
      str << "  <x>1</x>"
      str << "  <y>2</y>"
      str << "</XMLAttrPersonExtraFields>" << "\n"
    end
    expected_xml = String.build do |str|
      str << "<?xml version=\"1.0\"?>" << "\n"
      str << "<XMLAttrPersonExtraFields>"
      str << "  <name>John1</name>"
      str << "  <age>30</age>"
      str << "  <x>1</x>"
      str << "  <y>2</y>"
      str << "  <q>w</q>"
      str << "</XMLAttrPersonExtraFields>" << "\n"
    end

    person = XMLAttrPersonExtraFields.from_xml(original_xml)
    person.name = "John1"
    person.xml_unmapped.delete("y")
    person.xml_unmapped["q"] = XML::Any.new("w")
    # TODO: "z" => [1, 2, 3]
    person.to_xml.should eq expected_xml
  end

  pending "raises if non-nilable attribute is nil" do
    xml = String.build do |str|
      str << "<?xml version=\"1.0\"?>" << "\n"
      str << "<XMLAttrPerson>"
      str << "  <age>30</age>"
      str << "</XMLAttrPerson>" << "\n"
    end

    error_message = <<-'MSG'
      Missing XML attribute: name
        parsing XMLAttrPerson at line 1, column 1
      MSG

    ex = expect_raises ::XML::SerializableError, error_message do
      XMLAttrPerson.from_xml(xml)
    end
    ex.location.should eq({1, 1})
  end

  pending "raises if not an object" do
    error_message = <<-'MSG'
      Expected BeginObject but was String at line 1, column 1
        parsing StrictXMLAttrPerson at line 0, column 0
      MSG
    ex = expect_raises ::XML::SerializableError, error_message do
      StrictXMLAttrPerson.from_xml <<-XML
        "foo"
        XML
    end
    ex.location.should eq({1, 1})
  end

  pending "raises if data type does not match" do
    xml = String.build do |str|
      str << "<?xml version=\"1.0\"?>" << "\n"
      str << "<XMLAttrPerson>"
      str << "  <name>John</name>"
      str << "  <age>30</age>"
      str << "  <foo>bar</foo>"
      str << "</XMLAttrPerson>" << "\n"
    end

    error_message = <<-MSG
      Couldn't parse (Int32 | Nil) from "foo" at line 3, column 10
      MSG
    ex = expect_raises ::XML::SerializableError, error_message do
      StrictXMLAttrPerson.from_xml xml
    end
    ex.location.should eq({3, 10})
  end

  pending "doesn't emit null by default when doing to_xml" do
    xml = String.build do |str|
      str << "<?xml version=\"1.0\"?>" << "\n"
      str << "<XMLAttrPerson>"
      str << "  <name>John</name>"
      str << "</XMLAttrPerson>" << "\n"
    end

    person = XMLAttrPerson.from_xml(xml)
    (person.to_xml =~ /age/).should be_falsey
  end

  it "emits null on request when doing to_xml" do
    xml = String.build do |str|
      str << "<?xml version=\"1.0\"?>" << "\n"
      str << "<XMLAttrPersonEmittingNull>"
      str << "  <name>John</name>"
      str << "</XMLAttrPersonEmittingNull>" << "\n"
    end

    person = XMLAttrPersonEmittingNull.from_xml(xml)
    (person.to_xml =~ /age/).should be_truthy
  end

  it "emit_nulls option" do
    original_xml = String.build do |str|
      str << "<?xml version=\"1.0\"?>\n"
      str << "<XMLAttrPerson>"
      str << "  <name>John</name>"
      str << "</XMLAttrPerson>\n"
    end

    expected_xml = String.build do |str|
      str << "<?xml version=\"1.0\"?>\n"
      str << "<XMLAttrPersonEmittingNullsByOptions>"
      str << "<name>John</name>"
      str << "<age></age>"
      str << "<value1></value1>"
      str << "</XMLAttrPersonEmittingNullsByOptions>\n"
    end

    person = XMLAttrPersonEmittingNullsByOptions.from_xml(original_xml)
    person.to_xml.should eq expected_xml
  end

  it "doesn't raises on false value when not-nil" do
    xml = String.build do |str|
      str << "<?xml version=\"1.0\"?>\n"
      str << "<XMLAttrWithBool>"
      str << "  <value>false</value>"
      str << "</XMLAttrWithBool>\n"
    end

    xml = XMLAttrWithBool.from_xml(xml)
    xml.value.should be_false
  end

  it "parses UUID" do
    xml = String.build do |str|
      str << "<?xml version=\"1.0\"?>\n"
      str << "<XMLAttrWithBool>"
      str << "  <value>ba714f86-cac6-42c7-8956-bcf5105e1b81</value>"
      str << "</XMLAttrWithBool>\n"
    end

    uuid = XMLAttrWithUUID.from_xml(xml)
    uuid.should be_a(XMLAttrWithUUID)
    uuid.value.should eq(UUID.new("ba714f86-cac6-42c7-8956-bcf5105e1b81"))
  end

  it "parses xml with Time::Format converter" do
    original_xml = String.build do |str|
      str << "<?xml version=\"1.0\"?>\n"
      str << "<XMLAttrWithTime>"
      str << "  <value>2014-10-31 23:37:16</value>"
      str << "</XMLAttrWithTime>\n"
    end

    expected_xml = String.build do |str|
      str << "<?xml version=\"1.0\"?>\n"
      str << "<XMLAttrWithTime>"
      str << "<value>2014-10-31 23:37:16</value>" # NOTE: should this include `UTC`
      str << "</XMLAttrWithTime>\n"
    end

    xml = XMLAttrWithTime.from_xml(original_xml)
    xml.value.should be_a(Time)
    xml.value.to_s.should eq("2014-10-31 23:37:16 UTC")
    xml.to_xml.should eq(expected_xml)
  end

  it "allows setting a nilable property to nil" do
    person = XMLAttrPerson.new("John")
    person.age = 1
    person.age = nil
  end

  it "parses simple mapping" do
    xml = String.build do |str|
      str << "<?xml version=\"1.0\"?>\n"
      str << "<XMLAttrWithSimpleMapping>"
      str << "  <name>John</name>"
      str << "  <age>30</age>"
      str << "</XMLAttrWithSimpleMapping>\n"
    end

    person = XMLAttrWithSimpleMapping.from_xml(xml)
    person.should be_a(XMLAttrWithSimpleMapping)
    person.name.should eq("John")
    person.age.should eq(30)
  end

  it "outputs with converter when nilable" do
    xml = String.build do |str|
      str << "<?xml version=\"1.0\"?>\n"
      str << "<XMLAttrWithNilableTime/>\n"
    end

    obj = XMLAttrWithNilableTime.new
    obj.to_xml.should eq(xml)
  end

  it "outputs with converter when nilable when emit_null is true" do
    xml = String.build do |str|
      str << "<?xml version=\"1.0\"?>\n"
      str << "<XMLAttrWithNilableTimeEmittingNull>"
      str << "<value></value>"
      str << "</XMLAttrWithNilableTimeEmittingNull>\n"
    end

    obj = XMLAttrWithNilableTimeEmittingNull.new
    obj.to_xml.should eq(xml)
  end

  # # TODO: implement Hash.to_xml
  # # it "outputs JSON with properties key" do
  # #   xml = String.build do |str|
  # #     str << "<?xml version=\"1.0\"?>\n"
  # #     str << "<XMLAttrWithKeywordsMapping>"
  # #     str << "<properties>"
  # #     str << "<foo>bar</foo>"
  # #     str << "</properties>"
  # #     str << "</XMLAttrWithKeywordsMapping>\n"
  # #   end

  # #   obj = XMLAttrWithPropertiesKey.from_xml(xml)
  # #   obj.to_xml.should eq(xml)
  # # end

  it "parses xml with keywords" do
    xml = String.build do |str|
      str << "<?xml version=\"1.0\"?>\n"
      str << "<XMLAttrWithKeywordsMapping>"
      str << "  <end>1</end>"
      str << "  <abstract>2</abstract>"
      str << "</XMLAttrWithKeywordsMapping>\n"
    end

    obj = XMLAttrWithKeywordsMapping.from_xml(xml)
    obj.end.should eq(1)
    obj.abstract.should eq(2)
  end

  # # it "parses json with any" do
  # #   xml = String.build do |str|
  # #     str << "<?xml version=\"1.0\"?>"
  # #     str << "<XMLAttrWithAny>"
  # #     str << "<name>John</name>"
  # #     str << "<any>"
  # #     str << "<value><x>1</x></value>"
  # #     str << "<value>2</value>"
  # #     str << "<value>hey</value>"
  # #     str << "<value>true</value>"
  # #     str << "<value>false</value>"
  # #     str << "<value>1.5</value>"
  # #     str << "<value>null<value>"
  # #     str << "</any>"
  # #     str << "</XMLAttrWithAny>\n"
  # #   end
  # #   obj = XMLAttrWithAny.from_xml(xml)
  # #   obj.name.should eq("John")
  # #   obj.any.raw.should eq([{"x" => 1}, 2, "hey", true, false, 1.5, nil])
  # #   obj.to_xml.should eq(%({"name":"Hi","any":[{"x":1},2,"hey",true,false,1.5,null]}))
  # # end

  it "parses xml with problematic keys" do
    xml = String.build do |str|
      str << "<?xml version=\"1.0\"?>\n"
      str << "<XMLAttrWithProblematicKeys>"
      str << "  <key>1</key>"
      str << "  <pull>2</pull>"
      str << "</XMLAttrWithProblematicKeys>\n"
    end

    obj = XMLAttrWithProblematicKeys.from_xml(xml)
    obj.key.should eq(1)
    obj.pull.should eq(2)
  end

  pending "parses xml array as set" do
    xml = String.build do |str|
      str << "<?xml version=\"1.0\"?>\n"
      str << "<XMLAttrWithSet>"
      str << "  <set>"
      str << "    <value>a</value>"
      str << "    <value>a</value>"
      str << "    <value>b</value>"
      str << "  </set>"
      str << "</XMLAttrWithSet>\n"
    end

    obj = XMLAttrWithSet.from_xml(xml)
    obj.set.should eq(Set(String){"a", "b"})
  end

  pending "allows small types of integer" do
    xml = String.build do |str|
      str << "<?xml version=\"1.0\"?>\n"
      str << "<XMLAttrWithSmallIntegers>"
      str << "<foo>1</foo>"
      str << "<bar>2</bar>"
      str << "</XMLAttrWithSmallIntegers>\n"
    end

    obj = XMLAttrWithSmallIntegers.from_xml(xml)

    typeof(obj.foo).should eq(Int16)
    obj.foo.should eq(23)

    typeof(obj.bar).should eq(Int8)
    obj.bar.should eq(7)
  end

  describe "parses json with defaults" do
    it "mixed" do
      obj = XMLAttrWithDefaults.from_xml(String.build { |str|
        str << "<?xml version=\"1.0\"?>\n"
        str << "<JSONAttrWithDefaults>"
        str << "  <a>1</a>"
        str << "  <b>bla</b>"
        str << "</JSONAttrWithDefaults>\n"
      })
      obj.a.should eq 1
      obj.b.should eq "bla"

      xml = XMLAttrWithDefaults.from_xml(String.build { |str|
        str << "<?xml version=\"1.0\"?>\n"
        str << "<JSONAttrWithDefaults>"
        str << "  <a>1</a>"
        str << "</JSONAttrWithDefaults>\n"
      })
      xml.a.should eq 1
      xml.b.should eq "Haha"

      xml = XMLAttrWithDefaults.from_xml(String.build { |str|
        str << "<?xml version=\"1.0\"?>\n"
        str << "<JSONAttrWithDefaults>"
        str << "  <b>bla</b>"
        str << "</JSONAttrWithDefaults>\n"
      })
      xml.a.should eq 11
      xml.b.should eq "bla"

      xml = XMLAttrWithDefaults.from_xml(String.build { |str|
        str << "<?xml version=\"1.0\"?>\n"
        str << "<JSONAttrWithDefaults>"
        str << "</JSONAttrWithDefaults>\n"
      })
      xml.a.should eq 11
      xml.b.should eq "Haha"

      # xml = XMLAttrWithDefaults.from_xml(<<-XML
      # <?xml version="1.0"?>
      # <JSONAttrWithDefaults>
      #   <a></a>
      #   <b></b>
      # </JSONAttrWithDefaults>
      # XML
      # )
      # xml.a.should eq 11
      # xml.b.should eq "Haha"
    end

    it "bool" do
      # xml = XMLAttrWithDefaults.from_xml(<<-XML
      # <?xml version="1.0"?>
      # <XMLAttrWithDefaults>
      # </XMLAttrWithDefaults>
      # XML
      # )
      # xml.c.should eq true
      # typeof(xml.c).should eq Bool
      # xml.d.should eq false
      # typeof(xml.d).should eq Bool

      xml = XMLAttrWithDefaults.from_xml(String.build { |str|
        str << "<?xml version=\"1.0\"?>\n"
        str << "<XMLAttrWithDefaults>"
        str << "  <c>false</c>"
        str << "</XMLAttrWithDefaults>\n"
      })
      xml.c.should eq false
      xml = XMLAttrWithDefaults.from_xml(String.build { |str|
        str << "<?xml version=\"1.0\"?>\n"
        str << "<XMLAttrWithDefaults>"
        str << "  <c>true</c>"
        str << "</XMLAttrWithDefaults>\n"
      })
      xml.c.should eq true

      xml = XMLAttrWithDefaults.from_xml(String.build { |str|
        str << "<?xml version=\"1.0\"?>\n"
        str << "<XMLAttrWithDefaults>"
        str << "  <d>false</d>"
        str << "</XMLAttrWithDefaults>\n"
      })
      xml.d.should eq false
      xml = XMLAttrWithDefaults.from_xml(String.build { |str|
        str << "<?xml version=\"1.0\"?>\n"
        str << "<XMLAttrWithDefaults>"
        str << "  <d>true</d>"
        str << "</XMLAttrWithDefaults>\n"
      })
      xml.d.should eq true
    end

    it "with nilable" do
      xml = XMLAttrWithDefaults.from_xml(String.build { |str|
        str << "<?xml version=\"1.0\"?>\n"
        str << "<XMLAttrWithDefaults>"
        str << "</XMLAttrWithDefaults>\n"
      })

      xml.e.should eq false
      typeof(xml.e).should eq(Bool | Nil)

      xml.f.should eq 1
      typeof(xml.f).should eq(Int32 | Nil)

      xml.g.should eq nil
      typeof(xml.g).should eq(Int32 | Nil)

      xml = XMLAttrWithDefaults.from_xml(String.build { |str|
        str << "<?xml version=\"1.0\"?>\n"
        str << "<XMLAttrWithDefaults>"
        str << "  <e>false</e>"
        str << "</XMLAttrWithDefaults>\n"
      })
      xml.e.should eq false
      xml = XMLAttrWithDefaults.from_xml(String.build { |str|
        str << "<?xml version=\"1.0\"?>\n"
        str << "<XMLAttrWithDefaults>"
        str << "  <e>true</e>"
        str << "</XMLAttrWithDefaults>\n"
      })
      xml.e.should eq true
    end

    it "create new array every time" do
      xml = XMLAttrWithDefaults.from_xml(String.build { |str|
        str << "<?xml version=\"1.0\"?>\n"
        str << "<XMLAttrWithDefaults>"
        str << "</XMLAttrWithDefaults>\n"
      })
      xml.h.should eq [1, 2, 3]
      xml.h << 4
      xml.h.should eq [1, 2, 3, 4]

      xml = XMLAttrWithDefaults.from_xml(String.build { |str|
        str << "<?xml version=\"1.0\"?>\n"
        str << "<XMLAttrWithDefaults>"
        str << "</XMLAttrWithDefaults>\n"
      })
      xml.h.should eq [1, 2, 3]
    end
  end

  it "uses Time::EpochConverter" do
    string = String.build do |str|
      str << "<?xml version=\"1.0\"?>\n"
      str << "<XMLAttrWithTimeEpoch>"
      str << "<value>1459859781</value>"
      str << "</XMLAttrWithTimeEpoch>\n"
    end

    xml = XMLAttrWithTimeEpoch.from_xml(string)
    xml.value.should be_a(Time)
    xml.value.should eq(Time.unix(1459859781))
    xml.to_xml.should eq(string)
  end

  it "uses Time::EpochMillisConverter" do
    string = String.build do |str|
      str << "<?xml version=\"1.0\"?>\n"
      str << "<XMLAttrWithTimeEpochMillis>"
      str << "<value>1459860483856</value>"
      str << "</XMLAttrWithTimeEpochMillis>\n"
    end

    xml = XMLAttrWithTimeEpochMillis.from_xml(string)
    xml.value.should be_a(Time)
    xml.value.should eq(Time.unix_ms(1459860483856))
    xml.to_xml.should eq(string)
  end

  it "parses raw value from int" do
    string = String.build do |str|
      str << "<?xml version=\"1.0\"?>\n"
      str << "<XMLAttrWithRaw>"
      str << "<value>123456789123456789123456789123456789</value>"
      str << "</XMLAttrWithRaw>\n"
    end

    xml = XMLAttrWithRaw.from_xml(string)
    xml.value.should eq("123456789123456789123456789123456789")
    xml.to_xml.should eq(string)
  end

  # it "parses raw value from float" do
  #   string = String.build do |str|
  #     str << "<?xml version=\"1.0\"?>\n"
  #     str << "<XMLAttrWithRaw>"
  #     str << "<value>123456789123456789.123456789123456789</value>"
  #     str << "</XMLAttrWithRaw>\n"
  #   end

  #   xml = XMLAttrWithRaw.from_xml(string)
  #   xml.value.should eq("123456789123456789.123456789123456789")
  #   xml.to_xml.should eq(string)
  # end

  # it "parses raw value from object" do
  #   string = String.build do |str|
  #     str << "<?xml version=\"1.0\"?>\n"
  #     str << "<XMLAttrWithRaw>"
  #     str << "<value><x>foo</x></value>"
  #     str << "</XMLAttrWithRaw>\n"
  #   end

  #   xml = XMLAttrWithRaw.from_xml(string)
  #   xml.value.should eq(%(<x>foo</x>))
  #   xml.to_xml.should eq(string)
  # end

  # it "parses with root" do
  #   json = %({"result":{"heroes":[{"name":"Batman"}]}})
  #   result = JSONAttrWithRoot.from_json(json)
  #   result.result.should be_a(Array(JSONAttrPerson))
  #   result.result.first.name.should eq "Batman"
  #   result.to_json.should eq(json)
  # end

  # it "parses with nilable root" do
  #   json = %({"result":null})
  #   result = JSONAttrWithNilableRoot.from_json(json)
  #   result.result.should be_nil
  #   result.to_json.should eq("{}")
  # end

  # it "parses with nilable root and emit null" do
  #   json = %({"result":null})
  #   result = JSONAttrWithNilableRootEmitNull.from_json(json)
  #   result.result.should be_nil
  #   result.to_json.should eq(json)
  # end

  # it "parses nilable union" do
  #   obj = JSONAttrWithNilableUnion.from_json(%({"value": 1}))
  #   obj.value.should eq(1)
  #   obj.to_json.should eq(%({"value":1}))

  #   obj = JSONAttrWithNilableUnion.from_json(%({"value": null}))
  #   obj.value.should be_nil
  #   obj.to_json.should eq(%({}))

  #   obj = JSONAttrWithNilableUnion.from_json(%({}))
  #   obj.value.should be_nil
  #   obj.to_json.should eq(%({}))
  # end

  # it "parses nilable union2" do
  #   obj = JSONAttrWithNilableUnion2.from_json(%({"value": 1}))
  #   obj.value.should eq(1)
  #   obj.to_json.should eq(%({"value":1}))

  #   obj = JSONAttrWithNilableUnion2.from_json(%({"value": null}))
  #   obj.value.should be_nil
  #   obj.to_json.should eq(%({}))

  #   obj = JSONAttrWithNilableUnion2.from_json(%({}))
  #   obj.value.should be_nil
  #   obj.to_json.should eq(%({}))
  # end

  describe "parses XML with presence markers" do
    it "parses person with absent attributes" do
      string = String.build do |str|
        str << "<?xml version=\"1.0\"?>\n"
        str << "<XMLAttrWithPresence>"
        str << "<first_name></first_name>"
        str << "</XMLAttrWithPresence>\n"
      end

      xml = XMLAttrWithPresence.from_xml(string)
      xml.first_name.should be_nil
      xml.first_name_present?.should be_true
      xml.last_name.should be_nil
      xml.last_name_present?.should be_false
    end
  end

  describe "serializes XML with presence markers and ignore_serialize" do
    context "ignore_serialize is set to a method which returns true when value is nil or empty string" do
      it "ignores field when value is empty string" do
        string = String.build do |str|
          str << "<?xml version=\"1.0\"?>\n"
          str << "<XMLAttrWithPresenceAndIgnoreSerialize>"
          str << "<first_name></first_name>"
          str << "</XMLAttrWithPresenceAndIgnoreSerialize>\n"
        end

        xml = XMLAttrWithPresenceAndIgnoreSerialize.from_xml(string)
        xml.first_name_present?.should be_true
        xml.to_xml.should eq(%(<?xml version="1.0"?>\n<XMLAttrWithPresenceAndIgnoreSerialize/>\n))
      end

      it "ignores field when value is nil" do
        string = String.build do |str|
          str << "<?xml version=\"1.0\"?>\n"
          str << "<XMLAttrWithPresenceAndIgnoreSerialize>"
          str << "<first_name/>"
          str << "</XMLAttrWithPresenceAndIgnoreSerialize>\n"
        end

        xml = XMLAttrWithPresenceAndIgnoreSerialize.from_xml(string)
        xml.first_name_present?.should be_true
        xml.to_xml.should eq(%(<?xml version="1.0"?>\n<XMLAttrWithPresenceAndIgnoreSerialize/>\n))
      end
    end

    context "ignore_serialize is set to conditional expressions 'last_name.nil? && !last_name_present?'" do
      # it "emits null when value is null and @last_name_present is true" do
      #   string = String.build do |str|
      #     str << "<?xml version=\"1.0\"?>\n"
      #     str << "<XMLAttrWithPresenceAndIgnoreSerialize>"
      #     str << "<last_name/>"
      #     str << "</XMLAttrWithPresenceAndIgnoreSerialize>\n"
      #   end
      #   xml = XMLAttrWithPresenceAndIgnoreSerialize.from_xml(string)
      #   xml.last_name_present?.should be_true
      #   xml.to_xml.should eq(%({"last_name":null}))
      # end

      it "does not emit null when value is null and @last_name_present is false" do
        string = String.build do |str|
          str << "<?xml version=\"1.0\"?>\n"
          str << "<XMLAttrWithPresenceAndIgnoreSerialize/>\n"
        end

        xml = XMLAttrWithPresenceAndIgnoreSerialize.from_xml(string)
        xml.last_name_present?.should be_false
        xml.to_xml.should eq(string)
      end

      # it "emits field when value is not nil and @last_name_present is false" do
      #   xml = XMLAttrWithPresenceAndIgnoreSerialize.new(last_name: "something")
      #   xml.last_name_present?.should be_false
      #   xml.to_xml.should eq(%({"last_name":"something"}))
      # end

      # it "emits field when value is not nil and @last_name_present is true" do
      #   string = String.build do |str|
      #     str << "<?xml version=\"1.0\"?>\n"
      #     str << "<XMLAttrWithPresenceAndIgnoreSerialize>"
      #     str << "<last_name>something</last_name>"
      #     str << "</XMLAttrWithPresenceAndIgnoreSerialize>\n"
      #   end

      #   xml = XMLAttrWithPresenceAndIgnoreSerialize.from_xml(string)
      #   xml.last_name_present?.should be_true
      #   xml.to_xml.should eq(%({"last_name":"something"}))
      # end
    end
  end

  describe "with query attributes" do
    it "defines query getter" do
      string = String.build do |str|
        str << "<?xml version=\"1.0\"?>\n"
        str << "<XMLAttrWithQueryAttributes>"
        str << "<foo>true</foo>"
        str << "</XMLAttrWithQueryAttributes>\n"
      end

      xml = XMLAttrWithQueryAttributes.from_xml(string)
      xml.foo?.should be_true
      xml.bar?.should be_false
    end

    it "defines query getter with class restriction" do
      {% begin %}
        {% methods = XMLAttrWithQueryAttributes.methods %}
        {{ methods.find(&.name.==("foo?")).return_type }}.should eq(Bool)
        {{ methods.find(&.name.==("bar?")).return_type }}.should eq(Bool)
      {% end %}
    end

    it "defines non-query setter and presence methods" do
      string = String.build do |str|
        str << "<?xml version=\"1.0\"?>\n"
        str << "<XMLAttrWithQueryAttributes>"
        str << "<foo>false</foo>"
        str << "</XMLAttrWithQueryAttributes>\n"
      end

      xml = XMLAttrWithQueryAttributes.from_xml(string)
      xml.bar_present?.should be_false
      xml.bar = true
      xml.bar?.should be_true
    end

    it "maps non-query attributes" do
      string = String.build do |str|
        str << "<?xml version=\"1.0\"?>\n"
        str << "<XMLAttrWithQueryAttributes>"
        str << "<foo>false</foo>"
        str << "<is_bar>false</is_bar>"
        str << "</XMLAttrWithQueryAttributes>\n"
      end

      xml = XMLAttrWithQueryAttributes.from_xml(string)
      xml.bar_present?.should be_true
      xml.bar?.should be_false
      xml.bar = true
      xml.to_xml.should eq(%(<?xml version="1.0"?>\n<XMLAttrWithQueryAttributes><foo>false</foo><is_bar>true</is_bar></XMLAttrWithQueryAttributes>\n))
    end

    # it "raises if non-nilable attribute is nil" do
    #   string = String.build do |str|
    #     str << "<?xml version=\"1.0\"?>\n"
    #     str << "<XMLAttrWithQueryAttributes>"
    #     str << "<is_bar>true</is_bar>"
    #     str << "</XMLAttrWithQueryAttributes>\n"
    #   end

    #   error_message = <<-'MSG'
    #     Missing XML attribute: foo
    #       parsing XMLAttrWithQueryAttributes at line 1, column 1
    #     MSG
    #   ex = expect_raises ::XML::SerializableError, error_message do
    #     XMLAttrWithQueryAttributes.from_xml(%({"is_bar": true}))
    #   end
    #   ex.location.should eq({1, 1})
    # end
  end

  describe "BigDecimal" do
    it "parses xml string with BigDecimal" do
      string = String.build do |str|
        str << "<?xml version=\"1.0\"?>\n"
        str << "<XMLAttrWithBigDecimal>"
        str << "<value>10.05</value>"
        str << "</XMLAttrWithBigDecimal>\n"
      end

      xml = XMLAttrWithBigDecimal.from_xml(string)
      xml.value.should eq(BigDecimal.new("10.05"))
    end

    it "parses large xml ints with BigDecimal" do
      string = String.build do |str|
        str << "<?xml version=\"1.0\"?>\n"
        str << "<XMLAttrWithBigDecimal>"
        str << "<value>9223372036854775808</value>"
        str << "</XMLAttrWithBigDecimal>\n"
      end

      xml = XMLAttrWithBigDecimal.from_xml(string)
      xml.value.should eq(BigDecimal.new("9223372036854775808"))
    end

    it "parses xml float with BigDecimal" do
      string = String.build do |str|
        str << "<?xml version=\"1.0\"?>\n"
        str << "<XMLAttrWithBigDecimal>"
        str << "<value>10.05</value>"
        str << "</XMLAttrWithBigDecimal>\n"
      end

      xml = XMLAttrWithBigDecimal.from_xml(string)
      xml.value.should eq(BigDecimal.new("10.05"))
    end

    it "parses large precision xml floats with BigDecimal" do
      string = String.build do |str|
        str << "<?xml version=\"1.0\"?>\n"
        str << "<XMLAttrWithBigDecimal>"
        str << "<value>0.00045808999999999997</value>"
        str << "</XMLAttrWithBigDecimal>\n"
      end

      xml = XMLAttrWithBigDecimal.from_xml(string)
      xml.value.should eq(BigDecimal.new("0.00045808999999999997"))
    end
  end

  describe "work with module and inheritance" do
    string = String.build do |str|
      str << "<?xml version=\"1.0\"?>\n"
      str << "<XMLAttrModuleTest>"
      str << "<phoo>20</phoo>"
      str << "</XMLAttrModuleTest>\n"
    end
    string2 = String.build do |str|
      str << "<?xml version=\"1.0\"?>\n"
      str << "<XMLAttrModuleTest>"
      str << "<phoo>20</phoo>"
      str << "<bar>30</bar>"
      str << "</XMLAttrModuleTest>\n"
    end
    string3 = String.build do |str|
      str << "<?xml version=\"1.0\"?>\n"
      str << "<XMLAttrModuleTest>"
      str << "<bar>30</bar>"
      str << "<moo>40</moo>"
      str << "</XMLAttrModuleTest>\n"
    end

    it { XMLAttrModuleTest.from_xml(string).to_tuple.should eq({10, 20}) }
    it { XMLAttrModuleTest.from_xml(string).to_tuple.should eq({10, 20}) }
    it { XMLAttrModuleTest2.from_xml(string2).to_tuple.should eq({10, 20, 30}) }
    it { XMLAttrModuleTest2.from_xml(string3).to_tuple.should eq({40, 15, 30}) }
  end

  # it "works together with yaml" do
  #   person = JSONAttrPersonWithYAML.new("Vasya", 30)
  #   person.to_json.should eq "{\"name\":\"Vasya\",\"age\":30}"
  #   person.to_yaml.should eq "---\nname: Vasya\nage: 30\n"

  #   JSONAttrPersonWithYAML.from_json(person.to_json).should eq person
  #   JSONAttrPersonWithYAML.from_yaml(person.to_yaml).should eq person
  # end

  # it "yaml and json with after_initialize hook" do
  #   person = JSONAttrPersonWithYAMLInitializeHook.new("Vasya", 30)
  #   person.msg.should eq "Hello Vasya"

  #   person.to_json.should eq "{\"name\":\"Vasya\",\"age\":30}"
  #   person.to_yaml.should eq "---\nname: Vasya\nage: 30\n"

  #   JSONAttrPersonWithYAMLInitializeHook.from_json(person.to_json).msg.should eq "Hello Vasya"
  #   JSONAttrPersonWithYAMLInitializeHook.from_yaml(person.to_yaml).msg.should eq "Hello Vasya"
  # end

  # it "json with selective serialization" do
  #   person = JSONAttrPersonWithSelectiveSerialization.new("Vasya", "P@ssw0rd")
  #   person.to_json.should eq "{\"name\":\"Vasya\",\"generated\":\"generated-internally\"}"

  #   person_json = "{\"name\":\"Vasya\",\"generated\":\"should not set\",\"password\":\"update\"}"
  #   person = JSONAttrPersonWithSelectiveSerialization.from_json(person_json)
  #   person.generated.should eq "generated-internally"
  #   person.password.should eq "update"
  # end

  # describe "use_xml_discriminator" do
  #   it "deserializes with discriminator" do
  #     string = String.build do |str|
  #       str << "<?xml version=\"1.0\"?>\n"
  #       str << "<XMLShape>"
  #       str << "<type>point</type>"
  #       str << "<x>1</x>"
  #       str << "<y>2</y>"
  #       str << "</XMLShape>\n"
  #     end

  #     point = XMLShape.from_xml(string).as(XMLPoint)
  #     point.x.should eq(1)
  #     point.y.should eq(2)

  #     string2 = String.build do |str|
  #       str << "<?xml version=\"1.0\"?>\n"
  #       str << "<XMLShape>"
  #       str << "<type>circle</type>"
  #       str << "<x>1</x>"
  #       str << "<y>2</y>"
  #       str << "<radius>3</radius>"
  #       str << "</XMLShape>\n"
  #     end
  #     circle = XMLShape.from_xml(string2).as(XMLCircle)
  #     circle.x.should eq(1)
  #     circle.y.should eq(2)
  #     circle.radius.should eq(3)
  #   end

  #   it "raises if missing discriminator" do
  #     expect_raises(::JSON::SerializableError, "Missing JSON discriminator field 'type'") do
  #       JSONShape.from_json("{}")
  #     end
  #   end

  #   it "raises if unknown discriminator value" do
  #     expect_raises(::JSON::SerializableError, %(Unknown 'type' discriminator value: "unknown")) do
  #       JSONShape.from_json(%({"type": "unknown"}))
  #     end
  #   end

  #   it "deserializes with variable discriminator value type" do
  #     object_number = JSONVariableDiscriminatorValueType.from_json(%({"type": 0}))
  #     object_number.should be_a(JSONVariableDiscriminatorNumber)

  #     object_string = JSONVariableDiscriminatorValueType.from_json(%({"type": "1"}))
  #     object_string.should be_a(JSONVariableDiscriminatorString)

  #     object_bool = JSONVariableDiscriminatorValueType.from_json(%({"type": true}))
  #     object_bool.should be_a(JSONVariableDiscriminatorBool)

  #     object_enum = JSONVariableDiscriminatorValueType.from_json(%({"type": 4}))
  #     object_enum.should be_a(JSONVariableDiscriminatorEnum)

  #     object_enum = JSONVariableDiscriminatorValueType.from_json(%({"type": 18}))
  #     object_enum.should be_a(JSONVariableDiscriminatorEnum8)
  #   end
  # end

  # describe "namespaced classes" do
  #   it "lets default values use the object's own namespace" do
  #     string = String.build do |str|
  #       str << "<?xml version=\"1.0\"?>\n"
  #       str << "<XMLNamespace::FooRequest>"
  #       str << "<foo/>"
  #       str << "</XMLNamespace::FooRequest>\n"
  #     end

  #     request = XMLNamespace::FooRequest.from_xml(%({"foo":{}}))
  #     request.foo.id.should eq "id:foo"
  #     request.bar.id.should eq "id:bar"
  #   end
  # end
end
