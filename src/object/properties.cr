# WARNING: THIS FILE HAS BEEN AUTOGENERATED BY scripts/generate_object_properties.cr
# WARNING: DO NOT EDIT MANUALLY!

class Object
  # Defines getter method(s) to access instance variable(s).
  #
  # Refer to [Getters](#getters) for details.
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

  # Identical to `getter` but defines query methods.
  #
  # For example writing:
  #
  # ```
  # class Robot
  #   getter? working
  # end
  # ```
  #
  # Is equivalent to writing:
  #
  # ```
  # class Robot
  #   def working?
  #     @working
  #   end
  # end
  # ```
  #
  # Refer to [Getters](#getters) for general details.
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

  # Similar to `getter` but defines both raise-on-nil methods as well as query
  # methods that return a nilable value.
  #
  # If a type is specified, then it will become a nilable type (union of the
  # type and `Nil`). Unlike the other `getter` methods the value is always
  # initialized to `nil`. There are no initial value or lazy initialization.
  #
  # For example writing:
  #
  # ```
  # class Robot
  #   getter! name : String
  # end
  # ```
  #
  # Is equivalent to writing:
  #
  # ```
  # class Robot
  #   @name : String?
  #
  #   def name? : String?
  #     @name
  #   end
  #
  #   def name : String
  #     @name.not_nil!("Robot#name cannot be nil")
  #   end
  # end
  # ```
  #
  # Refer to [Getters](#getters) for general details.
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

  # Generates setter methods to set instance variables.
  #
  # Refer to [Setters](#setters) for general details.
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

  # Generates both `getter` and `setter`
  # methods to access instance variables.
  #
  # Refer to the aforementioned macros for details.
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

  # Generates both `getter?` and `setter`
  # methods to access instance variables.
  #
  # Refer to the aforementioned macros for details.
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

  # Generates both `getter!` and `setter`
  # methods to access instance variables.
  #
  # Refer to the aforementioned macros for details.
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

  # Defines getter method(s) to access class variable(s).
  #
  # For example writing:
  #
  # ```
  # class Robot
  #   class_getter backend
  # end
  # ```
  #
  # Is equivalent to writing:
  #
  # ```
  # class Robot
  #   @@backend : String
  #
  #   def self.backend
  #     @@backend
  #   end
  # end
  # ```
  #
  # Refer to [Getters](#getters) for details.
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

  # Identical to `class_getter` but defines query methods.
  #
  # For example writing:
  #
  # ```
  # class Robot
  #   class_getter? backend
  # end
  # ```
  #
  # Is equivalent to writing:
  #
  # ```
  # class Robot
  #   def self.backend?
  #     @@backend
  #   end
  # end
  # ```
  #
  # Refer to [Getters](#getters) for general details.
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

  # Similar to `class_getter` but defines both raise-on-nil methods as well as
  # query methods that return a nilable value.
  #
  # If a type is specified, then it will become a nilable type (union of the
  # type and `Nil`). Unlike with `class_getter` the value is always initialized
  # to `nil`. There are no initial value or lazy initialization.
  #
  # For example writing:
  #
  # ```
  # class Robot
  #   class_getter! backend : String
  # end
  # ```
  #
  # Is equivalent to writing:
  #
  # ```
  # class Robot
  #   @@backend : String?
  #
  #   def self.backend? : String?
  #     @@backend
  #   end
  #
  #   def backend : String
  #     @@backend.not_nil!("Robot.backend cannot be nil")
  #   end
  # end
  # ```
  #
  # Refer to [Getters](#getters) for general details.
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

  # Generates setter method(s) to set class variable(s).
  #
  # For example writing:
  #
  # ```
  # class Robot
  #   class_setter factories
  # end
  # ```
  #
  # Is equivalent to writing:
  #
  # ```
  # class Robot
  #   @@factories
  #
  #   def self.factories=(@@factories)
  #   end
  # end
  # ```
  #
  # Refer to [Setters](#setters) for general details.
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

  # Generates both `class_getter` and `class_setter`
  # methods to access instance variables.
  #
  # Refer to the aforementioned macros for details.
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

  # Generates both `class_getter?` and `class_setter`
  # methods to access instance variables.
  #
  # Refer to the aforementioned macros for details.
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

  # Generates both `class_getter!` and `class_setter`
  # methods to access instance variables.
  #
  # Refer to the aforementioned macros for details.
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
