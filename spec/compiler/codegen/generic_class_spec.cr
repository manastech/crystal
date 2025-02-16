require "../../spec_helper"

describe "Code gen: generic class type" do
  it "codegens inherited generic class instance var" do
    run(%(
      class Foo(T)
        def initialize(@x : T)
        end

        def x
          @x &+ 1
        end
      end

      class Bar < Foo(Int32)
      end

      Bar.new(1).x
      )).to_i.should eq(2)
  end

  it "instantiates generic class with default argument in initialize (#394)" do
    run(%(
      class Foo(T)
        def initialize(@x = 1)
        end

        def x
          @x
        end
      end

      Foo(Int32).new.x &+ 1
      )).to_i.should eq(2)
  end

  it "allows initializing instance variable (#665)" do
    run(%(
      class SomeType(T)
        @x = 1

        def x
          @x
        end
      end

      SomeType(Char).new.x
      )).to_i.should eq(1)
  end

  it "allows initializing instance variable in inherited generic type" do
    run(%(
      class Foo(T)
        @x = 1

        def x
          @x
        end
      end

      class Bar(T) < Foo(T)
        @y = 2
      end

      Bar(Char).new.x
      )).to_i.should eq(1)
  end

  it "declares instance var with virtual T (#1675)" do
    run(%(
      class Foo
        def foo
          1
        end
      end

      class Bar < Foo
      end

      class Generic(T)
        def initialize
          @value = uninitialized T
        end

        def value=(@value)
        end

        def value
          @value
        end
      end

      generic = Generic(Foo).new
      generic.value = Foo.new
      generic.value.foo
      )).to_i.should eq(1)
  end

  it "runs generic instance var initializers in superclass's metaclass context (#4753)" do
    run(%(
      class Bar(T)
        def x
          {% if T == Int32 %} 1 {% else %} 2 {% end %}
        end
      end

      class FooBase(T)
        @bar = Bar(T).new

        def bar
          @bar
        end
      end

      class Foo(T) < FooBase(T)
      end

      Foo(Int32).new.bar.x
      )).to_i.should eq(1)
  end

  it "runs generic instance var initializers in superclass's metaclass context (2) (#6482)" do
    run(%(
      class Bar(T)
        def x
          {% if T == FooBase(Int32) %} 1 {% else %} 2 {% end %}
        end
      end

      class FooBase(T)
        @bar = Bar(FooBase(T)).new

        def bar
          @bar
        end
      end

      class Foo(T) < FooBase(T)
      end

      Foo(Int32).new.bar.x
      )).to_i.should eq(1)
  end

  it "doesn't run generic instance var initializers in formal superclass's context (#4753)" do
    run(%(
      class Foo(T)
        @foo = T.new

        def foo
          @foo
        end
      end

      class Bar(T) < Foo(T)
      end

      class Baz
        def baz
          7
        end
      end

      Bar(Baz).new.foo.baz
      )).to_i.should eq(7)
  end

  it "codegens static array size after instantiating" do
    run(%(
      struct StaticArray(T, N)
        def size
          N
        end
      end

      alias Foo = Int32[3]

      x = uninitialized Int32[3]
      x.size
      )).to_i.should eq(3)
  end

  it "inherited instance var initialize from generic to concrete (#2128)" do
    run(%(
      class Foo(T)
        @x = 42

        def x
          @x
        end
      end

      class Bar < Foo(Int32)
      end

      Bar.new.x
      )).to_i.should eq(42)
  end

  it "inherited instance var initialize from generic to generic to concrete (#2128)" do
    run(%(
      class Foo(T)
        @x = 10

        def x
          @x
        end
      end

      class Bar(T) < Foo(T)
        @y = 32

        def y
          @y
        end
      end

      class Baz < Bar(Int32)
      end

      baz = Baz.new
      baz.x &+ baz.y
      )).to_i.should eq(42)
  end

  it "invokes super in generic class (#2354)" do
    run(%(
      class Global
        @@x = 1

        def self.x=(@@x)
        end

        def self.x
          @@x
        end
      end

      class Foo
        def foo
          Global.x = 2
        end
      end

      class Bar(T) < Foo
        def foo
          super
        end
      end

      b = Bar(Int32).new
      b.foo

      Global.x
      )).to_i.should eq(2)
  end

  it "uses big integer as generic type argument (#2353)" do
    run(%(
      require "prelude"

      MIN_RANGE = -2374623294237463578
      MAX_RANGE = -MIN_RANGE

      class Hello(T)
        def self.t
          T
        end
      end

      Hello(MAX_RANGE).t
      )).to_u64.should eq(2374623294237463578)
  end

  it "doesn't use virtual + in type arguments (#2839)" do
    run(%(
      class Class
        def name : String
          {{ @type.name.stringify }}
        end
      end

      class Foo
      end

      class Bar < Foo
      end

      class Gen(T)
      end

      Gen(Foo).name
      )).to_string.should eq("Gen(Foo)")
  end

  it "doesn't use virtual + in type arguments for Tuple (#2839)" do
    run(%(
      class Class
        def name : String
          {{ @type.name.stringify }}
        end
      end

      class Foo
      end

      class Bar < Foo
      end

      class Gen(T)
      end

      Tuple(Foo).name
      )).to_string.should eq("Tuple(Foo)")
  end

  it "doesn't use virtual + in type arguments for NamedTuple (#2839)" do
    run(%(
      class Class
        def name : String
          {{ @type.name.stringify }}
        end
      end

      class Foo
      end

      class Bar < Foo
      end

      class Gen(T)
      end

      NamedTuple(x: Foo).name
      )).to_string.should eq("NamedTuple(x: Foo)")
  end

  it "codegens virtual generic metaclass macro method call" do
    run(%(
      class Class
        def name : String
          {{ @type.name.stringify }}
        end
      end

      class Foo(T)
      end

      class Bar(T) < Foo(T)
      end

      Bar(Int32).new.as(Foo(Int32)).class.name
      )).to_string.should eq("Bar(Int32)")
  end

  it "recomputes two calls that look the same due to generic type being instantiated (#7728)" do
    run(%(
      require "prelude"

      abstract class Base
      end

      class Gen(T) < Base
        def initialize(@x : T)
        end

        def x
          @x
        end
      end

      def foo(gen)
        gen.x
        gen.x
      end

      foo(Gen.new(1) || Gen.new(1.5))
      foo(Gen.new(true) || Gen.new(1_u8))
      foo(Gen.new("hello") || Gen.new('z')).as(String)
      )).to_string.should eq("hello")
  end

  it "doesn't consider abstract types for including types (#7200)" do
    codegen(%(
      module Moo
      end

      abstract class Foo(T)
        include Moo

        def foo
          bar
        end
      end

      class Bar(T) < Foo(T)
        def bar
        end
      end

      Bar(Int32).new.as(Moo).foo
      ))
  end

  it "doesn't consider abstract generic instantiation when restricting type (#5190)" do
    codegen(%(
      abstract class Foo(E)
        abstract def foo
      end

      abstract class Bar(E) < Foo(E)
      end

      class Baz(E) < Bar(E)
        def foo
        end
      end

      ptr = Pointer(Foo(String)).malloc(1_u64)

      Baz(String).new

      x = ptr.value
      if x.is_a?(Bar)
        x.foo
      end
      ))
  end

  it "doesn't crash on generic type restriction with initially no subtypes (#8411)" do
    codegen(%(
      class Foo
      end

      class Baz(T) < Foo
        def baz
        end
      end

      def x(z)
      end

      f = uninitialized Foo
      if f.is_a?(Baz)
        x(f.baz)
      end

      Baz(Int32).new
      ))
  end

  it "doesn't crash on generic type restriction with no subtypes (#7583)" do
    codegen(%(
      require "prelude"

      class Foo
      end

      class Baz(T) < Foo
        def baz
        end
      end

      def x(z)
      end

      f = uninitialized Foo
      if f.is_a?(Baz)
        x(f.baz)
      end
      ))
  end

  it "doesn't override guessed instance var in generic type if already declared in superclass (#9431)" do
    codegen(%(
      class Foo
        @x = 0
      end

      class Bar(T) < Foo
        @x = 0
      end

      class Baz < Bar(Int32)
        @valid = true
      end

      Baz.new
      ))
  end

  it "accesses generic type argument from superclass, def context (#10834)" do
    run(%(
      class Foo(T)
      end

      class Bar(U) < Foo(U)
        def t
          T
        end
      end

      Bar(7).new.t
      )).to_i.should eq(7)
  end

  it "accesses generic type argument from superclass, metaclass context" do
    run(%(
      struct Int32
        def self.new(x : Int32)
          x
        end
      end

      class Foo(T)
      end

      class Bar(U) < Foo(U)
        @x = T.new(7)
      end

      Bar(Int32).new.@x
      )).to_i.should eq(7)
  end

  it "accesses generic type argument from superclass, macro context" do
    run(%(
      class Foo(T)
      end

      class Bar(U) < Foo(U)
        def t
          {{ T == 7 ? 1 : 2 }}
        end
      end

      Bar(7).new.t
      )).to_i.should eq(1)
  end

  it "codegens compile-time interpreted generic int128" do
    run(%(
      require "prelude"

      CONST = 1_i128 + 2_i128
      class Foo(T)
        def initialize()
        end

        def t_incr
          T + 1
        end
      end

      class Bar < Foo(CONST)
      end

      Bar.new.t_incr
      )).to_i.should eq(4)
  end
end
