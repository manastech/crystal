require "./semantic_visitor"
require "./type_guess_visitor"

# In this pass we check type declarations like:
#
#     @x : Int32
#     @@x : Int32
#     $x : Int32
#
# In this way we declare their type before the "main" code.
#
# This allows to put "main" code before these declarations,
# so order matters less in the end.
#
# This visitor also processes the following:
#
# - C struct/union fields
# - fun declarations
# - alias declarations
#
# We do this now because in a previous pass, TopLevelVisitor
# declared all types so now we can search them and always find
# them, not needing any kind of forward referencing.
class Crystal::TypeDeclarationVisitor < Crystal::SemanticVisitor
  alias TypeDeclarationWithLocation = TypeDeclarationProcessor::TypeDeclarationWithLocation

  getter class_vars
  getter instance_vars

  def initialize(mod,
                 @instance_vars : Hash(Type, Hash(String, TypeDeclarationWithLocation)))
    super(mod)

    # The type of class variables. The last one wins.
    # This is type => variables.
    @class_vars = {} of ClassVarContainer => Hash(String, TypeDeclarationWithLocation)

    # A hash of all defined funs, so we can detect when
    # a fun is redefined with a different signature
    @externals = {} of String => External
  end

  def visit(node : Alias)
    node.resolved_type.process_value
    false
  end

  def visit(node : Include)
    if @in_c_struct_or_union
      include_c_struct(node)
    else
      super
    end
    false
  end

  def include_c_struct(node)
    type = current_type.as(NonGenericClassType)

    included_type = lookup_type(node.name)
    unless included_type.is_a?(NonGenericClassType) && included_type.extern? && !included_type.extern_union?
      node.name.raise "can only include C struct, not #{included_type.type_desc}"
    end

    included_type.instance_vars.each_value do |var|
      field_name = var.name[1..-1]
      if type.lookup_instance_var?(var.name)
        node.raise "struct #{included_type} has a field named '#{field_name}', which #{type} already defines"
      end
      declare_c_struct_or_union_field(type, field_name, var, var.location || node.location)
    end
  end

  def visit(node : LibDef)
    pushing_type(node.resolved_type) do
      @in_lib = true
      @annotations = nil
      node.body.accept self
      @in_lib = false
    end

    false
  end

  def visit(node : CStructOrUnionDef)
    pushing_type(node.resolved_type) do
      @in_c_struct_or_union = true
      node.body.accept self
      @in_c_struct_or_union = false
    end

    false
  end

  def visit(node : ExternalVar)
    thread_local = check_class_var_annotations

    var_type = lookup_type(node.type_spec)
    var_type = check_allowed_in_lib node.type_spec, var_type

    type = current_type.as(LibType)
    type.add_var node.name, var_type, (node.real_name || node.name), thread_local

    false
  end

  def visit(node : FunDef)
    external = node.external

    node.args.each_with_index do |arg, index|
      restriction = arg.restriction.not_nil!
      arg_type = lookup_type(restriction)
      arg_type = check_allowed_in_lib(restriction, arg_type)
      if arg_type.remove_typedef.void?
        restriction.raise "can't use Void as parameter type"
      end

      # The external args were added in TopLevelVisitor
      external.args[index].type = arg_type
    end

    node_return_type = node.return_type
    if node_return_type
      return_type = lookup_type(node_return_type)
      return_type = check_allowed_in_lib(node_return_type, return_type) unless return_type.nil_type?
      return_type = @program.nil if return_type.void?
    else
      return_type = @program.nil
    end

    external.set_type(return_type)

    old_external = add_external external
    old_external.dead = true if old_external

    if current_type.is_a?(Program)
      key = DefInstanceKey.new external.object_id, external.args.map(&.type), nil, nil
      program.add_def_instance key, external
    end

    node.type = @program.nil

    false
  end

  def visit(node : TypeDeclaration)
    case var = node.var
    when Var
      declare_c_struct_or_union_field(node) if @in_c_struct_or_union
    when InstanceVar
      declare_instance_var(node, var)
    when ClassVar
      declare_class_var(node, var, false)
    else
      raise "Unexpected TypeDeclaration var type: #{var.class}"
    end

    false
  end

  def add_external(external : External)
    existing = @externals[external.real_name]?
    if existing
      if existing.compatible_with?(external)
        return existing
      else
        external.raise "fun redefinition with different signature (was `#{existing}` at #{existing.location})"
      end
    end
    @externals[external.real_name] = external
    nil
  end

  def declare_c_struct_or_union_field(node)
    type = current_type.as(NonGenericClassType)

    field_type = lookup_type(node.declared_type)
    field_type = check_allowed_in_lib node.declared_type, field_type
    if field_type.remove_typedef.void?
      node.declared_type.raise "can't use Void as a #{type.type_desc} field type"
    end

    field_name = node.var.as(Var).name
    var_name = '@' + field_name

    if type.lookup_instance_var?(var_name)
      node.raise "#{type.type_desc} #{type} already defines a field named '#{field_name}'"
    end
    ivar = MetaTypeVar.new(var_name, field_type)
    ivar.owner = type
    declare_c_struct_or_union_field(type, field_name, ivar, node.location)
  end

  def declare_c_struct_or_union_field(type, field_name, var, location)
    type.instance_vars[var.name] = var
    # even on `-Dpreview_overload_order` these methods should never be defined
    # on the type before, because field names cannot repeat
    type.add_def Def.new("#{field_name}=", [Arg.new("value")], Primitive.new("struct_or_union_set").at(location))
    type.add_def Def.new(field_name, body: InstanceVar.new(var.name))
  end

  def declare_instance_var(node, var)
    unless current_type.allows_instance_vars?
      node.raise "can't declare instance variables in #{current_type}"
    end

    case owner = current_type
    when NonGenericClassType
      declare_instance_var(owner, node, var)
      return
    when GenericClassType
      declare_instance_var(owner, node, var)
      return
    when GenericModuleType
      declare_instance_var(owner, node, var)
      return
    when GenericClassInstanceType
      # OK
      return
    when Program, FileModule
      # Error, continue
    when NonGenericModuleType
      declare_instance_var(owner, node, var)
      return
    else
      # Error, continue
    end

    node.raise "can only declare instance variables of a non-generic class, not a #{owner.type_desc} (#{owner})"
  end

  def declare_instance_var(owner, node, var)
    annotations = nil
    process_annotations(@annotations) do |annotation_type, ann|
      annotations ||= [] of {AnnotationType, Annotation}
      annotations << {annotation_type, ann}
    end

    var_type = lookup_type(node.declared_type)
    var_type = check_declare_var_type(node, var_type, "an instance variable")
    owner_vars = @instance_vars[owner] ||= {} of String => TypeDeclarationWithLocation
    type_decl = TypeDeclarationWithLocation.new(var_type.virtual_type, node.location.not_nil!,
      false, annotations)
    owner_vars[var.name] = type_decl
  end

  def declare_class_var(node, var, uninitialized)
    owner = class_var_owner(node)
    var_type = lookup_type(node.declared_type)
    var_type = check_declare_var_type(node, var_type, "a class variable")
    owner_vars = @class_vars[owner] ||= {} of String => TypeDeclarationWithLocation
    owner_vars[var.name] = TypeDeclarationWithLocation.new(var_type.virtual_type, node.location.not_nil!, uninitialized, nil)
  end

  def visit(node : UninitializedVar)
    var = node.var
    case var
    when InstanceVar
      declare_instance_var(node, var)
    when ClassVar
      declare_class_var(node, var, true)
    else
      # nothing (it's a var)
    end
    false
  end

  def visit(node : Assign)
    false
  end

  def visit(node : ProcLiteral)
    node.def.body.accept self
    false
  end
end
