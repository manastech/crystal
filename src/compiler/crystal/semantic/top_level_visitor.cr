require "./semantic_visitor"

# In this pass we traverse the AST nodes to declare and process:
# - class
# - struct
# - module
# - include
# - extend
# - enum (checking their value, since these need to be numbers or simple math operations)
# - macro
# - def (without going inside them)
# - alias (without resolution)
# - constants (without checking their value)
# - macro calls (only surface macros, because we don't go inside defs)
# - lib and everything inside them
# - fun with body (without going inside them)
#
# Macro calls are expanded, but only the first pass is done to them. This
# allows macros to define new classes and methods.
#
# We also process @[Link] annotations.
#
# After this pass we have completely defined the whole class hierarchy,
# including methods. After this point no new classes or methods can be introduced
# since in next passes we only go inside methods and top-level code, but we already
# analyzed top-level (surface) macros that could have expanded to class/method
# definitions.
#
# Now that we know the whole hierarchy, when someone types Foo, we know whether Foo has
# subclasses or not and we can tag it as "virtual" (having subclasses), but that concept
# might disappear in the future and we'll make consider everything as "maybe virtual".
class Crystal::TopLevelVisitor < Crystal::SemanticVisitor
  # These are `new` methods (values) that was created from `initialize` methods (keys)
  getter new_expansions : Hash(Def, Def) = ({} of Def => Def).compare_by_identity

  # All finished hooks and their scope
  record FinishedHook, scope : ModuleType, macro : Macro
  @finished_hooks = [] of FinishedHook

  @method_added_running = false

  @last_doc : String?

  # special types recognized for `@[Primitive]`
  private enum PrimitiveType
    ReferenceStorageType
  end

  def visit(node : ClassDef)
    check_outside_exp node, "declare class"

    scope, name, type = lookup_type_def(node)

    annotations = read_annotations

    special_type = nil
    process_annotations(annotations) do |annotation_type, ann|
      case annotation_type
      when @program.primitive_annotation
        if ann.args.size != 1
          ann.raise "expected Primitive annotation to have one argument"
        end

        arg = ann.args.first
        unless arg.is_a?(SymbolLiteral)
          arg.raise "expected Primitive argument to be a symbol literal"
        end

        value = arg.value
        special_type = PrimitiveType.parse?(value)
        unless special_type
          arg.raise "BUG: Unknown primitive type #{value.inspect}"
        end
      end
    end

    created_new_type = false

    if type
      type = type.remove_alias

      unless type.is_a?(ClassType)
        node.raise "#{name} is not a #{node.struct? ? "struct" : "class"}, it's a #{type.type_desc}"
      end

      if node.struct? != type.struct?
        node.raise "#{name} is not a #{node.struct? ? "struct" : "class"}, it's a #{type.type_desc}"
      end

      if type_vars = node.type_vars
        if type.is_a?(GenericType)
          check_reopened_generic(type, node, type_vars)
        else
          node.raise "#{name} is not a generic #{type.type_desc}"
        end
      end
    else
      created_new_type = true
      case special_type
      in Nil
        if type_vars = node.type_vars
          type = GenericClassType.new @program, scope, name, nil, type_vars, false
          type.splat_index = node.splat_index
        else
          type = NonGenericClassType.new @program, scope, name, nil, false
        end
        type.abstract = node.abstract?
        type.struct = node.struct?
      in .reference_storage_type?
        type_vars = node.type_vars
        case
        when !node.struct?
          node.raise "BUG: Expected ReferenceStorageType to be a struct type"
        when node.abstract?
          node.raise "BUG: Expected ReferenceStorageType to be a non-abstract type"
        when !type_vars
          node.raise "BUG: Expected ReferenceStorageType to be a generic type"
        when type_vars.size != 1
          node.raise "BUG: Expected ReferenceStorageType to have a single generic type parameter"
        when node.splat_index
          node.raise "BUG: Expected ReferenceStorageType to have no splat parameter"
        end
        type = GenericReferenceStorageType.new @program, scope, name, @program.value, type_vars
        type.declare_instance_var("@type_id", @program.int32)
        type.can_be_stored = false
      end
    end

    type.private = true if node.visibility.private?

    node_superclass = node.superclass
    if node_superclass
      if type_vars = node.type_vars
        free_vars = {} of String => TypeVar
        type_vars.each do |type_var|
          free_vars[type_var] = type.as(GenericType).type_parameter(type_var)
        end
      else
        free_vars = nil
      end

      # find_root_generic_type_parameters is false because
      # we don't want to find T in this case:
      #
      # class A(T)
      #   class B < T
      #   end
      # end
      #
      # We search for a superclass starting from the current
      # type, A(T) in this case, but we don't want to find
      # type parameters because they will always be unbound.
      superclass = lookup_type(node_superclass,
        free_vars: free_vars,
        find_root_generic_type_parameters: false).devirtualize
      case superclass
      when GenericClassType
        node_superclass.raise "generic type arguments must be specified when inheriting #{superclass}"
      when NonGenericClassType, GenericClassInstanceType
        if superclass == @program.enum
          node_superclass.raise "can't inherit Enum. Use the enum keyword to define enums"
        end
      else
        node_superclass.raise "#{superclass} is not a class, it's a #{superclass.type_desc}"
      end
    else
      superclass = node.struct? ? program.struct : program.reference
    end

    if node.superclass && !created_new_type && type.superclass != superclass
      node.raise "superclass mismatch for class #{type} (#{superclass} for #{type.superclass})"
    end

    if created_new_type && superclass
      if node.struct? != superclass.struct?
        node.raise "can't make #{node.struct? ? "struct" : "class"} '#{node.name}' inherit #{superclass.type_desc} '#{superclass}'"
      end

      if superclass.struct? && !superclass.abstract?
        node.raise "can't extend non-abstract struct #{superclass}"
      end

      if type.is_a?(GenericReferenceStorageType) && superclass != @program.value
        node.raise "BUG: Expected reference_storage_type to inherit from Value"
      end
    end

    if created_new_type
      type.superclass = superclass

      # If it's SomeClass(T) < Foo(T), or SomeClass < Foo(Int32),
      # we want to add SomeClass as a subclass of Foo(T)
      if superclass.is_a?(GenericClassInstanceType)
        superclass.generic_type.add_subclass(type)
      end
      scope.types[name] = type
    end

    node.resolved_type = type

    process_annotations(annotations) do |annotation_type, ann|
      if node.struct? && type.is_a?(NonGenericClassType)
        case annotation_type
        when @program.extern_annotation
          unless type.is_a?(NonGenericClassType)
            node.raise "can only use Extern annotation with non-generic structs"
          end

          unless ann.args.empty?
            ann.raise "Extern annotation can't have positional arguments, only named arguments: 'union'"
          end

          ann.named_args.try &.each do |named_arg|
            case named_arg.name
            when "union"
              value = named_arg.value
              if value.is_a?(BoolLiteral)
                type.extern_union = value.value
              else
                value.raise "Extern 'union' annotation must be a boolean, not #{value.class_desc}"
              end
            else
              named_arg.raise "unknown Extern named argument, valid arguments are: 'union'"
            end
          end

          type.extern = true
        when @program.packed_annotation
          type.packed = true
        else
          # not a built-in annotation
        end
      end

      type.add_annotation(annotation_type, ann)
    end

    attach_doc type, node, annotations

    pushing_type(type) do
      run_hooks(hook_type(superclass), type, :inherited, node) if created_new_type
      node.body.accept self
    end

    if created_new_type
      type.force_add_subclass
    end

    false
  end

  def visit(node : ModuleDef)
    check_outside_exp node, "declare module"

    annotations = read_annotations

    scope, name, type = lookup_type_def(node)

    if type
      type = type.remove_alias

      unless type.module?
        node.raise "#{name} is not a module, it's a #{type.type_desc}"
      end

      if type_vars = node.type_vars
        if type.is_a?(GenericType)
          check_reopened_generic(type, node, type_vars)
        else
          node.raise "#{name} is not a generic module"
        end
      end

      type = type.as(ModuleType)
    else
      if type_vars = node.type_vars
        type = GenericModuleType.new @program, scope, name, type_vars
        type.splat_index = node.splat_index
      else
        type = NonGenericModuleType.new @program, scope, name
      end
      scope.types[name] = type
    end

    type.private = true if node.visibility.private?

    node.resolved_type = type

    attach_doc type, node, annotations

    process_annotations(annotations) do |annotation_type, ann|
      type.add_annotation(annotation_type, ann)
    end

    pushing_type(type) do
      node.body.accept self
    end

    false
  end

  private def check_reopened_generic(generic, node, new_type_vars)
    generic_type_vars = generic.type_vars
    if new_type_vars != generic_type_vars || node.splat_index != generic.splat_index
      msg = String.build do |io|
        io << "type var"
        io << 's' if generic_type_vars.size > 1
        io << " must be "
        generic_type_vars.each_with_index do |var, i|
          io << ", " if i > 0
          io << '*' if i == generic.splat_index
          var.to_s(io)
        end
        io << ", not "
        new_type_vars.each_with_index do |var, i|
          io << ", " if i > 0
          io << '*' if i == node.splat_index
          var.to_s(io)
        end
      end
      node.raise msg
    end
  end

  def visit(node : AnnotationDef)
    check_outside_exp node, "declare annotation"

    annotations = read_annotations
    process_annotations(annotations) do |annotation_type, ann|
      node.add_annotation(annotation_type, ann)
    end

    scope, name, type = lookup_type_def(node)

    if type
      unless type.is_a?(AnnotationType)
        node.raise "#{type} is not an annotation, it's a #{type.type_desc}"
      end
    else
      type = AnnotationType.new(@program, scope, name)
      scope.types[name] = type
    end

    node.resolved_type = type

    attach_doc type, node, annotations

    false
  end

  def visit(node : Alias)
    check_outside_exp node, "declare alias"

    annotations = read_annotations

    scope, name, existing_type = lookup_type_def(node)

    if existing_type
      if existing_type.is_a?(AliasType)
        node.raise "alias #{node.name} is already defined"
      else
        node.raise "can't alias #{node.name} because it's already defined as a #{existing_type.type_desc}"
      end
    end

    alias_type = AliasType.new(@program, scope, name, node.value)
    attach_doc alias_type, node, annotations
    scope.types[name] = alias_type

    alias_type.private = true if node.visibility.private?

    node.resolved_type = alias_type

    false
  end

  def visit(node : Macro)
    check_outside_exp node, "declare macro"

    annotations = read_annotations
    process_annotations(annotations) do |annotation_type, ann|
      node.add_annotation(annotation_type, ann)
    end
    node.doc ||= annotations_doc(annotations)
    check_ditto node, node.location

    node.args.each &.accept self
    node.double_splat.try &.accept self
    node.block_arg.try &.accept self

    node.set_type @program.nil

    if node.name == "finished"
      unless node.args.empty?
        node.raise "wrong number of parameters for macro '#{node.name}' (given #{node.args.size}, expected 0)"
      end
      @finished_hooks << FinishedHook.new(current_type, node)
      return false
    end

    target = current_type.metaclass.as(ModuleType)
    begin
      target.add_macro node
    rescue ex : Crystal::CodeError
      node.raise ex.message
    end

    false
  end

  def visit(node : Arg)
    if anns = node.parsed_annotations
      process_annotations anns do |annotation_type, ann|
        node.add_annotation annotation_type, ann
      end
    end

    false
  end

  def visit(node : Def)
    check_outside_exp node, "declare def"

    annotations = read_annotations

    process_def_annotations(node, annotations) do |annotation_type, ann|
      if annotation_type == @program.primitive_annotation
        process_def_primitive_annotation(node, ann)
      end

      node.add_annotation(annotation_type, ann)
    end

    node.doc ||= annotations_doc(annotations)
    check_ditto node, node.location

    node.args.each &.accept self
    node.double_splat.try &.accept self
    node.block_arg.try &.accept self

    is_instance_method = false

    target_type = case receiver = node.receiver
                  when Nil
                    is_instance_method = true
                    current_type
                  when Var
                    unless receiver.name == "self"
                      receiver.raise "def receiver can only be a Type or self"
                    end
                    current_type.metaclass
                  else
                    type = lookup_type(receiver)
                    metaclass = type.metaclass
                    case metaclass
                    when LibType
                      receiver.raise "can't define method in lib #{metaclass}"
                    when GenericClassInstanceMetaclassType
                      receiver.raise "can't define method in generic instance #{metaclass}"
                    when GenericModuleInstanceMetaclassType
                      receiver.raise "can't define method in generic instance #{metaclass}"
                    end
                    metaclass
                  end

    target_type = target_type.as(ModuleType)

    if node.abstract?
      if (target_type.class? || target_type.struct?) && !target_type.abstract?
        node.raise "can't define abstract def on non-abstract #{target_type.type_desc}"
      end
      if target_type.metaclass?
        node.raise "can't define abstract def on metaclass"
      end
    end

    if target_type.struct? && !target_type.metaclass? && node.name == "finalize"
      node.raise "structs can't have finalizers because they are not tracked by the GC"
    end

    if target_type.is_a?(EnumType) && node.name == "initialize"
      node.raise "enums can't define an `initialize` method, try using `def self.new`"
    end

    defer_overload_order = @program.has_flag?("preview_overload_order")
    target_type.add_def node, ordered: !defer_overload_order

    node.set_type @program.nil

    if is_instance_method
      # If it's an initialize method, we define a `self.new` for
      # the type, initially empty. We will fill it once we know if
      # a type defines a `finalize` method, but defining it now
      # allows `previous_def` for a next `def self.new` definition
      # to find this method.
      if node.name == "initialize"
        new_method = node.expand_new_signature_from_initialize(target_type)
        target_type.metaclass.as(ModuleType).add_def(new_method, ordered: !defer_overload_order)

        # And we register it to later complete it
        new_expansions[node] = new_method
      end

      if !@method_added_running && has_hooks?(target_type.metaclass)
        @method_added_running = true
        run_hooks target_type.metaclass, target_type, :method_added, node, Call.new("method_added", node).at(node)
        @method_added_running = false
      end
    end

    false
  end

  private def process_def_primitive_annotation(node, ann)
    if ann.args.size != 1
      ann.raise "expected Primitive annotation to have one argument"
    end

    arg = ann.args.first
    unless arg.is_a?(SymbolLiteral)
      arg.raise "expected Primitive argument to be a symbol literal"
    end

    value = arg.value

    primitive = Primitive.new(value)
    primitive.location = node.location

    node.body = primitive
  end

  def visit(node : Include)
    check_outside_exp node, "include"
    include_in current_type, node, :included
    false
  end

  def visit(node : Extend)
    check_outside_exp node, "extend"
    include_in current_type.metaclass, node, :extended
    false
  end

  def visit(node : LibDef)
    check_outside_exp node, "declare lib"

    annotations = read_annotations

    scope, name, type = lookup_type_def(node)

    if type
      unless type.is_a?(LibType)
        node.raise "#{type} is not a lib, it's a #{type.type_desc}"
      end
    else
      type = LibType.new @program, scope, name
      scope.types[name] = type
    end

    node.resolved_type = type

    type.private = true if node.visibility.private?

    wasm_import_module = nil

    process_annotations(annotations) do |annotation_type, ann|
      case annotation_type
      when @program.link_annotation
        link_annotation = LinkAnnotation.from(ann)

        if link_annotation.static?
          @program.warnings.add_warning(ann, "specifying static linking for individual libraries is deprecated")
        end

        if ann.args.size > 1
          @program.warnings.add_warning(ann, "using non-named arguments for Link annotations is deprecated")
        end

        if wasm_import_module && link_annotation.wasm_import_module
          ann.raise "multiple wasm import modules specified for lib #{type}"
        end

        wasm_import_module = link_annotation.wasm_import_module

        type.add_link_annotation(link_annotation)
      when @program.call_convention_annotation
        type.call_convention = parse_call_convention(ann, type.call_convention)
      else
        # not a built-in annotation
      end
      type.add_annotation(annotation_type, ann)
    end

    pushing_type(type) do
      @in_lib = true
      node.body.accept self
      @in_lib = false
    end

    false
  end

  def visit(node : CStructOrUnionDef)
    annotations = read_annotations

    packed = false
    unless node.union?
      process_annotations(annotations) do |ann|
        packed = true if ann == @program.packed_annotation
      end
    end

    type = current_type.types[node.name]?
    if type
      unless type.is_a?(NonGenericClassType)
        node.raise "#{node.name} is already defined as #{type.type_desc}"
      end

      if !type.extern? || (type.extern_union? != node.union?)
        node.raise "#{node.name} is already defined as #{type.type_desc}"
      end

      node.raise "#{node.name} is already defined"
    else
      type = NonGenericClassType.new(@program, current_type, node.name, @program.struct)
      type.struct = true
      type.extern = true
      type.extern_union = node.union?

      if location = node.location
        type.add_location(location)
      end

      current_type.types[node.name] = type
    end

    node.resolved_type = type

    type.packed = packed

    false
  end

  def visit(node : TypeDef)
    type = current_type.types[node.name]?
    if type
      node.raise "#{node.name} is already defined"
    else
      typed_def_type = lookup_type(node.type_spec)
      typed_def_type = check_allowed_in_lib node.type_spec, typed_def_type
      current_type.types[node.name] = TypeDefType.new @program, current_type, node.name, typed_def_type
      false
    end
  end

  def visit(node : EnumDef)
    check_outside_exp node, "declare enum"

    annotations = read_annotations

    scope, name, enum_type = lookup_type_def(node)

    if enum_type
      unless enum_type.is_a?(EnumType)
        node.raise "#{name} is not a enum, it's a #{enum_type.type_desc}"
      end
    end

    if base_type = node.base_type
      enum_base_type = lookup_type(base_type)
      unless enum_base_type.is_a?(IntegerType)
        base_type.raise "enum base type must be an integer type"
      end

      if enum_type && enum_base_type != enum_type.base_type
        base_type.raise "enum #{name}'s base type is #{enum_type.base_type}, not #{enum_base_type}"
      end
    end

    existed = !!enum_type
    enum_type ||= EnumType.new(@program, scope, name, enum_base_type || @program.int32)

    enum_type.private = true if node.visibility.private?

    process_annotations(annotations) do |annotation_type, ann|
      enum_type.flags = true if annotation_type == @program.flags_annotation
      enum_type.add_annotation(annotation_type, ann)
    end

    node.resolved_type = enum_type
    attach_doc enum_type, node, annotations

    pushing_type(enum_type) do
      visit_enum_members(node, node.members, existed, enum_type)
    end

    unless existed
      num_members = enum_type.types.size
      if num_members > 0 && enum_type.flags?
        # skip None & All, they doesn't count as members for @[Flags] enums
        num_members = enum_type.types.count { |(name, _)| !name.in?("None", "All") }
      end

      if num_members == 0
        node.raise "enum #{node.name} must have at least one member"
      end

      if enum_type.flags?
        unless enum_type.types.has_key?("None")
          none_member = enum_type.add_constant("None", 0)

          if node_location = node.location
            none_member.add_location node_location
          end

          define_enum_none_question_method(enum_type, node)
        end

        unless enum_type.types.has_key?("All")
          all_value = enum_type.base_type.kind.cast(0).as(Int::Primitive)

          enum_type.types.each_value do |member|
            all_value |= interpret_enum_value(member.as(Const).value, enum_type.base_type)
          end

          all_member = enum_type.add_constant("All", all_value)

          if node_location = node.location
            all_member.add_location node_location
          end
        end
      end

      scope.types[name] = enum_type
    end

    false
  end

  def visit_enum_members(node, members, existed, enum_type, previous_counter = nil)
    members.reduce(previous_counter) do |counter, member|
      visit_enum_member(node, member, existed, enum_type, counter)
    end
  end

  def visit_enum_member(node, member, existed, enum_type, previous_counter = nil)
    case member
    when MacroIf
      expanded = expand_inline_macro(member, mode: Parser::ParseMode::Enum, accept: false)
      visit_enum_member(node, expanded, existed, enum_type, previous_counter)
    when MacroExpression
      expanded = expand_inline_macro(member, mode: Parser::ParseMode::Enum, accept: false)
      visit_enum_member(node, expanded, existed, enum_type, previous_counter)
    when MacroFor
      expanded = expand_inline_macro(member, mode: Parser::ParseMode::Enum, accept: false)
      visit_enum_member(node, expanded, existed, enum_type, previous_counter)
    when Expressions
      visit_enum_members(node, member.expressions, existed, enum_type, previous_counter)
    when Arg
      if existed
        node.raise "can't reopen enum and add more constants to it"
      end

      if enum_type.types.has_key?(member.name)
        member.raise "enum '#{enum_type}' already contains a member named '#{member.name}'"
      end

      if default_value = member.default_value
        counter = interpret_enum_value(default_value, enum_type.base_type)
      elsif previous_counter
        if enum_type.flags?
          if previous_counter == 0 # In case the member is set to 0
            counter = 1
          else
            counter = previous_counter &* 2
            unless (counter <=> previous_counter).sign == previous_counter.sign
              member.raise "value of enum member #{member} would overflow the base type #{enum_type.base_type}"
            end
          end
        else
          counter = previous_counter &+ 1
          unless counter > previous_counter
            member.raise "value of enum member #{member} would overflow the base type #{enum_type.base_type}"
          end
        end
      else
        counter = enum_type.base_type.kind.cast(enum_type.flags? ? 1 : 0).as(Int::Primitive)
      end

      if enum_type.flags? && !@in_lib
        if member.name == "None" && counter != 0
          member.raise "flags enum can't redefine None member to non-0"
        elsif member.name == "All"
          member.raise "flags enum can't redefine All member. None and All are autogenerated"
        end
      end

      if default_value.is_a?(Crystal::NumberLiteral)
        enum_base_kind = enum_type.base_type.kind
        if (enum_base_kind.i32?) && (enum_base_kind != default_value.kind)
          default_value.raise "enum value must be an Int32"
        end
      end

      define_enum_question_method(enum_type, member, enum_type.flags?)

      const_member = enum_type.add_constant(member.name, counter)
      member.default_value = const_member.value

      const_member.doc = member.doc
      check_ditto const_member, member.location

      if member_location = member.location
        const_member.add_location(member_location)
      end

      counter
    else
      member.accept self
      previous_counter
    end
  end

  def define_enum_question_method(enum_type, member, is_flags)
    method_name = is_flags ? "includes?" : "=="
    body = Call.new(Var.new("self").at(member), method_name, Path.new(member.name).at(member)).at(member)
    a_def = Def.new("#{member.name.underscore}?", body: body).at(member)

    a_def.doc = if member.doc.try &.starts_with?(":nodoc:")
                  ":nodoc:"
                else
                  "Returns `true` if this enum value #{is_flags ? "contains" : "equals"} `#{member.name}`"
                end

    enum_type.add_def a_def
  end

  def define_enum_none_question_method(enum_type, node)
    body = Call.new(Call.new(nil, "value").at(node), "==", NumberLiteral.new(0)).at(node)
    a_def = Def.new("none?", body: body).at(node)
    enum_type.add_def a_def
  end

  def visit(node : Expressions)
    node.expressions.each_with_index do |child, i|
      begin
        child.accept self
      rescue SkipMacroException
        node.expressions.delete_at(i..-1)
        break
      end
    end
    false
  end

  def visit(node : Assign)
    type_assign(node.target, node.value, node)
    false
  end

  def type_assign(target : Var, value, node)
    @vars[target.name] = MetaVar.new(target.name)
    value.accept self
    false
  end

  def type_assign(target : Path, value, node)
    # We are inside the assign, so we go outside it to check if we are inside an outer expression
    @exp_nest -= 1
    check_outside_exp node, "declare constant"
    @exp_nest += 1

    annotations = read_annotations

    name = target.names.last
    scope = lookup_type_def_scope(target, target)
    type = scope.types[name]?
    if type
      target.raise "already initialized constant #{type}"
    end

    const = Const.new(@program, scope, name, value)
    const.private = true if target.visibility.private?

    process_annotations(annotations) do |annotation_type, ann|
      # annotations on constants are inaccessible in macros so we only add deprecations
      const.add_annotation(annotation_type, ann) if annotation_type == @program.deprecated_annotation
    end

    check_ditto node, node.location
    attach_doc const, node, annotations

    scope.types[name] = const

    target.target_const = const
  end

  def type_assign(target, value, node)
    value.accept self

    # Prevent to assign instance variables inside nested expressions.
    # `@exp_nest > 1` is to check nested expressions. We cannot use `inside_exp?` simply
    # because `@exp_nest` is increased when `node` is `Assign`.
    if @exp_nest > 1 && target.is_a?(InstanceVar)
      node.raise "can't use instance variables at the top level"
    end

    false
  end

  def visit(node : VisibilityModifier)
    node.exp.visibility = node.modifier
    node.exp.accept self

    # Can only apply visibility modifier to def, type, macro or a macro call
    case exp = node.exp
    when ClassDef, ModuleDef, EnumDef, Alias, LibDef
      if node.modifier.private?
        return false
      else
        node.raise "can only use 'private' for types"
      end
    when Assign
      if exp.target.is_a?(Path)
        if node.modifier.private?
          return false
        else
          node.raise "can only use 'private' for constants"
        end
      end
    when Def
      return false
    when Macro
      if node.modifier.private?
        return false
      else
        node.raise "can only use 'private' for macros"
      end
    when Call
      # Don't give an error yet: wait to see if the
      # call doesn't resolve to a method/macro
      return false
    end

    node.raise "can't apply visibility modifier"
  end

  def visit(node : ProcLiteral)
    old_vars_keys = @vars.keys

    node.def.args.each do |arg|
      @vars[arg.name] = MetaVar.new(arg.name)
    end

    node.def.body.accept self

    # Now remove these vars, but only if they weren't vars before
    node.def.args.each do |arg|
      @vars.delete(arg.name) unless old_vars_keys.includes?(arg.name)
    end

    false
  end

  def visit(node : FunDef)
    check_outside_exp node, "declare fun"

    if node.body && !current_type.is_a?(Program)
      node.raise "can only declare fun at lib or global scope"
    end

    annotations = read_annotations

    # We'll resolve the external args types later, in TypeDeclarationVisitor
    external_args = node.args.map do |arg|
      Arg.new(arg.name).at(arg.location)
    end

    external = External.new(node.name, external_args, node.body, node.real_name).at(node)
    external.name_location = node.name_location

    call_convention = nil
    process_def_annotations(external, annotations) do |annotation_type, ann|
      if annotation_type == @program.call_convention_annotation
        call_convention = parse_call_convention(ann, call_convention)
      elsif annotation_type == @program.primitive_annotation
        process_def_primitive_annotation(external, ann)
      else
        ann.raise "funs can only be annotated with: NoInline, AlwaysInline, Naked, ReturnsTwice, Raises, CallConvention"
      end
    end

    node.doc ||= annotations_doc(annotations)
    check_ditto node, node.location

    # Copy call convention from lib, if any
    scope = current_type
    if !call_convention && scope.is_a?(LibType)
      call_convention = scope.call_convention
    end

    if scope.is_a?(LibType)
      external.wasm_import_module = scope.wasm_import_module
    end

    # We fill the arguments and return type in TypeDeclarationVisitor
    external.doc = node.doc
    external.call_convention = call_convention
    external.varargs = node.varargs?
    external.fun_def = node
    node.external = external

    # C funs cannot overload, so overload order shouldn't matter here
    # TODO: top-level funs can still overload with top-level defs (#4761),
    # they should be disallowed
    current_type.add_def(external)

    false
  end

  def visit(node : TypeDeclaration)
    if (var = node.var).is_a?(Var)
      @vars[var.name] = MetaVar.new(var.name)
    end

    # Because the value could be using macro expansions
    node.value.try &.accept(self)

    false
  end

  def visit(node : UninitializedVar)
    if (var = node.var).is_a?(Var)
      @vars[var.name] = MetaVar.new(var.name)
    end
    false
  end

  def visit(node : MultiAssign)
    node.targets.each do |target|
      var = target.is_a?(Splat) ? target.exp : target
      if var.is_a?(Var)
        @vars[var.name] = MetaVar.new(var.name)
      end
      target.accept self
    end

    node.values.each &.accept self
    false
  end

  def visit(node : Rescue)
    if name = node.name
      @vars[name] = MetaVar.new(name)
    end

    node.body.accept self

    false
  end

  def visit(node : Call)
    node.scope = node.global? ? @program : current_type.metaclass
    !expand_macro(node, raise_on_missing_const: false, first_pass: true)
  end

  def visit(node : ProcPointer)
    # A proc pointer at the top-level might refer to a macro, so we check
    # that here but we don't yet give an error: we let the real semantic visitor
    # (MainVisitor) do that job to avoid duplicating code.
    obj = node.obj

    call = Call.new(obj, node.name).at(obj)
    call.scope = current_type.metaclass
    node.call = call

    expand_macro(call, raise_on_missing_const: false, first_pass: true)

    false
  end

  def visit(node : Out)
    exp = node.exp
    if exp.is_a?(Var)
      @vars[exp.name] = MetaVar.new(exp.name)
    end
    true
  end

  def visit(node : Block)
    # Remember how many local vars we had before the block
    old_vars_size = @vars.size

    # When accepting a block, declare variables for block arguments.
    # These are needed for macro expansions to parser identifiers
    # as variables and not calls.
    node.args.each do |arg|
      @vars[arg.name] = MetaVar.new(arg.name)
    end

    node.body.accept self

    # After the block we should have the same number of local vars
    # (blocks can't declare inject local vars to the outer scope)
    while @vars.size > old_vars_size
      @vars.delete(@vars.last_key)
    end

    false
  end

  def include_in(current_type, node, kind : HookKind)
    node_name = node.name

    type = lookup_type(node_name)
    case type
    when GenericModuleType
      node.raise "generic type arguments must be specified when including #{type}"
    when .module?
      # OK
    else
      node_name.raise "#{type} is not a module, it's a #{type.type_desc}"
    end

    begin
      current_type.as(ModuleType).include type
      run_hooks hook_type(type), current_type, kind, node
    rescue ex : TypeException
      node.raise "at '#{kind}' hook", ex
    end
  end

  def has_hooks?(type_with_hooks)
    hooks = type_with_hooks.as?(ModuleType).try &.hooks
    !hooks.nil? && !hooks.empty?
  end

  def run_hooks(type_with_hooks, current_type, kind : HookKind, node, call = nil)
    type_with_hooks.as?(ModuleType).try &.hooks.try &.each do |hook|
      next if hook.kind != kind

      expansion = expand_macro(hook.macro, node, visibility: :public) do
        if call
          @program.expand_macro hook.macro, call, current_type.instance_type
        else
          @program.expand_macro hook.macro.body, current_type.instance_type
        end
      end

      node.add_hook_expansion(expansion)
    end

    if kind.inherited?
      # In the case of:
      #
      #    class A(X); end
      #    class B < A(Int32);end
      #
      # we need to go from A(Int32) to A(X) to go up the hierarchy.
      if type_with_hooks.is_a?(GenericClassInstanceMetaclassType)
        run_hooks(type_with_hooks.instance_type.generic_type.metaclass, current_type, kind, node)
      elsif (superclass = type_with_hooks.instance_type.superclass)
        run_hooks(superclass.metaclass, current_type, kind, node)
      end
    end
  end

  private def hook_type(type)
    type = type.generic_type if type.is_a?(GenericInstanceType)
    type.metaclass
  end

  def parse_call_convention(ann, call_convention)
    if call_convention
      ann.raise "call convention already specified"
    end

    if ann.args.size != 1
      ann.wrong_number_of_arguments "annotation CallConvention", ann.args.size, 1
    end

    call_convention_node = ann.args.first
    unless call_convention_node.is_a?(StringLiteral)
      call_convention_node.raise "argument to CallConvention must be a string"
    end

    value = call_convention_node.value
    call_convention = LLVM::CallConvention.parse?(value)
    unless call_convention
      call_convention_node.raise "invalid call convention. Valid values are #{LLVM::CallConvention.values.join ", "}"
    end
    call_convention
  end

  def attach_doc(type, node, annotations)
    if @program.wants_doc?
      type.doc ||= node.doc
      type.doc ||= annotations_doc(annotations) if annotations
    end

    if node_location = node.location
      type.add_location(node_location)
    end
  end

  def check_ditto(node : Def | Assign | FunDef | Const | Macro, location : Location?) : Nil
    return if !@program.wants_doc?

    if stripped_doc = node.doc.try &.strip
      if stripped_doc == ":ditto:"
        node.doc = @last_doc
        return
      elsif appendix = stripped_doc.lchop?(":ditto:\n")
        node.doc = "#{@last_doc}\n\n#{appendix.lchop('\n')}"
        return
      end
    end

    @last_doc = node.doc
  end

  def annotations_doc(annotations)
    annotations.try(&.first?).try &.doc
  end

  def process_def_annotations(node, annotations, &)
    process_annotations(annotations) do |annotation_type, ann|
      case annotation_type
      when @program.no_inline_annotation
        node.no_inline = true
      when @program.always_inline_annotation
        node.always_inline = true
      when @program.naked_annotation
        node.naked = true
      when @program.returns_twice_annotation
        node.returns_twice = true
      when @program.raises_annotation
        node.raises = true
      else
        yield annotation_type, ann
      end
    end
  end

  def lookup_type_def(node : ASTNode)
    path = node.name
    scope = lookup_type_def_scope(node, path)
    name = path.names.last
    type = scope.types[name]?
    if type && node.doc
      type.doc = node.doc
    end
    {scope, name, type}
  end

  def lookup_type_def_scope(node : ASTNode, path : Path)
    scope =
      if path.names.size == 1
        if path.global?
          if node.visibility.private?
            path.raise "can't declare private type in the global namespace; drop the `private` for the top-level namespace, or drop the leading `::` for the file-private namespace"
          end
          program
        else
          if current_type.is_a?(Program)
            file_module = program.check_private(node)
          end
          file_module || current_type
        end
      else
        prefix = path.clone
        prefix.names.pop
        lookup_type_def_name_creating_modules prefix
      end

    check_type_is_type_container(scope, path)
  end

  def check_type_is_type_container(scope, path)
    if scope.is_a?(EnumType) || !scope.is_a?(ModuleType)
      path.raise "can't declare type inside #{scope.type_desc} #{scope}"
    end

    scope
  end

  def lookup_type_def_name_creating_modules(path : Path)
    base_type = path.global? ? program : current_type
    target_type = base_type.lookup_path(path, lookup_in_namespace: false).as?(Type).try &.remove_alias_if_simple

    unless target_type
      next_type = base_type
      path.names.each do |name|
        next_type = base_type.lookup_path_item(name, lookup_self: false, lookup_in_namespace: false, include_private: true, location: path.location)
        if next_type
          if next_type.is_a?(ASTNode)
            path.raise "expected #{name} to be a type"
          end
        else
          base_type = check_type_is_type_container(base_type, path)
          next_type = NonGenericModuleType.new(@program, base_type.as(ModuleType), name)
          if (location = path.location)
            next_type.add_location(location)
          end
          base_type.types[name] = next_type
        end
        base_type = next_type
      end
      target_type = next_type
    end

    target_type.as(NamedType)
  end

  # Turns all finished macros into expanded nodes, and
  # adds them to the program
  def process_finished_hooks
    @finished_hooks.each do |hook|
      self.current_type = hook.scope
      expansion = expand_macro(hook.macro, hook.macro, visibility: :public) do
        @program.expand_macro hook.macro.body, hook.scope
      end
      program.add_finished_hook(hook.scope, hook.macro, expansion)
    end
  end
end
