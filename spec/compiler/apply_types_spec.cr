require "./spec_helper"

def run_source_typer_spec(input, expected_output,
                          excludes : Array(String) = [] of String,
                          splats : Bool = true,
                          line_number : Int32 = 1,
                          named_splats : Bool = true,
                          blocks : Bool = true,
                          prelude : String = "")
  entrypoint_file = File.expand_path("entrypoint.cr")
  locator = line_number > 0 ? "#{entrypoint_file}:#{line_number}" : entrypoint_file
  typer = Crystal::SourceTyper.new(entrypoint_file, [locator], excludes, blocks, splats, named_splats, prelude)

  typer.semantic(entrypoint_file, input)

  typer.files.to_a.should eq [entrypoint_file]
  result = typer.type_source(entrypoint_file, input)
  result.try(&.strip).should eq expected_output.try &.strip
end

describe Crystal::SourceTyper do
  it "types method return types" do
    run_source_typer_spec(<<-INPUT, <<-OUTPUT)
    def hello
      "world!"
    end

    hello
    INPUT
    def hello : String
      "world!"
    end

    hello
    OUTPUT
  end

  it "types positional arguments" do
    run_source_typer_spec(<<-INPUT, <<-OUTPUT)
    def hello(arg)
      arg
    end
    hello("world")
    INPUT
    def hello(arg : String) : String
      arg
    end

    hello("world")
    OUTPUT
  end

  it "types positional args with unions" do
    run_source_typer_spec(<<-INPUT, <<-OUTPUT)
    def hello(arg)
      arg
    end
    hello("world")
    hello(3)
    INPUT
    def hello(arg : String | Int32) : String | Int32
      arg
    end

    hello("world")
    hello(3)
    OUTPUT
  end

  it "types splats, single type" do
    run_source_typer_spec(<<-INPUT, <<-OUTPUT)
    def hello(*arg)
      nil
    end
    hello("world")
    INPUT
    def hello(*arg : String) : Nil
      nil
    end

    hello("world")
    OUTPUT
  end

  it "types splats, multiple calls with single type" do
    run_source_typer_spec(<<-INPUT, <<-OUTPUT)
    def hello(*arg)
      nil
    end
    hello("world")
    hello(3)
    INPUT
    def hello(*arg : String | Int32) : Nil
      nil
    end

    hello("world")
    hello(3)
    OUTPUT
  end

  it "types splats, one call with multiple types" do
    run_source_typer_spec(<<-INPUT, <<-OUTPUT)
    def hello(*arg)
      nil
    end
    hello("world", 3)
    INPUT
    def hello(*arg : String | Int32) : Nil
      nil
    end

    hello("world", 3)
    OUTPUT
  end

  it "types arguments but not splats" do
    run_source_typer_spec(<<-INPUT, <<-OUTPUT, splats: false)
    def hello(the_arg, *arg)
      nil
    end
    hello(2, "world", 3)
    INPUT
    def hello(the_arg : Int32, *arg) : Nil
      nil
    end

    hello(2, "world", 3)
    OUTPUT
  end

  it "doesn't type splats with empty call" do
    run_source_typer_spec(<<-INPUT, <<-OUTPUT)
    def hello(*arg)
      nil
    end
    hello("world")
    hello
    INPUT
    def hello(*arg) : Nil
      nil
    end

    hello("world")
    hello
    OUTPUT
  end

  it "types double splats, single type" do
    run_source_typer_spec(<<-INPUT, <<-OUTPUT)
    def hello(**args)
      nil
    end
    hello(hello: "world")
    INPUT
    def hello(**args : String) : Nil
      nil
    end

    hello(hello: "world")
    OUTPUT
  end

  it "types double splats, multiple types" do
    run_source_typer_spec(<<-INPUT, <<-OUTPUT)
    def hello(**args)
      nil
    end
    hello(hello: "world", world: 3)
    INPUT
    def hello(**args : String | Int32) : Nil
      nil
    end

    hello(hello: "world", world: 3)
    OUTPUT
  end

  it "types arguments but not double splats" do
    run_source_typer_spec(<<-INPUT, <<-OUTPUT, named_splats: false)
    def hello(the_arg, **args)
      nil
    end
    hello(2, hello: "world", world: 3)
    INPUT
    def hello(the_arg : Int32, **args) : Nil
      nil
    end

    hello(2, hello: "world", world: 3)
    OUTPUT
  end

  it "types splats but not double splats" do
    run_source_typer_spec(<<-INPUT, <<-OUTPUT, named_splats: false)
    def hello(*arg, **args)
      nil
    end
    hello(2, hello: "world", world: 3)
    INPUT
    def hello(*arg : Int32, **args) : Nil
      nil
    end

    hello(2, hello: "world", world: 3)
    OUTPUT
  end

  it "types double plats but not splats" do
    run_source_typer_spec(<<-INPUT, <<-OUTPUT, splats: false)
    def hello(*arg, **args)
      nil
    end
    hello(2, hello: "world", world: 3)
    INPUT
    def hello(*arg, **args : String | Int32) : Nil
      nil
    end

    hello(2, hello: "world", world: 3)
    OUTPUT
  end

  it "doesn't type double splat with empty call" do
    run_source_typer_spec(<<-INPUT, <<-OUTPUT)
    def hello(**args)
      nil
    end
    hello(hello: "world", world: 3)
    hello
    INPUT
    def hello(**args) : Nil
      nil
    end

    hello(hello: "world", world: 3)
    hello
    OUTPUT
  end

  it "types blocks" do
    run_source_typer_spec(<<-INPUT, <<-OUTPUT)
    def hello(&block)
      block
    end
    hello {}
    INPUT
    def hello(&block : Proc(Nil)) : Proc(Nil)
      block
    end

    hello { }
    OUTPUT
  end

  it "types class instance methods" do
    run_source_typer_spec(<<-INPUT, <<-OUTPUT, line_number: 2)
    class Test
      def hello(arg)
        arg
      end
    end
    Test.new.hello(3)
    INPUT
    class Test
      def hello(arg : Int32) : Int32
        arg
      end
    end

    Test.new.hello(3)
    OUTPUT
  end

  it "types class methods" do
    run_source_typer_spec(<<-INPUT, <<-OUTPUT, line_number: 2)
    class Test
      def self.hello(arg)
        arg
      end
    end
    Test.hello(3)
    INPUT
    class Test
      def self.hello(arg : Int32) : Int32
        arg
      end
    end

    Test.hello(3)
    OUTPUT
  end

  it "types method included from module" do
    run_source_typer_spec(<<-INPUT, <<-OUTPUT, line_number: 2)
    module IncludeMe
      def hello(arg)
        arg
      end
    end

    class Test
      include IncludeMe
    end
    Test.new.hello(3)
    INPUT
    module IncludeMe
      def hello(arg : Int32) : Int32
        arg
      end
    end

    class Test
      include IncludeMe
    end

    Test.new.hello(3)
    OUTPUT
  end

  it "doesn't remove newline when inserting return types" do
    run_source_typer_spec(<<-INPUT, <<-OUTPUT)
    def hello
      # world
      "world"
    end
    hello
    INPUT
    def hello : String
      # world
      "world"
    end

    hello
    OUTPUT
  end

  it "turns unions with nil to have a '?' suffix" do
    run_source_typer_spec(<<-INPUT, <<-OUTPUT)
    def hello(arg)
      nil
    end
    hello(nil)
    hello("world")
    INPUT
    def hello(arg : String?) : Nil
      nil
    end

    hello(nil)
    hello("world")
    OUTPUT
  end

  it "types args that use keyword names" do
    run_source_typer_spec(<<-INPUT, <<-OUTPUT, line_number: 3)
    class Test
      @begin : String = ""
      def begin=(@begin)
      end
    end
    Test.new.begin = "world"
    INPUT
    class Test
      @begin : String = ""

      def begin=(@begin : String) : String
      end
    end

    Test.new.begin = "world"
    OUTPUT
  end

  it "types args that use an external name" do
    run_source_typer_spec(<<-INPUT, <<-OUTPUT)
    def test(external_name real_name)
      nil
    end

    test("world!")
    INPUT
    def test(external_name real_name : String) : Nil
      nil
    end

    test("world!")
    OUTPUT
  end

  it "types args that are module classes (Metatype)" do
    run_source_typer_spec(<<-INPUT, <<-OUTPUT, line_number: 4)
    module MyModule
    end

    def hello(world)
      nil
    end

    hello(MyModule)
    INPUT
    module MyModule
    end

    def hello(world : MyModule.class) : Nil
      nil
    end

    hello(MyModule)
    OUTPUT
  end

  it "types args and include default type" do
    run_source_typer_spec(<<-INPUT, <<-OUTPUT)
    def test(arg = nil)
      nil
    end
    test(3)
    INPUT
    def test(arg : Int32? = nil) : Nil
      nil
    end

    test(3)
    OUTPUT
  end

  it "types args with constant defaults" do
    run_source_typer_spec(<<-INPUT, <<-OUTPUT, line_number: -1)
    class Foo
      MY_CONSTANT = 3
      def test(arg = MY_CONSTANT); end
    end

    Foo.new.test(3.0)
    INPUT
    class Foo
      MY_CONSTANT = 3

      def test(arg : Float64 | Int32 = MY_CONSTANT) : Nil; end
    end

    Foo.new.test(3.0)
    OUTPUT
  end

  it "doesn't type methods that are inherited" do
    run_source_typer_spec(<<-INPUT, nil, line_number: -1)
    class Foo
      def test(arg)
        nil
      end
    end

    class Bar < Foo
      def test(arg)
        1
      end
    end

    Bar.new.test(3)
    INPUT
  end

  it "doesn't type ancestor methods that are inherited" do
    run_source_typer_spec(<<-INPUT, nil, line_number: -1)
    class Foo
      def test(arg)
        arg
      end
    end

    class Bar < Foo
      def test(arg)
        1
      end
    end

    Bar.new.test(3)
    Foo.new.test(2)
    INPUT
  end

  it "runs prelude and types everything" do
    run_source_typer_spec(<<-INPUT, <<-OUTPUT, line_number: -1, prelude: "prelude")
    # This file tries to capture each type of definition format
    def hello
      "world"
    end

    def hello1(arg1)
      arg1
    end

    def hello2(arg1, *, arg2)
      arg1 + arg2
    end

    def hello3(&block)
      block.call
    end

    def hello4(*args)
      args[0]?
    end

    def hello5(**args)
      nil
    end

    class Test
      def hello
        "world"
      end

      def self.hello
        "world"
      end
    end

    hello
    hello1("world")
    hello2(1, arg2: 2)
    hello3 do
      "hello"
    end
    hello4(3, "ok")
    hello5(test: "test", other: 3)
    Test.hello
    Test.new.hello

    INPUT
    # This file tries to capture each type of definition format
    def hello : String
      "world"
    end

    def hello1(arg1 : String) : String
      arg1
    end

    def hello2(arg1 : Int32, *, arg2 : Int32) : Int32
      arg1 + arg2
    end

    def hello3(&block : Proc(Nil)) : Nil
      block.call
    end

    def hello4(*args : Int32 | String) : Int32
      args[0]?
    end

    def hello5(**args : String | Int32) : Nil
      nil
    end

    class Test
      def hello : String
        "world"
      end

      def self.hello : String
        "world"
      end
    end

    hello
    hello1("world")
    hello2(1, arg2: 2)
    hello3 do
      "hello"
    end
    hello4(3, "ok")
    hello5(test: "test", other: 3)
    Test.hello
    Test.new.hello
    OUTPUT
  end
end
