require "./item"

class Crystal::Doc::Type
  include Item

  PSEUDO_CLASS_PREFIX = "CRYSTAL_PSEUDO__"
  PSEUDO_CLASS_NOTE   = <<-DOC

    NOTE: This is a pseudo-class provided directly by the Crystal compiler.
    It cannot be reopened nor overridden.
    DOC

  getter type : Crystal::Type

  def initialize(@generator : Generator, type : Crystal::Type)
    @type = type.devirtualize
  end

  def kind
    case @type
    when Const
      "const"
    when .extern_union?
      "union"
    when .struct?
      "struct"
    when .class?, .metaclass?
      "class"
    when .module?
      "module"
    when AliasType
      "alias"
    when EnumType
      "enum"
    when NoReturnType, VoidType
      "struct"
    when AnnotationType
      "annotation"
    when LibType
      "lib"
    when TypeDefType
      "type"
    else
      raise "Unhandled type in `kind`: #{@type}"
    end
  end

  def name
    case type = @type
    when Program
      "Top Level Namespace"
    when NamedType
      if @generator.project_info.crystal_stdlib?
        type.name.lchop(PSEUDO_CLASS_PREFIX)
      else
        type.name
      end
    when NoReturnType
      "NoReturn"
    when VoidType
      "Void"
    when Const
      type.name
    when GenericInstanceType
      type.generic_type.name
    when TypeParameter
      type.name
    when TypeSplat
      "*#{type.splatted_type}"
    else
      raise "Unhandled type in `name`: #{@type}"
    end
  end

  def type_vars
    case type = @type
    when GenericType
      type.type_vars
    else
      nil
    end
  end

  def abstract?
    @type.abstract?
  end

  def visibility
    @type.private? ? "private" : nil
  end

  def parents_of?(type)
    return false unless type

    while type = type.namespace
      return true if type.full_name == full_name
    end

    false
  end

  def current?(type)
    return false unless type

    parents_of?(type) || type.full_name == full_name
  end

  def superclass
    case type = @type
    when ClassType
      superclass = type.superclass unless ast_node?
    when GenericClassInstanceType
      superclass = type.superclass
    end

    if superclass
      @generator.type(superclass)
    else
      nil
    end
  end

  def ancestors
    ancestors = [] of self

    unless ast_node?
      @type.ancestors.each do |ancestor|
        doc_type = @generator.type(ancestor)
        ancestors << doc_type
        break if ancestor == @generator.program.object || doc_type.ast_node?
      end
    end

    ancestors
  end

  def ast_node?
    type = @type
    type.is_a?(ClassType) && type.full_name == "Crystal::Macros::ASTNode"
  end

  def locations
    @generator.relative_locations(@type)
  end

  def program?
    @type.is_a?(Program)
  end

  def program
    @generator.type(@type.program)
  end

  def enum?
    @type.is_a?(EnumType)
  end

  def alias?
    @type.is_a?(AliasType)
  end

  def const?
    @type.is_a?(Const)
  end

  def type_def?
    @type.is_a?(TypeDefType)
  end

  def lib?
    @type.is_a?(LibType)
  end

  def fun_def?
    @type.is_a?(FunDef)
  end

  def alias_definition
    alias_def = @type.as?(AliasType).try(&.aliased_type)
    alias_def
  end

  def formatted_alias_definition
    type_to_html alias_definition.as(Crystal::Type)
  end

  def type_definition
    @type.as?(TypeDefType).try(&.typedef)
  end

  def formatted_type_definition
    type_to_html type_definition.as(Crystal::Type)
  end

  @types : Array(Type)?

  def types
    @types ||= @generator.collect_subtypes(@type)
  end

  @instance_methods : Array(Method)?

  def instance_methods
    @instance_methods ||= begin
      case @type
      when Program
        [] of Method
      else
        defs = [] of Method
        @type.defs.try &.each do |def_name, defs_with_metadata|
          defs_with_metadata.each do |def_with_metadata|
            next if !def_with_metadata.def.visibility.public? && !showdoc?(def_with_metadata.def)
            next unless @generator.must_include? def_with_metadata.def

            defs << method(def_with_metadata.def, false)
          end
        end
        defs.sort_by! { |x| sort_order(x) }
      end
    end
  end

  @external_vars : Array(Method)?

  def external_vars
    @external_vars ||= begin
      case @type
      when LibType
        defs = [] of Method
        @type.defs.try &.each do |def_name, defs_with_metadata|
          defs_with_metadata.each do |def_with_metadata|
            next unless (ext = def_with_metadata.def).is_a?(External)
            next if !ext.external_var? || ext.name.ends_with?("=")
            next unless @generator.must_include? ext

            defs << method(ext, false)
          end
        end
        defs.sort_by! { |x| sort_order(x) }
      else
        [] of Method
      end
    end
  end

  @functions : Array(Method)?

  def functions
    @functions ||= begin
      case @type
      when LibType
        defs = [] of Method
        @type.defs.try &.each do |def_name, defs_with_metadata|
          defs_with_metadata.each do |def_with_metadata|
            next unless (ext = def_with_metadata.def).is_a?(External)
            next if ext.external_var?
            next unless @generator.must_include? def_with_metadata.def

            defs << method(def_with_metadata.def, false)
          end
        end
        defs.sort_by! { |x| sort_order(x) }
      else
        [] of Method
      end
    end
  end

  private def showdoc?(adef)
    @generator.showdoc?(adef.doc.try &.strip)
  end

  private def sort_order(item)
    # Sort operators first, then alphanumeric (case-insensitive).
    {item.name[0].alphanumeric? ? 1 : 0, item.name.downcase}
  end

  @class_methods : Array(Method)?

  def all_class_methods
    @class_methods ||= begin
      class_methods = [] of Method
      @type.metaclass.defs.try &.each_value do |defs_with_metadata|
        defs_with_metadata.each do |def_with_metadata|
          a_def = def_with_metadata.def
          next if !def_with_metadata.def.visibility.public? && !showdoc?(def_with_metadata.def)

          body = a_def.body

          # Skip auto-generated allocate method
          next if body.is_a?(Crystal::Primitive) && body.name == "allocate"

          if @generator.must_include? a_def
            class_methods << method(a_def, true)
          end
        end
      end
      class_methods.sort_by! { |x| sort_order(x) }
    end
  end

  def class_methods
    all_class_methods - constructors
  end

  def constructors
    all_class_methods.select &.constructor?
  end

  @macros : Array(Macro)?

  def macros
    @macros ||= begin
      macros = [] of Macro
      @type.metaclass.macros.try &.each_value do |the_macros|
        the_macros.each do |a_macro|
          next if !a_macro.visibility.public? && !showdoc?(a_macro)

          if @generator.must_include? a_macro
            macros << self.macro(a_macro)
          end
        end
      end
      macros.sort_by! { |x| sort_order(x) }
    end
  end

  @constants : Array(Constant)?

  def constants
    @constants ||= @generator.collect_constants(self)
  end

  @included_modules : Array(Type)?

  def included_modules
    @included_modules ||= begin
      included_modules = [] of Type
      @type.parents.try &.each do |parent|
        if parent.module?
          included_modules << @generator.type(parent)
        end
      end
      included_modules.sort_by! &.full_name.downcase
    end
  end

  @extended_modules : Array(Type)?

  def extended_modules
    @extended_modules ||= begin
      extended_modules = [] of Type
      @type.metaclass.parents.try &.each do |parent|
        if parent.module?
          extended_modules << @generator.type(parent)
        end
      end
      extended_modules.sort_by! &.full_name.downcase
    end
  end

  @subclasses : Array(Type)?

  def subclasses
    @subclasses ||= begin
      case type = @type
      when .metaclass?
        [] of Type
      when ClassType
        subclasses = [] of Type
        type.subclasses.each do |subclass|
          case subclass
          when GenericClassInstanceType
            next
          when NonGenericClassType
            next if subclass.extern?
          end

          next unless @generator.must_include?(subclass)

          subclasses << @generator.type(subclass)
        end
        subclasses.sort_by! &.full_name.downcase
      else
        [] of Type
      end
    end
  end

  @including_types : Array(Type)?

  def including_types
    @including_types ||= begin
      case type = @type
      when NonGenericModuleType
        gather_including_types type
      when GenericModuleType
        gather_including_types type
      else
        [] of Type
      end
    end
  end

  private def gather_including_types(type)
    including_types = [] of Type
    type.raw_including_types.try &.each do |subtype|
      if @generator.must_include? subtype
        including_types << @generator.type(subtype)
      end
    end
    including_types.uniq!.sort_by! &.full_name.downcase
  end

  def namespace
    namespace = type.namespace
    if namespace.is_a?(Program)
      nil
    else
      @generator.type(namespace)
    end
  end

  def full_name
    String.build { |io| full_name(io) }
  end

  def full_name(io)
    full_name_without_type_vars(io)
    append_type_vars io
  end

  def full_name_without_type_vars
    String.build { |io| full_name_without_type_vars(io) }
  end

  def full_name_without_type_vars(io)
    if namespace = self.namespace
      namespace.full_name_without_type_vars(io)
      io << "::"
    end
    io << name
  end

  def path
    if program?
      "toplevel.html"
    elsif namespace = self.namespace
      "#{namespace.dir}/#{name}.html"
    else
      "#{name}.html"
    end
  end

  def path_from(type)
    if type
      type.path_to(self)
    else
      path
    end
  end

  def path_to(filename : String)
    "#{"../" * nesting}#{filename}"
  end

  def path_to(type : Type)
    if type.const?
      namespace = type.namespace || @generator.program_type
      "#{path_to(namespace)}##{type.name}"
    else
      path_to(type.path)
    end
  end

  def link_from(type : Type)
    type.type_to_html self
  end

  def dir
    if namespace = self.namespace
      "#{namespace.dir}/#{name}"
    else
      name.to_s
    end
  end

  def nesting
    if namespace = self.namespace
      1 + namespace.nesting
    else
      0
    end
  end

  def doc
    if (t = type).is_a?(NamedType) && t.name.starts_with?(PSEUDO_CLASS_PREFIX)
      "#{@type.doc}#{PSEUDO_CLASS_NOTE}"
    else
      @type.doc
    end
  end

  def lookup_path(path_or_names : Path | Array(String))
    match = @type.lookup_path(path_or_names)
    return unless match.is_a?(Crystal::Type)

    @generator.type(match)
  end

  def lookup_path(full_path : String)
    global = full_path.starts_with?("::")
    full_path = full_path[2..-1] if global
    path = Path.new(full_path.split("::"), global: global)
    lookup_path(path)
  end

  def lookup_method(name)
    lookup_in_methods instance_methods, name
  end

  def lookup_method(name, args_size)
    lookup_in_methods instance_methods, name, args_size
  end

  def lookup_class_method(name)
    lookup_in_methods all_class_methods, name
  end

  def lookup_class_method(name, args_size)
    lookup_in_methods all_class_methods, name, args_size
  end

  def lookup_macro(name)
    lookup_in_methods macros, name
  end

  def lookup_macro(name, args_size)
    lookup_in_methods macros, name, args_size
  end

  private def lookup_in_methods(methods, name)
    methods.find { |method| method.name == name }
  end

  private def lookup_in_methods(methods, name, args_size)
    if args_size
      methods.find { |method| method.name == name && method.args.size == args_size }
    else
      methods = methods.select { |method| method.name == name }
      methods.find(&.args.empty?) || methods.first?
    end
  end

  def method(a_def, class_method)
    @generator.method(self, a_def, class_method)
  end

  def macro(a_macro)
    @generator.macro(self, a_macro)
  end

  def to_s(io : IO) : Nil
    io << name
    append_type_vars io
  end

  private def append_type_vars(io : IO) : Nil
    type = @type
    if type_vars = type_vars()
      io << '('
      io << "**" if type.is_a?(GenericType) && type.double_variadic?
      type_vars.each_with_index do |type_var, i|
        io << ", " if i > 0
        io << '*' if type.is_a?(GenericType) && type.splat_index == i
        io << type_var
      end
      io << ')'
    end
  end

  def node_to_html(node)
    String.build { |io| node_to_html node, io }
  end

  def node_to_html(node : Path, io, html : HTMLOption = :all)
    match = lookup_path(node)
    if match
      # If the path is global, search a local path and
      # see if there's a different match. If not, we can safely
      # remove the `::` as a prefix (harder to read)
      remove_colons = false
      if node.global?
        node.global = false
        remove_colons = lookup_path(node) == match
        node.global = true unless remove_colons
      end

      type_to_html match, io, node.to_s, html: html
      node.global = true if remove_colons
    else
      io << node
    end
  end

  def node_to_html(node : Generic, io, html : HTMLOption = :all)
    node_to_html node.name, io, html: html
    io << '('
    node.type_vars.join(io, ", ") do |type_var|
      node_to_html type_var, io, html: html
    end
    if (named_args = node.named_args) && !named_args.empty?
      io << ", " unless node.type_vars.empty?
      named_args.join(io, ", ") do |entry|
        Symbol.quote_for_named_argument(io, entry.name)
        io << ": "
        node_to_html entry.value, io, html: html
      end
    end
    io << ')'
  end

  def node_to_html(node : ProcNotation, io, html : HTMLOption = :all)
    if inputs = node.inputs
      inputs.join(io, ", ") do |input|
        node_to_html input, io, html: html
      end
    end
    io << " -> "
    if output = node.output
      node_to_html output, io, html: html
    end
  end

  def node_to_html(node : Union, io, html : HTMLOption = :all)
    # See if it's a nilable type
    if node.types.size == 2
      # See if first type is Nil
      if nil_type?(node.types[0])
        return nilable_type_to_html node.types[1], io, html: html
      elsif nil_type?(node.types[1])
        return nilable_type_to_html node.types[0], io, html: html
      end
    end

    node.types.join(io, " | ") do |elem|
      node_to_html elem, io, html: html
    end
  end

  private def nilable_type_to_html(node : ASTNode, io, html)
    node_to_html node, io, html: html
    io << '?'
  end

  private def nilable_type_to_html(type : Crystal::Type, io, text, html)
    type_to_html(type, io, text, html: html)
    io << '?'
  end

  def nil_type?(node : ASTNode)
    return false unless node.is_a?(Path)

    match = lookup_path(node)
    !!match.try &.type == @generator.program.nil_type
  end

  def node_to_html(node, io, html : HTMLOption = :all)
    if html.highlight?
      io << SyntaxHighlighter::HTML.highlight!(node.to_s)
    else
      io << node
    end
  end

  def node_to_html(node : Underscore, io, html : HTMLOption = :all)
    io << '_'
  end

  def type_to_html(type)
    type = type.type if type.is_a?(Type)
    String.build { |io| type_to_html(type, io) }
  end

  def type_to_html(type : Crystal::UnionType, io, text = nil, html : HTMLOption = :all)
    has_type_splat = type.union_types.any?(TypeSplat)

    if !has_type_splat && type.union_types.size == 2
      if type.union_types[0].nil_type?
        return nilable_type_to_html(type.union_types[1], io, text, html)
      elsif type.union_types[1].nil_type?
        return nilable_type_to_html(type.union_types[0], io, text, html)
      end
    end

    if has_type_splat
      io << "Union("
      separator = ", "
    else
      separator = " | "
    end

    type.union_types.join(io, separator) do |union_type|
      type_to_html union_type, io, text, html: html
    end

    io << ')' if has_type_splat
  end

  def type_to_html(type : Crystal::ProcInstanceType, io, text = nil, html : HTMLOption = :all)
    type.arg_types.join(io, ", ") do |arg_type|
      type_to_html arg_type, io, html: html
    end
    io << " -> "
    return_type = type.return_type
    type_to_html return_type, io, html: html unless return_type.void?
  end

  def type_to_html(type : Crystal::TupleInstanceType, io, text = nil, html : HTMLOption = :all)
    io << '{'
    type.tuple_types.join(io, ", ") do |tuple_type|
      type_to_html tuple_type, io, html: html
    end
    io << '}'
  end

  def type_to_html(type : Crystal::NamedTupleInstanceType, io, text = nil, html : HTMLOption = :all)
    io << '{'
    type.entries.join(io, ", ") do |entry|
      Symbol.quote_for_named_argument(io, entry.name)
      io << ": "
      type_to_html entry.type, io, html: html
    end
    io << '}'
  end

  def type_to_html(type : Crystal::GenericInstanceType, io, text = nil, html : HTMLOption = :all)
    has_link_in_type_vars = type.type_vars.any? { |(name, type_var)| type_has_link? type_var.as?(Var).try(&.type) || type_var }
    generic_type = @generator.type(type.generic_type)
    must_be_included = generic_type.must_be_included?

    if must_be_included && html.links?
      io << %(<a href=")
      io << generic_type.path_from(self)
      io << %(">)
    end

    if text
      io << text
    else
      generic_type.full_name_without_type_vars(io)
    end

    io << "</a>" if must_be_included && html.links? && has_link_in_type_vars

    io << '('
    type.type_vars.values.join(io, ", ") do |type_var|
      case type_var
      when Var
        type_to_html type_var.type, io, html: html
      else
        type_to_html type_var, io, html: html
      end
    end
    io << ')'

    io << "</a>" if must_be_included && html.links? && !has_link_in_type_vars
  end

  def type_to_html(type : Crystal::VirtualType, io, text = nil, html : HTMLOption = :all)
    type_to_html type.base_type, io, text, html: html
  end

  def type_to_html(type : Crystal::Type, io, text = nil, html : HTMLOption = :all)
    type = @generator.type(type)
    if type.must_be_included?
      if html.links?
        io << %(<a href=")
        io << type.path_from(self)
        io << %(">)
      end
      if text
        io << text
      else
        type.full_name(io)
      end
      if html.links?
        io << "</a>"
      end
    else
      if text
        io << text
      else
        type.full_name(io)
      end
    end
  end

  def type_to_html(type : Type, io, text = nil, html : HTMLOption = :all)
    type_to_html type.type, io, text, html: html
  end

  def type_to_html(type : ASTNode, io, text = nil, html : HTMLOption = :all)
    type.to_s io
  end

  def type_has_link?(type : Crystal::UnionType)
    type.union_types.any? { |type| type_has_link? type }
  end

  def type_has_link?(type : Crystal::ProcInstanceType)
    type.arg_types.any? { |type| type_has_link? type } ||
      type_has_link? type.return_type
  end

  def type_has_link?(type : Crystal::TupleInstanceType)
    type.tuple_types.any? { |type| type_has_link? type }
  end

  def type_has_link?(type : Crystal::NamedTupleInstanceType)
    type.entries.any? { |entry| type_has_link? entry.type }
  end

  def type_has_link?(type : Crystal::GenericInstanceType)
    @generator.type(type.generic_type).must_be_included? ||
      type.type_vars.any? { |(name, type_var)| type_has_link? type_var.as?(Var).try(&.type) || type_var }
  end

  def type_has_link?(type : Crystal::Type)
    @generator.type(type.devirtualize).must_be_included?
  end

  def type_has_link?(type : Crystal::TypeParameter | ASTNode)
    false
  end

  def must_be_included?
    @generator.must_include? self
  end

  def superclass_hierarchy
    hierarchy = [self]
    superclass = self.superclass
    while superclass
      hierarchy << superclass
      superclass = superclass.superclass
    end
    String.build do |io|
      io << %(<ul class="superclass-hierarchy">)
      hierarchy.each do |type|
        io << %(<li class="superclass">)
        type_to_html type, io
        io << "</li>"
      end
      io << "</ul>"
    end
  end

  def html_id
    "#{@generator.project_info.name}/" + (
      if program?
        "toplevel"
      elsif namespace = self.namespace
        "#{namespace.dir}/#{name}"
      else
        "#{name}"
      end
    )
  end

  delegate to_s, inspect, to: @type

  def to_json(builder : JSON::Builder)
    builder.object do
      builder.field "html_id", html_id
      builder.field "path", path
      builder.field "kind", kind
      builder.field "full_name", full_name
      builder.field "name", name
      builder.field "abstract", abstract?
      builder.field "superclass" { superclass.try &.to_json_simple(builder) } unless superclass.nil?
      unless ancestors.empty?
        builder.field "ancestors" do
          builder.array do
            ancestors.each &.to_json_simple(builder)
          end
        end
      end
      builder.field "locations", locations
      builder.field "repository_name", @generator.project_info.name
      builder.field "program", program?
      builder.field "enum", enum?
      builder.field "alias", alias?
      builder.field "aliased", alias_definition.to_s if alias?
      builder.field "aliased_html", formatted_alias_definition if alias?
      builder.field "const", const?
      builder.field "constants", constants unless constants.empty?
      unless included_modules.empty?
        builder.field "included_modules" do
          builder.array do
            included_modules.each &.to_json_simple(builder)
          end
        end
      end
      unless extended_modules.empty?
        builder.field "extended_modules" do
          builder.array do
            extended_modules.each &.to_json_simple(builder)
          end
        end
      end
      unless subclasses.empty?
        builder.field "subclasses" do
          builder.array do
            subclasses.each &.to_json_simple(builder)
          end
        end
      end
      unless including_types.empty?
        builder.field "including_types" do
          builder.array do
            including_types.each &.to_json_simple(builder)
          end
        end
      end
      builder.field "namespace" { namespace.try &.to_json_simple(builder) } unless namespace.nil?
      builder.field "doc", doc unless doc.nil?
      builder.field "summary", formatted_summary unless formatted_summary.nil?
      builder.field "class_methods", class_methods unless class_methods.empty?
      builder.field "constructors", constructors unless constructors.empty?
      builder.field "instance_methods", instance_methods unless instance_methods.empty?
      builder.field "macros", macros unless macros.empty?
      builder.field "types", types unless types.empty?
    end
  end

  def to_json_simple(builder : JSON::Builder)
    builder.object do
      builder.field "html_id", html_id
      builder.field "kind", kind
      builder.field "full_name", full_name
      builder.field "name", name
    end
  end

  def annotations(annotation_type)
    @type.annotations(annotation_type)
  end
end
