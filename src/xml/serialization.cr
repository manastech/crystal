module XML
  struct Any
    alias Type = Nil | Bool | Int64 | Float64 | String | Array(Any) | Hash(String, Any)

    # Returns the raw underlying value.
    getter raw : Type

    # Creates a `XML::Any` that wraps the given value.
    def initialize(@raw : Type)
    end
  end

  annotation Element
  end

  module Serializable
    annotation Options
    end

    macro included
      def self.new(parser : ::XML::PullParser)
        new_from_xml_node(parser)
      end

      private def self.new_from_xml_node(parser : ::XML::PullParser)
        instance = allocate
        instance.initialize(__for_xml_serializable: parser)
        GC.add_finalizer(instance) if instance.responds_to?(:finalize)
        instance
      end

      macro inherited
        def self.new(parser : ::XML::PullParser)
          new_from_xml_node(parser)
        end
      end
    end

    def initialize(*, __for_xml_serializable parser : ::XML::PullParser)
      {% begin %}
        {% properties = {} of Nil => Nil %}
        {% for ivar in @type.instance_vars %}
          # TODO: handle Attribute
          {% ann = ivar.annotation(::XML::Element) %}
          {% unless ann && (ann[:ignore] || ann[:ignore_deserialize]) %}
            {%
              properties[ivar.id] = {
                type:        ivar.type,
                key:         ((ann && ann[:key]) || ivar).id.stringify,
                has_default: ivar.has_default_value?,
                default:     ivar.default_value,
                nilable:     ivar.type.nilable?,
                root:        ann && ann[:root],
                converter:   ann && ann[:converter],
                presence:    ann && ann[:presence],
              }
            %}
          {% end %}
        {% end %}

        {% for name, value in properties %}
          %var{name} = nil
          %found{name} = false
        {% end %}

        el_name = parser.name
        while parser.readable?
          %location = {parser.line_number, parser.column_number}

          case el_name
          {% for name, value in properties %}
            when {{value[:key]}}
              %found{name} = true

              begin
              {% if value[:converter] %}
                %var{name} = {{value[:converter]}}.from_xml(parser)
              {% else %}
                %var{name} = ::Union({{value[:type]}}).new(parser)
              {% end %}

              rescue exc : ::XML::Error
                raise ::XML::SerializableError.new(exc.message, self.class.to_s, {{value[:key]}}, exc.line_number)
              end
          {% end %}
          else
            on_unknown_xml_attribute(parser, el_name)
          end

          el_name = parser.read_name
        end

        {% for name, value in properties %}
          {% unless value[:nilable] || value[:has_default] %}
            if %var{name}.nil? && !%found{name} && !::Union({{value[:type]}}).nilable?
              raise ::XML::SerializableError.new("Missing XML node: {{value[:key].id}}", self.class.to_s, nil, 0)
            end
          {% end %}

          {% if value[:nilable] %}
            {% if value[:has_default].nil? %}
              @{{name}} = %var{name}
            {% else %}
              @{{name}} = %found{name} ? %var{name} : {{value[:default]}}
            {% end %}
          {% elsif value[:has_default] %}
            if %found{name} && !%var{name}.nil?
              @{{name}} = %var{name}
            end
          {% else %}
            @{{name}} = %var{name}.as({{value[:type]}})
          {% end %}

          {% if value[:presence] %}
            @{{name}}_present = %found{name}
          {% end %}
        {% end %}
      {% end %}

      after_initialize
    end

    protected def after_initialize
    end

    # TODO implement location
    protected def on_unknown_xml_attribute(node, key)
    end

    def to_xml
      XML.build(version: "1.0") do |xml|
        {% begin %}
          {% options = @type.annotation(::XML::Serializable::Options) %}
          {% emit_nulls = options && options[:emit_nulls] %}

          {% properties = {} of Nil => Nil %}
          {% for ivar in @type.instance_vars %}
            {% ann = ivar.annotation(::XML::Element) %}
            {% unless ann && (ann[:ignore] || ann[:ignore_serialize]) %}
              {%
                properties[ivar.id] = {
                  type:             ivar.type,
                  key:              ((ann && ann[:key]) || ivar).id.stringify,
                  root:             ann && ann[:root],
                  converter:        ann && ann[:converter],
                  emit_null:        (ann && (ann[:emit_null] != nil) ? ann[:emit_null] : emit_nulls),
                  ignore_serialize: ann && ann[:ignore_serialize],
                }
              %}
            {% end %}
          {% end %}

          xml.element({{@type.name.stringify}}) do
            {% for name, value in properties %}
              _{{name}} = @{{name}}

              {% if value[:ignore_serialize] %}
                unless {{ value[:ignore_serialize] }}
              {% end %}

              {% unless value[:emit_null] %}
                unless _{{name}}.nil?
              {% end %}

              xml.element({{value[:key]}}) do
                {% if value[:converter] %}
                  if _{{name}}
                    {{ value[:converter] }}.to_xml(_{{name}}, xml)
                  else
                    nil.to_xml(xml)
                  end
                {% else %}
                  _{{name}}.to_xml(xml)
                {% end %}

                if _{{name}}
                else
                end
              end

              {% unless value[:emit_null] %}
                end
              {% end %}

              {% if value[:ignore_serialize] %}
                end
              {% end %}
            {% end %}
          end
        {% end %}
      end
    end

    module Strict
      protected def on_unknown_xml_attribute(node, key)
        raise ::XML::SerializableError.new("Unknown XML attribute: #{key}", self.class.to_s, nil, 0)
      end
    end

    module Unmapped
      # TODO: use alias other then XML::Any
      @[XML::Element(ignore: true)]
      property xml_unmapped = Hash(String, XML::Any).new

      protected def on_unknown_xml_attribute(node, name)
        xml_unmapped[name] = begin
          XML::Any.new(node.content)
        end
      end
    end

    # Tells this class to decode XML by using a field as a discriminator.
    #
    # - *field* must be the field name to use as a discriminator
    # - *mapping* must be a hash or named tuple where each key-value pair
    #   maps a discriminator value to a class to deserialize
    #
    # For example:
    #
    # ```
    # require "xml"
    #
    # abstract class Shape
    #   include XML::Serializable
    #
    #   use_xml_discriminator "type", {point: Point, circle: Circle}
    #
    #   property type : String
    # end
    #
    # class Point < Shape
    #   property x : Int32
    #   property y : Int32
    # end
    #
    # class Circle < Shape
    #   property x : Int32
    #   property y : Int32
    #   property radius : Int32
    # end
    #
    # Shape.from_xml(TODO: update) # => #<Point:0x10373ae20 @type="point", @x=1, @y=2>
    # Shape.from_xml(TODO: update) # => #<Circle:0x106a4cea0 @type="circle", @x=1, @y=2, @radius=3>
    # ```
    # macro use_xml_discriminator(field, mapping)
    #   {% unless mapping.is_a?(HashLiteral) || mapping.is_a?(NamedTupleLiteral) %}
    #     {% mapping.raise "mapping argument must be a HashLiteral or a NamedTupleLiteral, not #{mapping.class_name.id}" %}
    #   {% end %}

    #   def self.new(node : ::XML::Node)
    #     # location = pull.location TODO: add location

    #     discriminator_value = nil
    #     xml = ""

    #     begin
    #       if node.document?
    #         root = node.root
    #         if root.nil?
    #           raise ::XML::SerializableError.new("Missing XML root document", self.class.to_s, nil, 0)
    #         else
    #           children = root.children
    #         end
    #       else
    #         children = node.children
    #       end
    #     rescue exc : ::XML::Error
    #       raise ::XML::SerializableError.new(exc.message, self.class.to_s, nil, exc.line_number)
    #     end

    #     # Try to find the discriminator while also getting the raw
    #     # string value of the parsed XML, so then we can pass it
    #     # to the final type.
    #     # xml = XML.build_fragment do |builder|
    #       children.each do |child|
    #         if child.name == {{field.id.stringify}}
    #           # TODO: should be removed
    #           case child.content
    #           when "true"
    #             discriminator_value = true
    #           when "false"
    #             discriminator_value = false
    #           when .to_i?
    #             discriminator_value = child.content.to_i
    #           else
    #             discriminator_value = child.content
    #           end

    #           xml = XML.build { |b| b.element(child.name) { discriminator_value } }
    #           # builder.element(child.name) { builder.text discriminator_value.to_s }
    #         else
    #           # builder.element(child.name) { builder.text node.children.to_s }
    #         end
    #       end
    #     # end

    #     if discriminator_value.nil?
    #       raise ::XML::SerializableError.new("Missing XML discriminator field '{{field.id}}'", to_s, nil, 0)
    #     end

    #     case discriminator_value
    #     {% for key, value in mapping %}
    #       {% if mapping.is_a?(NamedTupleLiteral) %}
    #         when {{key.id.stringify}}
    #       {% else %}
    #         {% if key.is_a?(StringLiteral) %}
    #           when {{key}}
    #         {% elsif key.is_a?(NumberLiteral) || key.is_a?(BoolLiteral) %}
    #           when {{key.id}}
    #         {% elsif key.is_a?(Path) %}
    #           when {{key.resolve}}
    #         {% else %}
    #           {% key.raise "mapping keys must be one of StringLiteral, NumberLiteral, BoolLiteral, or Path, not #{key.class_name.id}" %}
    #         {% end %}
    #       {% end %}
    #       {{value.id}}.from_xml(xml)
    #     {% end %}
    #     else
    #       raise ::XML::SerializableError.new("Unknown '{{field.id}}' discriminator value: #{discriminator_value.inspect}", to_s, nil, 0)
    #     end
    #   end
    # end
  end

  class SerializableError < XML::Error
    getter klass : String
    getter attribute : String?

    def initialize(
      message : String?,
      @klass : String,
      @attribute : String?,
      line_number : Int32 = 0,
      column_number : Int32 = 0
    )
      message = String.build do |io|
        io << message
        io << "\n  parsing "
        io << klass
        if attribute = @attribute
          io << '#' << attribute
        end
      end
      super(message, line_number)
    end
  end
end
