require "html"
require "uri"
require "./item"

class Crystal::Doc::Method
  include Item

  PSEUDO_METHOD_PREFIX = "__crystal_pseudo_"
  PSEUDO_METHOD_NOTE   = <<-DOC

    NOTE: This is a pseudo-method provided directly by the Crystal compiler.
    It cannot be redefined nor overridden.
    DOC

  getter type : Type
  getter def : Def

  def initialize(@generator : Generator, @type : Type, @def : Def, @class_method : Bool)
  end

  def name
    name = @def.name
    if @generator.project_info.crystal_stdlib?
      name.lchop(PSEUDO_METHOD_PREFIX)
    else
      name
    end
  end

  def args
    @def.args
  end

  private record DocInfo, doc : String?, copied_from : Type?

  private getter(doc_info : DocInfo) do
    compute_doc_info
  end

  # Returns this method's docs ready to be shown (before formatting)
  # in the UI. This includes copying docs from previous def or
  # ancestors and replacing `:inherit:` with the ancestor docs.
  # This docs not include the "Description copied from ..." banner
  # in case it's needed.
  def doc
    doc_info.doc.try &.strip.lchop(":showdoc:").strip
  end

  # Returns the type this method's docs are copied from, but
  # only if this method has no docs at all. In this case
  # the docs will be copied from this type and a
  # "Description copied from ..." will be added before the docs.
  def doc_copied_from : Type?
    doc_info.copied_from
  end

  private def compute_doc_info : DocInfo?
    def_doc = @def.doc
    if def_doc
      ancestor_doc_info = nil
      # TODO: warn about `:inherit:` not finding an ancestor
      inherit_def_doc = def_doc.gsub(/^[ \t]*:inherit:[ \t]*$/m) do
        ancestor_doc_info ||= self.ancestor_doc_info
        ancestor_doc_info.try(&.doc) || break
      end

      # inherit_def_doc is nil when breaking from the gsub block which means
      # no ancestor doc info was found
      if inherit_def_doc && !inherit_def_doc.same?(def_doc)
        return DocInfo.new(inherit_def_doc, nil)
      end

      if @def.name.starts_with?(PSEUDO_METHOD_PREFIX)
        def_doc += PSEUDO_METHOD_NOTE
      end

      return DocInfo.new(def_doc, nil)
    end

    previous_docs = previous_def_docs(@def)
    if previous_docs
      return DocInfo.new(def_doc, nil)
    end

    ancestor_info = self.ancestor_doc_info
    return ancestor_info if ancestor_info

    DocInfo.new(nil, nil)
  end

  private def previous_def_docs(a_def)
    while previous = a_def.previous
      a_def = previous.def
      doc = a_def.doc
      return doc if doc
    end

    nil
  end

  private def ancestor_doc_info
    def_with_metadata = DefWithMetadata.new(@def)

    # Check ancestors
    type.type.ancestors.each do |ancestor|
      other_defs_with_metadata = ancestor.defs.try &.[@def.name]?
      other_defs_with_metadata.try &.each do |other_def_with_metadata|
        # If we find an ancestor method with the same signature
        if def_with_metadata.compare_strictness(other_def_with_metadata, self_owner: type.type, other_owner: ancestor) == 0
          other_def = other_def_with_metadata.def
          doc = other_def.doc
          return DocInfo.new(doc, @generator.type(ancestor)) if doc

          doc = previous_def_docs(other_def)
          return DocInfo.new(doc, nil) if doc
        end
      end
    end

    nil
  end

  def location
    @generator.relative_location(@def)
  end

  def external_var?
    !!@def.as?(External).try(&.external_var?)
  end

  def prefix
    case
    when @type.program?
      ""
    when external_var?
      "$"
    when @class_method, @type.lib?
      "."
    else
      "#"
    end
  end

  def visibility
    case @def.visibility
    in .public?
    in .protected?
      "protected"
    in .private?
      "private"
    end
  end

  def real_name
    a_def = @def.as?(External)
    if a_def && (real_name = (a_def.real_name)) && (real_name != a_def.name)
      " = #{real_name}"
    end
  end

  def constructor?
    return false unless @class_method
    return true if name == "new"

    return_type = self.return_type
    if return_type.is_a?(Union)
      if return_type.types.size == 2
        if @type.nil_type?(return_type.types[0])
          return_type = return_type.types[1]
        elsif @type.nil_type?(return_type.types[1])
          return_type = return_type.types[0]
        end
      end
    end
    return_type.to_s.in?(type.name, "self")
  end

  def abstract?
    @def.abstract?
  end

  def return_type
    return_type = @def.return_type

    # If the def's body is a single instance variable, we include
    # a return type since instance vars must have a fixed/guessed type,
    # so docs will be better and easier to navigate.
    if !return_type && (body = @def.body).is_a?(InstanceVar)
      owner = type.type
      if owner.is_a?(NonGenericClassType)
        ivar = owner.lookup_instance_var?(body.name)
        return_type = ivar.try &.type?
      end
    end
    return_type
  end

  def kind
    case
    when external_var?
      "$"
    when @type.lib?
      "fun "
    when @type.program?
      "def "
    when @class_method
      "def self."
    else
      "def "
    end
  end

  def id
    String.build do |io|
      io << to_s.delete(' ')
      if external_var?
        io << "-external-var"
      elsif @type.lib?
        io << "-function"
      elsif @class_method
        io << "-class-method"
      else
        io << "-instance-method"
      end
    end
  end

  def html_id
    HTML.escape(id)
  end

  def anchor
    "#" + URI.encode_path(id)
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
    return_type = self.return_type

    return unless has_args? || return_type

    if has_args?
      io << '('
      printed = false
      @def.args.each_with_index do |arg, i|
        io << ", " if printed
        io << '*' if @def.splat_index == i
        arg_to_html arg, io, html: html
        printed = true
      end
      if double_splat = @def.double_splat
        io << ", " if printed
        io << "**"
        io << double_splat
        printed = true
      end
      if block_arg = @def.block_arg
        io << ", " if printed
        io << '&'
        arg_to_html block_arg, io, html: html
      elsif @def.block_arity
        io << ", " if printed
        io << '&'
      end
      io << ')'
    end

    case return_type
    when Nil
      # Nothing to do
    when ASTNode
      io << " : "
      node_to_html return_type, io, html: html
    when Crystal::Type
      io << " : "
      @type.type_to_html return_type, io, html: html
    end

    if free_vars = @def.free_vars
      io << " forall "
      free_vars.join(io, ", ")
    end

    io
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

    if restriction = arg.restriction
      io << " : "
      node_to_html restriction, io, html: html
    elsif type = arg.type?
      io << " : "
      @type.type_to_html type, io, html: html
    end

    if default_value = arg.default_value
      io << " = "
      if html.highlight?
        io << SyntaxHighlighter::HTML.highlight!(default_value.to_s)
      else
        io << default_value
      end
    end
  end

  def node_to_html(node, io, html : HTMLOption = :all)
    @type.node_to_html node, io, html: html
  end

  def must_be_included?
    @generator.must_include? @def
  end

  def has_args?
    !@def.args.empty? || @def.double_splat || @def.block_arg || @def.block_arity
  end

  def to_json(builder : JSON::Builder)
    builder.object do
      builder.field "html_id", id
      builder.field "name", name
      builder.field "real_name", real_name if real_name
      builder.field "doc", doc unless doc.nil?
      builder.field "summary", formatted_summary unless formatted_summary.nil?
      builder.field "abstract", abstract?
      builder.field "visibility", visibility if visibility
      builder.field "args", args unless args.empty?
      builder.field "args_string", args_to_s unless args.empty?
      builder.field "args_html", args_to_html unless args.empty?
      builder.field "location", location unless location.nil?
      builder.field @type.lib? ? "fun" : "def", self.def
      builder.field "external_var", external_var?
    end
  end

  def annotations(annotation_type)
    @def.annotations(annotation_type)
  end
end
