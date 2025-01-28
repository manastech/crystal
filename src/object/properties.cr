# WARNING: THIS FILE HAS BEEN AUTOGENERATED BY scripts/generate_object_properties.cr
# WARNING: DO NOT EDIT MANUALLY!

class Object
  # Defines getter methods for each of the given arguments.
  #
  # Writing:
  #
  # ```
  # class Person
  #   getter name
  # end
  # ```
  #
  # Is the same as writing:
  #
  # ```
  # class Person
  #   def name
  #     @name
  #   end
  # end
  # ```
  #
  # The arguments can be string literals, symbol literals or plain names:
  #
  # ```
  # class Person
  #   getter :name, "age"
  # end
  # ```
  #
  # If a type declaration is given, a variable with that name
  # is declared with that type.
  #
  # ```
  # class Person
  #   getter name : String
  # end
  # ```
  #
  # Is the same as writing:
  #
  # ```
  # class Person
  #   @name : String
  #
  #   def name : String
  #     @name
  #   end
  # end
  # ```
  #
  # The type declaration can also include an initial value:
  #
  # ```
  # class Person
  #   getter name : String = "John Doe"
  # end
  # ```
  #
  # Is the same as writing:
  #
  # ```
  # class Person
  #   @name : String = "John Doe"
  #
  #   def name : String
  #     @name
  #   end
  # end
  # ```
  #
  # An assignment can be passed too, but in this case the type of the
  # variable must be easily inferable from the initial value:
  #
  # ```
  # class Person
  #   getter name = "John Doe"
  # end
  # ```
  #
  # Is the same as writing:
  #
  # ```
  # class Person
  #   @name = "John Doe"
  #
  #   def name : String
  #     @name
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
  #   getter(birth_date) { Time.local }
  # end
  # ```
  #
  # Is the same as writing:
  #
  # ```
  # class Person
  #   def birth_date
  #     if (value = @birth_date).nil?
  #       @birth_date = Time.local
  #     else
  #       value
  #     end
  #   end
  # end
  # ```
  macro getter(*names, &block)
    {% for name in names %}
      {% if name.is_a?(TypeDeclaration) %}
        {% var_name = name.var.id %}
        {% type = name.type %}
        {% if block %}
          @{{var_name}} : {{type}}? {% if name.value %} = {{name.value}} {% end %}
        {% else %}
          @{{name}}
        {% end %}
      {% elsif name.is_a?(Assign) %}
        {% var_name = name.target %}
        {% type = nil %}
        @{{name}}
      {% else %}
        {% var_name = name.id %}
        {% type = nil %}
      {% end %}

      def {{var_name}} {% if type %} : {{type}} {% end %}
        {% if block %}
          if (%value = @{{var_name}}).nil?
            @{{var_name}} = {{yield}}
          else
            %value
          end
        {% else %}
          @{{var_name}}
        {% end %}
      end

    {% end %}
  end

  # Defines query getter methods for each of the given arguments.
  #
  # Writing:
  #
  # ```
  # class Person
  #   getter? happy
  # end
  # ```
  #
  # Is the same as writing:
  #
  # ```
  # class Person
  #   def happy?
  #     @happy
  #   end
  # end
  # ```
  #
  # The arguments can be string literals, symbol literals or plain names:
  #
  # ```
  # class Person
  #   getter? :happy, "famous"
  # end
  # ```
  #
  # If a type declaration is given, a variable with that name
  # is declared with that type.
  #
  # ```
  # class Person
  #   getter? happy : Bool
  # end
  # ```
  #
  # is the same as writing:
  #
  # ```
  # class Person
  #   @happy : Bool
  #
  #   def happy? : Bool
  #     @happy
  #   end
  # end
  # ```
  #
  # The type declaration can also include an initial value:
  #
  # ```
  # class Person
  #   getter? happy : Bool = true
  # end
  # ```
  #
  # Is the same as writing:
  #
  # ```
  # class Person
  #   @happy : Bool = true
  #
  #   def happy? : Bool
  #     @happy
  #   end
  # end
  # ```
  #
  # An assignment can be passed too, but in this case the type of the
  # variable must be easily inferable from the initial value:
  #
  # ```
  # class Person
  #   getter? happy = true
  # end
  # ```
  #
  # Is the same as writing:
  #
  # ```
  # class Person
  #   @happy = true
  #
  #   def happy?
  #     @happy
  #   end
  # end
  # ```
  #
  # If a block is given to the macro, a getter is generated with a variable
  # that is lazily initialized with the block's contents, for examples see
  # `#getter`.
  macro getter?(*names, &block)
    {% for name in names %}
      {% if name.is_a?(TypeDeclaration) %}
        {% var_name = name.var.id %}
        {% type = name.type %}
        {% if block %}
          @{{var_name}} : {{type}}? {% if name.value %} = {{name.value}} {% end %}
        {% else %}
          @{{name}}
        {% end %}
      {% elsif name.is_a?(Assign) %}
        {% var_name = name.target %}
        {% type = nil %}
        @{{name}}
      {% else %}
        {% var_name = name.id %}
        {% type = nil %}
      {% end %}

      def {{var_name}}? {% if type %} : {{type}} {% end %}
        {% if block %}
          if (%value = @{{var_name}}).nil?
            @{{var_name}} = {{yield}}
          else
            %value
          end
        {% else %}
          @{{var_name}}
        {% end %}
      end

    {% end %}
  end

  # Defines raise-on-nil and nilable getter methods for each of the given arguments.
  #
  # Writing:
  #
  # ```
  # class Person
  #   getter! name
  # end
  # ```
  #
  # Is the same as writing:
  #
  # ```
  # class Person
  #   def name?
  #     @name
  #   end
  #
  #   def name
  #     @name.not_nil!
  #   end
  # end
  # ```
  #
  # The arguments can be string literals, symbol literals or plain names:
  #
  # ```
  # class Person
  #   getter! :name, "age"
  # end
  # ```
  #
  # If a type declaration is given, a variable with that name
  # is declared with that type, as nilable.
  #
  # ```
  # class Person
  #   getter! name : String
  # end
  # ```
  #
  # is the same as writing:
  #
  # ```
  # class Person
  #   @name : String?
  #
  #   def name?
  #     @name
  #   end
  #
  #   def name
  #     @name.not_nil!
  #   end
  # end
  # ```
  macro getter!(*names)
    {% for name in names %}
      {% if name.is_a?(TypeDeclaration) %}
        {% var_name = name.var.id %}
        {% type = name.type %}
        @{{name}}?
      {% else %}
        {% var_name = name.id %}
        {% type = nil %}
      {% end %}

      def {{var_name}}? {% if type %} : {{type}}? {% end %}
        @{{var_name}}
      end

      def {{var_name}} {% if type %} : {{type}} {% end %}
        if (%value = @{{var_name}}).nil?
          ::raise ::NilAssertionError.new("{{@type.id}}{{"#".id}}{{var_name}} cannot be nil")
        else
          %value
        end
      end

    {% end %}
  end

  # Defines setter methods for each of the given arguments.
  #
  # Writing:
  #
  # ```
  # class Person
  #   setter name
  # end
  # ```
  #
  # Is the same as writing:
  #
  # ```
  # class Person
  #   def name=(@name)
  #   end
  # end
  # ```
  #
  # The arguments can be string literals, symbol literals or plain names:
  #
  # ```
  # class Person
  #   setter :name, "age"
  # end
  # ```
  #
  # If a type declaration is given, a variable with that name
  # is declared with that type.
  #
  # ```
  # class Person
  #   setter name : String
  # end
  # ```
  #
  # is the same as writing:
  #
  # ```
  # class Person
  #   @name : String
  #
  #   def name=(@name : String)
  #   end
  # end
  # ```
  #
  # The type declaration can also include an initial value:
  #
  # ```
  # class Person
  #   setter name : String = "John Doe"
  # end
  # ```
  #
  # Is the same as writing:
  #
  # ```
  # class Person
  #   @name : String = "John Doe"
  #
  #   def name=(@name : String)
  #   end
  # end
  # ```
  #
  # An assignment can be passed too, but in this case the type of the
  # variable must be easily inferable from the initial value:
  #
  # ```
  # class Person
  #   setter name = "John Doe"
  # end
  # ```
  #
  # Is the same as writing:
  #
  # ```
  # class Person
  #   @name = "John Doe"
  #
  #   def name=(@name)
  #   end
  # end
  # ```
  macro setter(*names)
    {% for name in names %}
      {% if name.is_a?(TypeDeclaration) %}
        {% var_name = name.var.id %}
        {% type = name.type %}
        @{{name}}
      {% elsif name.is_a?(Assign) %}
        {% var_name = name.target %}
        {% type = nil %}
        @{{name}}
      {% else %}
        {% var_name = name.id %}
        {% type = nil %}
      {% end %}

      def {{var_name}}=(@{{var_name}}{% if type %} : {{type}} {% end %})
      end

    {% end %}
  end

  # Defines property methods for each of the given arguments.
  #
  # Writing:
  #
  # ```
  # class Person
  #   property name
  # end
  # ```
  #
  # Is the same as writing:
  #
  # ```
  # class Person
  #   def name=(@name)
  #   end
  #
  #   def name
  #     @name
  #   end
  # end
  # ```
  #
  # The arguments can be string literals, symbol literals or plain names:
  #
  # ```
  # class Person
  #   property :name, "age"
  # end
  # ```
  #
  # If a type declaration is given, a variable with that name
  # is declared with that type.
  #
  # ```
  # class Person
  #   property name : String
  # end
  # ```
  #
  # Is the same as writing:
  #
  # ```
  # class Person
  #   @name : String
  #
  #   def name=(@name)
  #   end
  #
  #   def name
  #     @name
  #   end
  # end
  # ```
  #
  # The type declaration can also include an initial value:
  #
  # ```
  # class Person
  #   property name : String = "John Doe"
  # end
  # ```
  #
  # Is the same as writing:
  #
  # ```
  # class Person
  #   @name : String = "John Doe"
  #
  #   def name=(@name : String)
  #   end
  #
  #   def name
  #     @name
  #   end
  # end
  # ```
  #
  # An assignment can be passed too, but in this case the type of the
  # variable must be easily inferable from the initial value:
  #
  # ```
  # class Person
  #   property name = "John Doe"
  # end
  # ```
  #
  # Is the same as writing:
  #
  # ```
  # class Person
  #   @name = "John Doe"
  #
  #   def name=(@name : String)
  #   end
  #
  #   def name
  #     @name
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
  #   property(birth_date) { Time.local }
  # end
  # ```
  #
  # Is the same as writing:
  #
  # ```
  # class Person
  #   def birth_date
  #     if (value = @birth_date).nil?
  #       @birth_date = Time.local
  #     else
  #       value
  #     end
  #   end
  #
  #   def birth_date=(@birth_date)
  #   end
  # end
  # ```
  macro property(*names, &block)
    {% for name in names %}
      {% if name.is_a?(TypeDeclaration) %}
        {% var_name = name.var.id %}
        {% type = name.type %}
        {% if block %}
          @{{var_name}} : {{type}}? {% if name.value %} = {{name.value}} {% end %}
        {% else %}
          @{{name}}
        {% end %}
      {% elsif name.is_a?(Assign) %}
        {% var_name = name.target %}
        {% type = nil %}
        @{{name}}
      {% else %}
        {% var_name = name.id %}
        {% type = nil %}
      {% end %}

      def {{var_name}} {% if type %} : {{type}} {% end %}
        {% if block %}
          if (%value = @{{var_name}}).nil?
            @{{var_name}} = {{yield}}
          else
            %value
          end
        {% else %}
          @{{var_name}}
        {% end %}
      end

      def {{var_name}}=(@{{var_name}}{% if type %} : {{type}} {% end %})
      end

    {% end %}
  end

  # Defines query property methods for each of the given arguments.
  #
  # Writing:
  #
  # ```
  # class Person
  #   property? happy
  # end
  # ```
  #
  # Is the same as writing:
  #
  # ```
  # class Person
  #   def happy=(@happy)
  #   end
  #
  #   def happy?
  #     @happy
  #   end
  # end
  # ```
  #
  # The arguments can be string literals, symbol literals or plain names:
  #
  # ```
  # class Person
  #   property? :happy, "famous"
  # end
  # ```
  #
  # If a type declaration is given, a variable with that name
  # is declared with that type.
  #
  # ```
  # class Person
  #   property? happy : Bool
  # end
  # ```
  #
  # Is the same as writing:
  #
  # ```
  # class Person
  #   @happy : Bool
  #
  #   def happy=(@happy : Bool)
  #   end
  #
  #   def happy? : Bool
  #     @happy
  #   end
  # end
  # ```
  #
  # The type declaration can also include an initial value:
  #
  # ```
  # class Person
  #   property? happy : Bool = true
  # end
  # ```
  #
  # Is the same as writing:
  #
  # ```
  # class Person
  #   @happy : Bool = true
  #
  #   def happy=(@happy : Bool)
  #   end
  #
  #   def happy? : Bool
  #     @happy
  #   end
  # end
  # ```
  #
  # An assignment can be passed too, but in this case the type of the
  # variable must be easily inferable from the initial value:
  #
  # ```
  # class Person
  #   property? happy = true
  # end
  # ```
  #
  # Is the same as writing:
  #
  # ```
  # class Person
  #   @happy = true
  #
  #   def happy=(@happy)
  #   end
  #
  #   def happy?
  #     @happy
  #   end
  # end
  # ```
  #
  # If a block is given to the macro, a property is generated
  # with a variable that is lazily initialized with
  # the block's contents, for examples see `#property`.
  macro property?(*names, &block)
    {% for name in names %}
      {% if name.is_a?(TypeDeclaration) %}
        {% var_name = name.var.id %}
        {% type = name.type %}
        {% if block %}
          @{{var_name}} : {{type}}? {% if name.value %} = {{name.value}} {% end %}
        {% else %}
          @{{name}}
        {% end %}
      {% elsif name.is_a?(Assign) %}
        {% var_name = name.target %}
        {% type = nil %}
        @{{name}}
      {% else %}
        {% var_name = name.id %}
        {% type = nil %}
      {% end %}

      def {{var_name}}? {% if type %} : {{type}} {% end %}
        {% if block %}
          if (%value = @{{var_name}}).nil?
            @{{var_name}} = {{yield}}
          else
            %value
          end
        {% else %}
          @{{var_name}}
        {% end %}
      end

      def {{var_name}}=(@{{var_name}}{% if type %} : {{type}} {% end %})
      end

    {% end %}
  end

  # Defines raise-on-nil property methods for each of the given arguments.
  #
  # Writing:
  #
  # ```
  # class Person
  #   property! name
  # end
  # ```
  #
  # Is the same as writing:
  #
  # ```
  # class Person
  #   def name=(@name)
  #   end
  #
  #   def name?
  #     @name
  #   end
  #
  #   def name
  #     @name.not_nil!
  #   end
  # end
  # ```
  #
  # The arguments can be string literals, symbol literals or plain names:
  #
  # ```
  # class Person
  #   property! :name, "age"
  # end
  # ```
  #
  # If a type declaration is given, a variable with that name
  # is declared with that type, as nilable.
  #
  # ```
  # class Person
  #   property! name : String
  # end
  # ```
  #
  # Is the same as writing:
  #
  # ```
  # class Person
  #   @name : String?
  #
  #   def name=(@name)
  #   end
  #
  #   def name?
  #     @name
  #   end
  #
  #   def name
  #     @name.not_nil!
  #   end
  # end
  # ```
  macro property!(*names)
    {% for name in names %}
      {% if name.is_a?(TypeDeclaration) %}
        {% var_name = name.var.id %}
        {% type = name.type %}
        @{{name}}?
      {% else %}
        {% var_name = name.id %}
        {% type = nil %}
      {% end %}

      def {{var_name}}? {% if type %} : {{type}}? {% end %}
        @{{var_name}}
      end

      def {{var_name}} {% if type %} : {{type}} {% end %}
        if (%value = @{{var_name}}).nil?
          ::raise ::NilAssertionError.new("{{@type.id}}{{"#".id}}{{var_name}} cannot be nil")
        else
          %value
        end
      end

      def {{var_name}}=(@{{var_name}}{% if type %} : {{type}} {% end %})
      end

    {% end %}
  end

  # Defines getter methods for each of the given arguments.
  #
  # Writing:
  #
  # ```
  # class Person
  #   class_getter name
  # end
  # ```
  #
  # Is the same as writing:
  #
  # ```
  # class Person
  #   def self.name
  #     @@name
  #   end
  # end
  # ```
  #
  # The arguments can be string literals, symbol literals or plain names:
  #
  # ```
  # class Person
  #   class_getter :name, "age"
  # end
  # ```
  #
  # If a type declaration is given, a variable with that name
  # is declared with that type.
  #
  # ```
  # class Person
  #   class_getter name : String
  # end
  # ```
  #
  # Is the same as writing:
  #
  # ```
  # class Person
  #   @@name : String
  #
  #   def self.name : String
  #     @@name
  #   end
  # end
  # ```
  #
  # The type declaration can also include an initial value:
  #
  # ```
  # class Person
  #   class_getter name : String = "John Doe"
  # end
  # ```
  #
  # Is the same as writing:
  #
  # ```
  # class Person
  #   @@name : String = "John Doe"
  #
  #   def self.name : String
  #     @@name
  #   end
  # end
  # ```
  #
  # An assignment can be passed too, but in this case the type of the
  # variable must be easily inferable from the initial value:
  #
  # ```
  # class Person
  #   class_getter name = "John Doe"
  # end
  # ```
  #
  # Is the same as writing:
  #
  # ```
  # class Person
  #   @@name = "John Doe"
  #
  #   def self.name : String
  #     @@name
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
  #   class_getter(birth_date) { Time.local }
  # end
  # ```
  #
  # Is the same as writing:
  #
  # ```
  # class Person
  #   def self.birth_date
  #     if (value = @@birth_date).nil?
  #       @@birth_date = Time.local
  #     else
  #       value
  #     end
  #   end
  # end
  # ```
  macro class_getter(*names, &block)
    {% for name in names %}
      {% if name.is_a?(TypeDeclaration) %}
        {% var_name = name.var.id %}
        {% type = name.type %}
        {% if block %}
          @@{{var_name}} : {{type}}? {% if name.value %} = {{name.value}} {% end %}
        {% else %}
          @@{{name}}
        {% end %}
      {% elsif name.is_a?(Assign) %}
        {% var_name = name.target %}
        {% type = nil %}
        @@{{name}}
      {% else %}
        {% var_name = name.id %}
        {% type = nil %}
      {% end %}

      def self.{{var_name}} {% if type %} : {{type}} {% end %}
        {% if block %}
          if (%value = @@{{var_name}}).nil?
            @@{{var_name}} = {{yield}}
          else
            %value
          end
        {% else %}
          @@{{var_name}}
        {% end %}
      end

    {% end %}
  end

  # Defines query getter methods for each of the given arguments.
  #
  # Writing:
  #
  # ```
  # class Person
  #   class_getter? happy
  # end
  # ```
  #
  # Is the same as writing:
  #
  # ```
  # class Person
  #   def self.happy?
  #     @@happy
  #   end
  # end
  # ```
  #
  # The arguments can be string literals, symbol literals or plain names:
  #
  # ```
  # class Person
  #   class_getter? :happy, "famous"
  # end
  # ```
  #
  # If a type declaration is given, a variable with that name
  # is declared with that type.
  #
  # ```
  # class Person
  #   class_getter? happy : Bool
  # end
  # ```
  #
  # is the same as writing:
  #
  # ```
  # class Person
  #   @@happy : Bool
  #
  #   def self.happy? : Bool
  #     @@happy
  #   end
  # end
  # ```
  #
  # The type declaration can also include an initial value:
  #
  # ```
  # class Person
  #   class_getter? happy : Bool = true
  # end
  # ```
  #
  # Is the same as writing:
  #
  # ```
  # class Person
  #   @@happy : Bool = true
  #
  #   def self.happy? : Bool
  #     @@happy
  #   end
  # end
  # ```
  #
  # An assignment can be passed too, but in this case the type of the
  # variable must be easily inferable from the initial value:
  #
  # ```
  # class Person
  #   class_getter? happy = true
  # end
  # ```
  #
  # Is the same as writing:
  #
  # ```
  # class Person
  #   @@happy = true
  #
  #   def self.happy?
  #     @@happy
  #   end
  # end
  # ```
  #
  # If a block is given to the macro, a getter is generated with a variable
  # that is lazily initialized with the block's contents, for examples see
  # `#class_getter`.
  macro class_getter?(*names, &block)
    {% for name in names %}
      {% if name.is_a?(TypeDeclaration) %}
        {% var_name = name.var.id %}
        {% type = name.type %}
        {% if block %}
          @@{{var_name}} : {{type}}? {% if name.value %} = {{name.value}} {% end %}
        {% else %}
          @@{{name}}
        {% end %}
      {% elsif name.is_a?(Assign) %}
        {% var_name = name.target %}
        {% type = nil %}
        @@{{name}}
      {% else %}
        {% var_name = name.id %}
        {% type = nil %}
      {% end %}

      def self.{{var_name}}? {% if type %} : {{type}} {% end %}
        {% if block %}
          if (%value = @@{{var_name}}).nil?
            @@{{var_name}} = {{yield}}
          else
            %value
          end
        {% else %}
          @@{{var_name}}
        {% end %}
      end

    {% end %}
  end

  # Defines raise-on-nil and nilable getter methods for each of the given arguments.
  #
  # Writing:
  #
  # ```
  # class Person
  #   class_getter! name
  # end
  # ```
  #
  # Is the same as writing:
  #
  # ```
  # class Person
  #   def self.name?
  #     @@name
  #   end
  #
  #   def self.name
  #     @@name.not_nil!
  #   end
  # end
  # ```
  #
  # The arguments can be string literals, symbol literals or plain names:
  #
  # ```
  # class Person
  #   class_getter! :name, "age"
  # end
  # ```
  #
  # If a type declaration is given, a variable with that name
  # is declared with that type, as nilable.
  #
  # ```
  # class Person
  #   class_getter! name : String
  # end
  # ```
  #
  # is the same as writing:
  #
  # ```
  # class Person
  #   @@name : String?
  #
  #   def self.name?
  #     @@name
  #   end
  #
  #   def self.name
  #     @@name.not_nil!
  #   end
  # end
  # ```
  macro class_getter!(*names)
    {% for name in names %}
      {% if name.is_a?(TypeDeclaration) %}
        {% var_name = name.var.id %}
        {% type = name.type %}
        @@{{name}}?
      {% else %}
        {% var_name = name.id %}
        {% type = nil %}
      {% end %}

      def self.{{var_name}}? {% if type %} : {{type}}? {% end %}
        @@{{var_name}}
      end

      def self.{{var_name}} {% if type %} : {{type}} {% end %}
        if (%value = @@{{var_name}}).nil?
          ::raise ::NilAssertionError.new("{{@type.id}}{{".".id}}{{var_name}} cannot be nil")
        else
          %value
        end
      end

    {% end %}
  end

  # Defines setter methods for each of the given arguments.
  #
  # Writing:
  #
  # ```
  # class Person
  #   class_setter name
  # end
  # ```
  #
  # Is the same as writing:
  #
  # ```
  # class Person
  #   def self.name=(@@name)
  #   end
  # end
  # ```
  #
  # The arguments can be string literals, symbol literals or plain names:
  #
  # ```
  # class Person
  #   class_setter :name, "age"
  # end
  # ```
  #
  # If a type declaration is given, a variable with that name
  # is declared with that type.
  #
  # ```
  # class Person
  #   class_setter name : String
  # end
  # ```
  #
  # is the same as writing:
  #
  # ```
  # class Person
  #   @@name : String
  #
  #   def self.name=(@@name : String)
  #   end
  # end
  # ```
  #
  # The type declaration can also include an initial value:
  #
  # ```
  # class Person
  #   class_setter name : String = "John Doe"
  # end
  # ```
  #
  # Is the same as writing:
  #
  # ```
  # class Person
  #   @@name : String = "John Doe"
  #
  #   def self.name=(@@name : String)
  #   end
  # end
  # ```
  #
  # An assignment can be passed too, but in this case the type of the
  # variable must be easily inferable from the initial value:
  #
  # ```
  # class Person
  #   class_setter name = "John Doe"
  # end
  # ```
  #
  # Is the same as writing:
  #
  # ```
  # class Person
  #   @@name = "John Doe"
  #
  #   def self.name=(@@name)
  #   end
  # end
  # ```
  macro class_setter(*names)
    {% for name in names %}
      {% if name.is_a?(TypeDeclaration) %}
        {% var_name = name.var.id %}
        {% type = name.type %}
        @@{{name}}
      {% elsif name.is_a?(Assign) %}
        {% var_name = name.target %}
        {% type = nil %}
        @@{{name}}
      {% else %}
        {% var_name = name.id %}
        {% type = nil %}
      {% end %}

      def self.{{var_name}}=(@@{{var_name}}{% if type %} : {{type}} {% end %})
      end

    {% end %}
  end

  # Defines property methods for each of the given arguments.
  #
  # Writing:
  #
  # ```
  # class Person
  #   class_property name
  # end
  # ```
  #
  # Is the same as writing:
  #
  # ```
  # class Person
  #   def self.name=(@@name)
  #   end
  #
  #   def self.name
  #     @@name
  #   end
  # end
  # ```
  #
  # The arguments can be string literals, symbol literals or plain names:
  #
  # ```
  # class Person
  #   class_property :name, "age"
  # end
  # ```
  #
  # If a type declaration is given, a variable with that name
  # is declared with that type.
  #
  # ```
  # class Person
  #   class_property name : String
  # end
  # ```
  #
  # Is the same as writing:
  #
  # ```
  # class Person
  #   @@name : String
  #
  #   def self.name=(@@name)
  #   end
  #
  #   def self.name
  #     @@name
  #   end
  # end
  # ```
  #
  # The type declaration can also include an initial value:
  #
  # ```
  # class Person
  #   class_property name : String = "John Doe"
  # end
  # ```
  #
  # Is the same as writing:
  #
  # ```
  # class Person
  #   @@name : String = "John Doe"
  #
  #   def self.name=(@@name : String)
  #   end
  #
  #   def self.name
  #     @@name
  #   end
  # end
  # ```
  #
  # An assignment can be passed too, but in this case the type of the
  # variable must be easily inferable from the initial value:
  #
  # ```
  # class Person
  #   class_property name = "John Doe"
  # end
  # ```
  #
  # Is the same as writing:
  #
  # ```
  # class Person
  #   @@name = "John Doe"
  #
  #   def self.name=(@@name : String)
  #   end
  #
  #   def self.name
  #     @@name
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
  #   class_property(birth_date) { Time.local }
  # end
  # ```
  #
  # Is the same as writing:
  #
  # ```
  # class Person
  #   def self.birth_date
  #     if (value = @@birth_date).nil?
  #       @@birth_date = Time.local
  #     else
  #       value
  #     end
  #   end
  #
  #   def self.birth_date=(@@birth_date)
  #   end
  # end
  # ```
  macro class_property(*names, &block)
    {% for name in names %}
      {% if name.is_a?(TypeDeclaration) %}
        {% var_name = name.var.id %}
        {% type = name.type %}
        {% if block %}
          @@{{var_name}} : {{type}}? {% if name.value %} = {{name.value}} {% end %}
        {% else %}
          @@{{name}}
        {% end %}
      {% elsif name.is_a?(Assign) %}
        {% var_name = name.target %}
        {% type = nil %}
        @@{{name}}
      {% else %}
        {% var_name = name.id %}
        {% type = nil %}
      {% end %}

      def self.{{var_name}} {% if type %} : {{type}} {% end %}
        {% if block %}
          if (%value = @@{{var_name}}).nil?
            @@{{var_name}} = {{yield}}
          else
            %value
          end
        {% else %}
          @@{{var_name}}
        {% end %}
      end

      def self.{{var_name}}=(@@{{var_name}}{% if type %} : {{type}} {% end %})
      end

    {% end %}
  end

  # Defines query property methods for each of the given arguments.
  #
  # Writing:
  #
  # ```
  # class Person
  #   class_property? happy
  # end
  # ```
  #
  # Is the same as writing:
  #
  # ```
  # class Person
  #   def self.happy=(@@happy)
  #   end
  #
  #   def self.happy?
  #     @@happy
  #   end
  # end
  # ```
  #
  # The arguments can be string literals, symbol literals or plain names:
  #
  # ```
  # class Person
  #   class_property? :happy, "famous"
  # end
  # ```
  #
  # If a type declaration is given, a variable with that name
  # is declared with that type.
  #
  # ```
  # class Person
  #   class_property? happy : Bool
  # end
  # ```
  #
  # Is the same as writing:
  #
  # ```
  # class Person
  #   @@happy : Bool
  #
  #   def self.happy=(@@happy : Bool)
  #   end
  #
  #   def self.happy? : Bool
  #     @@happy
  #   end
  # end
  # ```
  #
  # The type declaration can also include an initial value:
  #
  # ```
  # class Person
  #   class_property? happy : Bool = true
  # end
  # ```
  #
  # Is the same as writing:
  #
  # ```
  # class Person
  #   @@happy : Bool = true
  #
  #   def self.happy=(@@happy : Bool)
  #   end
  #
  #   def self.happy? : Bool
  #     @@happy
  #   end
  # end
  # ```
  #
  # An assignment can be passed too, but in this case the type of the
  # variable must be easily inferable from the initial value:
  #
  # ```
  # class Person
  #   class_property? happy = true
  # end
  # ```
  #
  # Is the same as writing:
  #
  # ```
  # class Person
  #   @@happy = true
  #
  #   def self.happy=(@@happy)
  #   end
  #
  #   def self.happy?
  #     @@happy
  #   end
  # end
  # ```
  #
  # If a block is given to the macro, a property is generated
  # with a variable that is lazily initialized with
  # the block's contents, for examples see `#class_property`.
  macro class_property?(*names, &block)
    {% for name in names %}
      {% if name.is_a?(TypeDeclaration) %}
        {% var_name = name.var.id %}
        {% type = name.type %}
        {% if block %}
          @@{{var_name}} : {{type}}? {% if name.value %} = {{name.value}} {% end %}
        {% else %}
          @@{{name}}
        {% end %}
      {% elsif name.is_a?(Assign) %}
        {% var_name = name.target %}
        {% type = nil %}
        @@{{name}}
      {% else %}
        {% var_name = name.id %}
        {% type = nil %}
      {% end %}

      def self.{{var_name}}? {% if type %} : {{type}} {% end %}
        {% if block %}
          if (%value = @@{{var_name}}).nil?
            @@{{var_name}} = {{yield}}
          else
            %value
          end
        {% else %}
          @@{{var_name}}
        {% end %}
      end

      def self.{{var_name}}=(@@{{var_name}}{% if type %} : {{type}} {% end %})
      end

    {% end %}
  end

  # Defines raise-on-nil property methods for each of the given arguments.
  #
  # Writing:
  #
  # ```
  # class Person
  #   class_property! name
  # end
  # ```
  #
  # Is the same as writing:
  #
  # ```
  # class Person
  #   def self.name=(@@name)
  #   end
  #
  #   def self.name?
  #     @@name
  #   end
  #
  #   def self.name
  #     @@name.not_nil!
  #   end
  # end
  # ```
  #
  # The arguments can be string literals, symbol literals or plain names:
  #
  # ```
  # class Person
  #   class_property! :name, "age"
  # end
  # ```
  #
  # If a type declaration is given, a variable with that name
  # is declared with that type, as nilable.
  #
  # ```
  # class Person
  #   class_property! name : String
  # end
  # ```
  #
  # Is the same as writing:
  #
  # ```
  # class Person
  #   @@name : String?
  #
  #   def self.name=(@@name)
  #   end
  #
  #   def self.name?
  #     @@name
  #   end
  #
  #   def self.name
  #     @@name.not_nil!
  #   end
  # end
  # ```
  macro class_property!(*names)
    {% for name in names %}
      {% if name.is_a?(TypeDeclaration) %}
        {% var_name = name.var.id %}
        {% type = name.type %}
        @@{{name}}?
      {% else %}
        {% var_name = name.id %}
        {% type = nil %}
      {% end %}

      def self.{{var_name}}? {% if type %} : {{type}}? {% end %}
        @@{{var_name}}
      end

      def self.{{var_name}} {% if type %} : {{type}} {% end %}
        if (%value = @@{{var_name}}).nil?
          ::raise ::NilAssertionError.new("{{@type.id}}{{".".id}}{{var_name}} cannot be nil")
        else
          %value
        end
      end

      def self.{{var_name}}=(@@{{var_name}}{% if type %} : {{type}} {% end %})
      end

    {% end %}
  end
end
