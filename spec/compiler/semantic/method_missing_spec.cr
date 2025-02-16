require "../../spec_helper"

describe "Semantic: method_missing" do
  it "does error in method_missing macro with virtual type" do
    assert_error %(
      abstract class Foo
      end

      class Bar < Foo
        macro method_missing(call)
          2
        end
      end

      class Baz < Foo
      end

      foo = Baz.new || Bar.new
      foo.lala
      ), "undefined method 'lala' for Baz"
  end

  it "does error in method_missing if wrong number of params" do
    assert_error %(
      class Foo
        macro method_missing(call, foo)
        end
      end
      ), "wrong number of parameters for macro 'method_missing' (given 2, expected 1)"
  end

  it "does method missing for generic type" do
    assert_type(%(
      class Foo(T)
        macro method_missing(call)
          1
        end
      end

      Foo(Int32).new.foo
      )) { int32 }
  end

  it "errors if method_missing expands to an incorrect method" do
    assert_error %(
      class Foo
        macro method_missing(call)
          def baz
            1
          end
        end
      end

      Foo.new.bar
      ),
      "wrong method_missing expansion"
  end

  it "errors if method_missing expands to multiple methods" do
    assert_error %(
      class Foo
        macro method_missing(call)
          def bar
            1
          end

          def qux
          end
        end
      end

      Foo.new.bar
      ),
      "wrong method_missing expansion"
  end

  it "finds method_missing with 'with ... yield'" do
    assert_type(%(
      class Foo
        macro method_missing(call)
          1
        end
      end

      def bar
        foo = Foo.new
        with foo yield
      end

      bar do
        baz
      end
      )) { int32 }
  end

  it "reorders expanded def immediately" do
    assert_type(<<-CR) { int32 }
      class Foo
        macro method_missing(call)
          def foo(y : Int32)
            1
          end
        end

        def foo(x : Int32 | String)
          true
        end
      end

      Foo.new.foo(y: 1)
      Foo.new.foo(1)
      CR
  end

  it "reorders expanded def immediately, even if overload ordering is deferred" do
    assert_type(<<-CR, flags: "preview_overload_order") { int32 }
      class Foo
        macro method_missing(call)
          def foo(y : Int32)
            1
          end
        end

        def foo(x : Int32 | String)
          true
        end
      end

      Foo.new.foo(y: 1)
      Foo.new.foo(1)
      CR
  end

  it "doesn't look up method_missing in with_yield_scope if call has a receiver (#12097)" do
    assert_error(%(
      class Foo
        macro method_missing(method)
          def {{method}}
            1
          end
        end
      end

      def run
        with Foo.new yield
      end

      run do
        foo.bar
      end
      ),
      "undefined method 'bar' for Int32")
  end
end
