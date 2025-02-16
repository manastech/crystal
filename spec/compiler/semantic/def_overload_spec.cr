require "../../spec_helper"

def assert_stricter(params1, params2, args, *, file = __FILE__, line = __LINE__)
  assert_type(<<-CRYSTAL, file: file, line: line, flags: "preview_overload_order") { tuple_of([int32, int32]) }
    def foo(#{params1}); 1; end
    def foo(#{params2}); 'x'; end

    def bar(#{params2}); 'x'; end
    def bar(#{params1}); 1; end

    a = foo(#{args})
    b = bar(#{args})
    {a, b}
    CRYSTAL
end

def assert_unordered(params1, params2, args, *, file = __FILE__, line = __LINE__)
  assert_type(<<-CRYSTAL, file: file, line: line, flags: "preview_overload_order") { tuple_of([int32, int32]) }
    def foo(#{params1}); 1; end
    def foo(#{params2}); 'x'; end

    def bar(#{params2}); 1; end
    def bar(#{params1}); 'x'; end

    a = foo(#{args})
    b = bar(#{args})
    {a, b}
    CRYSTAL
end

describe "Semantic: def overload" do
  describe "compare_strictness" do
    context "positional parameters" do
      it "specificity" do
        signatures = [
          {2, 2, "x0, x1"},
          {2, 3, "x0, x1, x2 = 0"},
          {2, 4, "x0, x1, x2 = 0, x3 = 0"},
          {2, 9, "x0, x1, x2 = 0, x3 = 0, *xs"},
          {2, 9, "x0, x1, x2 = 0, *xs"},
          {2, 9, "x0, x1, *xs"},
          {1, 1, "x0"}, # incompatible with 6 defs above
          {1, 2, "x0, x1 = 0"},
          {1, 3, "x0, x1 = 0, x2 = 0"},
          {1, 9, "x0, x1 = 0, x2 = 0, *xs"},
          {1, 9, "x0, x1 = 0, *xs"},
          {1, 9, "x0, *xs"},
          {0, 0, ""},       # incompatible with 12 defs above
          {0, 1, "x0 = 0"}, # incompatible with 6 defs above
          {0, 2, "x0 = 0, x1 = 0"},
          {0, 9, "x0 = 0, x1 = 0, *xs"},
          {0, 9, "x0 = 0, *xs"},
          {0, 9, "*xs"},
        ]

        signatures.each_combination(2, reuse: true) do |(x, y)|
          min_count1, max_count1, params1 = x
          min_count2, max_count2, params2 = y
          next if min_count1 > max_count2 || min_count2 > max_count1
          args = Array.new({min_count1, min_count2}.max) { "0" }.join(", ")

          assert_stricter(params1, params2, args)
        end
      end

      it "single splat vs single splat with restriction (#3134)" do
        assert_stricter(
          "*args : Int32",
          "*args",
          "1")
      end

      it "single splat restriction vs single splat with stricter restriction" do
        assert_stricter(
          "*args : Int32",
          "*args : Int",
          "1")
      end

      it "positional parameter with restriction vs single splat" do
        assert_stricter(
          "x : Int32",
          "*args",
          "1")

        assert_stricter(
          "x : Int32 = 0",
          "*args",
          "")
      end

      it "positional parameter vs single splat with restriction" do
        assert_stricter(
          "*args : Int32",
          "x",
          "1")
      end

      it "positional parameter with stricter restriction vs single splat with restriction" do
        assert_stricter(
          "x : Int32",
          "*args : Int",
          "1")
      end

      it "positional parameter with restriction vs single splat with stricter restriction" do
        assert_stricter(
          "*args : Int32",
          "x : Int",
          "1")
      end
    end

    context "named parameters" do
      it "specificity" do
        signatures = [
          {1, 1, "*, n"},
          {1, 9, "*, n, **ns"},
          {0, 0, ""},
          {0, 1, "*, n = 0"},
          {0, 9, "*, n = 0, **ns"},
          {0, 9, "**ns"},
        ]

        signatures.each_combination(2, reuse: true) do |(x, y)|
          min_count1, max_count1, params1 = x
          min_count2, max_count2, params2 = y
          next if min_count1 > max_count2 || min_count2 > max_count1
          args = Array.new({min_count1, min_count2}.max) { "n: 0" }.join(", ")

          assert_stricter(params1, params2, args)
        end
      end

      it "double splat vs double splat with restriction" do
        assert_stricter(
          "**args : Int32",
          "**args",
          "x: 1")
      end

      it "double splat restriction vs double splat with stricter restriction" do
        assert_stricter(
          "**args : Int32",
          "**args : Int",
          "x: 1")
      end

      it "named parameter with restriction vs double splat (#5328)" do
        assert_stricter(
          "*, x : Int32",
          "**opts",
          "x: 1")

        assert_stricter(
          "*, x : Int32 = 0",
          "**opts",
          "")
      end

      it "named parameter vs double splat with restriction" do
        assert_stricter(
          "**opts : Int32",
          "*, x",
          "x: 1")
      end

      it "named parameter with stricter restriction vs double splat with restriction" do
        assert_stricter(
          "*, x : Int32",
          "**opts : Int",
          "x: 1")
      end

      it "named parameter with restriction vs double splat with stricter restriction" do
        assert_stricter(
          "**opts : Int32",
          "*, x : Int",
          "x: 1")
      end
    end

    context "subsumption conflicts" do
      it "positional vs positional" do
        assert_unordered(
          "x : Int32, y : Int",
          "x : Int, y : Int32",
          "1, 2")
      end

      it "positional vs single splat" do
        assert_unordered(
          "x : Int32, *args : Int",
          "x : Int, *args : Int32",
          "1, 2, 3, 4")

        assert_unordered(
          "x : Int32, *args : Number",
          "*args : Int",
          "1, 2, 3, 4")
      end

      it "positional vs named" do
        assert_unordered(
          "x : Int32, *, y : Int",
          "x : Int, *, y : Int32",
          "1, y: 2")
      end

      it "positional vs double splat" do
        assert_unordered(
          "x : Int32, **opts : Int",
          "x : Int, **opts : Int32",
          "1, y: 2, z: 3, w: 4")
      end

      it "single splat vs named" do
        assert_unordered(
          "*args : Int32, y : Int",
          "*args : Int, y : Int32",
          "1, 2, 3, y: 4")
      end

      it "single splat vs double splat" do
        assert_unordered(
          "*args : Int32, **opts : Int",
          "*args : Int, **opts : Int32",
          "1, 2, 3, y: 4, z: 5, w: 6")
      end

      it "named vs named" do
        assert_unordered(
          "*, x : Int32, y : Int",
          "*, x : Int, y : Int32",
          "x: 1, y: 2")
      end

      it "named vs double splat" do
        assert_unordered(
          "*, x : Int32, **opts : Int",
          "*, x : Int, **opts : Int32",
          "x: 1, y: 2, z: 3, w: 4")

        assert_unordered(
          "*, x : Int32, **opts : Number",
          "**opts : Int",
          "x: 1, y: 2, z: 3, w: 4")
      end
    end

    context "subsumption has higher precedence over specificity" do
      it "same positional parameter, required > optional" do
        assert_stricter(
          "x : Int32 = 0",
          "x : Int",
          "1")
      end

      it "same positional parameter, required > single splat" do
        assert_stricter(
          "*x : Int32",
          "x : Int",
          "1")
      end

      it "same positional parameter, optional > single splat" do
        assert_stricter(
          "*x : Int32",
          "x : Int = 0",
          "1")
      end

      it "positional vs (required positional > optional positional)" do
        assert_stricter(
          "x : Int32, y = 0",
          "x : Int, y",
          "1, 2")
      end

      it "positional vs (required positional > single splat)" do
        assert_stricter(
          "x : Int32, *args",
          "x : Int, y",
          "1, 2")
      end

      it "positional vs (optional positional > single splat)" do
        assert_stricter(
          "x : Int32, *args",
          "x : Int, y = 0",
          "1, 2")
      end

      it "positional vs (required named > optional named)" do
        assert_stricter(
          "x : Int32, *, y = 0",
          "x : Int, *, y",
          "1, y: 2")
      end

      it "positional vs (required named > double splat)" do
        assert_stricter(
          "x : Int32, **opts",
          "x : Int, *, y",
          "1, y: 2")
      end

      it "positional vs (optional named > double splat)" do
        assert_stricter(
          "x : Int32, **opts",
          "x : Int, *, y = 0",
          "1, y: 2")
      end

      it "single splat vs (required named > optional named)" do
        assert_stricter(
          "*args : Int32, y = 0",
          "*args : Int, y",
          "1, 2, 3, y: 4")
      end

      it "single splat vs (required named > double splat)" do
        assert_stricter(
          "*args : Int32, **opts",
          "*args : Int, y",
          "1, 2, 3, y: 4")
      end

      it "single splat vs (optional named > double splat)" do
        assert_stricter(
          "*args : Int32, **opts",
          "*args : Int, y = 0",
          "1, 2, 3, y: 4")
      end

      it "same named parameter, required > optional" do
        assert_stricter(
          "*, x : Int32 = 0",
          "*, x : Int",
          "x: 1")
      end

      it "same named parameter, required > double splat" do
        assert_stricter(
          "**opts : Int32",
          "*, x : Int",
          "x: 1")
      end

      it "same named parameter, optional > double splat" do
        assert_stricter(
          "**opts : Int32",
          "*, x : Int = 0",
          "x: 1")
      end

      it "named vs (required positional > optional positional)" do
        assert_stricter(
          "x = 0, *, y : Int32",
          "x, *, y : Int",
          "1, y: 2")
      end

      it "named vs (required positional > single splat)" do
        assert_stricter(
          "*args, y : Int32",
          "x, *, y : Int",
          "1, y: 2")
      end

      it "named vs (optional positional > single splat)" do
        assert_stricter(
          "*args, y : Int32",
          "x = 0, *, y : Int",
          "1, y: 2")
      end

      it "named vs (required named > optional named)" do
        assert_stricter(
          "*, x : Int32, y = 0",
          "*, x : Int, y",
          "x: 1, y: 2")
      end

      it "named vs (required named > double splat)" do
        assert_stricter(
          "*, x : Int32, **opts",
          "*, x : Int, y",
          "x: 1, y: 2")
      end

      it "named vs (optional named > double splat)" do
        assert_stricter(
          "*, x : Int32, **opts",
          "*, x : Int, y = 0",
          "x: 1, y: 2")
      end

      it "double splat vs (required positional > optional positional)" do
        assert_stricter(
          "x = 0, **opts : Int32",
          "x, **opts : Int",
          "1, y: 2, z: 3, w: 4")
      end

      it "double splat vs (required positional > single splat)" do
        assert_stricter(
          "*args, **opts : Int32",
          "x, **opts : Int",
          "1, y: 2, z: 3, w: 4")
      end

      it "double splat vs (optional positional > single splat)" do
        assert_stricter(
          "*args, **opts : Int32",
          "x = 0, **opts : Int",
          "1, y: 2, z: 3, w: 4")
      end
    end

    context "specificity conflicts, positional vs named" do
      it "(required > optional) vs (required > optional)" do
        assert_unordered(
          "x, *, y = 0",
          "x = 0, *, y",
          "1, y: 2")
      end

      it "(required > optional) vs (required > splat)" do
        assert_unordered(
          "x, **opts",
          "x = 0, *, y",
          "1, y: 2")
      end

      it "(required > optional) vs (optional > splat)" do
        assert_unordered(
          "x, **opts",
          "x = 0, *, y = 0",
          "1, y: 2")
      end

      it "(required > splat) vs (required > optional)" do
        assert_unordered(
          "x, *, y = 0",
          "*x, y",
          "1, y: 2")
      end

      it "(required > splat) vs (required > splat)" do
        assert_unordered(
          "x, **opts",
          "*x, y",
          "1, y: 2")
      end

      it "(required > splat) vs (optional > splat)" do
        assert_unordered(
          "x, **opts",
          "*x, y = 0",
          "1, y: 2")
      end

      it "(optional > splat) vs (required > optional)" do
        assert_unordered(
          "x = 0, *, y = 0",
          "*x, y",
          "1, y: 2")
      end

      it "(optional > splat) vs (required > splat)" do
        assert_unordered(
          "x = 0, **opts",
          "*x, y",
          "1, y: 2")
      end

      it "(optional > splat) vs (optional > splat)" do
        assert_unordered(
          "x = 0, **opts",
          "*x, y = 0",
          "1, y: 2")
      end
    end

    context "specificity conflicts, named vs named" do
      it "(required > optional) vs (required > optional)" do
        assert_unordered(
          "*, x, y = 0",
          "*, y, x = 0",
          "x: 1, y: 2")
      end

      it "(required > optional) vs (required > splat)" do
        assert_unordered(
          "*, x, **opts",
          "*, y, x = 0",
          "x: 1, y: 2")
      end

      it "(required > optional) vs (optional > splat)" do
        assert_unordered(
          "*, x, **opts",
          "*, y = 0, x = 0",
          "x: 1, y: 2")
      end

      it "(required > splat) vs (required > splat)" do
        assert_unordered(
          "*, x, **opts",
          "*, y, **opts",
          "x: 1, y: 2")
      end

      it "(required > splat) vs (optional > splat)" do
        assert_unordered(
          "*, x, **opts",
          "*, y = 0, **opts",
          "x: 1, y: 2")
      end

      it "(optional > splat) vs (optional > splat)" do
        assert_unordered(
          "*, x = 0, **opts",
          "*, y = 0, **opts",
          "x: 1, y: 2")
      end
    end
  end

  it "types a call with overload" do
    assert_type("def foo; 1; end; def foo(x); 2.5; end; foo") { int32 }
  end

  it "types a call with overload with yield" do
    assert_type("def foo; yield; 1; end; def foo; 2.5; end; foo") { float64 }
  end

  it "types a call with overload with yield after typing another call without yield" do
    assert_type("
      def foo; yield; 1; end
      def foo; 2.5; end
      foo
      foo {}
    ") { int32 }
  end

  it "types a call with overload with yield the other way" do
    assert_type("def foo; yield; 1; end; def foo; 2.5; end; foo { 1 }") { int32 }
  end

  it "types a call with overload type first overload" do
    assert_type("def foo(x : Int); 2.5; end; def foo(x : Float); 1; end; foo(1)") { float64 }
  end

  it "types a call with overload type second overload" do
    assert_type("def foo(x : Int); 2.5; end; def foo(x : Float); 1; end; foo(1.5)") { int32 }
  end

  it "types a call with overload Object type first overload" do
    assert_type("
      class Foo
      end

      class Bar
      end

      def foo(x : Foo)
        2.5
      end

      def foo(x : Bar)
        1
      end

      foo(Foo.new)
      ") { float64 }
  end

  it "types a call with overload selecting the most restrictive" do
    assert_type("def foo(x); 1; end; def foo(x : Float); 1.1; end; foo(1.5)") { float64 }
  end

  it "types a call with overload selecting the most restrictive 2" do
    assert_type("
      def foo(x, y : Int)
        1
      end

      def foo(x : Int, y)
        1.1
      end

      def foo(x : Int, y : Int)
        'a'
      end

      foo(1, 1)
    ") { char }
  end

  it "types a call with overload matches virtual" do
    assert_type("
      class Foo; end

      def foo(x : Object)
        1
      end

      foo(Foo.new)
    ") { int32 }
  end

  it "types a call with overload matches virtual 2" do
    assert_type("
      class Foo
      end

      class Bar < Foo
      end

      def foo(x : Foo)
        1
      end

      def foo(x : Bar)
        1.5
      end

      foo(Bar.new)
    ") { float64 }
  end

  it "types a call with overload matches virtual 3" do
    assert_type("
      class Foo
      end

      class Bar < Foo
      end

      def foo(x : Foo)
        1
      end

      def foo(x : Bar)
        1.5
      end

      foo(Foo.new)
    ") { int32 }
  end

  it "types a call with overload self" do
    assert_type("
      class Foo
        def foo(x : self)
          1
        end

        def foo(x)
          1.5
        end
      end

      a = Foo.new
      a.foo(a)
    ") { int32 }
  end

  it "types a call with overload self other match" do
    assert_type("
      class Foo
        def foo(x : self)
          1
        end

        def foo(x)
          1.5
        end
      end

      a = Foo.new
      a.foo(1)
    ") { float64 }
  end

  it "types a call with overload self in included module" do
    assert_type("
      module Foo
        def foo(x : self)
          1
        end
      end

      class Bar
        def foo(x)
          1.5
        end
      end

      class Baz < Bar
        include Foo
      end

      b = Baz.new
      b.foo(b)
    ") { int32 }
  end

  it "types a call with overload self in included module other type" do
    assert_type("
      module Foo
        def foo(x : self)
          1
        end
      end

      class Bar
        def foo(x)
          1.5
        end
      end

      class Baz < Bar
        include Foo
      end

      b = Baz.new
      b.foo(Bar.new)
    ") { float64 }
  end

  it "types a call with overload self with inherited type" do
    assert_type("
      class Foo
        def foo(x : self)
          1
        end
      end

      class Bar < Foo
      end

      a = Foo.new
      a.foo(Bar.new)
    ") { int32 }
  end

  it "matches types with free variables" do
    assert_type("
      require \"prelude\"
      def foo(x : Array(T), y : T) forall T
        1
      end

      def foo(x, y)
        1.5
      end

      foo([1], 1)
    ") { int32 }
  end

  it "does not consider global paths as free variables (1)" do
    assert_error <<-CRYSTAL, "undefined constant ::Foo"
      def foo(x : ::Foo) forall Foo
      end

      foo(1)
      CRYSTAL
  end

  it "does not consider global paths as free variables (2)" do
    assert_error <<-CRYSTAL, "expected argument #1 to 'foo' to be Foo, not Int32"
      class Foo
      end

      def foo(x : ::Foo) forall Foo
      end

      foo(1)
      CRYSTAL
  end

  it "prefers more specific overload than one with free variables" do
    assert_type("
      require \"prelude\"
      def foo(x : Array(T), y : T)
        1
      end

      def foo(x : Array(Int), y : Int)
        1.5
      end

      foo([1], 1)
    ") { float64 }
  end

  it "accepts overload with nilable type restriction" do
    assert_type("
      def foo(x : Int?)
        1
      end

      foo(1)
    ") { int32 }
  end

  it "dispatch call to def with restrictions" do
    assert_type("
      def foo(x : Value)
        1.1
      end

      def foo(x : Int32)
        1
      end

      a = 1 || 1.1
      foo(a)
    ") { union_of(int32, float64) }
  end

  it "dispatch call to def with restrictions" do
    assert_type("
      class Foo(T)
      end

      def foo(x : T) forall T
        Foo(T).new
      end

      foo 1
    ") { generic_class "Foo", int32 }
  end

  it "can call overload with generic restriction" do
    assert_type("
      class Foo(T)
      end

      def foo(x : Foo)
        1
      end

      foo(Foo(Int32).new)
    ") { int32 }
  end

  it "can call overload with aliased generic restriction" do
    assert_type("
      class Foo(T)
      end

      alias FooAlias = Foo

      def foo(x : FooAlias(T)) forall T
        1
      end

      foo(Foo(Int32).new)
    ") { int32 }
  end

  it "restrict matches to minimum necessary 1" do
    assert_type("
      def coco(x : Int, y); 1; end
      def coco(x, y : Int); 1.5; end
      def coco(x, y); 'a'; end

      coco 1, 1
    ") { int32 }
  end

  it "single type restriction wins over union" do
    assert_type("
      class Foo; end
      class Bar < Foo ;end

      def foo(x : Foo | Bar)
        1.1
      end

      def foo(x : Foo)
        1
      end

      foo(Foo.new || Bar.new)
    ") { int32 }
  end

  it "compare self type with others" do
    assert_type("
      class Foo
        def foo(x : Int)
          1.1
        end

        def foo(x : self)
          1
        end
      end

      x = Foo.new.foo(Foo.new)
    ") { int32 }
  end

  it "uses method defined in base class if the restriction doesn't match" do
    assert_type("
      class Foo
        def foo(x)
          1
        end
      end

      class Bar < Foo
        def foo(x : Float64)
          1.1
        end
      end

      Bar.new.foo(1)
    ") { int32 }
  end

  it "lookup matches in virtual type inside union" do
    assert_type("
      class Foo
        def foo
          1
        end
      end

      class Bar < Foo
      end

      class Baz
        def foo
          'a'
        end
      end

      a = Foo.new || Bar.new || Baz.new
      a.foo
    ") { union_of(int32, char) }
  end

  it "filter union type with virtual" do
    assert_type("
      class Foo
      end

      class Bar < Foo
        def bar
          1
        end
      end

      def foo(x : Bar)
        x.bar
      end

      def foo(x)
        1.1
      end

      foo(nil || Foo.new || Bar.new)
    ") { union_of(int32, float64) }
  end

  it "restrict virtual type with virtual type" do
    assert_type("
      def foo(x : T, y : T) forall T
        1
      end

      class Foo
      end

      class Bar < Foo
      end

      x = Foo.new || Bar.new
      foo(x, x)
    ") { int32 }
  end

  it "restricts union to generic class" do
    assert_type("
      class Foo(T)
      end

      def foo(x : Foo(T)) forall T
        1
      end

      def foo(x : Int)
        'a'
      end

      x = 1 || Foo(Int32).new
      foo(x)
    ") { union_of(int32, char) }
  end

  it "matches on partial union" do
    assert_type("
      require \"prelude\"

      def foo(x : Int32 | Float64)
        x.abs
        1
      end

      def foo(x : Char)
        x.ord
        'a'
      end

      foo 1 || 1.5 || 'a'
    ") { union_of(int32, char) }
  end

  pending "restricts on generic type with free type arg" do
    assert_type("
      require \"reference\"

      class Object
        def equal(expectation)
          expectation == self
        end
      end

      class Foo(T)
        def ==(other : Foo(U))
          1
        end
      end

      a = Foo(Int).new
      a.equal(a)
      ") { union_of(bool, int32) }
  end

  pending "restricts on generic type without type arg" do
    assert_type("
      require \"reference\"

      class Object
        def equal(expectation)
          expectation == self
        end
      end

      class Foo(T)
        def ==(other : Foo)
          1
        end
      end

      a = Foo(Int).new
      a.equal(a)
    ") { union_of(bool, int32) }
  end

  it "matches generic class instance type with another one" do
    assert_type("
      require \"prelude\"
      class Foo
      end

      class Bar < Foo
      end

      a = [] of Array(Foo)
      a.push [Foo.new, Bar.new]
      1
      ") { int32 }
  end

  it "errors if generic type doesn't match" do
    assert_error "
      class Foo(T)
      end

      def foo(x : Foo(Int32))
      end

      foo Foo(Int32 | Float64).new
      ",
      "expected argument #1 to 'foo' to be Foo(Int32), not Foo(Float64 | Int32)"
  end

  it "gets free variable from union restriction" do
    assert_type("
      def foo(x : Nil | U) forall U
        U
      end

      foo(1 || nil)
      ") { int32.metaclass }
  end

  it "gets free variable from union restriction (2)" do
    assert_type("
      def foo(x : Nil | U) forall U
        U
      end

      foo(nil || 1)
      ") { int32.metaclass }
  end

  it "gets free variable from union restriction without a union" do
    assert_type("
      def foo(x : Nil | U) forall U
        U
      end

      foo(1)
      ") { int32.metaclass }
  end

  it "matches a generic module argument" do
    assert_type("
      module Bar(T)
      end

      class Foo
        include Bar(Int32)
      end

      def foo(x : Bar(Int32))
        1
      end

      foo(Foo.new)
      ") { int32 }
  end

  it "matches a generic module argument with free var" do
    assert_type("
      module Bar(T)
      end

      class Foo
        include Bar(Int32)
      end

      def foo(x : Bar(T)) forall T
        T
      end

      foo(Foo.new)
      ") { int32.metaclass }
  end

  it "matches a generic module argument with free var (2)" do
    assert_type("
      module Bar(T)
      end

      class Foo(T)
        include Bar(T)
      end

      def foo(x : Bar(T)) forall T
        T
      end

      foo(Foo(Int32).new)
      ") { int32.metaclass }
  end

  it "matches a union argument with free var" do
    each_union_variant("T", "Nil") do |restriction|
      assert_type(%(
        def foo(x : #{restriction}) forall T
          T
        end

        {foo(1), foo(1 || nil)}
        )) { tuple_of([int32.metaclass, int32.metaclass]) }
    end
  end

  it "matches a union metaclass argument with free var (#8071)" do
    each_union_variant("T", "Nil") do |restriction|
      assert_type(%(
        def foo(x : (#{restriction}).class) forall T
          T
        end

        {foo(String), foo(String?)}
        )) { tuple_of([string.metaclass, string.metaclass]) }
    end
  end

  it "matches a union argument with free var, more types (1)" do
    each_union_variant("T", "Nil") do |restriction|
      assert_type(%(
        def foo(x : #{restriction}) forall T
          T
        end

        foo(1 || "" || nil)
        )) { union_of(int32, string).metaclass }
    end
  end

  it "matches a union argument with free var, more types (2)" do
    each_union_variant("T", "(Int32 | String)") do |restriction|
      assert_type(%(
        def foo(x : #{restriction}) forall T
          T
        end

        foo(1 || "" || 'a')
        )) { char.metaclass }
    end
  end

  it "errors if union restriction has multiple free vars" do
    each_union_variant("T", "U") do |restriction|
      assert_error "
        def foo(x : #{restriction}) forall T, U
        end

        foo(1)
        ",
        "can't specify more than one free var in union restriction"
    end
  end

  it "errors if union restriction has multiple free vars (2)" do
    each_union_variant("T", "U") do |restriction|
      assert_error "
        def foo(x : #{restriction}) forall T, U
        end

        foo(1 || 'a')
        ",
        "can't specify more than one free var in union restriction"
    end
  end

  it "matches virtual type to union" do
    assert_type("
      abstract class Foo
      end

      class Bar < Foo
      end

      class Baz < Foo
      end

      def foo(x : Bar | Baz)
        1
      end

      node = Bar.new || Baz.new
      foo(node)
      ") { int32 }
  end

  it "doesn't match tuples of different sizes" do
    assert_error "
      def foo(x : {X, Y, Z})
        'a'
      end

      foo({1, 2})
      ",
      "expected argument #1 to 'foo' to be ::Tuple(X, Y, Z), not Tuple(Int32, Int32)"
  end

  it "matches tuples of different sizes" do
    assert_type("
      def foo(x : {X, Y}) forall X, Y
        1
      end

      def foo(x : {X, Y, Z}) forall X, Y, Z
        'a'
      end

      x = {1, 2} || {1, 2, 3}
      foo x
      ") { union_of(int32, char) }
  end

  it "matches tuples and uses free var" do
    assert_type("
      def foo(x : {X, Y}) forall X, Y
        Y
      end

      foo({1, 2.5})
      ") { float64.metaclass }
  end

  it "matches tuple with underscore" do
    assert_type("
      def foo(x : {_, _})
        x
      end

      foo({1, 2.5})
      ") { tuple_of([int32, float64] of Type) }
  end

  it "gives correct error message, looking up parent defs, when no overload matches" do
    assert_error %(
      class Foo
        def foo(x : Int32)
        end
      end

      class Bar < Foo
        def foo
        end
      end

      Bar.new.foo(1.5)
      ),
      "expected argument #1 to 'Bar#foo' to be Int32, not Float64"
  end

  it "doesn't match with wrong number of type arguments (#313)" do
    assert_error %(
      class Foo(A, B)
      end

      def foo(x : Foo(Int32))
      end

      foo Foo(Int32, Int32).new
      ),
      "wrong number of type vars for Foo(A, B) (given 1, expected 2)"
  end

  it "includes splat symbol in error message" do
    assert_error %(
      def foo(x : Int32, *bar)
      end

      foo 'a'
      ),
      "foo(x : Int32, *bar)"
  end

  it "says `no overload matches` instead of `can't instantiate abstract class` on wrong argument in new method" do
    assert_error %(
      abstract class Foo
        def self.new(x : Int)
        end
      end

      Foo.new('a')
      ),
      "expected argument #1 to 'Foo.new' to be Int, not Char"
  end

  it "finds method after including module in generic module (#1201)" do
    assert_type(%(
      module Bar
        def foo
          'a'
        end
      end

      module Moo(T)
      end

      class Foo
        include Moo(Int32)

        def foo(x)
          1
        end
      end

      module Moo(T)
        include Bar
      end

      Foo.new.foo
      )) { char }
  end

  it "reports no overload matches with correct method owner (#2083)" do
    assert_error %(
      class Foo
        def foo(x : Int32)
          x + 1
        end
      end

      class Bar < Foo
        def foo(x : Int32)
          x + 2
        end
      end

      Bar.new.foo("hello")
      ),
      <<-MSG
       - Bar#foo(x : Int32)
       - Foo#foo(x : Int32)
      MSG
  end

  it "gives better error message with consecutive arguments sizes" do
    assert_error %(
      def foo
      end

      def foo(x)
      end

      def foo(x, y)
      end

      foo 1, 2, 3
      ),
      "wrong number of arguments for 'foo' (given 3, expected 0..2)"
  end

  it "errors if no overload matches on union against named arg (#2640)" do
    assert_error %(
      def f(a : Int32)
      end

      a = 1 || nil
      f(a: a)
      ),
      "expected argument 'a' to 'f' to be Int32, not (Int32 | Nil)"
  end

  it "errors if no overload matches on union against named arg with external param name (#10516)" do
    assert_error %(
      def f(a b : Int32)
      end

      a = 1 || nil
      f(a: a)
      ),
      "expected argument 'a' to 'f' to be Int32, not (Int32 | Nil)"
  end

  it "dispatches with named arg" do
    assert_type(%(
      def f(a : Int32, b : Int32)
        true
      end

      def f(b : Int32, a : Nil)
        'x'
      end

      a = 1 || nil
      f(a: a, b: 2)
      )) { union_of bool, char }
  end

  it "uses long name when no overload matches and name is the same (#1030)" do
    assert_error %(
      module Moo::String
        def self.foo(a : String, b : Bool)
          puts a if b
        end
      end

      Moo::String.foo("Hello, World!", true)
      ),
      " - Moo::String.foo(a : Moo::String, b : Bool)"
  end

  it "overloads on metaclass (#2916)" do
    assert_type(%(
      def foo(x : String.class)
        1
      end

      def foo(x : String?.class)
        'a'
      end

      {foo(String), foo(typeof("" || nil))}
      )) { tuple_of([int32, char]) }
  end

  it "overloads on metaclass (2) (#2916)" do
    assert_type(%(
      def foo(x : String.class)
        1
      end

      def foo(x : ::String.class)
        'a'
      end

      foo(String)
      )) { char }
  end

  it "overloads on metaclass (3) (#2916)" do
    assert_type(%(
      class Foo
      end

      class Bar < Foo
      end

      def foo(x : Foo.class)
        1
      end

      def foo(x : Bar.class)
        'a'
      end

      {foo(Bar), foo(Foo)}
      )) { tuple_of([char, int32]) }
  end

  it "doesn't crash on unknown metaclass" do
    assert_type(%(
      def foo(x : Foo.class)
      end

      def foo(x : Bar.class)
      end

      1
      )) { int32 }
  end

  it "overloads union against non-union (#2904)" do
    assert_type(%(
      def foo(x : Int32?)
        true
      end

      def foo(x : Int32)
        'a'
      end

      {foo(1), foo(nil)}
      )) { tuple_of([char, bool]) }
  end

  it "errors when binding free variable to different types" do
    assert_error %(
      def foo(x : T, y : T) forall T
      end

      foo(1, 'a')
      ),
      "expected argument #2 to 'foo' to be Int32, not Char"
  end

  it "errors when binding free variable to different types (2)" do
    assert_error %(
      class Gen(T)
      end

      def foo(x : T, y : Gen(T)) forall T
      end

      foo(1, Gen(Char).new)
      ),
      "expected argument #2 to 'foo' to be Gen(Int32), not Gen(Char)"
  end

  it "overloads with named argument (#4465)" do
    assert_type(%(
			def do_something(value : Int32)
			  value + 1
			  1.5
			end

			def do_something(value : Char)
			  value.ord
			  false
			end

			do_something value: 7.as(Int32 | Char)
			), inject_primitives: true) { union_of float64, bool }
  end

  it "resets free vars after a partial match is rejected (#10270)" do
    assert_type(%(
      def foo(x : T, y : String) forall T
        1
      end

      def foo(x : Char, y : T) forall T
        true
      end

      foo('a', 1)
      )) { bool }
  end

  it "resets free vars after a partial match is rejected (2) (#10185)" do
    assert_type(%(
      def foo(*x : *T) forall T
        T
      end

      def foo(**x : **T) forall T
        T
      end

      foo(**{a: 1, b: ""})
      )) { named_tuple_of({a: int32, b: string}).metaclass }
  end

  it "considers NamedTuple in a module's including types (#10380)" do
    assert_error %(
      module Foo
      end

      struct NamedTuple
        include Foo
      end

      class Bar
        include Foo
      end

      def foo(x : Bar)
      end

      # force a name tuple instantiation
      {a: 1}

      x = uninitialized Foo
      foo(x)
      ),
      "expected argument #1 to 'foo' to be Bar, not Foo"
  end

  it "treats single splats with same restriction as equivalent (#12579)" do
    assert_type(<<-CRYSTAL) { int32 }
      def foo(*x : Int32)
        'a'
      end

      def foo(*x : Int32)
        1
      end

      foo(1)
      CRYSTAL
  end

  it "treats single splats with same restriction as equivalent (2) (#12579)" do
    assert_type(<<-CRYSTAL) { int32 }
      def foo(*x : Int32)
        'a'
      end

      def foo(*y : Int32)
        1
      end

      foo(1)
      CRYSTAL
  end

  describe "without `-Dpreview_overload_order`" do
    it "orders overloads as soon as they are defined" do
      assert_type(<<-CR) { bool }
        class Foo
        end

        def foo(a : Bar)
          1
        end

        def foo(a : Foo)
          true
        end

        class Bar < Foo
        end

        foo(Bar.new)
        CR
    end

    it "overload ordering is observable from top-level macros (1)" do
      assert_type(<<-CR) { int32 }
        class Foo
        end

        class Bar < Foo
          def foo(a : Foo)
            true
          end

          def foo(a : Bar)
            1
          end
        end

        {{ Bar.methods[0].body }}
        CR
    end

    it "overload ordering is observable from top-level macros (2)" do
      assert_type(<<-CR) { int32 }
        module Foo
          def foo
            true
          end

          def foo
            1
          end
        end

        {{ Foo.methods[0].body }}
        CR
    end

    it "overload ordering is observable from macro defs" do
      assert_type(<<-CR) { int32 }
        class Foo
        end

        class Bar < Foo
          def foo(a : Foo)
            true
          end

          def foo(a : Bar)
            1
          end
        end

        def foo
          {{ Bar.methods[0].body }}
        end

        foo
        CR
    end
  end

  describe "with `-Dpreview_overload_order`" do
    it "orders overloads after all types are defined" do
      assert_type(<<-CR, flags: "preview_overload_order") { int32 }
        class Foo
        end

        def foo(a : Bar)
          1
        end

        def foo(a : Foo)
          true
        end

        class Bar < Foo
        end

        foo(Bar.new)
        CR
    end

    it "overload ordering is not observable from top-level macros (1)" do
      assert_type(<<-CR, flags: "preview_overload_order") { bool }
        class Foo
        end

        class Bar < Foo
          def foo(a : Foo)
            true
          end

          def foo(a : Bar)
            1
          end
        end

        {{ Bar.methods[0].body }}
        CR
    end

    it "overload ordering is not observable from top-level macros (2)" do
      assert_type(<<-CR, flags: "preview_overload_order") { bool }
        module Foo
          def foo
            true
          end

          def foo
            1
          end
        end

        {{ Foo.methods[0].body }}
        CR
    end

    it "overload ordering is observable from macro defs" do
      assert_type(<<-CR, flags: "preview_overload_order") { int32 }
        class Foo
        end

        class Bar < Foo
          def foo(a : Foo)
            true
          end

          def foo(a : Bar)
            1
          end
        end

        def foo
          {{ Bar.methods[0].body }}
        end

        foo
        CR
    end
  end
end

private def each_union_variant(t1, t2, &)
  yield "#{t1} | #{t2}"
  yield "#{t2} | #{t1}"
  # yield "Union(#{t1}, #{t2})"
  # yield "Union(#{t2}, #{t1})"
  yield "#{t1}?" if t2 == "Nil"
  yield "#{t2}?" if t1 == "Nil" && t2 != "Nil"
end
