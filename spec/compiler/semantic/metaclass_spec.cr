require "../../spec_helper"

private struct ProperSubtypeExpectation
  def initialize(@expected_value : Crystal::Type?)
  end

  def match(actual_value)
    subtype?(actual_value, @expected_value) && !subtype?(@expected_value, actual_value)
  end

  private def subtype?(t, u)
    if t.is_a?(Crystal::NoReturnType?)
      true
    elsif u.is_a?(Crystal::NoReturnType?)
      false
    else
      t.implements?(u)
    end
  end

  def failure_message(actual_value)
    actual_str = type_to_s(actual_value)
    expected_str = type_to_s(@expected_value)

    String.build do |io|
      io << "Expected: #{actual_str} to be a proper subtype of #{expected_str}, but "
      if !subtype?(actual_value, @expected_value)
        io << "#{actual_str} <= #{expected_str} is false"
      else # subtype?(@expected_value, actual_value)
        io << "#{expected_str} <= #{actual_str} is true"
      end
    end
  end

  def negative_failure_message(actual_value)
    "Expected: #{type_to_s(actual_value)} not to be a proper subtype of #{type_to_s(@expected_value)}"
  end

  private def type_to_s(type)
    case type
    when Nil
      "NoReturn"
    when Crystal::GenericInstanceType, Crystal::GenericClassInstanceMetaclassType, Crystal::GenericModuleInstanceMetaclassType
      type.to_s(generic_args: true)
    else
      type.to_s(generic_args: false)
    end
  end
end

private def be_a_proper_subtype_of(supertype)
  ProperSubtypeExpectation.new(supertype)
end

