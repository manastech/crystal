require "../../spec_helper"

describe "Semantic: def" do
  it "types a call with an int" do
    assert_type("def foo; 1; end; foo") { int32 }
  end

  it "types a call with a float" do
    assert_type("def foo; 2.3f32; end; foo") { float32 }
  end

  it "types a call with a double" do
    assert_type("def foo; 2.3; end; foo") { float64 }
  end

  it "types a call with an argument" do
    assert_type("def foo(x); x; end; foo 1") { int32 }
  end

  it "types a call with an argument" do
    input = parse "def foo(x); x; end; foo 1; foo 2.3"
    result = semantic input
    mod, input = result.program, result.node.as(Expressions)

    input[1].type.should eq(mod.int32)
    input[2].type.should eq(mod.float64)
  end

  it "types a call with an argument uses a new scope" do
    assert_type("x = 2.3; def foo(x); x; end; foo 1; x") { float64 }
  end

  it "assigns def owner" do
    input = parse "struct Int; def foo; 2.5; end; end; 1.foo"
    result = semantic input
    mod, input = result.program, result.node.as(Expressions)
    input.last.as(Call).target_def.owner.should eq(mod.int32)
  end

  it "types putchar with Char" do
    assert_type("lib LibC; fun putchar(c : Char) : Char; end; LibC.putchar 'a'") { char }
  end

  it "types getchar with Char" do
    assert_type("lib LibC; fun getchar : Char; end; LibC.getchar") { char }
  end

  it "allows recursion" do
    assert_type("def foo; foo; end; foo") { no_return }
  end

  it "allows recursion with arg" do
    assert_type("def foo(x); foo(x); end; foo 1") { no_return }
  end

  it "types simple recursion" do
    assert_type("def foo(x); if x > 0; foo(x - 1) + 1; else; 1; end; end; foo(5)", inject_primitives: true) { int32 }
  end

  it "types simple recursion 2" do
    assert_type("def foo(x); if x > 0; 1 + foo(x - 1); else; 1; end; end; foo(5)", inject_primitives: true) { int32 }
  end

  it "types mutual recursion" do
    assert_type("def foo(x); if 1 == 1; bar(x); else; 1; end; end; def bar(x); foo(x); end; foo(5)", inject_primitives: true) { int32 }
  end

  it "types empty body def" do
    assert_type("def foo; end; foo") { nil_type }
  end

  it "types mutual infinite recursion" do
    assert_type("def foo; bar; end; def bar; foo; end; foo") { no_return }
  end

  it "types call with union argument" do
    assert_type("def foo(x); x; end; a = 1 || 1.1; foo(a)") { union_of(int32, float64) }
  end

  it "defines class method" do
    assert_type("def Int.foo; 2.5; end; Int.foo") { float64 }
  end

  it "defines class method with self" do
    assert_type("struct Int; def self.foo; 2.5; end; end; Int.foo") { float64 }
  end

  it "calls with default argument" do
    assert_type("def foo(x = 1); x; end; foo") { int32 }
  end

  it "do not use body for the def type" do
    input = parse %(
      require "primitives"

      def foo
        if 1 == 2
          return 0
        end
      end

      foo
      )
    result = semantic input
    mod, input = result.program, result.node.as(Expressions)

    call = input.last.as(Call)
    call.type.should eq(mod.nilable(mod.int32))
    call.target_def.body.type.should eq(mod.nil)
  end

  it "reports undefined method" do
    assert_error "foo()",
      "undefined method 'foo'"
  end

  it "reports no overload matches" do
    assert_error "
      def foo(x : Int)
      end

      foo 1 || 1.5
      ",
      "expected argument #1 to 'foo' to be Int, not (Float64 | Int32)"
  end

  it "reports no overload matches 2" do
    assert_error "
      def foo(x : Int, y : Int)
      end

      def foo(x : Int, y : Float)
      end

      foo(1 || 'a', 1 || 1.5)
      ",
      "expected argument #1 to 'foo' to be Int, not (Char | Int32)"
  end

  it "reports no block given" do
    assert_error "
      def foo
        yield
      end

      foo
      ",
      "'foo' is expected to be invoked with a block, but no block was given"
  end

  it "reports block given" do
    assert_error "
      def foo
      end

      foo {}
      ",
      "'foo' is not expected to be invoked with a block, but a block was given"
  end

  it "errors when calling two functions with nil type" do
    assert_error "
      def bar
      end

      def foo
      end

      foo.bar
      ",
      "undefined method"
  end

  it "errors when default value is incompatible with type restriction" do
    assert_error "
      def foo(x : Int64 = 'a')
      end

      foo
      ",
      "can't restrict Char to Int64"
  end

  it "errors when default value is incompatible with non-type restriction" do
    assert_error "
      def foo(x : Tuple(_) = 'a')
      end

      foo
      ",
      "can't restrict Char to Tuple(_)"
  end

  it "types call with global scope" do
    assert_type("
      def bar
        1
      end

      class Foo
        def foo
          ::bar
        end

        def bar
          'a'
        end
      end

      Foo.new.foo
      ") { int32 }
  end

  it "lookups methods in super modules" do
    assert_type("
      require \"prelude\"

      module Foo
        def lookup_matches(x = 1)
          1
        end
      end

      module Bar
        include Foo
      end

      abstract class Type
      end

      abstract class CType < Type
      end

      abstract class MType < CType
        include Bar
      end

      class NonGenericMType < MType
      end

      class GenericMType < MType
      end

      b = [] of Type
      b.push NonGenericMType.new
      b.push GenericMType.new
      b[0].lookup_matches
      ") { int32 }
  end

  it "fixes bug #165" do
    assert_error %(
      abstract class Node
      end

      def foo(nodes : Pointer(Node))
        foo nodes.value
      end

      a = Pointer(Node).new(0_u64)
      foo a
      ),
      "expected argument #1 to 'foo' to be Pointer(Node), not Node",
      inject_primitives: true
  end

  it "says can only defined def on types and self" do
    assert_error %(
      class Foo
      end

      foo = Foo.new
      def foo.bar
      end
      ),
      "def receiver can only be a Type or self"
  end

  it "errors if return type doesn't match" do
    assert_error %(
      def foo : Int32
        'a'
      end

      foo
      ),
      "method ::foo must return Int32 but it is returning Char"
  end

  it "errors if return type doesn't match on instance method" do
    assert_error %(
      class Foo
        def foo : Int32
          'a'
        end
      end

      Foo.new.foo
      ),
      "method Foo#foo must return Int32 but it is returning Char"
  end

  it "errors if return type doesn't match on class method" do
    assert_error %(
      class Foo
        def self.foo : Int32
          'a'
        end
      end

      Foo.foo
      ),
      "method Foo.foo must return Int32 but it is returning Char"
  end

  it "is ok if returns Int32? with explicit return" do
    assert_type(%(
      def foo : Int32?
        if 1 == 2
          return nil
        end
        1
      end

      foo
      ), inject_primitives: true) { nilable int32 }
  end

  it "says compile-time type on error" do
    assert_error %(
      abstract class Foo
      end

      class Bar < Foo
        def bar
          1
        end
      end

      class Baz < Foo
      end

      f = Bar.new || Baz.new
      f.bar
      ),
      "compile-time type is Foo+"
  end

  it "gives correct error for wrong number of arguments for program call inside type (#1024)" do
    assert_error %(
      def foo
      end

      class Foo
        def self.bar
          foo 1
        end
      end

      Foo.bar
      ),
      "wrong number of arguments for 'foo' (given 1, expected 0)"
  end

  it "gives correct error for wrong number of arguments for program call inside type (2) (#1024)" do
    assert_error %(
      def foo(x : String)
      end

      class Foo
        def self.bar
          foo 1
        end
      end

      Foo.bar
      ),
      "expected argument #1 to 'foo' to be String, not Int32"
  end

  it "gives correct error for methods in Class" do
    assert_error %(
      class Class
        def foo
          1
        end
      end

      class Foo
      end

      Foo.foo(1)
      ),
      <<-ERROR
      wrong number of arguments for 'Foo.foo' (given 1, expected 0)

      Overloads are:
       - Class#foo()
      ERROR
  end

  it "gives correct error for methods in Class (2)" do
    assert_error %(
      class Class
        def self.foo
          1
        end
      end

      class Foo
      end

      Foo.foo(1)
      ),
      <<-ERROR
      wrong number of arguments for 'Foo.foo' (given 1, expected 0)

      Overloads are:
       - Class#foo()
      ERROR
  end

  it "errors if declares def inside if" do
    assert_error %(
      if 1 == 2
        def foo; end
      end
      ),
      "can't declare def dynamically"
  end

  it "accesses free var of default argument (#1101)" do
    assert_type(%(
      def foo(x, y : U = nil) forall U
        U
      end

      foo 1
      )) { nil_type.metaclass }
  end

  it "clones regex literal value (#2384)" do
    assert_type(%(
      require "prelude"

      def foo(x : String = "")
        /\#{1}/
        10
      end

      foo
      foo("")
      )) { int32 }
  end

  it "doesn't find type in namespace through free var" do
    assert_error %(
      def foo(x : T) forall T
        T::String
      end

      foo(1)
      ),
      "undefined constant T::String"
  end

  it "errors if trying to declare method on generic class instance" do
    assert_error %(
      class Foo(T)
      end

      alias Bar = Foo(Int32)

      def Bar.foo
      end
      ),
      "can't define method in generic instance"
  end

  it "uses free variable" do
    assert_type(%(
      def foo(x : Free) forall Free
        Free
      end

      foo(1)
      )) { int32.metaclass }
  end

  it "uses free variable with metaclass" do
    assert_type(%(
      def foo(x : Free.class) forall Free
        Free
      end

      foo(Int32)
      )) { int32.metaclass }
  end

  it "uses free variable with metaclass and default value" do
    assert_type(%(
      def foo(x : Free.class = Int32) forall Free
        Free
      end

      foo
      )) { int32.metaclass }
  end

  it "uses free variable as block return type" do
    assert_type(%(
      def foo(&block : -> Free) forall Free
        yield
        Free
      end

      foo { 1 }
      )) { int32.metaclass }
  end

  it "uses free variable and doesn't conflict with top-level type" do
    assert_type(%(
      class Free
      end

      def foo(x : Free) forall Free
        Free
      end

      foo(1)
      )) { int32.metaclass }
  end

  it "shows free variables if no overload matches" do
    assert_error %(
      class Foo(T)
        def foo(x : T, y : U, z : V) forall U, V
        end
      end

      Foo(Int32).new.foo("", "", "")
      ),
      <<-ERROR
      Overloads are:
       - Foo(T)#foo(x : T, y : U, z : V) forall U, V
      ERROR
  end

  it "can't use self in toplevel method" do
    assert_error %(
      def foo
        self
      end

      foo
    ), "there's no self in this scope"
  end

  it "points error at name (#6937)" do
    ex = assert_error <<-CRYSTAL,
      1.
        foobar
      CRYSTAL
      "undefined method"
    ex.line_number.should eq(2)
    ex.column_number.should eq(3)
    ex.size.should eq(6)
  end

  it "does not allow top-level 'def super'" do
    assert_error <<-CODE, "top-level 'def super' is not allowed due to no way to call this"
      def super
      end
      CODE
  end

  it "does not allow top-level 'def previous_def'" do
    assert_error <<-CODE, "top-level 'def previous_def' is not allowed due to no way to call this"
      def previous_def
      end
      CODE
  end
end
