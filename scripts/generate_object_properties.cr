#! /usr/bin/env crystal

struct Generator
  def initialize(@file : File, @macro_prefix : String, @method_prefix : String, @var_prefix : String, @doc_prefix : String)
  end

  def puts
    @file.puts
  end

  def puts(message)
    @file.puts(message)
  end

  def def_vars
    def_vars do
      <<-TEXT
              {% if block %}
                #{@var_prefix}{{var_name}} : {{type}}? {% if name.value %} = {{name.value}} {% end %}
              {% else %}
                #{@var_prefix}{{name}}
              {% end %}
      TEXT
    end
  end

  def def_vars_no_macro_block
    def_vars { "#{@var_prefix}{{name}}" }
  end

  def def_vars(&)
    <<-TEXT
          {% if name.is_a?(TypeDeclaration) %}
            {% var_name = name.var.id %}
            {% type = name.type %}
            #{yield.lstrip}
          {% elsif name.is_a?(Assign) %}
            {% var_name = name.target %}
            {% type = nil %}
            #{@var_prefix}{{name}}
          {% else %}
            {% var_name = name.id %}
            {% type = nil %}
          {% end %}

    TEXT
  end

  def def_vars!
    <<-TEXT
          {% if name.is_a?(TypeDeclaration) %}
            {% var_name = name.var.id %}
            {% type = name.type %}
            #{@var_prefix}{{name}}?
          {% else %}
            {% var_name = name.id %}
            {% type = nil %}
          {% end %}

    TEXT
  end

  def def_getter(suffix = "")
    <<-TEXT
          def #{@method_prefix}{{var_name}}#{suffix} {% if type %} : {{type}} {% end %}
            {% if block %}
              if (%value = #{@var_prefix}{{var_name}}).nil?
                #{@var_prefix}{{var_name}} = {{yield}}
              else
                %value
              end
            {% else %}
              #{@var_prefix}{{var_name}}
            {% end %}
          end

    TEXT
  end

  def def_getter!
    <<-TEXT
          def #{@method_prefix}{{var_name}}? {% if type %} : {{type}}? {% end %}
            #{@var_prefix}{{var_name}}
          end

          def #{@method_prefix}{{var_name}} {% if type %} : {{type}} {% end %}
            if (%value = #{@var_prefix}{{var_name}}).nil?
              ::raise ::NilAssertionError.new("{{@type.id}}{{#{@doc_prefix.inspect}.id}}{{var_name}} cannot be nil")
            else
              %value
            end
          end

    TEXT
  end

  def def_setter
    <<-TEXT
          def #{@method_prefix}{{var_name}}=(#{@var_prefix}{{var_name}}{% if type %} : {{type}} {% end %})
          end

    TEXT
  end

  def gen_getter
    puts <<-TEXT
      # Defines getter methods for each of the given arguments.
      #
      # Writing:
      #
      # ```
      # class Person
      #   #{@macro_prefix}getter name
      # end
      # ```
      #
      # Is the same as writing:
      #
      # ```
      # class Person
      #   def #{@method_prefix}name
      #     #{@var_prefix}name
      #   end
      # end
      # ```
      #
      # The arguments can be string literals, symbol literals or plain names:
      #
      # ```
      # class Person
      #   #{@macro_prefix}getter :name, "age"
      # end
      # ```
      #
      # If a type declaration is given, a variable with that name
      # is declared with that type.
      #
      # ```
      # class Person
      #   #{@macro_prefix}getter name : String
      # end
      # ```
      #
      # Is the same as writing:
      #
      # ```
      # class Person
      #   #{@var_prefix}name : String
      #
      #   def #{@method_prefix}name : String
      #     #{@var_prefix}name
      #   end
      # end
      # ```
      #
      # The type declaration can also include an initial value:
      #
      # ```
      # class Person
      #   #{@macro_prefix}getter name : String = "John Doe"
      # end
      # ```
      #
      # Is the same as writing:
      #
      # ```
      # class Person
      #   #{@var_prefix}name : String = "John Doe"
      #
      #   def #{@method_prefix}name : String
      #     #{@var_prefix}name
      #   end
      # end
      # ```
      #
      # An assignment can be passed too, but in this case the type of the
      # variable must be easily inferable from the initial value:
      #
      # ```
      # class Person
      #   #{@macro_prefix}getter name = "John Doe"
      # end
      # ```
      #
      # Is the same as writing:
      #
      # ```
      # class Person
      #   #{@var_prefix}name = "John Doe"
      #
      #   def #{@method_prefix}name : String
      #     #{@var_prefix}name
      #   end
      # end
      # ```
      #
      # If a block is given to the macro, a getter is generated
      # with a variable that is lazily initialized with
      # the block's contents:
      #
      # ```
      # class Person
      #   #{@macro_prefix}getter(birth_date) { Time.local }
      # end
      # ```
      #
      # Is the same as writing:
      #
      # ```
      # class Person
      #   def #{@method_prefix}birth_date
      #     if (value = #{@var_prefix}birth_date).nil?
      #       #{@var_prefix}birth_date = Time.local
      #     else
      #       value
      #     end
      #   end
      # end
      # ```
      macro #{@macro_prefix}getter(*names, &block)
        {% for name in names %}
    #{def_vars}
    #{def_getter}
        {% end %}
      end
    TEXT
  end

  def gen_getter?
    puts <<-TEXT
      # Defines query getter methods for each of the given arguments.
      #
      # Writing:
      #
      # ```
      # class Person
      #   #{@macro_prefix}getter? happy
      # end
      # ```
      #
      # Is the same as writing:
      #
      # ```
      # class Person
      #   def #{@method_prefix}happy?
      #     #{@var_prefix}happy
      #   end
      # end
      # ```
      #
      # The arguments can be string literals, symbol literals or plain names:
      #
      # ```
      # class Person
      #   #{@macro_prefix}getter? :happy, "famous"
      # end
      # ```
      #
      # If a type declaration is given, a variable with that name
      # is declared with that type.
      #
      # ```
      # class Person
      #   #{@macro_prefix}getter? happy : Bool
      # end
      # ```
      #
      # is the same as writing:
      #
      # ```
      # class Person
      #   #{@var_prefix}happy : Bool
      #
      #   def #{@method_prefix}happy? : Bool
      #     #{@var_prefix}happy
      #   end
      # end
      # ```
      #
      # The type declaration can also include an initial value:
      #
      # ```
      # class Person
      #   #{@macro_prefix}getter? happy : Bool = true
      # end
      # ```
      #
      # Is the same as writing:
      #
      # ```
      # class Person
      #   #{@var_prefix}happy : Bool = true
      #
      #   def #{@method_prefix}happy? : Bool
      #     #{@var_prefix}happy
      #   end
      # end
      # ```
      #
      # An assignment can be passed too, but in this case the type of the
      # variable must be easily inferable from the initial value:
      #
      # ```
      # class Person
      #   #{@macro_prefix}getter? happy = true
      # end
      # ```
      #
      # Is the same as writing:
      #
      # ```
      # class Person
      #   #{@var_prefix}happy = true
      #
      #   def #{@method_prefix}happy?
      #     #{@var_prefix}happy
      #   end
      # end
      # ```
      #
      # If a block is given to the macro, a getter is generated with a variable
      # that is lazily initialized with the block's contents, for examples see
      # `##{@macro_prefix}getter`.
      macro #{@macro_prefix}getter?(*names, &block)
        {% for name in names %}
    #{def_vars}
    #{def_getter "?"}
        {% end %}
      end
    TEXT
  end

  def gen_property
    puts <<-TEXT
      # Defines property methods for each of the given arguments.
      #
      # Writing:
      #
      # ```
      # class Person
      #   #{@macro_prefix}property name
      # end
      # ```
      #
      # Is the same as writing:
      #
      # ```
      # class Person
      #   def #{@method_prefix}name=(#{@var_prefix}name)
      #   end
      #
      #   def #{@method_prefix}name
      #     #{@var_prefix}name
      #   end
      # end
      # ```
      #
      # The arguments can be string literals, symbol literals or plain names:
      #
      # ```
      # class Person
      #   #{@macro_prefix}property :name, "age"
      # end
      # ```
      #
      # If a type declaration is given, a variable with that name
      # is declared with that type.
      #
      # ```
      # class Person
      #   #{@macro_prefix}property name : String
      # end
      # ```
      #
      # Is the same as writing:
      #
      # ```
      # class Person
      #   #{@var_prefix}name : String
      #
      #   def #{@method_prefix}name=(#{@var_prefix}name)
      #   end
      #
      #   def #{@method_prefix}name
      #     #{@var_prefix}name
      #   end
      # end
      # ```
      #
      # The type declaration can also include an initial value:
      #
      # ```
      # class Person
      #   #{@macro_prefix}property name : String = "John Doe"
      # end
      # ```
      #
      # Is the same as writing:
      #
      # ```
      # class Person
      #   #{@var_prefix}name : String = "John Doe"
      #
      #   def #{@method_prefix}name=(#{@var_prefix}name : String)
      #   end
      #
      #   def #{@method_prefix}name
      #     #{@var_prefix}name
      #   end
      # end
      # ```
      #
      # An assignment can be passed too, but in this case the type of the
      # variable must be easily inferable from the initial value:
      #
      # ```
      # class Person
      #   #{@macro_prefix}property name = "John Doe"
      # end
      # ```
      #
      # Is the same as writing:
      #
      # ```
      # class Person
      #   #{@var_prefix}name = "John Doe"
      #
      #   def #{@method_prefix}name=(#{@var_prefix}name : String)
      #   end
      #
      #   def #{@method_prefix}name
      #     #{@var_prefix}name
      #   end
      # end
      # ```
      #
      # If a block is given to the macro, a property is generated
      # with a variable that is lazily initialized with
      # the block's contents:
      #
      # ```
      # class Person
      #   #{@macro_prefix}property(birth_date) { Time.local }
      # end
      # ```
      #
      # Is the same as writing:
      #
      # ```
      # class Person
      #   def #{@method_prefix}birth_date
      #     if (value = #{@var_prefix}birth_date).nil?
      #       #{@var_prefix}birth_date = Time.local
      #     else
      #       value
      #     end
      #   end
      #
      #   def #{@method_prefix}birth_date=(#{@var_prefix}birth_date)
      #   end
      # end
      # ```
      macro #{@macro_prefix}property(*names, &block)
        {% for name in names %}
    #{def_vars}
    #{def_getter}
    #{def_setter}
        {% end %}
      end
    TEXT
  end

  def gen_property?
    puts <<-TEXT
      # Defines query property methods for each of the given arguments.
      #
      # Writing:
      #
      # ```
      # class Person
      #   #{@macro_prefix}property? happy
      # end
      # ```
      #
      # Is the same as writing:
      #
      # ```
      # class Person
      #   def #{@method_prefix}happy=(#{@var_prefix}happy)
      #   end
      #
      #   def #{@method_prefix}happy?
      #     #{@var_prefix}happy
      #   end
      # end
      # ```
      #
      # The arguments can be string literals, symbol literals or plain names:
      #
      # ```
      # class Person
      #   #{@macro_prefix}property? :happy, "famous"
      # end
      # ```
      #
      # If a type declaration is given, a variable with that name
      # is declared with that type.
      #
      # ```
      # class Person
      #   #{@macro_prefix}property? happy : Bool
      # end
      # ```
      #
      # Is the same as writing:
      #
      # ```
      # class Person
      #   #{@var_prefix}happy : Bool
      #
      #   def #{@method_prefix}happy=(#{@var_prefix}happy : Bool)
      #   end
      #
      #   def #{@method_prefix}happy? : Bool
      #     #{@var_prefix}happy
      #   end
      # end
      # ```
      #
      # The type declaration can also include an initial value:
      #
      # ```
      # class Person
      #   #{@macro_prefix}property? happy : Bool = true
      # end
      # ```
      #
      # Is the same as writing:
      #
      # ```
      # class Person
      #   #{@var_prefix}happy : Bool = true
      #
      #   def #{@method_prefix}happy=(#{@var_prefix}happy : Bool)
      #   end
      #
      #   def #{@method_prefix}happy? : Bool
      #     #{@var_prefix}happy
      #   end
      # end
      # ```
      #
      # An assignment can be passed too, but in this case the type of the
      # variable must be easily inferable from the initial value:
      #
      # ```
      # class Person
      #   #{@macro_prefix}property? happy = true
      # end
      # ```
      #
      # Is the same as writing:
      #
      # ```
      # class Person
      #   #{@var_prefix}happy = true
      #
      #   def #{@method_prefix}happy=(#{@var_prefix}happy)
      #   end
      #
      #   def #{@method_prefix}happy?
      #     #{@var_prefix}happy
      #   end
      # end
      # ```
      #
      # If a block is given to the macro, a property is generated
      # with a variable that is lazily initialized with
      # the block's contents, for examples see `##{@macro_prefix}property`.
      macro #{@macro_prefix}property?(*names, &block)
        {% for name in names %}
    #{def_vars}
    #{def_getter "?"}
    #{def_setter}
        {% end %}
      end
    TEXT
  end

  def gen_getter!
    puts <<-TEXT
      # Defines raise-on-nil and nilable getter methods for each of the given arguments.
      #
      # Writing:
      #
      # ```
      # class Person
      #   #{@macro_prefix}getter! name
      # end
      # ```
      #
      # Is the same as writing:
      #
      # ```
      # class Person
      #   def #{@method_prefix}name?
      #     #{@var_prefix}name
      #   end
      #
      #   def #{@method_prefix}name
      #     #{@var_prefix}name.not_nil!
      #   end
      # end
      # ```
      #
      # The arguments can be string literals, symbol literals or plain names:
      #
      # ```
      # class Person
      #   #{@macro_prefix}getter! :name, "age"
      # end
      # ```
      #
      # If a type declaration is given, a variable with that name
      # is declared with that type, as nilable.
      #
      # ```
      # class Person
      #   #{@macro_prefix}getter! name : String
      # end
      # ```
      #
      # is the same as writing:
      #
      # ```
      # class Person
      #   #{@var_prefix}name : String?
      #
      #   def #{@method_prefix}name?
      #     #{@var_prefix}name
      #   end
      #
      #   def #{@method_prefix}name
      #     #{@var_prefix}name.not_nil!
      #   end
      # end
      # ```
      macro #{@macro_prefix}getter!(*names)
        {% for name in names %}
    #{def_vars!}
    #{def_getter!}
        {% end %}
      end
    TEXT
  end

  def gen_property!
    puts <<-TEXT
      # Defines raise-on-nil property methods for each of the given arguments.
      #
      # Writing:
      #
      # ```
      # class Person
      #   #{@macro_prefix}property! name
      # end
      # ```
      #
      # Is the same as writing:
      #
      # ```
      # class Person
      #   def #{@method_prefix}name=(#{@var_prefix}name)
      #   end
      #
      #   def #{@method_prefix}name?
      #     #{@var_prefix}name
      #   end
      #
      #   def #{@method_prefix}name
      #     #{@var_prefix}name.not_nil!
      #   end
      # end
      # ```
      #
      # The arguments can be string literals, symbol literals or plain names:
      #
      # ```
      # class Person
      #   #{@macro_prefix}property! :name, "age"
      # end
      # ```
      #
      # If a type declaration is given, a variable with that name
      # is declared with that type, as nilable.
      #
      # ```
      # class Person
      #   #{@macro_prefix}property! name : String
      # end
      # ```
      #
      # Is the same as writing:
      #
      # ```
      # class Person
      #   #{@var_prefix}name : String?
      #
      #   def #{@method_prefix}name=(#{@var_prefix}name)
      #   end
      #
      #   def #{@method_prefix}name?
      #     #{@var_prefix}name
      #   end
      #
      #   def #{@method_prefix}name
      #     #{@var_prefix}name.not_nil!
      #   end
      # end
      # ```
      macro #{@macro_prefix}property!(*names)
        {% for name in names %}
    #{def_vars!}
    #{def_getter!}
    #{def_setter}
        {% end %}
      end
    TEXT
  end

  def gen_setter
    puts <<-TEXT
      # Defines setter methods for each of the given arguments.
      #
      # Writing:
      #
      # ```
      # class Person
      #   #{@macro_prefix}setter name
      # end
      # ```
      #
      # Is the same as writing:
      #
      # ```
      # class Person
      #   def #{@method_prefix}name=(#{@var_prefix}name)
      #   end
      # end
      # ```
      #
      # The arguments can be string literals, symbol literals or plain names:
      #
      # ```
      # class Person
      #   #{@macro_prefix}setter :name, "age"
      # end
      # ```
      #
      # If a type declaration is given, a variable with that name
      # is declared with that type.
      #
      # ```
      # class Person
      #   #{@macro_prefix}setter name : String
      # end
      # ```
      #
      # is the same as writing:
      #
      # ```
      # class Person
      #   #{@var_prefix}name : String
      #
      #   def #{@method_prefix}name=(#{@var_prefix}name : String)
      #   end
      # end
      # ```
      #
      # The type declaration can also include an initial value:
      #
      # ```
      # class Person
      #   #{@macro_prefix}setter name : String = "John Doe"
      # end
      # ```
      #
      # Is the same as writing:
      #
      # ```
      # class Person
      #   #{@var_prefix}name : String = "John Doe"
      #
      #   def #{@method_prefix}name=(#{@var_prefix}name : String)
      #   end
      # end
      # ```
      #
      # An assignment can be passed too, but in this case the type of the
      # variable must be easily inferable from the initial value:
      #
      # ```
      # class Person
      #   #{@macro_prefix}setter name = "John Doe"
      # end
      # ```
      #
      # Is the same as writing:
      #
      # ```
      # class Person
      #   #{@var_prefix}name = "John Doe"
      #
      #   def #{@method_prefix}name=(#{@var_prefix}name)
      #   end
      # end
      # ```
      macro #{@macro_prefix}setter(*names)
        {% for name in names %}
    #{def_vars_no_macro_block}
    #{def_setter}
        {% end %}
      end
    TEXT
  end
end

directory = File.expand_path("../src/object", __DIR__)
Dir.mkdir(directory) unless Dir.exists?(directory)

output = File.join(directory, "properties.cr")
File.open(output, "w") do |f|
  f.puts "# WARNING: THIS FILE HAS BEEN AUTOGENERATED BY scripts/generate_object_properties.cr"
  f.puts "# WARNING: DO NOT EDIT MANUALLY!"
  f.puts
  f.puts "class Object"

  g = Generator.new(f, "", "", "@", "#")

  g.gen_getter
  g.gen_getter?
  g.gen_getter!

  g.gen_setter

  g.gen_property
  g.gen_property?
  g.gen_property!

  g = Generator.new(f, "class_", "self.", "@@", ".")

  g.gen_getter
  g.gen_getter?
  g.gen_getter!

  g.gen_setter

  g.gen_property
  g.gen_property?
  g.gen_property!

  f.puts "end"
end
