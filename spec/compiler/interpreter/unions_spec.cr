{% skip_file if flag?(:without_interpreter) %}
require "./spec_helper"

describe Crystal::Repl::Interpreter do
  context "unions" do
    it "put and remove from union, together with is_a? (truthy case)" do
      interpret(<<-CRYSTAL).should eq(2)
        a = 1 == 1 ? 2 : true
        a.is_a?(Int32) ? a : 4
        CRYSTAL
    end

    it "put and remove from union, together with is_a? (falsey case)" do
      interpret(<<-CRYSTAL).should eq(true)
        a = 1 == 2 ? 2 : true
        a.is_a?(Int32) ? true : a
        CRYSTAL
    end

    it "returns union type" do
      interpret(<<-CRYSTAL).should eq('a')
        def foo
          if 1 == 1
            return 'a'
          end

          3
        end

        x = foo
        if x.is_a?(Char)
          x
        else
          'b'
        end
        CRYSTAL
    end

    it "returns large union type (#15041)" do
      interpret(<<-CRYSTAL).should eq(4_i64)
        a = {3_i64, 4_i64} || nil
        a.is_a?(Tuple) ? a[1] : 5_i64
        CRYSTAL
    end

    it "put and remove from union in local var" do
      interpret(<<-CRYSTAL).should eq(3)
        a = 1 == 1 ? 2 : true
        a = 3
        a.is_a?(Int32) ? a : 4
        CRYSTAL
    end

    it "put and remove from union in instance var" do
      interpret(<<-CRYSTAL).should eq(2)
        class Foo
          @x : Int32 | Char

          def initialize
            if 1 == 1
              @x = 2
            else
              @x = 'a'
            end
          end

          def x
            @x
          end
        end

        foo = Foo.new
        z = foo.x
        if z.is_a?(Int32)
          z
        else
          10
        end
      CRYSTAL
    end

    it "discards is_a?" do
      interpret(<<-CRYSTAL).should eq(3)
        a = 1 == 1 ? 2 : true
        a.is_a?(Int32)
        3
        CRYSTAL
    end

    it "converts from NilableReferenceType to NonGenericClassType" do
      interpret(<<-CRYSTAL).should eq("a")
        a = 1 == 1 ? "a" : nil
        a || "b"
        CRYSTAL
    end

    it "puts union inside union" do
      interpret(<<-CRYSTAL).should eq('a'.ord)
        a = 'a' || 1 || true
        case a
        in Char
          a.ord
        in Int32
          a
        in Bool
          20
        end
        CRYSTAL
    end
  end
end
