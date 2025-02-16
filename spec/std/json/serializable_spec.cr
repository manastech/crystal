require "../spec_helper"
require "json"
require "yaml"
require "big"
require "big/json"
require "uuid"
require "uuid/json"

class JSONAttrValue(T)
  include JSON::Serializable

  property value : T
end

record JSONAttrPoint, x : Int32, y : Int32 do
  include JSON::Serializable
end

class JSONAttrEmptyClass
  include JSON::Serializable

  def initialize; end
end

class JSONAttrEmptyClassWithUnmapped
  include JSON::Serializable
  include JSON::Serializable::Unmapped

  def initialize; end
end

class JSONAttrPerson
  include JSON::Serializable

  property name : String
  property age : Int32?

  def_equals name, age

  def initialize(@name : String)
  end
end

struct JSONAttrPersonWithTwoFieldInInitialize
  include JSON::Serializable

  property name : String
  property age : Int32

  def initialize(@name, @age)
  end
end

class StrictJSONAttrPerson
  include JSON::Serializable
  include JSON::Serializable::Strict

  property name : String
  property age : Int32?
end

class JSONAttrPersonExtraFields
  include JSON::Serializable
  include JSON::Serializable::Unmapped

  property name : String
  property age : Int32?
end

class JSONAttrPersonEmittingNull
  include JSON::Serializable

  property name : String

  @[JSON::Field(emit_null: true)]
  property age : Int32?
end

@[JSON::Serializable::Options(emit_nulls: true)]
class JSONAttrPersonEmittingNullsByOptions
  include JSON::Serializable

  property name : String
  property age : Int32?
  property value1 : Int32?

  @[JSON::Field(emit_null: false)]
  property value2 : Int32?
end

class JSONAttrWithTime
  include JSON::Serializable

  @[JSON::Field(converter: Time::Format.new("%F %T"))]
  property value : Time
end

class JSONAttrWithNilableTime
  include JSON::Serializable

  @[JSON::Field(converter: Time::Format.new("%F"))]
  property value : Time?

  def initialize
  end
end

class JSONAttrWithNilableTimeEmittingNull
  include JSON::Serializable

  @[JSON::Field(converter: Time::Format.new("%F"), emit_null: true)]
  property value : Time?

  def initialize
  end
end

class JSONAttrWithTimeArray1
  include JSON::Serializable

  @[JSON::Field(converter: JSON::ArrayConverter(Time::EpochConverter))]
  property value : Array(Time)
end

class JSONAttrWithTimeArray2
  include JSON::Serializable

  @[JSON::Field(converter: JSON::ArrayConverter.new(Time::EpochConverter))]
  property value : Array(Time)
end

class JSONAttrWithTimeArray3
  include JSON::Serializable

  @[JSON::Field(converter: JSON::ArrayConverter.new(Time::Format.new("%F %T")))]
  property value : Array(Time)
end

class JSONAttrWithTimeHash1
  include JSON::Serializable

  @[JSON::Field(converter: JSON::HashValueConverter(Time::EpochConverter))]
  property value : Hash(String, Time)
end

class JSONAttrWithTimeHash2
  include JSON::Serializable

  @[JSON::Field(converter: JSON::HashValueConverter.new(Time::EpochConverter))]
  property value : Hash(String, Time)
end

class JSONAttrWithTimeHash3
  include JSON::Serializable

  @[JSON::Field(converter: JSON::HashValueConverter.new(Time::Format.new("%F %T")))]
  property value : Hash(String, Time)
end

class JSONAttrWithSimpleMapping
  include JSON::Serializable

  property name : String
  property age : Int32
end

class JSONAttrWithKeywordsMapping
  include JSON::Serializable

  property end : Int32
  property abstract : Int32
end

class JSONAttrWithAny
  include JSON::Serializable

  property name : String
  property any : JSON::Any
end

class JSONAttrWithProblematicKeys
  include JSON::Serializable

  property key : Int32
  property pull : Int32
end

class JSONAttrWithDefaults
  include JSON::Serializable

  property a = 11
  property b = "Haha"
  property c = true
  property d = false
  property e : Bool? = false
  property f : Int32? = 1
  property g : Int32?
  property h = [1, 2, 3]
end

class JSONAttrWithSmallIntegers
  include JSON::Serializable

  property foo : Int16
  property bar : Int8
end

class JSONAttrWithTimeEpoch
  include JSON::Serializable

  @[JSON::Field(converter: Time::EpochConverter)]
  property value : Time
end

class JSONAttrNilableWithTimeEpoch
  include JSON::Serializable

  @[JSON::Field(converter: Time::EpochConverter)]
  property value : Time?
end

