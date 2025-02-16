module Crystal
  class Program
    def define_new_methods(new_expansions)
      # Here we complete the body of `self.new` methods
      # created from `initialize` methods.
      new_expansions.each do |original, expanded|
        expanded.fill_body_from_initialize(original.owner)
      end

      # We also need to define empty `new` methods for types
      # that don't have any `initialize` methods.
      define_default_new(self)
      file_modules.each_value do |file_module|
        define_default_new(file_module)
      end

      # Once we are done with the expansions we mark `initialize` methods
      # without an explicit visibility as `protected`.
      new_expansions.each do |original, expanded|
        original.visibility = Visibility::Protected if original.visibility.public?
      end
    end

    def define_default_new(type)
      type.types?.try &.each_value do |type|
        define_default_new_single(type)
      end
    end

    def define_default_new_single(type)
      check = case type
              when self.object, self.value, self.number, self.int, self.float,
                   self.struct, self.enum, self.tuple, self.proc
                false
              when NonGenericClassType, GenericClassType
                true
              else
                false
              end

      if check
        type = type.as(ModuleType)
        defer_overload_order = @program.has_flag?("preview_overload_order")

        self_initialize_methods = type.lookup_defs_without_parents("initialize")
        self_new_methods = type.metaclass.lookup_defs_without_parents("new")

        # Check to see if a default `new` needs to be defined
        initialize_methods = type.lookup_defs("initialize", lookup_ancestors_for_new: true)
        new_methods = type.metaclass.lookup_defs("new", lookup_ancestors_for_new: true)
        has_new_or_initialize = !initialize_methods.empty? || !new_methods.empty?

        if !has_new_or_initialize
          # Add self.new
          new_method = Def.argless_new(type)
          type.metaclass.as(ModuleType).add_def(new_method, ordered: !defer_overload_order)

          # Also add `initialize`, so `super` in a subclass
          # inside an `initialize` will find this one
          type.add_def Def.argless_initialize(type), ordered: !defer_overload_order
        end

        # Check to see if a type doesn't define `initialize`
        # nor `self.new()` on its own. In this case, when we
        # search a `new` method and we can't find it in this
        # type we must search in the superclass. We record
        # this information here instead of having to do this
        # check every time.
        has_self_initialize_methods = !self_initialize_methods.empty?
        if !has_self_initialize_methods
          is_generic = type.is_a?(GenericClassType)
          inherits_from_generic = type.ancestors.any?(GenericClassInstanceType)
          if is_generic || inherits_from_generic
            has_default_self_new = self_new_methods.any? do |a_def|
              a_def.args.empty? && !a_def.block_arity
            end

            # For a generic class type we need to define `new` even
            # if a superclass defines it, because the generated new
            # uses, for example, Foo(T) to match free vars, and here
            # we might need Bar(T) with Bar(T) < Foo(T).
            # (we can probably improve this in the future)
            if initialize_methods.empty?
              # If the type has `self.new()`, don't override it
              unless has_default_self_new
                type.metaclass.as(ModuleType).add_def(Def.argless_new(type), ordered: !defer_overload_order)
                type.add_def(Def.argless_initialize(type), ordered: !defer_overload_order)
              end
            else
              initialize_owner = nil

              initialize_methods.each do |initialize|
                # If the type has `self.new()`, don't override it
                if initialize.args.empty? && !initialize.block_arity && has_default_self_new
                  next
                end

                # Only copy initialize methods from the first ancestor that has them
                if initialize_owner && initialize.owner != initialize_owner
                  break
                end

                initialize_owner = initialize.owner

                new_method = initialize.expand_new_from_initialize(type)
                type.metaclass.as(ModuleType).add_def(new_method, ordered: !defer_overload_order)
              end

              # Copy non-generated `new` methods from parent to child
              new_methods.each do |new_method|
                next if new_method.new?

                type.metaclass.as(ModuleType).add_def(new_method.clone, ordered: !defer_overload_order)
              end
            end
          else
            type.as(ClassType).lookup_new_in_ancestors = true
          end
        end
      end

      define_default_new(type)
    end
  end

  class Def
    def expand_new_from_initialize(instance_type)
      new_def = expand_new_signature_from_initialize(instance_type)
      new_def.fill_body_from_initialize(instance_type)
      new_def
    end

    def expand_new_signature_from_initialize(instance_type)
      def_args = args.clone

      new_def = Def.new("new", def_args, Nop.new).at(self)
      new_def.splat_index = splat_index
      new_def.double_splat = double_splat.clone
      new_def.block_arity = block_arity
      new_def.visibility = visibility
      new_def.new = true
      new_def.doc = doc
      new_def.free_vars = free_vars
      new_def.annotations = annotations

      # Forward block argument if any
      if uses_block_arg?
        block_arg = self.block_arg.not_nil!
        new_def.block_arg = block_arg.clone
        new_def.uses_block_arg = true
      end

      new_def
    end

    def fill_body_from_initialize(instance_type)
      if instance_type.is_a?(GenericClassType)
        generic_type_args = instance_type.type_vars.map_with_index do |type_var, i|
          arg = Path.new(type_var).as(ASTNode).at(self)
          arg = Splat.new(arg).at(self) if instance_type.splat_index == i
          arg
        end
        new_generic = Generic.new(Path.new(instance_type.name), generic_type_args)
        alloc = Call.new(new_generic, "allocate").at(self)
      else
        alloc = Call.new("allocate").at(self)
      end

      # This creates:
      #
      #    x = allocate
      #    x.initialize ..., &block
      #    GC.add_finalizer x if x.responds_to? :finalize
      #    x
      obj = Var.new("_")

      new_vars = [] of ASTNode
      named_args = nil
      splat_index = self.splat_index

      args.each_with_index do |arg, i|
        # This is the case of a bare splat argument
        next if arg.name.empty?

        # Check if the argument has to be passed as a named argument
        if splat_index && i > splat_index
          named_args ||= [] of NamedArgument
          named_args << NamedArgument.new(arg.external_name, Var.new(arg.name).at(self)).at(self)
        else
          new_var = Var.new(arg.name).at(self)
          new_var = Splat.new(new_var).at(self) if i == splat_index
          new_vars << new_var
        end
      end

      # Make sure to forward the double splat argument
      if double_splat = self.double_splat
        new_vars << DoubleSplat.new(Var.new(double_splat.name).at(self)).at(self)
      end

      assign = Assign.new(obj.clone, alloc).at(self)
      init = Call.new(obj.clone, "initialize", new_vars, named_args: named_args).at(self)

      # If the initialize yields, call it with a block
      # that yields those arguments.
      if block_args_count = self.block_arity
        block_args = Array.new(block_args_count) { |i| Var.new("_arg#{i}") }
        vars = Array.new(block_args_count) { |i| Var.new("_arg#{i}").at(self).as(ASTNode) }
        init.block = Block.new(block_args, Yield.new(vars).at(self)).at(self)
      end

      exps = Array(ASTNode).new(4)
      exps << assign
      exps << init
      exps << If.new(RespondsTo.new(obj.clone, "finalize").at(self),
        Call.new(Path.global("GC").at(self), "add_finalizer", obj.clone).at(self))
      exps << obj

      # Forward block argument if any
      if uses_block_arg?
        block_arg = self.block_arg.not_nil!
        init.block_arg = Var.new(block_arg.name).at(self)
      end

      self.body = Expressions.from(exps).at(self.body)
    end

    def self.argless_new(instance_type)
      loc = instance_type.locations.try &.first?

      # This creates:
      #
      #    def new
      #      x = allocate
      #      GC.add_finalizer x if x.responds_to? :finalize
      #      x
      #    end
      var = Var.new("x").at(loc)
      alloc = Call.new("allocate").at(loc)
      assign = Assign.new(var, alloc).at(loc)

      call = Call.new(Path.global("GC").at(loc), "add_finalizer", var.clone).at(loc)
      exps = Array(ASTNode).new(3)
      exps << assign
      exps << If.new(RespondsTo.new(var.clone, "finalize").at(loc), call).at(loc)
      exps << var.clone

      a_def = Def.new("new", body: exps).at(loc)
      a_def.new = true
      a_def
    end

    def self.argless_initialize(instance_type)
      loc = instance_type.locations.try &.first?
      Def.new("initialize", body: Nop.new).at(loc)
    end

    def expand_new_default_arguments(instance_type, args_size, named_args)
      def_args = [] of Arg
      splat_index = nil

      i = 0
      args_size.times do
        def_args << Arg.new("__arg#{i}")
        i += 1
      end

      if named_args
        def_args << Arg.new("")
        splat_index = i
        i += 1

        name = String.build do |str|
          str << "new"
          named_args.each do |named_arg|
            str << ':'
            str << named_arg

            # When **opts is expanded for named arguments, we must use internal
            # names that won't clash with local variables defined in the method.
            temp_name = instance_type.program.new_temp_var_name
            def_args << Arg.new(temp_name, external_name: named_arg)
            i += 1
          end
        end
      else
        name = "new"
      end

      expansion = Def.new(name, def_args, Nop.new, splat_index: splat_index).at(self)
      expansion.block_arity = block_arity
      expansion.visibility = visibility
      expansion.annotations = annotations

      if uses_block_arg?
        block_arg = self.block_arg.not_nil!
        expansion.block_arg = block_arg.clone
        expansion.uses_block_arg = true
      end
      expansion.fill_body_from_initialize(instance_type)

      if owner = self.owner?
        expansion.owner = owner
      end

      # Remove the splat index: we just needed it so that named arguments
      # are passed as named arguments to the initialize call
      if splat_index
        expansion.splat_index = nil
        expansion.args.delete_at(splat_index)
      end

      expansion
    end
  end
end
