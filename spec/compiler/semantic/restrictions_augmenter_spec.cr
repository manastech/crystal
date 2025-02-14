require "../../spec_helper"

private def expect_augment(before : String, after : String)
  result = semantic(before)
  result.node.to_s.chomp.should eq(after.chomp)
end

private def expect_no_augment(code : String, flags = nil)
  result = semantic(code, flags: flags)
  result.node.to_s.chomp.should eq(code.chomp)
end

private def it_augments_for_ivar(ivar_type : String, expected_type : String, file = __FILE__, line = __LINE__)
  it "augments #{ivar_type}", file, line do
    before = <<-CRYSTAL
      class Foo
        @x : #{ivar_type}
        def initialize(value)
          @x = value
        end
      end
      CRYSTAL

    after = <<-CRYSTAL
      class Foo
        @x : #{ivar_type}
        def initialize(value : #{expected_type})
          @x = value
        end
      end
      CRYSTAL

    expect_augment before, after
  end
end

describe "Semantic: restrictions augmenter" do
  it_augments_for_ivar "Nil", "::Nil"
  it_augments_for_ivar "Bool", "::Bool"
  it_augments_for_ivar "Char", "::Char"
  it_augments_for_ivar "Int32", "::Int32"
  it_augments_for_ivar "Float32", "::Float32"
  it_augments_for_ivar "Symbol", "::Symbol"
  it_augments_for_ivar "String", "::String"
  it_augments_for_ivar "Array(String)", "::Array(::String)"
  it_augments_for_ivar "Tuple(Int32, Char)", "::Tuple(::Int32, ::Char)"
  it_augments_for_ivar "NamedTuple(a: Int32, b: Char)", "::NamedTuple(a: ::Int32, b: ::Char)"
  it_augments_for_ivar "Proc(Int32, Char)", "::Int32 -> ::Char"
  it_augments_for_ivar "Proc(Int32, Nil)", "::Int32 -> _"
  it_augments_for_ivar "Pointer(Void)", "::Pointer(::Void)"
  it_augments_for_ivar "StaticArray(Int32, 8)", "::StaticArray(::Int32, 8)"
  it_augments_for_ivar "Char | Int32 | String", "::Char | ::Int32 | ::String"
  it_augments_for_ivar "Char | Int32 | String", "::Char | ::Int32 | ::String"
  it_augments_for_ivar "Int32.class", "::Int32.class"
  it_augments_for_ivar "NoReturn", "::NoReturn"
  it_augments_for_ivar "Array(Int32).class", "::Array(::Int32).class"
  it_augments_for_ivar "Enumerable(Int32).class", "::Enumerable(::Int32).class"

  it "augments relative public type" do
    before = <<-CRYSTAL
      class Foo
        class Bar
          class Baz
          end
        end

        @x : Bar:: Baz

        def initialize(value)
          @x = value
        end
      end
      CRYSTAL

    after = <<-CRYSTAL
      class Foo
        class Bar
          class Baz
          end
        end

        @x : Bar::Baz

        def initialize(value : ::Foo::Bar::Baz)
          @x = value
        end
      end
      CRYSTAL

    expect_augment before, after
  end

  it "augments relative private type" do
    before = <<-CRYSTAL
      class Foo
        private class Bar
          class Baz
          end
        end

        @x : Bar:: Baz

        def initialize(value)
          @x = value
        end
      end
      CRYSTAL

    after = <<-CRYSTAL
      class Foo
        private class Bar
          class Baz
          end
        end

        @x : Bar::Baz

        def initialize(value : Bar::Baz)
          @x = value
        end
      end
      CRYSTAL

    expect_augment before, after
  end

  it "augments relative private type in same namespace" do
    before = <<-CRYSTAL
      class Foo
        private class Bar
        end
        private class Baz
          @x : Bar
          def initialize(value)
            @x = value
          end
        end
      end
      CRYSTAL

    after = <<-CRYSTAL
      class Foo
        private class Bar
        end
        private class Baz
          @x : Bar
          def initialize(value : Bar)
            @x = value
          end
        end
      end
      CRYSTAL

    expect_augment before, after
  end

  it "augments generic uninstantiated type" do
    before = <<-CRYSTAL
      class Foo(T)
        @x : Array(T)
        def initialize(value)
          @x = value
        end
      end
      CRYSTAL

    after = <<-CRYSTAL
      class Foo(T)
        @x : Array(T)
        def initialize(value : ::Array(T))
          @x = value
        end
      end
      CRYSTAL

    expect_augment before, after
  end

  it "augments for class var" do
    before = <<-CRYSTAL
      class Foo
        @@x = 1
        def self.set(value)
          @@x = value
        end
      end
      CRYSTAL

    after = <<-CRYSTAL
      class Foo
        @@x = 1
        def self.set(value : ::Int32)
          @@x = value
        end
      end
      CRYSTAL

    expect_augment before, after
  end

  it "doesn't augment if assigned inside if" do
    expect_no_augment <<-CRYSTAL
      class Foo
        @x : Int32
        def initialize(value)
          if value
            @x = value
          end
        end
      end
      CRYSTAL
  end

  it "doesn't augment if assigned inside while" do
    expect_no_augment <<-CRYSTAL
      class Foo
        @x : Int32
        def initialize(value)
          while false
            @x = value
          end
        end
      end
      CRYSTAL
  end

  it "doesn't augment if assigned inside block" do
    expect_no_augment <<-CRYSTAL
      def foo(&)
        yield
      end
      class Foo
        @x : Int32
        def initialize(value)
          foo do
            @x = value
          end
        end
      end
      CRYSTAL
  end

  it "doesn't augment if the no_restrictions_augmenter flag is present" do
    expect_no_augment <<-CRYSTAL, flags: "no_restrictions_augmenter"
      class Foo
        @x : Int32
        def initialize(value)
          @x = value
        end
      end
      CRYSTAL
  end

  it "augments recursive alias type (#12134)" do
    before = <<-CRYSTAL
      alias BasicObject = Array(BasicObject) | Hash(String, BasicObject)
      class Foo
        def initialize(value = Hash(String, BasicObject).new)
          @x = value
        end
      end
      CRYSTAL

    after = <<-CRYSTAL
      alias BasicObject = Array(BasicObject) | Hash(String, BasicObject)
      class Foo
        def initialize(value : ::Hash(::String, ::BasicObject) = Hash(String, BasicObject).new)
          @x = value
        end
      end
      CRYSTAL

    expect_augment before, after
  end

  it "augments typedef" do
    before = <<-CRYSTAL
      lib LibFoo
        type X = Int32
      end
      class Foo
        @x : LibFoo::X
        def initialize(value)
          @x = value
        end
      end
      CRYSTAL

    after = <<-CRYSTAL
      lib LibFoo
        type X = Int32
      end
      class Foo
        @x : LibFoo::X
        def initialize(value : ::LibFoo::X)
          @x = value
        end
      end
      CRYSTAL

    expect_augment before, after
  end

  it "augments virtual type" do
    before = <<-CRYSTAL
      class A
      end
      class B < A
      end
      class Foo
        @x : A
        def initialize(value)
          @x = value
        end
      end
      CRYSTAL

    after = <<-CRYSTAL
      class A
      end
      class B < A
      end
      class Foo
        @x : A
        def initialize(value : ::A)
          @x = value
        end
      end
      CRYSTAL

    expect_augment before, after
  end

  it "augments virtual metaclass type" do
    before = <<-CRYSTAL
      class A
      end
      class B < A
      end
      class Foo
        @x : A.class
        def initialize(value)
          @x = value
        end
      end
      CRYSTAL

    after = <<-CRYSTAL
      class A
      end
      class B < A
      end
      class Foo
        @x : A.class
        def initialize(value : ::A.class)
          @x = value
        end
      end
      CRYSTAL

    expect_augment before, after
  end

  it "augments type splat" do
    before = <<-CRYSTAL
      class Foo(T)
        @x : Array(*T)
        def initialize(value)
          @x = value
        end
      end
      CRYSTAL

    after = <<-CRYSTAL
      class Foo(T)
        @x : Array(*T)
        def initialize(value : ::Array(*T))
          @x = value
        end
      end
      CRYSTAL

    expect_augment before, after
  end

  it "doesn't crash on macro that yields and defines class (#12142)" do
    before = <<-CRYSTAL
      macro foo
        {{yield}}
      end
      foo do
        class Foo
        end
      end
      class Bar
        @x : Foo
        def initialize(value)
          @x = value
        end
      end
      CRYSTAL

    after = <<-CRYSTAL
      macro foo
        {{ yield }}
      end

      class Foo
      end

      class Bar
        @x : Foo
        def initialize(value : ::Foo)
          @x = value
        end
      end
      CRYSTAL

    expect_augment before, after
  end

  it "augments for Union(*T) (#12435)" do
    before = <<-CRYSTAL
      class Foo(*T)
        @x : Union(*T)
        def initialize(value)
          @x = value
        end
      end
      CRYSTAL

    after = <<-CRYSTAL
      class Foo(*T)
        @x : Union(*T)
        def initialize(value : ::Union(*T))
          @x = value
        end
      end
      CRYSTAL

    expect_augment before, after
  end
end
