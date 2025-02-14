require "./syntax/ast"

module Crystal
  # Abstract base class of all types
  abstract class Type
    include Annotatable

    # Returns the program where this type belongs.
    getter program

    def initialize(@program : Program)
    end

    # Returns any doc comments associated to this type.
    def doc : String?
      nil
    end

    # Returns all locations where this type is declared
    def locations : Array(Location)?
      nil
    end

    # An opaque id of every type. 0 for Nil, non zero for others, so we can
    # sort types by opaque_id and have Nil in the beginning.
    def opaque_id
      self.is_a?(NilType) ? 0_u64 : object_id
    end

    # The namespace this type belongs to. Every type belongs to
    # a namespace, and, when not explicit, the namespace is the `Program` itself.
    def namespace : ModuleType
      program
    end

    # Yields each namespace this type belongs to, excluding the `Program` itself.
    def each_namespace(& : ModuleType ->) : Nil
      ns = self.namespace
      until ns == program
        yield ns
        ns = ns.namespace
      end
    end

    # Returns `true` if this type is abstract.
    def abstract?
      false
    end

    # Returns `true` if this type is abstract and it has no
    # concrete subclasses. This can happen if this type has abstract
    # subclasses, or non-abstract generic subclasses without instantiations.
    def abstract_leaf?
      type = self.devirtualize

      case type
      when GenericType
        instances = type.instantiated_types
        (type.abstract? && instances.empty?) || instances.all?(&.abstract_leaf?)
      when GenericClassInstanceType
        type.abstract? && type.subclasses.all?(&.abstract_leaf?)
      when ClassType
        type.abstract? && type.subclasses.all?(&.abstract_leaf?)
      else
        false
      end
    end

    # Returns `true` if this type is a struct.
    def struct?
      false
    end

    # Returns `true` if this is an extern C struct or union (`extern_union?` tells which one)
    def extern?
      false
    end

    # Returns `true` if this is an extern C union (`extern?` will be `true` too)
    def extern_union?
      false
    end

    # Returns `true` if this type has the `@[Packed]` annotation on it
    # (only applicable for C structs)
    def packed?
      false
    end

    # Returns `true` if this type inherits from `Reference` or if this
    # is a union type where all types are reference types or nil.
    # In this case this type can be represented with a single pointer.
    def reference_like?
      case self
      when NilType, NilableType, NilableReferenceUnionType, ReferenceUnionType
        true
      when NonGenericClassType
        !self.struct?
      when GenericClassType
        !self.struct?
      when GenericClassInstanceType
        !self.struct?
      when VirtualType
        !self.struct?
      else
        false
      end
    end

    # Returns the methods defined in this type, indexed by their name.
    # This does not include methods defined in ancestors.
    def defs : Hash(String, Array(DefWithMetadata))?
      nil
    end

    # Returns all macros defines in this type, indexed by their name.
    # This does not include methods defined in ancestors.
    def macros : Hash(String, Array(Macro))?
      nil
    end

    # Returns this type's metaclass, which holds class methods for this type.
    getter metaclass : Type do
      metaclass = MetaclassType.new(program, self)
      initialize_metaclass(metaclass)
      metaclass
    end

    # Initializes a metaclass.
    # Some subtypes (classes) add an `allocate` method so a class can be instantiated.
    protected def initialize_metaclass(metaclass)
      # Nothing
    end

    # Returns `true` if this type can be assigned to an instance or class
    # variable, or used in a generic type argument.
    #
    # As of now, abstract base type such as Object, Reference, Value,
    # Int, and unbound generic types such as `Array(T)`, can't be stored.
    def can_be_stored?
      true
    end

    # Returns direct subclasses of this type.
    def subclasses : Array(Type)
      [] of Type
    end

    # Returns all subclasses of this type, including subclasses of
    # subclasses recursively.
    def all_subclasses
      subclasses = [] of Type
      append_subclasses(self, subclasses)
      subclasses
    end

    private def append_subclasses(type, subclasses)
      type.subclasses.each do |subclass|
        subclasses << subclass
        append_subclasses subclass, subclasses
      end
    end

    # Returns `true` if this type has no subclasses.
    def leaf?
      subclasses.size == 0
    end

    def class?
      false
    end

    def module?
      false
    end

    def metaclass?
      case self
      when MetaclassType,
           GenericClassInstanceMetaclassType, GenericModuleInstanceMetaclassType,
           VirtualMetaclassType
        true
      else
        false
      end
    end

    def pointer?
      self.is_a?(PointerInstanceType)
    end

    def nil_type?
      self.is_a?(NilType)
    end

    def nilable?
      nil_type? || program.nil_type.implements?(self)
    end

    def bool_type?
      self.is_a?(BoolType)
    end

    def no_return?
      self.is_a?(NoReturnType)
    end

    def virtual?
      self.is_a?(VirtualType)
    end

    def virtual_metaclass?
      self.is_a?(VirtualMetaclassType)
    end

    def proc?
      self.is_a?(ProcInstanceType)
    end

    def void?
      self.is_a?(VoidType)
    end

    def virtual_type
      self
    end

    def virtual_type!
      self
    end

    def instance_type
      self
    end

    def generic_type
      raise "BUG: #{self} doesn't implement generic_type"
    end

    def includes_type?(type)
      self == type
    end

    def remove_typedef
      self
    end

    # Returns the type that owns class vars for a type.
    #
    # This method returns self, but subclasses might override.
    # For example, a metaclass' class_var_owner is the instance type.
    def class_var_owner
      self
    end

    def has_in_type_vars?(type)
      false
    end

    # Should `new` be looked up in ancestors?
    #
    # This is `true` if this type doesn't define any
    # `initialize` methods.
    def lookup_new_in_ancestors?
      false
    end

    # Returns the non-virtual type of a given type
    # (returns self if self is already non-virtual)
    def devirtualize
      case self
      when VirtualType
        self.base_type
      when VirtualMetaclassType
        self.base_type.metaclass
      else
        self
      end
    end

    def implements?(other_type : Type)
      return true if self == other_type

      other_type = other_type.remove_alias
      case other_type
      when UnionType
        other_type.union_types.any? do |union_type|
          implements?(union_type)
        end
      when VirtualType
        implements?(other_type.base_type)
      when VirtualMetaclassType
        implements?(other_type.base_type.metaclass)
      else
        !!parents.try &.any? &.implements?(other_type)
      end
    end

    def filter_by(other_type : Type)
      Type.common_descendent(self, other_type)
    end

    def filter_by_responds_to(name)
      nil
    end

    def add_instance_var_initializer(name, value, meta_vars)
      raise "BUG: #{self} doesn't implement add_instance_var_initializer"
    end

    def declare_instance_var(name, type : Type, annotations = nil)
      var = MetaTypeVar.new(name)
      var.owner = self
      var.type = type
      var.annotations = annotations
      var.bind_to var
      var.freeze_type = type
      instance_vars[name] = var
    end

    # Determines if `self` can access *type* assuming it's a `protected` access.
    # If `allow_same_namespace` is true (the default), `protected` also means
    # the types are in the same namespace. Otherwise, it means they are just
    # in the same type hierarchy.
    def has_protected_access_to?(type, allow_same_namespace = true)
      owner = self.devirtualize
      type = type.devirtualize

      # Allow two different generic instantiations
      # of the same type to have protected access
      type = type.generic_type.as(Type) if type.is_a?(GenericInstanceType)
      owner = owner.generic_type.as(Type) if owner.is_a?(GenericInstanceType)

      owner.implements?(type) ||
        type.implements?(owner) ||
        (allow_same_namespace && owner.same_namespace?(type))
    end

    # Returns true if `self` and *other* are in the same namespace.
    def same_namespace?(other)
      top_namespace(self) == top_namespace(other) ||
        !!parents.try &.any?(&.same_namespace?(other))
    end

    private def top_namespace(type)
      type = type.generic_type if type.is_a?(GenericInstanceType)

      namespace = case type
                  when NamedType
                    type.namespace
                  when GenericClassInstanceType
                    type.namespace
                  else
                    nil
                  end
      case namespace
      when Program
        type
      when GenericInstanceType
        top_namespace(namespace.generic_type)
      when NamedType
        top_namespace(namespace)
      else
        type
      end
    end

    def types
      raise "BUG: #{self} has no types"
    end

    def types?
      nil
    end

    def lookup_name(name)
      types?.try(&.[name]?)
    end

    def parents
      nil
    end

    def ancestors
      ancestors = [] of Type
      collect_ancestors(ancestors)
      ancestors
    end

    protected def collect_ancestors(ancestors)
      parents.try &.each do |parent|
        ancestors << parent
        parent.collect_ancestors(ancestors)
      end
    end

    # Returns this type's superclass, or `nil` if it doesn't have one
    def superclass : Type?
      nil
    end

    def lookup_defs(name : String, lookup_ancestors_for_new : Bool = false)
      all_defs = [] of Def
      lookup_defs(name, all_defs, lookup_ancestors_for_new)
      all_defs
    end

    def lookup_defs(name : String, all_defs : Array(Def), lookup_ancestors_for_new : Bool? = false)
      self.defs.try &.[name]?.try &.each do |item|
        all_defs << item.def unless all_defs.find(&.same?(item.def))
      end

      is_new = name == "new"
      is_new_or_initialize = is_new || name == "initialize"
      return if is_new_or_initialize && !all_defs.empty?

      if !is_new_or_initialize || (lookup_ancestors_for_new || self.lookup_new_in_ancestors?)
        if is_new
          # For a `new` method we need to do this in case a `new` is defined
          # in a module type
          my_parents = instance_type.parents.try &.map(&.metaclass)
        else
          my_parents = parents
        end

        my_parents.try &.each do |parent|
          old_size = all_defs.size
          parent.lookup_defs(name, all_defs, lookup_ancestors_for_new)

          # Don't lookup new or initialize in parents once we found some defs
          break if is_new_or_initialize && all_defs.size > old_size
        end
      end
    end

    def lookup_defs_without_parents(name : String)
      all_defs = [] of Def
      lookup_defs_without_parents(name, all_defs)
      all_defs
    end

    def lookup_defs_without_parents(name : String, all_defs : Array(Def))
      self.defs.try &.[name]?.try &.each do |item|
        all_defs << item.def unless all_defs.find(&.same?(item.def))
      end
    end

    def lookup_defs_with_modules(name)
      if (list = self.defs.try &.[name]?) && !list.empty?
        return list.map(&.def)
      end

      parents.try &.each do |parent|
        next unless parent.module?

        parent_defs = parent.lookup_defs_with_modules(name)
        return parent_defs unless parent_defs.empty?
      end

      [] of Def
    end

    def lookup_first_def(name, block)
      block = !!block
      defs.try &.[name]?.try &.find(&.yields.==(block)).try &.def
    end

    def has_def?(name)
      has_def_without_parents?(name) || !!parents.try(&.any?(&.has_def?(name)))
    end

    def has_def_without_parents?(name)
      !!defs.try(&.has_key?(name))
    end

    record DefInMacroLookup

    # Looks up a macro with the given name and matching the given args
    # and named_args. Returns:
    # - a `Macro`, if found
    # - `nil`, if not found
    # - `DefInMacroLookup` if not found and a Def was found instead
    #
    # In the case of `DefInMacroLookup`, it means that macros shouldn't
    # be looked up in implicit enclosing scopes such as Object
    # or the Program.
    def lookup_macro(name, args : Array, named_args)
      # Macros are always stored in a type's metaclass
      macros_scope = self.metaclass? ? self : self.metaclass

      if macros = macros_scope.macros.try &.[name]?
        match = macros.find &.matches?(args, named_args)
        return match if match
      end

      # First check if there are defs at this scope with that name.
      # If so, make that a priority in the lookup and don't consider
      # macro matches.
      if has_def_without_parents?(name)
        return DefInMacroLookup.new
      end

      # We need to go through the instance type because of module
      # inclusion and inheritance.
      instance_type.parents.try &.each do |parent|
        # Make sure to start the search in the metaclass if we are a metaclass
        parent = parent.metaclass if self.metaclass?
        parent_macro = parent.lookup_macro(name, args, named_args)
        return parent_macro if parent_macro
      end

      nil
    end

    # Looks up macros with the given name. Returns:
    # - an Array of Macro if found
    # - `nil` if not found
    # - `DefInMacroLookup` if not found and some Defs were found instead
    def lookup_macros(name)
      # Macros are always stored in a type's metaclass
      macros_scope = self.metaclass? ? self : self.metaclass

      if macros = macros_scope.macros.try &.[name]?
        return macros
      end

      if has_def_without_parents?(name)
        return DefInMacroLookup.new
      end

      # We need to go through the instance type because of module
      # inclusion and inheritance.
      instance_type.parents.try &.each do |parent|
        # Make sure to start the search in the metaclass if we are a metaclass
        parent = parent.metaclass if self.metaclass?
        parent_macros = parent.lookup_macros(name)
        return parent_macros if parent_macros
      end

      nil
    end

    def add_including_type(mod)
      raise "BUG: #{self} doesn't implement add_including_type"
    end

    def including_types
      raise "BUG: #{self} doesn't implement including_types"
    end

    # Returns `true` if this type can have instance vars.
    # Primitive types, and types like Reference and Object,
    # can't have instance vars.
    def allows_instance_vars?
      case self
      when program.object, program.value, program.struct,
           program.reference, program.class_type,
           program.number, program.int, program.float,
           program.tuple, program.named_tuple,
           program.pointer, program.static_array,
           program.union, program.enum, program.proc,
           PrimitiveType, GenericReferenceStorageType
        false
      else
        true
      end
    end

    def instance_vars
      raise "BUG: #{self} doesn't implement instance_vars"
    end

    def class_vars
      raise "BUG: #{self} doesn't implement class_vars"
    end

    def all_instance_vars
      if superclass = self.superclass
        superclass.all_instance_vars.merge(instance_vars)
      else
        instance_vars
      end
    end

    def all_class_vars
      all_class_vars = {} of String => MetaTypeVar
      all_class_vars.merge!(class_vars)
      parents.try &.each do |parent|
        all_class_vars.merge!(parent.all_class_vars)
      end
      all_class_vars
    end

    def index_of_instance_var(name)
      if superclass = self.superclass
        index = superclass.index_of_instance_var(name)
        if index
          index
        else
          index = instance_vars.index { |k, v| k == name }
          if index
            superclass.all_instance_vars_count + index
          else
            nil
          end
        end
      else
        instance_vars.index { |k, v| k == name }
      end
    end

    def lookup_instance_var(name : String)
      lookup_instance_var?(name).not_nil!
    end

    def lookup_instance_var?(name : String)
      superclass.try(&.lookup_instance_var?(name)) ||
        instance_vars[name]?
    end

    def lookup_class_var?(name)
      nil
    end

    def lookup_class_var(name)
      raise "BUG: #{self} doesn't implement lookup_class_var"
    end

    def has_instance_var_initializer?(name)
      false
    end

    def all_instance_vars_count
      (superclass.try(&.all_instance_vars_count) || 0) + instance_vars.size
    end

    def lookup_similar_instance_var_name(ivar_name : String)
      case self
      when NonGenericModuleType, GenericClassType, GenericModuleType
        nil
      else
        Levenshtein.find(ivar_name) do |finder|
          self.all_instance_vars.each_key do |name|
            finder.test(name)
          end
        end
      end
    end

    def lookup_instance_var(node : InstanceVar | ReadInstanceVar | MetaVar)
      case self
      when Program
        node.raise "can't use instance variables at the top level"
      when PrimitiveType
        node.raise "can't use instance variables inside primitive types (at #{self})"
      when EnumType
        node.raise "can't use instance variables inside enums (at enum #{self})"
      when .metaclass?
        node.raise "@instance_vars are not yet allowed in metaclasses: use @@class_vars instead"
      when InstanceVarContainer
        lookup_instance_var?(node.name)
      else
        node.raise "BUG: #{self} is not an InstanceVarContainer"
      end
    end

    def add_subclass(subclass)
      raise "BUG: #{self} doesn't implement add_subclass"
    end

    # Replace type parameters in this type with the type parameters
    # of the given *instance* type.
    def replace_type_parameters(instance) : Type
      self
    end

    def depth
      0
    end

    def type_desc
      to_s
    end

    def remove_alias
      self
    end

    def remove_alias_if_simple
      self
    end

    def remove_indirection
      self
    end

    def remove_literal
      self
    end

    def generic_nest
      0
    end

    def double_variadic?
      false
    end

    def splat_index
      nil
    end

    def type_vars
      raise "BUG: #{self} doesn't implement type_vars"
    end

    def unbound?
      false
    end

    def private?
      false
    end

    def private=(set_private)
    end

    # Returns true if *name* if an unbound type variable in this (generic) type.
    def type_var?(name)
      false
    end

    # Returns the type that has to be used in sizeof and instance_sizeof computations
    def sizeof_type
      if struct?
        # In the case of an abstract struct we want to consider the union type
        # of all subtypes (if it's not abstract it's concrete and this will return self)
        virtual_type.remove_indirection
      else
        devirtualize
      end
    end

    def get_instance_var_initializer(name)
      nil
    end

    # Checks whether an exception needs to be raised because of a restriction
    # failure. Only overwritten by literal types (NumberAutocastType and
    # SymbolAutocastType) when they produce an ambiguous call.
    def check_restriction_exception
      nil
    end

    # Yields self and returns true if the block returns a truthy value.
    # UnionType overrides it and yields all types in turn and returns
    # true if for each of them the block returns true.
    def all?(&)
      (yield self) ? true : false
    end

    def to_s(*, generic_args : Bool = true)
      String.build do |io|
        to_s_with_options io, generic_args: generic_args
      end
    end

    def inspect(io : IO) : Nil
      to_s(io)
    end

    def to_s(io : IO) : Nil
      to_s_with_options(io)
    end

    abstract def to_s_with_options(io : IO, skip_union_parens : Bool = false, generic_args : Bool = true, codegen : Bool = false) : Nil

    def pretty_print(pp)
      pp.text to_s
    end
  end

  # A type that has a name and can be inside a namespace.
  # For example, given `class Foo::Bar`, `Foo` is the namespace and `Bar` is the name.
  #
  # There are other types that have a name but it can be deduced from other(s) type(s),
  # so they don't inherit NamedType: a union type, a metaclass, etc.
  abstract class NamedType < Type
    getter namespace : ModuleType
    getter name : String
    getter locations : Array(Location)?
    property doc : String?
    property? private : Bool = false

    def initialize(program, @namespace, @name)
      super(program)
    end

    # Adds a location to this type.
    def add_location(location : Location)
      locations = @locations ||= [] of Location
      locations << location
    end

    getter(types) { {} of String => NamedType }

    def types?
      @types
    end

    def append_full_name(io : IO, codegen : Bool = false) : Nil
      case namespace
      when Program
        # Skip
      when FileModule
        # For codegen we need the filename to distinguish it from other
        # types, but in macros we can't use that because it won't parse
        if codegen
          namespace.to_s_with_options(io, generic_args: false, codegen: codegen)
          io << "::"
        end
      else
        namespace.to_s_with_options(io, generic_args: false, codegen: codegen)
        io << "::"
      end
      io << @name
    end

    def full_name
      String.build { |io| append_full_name(io) }
    end

    def to_s_with_options(io : IO, skip_union_parens : Bool = false, generic_args : Bool = true, codegen : Bool = false) : Nil
      append_full_name(io, codegen: codegen)
    end
  end

  # A Def with some metadata to speed up matching it against
  # a call signature, or against other defs:
  # - max_size: the maximum number of arguments that can be passed to the method
  # - min_size: the minimum number of arguments that can be passed to the method
  # - yields: whether the method has a block
  record DefWithMetadata,
    min_size : Int32,
    max_size : Int32,
    yields : Bool,
    def : Def do
    def self.new(a_def : Def)
      min_size, max_size = a_def.min_max_args_sizes
      new min_size, max_size, !!a_def.block_arity, a_def
    end
  end

  # Kinds of macro hooks (`method_missing` and `finished` are handled separately)
  enum HookKind
    Inherited
    Included
    Extended
    MethodAdded
  end

  # A macro hook
  record Hook, kind : HookKind, macro : Macro

  # The key by which instantiated methods are cached.
  #
  # For example, given:
  #
  # ```
  # def foo(x, y) # def object id: 1234
  #   x + y
  # end
  #
  # foo(1, 2.5)
  # ```
  #
  # When `foo(1)` is analyzed the argument types are [Int32, Float64],
  # and so we instantiate the method with those types (in this case there's
  # no block type nor named argument types). We remember this instantiation
  # with a key that includes the def's object id, argument types, etc., so
  # when a call with the same target Def, argument types, etc., is found
  # we don't need to re-analyze it.
  record DefInstanceKey,
    def_object_id : UInt64,
    arg_types : Array(Type),
    block_type : Type?,
    named_args : Array(NamedArgumentType)?

  # A type that holds Def instantiations (defs where the argument types
  # are fixed). Some types don't support having def instances, for example
  # union types.
  module DefInstanceContainer
    getter(def_instances) { {} of DefInstanceKey => Def }

    def add_def_instance(key, typed_def)
      def_instances[key] = typed_def
    end

    def lookup_def_instance(key)
      def_instances[key]?
    end
  end

  # Base type for all module-like types (modules, classes, structs, enums).
  abstract class ModuleType < NamedType
    getter defs : Hash(String, Array(DefWithMetadata))?
    getter macros : Hash(String, Array(Macro))?
    getter hooks : Array(Hook)?
    getter(parents) { [] of Type }

    def add_def(a_def)
      a_def.owner = self

      item = DefWithMetadata.new(a_def)

      defs = (@defs ||= {} of String => Array(DefWithMetadata))
      list = defs[a_def.name] ||= [] of DefWithMetadata
      list.each_with_index do |ex_item, i|
        case item.compare_strictness(ex_item, self)
        when nil
          # Incompatible defs; do nothing
        when 0
          # The two defs have the same signature so item overrides ex_item.
          list[i] = item
          a_def.previous = ex_item
          a_def.doc ||= ex_item.def.doc
          ex_item.def.next = a_def
          return ex_item.def
        when .< 0
          # item has a new signature, stricter than ex_item.
          list.insert(i, item)
          return nil
        end
      end

      # item has a new signature, less strict than the existing defs with same name.
      list << item

      nil
    end

    def add_macro(a_macro)
      a_macro.owner = self

      case a_macro.name
      when "inherited"
        return add_hook :inherited, a_macro
      when "included"
        return add_hook :included, a_macro
      when "extended"
        return add_hook :extended, a_macro
      when "method_added"
        return add_hook :method_added, a_macro, args_size: 1
      when "method_missing"
        check_macro_param_count(a_macro, 1)
      else
        # normal macro
      end

      macros = (@macros ||= {} of String => Array(Macro))
      array = (macros[a_macro.name] ||= [] of Macro)
      index = array.index { |existing_macro| a_macro.overrides?(existing_macro) }
      if index
        # a_macro has the same signature of an existing macro, we override it.
        a_macro.doc ||= array[index].doc
        array[index] = a_macro
      else
        # a_macro has a new signature, add it with the others.
        array << a_macro
      end
    end

    def add_hook(kind : HookKind, a_macro, args_size = 0)
      check_macro_param_count(a_macro, args_size)
      hooks = @hooks ||= [] of Hook
      hooks << Hook.new(kind, a_macro)
    end

    private def check_macro_param_count(a_macro, expected_count)
      param_count = a_macro.args.size
      if param_count != expected_count
        raise TypeException.new "wrong number of parameters for macro '#{a_macro.name}' (given #{param_count}, expected #{expected_count})"
      end
    end

    def filter_by_responds_to(name)
      has_def?(name) ? self : nil
    end

    def include(mod)
      generic_module = mod.is_a?(GenericModuleInstanceType) ? mod.generic_type : mod

      if generic_module == self
        raise TypeException.new "cyclic include detected"
      end

      generic_module.ancestors.each do |ancestor|
        if ancestor == self || ancestor.is_a?(GenericModuleInstanceType) && ancestor.generic_type == self
          raise TypeException.new "cyclic include detected"
        end
      end

      unless parents.includes?(mod)
        parents.insert 0, mod
        mod.add_including_type(self)
      end
    end

    def type_desc
      "module"
    end
  end

  # A type that can have class variables.
  module ClassVarContainer
    getter(class_vars) { {} of String => MetaTypeVar }

    def class_vars?
      @class_vars
    end

    def lookup_class_var(name)
      lookup_class_var?(name).not_nil!
    end

    def lookup_class_var?(name)
      class_var = @class_vars.try &.[name]?
      return class_var if class_var

      ancestors.each do |ancestor|
        next unless ancestor.is_a?(ClassVarContainer)

        class_var = ancestor.lookup_class_var?(name)
        if class_var
          var = MetaTypeVar.new(name, class_var.type)
          var.owner = self
          var.thread_local = class_var.thread_local?
          var.initializer = class_var.initializer
          var.bind_to(class_var)
          self.class_vars[name] = var
          return var
        end
      end

      nil
    end
  end

  # Temporary type to recompute calls when a subclass is added to a type
  # hierarchy. This shouldn't be needed, because the type hierarchy is
  # now computed in a first pass, but for generic types, instantiations
  # are considered as kind of subclasses, and calls must be recomputed
  # to take them into account (but this should change in the future).
  module SubclassObservable
    def add_subclass_observer(observer)
      observers = (@subclass_observers ||= [] of Call)
      observers << observer
    end

    def remove_subclass_observer(observer)
      @subclass_observers.try &.reject! &.same?(observer)
    end

    def notify_subclass_added
      @subclass_observers.try &.dup.each &.on_new_subclass
    end
  end

  # A type that can have instance var initializers, like
  #
  # ```
  # @x = 1
  # ```
  module InstanceVarInitializerContainer
    class InstanceVarInitializer
      getter name : String
      property value : ASTNode
      getter meta_vars : MetaVars

      def initialize(@name, @value, @meta_vars)
      end
    end

    getter instance_vars_initializers : Array(InstanceVarInitializer)?

    def add_instance_var_initializer(name, value, meta_vars)
      initializers = @instance_vars_initializers ||= [] of InstanceVarInitializer

      # No meta vars means this initializer came from a generic type,
      # so we must type it now that we are defining it in a concrete type
      if !meta_vars && !self.is_a?(GenericType)
        meta_vars = MetaVars.new
        visitor = MainVisitor.new(program, vars: meta_vars, meta_vars: meta_vars)
        visitor.scope = self.metaclass
        value = value.clone
        value.accept visitor
      end

      meta_vars ||= MetaVars.new

      unless self.is_a?(GenericType)
        instance_var = lookup_instance_var(name)
        instance_var.bind_to(value)
      end

      initializer = InstanceVarInitializer.new(name, value, meta_vars)
      initializers << initializer

      program.after_inference_types << self

      initializer
    end

    def has_instance_var_initializer?(name)
      @instance_vars_initializers.try(&.any? { |init| init.name == name }) ||
        ancestors.any?(&.has_instance_var_initializer?(name))
    end

    def get_instance_var_initializer(name)
      match = @instance_vars_initializers.try &.find do |init|
        init.name == name
      end
      return match if match

      ancestors.each do |ancestor|
        match = ancestor.get_instance_var_initializer(name)
        return match if match
      end

      nil
    end
  end

  # A type that can have instance variables.
  module InstanceVarContainer
    getter(instance_vars) { {} of String => MetaTypeVar }
  end

  # A non generic module type.
  class NonGenericModuleType < ModuleType
    include InstanceVarContainer
    include ClassVarContainer
    include SubclassObservable

    def add_including_type(type)
      return if type.unbound?

      including_types = @including_types ||= [] of Type
      including_types.push type

      notify_subclass_added
    end

    def including_types
      if including_types = @including_types
        all_types = Array(Type).new(including_types.size)
        add_to_including_types(all_types)
        program.type_merge_union_of(all_types)
      else
        nil
      end
    end

    def add_to_including_types(all_types)
      if including_types = @including_types
        including_types.each do |including_type|
          add_to_including_types(including_type, all_types)
        end
      end
    end

    def raw_including_types
      @including_types
    end

    def remove_indirection
      if including_types = self.including_types
        including_types.remove_indirection
      else
        self
      end
    end

    def filter_by_responds_to(name)
      including_types.try &.filter_by_responds_to(name)
    end

    def module?
      true
    end

    def add_instance_var_initializer(name, value, meta_vars)
      add_instance_var_initializer @including_types, name, value, meta_vars
    end
  end

  # A module that is related to a file and contains its private defs.
  class FileModule < NonGenericModuleType
    include DefInstanceContainer

    getter(vars) { MetaVars.new }

    def vars?
      @vars
    end

    def metaclass?
      true
    end

    def metaclass
      self
    end
  end

  # Abstract base type for classes and structs
  # (types that can be allocated via the `allocate` method).
  abstract class ClassType < ModuleType
    include DefInstanceContainer
    include SubclassObservable
    include InstanceVarInitializerContainer

    setter metaclass : Type?
    getter superclass : Type?
    getter subclasses = [] of Type
    getter depth : Int32
    property? :abstract; @abstract = false
    property? :struct; @struct = false
    property? can_be_stored = true
    property? lookup_new_in_ancestors = false

    property? extern = false
    property? extern_union = false
    property? packed = false

    def initialize(program, namespace, name, @superclass, add_subclass = true)
      super(program, namespace, name)
      @depth = superclass ? (superclass.depth + 1) : 0
      parents.push superclass if superclass
      force_add_subclass if add_subclass
    end

    def superclass=(@superclass)
      @depth = superclass ? (superclass.depth + 1) : 0
      parents.push superclass if superclass
    end

    def add_subclass(subclass)
      return if subclass.unbound?

      subclasses << subclass
      notify_subclass_added

      superclass = superclass()
      while superclass.is_a?(SubclassObservable)
        superclass.notify_subclass_added
        superclass = superclass.superclass
      end
    end

    def force_add_subclass
      superclass.try &.add_subclass(self)
    end

    def type_desc
      case
      when extern? && extern_union?
        "union"
      when struct?
        "struct"
      else
        "class"
      end
    end
  end

  # A non-generic class type, like String.
  class NonGenericClassType < ClassType
    include InstanceVarContainer
    include ClassVarContainer

    protected def initialize_metaclass(metaclass)
      metaclass.add_def Def.new("allocate", body: Primitive.new("allocate"))
    end

    def virtual_type
      if leaf? && !abstract?
        self
      elsif struct? && abstract? && !leaf?
        virtual_type!
      elsif struct?
        self
      else
        virtual_type!
      end
    end

    def virtual_type!
      @virtual_type ||= VirtualType.new(program, self)
    end

    def class?
      true
    end
  end

  # Base type for primitive types like Bool and Char.
  abstract class PrimitiveType < ClassType
    include ClassVarContainer

    # Returns the number of bytes this type occupies in memory.
    getter bytes : Int32

    def initialize(program, namespace, name, superclass, @bytes : Int32)
      super(program, namespace, name, superclass)
      self.struct = true
    end

    def abstract?
      false
    end
  end

  class BoolType < PrimitiveType
  end

  class CharType < PrimitiveType
  end

  class IntegerType < PrimitiveType
    getter rank : Int32
    getter kind : NumberKind

    def initialize(program, namespace, name, superclass, bytes, @rank, @kind : NumberKind)
      super(program, namespace, name, superclass, bytes)
    end

    def signed?
      @rank % 2 == 1
    end

    def unsigned?
      @rank % 2 == 0
    end

    def bits
      8 * (2 ** normal_rank)
    end

    def normal_rank
      (@rank - 1) // 2
    end

    def range
      case kind
      when .i8?
        {Int8::MIN, Int8::MAX}
      when .i16?
        {Int16::MIN, Int16::MAX}
      when .i32?
        {Int32::MIN, Int32::MAX}
      when .i64?
        {Int64::MIN, Int64::MAX}
      when .i128?
        {Int128::MIN, Int128::MAX}
      when .u8?
        {UInt8::MIN, UInt8::MAX}
      when .u16?
        {UInt16::MIN, UInt16::MAX}
      when .u32?
        {UInt32::MIN, UInt32::MAX}
      when .u64?
        {UInt64::MIN, UInt64::MAX}
      when .u128?
        {UInt128::MIN, UInt128::MAX}
      else
        raise "Bug: called 'range' for non-integer literal"
      end
    end

    # Returns true if every _finite_ member of this type is also exactly
    # representable in the *other_type*. Used to define legal autocasts of
    # number-typed variables
    def subset_of?(other_type : IntegerType) : Bool
      self_min, self_max = self.range
      other_min, other_max = other_type.range
      other_min <= self_min && self_max <= other_max
    end

    # :ditto:
    def subset_of?(other_type : FloatType) : Bool
      # Float32 mantissa has 23 bits,
      # Float64 mantissa has 52 bits
      case kind
      when .i8?, .u8?, .i16?, .u16?
        # Less than 23 bits, so convertible to Float32 and Float64 without precision loss
        true
      when .i32?, .u32?
        # Less than 52 bits, so convertible to Float64 without precision loss
        other_type.kind.f64?
      else
        false
      end
    end
  end

  class FloatType < PrimitiveType
    getter rank : Int32

    def initialize(program, namespace, name, superclass, bytes, @rank)
      super(program, namespace, name, superclass, bytes)
    end

    def kind
      @bytes == 4 ? NumberKind::F32 : NumberKind::F64
    end

    def range
      case kind
      when .f32?
        {Float32::MIN, Float32::MAX}
      when .f64?
        {Float64::MIN, Float64::MAX}
      else
        raise "Bug: called 'range' for non-float literal"
      end
    end

    # Returns true if every _finite_ member of this type is also exactly
    # representable in the *other_type*. Used to define legal autocasts of
    # number-typed variables.
    def subset_of?(other_type : IntegerType) : Bool
      false
    end

    # :ditto:
    def subset_of?(other_type : FloatType) : Bool
      kind.f32? && other_type.kind.f64?
    end
  end

  class SymbolType < PrimitiveType
  end

  class NilType < PrimitiveType
  end

  class NoReturnType < NamedType
    # NoReturn can be assigned to any other type (because it never will)
    def implements?(other_type)
      true
    end
  end

  class VoidType < NamedType
  end

  abstract class AutocastType < Type
    # The most exact match type, or the first match otherwise
    getter match : Type?

    # All matches. It's nil if `@match` is an exact match.
    @all_matches : Set(Type)?

    def set_exact_match(type)
      @match = type
      @all_matches = nil
    end

    def add_match(type)
      if (match = @match) && match != type
        all_matches = @all_matches
        if all_matches.nil?
          all_matches = @all_matches = Set(Type).new
          all_matches << match
        end
        all_matches << type
      else
        @match = type
      end
    end

    def exact_match?
      literal.type == @match
    end

    def remove_literal
      literal.type
    end

    def check_restriction_exception
      if all_matches = @all_matches
        literal_value =
          case literal
          when NumberLiteral, SymbolLiteral
            literal.to_s
          else
            literal.type.to_s
          end
        literal.raise "ambiguous call, implicit cast of #{literal_value} matches all of #{all_matches.join(", ")}"
      end
    end
  end

  # Type for a number literal: it has the specific type of the number literal
  # but can also match other types (like ints and floats) if the literal
  # fits in those types.
  class NumberAutocastType < AutocastType
    # The literal associated with this type
    getter literal : ASTNode

    def initialize(program, @literal)
      super(program)
    end

    def to_s_with_options(io : IO, skip_union_parens : Bool = false, generic_args : Bool = true, codegen : Bool = false) : Nil
      io << @literal.type
    end
  end

  # Type for a symbol literal: it has the specific type of the symbol literal (SymbolType)
  # but can also match enums if their members match the symbol's name.
  class SymbolAutocastType < AutocastType
    # The literal associated with this type
    getter literal : SymbolLiteral

    def initialize(program, @literal)
      super(program)
    end

    def to_s_with_options(io : IO, skip_union_parens : Bool = false, generic_args : Bool = true, codegen : Bool = false) : Nil
      io << @literal.type
    end
  end

  # Any thing that can be passed as a generic type variable.
  #
  # For example, in:
  #
  # ```
  # StaticArray(UInt8, 256)
  # ```
  #
  # there are two type vars: UInt8 (the type) and 256 (a number literal).
  #
  # These are the only things that are currently accepted as type variables,
  # but this is kept as `Type | ASTNode` to make it easier to add new nodes
  # in the future.
  alias TypeVar = Type | ASTNode

  # A non-instantiated generic type, like Array(T), Hash(K, V)
  # or Enumerable(T).
  module GenericType
    include InstanceVarContainer

    # The type variable names (K and V in Hash).
    getter type_vars : Array(String)

    # The index of the `*` in the type variables.
    property splat_index : Int32?

    # Is it `**`? Currently only NamedTuple is.
    property? double_variadic = false

    # All generic type instantiations of this generic type, indexed
    # by the type variables.
    protected getter(generic_types) { {} of Array(TypeVar) => Type }

    # Returns an array of all instantiations of this generic type.
    # NamedTupleType overrides this because it doesn't use positional type
    # arguments.
    def instantiated_types
      generic_types.values
    end

    def each_instantiated_type(&)
      if types = @generic_types
        types.each_value { |type| yield type }
      end
    end

    # Returns a TypeParameter relative to this type
    def type_parameter(name) : TypeParameter
      type_parameters = @type_parameters ||= {} of String => TypeParameter
      type_parameters[name] ||= TypeParameter.new(program, self, name)
    end

    def instantiate(type_vars)
      if (instance = generic_types[type_vars]?)
        return instance
      end

      instance_type_vars = {} of String => ASTNode
      type_var_index = 0
      self.type_vars.each_with_index do |name, index|
        if splat_index == index
          types = [] of TypeVar
          (type_vars.size - (self.type_vars.size - 1)).times do
            types << type_vars[type_var_index]
            type_var_index += 1
          end
          var = Var.new(name, program.tuple_of(types))
          var.bind_to(var)
          instance_type_vars[name] = var
        else
          type_var = type_vars[type_var_index]
          case type_var
          when Type
            var = Var.new(name, type_var)
            var.bind_to var
            instance_type_vars[name] = var
          when ASTNode
            instance_type_vars[name] = type_var
          end
          type_var_index += 1
        end
      end

      instance = self.new_generic_instance(program, self, instance_type_vars)
      generic_types[type_vars] = instance

      if instance.is_a?(GenericClassInstanceType) && !instance.superclass
        instance.superclass = instantiated_generic_superclass(instance)
      end

      self.instance_vars.each do |name, ivar|
        ivar_type = ivar.type
        if ivar_type.is_a?(TypeSplat)
          # Consider the case of @x : *T
          instance_var_type = ivar_type.splatted_type.replace_type_parameters(instance)
          unless instance_var_type.is_a?(TupleInstanceType)
            raise TypeException.new "expected splatted type to be a tuple type, not #{instance_var_type}"
          end
        else
          instance_var_type = ivar_type.replace_type_parameters(instance)
        end
        instance.declare_instance_var(name, instance_var_type, ivar.annotations)
      end

      run_instance_vars_initializers self, self, instance

      instance.after_initialize

      # Notify that a subclass/instance of self was added
      self.notify_subclass_added if self.is_a?(SubclassObservable)

      # Notify parents that an instance was added
      notify_parents_subclass_added(self)

      instance
    end

    def notify_parents_subclass_added(type)
      type.parents.try &.each do |parent|
        parent.notify_subclass_added if parent.is_a?(SubclassObservable)
        notify_parents_subclass_added parent
      end
    end

    getter inherited : Array(Type)?

    def add_inherited(type)
      inherited = @inherited ||= [] of Type
      inherited << type
    end

    def add_instance_var_initializer(name, value, meta_vars)
      initializer = super

      # Make sure to type the initializer for existing instantiations
      each_instantiated_type do |instance|
        run_instance_var_initializer(initializer, instance)
      end

      @inherited.try &.each do |inherited|
        run_instance_var_initializer(initializer, inherited)
        if inherited.is_a?(GenericClassType)
          inherited.add_instance_var_initializer(name, value, meta_vars)
        end
      end

      initializer
    end

    def run_instance_vars_initializers(real_type, type : GenericClassType | ClassType, instance)
      if superclass = type.superclass
        run_instance_vars_initializers(real_type, superclass, instance)
      end

      type.instance_vars_initializers.try &.each do |initializer|
        run_instance_var_initializer initializer, instance
      end
    end

    def run_instance_vars_initializers(real_type, type, instance)
      # Nothing
    end

    def run_instance_var_initializer(initializer, instance : GenericClassInstanceType | NonGenericClassType)
      return if instance.unbound?

      meta_vars = MetaVars.new
      visitor = MainVisitor.new(program, vars: meta_vars, meta_vars: meta_vars)
      visitor.scope = instance.metaclass
      value = initializer.value.clone
      value.accept visitor
      instance_var = instance.lookup_instance_var(initializer.name)

      # Check if automatic cast can be done
      if instance_var.type != value.type && value.supports_autocast?(!@program.has_flag?("no_number_autocast"))
        if casted_value = MainVisitor.check_automatic_cast(@program, value, instance_var.type)
          value = casted_value
        end
      end

      instance_var.bind_to(value)
      instance.add_instance_var_initializer(initializer.name, value, meta_vars)
    end

    def run_instance_var_initializer(initializer, instance)
      # Nothing
    end

    def instantiated_generic_superclass(instance)
      superclass = self.superclass.not_nil!
      if superclass.is_a?(GenericClassInstanceType)
        superclass = superclass.replace_type_parameters(instance)
      end
      superclass
    end

    def type_var?(name)
      type_vars.includes? name
    end
  end

  # An un-bound type parameter of a generic type.

  # For example, given:
  #
  # ```
  # class Bar(T) < Foo(T, Int32)
  # end
  # ```
  #
  # when we solve `Foo(T, Int32)` we'll find Foo, and
  # then instantiate it with `T` being the type parameter
  # `T` of `Bar`, and `Int32` a regular type variable.
  #
  # Similarly, when including a generic module inside a generic
  # type, type parameters will be used.
  #
  # ```
  # class Baz(T)
  #   include Enumerable(T) # <- this is TypeParameter T of Foo
  # end
  # ```
  #
  # When instantiating Bar(T) in the first example, for example
  # doing `Bar(Char)`, superclasses and including modules will
  # have type parameters replaced with types given in the instantiation,
  # so `Foo(T, Int32)` will become `Foo(Char, Int32)`.
  class TypeParameter < Type
    # Returns the type that owns this type parameter
    getter owner

    # Returns the name of this type parameter
    getter name

    def initialize(program, @owner : GenericType, @name : String)
      super(program)
    end

    def replace_type_parameters(instance)
      node = solve(instance)
      if node.is_a?(Var)
        node.type
      else
        node.raise "can't declare variable with #{node.class_desc}"
      end
    end

    def solve(instance)
      if instance.is_a?(GenericInstanceType) && instance.generic_type == @owner
        ancestor = instance
      else
        ancestor = instance.ancestors.find { |ancestor| ancestor.is_a?(GenericInstanceType) && ancestor.generic_type == owner }.as(GenericInstanceType)
      end

      ancestor.type_vars[name]
    end

    def unbound?
      true
    end

    def to_s_with_options(io : IO, skip_union_parens : Bool = false, generic_args : Bool = true, codegen : Bool = false) : Nil
      io << @name
    end
  end

  # A splatted type inside an inherited generic class or included generic module.
  #
  # For example, given:
  #
  # ```
  # class Foo(T)
  #   include Bar(Union(*T))
  # end
  # ```
  #
  # the `T` in the included type will be a TypeParameter, but we can't
  # splat it yet (expands the types behind T) until we know T. We mark
  # this as a TypeSplat of the type parameter T.
  #
  # When instantiating Foo, T will be replaced with the instantiated type
  # and this TypeSplat will check that it's a tuple type and append its
  # types to the final type variables.
  class TypeSplat < Type
    getter splatted_type

    def initialize(program, @splatted_type : TypeParameter)
      super(program)
    end

    def to_s_with_options(io : IO, skip_union_parens : Bool = false, generic_args : Bool = true, codegen : Bool = false) : Nil
      io << '*' << @splatted_type
    end
  end

  # A generic module type, like Enumerable(T).
  class GenericModuleType < ModuleType
    include GenericType
    include ClassVarContainer

    def initialize(program, namespace, name, @type_vars)
      super(program, namespace, name)
    end

    def module?
      true
    end

    def can_be_stored?
      false
    end

    def type_desc
      "generic module"
    end

    def add_including_type(type)
      including_types = @including_types ||= [] of Type
      including_types.push type
    end

    def raw_including_types
      @including_types
    end

    def new_generic_instance(program, generic_type, type_vars)
      GenericModuleInstanceType.new program, generic_type, type_vars
    end

    def add_instance_var_initializer(name, value, meta_vars)
      add_instance_var_initializer @including_types, name, value, meta_vars
    end

    def to_s_with_options(io : IO, skip_union_parens : Bool = false, generic_args : Bool = true, codegen : Bool = false) : Nil
      super
      if generic_args
        io << '('
        type_vars.each_with_index do |type_var, i|
          io << ", " if i > 0
          io << '*' if i == splat_index
          type_var.to_s(io)
        end
        io << ')'
      end
    end
  end

  # A generic class type, like Array(T).
  class GenericClassType < ClassType
    include GenericType
    include ClassVarContainer

    def initialize(program, namespace, name, superclass, @type_vars : Array(String), add_subclass = true)
      super(program, namespace, name, superclass, add_subclass)
    end

    def class?
      true
    end

    def can_be_stored?
      false
    end

    def new_generic_instance(program, generic_type, type_vars)
      GenericClassInstanceType.new program, generic_type, nil, type_vars
    end

    protected def initialize_metaclass(metaclass)
      metaclass.add_def Def.new("allocate", body: Primitive.new("allocate"))
    end

    def type_desc
      struct? ? "generic struct" : "generic class"
    end

    def including_types
      instances = instantiated_types
      subclasses.each do |subclass|
        if subclass.is_a?(GenericClassType)
          subtypes = subclass.including_types
          instances << subtypes if subtypes
        else
          instances << subclass
        end
      end
      program.union_of instances
    end

    def remove_indirection
      if including_types = self.including_types
        including_types.remove_indirection
      else
        self
      end
    end

    def to_s_with_options(io : IO, skip_union_parens : Bool = false, generic_args : Bool = true, codegen : Bool = false) : Nil
      super
      if generic_args
        io << '('
        type_vars.each_with_index do |type_var, i|
          io << ", " if i > 0
          io << '*' if i == splat_index
          type_var.to_s(io)
        end
        io << ')'
      end
    end
  end

  # An instantiated generic type (like Array(String) or Enumerable(Int32)).
  #
  # To represent generic superclasses and generic included modules,
  # GenericInstanceType is also used. For example, in:
  #
  # ```
  # class Foo(T); end
  #
  # class Bar(T) < Foo(T); end
  # ```
  #
  # The GenericClassType `Bar(T)` will have a GenericClassInstanceType
  # `Foo(T)` as a superclass, with `T` being a `TypeParameter`. We can't
  # simply have the generic type `Foo(T)` be the superclass (maybe in this
  # particular example yes) but we could also have:
  #
  # ```
  # class Foo(X, Y); end
  #
  # class Bar(T) < Foo(Int32, T); end
  # ```
  #
  # In that case `Foo(X, Y)` is not quite the superclass, because
  # the superclass has a fixed type `Int32` as the first parameter.
  abstract class GenericInstanceType < Type
    getter generic_type : GenericType
    getter type_vars : Hash(String, ASTNode)

    delegate :annotation, :annotations, :all_annotations, to: generic_type

    def initialize(program, @generic_type, @type_vars)
      super(program)
    end

    def class_var_owner
      generic_type.class_var_owner
    end

    def parents
      generic_type.parents.try &.map do |parent|
        parent.replace_type_parameters(self)
      end
    end

    def replace_type_parameters(instance)
      new_type_vars = [] of TypeVar

      type_vars.each_with_index do |(name, node), index|
        if node.is_a?(Var)
          type = node.type

          case type
          when TypeParameter
            replacement = type.solve(instance)
            if replacement.is_a?(Var)
              type_var = replacement.type
            else
              type_var = replacement
            end
          when TypeSplat
            type_var = type.splatted_type.replace_type_parameters(instance)
          else
            type_var = type.replace_type_parameters(instance)
          end

          if splat_index == index
            if type_var.is_a?(TupleInstanceType)
              new_type_vars.concat(type_var.tuple_types)
            else
              node.raise "expected type to be a tuple type, not #{type_var}"
            end
          elsif type.is_a?(TypeSplat)
            if type_var.is_a?(TupleInstanceType)
              new_type_vars.concat(type_var.tuple_types)
            else
              node.raise "expected type to be a tuple type, not #{type_var}"
            end
          else
            new_type_vars << type_var
          end
        else
          new_type_vars << node
        end
      end

      generic_type.instantiate(new_type_vars)
    end

    def implements?(other_type : GenericInstanceType)
      if generic_type == other_type.generic_type
        type_vars.each do |name, type_var|
          other_type_var = other_type.type_vars[name]
          if type_var.is_a?(Var) && other_type_var.is_a?(Var)
            # type vars are invariant here; (Named)TupleInstanceType have their own logic
            return super unless type_var.type.devirtualize == other_type_var.type.devirtualize
          else
            return super unless type_var == other_type_var
          end
        end
        return true
      end

      super
    end

    def implements?(other_type)
      other_type = other_type.remove_alias
      super || generic_type.implements?(other_type)
    end

    def has_in_type_vars?(type)
      type_vars.each_value do |type_var|
        if type_var.is_a?(Var)
          return true if type_var.type.includes_type?(type) || type_var.type.has_in_type_vars?(type)
        end
      end
      false
    end

    def unbound?
      type_vars.each_value do |type_var|
        if type_var.is_a?(Var)
          return true if type_var.type.unbound?
        end
      end
      false
    end

    def to_s_with_options(io : IO, skip_union_parens : Bool = false, generic_args : Bool = true, codegen : Bool = false) : Nil
      generic_type.append_full_name(io)
      if generic_args
        io << '('
        first = true
        type_vars.each_with_index do |(_, type_var), i|
          if type_var.is_a?(Var)
            if i == splat_index
              tuple = type_var.type.as(TupleInstanceType)
              tuple.tuple_types.each do |tuple_type|
                io << ", " unless first
                first = false
                tuple_type = tuple_type.devirtualize unless codegen
                tuple_type.to_s_with_options(io, codegen: codegen)
              end
            else
              io << ", " unless first
              first = false
              type_var_type = type_var.type
              type_var_type = type_var_type.devirtualize unless codegen
              type_var_type.to_s_with_options(io, skip_union_parens: true, codegen: codegen)
            end
          else
            io << ", " unless first
            first = false
            type_var.to_s(io)
          end
        end
        io << ')'
      end
    end
  end

  # An instantiated generic type, like Array(String).
  class GenericClassInstanceType < GenericInstanceType
    include InstanceVarContainer
    include InstanceVarInitializerContainer
    include DefInstanceContainer
    include SubclassObservable

    property superclass : Type?
    getter subclasses = [] of Type
    getter generic_nest : Int32

    def initialize(program, generic_type, @superclass, type_vars, generic_nest = nil)
      super(program, generic_type, type_vars)
      @generic_nest = generic_nest || (1 + @type_vars.values.max_of { |node| node.type?.try(&.generic_nest) || 0 })
    end

    def after_initialize
      superclass.not_nil!.add_subclass(self)
      ancestors.each do |ancestor|
        ancestor.add_including_type(self) if ancestor.is_a?(GenericModuleInstanceType)
      end
    end

    def add_subclass(subclass)
      return if subclass.unbound?

      subclasses << subclass
      notify_subclass_added

      superclass = superclass()
      while superclass.is_a?(SubclassObservable)
        superclass.notify_subclass_added
        superclass = superclass.superclass
      end
    end

    def virtual_type
      if generic_type.leaf? && !abstract?
        self
      elsif struct? && abstract? && !generic_type.leaf?
        virtual_type!
      elsif struct?
        self
      else
        virtual_type!
      end
    end

    def virtual_type!
      @virtual_type ||= VirtualType.new(program, self)
    end

    delegate depth, defs, superclass, macros, abstract?, struct?,
      type_desc, namespace, lookup_new_in_ancestors?,
      splat_index, double_variadic?, to: @generic_type

    def filter_by_responds_to(name)
      @generic_type.filter_by_responds_to(name) ? self : nil
    end

    def class?
      true
    end

    getter(metaclass) { GenericClassInstanceMetaclassType.new(self.program, self) }
  end

  # An instantiated generic module, like Enumerable(Int32).
  class GenericModuleInstanceType < GenericInstanceType
    include InstanceVarContainer
    include InstanceVarInitializerContainer
    include DefInstanceContainer
    include SubclassObservable

    getter generic_nest : Int32

    def initialize(program, generic_type, type_vars, generic_nest = nil)
      super(program, generic_type, type_vars)
      @generic_nest = generic_nest || (1 + @type_vars.values.max_of { |node| node.type?.try(&.generic_nest) || 0 })
    end

    def after_initialize
      ancestors.each do |ancestor|
        ancestor.add_including_type(self) if ancestor.is_a?(GenericModuleInstanceType)
      end
    end

    def virtual_type
      self
    end

    delegate leaf?, depth, defs, macros,
      type_desc, namespace, lookup_new_in_ancestors?,
      splat_index, double_variadic?, to: @generic_type

    def add_including_type(type)
      return if type.unbound?

      @generic_type.add_including_type(type)

      including_types = @including_types ||= [] of Type
      including_types.push type

      notify_subclass_added
    end

    def including_types
      if including_types = @including_types
        all_types = Array(Type).new(including_types.size)
        add_to_including_types(all_types)
        program.type_merge_union_of(all_types)
      else
        nil
      end
    end

    def add_to_including_types(all_types)
      if including_types = @including_types
        including_types.each do |including_type|
          add_to_including_types(including_type, all_types)
        end
      end
    end

    def raw_including_types
      @including_types
    end

    def remove_indirection
      if including_types = self.including_types
        including_types.remove_indirection
      else
        self
      end
    end

    def filter_by_responds_to(name)
      including_types.try &.filter_by_responds_to(name)
    end

    def module?
      true
    end

    getter(metaclass) { GenericModuleInstanceMetaclassType.new(self.program, self) }
  end

  # The non-instantiated Pointer(T) type.
  class PointerType < GenericClassType
    def new_generic_instance(program, generic_type, type_vars)
      PointerInstanceType.new program, generic_type, program.struct, type_vars
    end

    def type_desc
      "generic struct"
    end
  end

  # An instantiated pointer type, like Pointer(Int32).
  class PointerInstanceType < GenericClassInstanceType
    def var
      type_vars["T"]
    end

    def element_type
      var.type
    end

    def type_desc
      "struct"
    end
  end

  # The non-instantiated StaticArray(T, N) type.
  class StaticArrayType < GenericClassType
    def new_generic_instance(program, generic_type, type_vars)
      n = type_vars["N"]

      unless n.is_a?(Var) && n.type.is_a?(TypeParameter)
        unless n.is_a?(NumberLiteral)
          raise TypeException.new "can't instantiate StaticArray(T, N) with N = #{n.type} (N must be an integer)"
        end

        value = n.value.to_i
        if value < 0
          raise TypeException.new "can't instantiate StaticArray(T, N) with N = #{value} (N must be positive)"
        end
      end

      StaticArrayInstanceType.new program, generic_type, program.struct, type_vars
    end
  end

  # An instantiated static array type, like StaticArray(UInt8, 256)
  class StaticArrayInstanceType < GenericClassInstanceType
    def var
      type_vars["T"]
    end

    def size
      type_vars["N"]
    end

    def element_type
      var.type
    end
  end

  # The non-instantiated Proc(*T, R) type.
  class ProcType < GenericClassType
    @splat_index = 0
    @struct = true

    def instantiate(type_vars)
      if (instance = generic_types[type_vars]?)
        return instance
      end

      types = type_vars.map do |type_var|
        unless type_var.is_a?(Type)
          type_var.raise "argument to Proc must be a type, not #{type_var}"
        end
        type_var
      end
      return_type = types.pop

      # Transform Proc(*T, Void) to Proc(*T, Nil) as Void has
      # only a special meaning in Pointer(Void)
      if return_type == @program.void
        return_type = @program.nil_type
      end

      instance = ProcInstanceType.new(program, types, return_type)
      generic_types[type_vars] = instance
      instance.after_initialize
      instance
    end

    def can_be_stored?
      false
    end

    def new_generic_instance(program, generic_type, type_vars)
      raise "BUG: ProcType#new_generic_instance shouldn't be invoked"
    end

    def type_desc
      "function"
    end
  end

  # An instantiated proc type like Proc(Int32, Char)
  class ProcInstanceType < GenericClassInstanceType
    getter arg_types : Array(Type)
    getter return_type : Type

    def initialize(program, @arg_types, @return_type)
      t_var = Var.new("T", program.tuple_of(@arg_types))
      t_var.bind_to t_var

      r_var = Var.new("R", @return_type)
      r_var.bind_to r_var

      super(program, program.proc, program.struct, {"T" => t_var, "R" => r_var} of String => ASTNode)
    end

    def struct?
      true
    end

    def implements?(other_type : ProcInstanceType)
      return true if self == other_type
      return false unless self.arg_types == other_type.arg_types

      # - Proc(..., NoReturn) can be cast to Proc(..., T)
      # - Anything can be cast to Proc(..., Void)
      # - Anything can be cast to Proc(..., Nil)
      self.return_type.no_return? || other_type.return_type.void? || other_type.return_type.nil_type?
    end

    def to_s_with_options(io : IO, skip_union_parens : Bool = false, generic_args : Bool = true, codegen : Bool = false) : Nil
      io << "Proc("
      arg_types.each do |type|
        type = type.devirtualize unless codegen
        type.to_s_with_options(io, codegen: codegen)
        io << ", "
      end
      return_type = self.return_type
      return_type = return_type.devirtualize unless codegen
      return_type.to_s_with_options(io, codegen: codegen)
      io << ')'
    end
  end

  # The non-instantiated type Tuple(*T).
  class TupleType < GenericClassType
    @splat_index = 0
    @struct = true

    def instantiate(type_vars)
      if (instance = generic_types[type_vars]?)
        return instance
      end

      types = type_vars.map do |type_var|
        unless type_var.is_a?(Type)
          type_var.raise "argument to Tuple must be a type, not #{type_var}"
        end
        type_var
      end
      instance = TupleInstanceType.new(program, types)
      generic_types[type_vars] = instance
      instance.after_initialize
      instance
    end

    def new_generic_instance(program, generic_type, type_vars)
      raise "BUG: TupleType#new_generic_instance shouldn't be invoked"
    end

    def type_desc
      "tuple"
    end
  end

  # An instantiated tuple type, like Tuple(Char, Int32).
  class TupleInstanceType < GenericClassInstanceType
    alias Index = Int32 | Range(Int32, Int32)

    getter tuple_types : Array(Type)

    def initialize(program, @tuple_types)
      generic_nest = 1 + (@tuple_types.empty? ? 0 : @tuple_types.max_of(&.generic_nest))
      var = Var.new("T", self)
      var.bind_to var
      super(program, program.tuple, program.struct,
        {"T" => var} of String => ASTNode, generic_nest)
    end

    def tuple_indexer(index)
      indexers = @tuple_indexers ||= {} of Index => Def
      tuple_indexer(indexers, index)
    end

    def tuple_metaclass_indexer(index)
      indexers = @tuple_metaclass_indexers ||= {} of Index => Def
      tuple_indexer(indexers, index)
    end

    def size
      tuple_types.size
    end

    private def tuple_indexer(indexers, index)
      indexers[index] ||= begin
        body = index == -1 ? NilLiteral.new : TupleIndexer.new(index)
        indexer = Def.new("[]", [Arg.new("index")], body)
        indexer.owner = self
        indexer
      end
    end

    def implements?(other_type : TupleInstanceType)
      return true if self == other_type
      return false unless self.size == other_type.size

      tuple_types.zip(other_type.tuple_types) do |self_tuple_type, other_tuple_type|
        return false unless self_tuple_type.implements?(other_tuple_type)
      end

      true
    end

    def var
      type_vars["T"]
    end

    def has_in_type_vars?(type)
      tuple_types.any? { |tuple_type| tuple_type.includes_type?(type) || tuple_type.has_in_type_vars?(type) }
    end

    def replace_type_parameters(instance)
      new_tuple_types = [] of Type
      tuple_types.each do |tuple_type|
        if tuple_type.is_a?(TypeSplat)
          type = tuple_type.splatted_type.replace_type_parameters(instance)
          if type.is_a?(TupleInstanceType)
            new_tuple_types.concat(type.tuple_types)
          else
            raise "expected type to be a tuple type, not #{type}"
          end
        else
          new_tuple_types << tuple_type.replace_type_parameters(instance)
        end
      end
      program.tuple_of(new_tuple_types)
    end

    def unbound?
      tuple_types.any? &.unbound?
    end

    def to_s_with_options(io : IO, skip_union_parens : Bool = false, generic_args : Bool = true, codegen : Bool = false) : Nil
      io << "Tuple("
      @tuple_types.join(io, ", ") do |tuple_type|
        tuple_type = tuple_type.devirtualize unless codegen
        tuple_type.to_s_with_options(io, skip_union_parens: true, codegen: codegen)
      end
      io << ')'
    end

    def type_desc
      "tuple"
    end
  end

  # The non-instantiated NamedTuple(**T) type.
  class NamedTupleType < GenericClassType
    @struct = true
    @double_variadic = true
    @instantiations = {} of Array(NamedArgumentType) => Type

    def instantiated_types
      @instantiations.values
    end

    def each_instantiated_type(&)
      @instantiations.each_value { |type| yield type }
    end

    def instantiate(type_vars)
      raise "can't instantiate NamedTuple type yet"
    end

    def instantiate_named_args(entries : Array(NamedArgumentType))
      @instantiations[entries] ||= NamedTupleInstanceType.new(program, entries)
    end

    def new_generic_instance(program, generic_type, type_vars)
      raise "BUG: NamedTupleType#new_generic_instance shouldn't be invoked"
    end

    def type_desc
      "named tuple"
    end
  end

  # An instantiated named tuple type, like NamedTuple(x: Int32, y: Char).
  class NamedTupleInstanceType < GenericClassInstanceType
    getter entries

    def initialize(program, @entries : Array(NamedArgumentType))
      generic_nest = 1 + (@entries.empty? ? 0 : @entries.max_of(&.type.generic_nest))
      var = Var.new("T", self)
      var.bind_to var
      super(program, program.named_tuple, program.struct,
        {"T" => var} of String => ASTNode, generic_nest)
    end

    def name_index(name)
      @entries.index(&.name.==(name))
    end

    def name_type(name)
      @entries.find!(&.name.==(name)).type
    end

    def tuple_indexer(index)
      indexers = @tuple_indexers ||= {} of Int32 => Def
      tuple_indexer(indexers, index)
    end

    def tuple_metaclass_indexer(index)
      indexers = @tuple_metaclass_indexers ||= {} of Int32 => Def
      tuple_indexer(indexers, index)
    end

    private def tuple_indexer(indexers, index)
      indexers[index] ||= begin
        body = index == -1 ? NilLiteral.new : TupleIndexer.new(index)
        indexer = Def.new("[]", [Arg.new("index")], body)
        indexer.owner = self
        indexer
      end
    end

    def implements?(other_type : NamedTupleInstanceType)
      return true if self == other_type
      return false unless self.size == other_type.size

      self_entries = self.entries.sort_by &.name
      other_entries = other_type.entries.sort_by &.name

      self_entries.zip(other_entries) do |self_entry, other_entry|
        return false unless self_entry.name == other_entry.name
        return false unless self_entry.type.implements?(other_entry.type)
      end

      true
    end

    def size
      entries.size
    end

    def var
      type_vars["T"]
    end

    def replace_type_parameters(instance)
      new_entries = entries.map do |entry|
        NamedArgumentType.new(entry.name, entry.type.replace_type_parameters(instance))
      end
      program.named_tuple_of(new_entries)
    end

    def unbound?
      entries.any? &.type.unbound?
    end

    def has_in_type_vars?(type)
      entries.any? { |entry| entry.type.includes_type?(type) || entry.type.has_in_type_vars?(type) }
    end

    def to_s_with_options(io : IO, skip_union_parens : Bool = false, generic_args : Bool = true, codegen : Bool = false) : Nil
      io << "NamedTuple("
      @entries.join(io, ", ") do |entry|
        Symbol.quote_for_named_argument(io, entry.name)
        io << ": "
        entry_type = entry.type
        entry_type = entry_type.devirtualize unless codegen
        entry_type.to_s_with_options(io, skip_union_parens: true, codegen: codegen)
      end
      io << ')'
    end

    def type_desc
      "tuple"
    end
  end

  # The non-instantiated ReferenceStorage(T) type.
  class GenericReferenceStorageType < GenericClassType
    @struct = true

    def new_generic_instance(program, generic_type, type_vars)
      type_param = self.type_vars.first
      t = type_vars[type_param].type

      unless t.is_a?(TypeParameter) || (t.class? && !t.struct?)
        raise TypeException.new "Can't instantiate ReferenceStorage(#{type_param}) with #{type_param} = #{t} (#{type_param} must be a reference type)"
      end

      ReferenceStorageType.new program, t, self, type_param
    end
  end

  class ReferenceStorageType < GenericClassInstanceType
    getter reference_type : Type

    def initialize(program, @reference_type, generic_type, type_param)
      t_var = Var.new("T", @reference_type)
      t_var.bind_to t_var

      super(program, generic_type, program.value, {type_param => t_var} of String => ASTNode)
    end
  end

  # A lib type, like `lib LibC`.
  class LibType < ModuleType
    getter link_annotations : Array(LinkAnnotation)?
    property? used = false
    property call_convention : LLVM::CallConvention?

    def add_link_annotation(link_annotation : LinkAnnotation)
      link_annotations = @link_annotations ||= [] of LinkAnnotation
      link_annotations << link_annotation unless link_annotations.includes?(link_annotation)
    end

    def metaclass
      self
    end

    def lookup_var(name)
      a_def = lookup_first_def(name, false)
      return nil unless a_def

      body = a_def.body
      return nil unless body.is_a?(Primitive) && body.name == "external_var_get"

      a_def
    end

    def type_desc
      "lib"
    end

    def wasm_import_module
      (@link_annotations.try &.find &.wasm_import_module).try &.wasm_import_module
    end
  end

  # A `type` (typedef) type inside a `lib` declaration.
  class TypeDefType < NamedType
    include DefInstanceContainer

    getter typedef : Type

    def initialize(program, namespace, name, @typedef)
      super(program, namespace, name)
    end

    delegate remove_typedef, pointer?, defs,
      macros, reference_like?, parents, lookup_instance_var, to: typedef

    def remove_indirection
      self
    end

    def type_def_type?
      true
    end

    def type_desc
      "type def"
    end
  end

  # An alias type.
  class AliasType < NamedType
    getter? value_processed = false
    property! aliased_type : Type
    getter? simple

    def initialize(program, namespace, name, @value : ASTNode)
      super(program, namespace, name)
      @simple = true
    end

    delegate lookup_defs, lookup_defs_with_modules, lookup_first_def,
      lookup_macro, lookup_macros, to: aliased_type

    def lookup_name(name)
      process_value
      @aliased_type.try(&.lookup_name(name))
    end

    def remove_alias
      process_value
      if aliased_type = @aliased_type
        aliased_type.remove_alias
      else
        @simple = false
        self
      end
    end

    def remove_alias_if_simple
      process_value
      @simple ? remove_alias : self
    end

    def remove_indirection
      process_value
      if aliased_type = @aliased_type
        aliased_type.remove_indirection
      else
        @simple = false
        self
      end
    end

    def can_be_stored?
      process_value
      if aliased_type = @aliased_type
        aliased_type.remove_alias.can_be_stored?
      else
        true
      end
    end

    def process_value
      return if @value_processed
      @value_processed = true
      @aliased_type = namespace.lookup_type(@value,
        allow_typeof: false,
        find_root_generic_type_parameters: false)
    end

    def includes_type?(other)
      remove_indirection.includes_type?(other)
    end

    def type_desc
      "alias"
    end
  end

  # An instantiated enum type.
  #
  # TODO: right now this is not properly modeled. Ideally there
  # should be EnumType and EnumInstanceType, where EnumType would
  # be `Enum(T)` and given:
  #
  # ```
  # enum Foo : Int32
  #   # ...
  # end
  # ```
  #
  # we'd have:
  #
  # ```
  # enum Foo < Enum(Int32)
  # end
  # ```
  #
  # but right now that's not the case.
  class EnumType < ModuleType
    include DefInstanceContainer
    include ClassVarContainer

    getter base_type : IntegerType
    property? flags = false

    def initialize(program, namespace, name, @base_type)
      super(program, namespace, name)

      add_def Def.new("value", [] of Arg, Primitive.new("enum_value", @base_type))
      metaclass.as(ModuleType).add_def Def.new("new", [Arg.new("value", restriction: Path.global(@base_type.to_s))], Primitive.new("enum_new", self))
    end

    def parents
      @parents ||= [program.enum] of Type
    end

    def add_constant(name, value)
      const_exp = NumberLiteral.new(value.to_s, base_type.kind)
      const_exp.type = self
      types[name] = const = Const.new(program, self, name, const_exp)
      program.const_initializers << const
      const
    end

    def lookup_new_in_ancestors?
      true
    end

    def find_member(name)
      name = name.underscore
      types.each do |member_name, member|
        if name == member_name.underscore
          return member.as(Const)
        end
      end
      nil
    end

    def type_desc
      "enum"
    end
  end

  class AnnotationType < NamedType
    def type_desc
      "annotation"
    end
  end

  # A metaclass type, that results from invoking `.class` on a type.
  #
  # For example `String.class` is the metaclass of `String`, and it's
  # the type of `String` (the type of `"foo"` is `String`, the type of
  # `String` is `String.class`).
  #
  # This metaclass represents only the metaclass of non-generic types.
  class MetaclassType < ClassType
    include ClassVarContainer

    getter instance_type : Type

    def initialize(program, @instance_type : Type, super_class = nil, name = nil)
      super_class ||= if instance_type.is_a?(ClassType) && instance_type.superclass
                        instance_type.superclass.not_nil!.metaclass
                      elsif instance_type.is_a?(EnumType)
                        program.enum.metaclass
                      else
                        program.class_type
                      end
      unless name
        if instance_type.module?
          name = "#{@instance_type}:Module"
        else
          name = "#{@instance_type}.class"
        end
      end
      super(program, program, name, super_class)
    end

    def metaclass
      program.class_type
    end

    delegate abstract?, generic_nest, lookup_new_in_ancestors?,
      type_var?, to: instance_type

    def class_var_owner
      instance_type.class_var_owner
    end

    def virtual_type
      instance_type.virtual_type.metaclass
    end

    def virtual_type!
      instance_type.virtual_type!.metaclass
    end

    def remove_typedef
      if instance_type.is_a?(TypeDefType)
        return instance_type.remove_typedef.metaclass
      end
      self
    end

    def replace_type_parameters(instance)
      instance_type.replace_type_parameters(instance).metaclass
    end

    def to_s_with_options(io : IO, skip_union_parens : Bool = false, generic_args : Bool = true, codegen : Bool = false) : Nil
      io << @name
    end

    def type_desc
      "metaclass"
    end
  end

  # The metaclass of a generic class instance type, like `Array(String).class`
  class GenericClassInstanceMetaclassType < Type
    include DefInstanceContainer

    getter instance_type : Type

    def initialize(program, @instance_type)
      super(program)
    end

    def metaclass
      program.class_type
    end

    def add_subclass(subclass)
      # Nothing
    end

    def superclass
      instance_type.superclass.try(&.metaclass) || program.class_type
    end

    def parents
      generic_type.parents.try &.map do |parent|
        parent.replace_type_parameters(instance_type)
      end
    end

    def generic_type
      instance_type.generic_type.metaclass
    end

    def implements?(other_type : Type)
      other_type = other_type.remove_alias
      super || generic_type.implements?(other_type)
    end

    def replace_type_parameters(instance_type)
      self.instance_type.replace_type_parameters(instance_type).metaclass
    end

    def virtual_type
      instance_type.virtual_type.metaclass
    end

    def virtual_type!
      instance_type.virtual_type!.metaclass
    end

    delegate defs, macros, to: generic_type
    delegate type_vars, abstract?, generic_nest, lookup_new_in_ancestors?, to: instance_type

    def class_var_owner
      instance_type.class_var_owner
    end

    def filter_by_responds_to(name)
      if generic_type.filter_by_responds_to(name)
        self
      else
        nil
      end
    end

    def to_s_with_options(io : IO, skip_union_parens : Bool = false, generic_args : Bool = true, codegen : Bool = false) : Nil
      instance_type.to_s(io)
      io << ".class"
    end

    def type_desc
      "metaclass"
    end
  end

  # The metaclass of a generic module instance type, like `Enumerable(Int32).class`
  class GenericModuleInstanceMetaclassType < Type
    include DefInstanceContainer

    getter instance_type : Type

    def initialize(program, @instance_type)
      super(program)
    end

    def metaclass
      program.class_type
    end

    def add_subclass(subclass)
      # Nothing
    end

    def parents
      generic_type.parents.try &.map do |parent|
        parent.replace_type_parameters(instance_type)
      end
    end

    def generic_type
      instance_type.generic_type.metaclass
    end

    def implements?(other_type : Type)
      other_type = other_type.remove_alias
      super || generic_type.implements?(other_type)
    end

    def replace_type_parameters(instance_type)
      self.instance_type.replace_type_parameters(instance_type).metaclass
    end

    delegate defs, macros, to: generic_type
    delegate type_vars, generic_nest, lookup_new_in_ancestors?, to: instance_type

    def class_var_owner
      instance_type.class_var_owner
    end

    def to_s_with_options(io : IO, skip_union_parens : Bool = false, generic_args : Bool = true, codegen : Bool = false) : Nil
      instance_type.to_s(io)
      io << ".class"
    end

    def type_desc
      "metaclass"
    end
  end

  # A type that consists of other types, like unions and virtual types.
  module MultiType
    def concrete_types
      types = [] of Type
      each_concrete_type { |type| types << type }
      types
    end

    def union_types
      union_types = program.type_merge_union_of(concrete_types)
      union_types || base_type
    end
  end

  # The non-instantiated Union(*T) type.
  class GenericUnionType < GenericClassType
    @splat_index = 0
    @struct = true

    def instantiate(type_vars, type_merge_union_of = false)
      types = type_vars.map do |type_var|
        unless type_var.is_a?(Type)
          type_var.raise "argument to Union must be a type, not #{type_var}"
        end
        # There's no need for types to be virtual because at the end
        # `type_merge` will take care of that.
        # The benefit is that if one writes `Union(T)`, that becomes exactly T
        # and not T+ (which might lead to some inconsistencies).
        type_var.devirtualize.as(Type)
      end

      if type_merge_union_of
        program.type_merge_union_of(types) || program.no_return
      else
        program.type_merge(types) || program.no_return
      end
    end

    def new_generic_instance(program, generic_type, type_vars)
      raise "BUG: GenericUnionType#new_generic_instance shouldn't be invoked"
    end

    def type_desc
      "union"
    end
  end

  # Base class for instantiated union types.
  abstract class UnionType < Type
    include MultiType

    getter union_types : Array(Type)

    def initialize(program, @union_types)
      super(program)
    end

    def parents
      @parents ||= [program.value] of Type
    end

    def superclass
      program.value
    end

    def generic_type
      program.union
    end

    def metaclass
      @metaclass ||= GenericClassInstanceMetaclassType.new(program, self)
    end

    def generic_nest
      union_types.max_of &.generic_nest
    end

    def includes_type?(other_type)
      union_types.any? &.includes_type?(other_type)
    end

    def filter_by_responds_to(name)
      filtered_types = union_types.compact_map &.filter_by_responds_to(name)
      program.type_merge_union_of filtered_types
    end

    def each_concrete_type(&)
      union_types.each do |type|
        if type.is_a?(VirtualType) || type.is_a?(VirtualMetaclassType)
          type.each_concrete_type do |concrete_type|
            yield concrete_type
          end
        elsif type.is_a?(ModuleType) || type.is_a?(GenericModuleInstanceType)
          _type = type.remove_indirection
          if _type.responds_to?(:concrete_types)
            # do to recursion uncaptured block method
            # we need to use concrete_types.each
            # instead of each_concrete_types
            _type.concrete_types.each do |concrete_type|
              yield concrete_type
            end
          else
            yield _type
          end
        else
          yield type
        end
      end
    end

    def virtual_type
      if union_types.any? { |t| t.virtual_type != t }
        program.type_merge(union_types.map(&.virtual_type)).not_nil!
      else
        self
      end
    end

    def implements?(other_type : Type)
      other_type = other_type.remove_alias
      self == other_type || union_types.all?(&.implements?(other_type))
    end

    def replace_type_parameters(instance)
      new_union_types = Array(Type).new(union_types.size)
      union_types.each do |type|
        case type
        when TypeParameter
          replacement = type.solve(instance)
          if replacement.is_a?(Var)
            new_union_types << replacement.type
          else
            raise TypeException.new "expected type, not #{replacement.class_desc}"
          end
        when TypeSplat
          type_var = type.splatted_type.replace_type_parameters(instance)
          if type_var.is_a?(TupleInstanceType)
            new_union_types.concat(type_var.tuple_types)
          else
            raise TypeException.new "expected tuple type, not #{type_var}"
          end
        else
          new_union_types << type.replace_type_parameters(instance)
        end
      end
      program.type_merge(new_union_types) || program.no_return
    end

    def unbound?
      union_types.any? &.unbound?
    end

    def all?(&)
      union_types.all? { |union_type| yield union_type }
    end

    def to_s_with_options(io : IO, skip_union_parens : Bool = false, generic_args : Bool = true, codegen : Bool = false) : Nil
      io << '(' unless skip_union_parens
      union_types = @union_types
      # Make sure to put Nil at the end
      if nil_type_index = @union_types.index(&.nil_type?)
        union_types = @union_types.dup
        union_types << union_types.delete_at(nil_type_index)
      end
      union_types.join(io, " | ") do |type|
        type = type.devirtualize unless codegen
        type.to_s_with_options(io, codegen: codegen)
      end
      io << ')' unless skip_union_parens
    end

    def type_desc
      "union"
    end
  end

  # A union type that has two types: Nil and another Reference type.
  # Can be represented as a maybe-null pointer where the type id
  # of the type that is not nil is known at compile time.
  class NilableType < UnionType
    def initialize(program, not_nil_type)
      super(program, [program.nil, not_nil_type] of Type)
    end

    def not_nil_type
      @union_types.last
    end
  end

  # A union type that has Nil and other reference-like types.
  # Can be represented as a maybe-null pointer but the type id is
  # not known at compile time.
  class NilableReferenceUnionType < UnionType
  end

  # A union type that doesn't have nil, and all types are reference-like.
  # Can be represented as a never-null pointer.
  class ReferenceUnionType < UnionType
  end

  # A union type of nil and a single function type.
  class NilableProcType < UnionType
    def initialize(program, proc_type)
      super(program, [program.nil, proc_type] of Type)
    end

    def proc_type
      @union_types.last.remove_typedef.as(ProcInstanceType)
    end
  end

  # A union type that doesn't match any of the previous definitions,
  # so it can contain Nil with primitive types, or Reference types with
  # primitives types.
  # Must be represented as a union.
  class MixedUnionType < UnionType
  end

  # A constant inside a type. For example, given:
  #
  # ```
  # class Foo
  #   A = 1
  # end
  # ```
  #
  # `A` will be a Const type with a value of 1.
  #
  # A constant is a type because when we do `Foo::A` we do a regular
  # type lookup, which might result in a constant, so constants are
  # saved under a type types like any other type.
  class Const < NamedType
    property value : ASTNode
    property fake_def : Def?
    property? used = false
    property? visited = false

    # Was this const's value cleaned up by CleanupTransformer yet?
    property? cleaned_up = false

    # Is this constant accessed with pointerof(...)?
    property? pointer_read = false

    property visitor : MainVisitor?

    def initialize(program, namespace, name, @value)
      super(program, namespace, name)
    end

    def type_desc
      "constant"
    end
  end

  module VirtualTypeLookup
    def filter_by_responds_to(name)
      filtered = virtual_lookup(base_type).filter_by_responds_to(name)
      return filtered.virtual_type if filtered

      result = [] of Type
      collect_filtered_by_responds_to(name, base_type, result)
      program.type_merge_union_of(result)
    end

    def collect_filtered_by_responds_to(name, type, result)
      type.subclasses.each do |subclass|
        unless subclass.is_a?(GenericType) || subclass.unbound?
          filtered = virtual_lookup(subclass).filter_by_responds_to(name)
          if filtered
            result << virtual_lookup(subclass).virtual_type
            next
          end
        end

        collect_filtered_by_responds_to(name, subclass, result)
      end
    end
  end

  # A virtual type represents a type or any of its subclasses. It's created
  # automatically by the compiler when a type is used in a generic argument
  # and it either has subtypes, or it's abstract. A virtual type never exists
  # for a non-abstract type that doesn't have subtypes.
  #
  # A virtual type is denoted, internally, with a '+' sign following the type.
  #
  # ```
  # class Foo
  # end
  #
  # class Bar < Foo
  # end
  #
  # # Here the compiler actually makes this be [] of Foo+, so the array
  # # can actually hold a Foo or a Bar, transparently.
  # ary = [] of Foo
  #
  # # Here the compiler leaves it as [] of Bar, because Bar has no subclasses.
  # another = [] of Bar
  # ```
  class VirtualType < Type
    include MultiType
    include DefInstanceContainer
    include VirtualTypeLookup
    include InstanceVarContainer
    include ClassVarContainer

    # Given `Foo+`, this returns `Foo`.
    getter base_type : Type

    def initialize(program, @base_type)
      super(program)
    end

    delegate leaf?, superclass, lookup_first_def, lookup_defs,
      lookup_defs_with_modules, lookup_instance_var, lookup_instance_var?,
      index_of_instance_var, lookup_macro, lookup_macros, all_instance_vars,
      abstract?, implements?, ancestors, struct?,
      type_var?, unbound?, to: base_type

    def remove_indirection
      if struct?
        union_types
      else
        self
      end
    end

    def metaclass
      @metaclass ||= VirtualMetaclassType.new(program, self)
    end

    def each_concrete_type(&)
      subtypes.each do |subtype|
        yield subtype unless subtype.abstract?
      end
    end

    def subtypes
      subtypes = [] of Type
      collect_subtypes(base_type, subtypes)
      subtypes
    end

    def subtypes(type)
      subtypes = [] of Type
      type.subclasses.each do |subclass|
        collect_subtypes subclass, subtypes
      end
      subtypes
    end

    def collect_subtypes(type, subtypes)
      subtypes << type unless type.is_a?(GenericType) || type.unbound?
      type.subclasses.each do |subclass|
        collect_subtypes subclass, subtypes
      end
    end

    def lookup_class_var?(name)
      class_var = @class_vars.try &.[name]?
      return class_var if class_var

      class_var = base_type.lookup_class_var?(name)
      if class_var
        var = MetaTypeVar.new(name, class_var.type)
        var.owner = self
        var.thread_local = class_var.thread_local?
        var.initializer = class_var.initializer
        var.bind_to(class_var)
        self.class_vars[name] = var
        return var
      end

      nil
    end

    def all_class_vars
      all_class_vars = {} of String => MetaTypeVar
      @class_vars.try { |v| all_class_vars.merge!(v) }
      all_class_vars.merge!(base_type.all_class_vars)
      all_class_vars
    end

    def replace_type_parameters(instance)
      base_type.replace_type_parameters(instance).virtual_type
    end

    def to_s_with_options(io : IO, skip_union_parens : Bool = false, generic_args : Bool = true, codegen : Bool = false) : Nil
      base_type.to_s(io)
      io << '+'
    end

    def name
      to_s
    end
  end

  class VirtualMetaclassType < Type
    include MultiType
    include DefInstanceContainer
    include VirtualTypeLookup
    include ClassVarContainer

    getter instance_type : VirtualType

    def initialize(program, @instance_type)
      super(program)
    end

    def metaclass
      program.class_type
    end

    def parents
      @parents ||= [instance_type.superclass.try(&.metaclass) || program.class_type] of Type
    end

    def leaf?
      instance_type.leaf?
    end

    # Given `Foo+.class` returns `Foo` (not `Foo.class`)
    delegate base_type, to: instance_type

    delegate lookup_first_def, to: instance_type.metaclass

    def replace_type_parameters(instance)
      base_type.replace_type_parameters(instance).virtual_type.metaclass
    end

    def each_concrete_type(&)
      instance_type.subtypes.each do |type|
        yield type.metaclass
      end
    end

    def lookup_class_var?(name)
      class_var = @class_vars.try &.[name]?
      return class_var if class_var

      class_var = base_type.instance_type.lookup_class_var?(name)
      if class_var
        var = MetaTypeVar.new(name, class_var.type)
        var.owner = self
        var.thread_local = class_var.thread_local?
        var.initializer = class_var.initializer
        var.bind_to(class_var)
        self.class_vars[name] = var
        return var
      end

      nil
    end

    def implements?(other_type)
      base_type.metaclass.implements?(other_type)
    end

    def to_s_with_options(io : IO, skip_union_parens : Bool = false, generic_args : Bool = true, codegen : Bool = false) : Nil
      instance_type.to_s_with_options(io, codegen: codegen)
      io << ".class"
    end

    def type_desc
      "metaclass"
    end
  end