class JSONAttrDefaultWithTimeEpoch
  include JSON::Serializable

  @[JSON::Field(converter: Time::EpochConverter)]
  property value : Time = Time.unix(0)
end

class JSONAttrWithTimeEpochMillis
  include JSON::Serializable

  @[JSON::Field(converter: Time::EpochMillisConverter)]
  property value : Time
end

class JSONAttrWithRaw
  include JSON::Serializable

  @[JSON::Field(converter: String::RawConverter)]
  property value : String
end

class JSONAttrWithRoot
  include JSON::Serializable

  @[JSON::Field(root: "heroes")]
  property result : Array(JSONAttrPerson)
end

class JSONAttrWithNilableRoot
  include JSON::Serializable

  @[JSON::Field(root: "heroes")]
  property result : Array(JSONAttrPerson)?
end

class JSONAttrWithNilableRootEmitNull
  include JSON::Serializable

  @[JSON::Field(root: "heroes", emit_null: true)]
  property result : Array(JSONAttrPerson)?
end

class JSONAttrWithPresence
  include JSON::Serializable

  @[JSON::Field(presence: true)]
  property first_name : String?

  @[JSON::Field(presence: true)]
  property last_name : String?

  @[JSON::Field(ignore: true)]
  getter? first_name_present : Bool

  @[JSON::Field(ignore: true)]
  getter? last_name_present : Bool
end

class JSONAttrWithPresenceAndIgnoreSerialize
  include JSON::Serializable

  @[JSON::Field(presence: true, ignore_serialize: ignore_first_name?)]
  property first_name : String?

  @[JSON::Field(presence: true, ignore_serialize: last_name.nil? && !last_name_present?, emit_null: true)]
  property last_name : String?

  @[JSON::Field(ignore: true)]
  getter? first_name_present : Bool = false

  @[JSON::Field(ignore: true)]
  getter? last_name_present : Bool = false

  def initialize(@first_name : String? = nil, @last_name : String? = nil)
  end

  def ignore_first_name?
    first_name.nil? || first_name == ""
  end
end

class JSONAttrWithQueryAttributes
  include JSON::Serializable

  property? foo : Bool

  @[JSON::Field(key: "is_bar", presence: true)]
  property? bar : Bool = false

  @[JSON::Field(ignore: true)]
  getter? bar_present : Bool
end

module JSONAttrModule
  property moo : Int32 = 10
end

class JSONAttrModuleTest
  include JSONAttrModule
  include JSON::Serializable

  @[JSON::Field(key: "phoo")]
  property foo = 15

  def initialize; end

  def to_tuple
    {@moo, @foo}
  end
end

class JSONAttrModuleTest2 < JSONAttrModuleTest
  property bar : Int32

  def initialize(@bar : Int32); end

  def to_tuple
    {@moo, @foo, @bar}
  end
end

struct JSONAttrPersonWithYAML
  include JSON::Serializable
  include YAML::Serializable

  property name : String
  property age : Int32?

  def initialize(@name : String, @age : Int32? = nil)
  end
end

struct JSONAttrPersonWithYAMLInitializeHook
  include JSON::Serializable
  include YAML::Serializable

  property name : String
  property age : Int32?

  def initialize(@name : String, @age : Int32? = nil)
    after_initialize
  end

  @[JSON::Field(ignore: true)]
  @[YAML::Field(ignore: true)]
  property msg : String?

  def after_initialize
    @msg = "Hello " + name
  end
end

struct JSONAttrPersonWithSelectiveSerialization
  include JSON::Serializable

  property name : String

  @[JSON::Field(ignore_serialize: true)]
  property password : String

  @[JSON::Field(ignore_deserialize: true)]
  property generated : String = "generated-internally"

  def initialize(@name : String, @password : String)
  end
end

abstract class JSONShape
  include JSON::Serializable

  use_json_discriminator "type", {point: JSONPoint, circle: JSONCircle}

  property type : String
end

class JSONPoint < JSONShape
  property x : Int32
  property y : Int32
end

class JSONCircle < JSONShape
  property x : Int32
  property y : Int32
  property radius : Int32
end

enum JSONVariableDiscriminatorEnumFoo
  Foo = 4
end

enum JSONVariableDiscriminatorEnumFoo8 : UInt8
  Foo = 1_8
end

class JSONVariableDiscriminatorValueType
  include JSON::Serializable

  use_json_discriminator "type", {
                                         0 => JSONVariableDiscriminatorNumber,
    "1"                                    => JSONVariableDiscriminatorString,
    true                                   => JSONVariableDiscriminatorBoolTrue,
    false                                  => JSONVariableDiscriminatorBoolFalse,
    JSONVariableDiscriminatorEnumFoo::Foo  => JSONVariableDiscriminatorEnum,
    JSONVariableDiscriminatorEnumFoo8::Foo => JSONVariableDiscriminatorEnum8,
  }