describe "Semantic: metaclass" do
  it "types Object class" do
    assert_type("Object") { program.object.metaclass }
  end

  it "types Class class" do
    assert_type("Class") { class_type }
  end

  it "types Object and Class metaclasses" do
    assert_type("Object.class", inject_primitives: true) { class_type }
    assert_type("Class.class", inject_primitives: true) { class_type }
  end

  it "types Reference metaclass" do
    assert_type("Reference") { program.reference.metaclass }
    assert_type("Reference.class", inject_primitives: true) { class_type }
  end

  it "types generic class metaclass" do
    assert_type("Pointer") { pointer.metaclass }
    assert_type("Pointer.class", inject_primitives: true) { class_type }
    assert_type("Pointer(Int32)") { pointer_of(int32).metaclass }
    assert_type("Pointer(Int32).class", inject_primitives: true) { class_type }
  end

  it "types generic module metaclass" do
    assert_type("module Foo(T); end; Foo") { types["Foo"].metaclass }
    assert_type("module Foo(T); end; Foo.class", inject_primitives: true) { class_type }
    assert_type("module Foo(T); end; Foo(Int32)") { generic_module("Foo", int32).metaclass }
    assert_type("module Foo(T); end; Foo(Int32).class", inject_primitives: true) { class_type }
  end

  it "types metaclass superclass" do
    mod = semantic(%(
      class Foo; end
      class Bar < Foo; end
      )).program

    bar_class = mod.types["Bar"].metaclass.as(MetaclassType)
    bar_class.superclass.should eq(mod.types["Foo"].metaclass)
  end

  it "types generic metaclass superclass" do
    mod = semantic(%(
      class Foo(T); end
      class Bar(T) < Foo(T); end
      )).program

    foo_class = mod.types["Foo"].metaclass.as(MetaclassType)
    foo_class.superclass.should eq(mod.program.reference.metaclass)

    bar = mod.types["Bar"].as(GenericClassType)
    bar_class = bar.metaclass.as(MetaclassType)
    bar_class.superclass.should eq(mod.generic_class("Foo", bar.type_parameter("T")).metaclass)
  end

  it "types generic instance metaclass superclass" do
    mod = semantic(%(
      class Foo(T); end
      class Bar(T) < Foo(T); end
      )).program

    foo_class = mod.generic_class("Foo", mod.int32).metaclass.as(GenericClassInstanceMetaclassType)
    foo_class.superclass.should eq(mod.program.reference.metaclass)

    bar_class = mod.generic_class("Bar", mod.int32).metaclass.as(GenericClassInstanceMetaclassType)
    bar_class.superclass.should eq(foo_class)
  end

  describe "subtyping relations between metaclasses" do
    it "non-generic classes" do
      mod = semantic(%(
        class Foo; end
        class Bar < Foo; end
        )).program

      foo_class = mod.types["Foo"].metaclass
      bar_class = mod.types["Bar"].metaclass
      bar_class.should be_a_proper_subtype_of(foo_class)
    end

    it "virtual metaclass type with virtual type (#12628)" do
      mod = semantic(%(
        class Base; end
        class Impl < Base; end
        )).program

      base = mod.types["Base"]
      base.virtual_type!.metaclass.implements?(base).should be_false
      base.virtual_type!.metaclass.implements?(base.metaclass).should be_true
      base.virtual_type!.metaclass.implements?(base.metaclass.virtual_type!).should be_true
    end

    it "generic classes (1)" do
      mod = semantic(%(
        class Foo(T); end
        class Bar < Foo(Int32); end
        )).program

      foo_class = mod.types["Foo"].metaclass
      foo_int32_class = mod.generic_class("Foo", mod.int32).metaclass
      bar_class = mod.types["Bar"].metaclass

      bar_class.should be_a_proper_subtype_of(foo_int32_class)
      bar_class.should be_a_proper_subtype_of(foo_class)
      foo_int32_class.should be_a_proper_subtype_of(foo_class)
    end

    it "generic classes (2)" do
      mod = semantic(%(
        class Foo; end
        class Bar(T) < Foo; end
        )).program

      foo_class = mod.types["Foo"].metaclass
      bar_class = mod.types["Bar"].metaclass
      bar_int32_class = mod.generic_class("Bar", mod.int32).metaclass

      bar_int32_class.should be_a_proper_subtype_of(bar_class)
      bar_int32_class.should be_a_proper_subtype_of(foo_class)
      bar_class.should be_a_proper_subtype_of(foo_class)
    end

    it "generic classes (3)" do
      mod = semantic(%(
        class Foo(T); end
        class Bar(T) < Foo(T); end
        )).program

      foo_class = mod.types["Foo"].metaclass
      bar_class = mod.types["Bar"].metaclass
      foo_int32_class = mod.generic_class("Foo", mod.int32).metaclass
      bar_int32_class = mod.generic_class("Bar", mod.int32).metaclass

      bar_int32_class.should be_a_proper_subtype_of(bar_class)
      bar_int32_class.should be_a_proper_subtype_of(foo_int32_class)
      bar_class.should be_a_proper_subtype_of(foo_class)
      foo_int32_class.should be_a_proper_subtype_of(foo_class)
      bar_int32_class.should be_a_proper_subtype_of(foo_class)
    end

    it "non-generic modules" do
      mod = semantic(%(
        module Foo; end
        module Bar; include Foo; end
        )).program

      foo_class = mod.types["Foo"].metaclass
      bar_class = mod.types["Bar"].metaclass
      bar_class.implements?(foo_class).should be_false
    end

    it "generic modules (1)" do
      mod = semantic(%(
        module Foo(T); end
        module Bar; include Foo(Int32); end
        )).program

      foo_class = mod.types["Foo"].metaclass
      foo_int32_class = mod.generic_module("Foo", mod.int32).metaclass
      bar_class = mod.types["Bar"].metaclass

      # only instantiations of generic module metaclasses are subtypes of the
      # uninstantiated metaclasses
      foo_int32_class.should be_a_proper_subtype_of(foo_class)

      bar_class.implements?(foo_int32_class).should be_false
      bar_class.implements?(foo_class).should be_false
    end

    it "generic modules (2)" do
      mod = semantic(%(
        module Foo; end
        module Bar(T); include Foo; end
        )).program

      foo_class = mod.types["Foo"].metaclass
      bar_class = mod.types["Bar"].metaclass
      bar_int32_class = mod.generic_module("Bar", mod.int32).metaclass

      bar_int32_class.should be_a_proper_subtype_of(bar_class)

      bar_int32_class.implements?(foo_class).should be_false
      bar_class.implements?(foo_class).should be_false
    end

    it "generic modules (3)" do
      mod = semantic(%(
        module Foo(T); end
        module Bar(T); include Foo(T); end
        )).program

      foo_class = mod.types["Foo"].metaclass
      bar_class = mod.types["Bar"].metaclass
      foo_int32_class = mod.generic_module("Foo", mod.int32).metaclass
      bar_int32_class = mod.generic_module("Bar", mod.int32).metaclass

      bar_int32_class.should be_a_proper_subtype_of(bar_class)
      foo_int32_class.should be_a_proper_subtype_of(foo_class)

      bar_int32_class.implements?(foo_int32_class).should be_false
      bar_int32_class.implements?(foo_class).should be_false
      bar_class.implements?(foo_class).should be_false
    end
  end

  it "doesn't put Object.class as the parent of generic module instance metaclasses (#11110)" do
    mod = semantic(%(
      module Foo(T); end
      )).program

    foo_int32_class = mod.generic_module("Foo", mod.int32).metaclass
    foo_int32_class.parents.should eq([mod.class_type])
    foo_int32_class.ancestors.should eq([mod.class_type, mod.value, mod.object])
  end

  it "can't reopen as struct" do
    assert_error <<-CRYSTAL, "Bar is not a struct, it's a metaclass"
      class Foo
      end

      alias Bar = Foo.class

      struct Bar
      end
      CRYSTAL
  end

  it "can't reopen as module" do
    assert_error <<-CRYSTAL, "Bar is not a module, it's a metaclass"
      class Foo
      end

      alias Bar = Foo.class

      module Bar
      end
      CRYSTAL
  end
end
