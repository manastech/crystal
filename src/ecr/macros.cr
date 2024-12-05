require "./processor"

module ECR
  # Defines a `to_s(io)` method whose body is the ECR contained
  # in *filename*, translated to Crystal code.
  #
  # ```text
  # # greeting.ecr
  # Hello <%= @name %>!
  # ```
  #
  # ```
  # require "ecr/macros"
  #
  # class Greeting
  #   def initialize(@name : String)
  #   end
  #
  #   ECR.def_to_s "greeting.ecr"
  # end
  #
  # Greeting.new("World").to_s # => "Hello World!"
  # ```
  #
  # The macro basically translates the text inside the given file
  # to Crystal code that appends to the IO:
  #
  # ```
  # class Greeting
  #   def to_s(io)
  #     io << "Hello "
  #     io << @name
  #     io << '!'
  #   end
  # end
  # ```
  macro def_to_s(filename)
    def to_s(__io__ : IO) : Nil
      ::ECR.embed {{filename}}, "__io__"
    end
  end

  # Embeds an ECR file *filename* into the program and appends the content to
  # an IO in the variable *io_name*.
  #
  # The generated code is the result of translating the contents of
  # the ECR file to Crystal, a program that appends to an IO.
  #
  # ```text
  # # greeting.ecr
  # Hello <%= name %>!
  # ```
  #
  # ```
  # require "ecr/macros"
  #
  # name = "World"
  #
  # io = IO::Memory.new
  # ECR.embed "greeting.ecr", io
  # io.to_s # => "Hello World!"
  # ```
  #
  # The `ECR.embed` line basically generates this Crystal code:
  #
  # ```
  # io << "Hello "
  # io << name
  # io << '!'
  # ```
  macro embed(filename, io_name)
    ::ECR.process_string({{ read_file(filename) }}, {{ filename }}, {{ io_name.id.stringify }}, false)
  end

  # Embeds an ECR file *filename* into the program and renders it to a string.
  #
  # The generated code is the result of translating the contents of
  # the ECR file to Crystal, a program that appends to an IO and returns a string.
  #
  # ```text
  # # greeting.ecr
  # Hello <%= name %>!
  # ```
  #
  # ```
  # require "ecr/macros"
  #
  # name = "World"
  #
  # rendered = ECR.render "greeting.ecr"
  # rendered # => "Hello World!"
  # ```
  #
  # The `ECR.render` basically generates this Crystal code:
  #
  # ```
  # String.build do |io|
  #   io << "Hello "
  #   io << name
  #   io << '!'
  # end
  # ```
  macro render(filename)
    ::String.build do |%io|
      ::ECR.embed({{filename}}, %io)
    end
  end
end
