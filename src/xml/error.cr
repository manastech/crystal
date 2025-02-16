require "./libxml2"

class XML::Error < Exception
  getter line_number : Int32 = 0
  getter column_number : Int32 = 0

  def self.new(error : LibXML::Error*)
    new String.new(error.value.message).chomp, error.value.line
  end

  def initialize(message, @line_number = 0, @column_number = 0, cause = nil)
    super(message, cause)
  end

  @[Deprecated("This class accessor is deprecated. XML errors are accessible directly in the respective context via `XML::Reader#errors` and `XML::Node#errors`.")]
  def self.errors : Array(XML::Error)?
    {% raise "`XML::Error.errors` was removed because it leaks memory when it's not used. XML errors are accessible directly in the respective context via `XML::Reader#errors` and `XML::Node#errors`.\nSee https://github.com/crystal-lang/crystal/issues/14934 for details. " %}
  end

  def self.collect(errors, &)
    LibXML.xmlSetStructuredErrorFunc Box.box(errors), ->(ctx, error) {
      Box(Array(XML::Error)).unbox(ctx) << XML::Error.new(error)
    }
    begin
      yield
    ensure
      LibXML.xmlSetStructuredErrorFunc nil, nil
    end
  end

  def self.collect_generic(errors, &)
    LibXML.xmlSetGenericErrorFunc Box.box(errors), ->(ctx, fmt) {
      # TODO: use va_start and va_end to
      message = String.new(fmt).chomp
      error = XML::Error.new(message, 0)

      {% if flag?(:arm) || flag?(:aarch64) %}
        # libxml2 is likely missing ARM unwind tables (.ARM.extab and .ARM.exidx
        # sections) which prevent raising from a libxml2 context.
        Box(Array(XML::Error)).unbox(ctx) << error
      {% else %}
        raise error
      {% end %}
    }

    begin
      collect(errors) do
        yield
      end
    ensure
      LibXML.xmlSetGenericErrorFunc nil, nil
    end
  end
end