end

private def add_to_including_types(type : Crystal::GenericType, all_types)
  type.each_instantiated_type do |instance|
    # Unbound generic types are not concrete types
    next if instance.unbound?

    # Abstract types also shouldn't form the union of including types
    next if instance.abstract?

    all_types << instance unless all_types.includes?(instance)
  end
  type.subclasses.each do |subclass|
    add_to_including_types subclass, all_types
  end
end

private def add_to_including_types(type : Crystal::NonGenericModuleType | Crystal::GenericModuleInstanceType, all_types)
  type.add_to_including_types(all_types)
end

private def add_to_including_types(type, all_types)
  virtual_type = type.virtual_type
  all_types << virtual_type unless all_types.includes?(virtual_type)
end

private def add_instance_var_initializer(including_types, name, value, meta_vars)
  including_types.try &.each do |type|
    case type
    when Crystal::Program, Crystal::FileModule
      # skip
    when Crystal::NonGenericModuleType
      type.add_instance_var_initializer(name, value, meta_vars)
    when Crystal::NonGenericClassType
      type.add_instance_var_initializer(name, value, meta_vars)
    when Crystal::GenericClassType
      type.add_instance_var_initializer(name, value, meta_vars)
    when Crystal::GenericModuleType
      type.add_instance_var_initializer(name, value, meta_vars)
    else
      # skip
    end
  end
end