end

class JSONVariableDiscriminatorNumber < JSONVariableDiscriminatorValueType
end

class JSONVariableDiscriminatorString < JSONVariableDiscriminatorValueType
end

class JSONVariableDiscriminatorBoolTrue < JSONVariableDiscriminatorValueType
end

class JSONVariableDiscriminatorBoolFalse < JSONVariableDiscriminatorValueType
end

class JSONVariableDiscriminatorEnum < JSONVariableDiscriminatorValueType
end

class JSONVariableDiscriminatorEnum8 < JSONVariableDiscriminatorValueType
end

class JSONStrictDiscriminator
  include JSON::Serializable
  include JSON::Serializable::Strict

  property type : String

  use_json_discriminator "type", {foo: JSONStrictDiscriminatorFoo, bar: JSONStrictDiscriminatorBar}
end

class JSONStrictDiscriminatorFoo < JSONStrictDiscriminator
end

class JSONStrictDiscriminatorBar < JSONStrictDiscriminator
  property x : JSONStrictDiscriminator
  property y : JSONStrictDiscriminator
end

module JSONNamespace
  struct FooRequest
    include JSON::Serializable

    getter foo : Foo
    getter bar = Bar.new
  end

  struct Foo
    include JSON::Serializable
    getter id = "id:foo"
  end

  struct Bar
    include JSON::Serializable
    getter id = "id:bar"

    def initialize # Allow for default value above
    end
  end
end

class JSONSomething
  include JSON::Serializable

  property value : JSONSomething?
end

module JsonDiscriminatorBug
  abstract class Base
    include JSON::Serializable

    use_json_discriminator("type", {"a" => A, "b" => B, "c" => C})
  end

  class A < Base
  end

  class B < Base
    property source : Base
    property value : Int32 = 1
  end

  class C < B
  end
end

