{% skip_file if flag?(:without_interpreter) %}
require "./spec_helper"

describe Crystal::Repl::Interpreter do
  context "is_a?" do
    it "does is_a? from NilableReferenceType to NonGenericClassType (true)" do
      interpret(<<-CRYSTAL).should eq("hello")
        a = "hello" || nil
        if a.is_a?(String)
          a
        else
          "bar"
        end
        CRYSTAL
    end

    it "does is_a? from NilableReferenceType to NonGenericClassType (false)" do
      interpret(<<-CRYSTAL).should eq("bar")
        a = 1 == 1 ? nil : "hello"
        if a.is_a?(String)
          a
        else
          z = a
          "bar"
        end
        CRYSTAL
    end

    it "does is_a? from NilableReferenceType to GenericClassInstanceType (true)" do
      interpret(<<-CRYSTAL).should eq(1)
        class Foo(T)
          def initialize(@x : T)
          end

          def x
            @x
          end
        end

        a = Foo.new(1) || nil
        if a.is_a?(Foo)
          a.x
        else
          2
        end
        CRYSTAL
    end

    it "does is_a? from NilableReferenceType to GenericClassInstanceType (false)" do
      interpret(<<-CRYSTAL).should eq(2)
        class Foo(T)
          def initialize(@x : T)
          end

          def x
            @x
          end
        end

        a = 1 == 1 ? nil : Foo.new(1)
        if a.is_a?(Foo)
          a.x
        else
          z = a
          2
        end
        CRYSTAL
    end

    it "does is_a? from NilableReferenceUnionType to NonGenericClassType (true)" do
      interpret(<<-CRYSTAL).should eq("hello")
        class Foo
        end

        a = 1 == 1 ? "hello" : (1 == 1 ? Foo.new : nil)
        if a.is_a?(String)
          a
        else
          "bar"
        end
        CRYSTAL
    end

    it "does is_a? from NilableReferenceUnionType to NonGenericClassType (false)" do
      interpret(<<-CRYSTAL).should eq("baz")
        class Foo
        end

        a = 1 == 1 ? "hello" : (1 == 1 ? Foo.new : nil)
        if a.is_a?(Foo)
          "bar"
        else
          "baz"
        end
        CRYSTAL
    end

    it "does is_a? from VirtualType to NonGenericClassType (true)" do
      interpret(<<-CRYSTAL).should eq(2)
        class Foo
          def x
            1
          end
        end

        class Bar < Foo
          def x
            2
          end
        end

        foo = Bar.new || Foo.new
        if foo.is_a?(Bar)
          foo.x
        else
          20
        end
        CRYSTAL
    end

    it "does is_a? from VirtualType to NonGenericClassType (false)" do
      interpret(<<-CRYSTAL).should eq(20)
        class Foo
          def x
            1
          end
        end

        class Bar < Foo
          def x
            2
          end
        end

        foo = Foo.new || Bar.new
        if foo.is_a?(Bar)
          foo.x
        else
          20
        end
        CRYSTAL
    end

    it "does is_a? from NilableProcType to Nil" do
      interpret(<<-CRYSTAL).should eq(10)
        proc = 1 == 1 ? nil : ->{ 1 }
        if proc.nil?
          10
        else
          20
        end
        CRYSTAL
    end

    it "does is_a? from NilableProcType to non-Nil" do
      interpret(<<-CRYSTAL).should eq(10)
        proc = 1 == 2 ? nil : ->{ 10 }
        if proc.is_a?(Proc)
          proc.call
        else
          20
        end
        CRYSTAL
    end
  end
end
