require "../../spec_helper"

describe "Semantic: recursive struct check" do
  it "errors on recursive struct" do
    assert_error %(
      struct Test
        def initialize(@test : Test?)
        end
      end

      Test.new(Test.new(nil))
      ),
      "recursive struct Test detected: `@test : (Test | Nil)`"
  end

  it "errors on recursive struct inside module" do
    assert_error %(
      struct Foo::Test
        def initialize(@test : Foo::Test?)
        end
      end

      Foo::Test.new(Foo::Test.new(nil))
      ),
      "recursive struct Foo::Test detected: `@test : (Foo::Test | Nil)`"
  end

  it "errors on recursive generic struct inside module" do
    assert_error %(
      struct Foo::Test(T)
        def initialize(@test : Foo::Test(T)?)
        end
      end

      Foo::Test(Int32).new(Foo::Test(Int32).new(nil))
      ),
      "recursive struct Foo::Test(T) detected: `@test : (Foo::Test(T) | Nil)`"
  end

  it "errors on mutually recursive struct" do
    assert_error %(
      struct Foo
        def initialize(@bar : Bar?)
        end
      end

      struct Bar
        def initialize(@foo : Foo?)
        end
      end

      Foo.new(Bar.new(nil))
      Bar.new(Foo.new(nil))
      ),
      "recursive struct Foo detected: `@bar : (Bar | Nil)` -> `@foo : (Foo | Nil)`"
  end

  it "detects recursive struct through module" do
    assert_error %(
      module Moo
      end

      struct Foo
        include Moo

        def initialize(@moo : Moo)
        end
      end
      ),
      "recursive struct Foo detected: `@moo : Moo` -> `Moo` -> `Foo`"
  end

  it "detects recursive generic struct through module (#4720)" do
    assert_error %(
      module Bar
      end

      struct Foo(T)
        include Bar
        def initialize(@base : Bar?)
        end
      end
      ),
      "recursive struct Foo(T) detected: `@base : (Bar | Nil)` -> `Bar` -> `Foo(T)`"
  end

  it "detects recursive generic struct through generic module (#4720)" do
    assert_error %(
      module Bar(T)
      end

      struct Foo(T)
        include Bar(T)
        def initialize(@base : Bar(T)?)
        end
      end
      ),
      "recursive struct Foo(T) detected: `@base : (Bar(T) | Nil)` -> `Bar(T)` -> `Foo(T)`"
  end

  it "detects recursive struct through inheritance (#3071)" do
    assert_error %(
      abstract struct Foo
      end

      struct Bar < Foo
        @value = uninitialized Foo
      end
      ),
      "recursive struct Bar detected: `@value : Foo` -> `Foo` -> `Bar`"
  end
end
