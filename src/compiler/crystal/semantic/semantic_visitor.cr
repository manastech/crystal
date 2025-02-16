# Base visitor for semantic analysis. It traverses the whole
# ASTNode tree, keeping a `current_type` in context, which corresponds
# to the type being visited according to class/module/lib definitions.
abstract class Crystal::SemanticVisitor < Crystal::Visitor
  getter program : Program

  # At every point there's a current type.
  # In the beginning this is the `Program` (top-level), but when
  # a class definition is visited this changes to that type, and so on.
  property current_type : ModuleType

  property! scope : Type
  setter scope

  property vars : MetaVars

  @path_lookup : Type?
  @untyped_def : Def?
  @typed_def : Def?
  @block : Block?

  def initialize(@program, @vars = MetaVars.new)
    @current_type = @program
    @exp_nest = 0
    @in_lib = false
    @in_c_struct_or_union = false
    @in_is_a = false
  end

  # Transform require to its source code.
  # The source code can be a Nop if the file was already required.
  def visit(node : Require)
    if expanded = node.expanded
      expanded.accept self
      return false
    end

    if inside_exp?
      node.raise "can't require dynamically"
    end

    location = node.location
    filename = node.string
    relative_to = location.try &.original_filename

    # Remember that the program depends on this require
    @program.record_require(filename, relative_to)

    filenames = begin
      @program.find_in_path(filename, relative_to)
    rescue ex : CrystalPath::NotFoundError
      message = "can't find file '#{ex.filename}'"
      notes = [] of String

      if ex.filename.starts_with? '.'
        if relative_to
          message += " relative to '#{relative_to}'"
        end
      else
        notes << <<-NOTE
          If you're trying to require a shard:
          - Did you remember to run `shards install`?
          - Did you make sure you're running the compiler in the same directory as your shard.yml?
          NOTE
      end

      node.raise "#{message}\n\n#{notes.join("\n")}"
    end

    if filenames
      nodes = Array(ASTNode).new(filenames.size)

      @program.run_requires(node, filenames) do |filename|
        nodes << require_file(node, filename)
      end

      expanded = Expressions.from(nodes)
    else
      expanded = Nop.new
    end

    node.expanded = expanded
    node.bind_to(expanded)
    false
  end

  private def require_file(node : Require, filename : String)
    parser = @program.new_parser(File.read(filename))
    parser.filename = filename
    parser.wants_doc = @program.wants_doc?
    begin
      parsed_nodes = parser.parse
      parsed_nodes = @program.normalize(parsed_nodes, inside_exp: inside_exp?)
      # We must type the node immediately, in case a file requires another
      # *before* one of the files in `filenames`
      parsed_nodes.accept self
    rescue ex : CodeError
      node.raise "while requiring \"#{node.string}\"", ex
    rescue ex
      raise Error.new "while requiring \"#{node.string}\"", ex
    end

    FileNode.new(parsed_nodes, filename)
  end

  def visit(node : ClassDef)
    check_outside_exp node, "declare class"
    pushing_type(node.resolved_type) do
      node.hook_expansions.try &.each &.accept self
      node.body.accept self
    end
    node.set_type(@program.nil)
    false
  end

  def visit(node : ModuleDef)
    check_outside_exp node, "declare module"
    pushing_type(node.resolved_type) do
      node.body.accept self
    end
    node.set_type(@program.nil)
    false
  end

  def visit(node : AnnotationDef)
    check_outside_exp node, "declare annotation"
    node.set_type(@program.nil)
    false
  end

  def visit(node : EnumDef)
    check_outside_exp node, "declare enum"
    pushing_type(node.resolved_type) do
      node.members.each &.accept self
    end
    node.set_type(@program.nil)
    false
  end

  def visit(node : LibDef)
    check_outside_exp node, "declare lib"
    node.set_type(@program.nil)
    false
  end

  def visit(node : Include)
    check_outside_exp node, "include"
    node.hook_expansions.try &.each &.accept self
    node.set_type(@program.nil)
    false
  end

  def visit(node : Extend)
    check_outside_exp node, "extend"
    node.hook_expansions.try &.each &.accept self
    node.set_type(@program.nil)
    false
  end

  def visit(node : Alias)
    check_outside_exp node, "declare alias"
    node.set_type(@program.nil)
    false
  end

  def visit(node : Def)
    check_outside_exp node, "declare def"
    node.hook_expansions.try &.each &.accept self
    node.set_type(@program.nil)
    false
  end

  def visit(node : Macro)
    check_outside_exp node, "declare macro"
    node.set_type(@program.nil)
    false
  end

  def visit(node : Annotation)
    annotations = @annotations ||= [] of Annotation
    annotations << node
    false
  end

  def visit(node : Call)
    !expand_macro(node, raise_on_missing_const: false)
  end

  def visit(node : MacroExpression)
    expand_inline_macro node
    false
  end

  def visit(node : MacroIf)
    expand_inline_macro node
    false
  end

  def visit(node : MacroFor)
    expand_inline_macro node
    false
  end

  def visit(node : MacroVerbatim)
    expansion = MacroIf.new(BoolLiteral.new(true), node)
    expand_inline_macro expansion

    node.expanded = expansion
    node.bind_to expansion

    false
  end

  def visit(node : ExternalVar | Path | Generic | ProcNotation | Union | Metaclass | Self | TypeOf)
    false
  end

  def visit(node : ASTNode)
    true
  end

  def visit_any(node)
    @exp_nest += 1 if nesting_exp?(node)

    true
  end

  def end_visit_any(node)
    @exp_nest -= 1 if nesting_exp?(node)

    if @annotations
      case node
      when Expressions
        # Nothing, will be taken care in individual expressions
      when Annotation
        # Nothing
      when Nop
        # Nothing (might happen as a result of an evaluated macro if)
      when Call
        # Don't clear annotations if these were generated by a macro
        unless node.expanded
          @annotations = nil
        end
      when MacroExpression, MacroIf, MacroFor
        # Don't clear annotations if these were generated by a macro
      else
        @annotations = nil
      end
    end
  end

  # Returns free variables
  def free_vars : Hash(String, TypeVar)?
    nil
  end

  def nesting_exp?(node)
    case node
    when Expressions, LibDef, CStructOrUnionDef, ClassDef, ModuleDef, FunDef, Def, Macro,
         Alias, Include, Extend, EnumDef, VisibilityModifier, MacroFor, MacroIf, MacroExpression,
         FileNode, TypeDeclaration, Require, AnnotationDef
      false
    else
      true
    end
  end

  def lookup_type(node : ASTNode,
                  free_vars = nil,
                  find_root_generic_type_parameters = true)
    current_type.lookup_type(
      node,
      free_vars: free_vars,
      allow_typeof: false,
      find_root_generic_type_parameters: find_root_generic_type_parameters
    )
  end

  def check_outside_exp(node, op)
    node.raise "can't #{op} dynamically" if inside_exp?
  end

  def expand_macro(node, raise_on_missing_const = true, first_pass = false, accept = true)
    if expanded = node.expanded
      @exp_nest -= 1
      eval_macro(node) do
        expanded.accept self if accept
      end
      @exp_nest += 1
      return true
    end

    obj = node.obj
    case obj
    when Path, Generic
      base_type = @path_lookup || @scope || @current_type
      macro_scope =
        if obj.is_a?(Path)
          base_type.lookup_type_var?(obj, free_vars: free_vars, raise: raise_on_missing_const)
        else
          base_type.lookup_type?(obj, allow_typeof: false, free_vars: free_vars, raise: raise_on_missing_const, raise_typeof: false)
        end

      return false unless macro_scope.is_a?(Type)

      macro_scope = macro_scope.remove_alias

      the_macro = macro_scope.metaclass.lookup_macro(node.name, node.args, node.named_args)
      node.raise "private macro '#{node.name}' called for #{obj}" if the_macro.is_a?(Macro) && the_macro.visibility.private?
    when Nil
      return false if node.super? || node.previous_def?
      the_macro = node.lookup_macro
    else
      return false
    end

    return false unless the_macro.is_a?(Macro)

    # If we find a macro outside a def/block and this is not the first pass it means that the
    # macro was defined before we first found this call, so it's an error
    # (we must analyze the macro expansion in all passes)
    if !@typed_def && !@block && !first_pass
      node.raise "macro '#{node.name}' must be defined before this point but is defined later"
    end

    expansion_scope = (macro_scope || @scope || current_type)

    args, named_args = expand_macro_arguments(node, expansion_scope)

    @exp_nest -= 1
    generated_nodes = expand_macro(the_macro, node, visibility: node.visibility, accept: accept) do
      old_args, old_named_args = node.args, node.named_args
      node.args, node.named_args = args, named_args
      expanded_macro, macro_expansion_pragmas = @program.expand_macro the_macro, node, expansion_scope, expansion_scope, @untyped_def
      node.args, node.named_args = old_args, old_named_args
      {expanded_macro, macro_expansion_pragmas}
    end
    @exp_nest += 1

    node.expanded = generated_nodes
    node.expanded_macro = the_macro
    node.bind_to generated_nodes

    true
  end

  def expand_macro(the_macro, node, mode = nil, *, visibility : Visibility, accept = true, &)
    expanded_macro, macro_expansion_pragmas =
      eval_macro(node) do
        yield
      end

    mode ||= if @in_c_struct_or_union
               Parser::ParseMode::LibStructOrUnion
             elsif @in_lib
               Parser::ParseMode::Lib
             else
               Parser::ParseMode::Normal
             end

    # We could do Set.new(@vars.keys) but that creates an intermediate array
    local_vars = Set(String).new(initial_capacity: @vars.size)
    @vars.each_key { |key| local_vars << key }

    generated_nodes = @program.parse_macro_source(expanded_macro, macro_expansion_pragmas, the_macro, node, local_vars,
      current_def: @typed_def,
      inside_type: !current_type.is_a?(Program),
      inside_exp: @exp_nest > 0,
      mode: mode,
      visibility: visibility,
    )

    node.doc ||= annotations_doc @annotations

    if node_doc = node.doc
      generated_nodes.accept PropagateDocVisitor.new(node_doc)
    end

    generated_nodes.accept self if accept
    generated_nodes
  end

  class PropagateDocVisitor < Visitor
    @doc : String

    def initialize(@doc)
    end

    def visit(node : ClassDef | ModuleDef | EnumDef | Def | FunDef | Macro | AnnotationDef | Alias | Assign | Call)
      node.doc ||= @doc
      false
    end

    def visit(node : ASTNode)
      true
    end
  end

  def expand_macro_arguments(call, expansion_scope)
    # If any argument is a MacroExpression, solve it first and
    # replace Path with Const/TypeNode if it denotes such thing
    args = call.args
    named_args = call.named_args

    if args.any?(MacroExpression) || named_args.try &.any? &.value.is_a?(MacroExpression)
      @exp_nest -= 1
      args = args.map do |arg|
        expand_macro_argument(arg, expansion_scope)
      end
      named_args = named_args.try &.map do |named_arg|
        value = expand_macro_argument(named_arg.value, expansion_scope)
        NamedArgument.new(named_arg.name, value)
      end
      @exp_nest += 1
    end

    {args, named_args}
  end

  def expand_macro_argument(node, expansion_scope)
    if node.is_a?(MacroExpression)
      node.accept self
      expanded = node.expanded.not_nil!
      if expanded.is_a?(Path)
        expanded_type = expansion_scope.lookup_path(expanded)
        case expanded_type
        when Const
          expanded = expanded_type.value
        when Type
          expanded = TypeNode.new(expanded_type)
        end
      end
      expanded
    else
      node
    end
  end

  def expand_inline_macro(node, mode = nil, accept = true)
    if expanded = node.expanded
      eval_macro(node) do
        expanded.accept self if accept
      end
      return expanded
    end

    the_macro = Macro.new("macro_#{node.object_id}", [] of Arg, node).at(node)

    skip_macro_exception = nil

    generated_nodes = expand_macro(the_macro, node, mode: mode, visibility: :public, accept: accept) do
      begin
        @program.expand_macro node, (@scope || current_type), @path_lookup, free_vars, @untyped_def
      rescue ex : SkipMacroException
        skip_macro_exception = ex
        {ex.expanded_before_skip, ex.macro_expansion_pragmas}
      end
    end

    node.expanded = generated_nodes
    node.bind_to generated_nodes

    raise skip_macro_exception if skip_macro_exception

    generated_nodes
  end

  def eval_macro(node, &)
    yield
  rescue ex : TopLevelMacroRaiseException
    # If the node that caused a top level macro raise is a `Call`, it denotes it happened within the context of a macro.
    # In this case, we want the inner most exception to be the call of the macro itself so that it's the last frame in the trace.
    # This will make the actual `#raise` method call be the first frame.
    if node.is_a? Call
      ex.inner = Crystal::MacroRaiseException.for_node node, ex.message
    end

    # Otherwise, if the current node is _NOT_ a `Call`, it denotes a top level raise within a method.
    # In this case, we want the same behavior as if it were a `Call`, but do not want to set the inner exception here since that will be handled via `Call#bubbling_exception`.
    # So just re-raise the exception to keep the original location intact.
    raise ex
  rescue ex : MacroRaiseException
    # Raise another exception on this node, keeping the original as the inner exception.
    # This will retain the location of the node specific raise as the last frame, while also adding in this node into the trace.
    #
    # If the original exception does not have a location, it'll essentially be dropped and this node will take its place as the last frame.
    node.raise ex.message, ex, exception_type: Crystal::MacroRaiseException
  rescue ex : Crystal::CodeError
    node.raise "expanding macro", ex
  end

  def process_annotations(annotations, &)
    annotations.try &.each do |ann|
      annotation_type = lookup_annotation(ann)
      validate_annotation(annotation_type, ann)
      yield annotation_type, ann
    end
  end

  def lookup_annotation(ann)
    # TODO: Since there's `Int::Primitive`, and now we'll have
    # `::Primitive`, but there's no way to specify ::Primitive
    # just yet in annotations, we temporarily hardcode
    # that `Primitive` inside annotations means the top
    # level primitive.
    # We also have the same problem with File::Flags, which
    # is an enum marked with Flags annotation.
    if ann.path.single?("Primitive")
      type = @program.primitive_annotation
    elsif ann.path.single?("Flags")
      type = @program.flags_annotation
    else
      type = lookup_type(ann.path)
    end

    unless type.is_a?(AnnotationType)
      ann.raise "#{ann.path} is not an annotation, it's a #{type.type_desc}"
    end

    type
  end

  def validate_annotation(annotation_type, ann)
    case annotation_type
    when @program.deprecated_annotation
      # Check whether a DeprecatedAnnotation can be built.
      # There is no need to store it, but enforcing
      # arguments makes sense here.
      DeprecatedAnnotation.from(ann)
    when @program.experimental_annotation
      # ditto DeprecatedAnnotation
      ExperimentalAnnotation.from(ann)
    end
  end

  private def annotations_doc(annotations)
    annotations.try(&.first?).try &.doc
  end

  def check_class_var_annotations
    thread_local = false
    process_annotations(@annotations) do |annotation_type, ann|
      if annotation_type == @program.thread_local_annotation
        thread_local = true
      else
        ann.raise "class variables can only be annotated with ThreadLocal"
      end
    end
    thread_local
  end

  def check_allowed_in_lib(node, type = node.type.instance_type)
    unless type.allowed_in_lib?
      msg = String.build do |msg|
        msg << "only primitive types, pointers, structs, unions, enums and tuples are allowed in lib declarations, not #{type}"
        msg << " (did you mean LibC::Int?)" if type == @program.int
        msg << " (did you mean LibC::Float?)" if type == @program.float
      end
      node.raise msg
    end

    type
  end

  def check_declare_var_type(node, declared_type, variable_kind)
    type = declared_type.instance_type

    if type.is_a?(GenericClassType)
      node.raise "can't declare variable of generic non-instantiated type #{type}"
    end

    Crystal.check_type_can_be_stored(node, type, "can't use #{type} as the type of #{variable_kind}")

    declared_type
  end

  def class_var_owner(node)
    scope = (@scope || current_type).class_var_owner

    if scope.is_a?(Program)
      node.raise "can't use class variables at the top level"
    end

    scope.as(ClassVarContainer)
  end

  def interpret_enum_value(node : ASTNode, target_type : IntegerType? = nil)
    MathInterpreter
      .new(current_type, self, target_type)
      .interpret(node)
  end

  def inside_exp?
    @exp_nest > 0
  end

  def pushing_type(type : ModuleType, &)
    old_type = @current_type
    @current_type = type
    read_annotations
    yield
    @current_type = old_type
  end

  # Returns the current annotations and clears them for subsequent readers.
  def read_annotations
    annotations = @annotations
    @annotations = nil
    annotations
  end
end
