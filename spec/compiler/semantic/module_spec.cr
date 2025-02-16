require "../../spec_helper"

describe "Semantic: module" do
  it "includes but not a module" do
    assert_error "class Foo; end; class Bar; include Foo; end",
      "Foo is not a module"
  end

  it "includes module in a class" do
    assert_type("module Foo; def foo; 1; end; end; class Bar; include Foo; end; Bar.new.foo") { int32 }
  end

  it "includes module in a module" do
    assert_type("
      module Moo
        def foo
          1
        end
      end

      module Boo
        include Moo
      end

      class Foo
        include Boo
      end

      Foo.new.foo
      ") { int32 }
  end

  it "finds in module when included" do
    assert_type("
      module Moo
        class B
          def foo; 1; end
        end
      end

      include Moo

      B.new.foo
    ") { int32 }
  end

  it "includes generic module with type" do
    assert_type("
      module Foo(T)
        def foo(x : T)
          x
        end
      end

      class Bar
        include Foo(Int)
      end

      Bar.new.foo(1)
      ") { int32 }
  end

  it "includes generic module and errors in call" do
    assert_error "
      module Foo(T)
        def foo(x : T)
          x
        end
      end

      class Bar
        include Foo(Int)
      end

      Bar.new.foo(1.5)
      ",
      "expected argument #1 to 'Bar#foo' to be Int, not Float64"
  end

  it "includes module but not generic" do
    assert_error "
      module Foo
      end

      class Bar
        include Foo(Int)
      end
      ",
      "Foo is not a generic type"
  end

  it "errors if including generic and incorrect number of type vars" do
    assert_error "
      module Foo(T, U)
      end

      class Bar
        include Foo(Int)
      end
      ",
      "wrong number of type vars for Foo(T, U) (given 1, expected 2)"
  end

  it "errors if including variadic generic and incorrect number of type vars" do
    assert_error %(
      module Foo(*T, U, V)
      end

      class Bar
        include Foo(Int32)
      end
      ),
      "wrong number of type vars for Foo(*T, U, V) (given 1, expected 2+)"
  end

  it "errors if splatting type var into generic without splats" do
    assert_error %(
      module Foo(T)
      end

      class Bar(*T)
        include Foo(*T)
      end
      ),
      "cannot splat *T into Foo(T)"
  end

  it "errors if splatting type var into non-splat parameter, before splat in definition" do
    assert_error %(
      module Foo(T, *U)
      end

      class Bar(*T)
        include Foo(*T, Int32)
      end
      ),
      "cannot splat *T into non-splat type parameter T of Foo(T, *U)"
  end

  it "errors if splatting type var into non-splat parameter, after splat in definition" do
    assert_error %(
      module Foo(*T, U)
      end

      class Bar(*T)
        include Foo(Int32, *T)
      end
      ),
      "cannot splat *T into non-splat type parameter U of Foo(*T, U)"
  end

  it "errors if splatting type var into non-splat parameter, more args" do
    assert_error %(
      module Foo(T, *U, V, W)
      end

      class Bar(T, U, *V, W)
        include Foo(V, U, T, W, *V, T)
      end
      ),
      "cannot splat *V into non-splat type parameter V of Foo(T, *U, V, W)"
  end

  it "errors if including generic module and not specifying type vars" do
    assert_error "
      module Foo(T)
      end

      class Bar
        include Foo
      end
      ",
      "generic type arguments must be specified when including Foo(T)"
  end

  it "includes generic module explicitly" do
    assert_type("
      module Foo(T)
        def foo(x : T)
          x
        end
      end

      class Bar(U)
        include Foo(U)
      end

      Bar(Int32).new.foo(1)
      ") { int32 }
  end

  it "includes generic module explicitly and errors" do
    assert_error "
      module Foo(T)
        def foo(x : T)
          x
        end
      end

      class Bar(U)
        include Foo(U)
      end

      Bar(Int32).new.foo(1.5)
      ",
      "expected argument #1 to 'Bar(Int32)#foo' to be Int32, not Float64"
  end

  it "reports can't use instance variables inside module" do
    assert_error "def foo; @a = 1; end; foo",
      "can't use instance variables at the top level"
  end

  it "works with int including enumerable" do
    assert_type("
      require \"prelude\"

      struct Int32
        include Enumerable(Int32)

        def each
          yield self
          yield self + 2
        end
      end

      1.map { |x| x * 0.5 }
      ") { array_of(float64) }
  end

  it "works with range and map" do
    assert_type("
      require \"prelude\"
      (1..3).map { |x| x * 0.5 }
      ") { array_of(float64) }
  end

  it "declares module automatically if not previously declared when declaring a class" do
    assert_type("
      class Foo::Bar
      end
      Foo
      ") do
      foo = types["Foo"]
      foo.module?.should be_true
      foo.metaclass
    end
  end

  it "declares module automatically if not previously declared when declaring a module" do
    assert_type("
      module Foo::Bar
      end
      Foo
      ") do
      foo = types["Foo"]
      foo.module?.should be_true
      foo.metaclass
    end
  end

  it "includes generic module with another generic type" do
    assert_type("
      module Foo(T)
        def foo
          T
        end
      end

      class Baz(X)
      end

      class Bar(U)
        include Foo(Baz(U))
      end

      Bar(Int32).new.foo
      ") { generic_class("Baz", int32).metaclass }
  end

  it "includes generic module with self" do
    assert_type("
      module Foo(T)
        def foo
          T
        end
      end

      class Bar(U)
        include Foo(self)
      end

      Bar(Int32).new.foo
      ") { generic_class("Bar", int32).metaclass }
  end

  it "includes generic module with self, and inherits it" do
    assert_type("
      module Foo(T)
        def foo
          T
        end
      end

      class Bar(U)
        include Foo(self)
      end

      class Baz < Bar(Int32)
      end

      Baz.new.foo
      ") { generic_class("Bar", int32).metaclass }
  end

  it "includes generic module with self (check argument type, success)" do
    assert_type("
      module Foo(T)
        def foo(x : T)
          x
        end
      end

      class Bar(U)
        include Foo(self)
      end

      Bar(Int32).new.foo Bar(Int32).new
      ") { generic_class("Bar", int32) }
  end

  it "includes generic module with self (check argument superclass type, success)" do
    assert_type("
      module Foo(T)
        def foo(x : T)
          x
        end
      end

      class Bar(U)
        include Foo(self)
      end

      class Baz < Bar(Int32)
      end

      Bar(Int32).new.foo Baz.new
      ") { types["Baz"] }
  end

  it "includes generic module with self (check argument type, error)" do
    assert_error "
      module Foo(T)
        def foo(x : T)
          x
        end
      end

      class Bar(U)
        include Foo(self)
      end

      class Baz1 < Bar(Int32)
      end

      class Baz2 < Bar(Float64)
      end

      Baz1.new.foo Baz2.new
      ",
      "expected argument #1 to 'Baz1#foo' to be Bar(Int32), not Baz2"
  end

  it "includes generic module with self (check argument superclass type, success)" do
    assert_type("
      module Foo(T)
        def foo(x : T)
          x
        end
      end

      class Bar(U)
        include Foo(self)
      end

      class Baz1 < Bar(Int32)
      end

      class Baz2 < Bar(Int32)
      end

      Baz1.new.foo Baz2.new
      ") { types["Baz2"] }
  end

  it "includes generic module with self (check return type, success)" do
    assert_type("
      module Foo(T)
        def foo : T
          Bar(Int32).new
        end
      end

      class Bar(U)
        include Foo(self)
      end

      Bar(Int32).new.foo
      ") { generic_class("Bar", int32) }
  end

  it "includes generic module with self (check return subclass type, success)" do
    assert_type("
      module Foo(T)
        def foo : T
          Baz.new
        end
      end

      class Bar(U)
        include Foo(self)
      end

      class Baz < Bar(Int32)
      end

      Bar(Int32).new.foo
      ") { types["Baz"] }
  end

  it "includes generic module with self (check return type, error)" do
    assert_error "
      module Foo(T)
        def foo : T
          Bar(Int32).new
        end
      end

      class Bar(U)
        include Foo(self)
      end

      class Baz < Bar(Float64)
      end

      Baz.new.foo
      ", "method Baz#foo must return Bar(Float64) but it is returning Bar(Int32)"
  end

  it "includes generic module with self (check return subclass type, error)" do
    assert_error "
      module Foo(T)
        def foo : T
          Baz2.new
        end
      end

      class Bar(U)
        include Foo(self)
      end

      class Baz1 < Bar(Int32)
      end

      class Baz2 < Bar(Float64)
      end

      Baz1.new.foo
      ", "method Baz1#foo must return Bar(Int32) but it is returning Baz2"
  end

  it "includes module but can't access metaclass methods" do
    assert_error "
      module Foo
        def self.foo
          1
        end
      end

      class Bar
        include Foo
      end

      Bar.foo
      ", "undefined method 'foo'"
  end

  it "extends a module" do
    assert_type("
      module Foo
        def foo
          1
        end
      end

      class Bar
        extend Foo
      end

      Bar.foo
      ") { int32 }
  end

  it "extends self" do
    assert_type("
      module Foo
        extend self

        def foo
          1
        end
      end

      Foo.foo
      ") { int32 }
  end

  it "gives error when including self" do
    assert_error "
      module Foo
        include self
      end
      ", "cyclic include detected"
  end

  it "gives error with cyclic include" do
    assert_error "
      module Foo
      end

      module Bar
        include Foo
      end

      module Foo
        include Bar
      end
      ", "cyclic include detected"
  end

  it "gives error when including self, generic module" do
    assert_error "
      module Foo(T)
        include self
      end
      ", "cyclic include detected"
  end

  it "gives error when including instantiation of self, generic module" do
    assert_error "
      module Foo(T)
        include Foo(Int32)
      end
      ", "cyclic include detected"
  end

  it "gives error with cyclic include, generic module" do
    assert_error "
      module Foo(T)
      end

      module Bar(T)
        include Foo(T)
      end

      module Foo(T)
        include Bar(T)
      end
      ", "cyclic include detected"
  end

  it "gives error with cyclic include between non-generic and generic module" do
    assert_error "
      module Foo
      end

      module Bar(T)
        include Foo
      end

      module Foo
        include Bar(Int32)
      end
      ", "cyclic include detected"
  end

  it "gives error with cyclic include between non-generic and generic module (2)" do
    assert_error "
      module Bar(T)
      end

      module Foo
        include Bar(Int32)
      end

      module Bar(T)
        include Foo
      end
      ", "cyclic include detected"
  end

  it "finds types close to included module" do
    assert_type("
      module Foo
        class T
        end

        def foo
          T
        end
      end

      class Bar
        class T
        end

        include Foo
      end

      Bar.new.foo
      ") { types["Foo"].types["T"].metaclass }
  end

  it "finds nested type inside method in block inside module" do
    assert_type("
      def foo
        yield
      end

      module Foo
        class Bar; end

        @@x : Bar.class
        @@x = foo { Bar }

        def self.x
          @@x
        end
      end

      Foo.x
      ") { types["Foo"].types["Bar"].metaclass }
  end

  it "finds class method in block" do
    assert_type("
      def foo
        yield
      end

      module Foo
        def self.bar
          1
        end

        @@x : Int32
        @@x = foo { bar }

        def self.x
          @@x
        end
      end

      Foo.x
      ") { int32 }
  end

  it "types pointer of module" do
    assert_type("
      module Moo
      end

      class Foo
        include Moo

        def foo
          1
        end
      end

      p = Pointer(Moo).malloc(1_u64)
      p.value = Foo.new
      p.value
      ", inject_primitives: true) { types["Moo"] }
  end

  it "types pointer of module with method" do
    assert_type("
      module Moo
      end

      class Foo
        include Moo

        def foo
          1
        end
      end

      p = Pointer(Moo).malloc(1_u64)
      p.value = Foo.new
      p.value.foo
      ", inject_primitives: true) { int32 }
  end

  it "types pointer of module with method with two including types" do
    assert_type("
      module Moo
      end

      class Foo
        include Moo

        def foo
          1
        end
      end

      class Bar
        include Moo

        def foo
          'a'
        end
      end

      p = Pointer(Moo).malloc(1_u64)
      p.value = Foo.new
      p.value = Bar.new
      p.value.foo
      ", inject_primitives: true) { union_of(int32, char) }
  end

  it "types pointer of module with generic type" do
    assert_type("
      module Moo
      end

      class Foo(T)
        include Moo

        def foo
          1
        end
      end

      p = Pointer(Moo).malloc(1_u64)
      p.value = Foo(Int32).new
      p.value.foo
      ", inject_primitives: true) { int32 }
  end

  it "types pointer of module with generic type" do
    assert_type("
      module Moo
      end

      class Bar
        def self.boo
          1
        end
      end

      class Baz
        def self.boo
          'a'
        end
      end

      class Foo(T)
        include Moo

        def foo
          T.boo
        end
      end

      p = Pointer(Moo).malloc(1_u64)
      p.value = Foo(Bar).new
      x = p.value.foo

      p.value = Foo(Baz).new

      x
      ", inject_primitives: true) { union_of(int32, char) }
  end

  it "allows overloading with included generic module" do
    assert_type(%(
      module Foo(T)
        def foo(x : T)
          bar(x)
        end
      end

      class Bar
        include Foo(Int32)
        include Foo(String)

        def bar(x : Int32)
          1
        end

        def bar(x : String)
          "a"
        end
      end

      Bar.new.foo(1 || "hello")
      )) { union_of(int32, string) }
  end

  it "finds constant in generic module included in another module" do
    assert_type(%(
      module Foo(T)
        def foo
          T
        end
      end

      module Bar(T)
        include Foo(T)
      end

      class Baz
        include Bar(Int32)
      end

      Baz.new.foo
      )) { int32.metaclass }
  end

  it "calls super on included generic module" do
    assert_type(%(
      module Foo(T)
        def foo
          1
        end
      end

      class Bar
        include Foo(Int32)

        def foo
          super
        end
      end

      Bar.new.foo
      )) { int32 }
  end

  it "calls super on included generic module and finds type var" do
    assert_type(%(
      module Foo(T)
        def foo
          T
        end
      end

      class Bar(T)
        include Foo(T)

        def foo
          super
        end
      end

      Bar(Int32).new.foo
      )) { int32.metaclass }
  end

  it "calls super on included generic module and finds type var (2)" do
    assert_type(%(
      module Foo(T)
        def foo
          T
        end
      end

      module Bar(T)
        include Foo(T)

        def foo
          super
        end
      end

      class Baz(T)
        include Bar(T)
      end

      Baz(Int32).new.foo
      )) { int32.metaclass }
  end

  it "types union of module and class that includes it" do
    assert_type(%(
      module Moo
        def self.foo
          1
        end
      end

      class Bar
        include Moo

        def self.foo
          2
        end
      end

      Bar || Moo
      )) { union_of(types["Bar"].metaclass, types["Moo"].metaclass) }
  end

  it "works ok in a case where a typed-def type has an underlying type that has an included generic module (bug)" do
    assert_type(%(
      lib LibC
        type X = Void*
        fun x : X
      end

      module Mod(T)
        def bar(other : T)
          1
        end
      end

      struct Pointer
        include Mod(self)

        def foo
          address
        end
      end

      LibC.x.foo

      p = Pointer(Void).malloc(1_u64)
      p.bar(p)
      ), inject_primitives: true) { int32 }
  end

  it "finds inner class from inherited one (#476)" do
    assert_type(%(
      class Foo
        class Bar
          class Baz
          end
        end
      end

      class Quz < Foo
      end

      Quz::Bar::Baz
      )) { types["Foo"].types["Bar"].types["Baz"].metaclass }
  end

  it "type def does not reopen type from parent namespace (#11181)" do
    assert_type <<-CR, inject_primitives: false { types["Baz"].types["Foo"].types["Bar"].metaclass }
      module Foo::Bar
      end

      module Baz
        module Foo::Bar
        end
      end

      Baz::Foo::Bar
      CR
  end

  it "correctly types type var in included module, with a restriction with a free var (bug)" do
    assert_type(%(
      module Moo(T)
      end

      class Foo(T)
        include Moo(T)

        def foo(x : Moo(U)) forall U
          T
        end
      end

      Foo(Int32).new.foo(Foo(Char).new)
      )) { int32.metaclass }
  end

  it "types proc of module after type changes" do
    assert_type(%(
      module Moo
      end

      class Foo(T)
        include Moo

        def foo
          3
        end
      end

      z = ->(x : Moo) { x.foo }
      z.call(Foo(Int32).new)
      ), inject_primitives: true) { int32 }
  end

  it "types proc of module with generic class" do
    assert_type(%(
      module Moo
      end

      class Foo(T)
        include Moo

        def foo
          'a'
        end
      end

      z = ->(x : Moo) { x.foo }
      z.call(Foo(Int32).new)
      ), inject_primitives: true) { char }
  end

  it "errors if declares module inside if" do
    assert_error %(
      if 1 == 2
        module Foo; end
      end
      ),
      "can't declare module dynamically"
  end

  it "can't reopen as class" do
    assert_error "
      module Foo
      end

      class Foo
      end
      ", "Foo is not a class, it's a module"
  end

  it "can't reopen as struct" do
    assert_error "
      module Foo
      end

      struct Foo
      end
      ", "Foo is not a struct, it's a module"
  end

  it "errors if reopening non-generic module as generic" do
    assert_error %(
      module Foo
      end

      module Foo(T)
      end
      ),
      "Foo is not a generic module"
  end

  it "errors if reopening generic module with different type vars" do
    assert_error %(
      module Foo(T)
      end

      module Foo(U)
      end
      ),
      "type var must be T, not U"
  end

  it "errors if reopening generic module with different type vars (2)" do
    assert_error %(
      module Foo(A, B)
      end

      module Foo(C)
      end
      ),
      "type vars must be A, B, not C"
  end

  it "errors if reopening generic module with different splat index" do
    assert_error %(
      module Foo(A)
      end

      module Foo(*A)
      end
      ),
      "type var must be A, not *A"
  end

  it "errors if reopening generic module with different splat index (2)" do
    assert_error %(
      module Foo(*A)
      end

      module Foo(A)
      end
      ),
      "type var must be *A, not A"
  end

  it "errors if reopening generic module with different splat index (3)" do
    assert_error %(
      module Foo(*A, B)
      end

      module Foo(A, *B)
      end
      ),
      "type vars must be *A, B, not A, *B"
  end

  it "uses :Module name for modules in errors" do
    assert_error %(
      module Moo; end

      Moo.new
      ),
      "undefined method 'new' for Moo:Module"
  end

  it "gives error when trying to instantiate with new" do
    assert_error %(
      module Moo
        def initialize
        end
      end
      Moo.new),
      "undefined local variable or method 'allocate' for Moo:Module (modules cannot be instantiated)"
  end

  it "gives error when trying to instantiate with allocate" do
    assert_error %(
      module Moo
        def initialize
        end
      end
      Moo.allocate),
      "undefined method 'allocate' for Moo:Module (modules cannot be instantiated)"
  end

  it "uses type declaration inside module" do
    assert_type(%(
      module Moo
        @x : Int32

        def initialize
          @x = 1
        end

        def x
          @x
        end
      end

      class Foo
        include Moo
      end

      Foo.new.x
      )) { int32 }
  end

  it "uses type declaration inside module and gives error" do
    assert_error %(
      module Moo
        @x : Int32

        def initialize(@x)
        end

        def moo
          @x = false
        end
      end

      class Foo
        include Moo

        def initialize
          super(1)
          @x = 1
        end
      end

      Foo.new.moo
      ),
      "instance variable '@x' of Foo must be Int32, not Bool"
  end

  it "uses type declaration inside module, recursive, and gives error" do
    assert_error %(
      module Moo
        @x : Int32

        def initialize(@x)
        end

        def moo
          @x = false
        end
      end

      module Moo2
        include Moo
      end

      class Foo
        include Moo2

        def initialize
          super(1)
          @x = 1
        end
      end

      Foo.new.moo
      ),
      "instance variable '@x' of Foo must be Int32"
  end

  it "initializes variable in module" do
    assert_type(%(
      module Moo
        @x = 1

        def x
          @x
        end
      end

      class Foo
        include Moo
      end

      Foo.new.x
      )) { int32 }
  end

  it "initializes variable in module, recursive" do
    assert_type(%(
      module Moo
        @x = 1

        def x
          @x
        end
      end

      module Moo2
        include Moo
      end

      class Foo
        include Moo2
      end

      Foo.new.x
      )) { int32 }
  end

  it "inherits instance var type annotation from generic to concrete" do
    assert_type(%(
      module Foo(T)
        @x : Int32?

        def x
          @x
        end
      end

      class Bar
        include Foo(Int32)
      end

      Bar.new.x
      )) { nilable int32 }
  end

  it "inherits instance var type annotation from generic to concrete with T" do
    assert_type(%(
      module Foo(T)
        @x : T?

        def x
          @x
        end
      end

      class Bar
        include Foo(Int32)
      end

      Bar.new.x
      )) { nilable int32 }
  end

  it "inherits instance var type annotation from generic to generic to concrete" do
    assert_type(%(
      module Foo(T)
        @x : Int32?

        def x
          @x
        end
      end

      module Bar(T)
        include Foo(T)
      end

      class Baz
        include Bar(Int32)
      end

      Baz.new.x
      )) { nilable int32 }
  end

  it "instantiates generic variadic module, accesses T from instance method" do
    assert_type(%(
      module Moo(*T)
        def t
          T
        end
      end

      class Foo
        include Moo(Int32, Char)
      end

      Foo.new.t
      )) { tuple_of([int32, char]).metaclass }
  end

  it "instantiates generic variadic module, accesses T from class method" do
    assert_type(%(
      module Moo(*T)
        def t
          T
        end
      end

      class Foo
        extend Moo(Int32, Char)
      end

      Foo.t
      )) { tuple_of([int32, char]).metaclass }
  end

  it "instantiates generic variadic module, accesses T from instance method through generic include" do
    assert_type(%(
      module Moo(*T)
        def t
          T
        end
      end

      class Foo(*T)
        include Moo(*T)
      end

      Foo(Int32, Char).new.t
      )) { tuple_of([int32, char]).metaclass }
  end

  it "instantiates generic variadic module, accesses T from class method through generic extend" do
    assert_type(%(
      module Moo(*T)
        def t
          T
        end
      end

      class Foo(*T)
        extend Moo(*T)
      end

      Foo(Int32, Char).t
      )) { tuple_of([int32, char]).metaclass }
  end

  it "instantiates generic variadic module, accesses T from instance method, more args" do
    assert_type(%(
      module Moo(A, *T, B)
        def t
          {A, T, B}
        end
      end

      class Foo
        include Moo(Int32, Float64, Char, String)
      end

      Foo.new.t
      )) { tuple_of([int32.metaclass, tuple_of([float64, char]).metaclass, string.metaclass]) }
  end

  it "instantiates generic variadic module, accesses T from instance method through generic include, more args" do
    assert_type(%(
      module Moo(A, *T, B)
        def t
          {A, T, B}
        end
      end

      class Foo(*T)
        include Moo(Int32, *T, String)
      end

      Foo(Float64, Char).new.t
      )) { tuple_of([int32.metaclass, tuple_of([float64, char]).metaclass, string.metaclass]) }
  end

  it "includes module with Union(T*)" do
    assert_type(%(
      module Foo(U)
        def u
          U
        end
      end

      struct Tuple
        include Foo(Union(*T))
      end

      {1, 'a'}.u
      )) { union_of(int32, char).metaclass }
  end

  it "doesn't lookup type in ancestor when matches in current type (#2982)" do
    assert_error %(
      module Foo
        module Qux
          class Bar
          end
        end
      end

      class Qux
      end

      include Foo

      Qux::Bar
      ),
      "undefined constant Qux::Bar"
  end

  it "can restrict module with module (#3029)" do
    assert_type(%(
      module Foo
      end

      class Gen(T)
      end

      def foo(x : Gen(Foo))
        1
      end

      foo(Gen(Foo).new)
      )) { int32 }
  end

  it "can instantiate generic module" do
    assert_type(%(
      module Foo(T)
      end

      Foo(Int32)
      )) { generic_module("Foo", int32).metaclass }
  end

  it "can use generic module as instance variable type" do
    assert_type(%(
      module Moo(T)
        def foo
          1
        end
      end

      class Foo
        include Moo(Int32)
      end

      class Bar
        include Moo(Int32)

        def foo
          'a'
        end
      end

      class Mooer
        def initialize(@moo : Moo(Int32))
        end

        def moo
          @moo.foo
        end
      end

      mooer = Mooer.new(Foo.new)
      mooer.moo
      )) { union_of int32, char }
  end

  it "can use generic module as instance variable type (2)" do
    assert_type(%(
      module Moo(T)
        def foo
          1
        end
      end

      class Foo(T)
        include Moo(T)
      end

      class Bar(T)
        include Moo(T)

        def foo
          'a'
        end
      end

      class Mooer
        def initialize(@moo : Moo(Int32))
        end

        def moo
          @moo.foo
        end
      end

      mooer = Mooer.new(Foo(Int32).new)
      mooer = Mooer.new(Bar(Int32).new)
      mooer.moo
      )) { union_of int32, char }
  end

  it "errors when extending module that defines instance vars (#4065)" do
    assert_error %(
      module Foo
        @x = 0
      end

      module Bar
        extend Foo
      end
      ),
      "can't declare instance variables in Foo because Bar extends it"
  end

  it "errors when extending module that defines instance vars (2) (#4065)" do
    assert_error %(
      module Foo
        @x : Int32?
      end

      module Bar
        extend Foo
      end
      ),
      "can't declare instance variables in Foo because Bar extends it"
  end

  it "errors when extending generic module that defines instance vars" do
    assert_error %(
      module Foo(T)
        @x = 0
      end

      module Bar(T)
        extend Foo(T)
      end
      ),
      "can't declare instance variables in Foo(T) because Bar(T) extends it"
  end

  it "errors when extending generic module that defines instance vars (2)" do
    assert_error %(
      module Foo(T)
        @x : T?
      end

      module Bar(T)
        extend Foo(T)
      end
      ),
      "can't declare instance variables in Foo(T) because Bar(T) extends it"
  end

  it "errors when recursively extending module that defines instance vars" do
    assert_error %(
      module Foo
        @x = 0
      end

      module Bar
        include Foo
      end

      module Baz
        extend Bar
      end
      ),
      "can't declare instance variables in Foo because Baz extends it"
  end

  it "errors when recursively extending module that defines instance vars (2)" do
    assert_error %(
      module Foo
        @x : Int32?
      end

      module Bar
        include Foo
      end

      module Baz
        extend Bar
      end
      ),
      "can't declare instance variables in Foo because Baz extends it"
  end

  it "errors when extending self and self defines instance vars (#9568)" do
    assert_error %(
      module Foo
        extend self

        @x = 0
      end
      ),
      "can't declare instance variables in Foo because Foo extends it"
  end

  it "errors when extending self and self defines instance vars (2) (#9568)" do
    assert_error %(
      module Foo
        extend self

        @x : Int32?
      end
      ),
      "can't declare instance variables in Foo because Foo extends it"
  end

  it "errors when extending self and self defines instance vars (3) (#9568)" do
    assert_error %(
      module Foo
        extend self

        def initialize
          @x = 0
        end
      end
      ),
      "can't declare instance variables in Foo because Foo extends it"
  end

  it "can't pass module class to virtual metaclass (#6113)" do
    assert_error %(
      module Moo
      end

      class Foo
      end

      class Bar < Foo
        include Moo
      end

      class Gen(T)
        def self.foo(x : T)
        end
      end

      Gen(Foo.class).foo(Moo)
      ),
      "expected argument #1 to 'Gen(Foo.class).foo' to be Foo.class, not Moo:Module"
  end

  it "extends module from generic class and calls class method (#7167)" do
    assert_type(%(
      module Foo
        def foo
          1
        end
      end

      class Gen(T)
        extend Foo
      end

      Gen(Int32).foo
      )) { int32 }
  end

  it "extends generic module from generic class and calls class method (#7167)" do
    assert_type(%(
      module Foo(T)
        def foo
          T
        end
      end

      class Gen(U)
        extend Foo(U)
      end

      Gen(Int32).foo
      )) { int32.metaclass }
  end

  it "extends generic module from generic module and calls class method (#7167)" do
    assert_type(%(
      module Foo(T)
        def foo
          T
        end
      end

      module Gen(U)
        extend Foo(U)
      end

      Gen(Int32).foo
      )) { int32.metaclass }
  end

  it "doesn't look up initialize past module that defines initialize (#7007)" do
    assert_error %(
      module Moo
        def initialize(x)
        end
      end

      class Foo
        include Moo
      end

      Foo.new
      ),
      "wrong number of arguments"
  end

  it "gives helpful error message when generic type var is missing" do
    assert_error %(
      module Foo(T)
        def self.foo
          T.bar
        end
      end

      Foo.foo
      ),
      "can't infer the type parameter T for the generic module Foo(T). Please provide it explicitly"
  end

  it "gives helpful error message when generic type var is missing in block spec" do
    assert_error %(
      module Foo(T)
        def self.foo(&block : T -> )
          block
        end
      end

      Foo.foo { |x| }
      ),
      "can't infer the type parameter T for the generic module Foo(T). Please provide it explicitly"
  end
end
