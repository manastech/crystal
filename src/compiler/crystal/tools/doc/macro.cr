require "html"
require "uri"
require "./item"

class Crystal::Doc::Macro
  include Item

  getter type : Type
  getter macro : Crystal::Macro

  def initialize(@generator : Generator, @type : Type, @macro : Crystal::Macro)
  end

  def name
    @macro.name
  end

  def args
    @macro.args
  end

  def doc
    @macro.doc
  end

  def doc_copied_from
    nil
  end

  def location
    @generator.relative_location(@macro)
  end

  def id
    String.build do |io|
      io << to_s.delete(' ')
      io << "-macro"
    end
  end

  def html_id
    HTML.escape(id)
  end

  def anchor
    '#' + URI.encode_path(id)
  end

  def prefix
    ""
  end

  def abstract?
    false
  end

  def visibility
    @type.visibility
  end

  def real_name
  end

  def kind
    "macro "
  end

  def to_s(io : IO) : Nil
    io << name
    args_to_s io
  end

  def args_to_s
    String.build { |io| args_to_s io }
  end

  def args_to_s(io : IO) : Nil
    args_to_html(io, html: :none)
  end

  def args_to_html(html : HTMLOption = :all)
    String.build { |io| args_to_html io, html }
  end

  def args_to_html(io : IO, html : HTMLOption = :all) : Nil
    return unless has_args?

    printed = false
    io << '('

    @macro.args.each_with_index do |arg, i|
      io << ", " if printed
      io << '*' if @macro.splat_index == i
      arg_to_html arg, io, html: html
      printed = true
    end

    if double_splat = @macro.double_splat
      io << ", " if printed
      io << "**"
      arg_to_html double_splat, io, html: html
      printed = true
    end

    if block_arg = @macro.block_arg
      io << ", " if printed
      io << '&'
      arg_to_html block_arg, io, html: html
    end

    io << ')'
  end

  def arg_to_html(arg : Arg, io, html : HTMLOption = :all)
    if arg.external_name != arg.name
      if name = arg.external_name.presence
        name = Symbol.quote_for_named_argument(name)
        if html.none?
          io << name
        else
          HTML.escape name, io
        end
      else
        io << "_"
      end
      io << ' '
    end

    io << arg.name

    # Macro arg cannot not have a restriction.

    if default_value = arg.default_value
      io << " = "
      if html.highlight?
        io << SyntaxHighlighter::HTML.highlight!(default_value.to_s)
      else
        io << default_value
      end
    end
  end

  def has_args?
    !@macro.args.empty? || @macro.double_splat || @macro.block_arg
  end

  def must_be_included?
    @generator.must_include? @macro
  end

  def to_json(builder : JSON::Builder)
    builder.object do
      builder.field "html_id", id
      builder.field "name", name
      builder.field "doc", doc unless doc.nil?
      builder.field "summary", formatted_summary unless formatted_summary.nil?
      builder.field "abstract", abstract?
      builder.field "args", args unless args.empty?
      builder.field "args_string", args_to_s unless args.empty?
      builder.field "args_html", args_to_html unless args.empty?
      builder.field "location", location unless location.nil?
      builder.field "def", self.macro
    end
  end

  def annotations(annotation_type)
    @macro.annotations(annotation_type)
  end
end