describe "JSON mapping" do
  it "works with record" do
    JSONAttrPoint.new(1, 2).to_json.should eq "{\"x\":1,\"y\":2}"
    JSONAttrPoint.from_json(%({"x": 1, "y": 2})).should eq JSONAttrPoint.new(1, 2)
  end

  it "empty class" do
    e = JSONAttrEmptyClass.new
    e.to_json.should eq "{}"
    JSONAttrEmptyClass.from_json("{}")
  end

  it "empty class with unmapped" do
    JSONAttrEmptyClassWithUnmapped.from_json(%({"name": "John", "age": 30})).json_unmapped.should eq({"name" => "John", "age" => 30})
  end

  it "parses person" do
    person = JSONAttrPerson.from_json(%({"name": "John", "age": 30}))
    person.should be_a(JSONAttrPerson)
    person.name.should eq("John")
    person.age.should eq(30)
  end

  it "parses person without age" do
    person = JSONAttrPerson.from_json(%({"name": "John"}))
    person.should be_a(JSONAttrPerson)
    person.name.should eq("John")
    person.name.size.should eq(4) # This verifies that name is not nilable
    person.age.should be_nil
  end

  it "parses array of people" do
    people = Array(JSONAttrPerson).from_json(%([{"name": "John"}, {"name": "Doe"}]))
    people.size.should eq(2)
  end

  it "works with class with two fields" do
    person1 = JSONAttrPersonWithTwoFieldInInitialize.from_json(%({"name": "John", "age": 30}))
    person2 = JSONAttrPersonWithTwoFieldInInitialize.new("John", 30)
    person1.should eq person2
  end

  it "does to_json" do
    person = JSONAttrPerson.from_json(%({"name": "John", "age": 30}))
    person2 = JSONAttrPerson.from_json(person.to_json)
    person2.should eq(person)
  end

  it "parses person with unknown attributes" do
    person = JSONAttrPerson.from_json(%({"name": "John", "age": 30, "foo": "bar"}))
    person.should be_a(JSONAttrPerson)
    person.name.should eq("John")
    person.age.should eq(30)
  end

  it "parses strict person with unknown attributes" do
    error_message = <<-'MSG'
      Unknown JSON attribute: foo
        parsing StrictJSONAttrPerson
      MSG
    ex = expect_raises ::JSON::SerializableError, error_message do
      StrictJSONAttrPerson.from_json <<-JSON
        {
          "name": "John",
          "age": 30,
          "foo": "bar"
        }
        JSON
    end
    ex.location.should eq({4, 3})
  end

  it "should parse extra fields (JSONAttrPersonExtraFields with on_unknown_json_attribute)" do
    person = JSONAttrPersonExtraFields.from_json(%({"name": "John", "age": 30, "x": "1", "y": 2, "z": [1,2,3]}))
    person.name.should eq("John")
    person.age.should eq(30)
    person.json_unmapped.should eq({"x" => "1", "y" => 2_i64, "z" => [1, 2, 3]})
  end

  it "should to store extra fields (JSONAttrPersonExtraFields with on_to_json)" do
    person = JSONAttrPersonExtraFields.from_json(%({"name": "John", "age": 30, "x": "1", "y": 2, "z": [1,2,3]}))
    person.name = "John1"
    person.json_unmapped.delete("y")
    person.json_unmapped["q"] = JSON::Any.new("w")
    person.to_json.should eq "{\"name\":\"John1\",\"age\":30,\"x\":\"1\",\"z\":[1,2,3],\"q\":\"w\"}"
  end

  it "raises if non-nilable attribute is nil" do
    error_message = <<-'MSG'
      Missing JSON attribute: name
        parsing JSONAttrPerson at line 1, column 1
      MSG
    ex = expect_raises ::JSON::SerializableError, error_message do
      JSONAttrPerson.from_json(%({"age": 30}))
    end
    ex.location.should eq({1, 1})
  end

  it "raises if not an object" do
    error_message = <<-'MSG'
      Expected BeginObject but was String at line 1, column 1
        parsing StrictJSONAttrPerson at line 0, column 0
      MSG
    ex = expect_raises ::JSON::SerializableError, error_message do
      StrictJSONAttrPerson.from_json <<-JSON
        "foo"
        JSON
    end
    ex.location.should eq({1, 1})
  end

  it "raises if data type does not match" do
    error_message = <<-MSG
      Couldn't parse (Int32 | Nil) from "foo" at line 3, column 10
      MSG
    ex = expect_raises ::JSON::SerializableError, error_message do
      StrictJSONAttrPerson.from_json <<-JSON
        {
          "name": "John",
          "age": "foo",
          "foo": "bar"
        }
        JSON
    end
    ex.location.should eq({3, 10})
  end

  it "doesn't emit null by default when doing to_json" do
    person = JSONAttrPerson.from_json(%({"name": "John"}))
    person.to_json.should_not match /age/
  end

  it "emits null on request when doing to_json" do
    person = JSONAttrPersonEmittingNull.from_json(%({"name": "John"}))
    person.to_json.should match /age/
  end

  it "emit_nulls option" do
    person = JSONAttrPersonEmittingNullsByOptions.from_json(%({"name": "John"}))
    person.to_json.should eq "{\"name\":\"John\",\"age\":null,\"value1\":null}"
  end

  it "doesn't raises on false value when not-nil" do
    json = JSONAttrValue(Bool).from_json(%({"value": false}))
    json.value.should be_false
  end

  it "parses JSON integer into a float property (#8618)" do
    json = JSONAttrValue(Float64).from_json(%({"value": 123}))
    json.value.should eq(123.0)
  end

  it "parses UUID" do
    uuid = JSONAttrValue(UUID).from_json(%({"value": "ba714f86-cac6-42c7-8956-bcf5105e1b81"}))
    uuid.should be_a(JSONAttrValue(UUID))
    uuid.value.should eq(UUID.new("ba714f86-cac6-42c7-8956-bcf5105e1b81"))
  end

  it "parses json with Time::Format converter" do
    json = JSONAttrWithTime.from_json(%({"value": "2014-10-31 23:37:16"}))
    json.value.should be_a(Time)
    json.value.to_s.should eq("2014-10-31 23:37:16 UTC")
    json.to_json.should eq(%({"value":"2014-10-31 23:37:16"}))
  end

  it "allows setting a nilable property to nil" do
    person = JSONAttrPerson.new("John")
    person.age = 1
    person.age = nil
  end

  it "parses simple mapping" do
    person = JSONAttrWithSimpleMapping.from_json(%({"name": "John", "age": 30}))
    person.should be_a(JSONAttrWithSimpleMapping)
    person.name.should eq("John")
    person.age.should eq(30)
  end

  it "outputs with converter when nilable" do
    json = JSONAttrWithNilableTime.new
    json.to_json.should eq("{}")
  end

  it "outputs with converter when nilable when emit_null is true" do
    json = JSONAttrWithNilableTimeEmittingNull.new
    json.to_json.should eq(%({"value":null}))
  end

  it "outputs JSON with Hash" do
    input = {
      value: {"foo" => "bar"},
    }.to_json
    json = JSONAttrValue(Hash(String, String)).from_json(input)
    json.to_json.should eq(input)
  end

  it "parses json with keywords" do
    json = JSONAttrWithKeywordsMapping.from_json(%({"end": 1, "abstract": 2}))
    json.end.should eq(1)
    json.abstract.should eq(2)
  end

  it "parses json with any" do
    json = JSONAttrWithAny.from_json(%({"name": "Hi", "any": [{"x": 1}, 2, "hey", true, false, 1.5, null]}))
    json.name.should eq("Hi")
    json.any.raw.should eq([{"x" => 1}, 2, "hey", true, false, 1.5, nil])
    json.to_json.should eq(%({"name":"Hi","any":[{"x":1},2,"hey",true,false,1.5,null]}))
  end

  it "parses json with problematic keys" do
    json = JSONAttrWithProblematicKeys.from_json(%({"key": 1, "pull": 2}))
    json.key.should eq(1)
    json.pull.should eq(2)
  end

  it "parses json array as set" do
    json = JSONAttrValue(Set(String)).from_json(%({"value": ["a", "a", "b"]}))
    json.value.should eq(Set(String){"a", "b"})
  end

  it "allows small types of integer" do
    json = JSONAttrWithSmallIntegers.from_json(%({"foo": 23, "bar": 7}))

    json.foo.should eq(23)
    typeof(json.foo).should eq(Int16)

    json.bar.should eq(7)
    typeof(json.bar).should eq(Int8)
  end

  describe "parses json with defaults" do
    it "mixed" do
      json = JSONAttrWithDefaults.from_json(%({"a":1,"b":"bla"}))
      json.a.should eq 1
      json.b.should eq "bla"

      json = JSONAttrWithDefaults.from_json(%({"a":1}))
      json.a.should eq 1
      json.b.should eq "Haha"

      json = JSONAttrWithDefaults.from_json(%({"b":"bla"}))
      json.a.should eq 11
      json.b.should eq "bla"

      json = JSONAttrWithDefaults.from_json(%({}))
      json.a.should eq 11
      json.b.should eq "Haha"

      json = JSONAttrWithDefaults.from_json(%({"a":null,"b":null,"f":null}))
      json.a.should eq 11
      json.b.should eq "Haha"
      json.f.should be_nil
    end

    it "bool" do
      json = JSONAttrWithDefaults.from_json(%({}))
      json.c.should eq true
      typeof(json.c).should eq Bool
      json.d.should eq false
      typeof(json.d).should eq Bool

      json = JSONAttrWithDefaults.from_json(%({"c":false}))
      json.c.should eq false
      json = JSONAttrWithDefaults.from_json(%({"c":true}))
      json.c.should eq true

      json = JSONAttrWithDefaults.from_json(%({"d":false}))
      json.d.should eq false
      json = JSONAttrWithDefaults.from_json(%({"d":true}))
      json.d.should eq true
    end

    it "with nilable" do
      json = JSONAttrWithDefaults.from_json(%({}))

      json.e.should eq false
      typeof(json.e).should eq(Bool | Nil)

      json.f.should eq 1
      typeof(json.f).should eq(Int32 | Nil)

      json.g.should eq nil
      typeof(json.g).should eq(Int32 | Nil)

      json = JSONAttrWithDefaults.from_json(%({"e":false}))
      json.e.should eq false
      json = JSONAttrWithDefaults.from_json(%({"e":true}))
      json.e.should eq true
    end

    it "create new array every time" do
      json = JSONAttrWithDefaults.from_json(%({}))
      json.h.should eq [1, 2, 3]
      json.h << 4
      json.h.should eq [1, 2, 3, 4]

      json = JSONAttrWithDefaults.from_json(%({}))
      json.h.should eq [1, 2, 3]
    end
  end

  it "converter with null value (#13655)" do
    JSONAttrNilableWithTimeEpoch.from_json(%({"value": null})).value.should be_nil
    JSONAttrNilableWithTimeEpoch.from_json(%({"value":1459859781})).value.should eq Time.unix(1459859781)
  end

  it "converter with default value" do
    JSONAttrDefaultWithTimeEpoch.from_json(%({"value": null})).value.should eq Time.unix(0)
    JSONAttrDefaultWithTimeEpoch.from_json(%({"value":1459859781})).value.should eq Time.unix(1459859781)
  end

  it "uses Time::EpochConverter" do
    string = %({"value":1459859781})
    json = JSONAttrWithTimeEpoch.from_json(string)
    json.value.should be_a(Time)
    json.value.should eq(Time.unix(1459859781))
    json.to_json.should eq(string)
  end

  it "uses Time::EpochMillisConverter" do
    string = %({"value":1459860483856})
    json = JSONAttrWithTimeEpochMillis.from_json(string)
    json.value.should be_a(Time)
    json.value.should eq(Time.unix_ms(1459860483856))
    json.to_json.should eq(string)
  end

  describe JSON::ArrayConverter do
    it "uses converter metaclass" do
      string = %({"value":[1459859781]})
      json = JSONAttrWithTimeArray1.from_json(string)
      json.value.should be_a(Array(Time))
      json.value.should eq([Time.unix(1459859781)])
      json.to_json.should eq(string)
    end

    it "uses converter instance with nested converter metaclass" do
      string = %({"value":[1459859781]})
      json = JSONAttrWithTimeArray2.from_json(string)
      json.value.should be_a(Array(Time))
      json.value.should eq([Time.unix(1459859781)])
      json.to_json.should eq(string)
    end

    it "uses converter instance with nested converter instance" do
      string = %({"value":["2014-10-31 23:37:16"]})
      json = JSONAttrWithTimeArray3.from_json(string)
      json.value.should be_a(Array(Time))
      json.value.map(&.to_s).should eq(["2014-10-31 23:37:16 UTC"])
      json.to_json.should eq(string)
    end
  end

  describe JSON::HashValueConverter do
    it "uses converter metaclass" do
      string = %({"value":{"foo":1459859781}})
      json = JSONAttrWithTimeHash1.from_json(string)
      json.value.should be_a(Hash(String, Time))
      json.value.should eq({"foo" => Time.unix(1459859781)})
      json.to_json.should eq(string)
    end

    it "uses converter instance with nested converter metaclass" do
      string = %({"value":{"foo":1459859781}})
      json = JSONAttrWithTimeHash2.from_json(string)
      json.value.should be_a(Hash(String, Time))
      json.value.should eq({"foo" => Time.unix(1459859781)})
      json.to_json.should eq(string)
    end

    it "uses converter instance with nested converter instance" do
      string = %({"value":{"foo":"2014-10-31 23:37:16"}})
      json = JSONAttrWithTimeHash3.from_json(string)
      json.value.should be_a(Hash(String, Time))
      json.value.transform_values(&.to_s).should eq({"foo" => "2014-10-31 23:37:16 UTC"})
      json.to_json.should eq(string)
    end
  end

  it "parses raw value from int" do
    string = %({"value":123456789123456789123456789123456789})
    json = JSONAttrWithRaw.from_json(string)
    json.value.should eq("123456789123456789123456789123456789")
    json.to_json.should eq(string)
  end

  it "parses raw value from float" do
    string = %({"value":123456789123456789.123456789123456789})
    json = JSONAttrWithRaw.from_json(string)
    json.value.should eq("123456789123456789.123456789123456789")
    json.to_json.should eq(string)
  end

  it "parses raw value from object" do
    string = %({"value":[null,true,false,{"x":[1,1.5]}]})
    json = JSONAttrWithRaw.from_json(string)
    json.value.should eq(%([null,true,false,{"x":[1,1.5]}]))
    json.to_json.should eq(string)
  end

  it "parses with root" do
    json = %({"result":{"heroes":[{"name":"Batman"}]}})
    result = JSONAttrWithRoot.from_json(json)
    result.result.should be_a(Array(JSONAttrPerson))
    result.result.first.name.should eq "Batman"
    result.to_json.should eq(json)
  end

  it "parses with nilable root" do
    json = %({"result":null})
    result = JSONAttrWithNilableRoot.from_json(json)
    result.result.should be_nil
    result.to_json.should eq("{}")
  end

  it "parses with nilable root and emit null" do
    json = %({"result":null})
    result = JSONAttrWithNilableRootEmitNull.from_json(json)
    result.result.should be_nil
    result.to_json.should eq(json)
  end

  it "parses nilable union" do
    obj = JSONAttrValue(Int32?).from_json(%({"value": 1}))
    obj.value.should eq(1)
    obj.to_json.should eq(%({"value":1}))

    obj = JSONAttrValue(Int32?).from_json(%({"value": null}))
    obj.value.should be_nil
    obj.to_json.should eq(%({}))

    obj = JSONAttrValue(Int32?).from_json(%({}))
    obj.value.should be_nil
    obj.to_json.should eq(%({}))
  end

  describe "parses JSON with presence markers" do
    it "parses person with absent attributes" do
      json = JSONAttrWithPresence.from_json(%({"first_name": null}))
      json.first_name.should be_nil
      json.first_name_present?.should be_true
      json.last_name.should be_nil
      json.last_name_present?.should be_false
    end
  end

  describe "serializes JSON with presence markers and ignore_serialize" do
    context "ignore_serialize is set to a method which returns true when value is nil or empty string" do
      it "ignores field when value is empty string" do
        json = JSONAttrWithPresenceAndIgnoreSerialize.from_json(%({"first_name": ""}))
        json.first_name_present?.should be_true
        json.to_json.should eq(%({}))
      end

      it "ignores field when value is nil" do
        json = JSONAttrWithPresenceAndIgnoreSerialize.from_json(%({"first_name": null}))
        json.first_name_present?.should be_true
        json.to_json.should eq(%({}))
      end
    end

    context "ignore_serialize is set to conditional expressions 'last_name.nil? && !last_name_present?'" do
      it "emits null when value is null and @last_name_present is true" do
        json = JSONAttrWithPresenceAndIgnoreSerialize.from_json(%({"last_name": null}))
        json.last_name_present?.should be_true
        json.to_json.should eq(%({"last_name":null}))
      end

      it "does not emit null when value is null and @last_name_present is false" do
        json = JSONAttrWithPresenceAndIgnoreSerialize.from_json(%({}))
        json.last_name_present?.should be_false
        json.to_json.should eq(%({}))
      end

      it "emits field when value is not nil and @last_name_present is false" do
        json = JSONAttrWithPresenceAndIgnoreSerialize.new(last_name: "something")
        json.last_name_present?.should be_false
        json.to_json.should eq(%({"last_name":"something"}))
      end

      it "emits field when value is not nil and @last_name_present is true" do
        json = JSONAttrWithPresenceAndIgnoreSerialize.from_json(%({"last_name":"something"}))
        json.last_name_present?.should be_true
        json.to_json.should eq(%({"last_name":"something"}))
      end
    end
  end

  describe "with query attributes" do
    it "defines query getter" do
      json = JSONAttrWithQueryAttributes.from_json(%({"foo": true}))
      json.foo?.should be_true
      json.bar?.should be_false
    end

    it "defines query getter with class restriction" do
      {% begin %}
        {% methods = JSONAttrWithQueryAttributes.methods %}
        {{ methods.find(&.name.==("foo?")).return_type }}.should eq(Bool)
        {{ methods.find(&.name.==("bar?")).return_type }}.should eq(Bool)
      {% end %}
    end

    it "defines non-query setter and presence methods" do
      json = JSONAttrWithQueryAttributes.from_json(%({"foo": false}))
      json.bar_present?.should be_false
      json.bar = true
      json.bar?.should be_true
    end

    it "maps non-query attributes" do
      json = JSONAttrWithQueryAttributes.from_json(%({"foo": false, "is_bar": false}))
      json.bar_present?.should be_true
      json.bar?.should be_false
      json.bar = true
      json.to_json.should eq(%({"foo":false,"is_bar":true}))
    end

    it "raises if non-nilable attribute is nil" do
      error_message = <<-'MSG'
        Missing JSON attribute: foo
          parsing JSONAttrWithQueryAttributes at line 1, column 1
        MSG
      ex = expect_raises ::JSON::SerializableError, error_message do
        JSONAttrWithQueryAttributes.from_json(%({"is_bar": true}))
      end
      ex.location.should eq({1, 1})
    end
  end

  describe "BigDecimal" do
    it "parses json string with BigDecimal" do
      json = JSONAttrValue(BigDecimal).from_json(%({"value": "10.05"}))
      json.value.should eq(BigDecimal.new("10.05"))
    end

    it "parses large json ints with BigDecimal" do
      json = JSONAttrValue(BigDecimal).from_json(%({"value": 9223372036854775808}))
      json.value.should eq(BigDecimal.new("9223372036854775808"))
    end

    it "parses json float with BigDecimal" do
      json = JSONAttrValue(BigDecimal).from_json(%({"value": 10.05}))
      json.value.should eq(BigDecimal.new("10.05"))
    end

    it "parses large precision json floats with BigDecimal" do
      json = JSONAttrValue(BigDecimal).from_json(%({"value": 0.00045808999999999997}))
      json.value.should eq(BigDecimal.new("0.00045808999999999997"))
    end
  end

  it "parses 128-bit integer" do
    json = JSONAttrValue(Int128).from_json(%({"value": #{Int128::MAX}}))
    json.value.should eq Int128::MAX
  end

  describe "work with module and inheritance" do
    it { JSONAttrModuleTest.from_json(%({"phoo": 20})).to_tuple.should eq({10, 20}) }
    it { JSONAttrModuleTest.from_json(%({"phoo": 20})).to_tuple.should eq({10, 20}) }
    it { JSONAttrModuleTest2.from_json(%({"phoo": 20, "bar": 30})).to_tuple.should eq({10, 20, 30}) }
    it { JSONAttrModuleTest2.from_json(%({"bar": 30, "moo": 40})).to_tuple.should eq({40, 15, 30}) }
  end

  # TODO: add XML support
  it "works together with yaml" do
    person = JSONAttrPersonWithYAML.new("Vasya", 30)
    person.to_json.should eq "{\"name\":\"Vasya\",\"age\":30}"
    person.to_yaml.should eq "---\nname: Vasya\nage: 30\n"

    JSONAttrPersonWithYAML.from_json(person.to_json).should eq person
    JSONAttrPersonWithYAML.from_yaml(person.to_yaml).should eq person
  end

  it "yaml and json with after_initialize hook" do
    person = JSONAttrPersonWithYAMLInitializeHook.new("Vasya", 30)
    person.msg.should eq "Hello Vasya"

    person.to_json.should eq "{\"name\":\"Vasya\",\"age\":30}"
    person.to_yaml.should eq "---\nname: Vasya\nage: 30\n"

    JSONAttrPersonWithYAMLInitializeHook.from_json(person.to_json).msg.should eq "Hello Vasya"
    JSONAttrPersonWithYAMLInitializeHook.from_yaml(person.to_yaml).msg.should eq "Hello Vasya"
  end

  it "json with selective serialization" do
    person = JSONAttrPersonWithSelectiveSerialization.new("Vasya", "P@ssw0rd")
    person.to_json.should eq "{\"name\":\"Vasya\",\"generated\":\"generated-internally\"}"

    person_json = "{\"name\":\"Vasya\",\"generated\":\"should not set\",\"password\":\"update\"}"
    person = JSONAttrPersonWithSelectiveSerialization.from_json(person_json)
    person.generated.should eq "generated-internally"
    person.password.should eq "update"
  end

  describe "use_json_discriminator" do
    it "deserializes with discriminator" do
      point = JSONShape.from_json(%({"type": "point", "x": 1, "y": 2})).as(JSONPoint)
      point.x.should eq(1)
      point.y.should eq(2)

      circle = JSONShape.from_json(%({"type": "circle", "x": 1, "y": 2, "radius": 3})).as(JSONCircle)
      circle.x.should eq(1)
      circle.y.should eq(2)
      circle.radius.should eq(3)
    end

    it "raises if missing discriminator" do
      expect_raises(::JSON::SerializableError, "Missing JSON discriminator field 'type'") do
        JSONShape.from_json("{}")
      end
    end

    it "raises if unknown discriminator value" do
      expect_raises(::JSON::SerializableError, %(Unknown 'type' discriminator value: "unknown")) do
        JSONShape.from_json(%({"type": "unknown"}))
      end
    end

    it "deserializes with variable discriminator value type" do
      object_number = JSONVariableDiscriminatorValueType.from_json(%({"type": 0}))
      object_number.should be_a(JSONVariableDiscriminatorNumber)

      object_string = JSONVariableDiscriminatorValueType.from_json(%({"type": "1"}))
      object_string.should be_a(JSONVariableDiscriminatorString)

      object_bool = JSONVariableDiscriminatorValueType.from_json(%({"type": true}))
      object_bool.should be_a(JSONVariableDiscriminatorBoolTrue)

      object_bool = JSONVariableDiscriminatorValueType.from_json(%({"type": false}))
      object_bool.should be_a(JSONVariableDiscriminatorBoolFalse)

      object_enum = JSONVariableDiscriminatorValueType.from_json(%({"type": 4}))
      object_enum.should be_a(JSONVariableDiscriminatorEnum)

      object_enum = JSONVariableDiscriminatorValueType.from_json(%({"type": 18}))
      object_enum.should be_a(JSONVariableDiscriminatorEnum8)
    end

    it "deserializes with discriminator, strict recursive type" do
      foo = JSONStrictDiscriminator.from_json(%({"type": "foo"}))
      foo = foo.should be_a(JSONStrictDiscriminatorFoo)

      bar = JSONStrictDiscriminator.from_json(%({"type": "bar", "x": {"type": "foo"}, "y": {"type": "foo"}}))
      bar = bar.should be_a(JSONStrictDiscriminatorBar)
      bar.x.should be_a(JSONStrictDiscriminatorFoo)
      bar.y.should be_a(JSONStrictDiscriminatorFoo)
    end

    it "deserializes with discriminator, another recursive type, fixes: #13429" do
      c = JsonDiscriminatorBug::Base.from_json %q({"type": "c", "source": {"type": "a"}, "value": 2})
      c.as(JsonDiscriminatorBug::C).value.should eq 2

      c = JsonDiscriminatorBug::Base.from_json %q({"type": "c", "source": {"type": "a"}})
      c.as(JsonDiscriminatorBug::C).value.should eq 1
    end
  end

  describe "namespaced classes" do
    it "lets default values use the object's own namespace" do
      request = JSONNamespace::FooRequest.from_json(%({"foo":{}}))
      request.foo.id.should eq "id:foo"
      request.bar.id.should eq "id:bar"
    end
  end

  it "fixes #13337" do
    JSONSomething.from_json(%({"value":{}})).value.should_not be_nil
  end
end
