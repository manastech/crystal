require "../types"

class Crystal::Type
  # Searches the type that corresponds to the given *node*, relative
  # to `self`.
  #
  # This method handles AST nodes in the type grammar:
  #
  # - Path: Foo::Bar::Baz
  # - Union: T | U
  # - Metaclass: T.class
  # - Generic: Foo(T)
  # - ProcNotation: T -> U
  # - TypeOf: typeof(...)
  # - Self: self
  #
  # Passing other AST nodes will raise an exception.
  #
  # *self_type* is the type that will be used when `self` is encountered
  # in the node.
  #
  # If *allow_typeof* is `false`, this method raises if there's a typeof
  # in the given node.
  #
  # If *free_vars* is given, when resolving a Path, types will be first searched
  # in the given Hash.
  #
  # If *find_root_generic_type_parameters* is `true` (the default), type parameters
  # relative to `self_type` will be found. If `false`, they won't be found.
  #
  # For example, given:
  #
  # ```
  # class Foo
  #   class Bar(T)
  #   end
  #
  #   class Baz
  #   end
  # end
  # ```
  #
  # If `self` is `Foo` and `Bar(Baz)` is given, the result will be `Foo::Bar(Baz)`.
  def lookup_type(node : ASTNode, self_type = self.instance_type, allow_typeof = true, free_vars : Hash(String, TypeVar)? = nil, find_root_generic_type_parameters = true) : Type
    TypeLookup.new(self, self_type, true, allow_typeof, free_vars, find_root_generic_type_parameters).lookup(node).not_nil!
  end

  # Similar to `lookup_type`, but returns `nil` if a type can't be found.
  def lookup_type?(node : ASTNode, self_type = self.instance_type, allow_typeof = true, free_vars : Hash(String, TypeVar)? = nil, raise = false, raise_typeof = raise, find_root_generic_type_parameters = true) : Type?
    TypeLookup.new(self, self_type, raise, allow_typeof, free_vars, find_root_generic_type_parameters, raise_typeof: raise_typeof).lookup(node)
  end

  # Similar to `lookup_type`, but the result might also be an ASTNode, for example when
  # looking `N` relative to a StaticArray.
  def lookup_type_var(node : Path, free_vars : Hash(String, TypeVar)? = nil, find_root_generic_type_parameters = true, remove_alias = true) : Type | ASTNode
    TypeLookup.new(self, self.instance_type, true, false, free_vars, find_root_generic_type_parameters, remove_alias).lookup_type_var(node).not_nil!
  end

  # Similar to `lookup_type_var`, but might return `nil`.
  def lookup_type_var?(node : Path, free_vars : Hash(String, TypeVar)? = nil, raise = false, find_root_generic_type_parameters = true) : Type | ASTNode | Nil
    TypeLookup.new(self, self.instance_type, raise, false, free_vars, find_root_generic_type_parameters).lookup_type_var?(node)
  end

  private struct TypeLookup
    def initialize(@root : Type, @self_type : Type, @raise : Bool, @allow_typeof : Bool, @free_vars : Hash(String, TypeVar)? = nil, @find_root_generic_type_parameters = true, @remove_alias = true, @raise_typeof : Bool = raise)
      @in_generic_args = 0

      # If we are looking types inside a non-instantiated generic type,
      # for example Hash(K, V), we want to find K and V as type parameters
      # of that type.
      if @find_root_generic_type_parameters && root.is_a?(GenericType)
        free_vars ||= {} of String => TypeVar
        root.type_vars.each do |type_var|
          free_vars[type_var] ||= root.type_parameter(type_var)
        end
        @free_vars = free_vars
      end
    end

    delegate program, to: @root

    def lookup(node : Path)
      # A Path might have a type set.
      # This is at least done in AbstractDefChecker when we replace type
      # parameters with concrete types.
      if type = node.type?
        return type
      end

      type_var = lookup_type_var?(node)

      case type_var
      when Const
        if @raise
          node.raise "#{type_var} is not a type, it's a constant"
        else
          nil
        end
      when Type
        type_var
      else
        if @raise
          raise_undefined_constant(node)
        else
          nil
        end
      end
    end

    def lookup_type_var(node : Path)
      type_var = lookup_type_var?(node)
      return type_var if type_var

      if @raise
        raise_undefined_constant(node)
      else
        nil
      end
    end

    def lookup_type_var?(node : Path)
      # Check if the Path begins with a free variable
      if !node.global? && (free_var = @free_vars.try &.[node.names.first]?)
        if node.names.size == 1
          return free_var
        elsif free_var.is_a?(Type)
          type = free_var.lookup_path(node.names[1..-1], lookup_in_namespace: false, location: node.location)
        end
      else
        type = @root.lookup_path(node)
      end

      if type.is_a?(Type)
        if @in_generic_args == 0 && type.is_a?(AliasType) && !type.aliased_type?
          if type.value_processed?
            node.raise "infinite recursive definition of alias #{type}"
          else
            type.process_value
          end
        end
        type = type.remove_alias_if_simple if @remove_alias
      end

      type
    end

    def lookup(node : Union)
      types = node.types.map do |ident|
        type = lookup(ident)
        return if !@raise && !type
        type = type.not_nil!

        check_type_can_be_stored(ident, type, "can't use #{type} in unions")

        type.virtual_type
      end
      program.type_merge(types)
    end

    def lookup(node : Metaclass)
      type = lookup(node.name)
      return if !@raise && !type
      type = type.not_nil!

      type.virtual_type.metaclass.virtual_type
    end

    def lookup(node : Generic)
      type = lookup(node.name)
      return if !@raise && !type
      type = type.not_nil!

      instance_type = type

      case instance_type
      when NamedTupleType
        unless node.type_vars.empty?
          node.raise "can only instantiate NamedTuple with named arguments"
        end

        named_args = node.named_args
        entries = Array(NamedArgumentType).new(named_args.try(&.size) || 0)
        named_args.try &.each do |named_arg|
          subnode = named_arg.value

          if subnode.is_a?(NumberLiteral)
            subnode.raise "can't use number as type for NamedTuple"
          end

          type = in_generic_args { lookup(subnode) }
          return if !@raise && !type
          type = type.not_nil!

          check_type_can_be_stored(subnode, type, "can't use #{type} as a generic type argument")
          entries << NamedArgumentType.new(named_arg.name, type.virtual_type)
        end

        begin
          return instance_type.instantiate_named_args(entries)
        rescue ex : Crystal::CodeError
          node.raise "instantiating #{node}", inner: ex if @raise
        end
      when GenericType
        if instance_type.splat_index
          if node.named_args
            node.raise "can only use named arguments with NamedTuple"
          end

          min_needed = instance_type.type_vars.size - 1
          if node.type_vars.size < min_needed
            node.wrong_number_of "type vars", instance_type, node.type_vars.size, "#{min_needed}+"
          end
        else
          if node.named_args
            node.raise "can only use named arguments with NamedTuple"
          end

          if instance_type.type_vars.size != node.type_vars.size
            node.wrong_number_of "type vars", instance_type, node.type_vars.size, instance_type.type_vars.size
          end
        end
      else
        node.raise "#{instance_type} is not a generic type, it's a #{instance_type.type_desc}"
      end

      type_vars = Array(TypeVar).new(node.type_vars.size + 1)
      node.type_vars.each do |type_var|
        case type_var
        when NumberLiteral
          type_vars << type_var
          next
        when Splat
          type = in_generic_args { lookup(type_var.exp) }
          return if !@raise && !type
          type = type.not_nil!

          splat_type = type
          case splat_type
          when TupleInstanceType
            type_vars.concat splat_type.tuple_types
          when TypeParameter
            # Consider the case of *T, where T is a type parameter
            type_vars << TypeSplat.new(@root.program, splat_type)
          else
            return if !@raise

            type_var.raise "can only splat tuple type, not #{splat_type}"
          end
          next
        when SizeOf, InstanceSizeOf, AlignOf, InstanceAlignOf, OffsetOf
          next unless @raise

          type_var.raise "can't use #{type_var} as a generic type argument"
        end

        # Check the case of T resolving to a number
        if type_var.is_a?(Path)
          type = in_generic_args { lookup_type_var(type_var) }
          case type
          when Const
            program.check_deprecated_constant(type, type_var)
            interpreter = MathInterpreter.new(@root)
            begin
              num = interpreter.interpret(type.value)
              type_vars << NumberLiteral.new(num)
            rescue ex : Crystal::CodeError
              type_var.raise "expanding constant value for a number value", inner: ex
            end
            next
          when NumberLiteral
            type_vars << type
            next
          end
        end

        type = in_generic_args { lookup(type_var) }
        return if (!@raise || !@raise_typeof) && !type
        type = type.not_nil!

        case instance_type
        when GenericUnionType, PointerType, StaticArrayType, TupleType, ProcType
          check_type_can_be_stored(type_var, type, "can't use #{type} as a generic type argument")
        end

        type_vars << type.virtual_type
      end

      begin
        if instance_type.is_a?(GenericUnionType) && type_vars.any?(TypeSplat)
          # In the case of `Union(*T)`, we don't need to instantiate the union right
          # now because it will just return `*T`, but what we want to expand the
          # union types only when the type is instantiated.
          # TODO: check that everything is a type
          MixedUnionType.new(@root.program, type_vars.map(&.as(Type)))
        else
          instance_type.as(GenericType).instantiate(type_vars)
        end
      rescue ex : Crystal::CodeError
        node.raise "instantiating #{node}", inner: ex if @raise
      end
    end

    def lookup(node : ProcNotation)
      types = [] of Type
      if inputs = node.inputs
        inputs.each do |input|
          if input.is_a?(Splat)
            type = in_generic_args { lookup(input.exp) }
            return if !@raise && !type
            type = type.not_nil!

            a_type = type
            if a_type.is_a?(TupleInstanceType)
              types.concat(a_type.tuple_types)
            else
              if @raise
                input.exp.raise "can only splat tuple type, not #{a_type}"
              else
                return
              end
            end
          else
            type = in_generic_args { lookup(input) }
            return if !@raise && !type
            type = type.not_nil!

            check_type_can_be_stored(input, type, "can't use #{type} as proc argument")

            types << type.virtual_type
          end
        end
      end

      if output = node.output
        type = in_generic_args { lookup(output) }
        return if !@raise && !type
        type = type.not_nil!

        check_type_can_be_stored(output, type, "can't use #{type} as proc return type")

        types << type.virtual_type
      else
        types << program.void
      end

      program.proc_of(types)
    end

    def lookup(node : Self)
      if @self_type.is_a?(Program)
        node.raise "there's no self in this scope"
      end

      if (self_type = @self_type).is_a?(GenericType) && (free_vars = @free_vars)
        # Only instantiate self type with available free variables
        params = self_type.type_vars.map do |type_var|
          free_var = free_vars[type_var]?
          if free_var
            self_type.type_parameter(type_var).as(TypeVar)
          else
            return @self_type.virtual_type
          end
        end
        self_type.instantiate(params)
      else
        @self_type.virtual_type
      end
    end

    def lookup(node : TypeOf)
      unless @allow_typeof
        if @raise_typeof
          node.raise "can't use 'typeof' here"
        else
          return
        end
      end

      meta_vars = MetaVars{"self" => MetaVar.new("self", @self_type)}
      visitor = MainVisitor.new(program, meta_vars)
      expressions = node.expressions.clone
      begin
        expressions.each &.accept visitor
      rescue ex : Crystal::CodeError
        node.raise "typing typeof", inner: ex
      end
      program.type_merge expressions
    end

    def lookup(node : Splat)
      splat_type = in_generic_args { lookup(node.exp) }
      case splat_type
      when TypeParameter
        # Consider the case of *T, where T is a type parameter
        TypeSplat.new(@root.program, splat_type)
      else
        return if !@raise

        node.raise "can only splat tuple type, not #{splat_type}"
      end
    end

    def lookup(node : Underscore)
      node.raise "can't use underscore as generic type argument" if @raise
    end

    def lookup(node : ASTNode)
      raise "BUG: unknown node in TypeLookup: #{node} #{node.class_desc}"
    end

    def raise_undefined_constant(node)
      check_cant_infer_generic_type_parameter(@root, node)
      node.raise_undefined_constant(@root)
    end

    def check_cant_infer_generic_type_parameter(scope, node)
      if scope.is_a?(MetaclassType) && (instance_type = scope.instance_type).is_a?(GenericType)
        first_name = node.names.first
        if instance_type.type_vars.includes?(first_name)
          node.raise "can't infer the type parameter #{first_name} for the #{instance_type.type_desc} #{instance_type}. Please provide it explicitly"
        end
      end
    end

    def check_type_can_be_stored(ident, type, message)
      Crystal.check_type_can_be_stored(ident, type, message)
    end

    def in_generic_args(&)
      @in_generic_args += 1
      value = yield
      @in_generic_args -= 1
      value
    end
  end
end
