module Crystal
  # Specialized container for ASTNodes to use for bindings tracking.
  #
  # The average number of elements in both dependencies and observers is below 2
  # for ASTNodes. This struct inlines the first two elements saving up 4
  # allocations per node (two arrays, with a header and buffer for each) but we
  # need to pay a slight extra cost in memory upfront: a total of 6 pointers (48
  # bytes) vs 2 pointers (16 bytes). The other downside is that since this is a
  # struct, we need to be careful with mutation.
  struct SmallNodeList
    include Enumerable(ASTNode)

    @first : ASTNode?
    @second : ASTNode?
    @tail : Array(ASTNode)?

    def each(& : ASTNode ->)
      yield @first || return
      yield @second || return
      @tail.try(&.each { |node| yield node })
    end

    def size
      if @first.nil?
        0
      elsif @second.nil?
        1
      elsif (tail = @tail).nil?
        2
      else
        2 + tail.size
      end
    end

    def push(node : ASTNode) : self
      if @first.nil?
        @first = node
      elsif @second.nil?
        @second = node
      elsif (tail = @tail).nil?
        @tail = [node] of ASTNode
      else
        tail.push(node)
      end
      self
    end

    def reject!(& : ASTNode ->) : self
      if first = @first
        if second = @second
          if tail = @tail
            tail.reject! { |node| yield node }
          end
          if yield second
            @second = tail.try &.shift?
          end
        end
        if yield first
          @first = @second
          @second = tail.try &.shift?
        end
      end
      self
    end

    def concat(nodes : Enumerable(ASTNode)) : self
      nodes.each { |node| self.push(node) }
      self
    end
  end

  class ASTNode
    getter dependencies : SmallNodeList = SmallNodeList.new
    @observers : SmallNodeList = SmallNodeList.new
    property enclosing_call : Call?

    @dirty = false

    @type : Type?

    def type
      type? || ::raise "BUG: `#{self}` at #{self.location} has no type"
    end

    def type?
      @type || freeze_type
    end

    def type(*, with_autocast = false)
      type = self.type

      if with_autocast
        case self
        when NumberLiteral
          NumberAutocastType.new(type.program, self)
        when SymbolLiteral
          SymbolAutocastType.new(type.program, self)
        else
          case type
          when IntegerType, FloatType
            NumberAutocastType.new(type.program, self)
          else
            type
          end
        end
      else
        type
      end
    end

    def set_type(type : Type)
      type = type.remove_alias_if_simple
      if !type.no_return? && (freeze_type = self.freeze_type) && !type.implements?(freeze_type)
        raise_frozen_type freeze_type, type, self
      end
      @type = type
    end

    def set_type(type : Nil)
      @type = type
    end

    def set_type_from(type, from)
      set_type type
    rescue ex : FrozenTypeException
      # See if we can find where the mismatched type came from
      if from && !ex.inner && (freeze_type = self.freeze_type) && type.is_a?(UnionType) && type.includes_type?(freeze_type) && type.union_types.size == 2
        other_type = type.union_types.find { |type| type != freeze_type }
        trace = from.find_owner_trace(freeze_type.program, other_type)
        ex.inner = trace
      elsif from && !ex.inner && (freeze_type = self.freeze_type)
        trace = from.find_owner_trace(freeze_type.program, type)
        ex.inner = trace
      end

      if from && !location
        from.raise ex.message, ex.inner
      else
        ::raise ex
      end
    end

    def freeze_type
      nil
    end

    def raise_frozen_type(freeze_type, invalid_type, from)
      if !freeze_type.includes_type?(invalid_type.program.nil) && invalid_type.includes_type?(invalid_type.program.nil)
        # This means that an instance variable become nil
        if self.is_a?(MetaTypeVar) && (nil_reason = self.nil_reason)
          inner = MethodTraceException.new(nil, [] of ASTNode, nil_reason, freeze_type.program.show_error_trace?)
        end
      end

      case self
      when MetaTypeVar
        if self.global?
          from.raise "global variable '#{self.name}' must be #{freeze_type}, not #{invalid_type}", inner, Crystal::FrozenTypeException
        else
          from.raise "#{self.kind.to_s.underscore} variable '#{self.name}' of #{self.owner} must be #{freeze_type}, not #{invalid_type}", inner, Crystal::FrozenTypeException
        end
      when Def
        (self.return_type || self).raise "method #{self.short_reference} must return #{freeze_type} but it is returning #{invalid_type}", inner, Crystal::FrozenTypeException
      when NamedType
        from.raise "type #{self.full_name} must be #{freeze_type}, not #{invalid_type}", inner, Crystal::FrozenTypeException
      else
        from.raise "type must be #{freeze_type}, not #{invalid_type}", inner, Crystal::FrozenTypeException
      end
    end

    def type=(type)
      return if @type.same?(type) || (!type && !@type)

      set_type(type)
      notify_observers
      @type
    end

    def bind_to(node : ASTNode) : Nil
      bind(node) do
        @dependencies.push node
        node.add_observer self
      end
    end

    def bind_to(nodes : Indexable) : Nil
      return if nodes.empty?

      bind do
        @dependencies.concat nodes
        nodes.each &.add_observer self
      end
    end

    def bind(from = nil, &)
      # Quick check to provide a better error message when assigning a type
      # to a variable whose type is frozen
      if self.is_a?(MetaTypeVar) && (freeze_type = self.freeze_type) && from &&
         (from_type = from.type?) && !from_type.implements?(freeze_type)
        raise_frozen_type freeze_type, from_type, from
      end

      yield

      new_type = type_from_dependencies
      new_type = map_type(new_type) if new_type

      if new_type && (freeze_type = self.freeze_type)
        new_type = restrict_type_to_freeze_type(freeze_type, new_type)
      end

      return if @type.same? new_type
      return unless new_type

      set_type_from(new_type, from)
      @dirty = true
      propagate
    end

    def type_from_dependencies : Type?
      Type.merge @dependencies
    end

    def unbind_from(nodes : Nil)
      # Nothing to do
    end

    def unbind_from(node : ASTNode)
      @dependencies.reject! &.same?(node)
      node.remove_observer self
    end

    def unbind_from(nodes : Enumerable(ASTNode))
      @dependencies.reject! { |dep| nodes.any? &.same?(dep) }
      nodes.each &.remove_observer self
    end

    def add_observer(observer)
      @observers.push observer
    end

    def remove_observer(observer)
      @observers.try &.reject! &.same?(observer)
    end

    def set_enclosing_call(enclosing_call)
      current_enclosing_call = @enclosing_call
      if current_enclosing_call
        # This can happen when a block is typed, and meanwhile a new
        # generic instance type is created that triggers the block to
        # be typed again, potentially analyzing a call twice.
        unless current_enclosing_call.same?(enclosing_call)
          raise "BUG: already had a different enclosing call"
        end
      else
        @enclosing_call = enclosing_call
      end
    end

    def remove_enclosing_call(enclosing_call)
      @enclosing_call = nil if @enclosing_call.same?(enclosing_call)
    end

    def notify_observers
      @observers.try &.each &.update self
      @enclosing_call.try &.recalculate
      @observers.try &.each &.propagate
      @enclosing_call.try &.propagate
    end

    def update(from = nil)
      return if @type && @type.same? from.try &.type?

      new_type = type_from_dependencies
      new_type = map_type(new_type) if new_type

      if new_type && (freeze_type = self.freeze_type)
        new_type = restrict_type_to_freeze_type(freeze_type, new_type)
      end

      return if @type.same? new_type

      if new_type
        set_type_from(new_type, from)
      else
        return unless @type

        set_type(nil)
      end

      @dirty = true
    end

    def propagate
      if @dirty
        @dirty = false
        notify_observers
      end
    end

    def map_type(type)
      type
    end

    # Computes the type resulting from assigning type to freeze_type,
    # in the case where freeze_type is not nil.
    #
    # Special cases are listed inside the method body.
    def restrict_type_to_freeze_type(freeze_type, type)
      if freeze_type.is_a?(ProcInstanceType)
        # We allow assigning Proc(*T, R) to Proc(*T, Nil)
        if freeze_type.return_type.nil_type? &&
           type.all? { |a_type|
             a_type.is_a?(ProcInstanceType) && a_type.arg_types == freeze_type.arg_types
           }
          return freeze_type
        end

        # We also allow assigning Proc(*T, NoReturn) to Proc(*T, U)
        if type.all? { |a_type|
             a_type.is_a?(ProcInstanceType) &&
             (a_type.return_type.is_a?(NoReturnType) || a_type.return_type == freeze_type.return_type) &&
             a_type.arg_types == freeze_type.arg_types
           }
          return freeze_type
        end
      end

      type
    end

    def find_owner_trace(program, owner)
      owner_trace = [] of ASTNode
      node = self

      visited = Set(ASTNode).new.compare_by_identity
      owner_trace << node if node.type?.try &.includes_type?(owner)
      visited.add node
      while node = node.dependencies.find { |dep| dep.type? && dep.type.includes_type?(owner) && !visited.includes?(dep) }
        nil_reason = node.nil_reason if node.is_a?(MetaTypeVar)
        owner_trace << node if node
        visited.add node
      end

      MethodTraceException.new(owner, owner_trace, nil_reason, program.show_error_trace?)
    end
  end

  class Def
    def map_type(type)
      # When we have Nil forced as a return type, NoReturn still
      # wins, so we must account for this case.
      # Otherwise we simply keep having the Nil type.
      if freeze_type.try &.nil_type? && !type.no_return?
        freeze_type
      else
        type
      end
    end

    def set_type(type : Type)
      super

      raise "returns a large value type: #{type}" if type.large_value_type?
      type
    end
  end

  class PointerOf
    def map_type(type)
      old_type = self.type?
      new_type = type.program.pointer_of(type)
      if old_type && grew?(old_type, new_type)
        raise "recursive pointerof expansion: #{old_type}, #{new_type}, ..."
      end

      new_type
    end

    def grew?(old_type, new_type)
      new_type = new_type.as(PointerInstanceType)
      element_type = new_type.element_type
      type_includes?(element_type, old_type)
    end

    def type_includes?(haystack, needle)
      return true if haystack == needle

      case haystack
      when UnionType
        haystack.union_types.any? { |sub| type_includes?(sub, needle) }
      when GenericClassInstanceType
        splat_index = haystack.generic_type.splat_index
        haystack.type_vars.each_with_index do |(_, sub), index|
          if sub.is_a?(Var)
            if index == splat_index
              return true if sub.type.as(TupleInstanceType).tuple_types.any? { |sub2| type_includes?(sub2, needle) }
            else
              return true if type_includes?(sub.type, needle)
            end
          end
        end
        false
      else
        false
      end
    end
  end

  class TypeOf
    property? in_type_args = false

    def map_type(type)
      @in_type_args ? type : type.metaclass
    end

    def update(from = nil)
      super
      propagate
    end
  end

  class ExceptionHandler
    def map_type(type)
      if (ensure_type = @ensure.try &.type?).try &.is_a?(NoReturnType)
        ensure_type
      else
        type
      end
    end
  end

  class Union
    property? inside_is_a = false

    def update(from = nil)
      computed_types = types.compact_map do |subtype|
        instance_type = subtype.type?
        next unless instance_type

        unless instance_type.can_be_stored?
          subtype.raise "can't use #{instance_type} in unions yet, use a more specific type"
        end
        instance_type.virtual_type
      end

      return if computed_types.empty?

      program = computed_types.first.program

      if inside_is_a?
        self.type = program.type_merge_union_of(computed_types)
      else
        self.type = program.type_merge(computed_types)
      end
    end
  end

  class Cast
    property? upcast = false

    def update(from = nil)
      to_type = to.type?
      return unless to_type

      program = to_type.program

      case to_type
      when program.object
        raise "can't cast to Object yet"
      when program.reference
        raise "can't cast to Reference yet"
      when program.class_type
        raise "can't cast to Class yet"
      end

      obj_type = obj.type?

      if obj_type.is_a?(PointerInstanceType)
        to_type_instance_type = to_type.instance_type
        if to_type_instance_type.is_a?(GenericType)
          raise "can't cast #{obj_type} to #{to_type_instance_type}"
        end
      end

      @upcast = false

      if obj_type && !(obj_type.pointer? || to_type.pointer?)
        filtered_type = obj_type.filter_by(to_type)

        # If the filtered type didn't change it means that an
        # upcast is being made, for example:
        #
        #   1 as Int32 | Float64
        #   Bar.new as Foo # where Bar < Foo
        if obj_type == filtered_type && !to_type.is_a?(GenericClassType) &&
           to_type.can_be_stored?
          filtered_type = to_type
          @upcast = true
        end
      end

      # If we couldn't filter the type and we are casting to something that
      # isn't allowed in variables (like Int or uninstantiated Array(T))
      # we can't guess a type.
      return if !filtered_type && !to_type.can_be_stored?

      # If we don't have a matching type, leave it as the to_type:
      # later (in cleanup) we will check again.
      filtered_type ||= to_type
      self.type = filtered_type.virtual_type
    end
  end

  class NilableCast
    property? upcast = false
    getter! non_nilable_type : Type

    def update(from = nil)
      to_type = to.type?
      return unless to_type

      program = to_type.program

      case to_type
      when program.object
        raise "can't cast to Object yet"
      when program.reference
        raise "can't cast to Reference yet"
      when program.class_type
        raise "can't cast to Class yet"
      end

      obj_type = obj.type?

      if obj_type.is_a?(PointerInstanceType)
        to_type_instance_type = to_type.instance_type
        if to_type_instance_type.is_a?(GenericType)
          raise "can't cast #{obj_type} to #{to_type_instance_type}"
        end
      end

      @upcast = false

      if obj_type
        filtered_type = obj_type.filter_by(to_type)

        # If the filtered type didn't change it means that an
        # upcast is being made, for example:
        #
        #   1 as Int32 | Float64
        #   Bar.new as Foo # where Bar < Foo
        if obj_type == filtered_type && !to_type.is_a?(GenericClassType) &&
           to_type.can_be_stored?
          filtered_type = to_type.virtual_type
          @upcast = true
        end
      end

      # If we couldn't filter the type and we are casting to something that
      # isn't allowed in variables (like Int or uninstantiated Array(T))
      # we can't guess a type.
      if !filtered_type && !to_type.can_be_stored?
        self.type = to_type.program.nil_type
        return
      end

      # If we don't have a matching type, leave it as the to_type:
      # later (in cleanup) we will check again.
      filtered_type ||= to_type
      filtered_type = filtered_type.virtual_type

      @non_nilable_type = filtered_type

      # The final type is nilable
      self.type = filtered_type.program.nilable(filtered_type)
    end
  end

  class ProcLiteral
    property? force_nil = false
    property expected_return_type : Type?
    property? from_block = false

    def update(from = nil)
      return unless self.def.args.all? &.type?
      return unless self.def.type?

      types = self.def.args.map &.type.virtual_type
      return_type = @force_nil ? self.def.type.program.nil : self.def.type.virtual_type

      expected_return_type = @expected_return_type
      if expected_return_type && !expected_return_type.nil_type? && !return_type.implements?(expected_return_type)
        raise "expected #{from_block? ? "block" : "Proc"} to return #{expected_return_type.devirtualize}, not #{return_type}"
      end

      types << (expected_return_type || return_type)

      self.type = self.def.type.program.proc_of(types)
    end

    def return_type
      @type.as(ProcInstanceType).return_type
    end
  end

  class ProcPointer
    property! call : Call

    def map_type(type)
      if self.expanded
        return type
      end

      return nil unless call.type?

      arg_types = call.args.map &.type.virtual_type
      arg_types.push call.type.virtual_type

      call.type.program.proc_of(arg_types)
    end
  end

  class Generic
    property! instance_type : GenericType
    property scope : Type?
    property? in_type_args = false
    property? inside_is_a = false

    def update(from = nil)
      instance_type = self.instance_type
      if instance_type.is_a?(NamedTupleType)
        entries = Array(NamedArgumentType).new(named_args.try(&.size) || 0)
        named_args.try &.each do |named_arg|
          node = named_arg.value

          if node.is_a?(Path) && (syntax_replacement = node.syntax_replacement)
            node = syntax_replacement
          end

          if node.is_a?(NumberLiteral)
            node.raise "can't use number as type for NamedTuple"
          end

          node_type = node.type?
          return unless node_type

          if node.is_a?(Path) && node.target_const
            node.raise "can't use constant as type for NamedTuple"
          end

          Crystal.check_type_can_be_stored(node, node_type, "can't use #{node_type} as generic type argument")
          node_type = node_type.virtual_type

          entries << NamedArgumentType.new(named_arg.name, node_type)
        end

        generic_type = instance_type.instantiate_named_args(entries)
      else
        type_vars_types = Array(TypeVar).new(type_vars.size + 1)
        type_vars.each do |node|
          if node.is_a?(Path) && (syntax_replacement = node.syntax_replacement)
            node = syntax_replacement
          end
          if node.is_a?(SizeOf) && (expanded = node.expanded)
            node = expanded
          end
          if node.is_a?(InstanceSizeOf) && (expanded = node.expanded)
            node = expanded
          end
          if node.is_a?(AlignOf) && (expanded = node.expanded)
            node = expanded
          end
          if node.is_a?(InstanceAlignOf) && (expanded = node.expanded)
            node = expanded
          end
          if node.is_a?(OffsetOf) && (expanded = node.expanded)
            node = expanded
          end

          case node
          when NumberLiteral
            type_var = node
          when Splat
            type = node.type?
            return unless type.is_a?(TupleInstanceType)

            type_vars_types.concat(type.tuple_types)
            next
          else
            node_type = node.type?
            return unless node_type

            # If the Path points to a constant, we solve it and use it if it's a number literal
            if node.is_a?(Path) && (target_const = node.target_const)
              value = target_const.value
              if value.is_a?(NumberLiteral)
                type_var = value
              else
                # Try to interpret the value
                visitor = target_const.visitor
                if visitor
                  numeric_value = visitor.interpret_enum_value(value)
                  numeric_type = node_type.program.int?(numeric_value) || raise "BUG: expected integer type, not #{numeric_value.class}"
                  type_var = NumberLiteral.new(numeric_value.to_s, numeric_type.kind)
                  type_var.set_type_from(numeric_type, from)
                else
                  node.raise "can't use constant #{node} (value = #{value}) as generic type argument, it must be a numeric constant"
                end
              end
            else
              Crystal.check_type_can_be_stored(node, node_type, "can't use #{node_type} as generic type argument")
              type_var = node_type.virtual_type
            end
          end

          type_vars_types << type_var
        end

        begin
          generic_instance_type = instance_type.as(GenericType)
          generic_type =
            if generic_instance_type.is_a?(GenericUnionType) && inside_is_a?
              # In the case of `exp.is_a?(Union(X, Y))` we make it work exactly
              # like `exp.is_a?(X | Y)`, which won't resolve `X | Y` to the virtual
              # parent type.
              generic_instance_type.instantiate(type_vars_types, type_merge_union_of: true)
            else
              generic_instance_type.instantiate(type_vars_types)
            end
        rescue ex : Crystal::CodeError
          raise ex.message, ex
        end
      end

      if generic_type_too_nested?(generic_type.generic_nest)
        raise "generic type too nested: #{generic_type}"
      end

      generic_type = generic_type.metaclass unless @in_type_args
      self.type = generic_type
    end
  end

  class TupleLiteral
    property! program : Program

    def update(from = nil)
      types = [] of TypeVar
      elements.each do |node|
        if node.is_a?(Splat)
          type = node.type?
          return unless type.is_a?(TupleInstanceType)
          types.concat(type.tuple_types)
        else
          type = node.type?
          return unless type
          types << type
        end
      end

      tuple_type = program.tuple_of types

      if generic_type_too_nested?(tuple_type.generic_nest)
        raise "tuple type too nested: #{tuple_type}"
      end

      if types.size > 300
        raise "tuple size cannot be greater than 300 (size is #{types.size})"
      end

      self.type = tuple_type
    end
  end

  class NamedTupleLiteral
    property! program : Program

    def update(from = nil)
      return unless entries.all? &.value.type?

      entries = self.entries.map do |element|
        NamedArgumentType.new(element.key, element.value.type)
      end

      named_tuple_type = program.named_tuple_of(entries)

      if generic_type_too_nested?(named_tuple_type.generic_nest)
        raise "named tuple type too nested: #{named_tuple_type}"
      end

      if entries.size > 300
        raise "named tuple size cannot be greater than 300 (size is #{entries.size})"
      end

      self.type = named_tuple_type
    end
  end

  class ReadInstanceVar
    def update(from = nil)
      obj_type = obj.type?
      return unless obj_type

      self.type =
        if obj_type.is_a?(UnionType)
          obj_type.program.type_merge(
            obj_type.union_types.map do |union_type|
              lookup_instance_var(union_type).type
            end
          )
        else
          lookup_instance_var(obj_type).type
        end
    end

    private def lookup_instance_var(type)
      ivar = type.lookup_instance_var(self)
      unless ivar
        similar_name = type.lookup_similar_instance_var_name(name)
        type.program.undefined_instance_variable(self, type, similar_name)
      end
      ivar
    end
  end

  class Not
    def update(from = nil)
      type = exp.type?
      return unless type

      self.type = type.no_return? ? type : type.program.bool
    end
  end

  class Block
    property binder : YieldBlockBinder?
  end

  # Fictitious node to bind yield expressions to block arguments
  class YieldBlockBinder < ASTNode
    getter block

    def initialize(@program : Program, @block : Block)
      @yields = [] of {Yield, Array(Var)?}
    end

    def add_yield(node : Yield, yield_vars : Array(Var)?)
      @yields << {node, yield_vars}
      node.exps.each &.add_observer(self)
    end

    def update(from = nil)
      # We compute all the types for each block arguments
      block_arg_types = Array(Array(Type)?).new(block.args.size, nil)

      @yields.each do |a_yield, yield_vars|
        gather_yield_block_arg_types(a_yield, yield_vars, block, block_arg_types)
      end

      block.args.each_with_index do |arg, i|
        block_arg_type = block_arg_types[i]
        if block_arg_type
          arg_type = Type.merge(block_arg_type) || @program.nil
          if i == block.splat_index && !arg_type.is_a?(TupleInstanceType)
            arg.raise "yield argument to block splat parameter must be a Tuple, not #{arg_type}"
          end
          arg.type = arg_type
        else
          # Skip, no type info found in this position
        end
      end
    end

    # Gather all exps types and then assign to block_arg_types.
    # We need to do that in case of a block splat argument, we need
    # to split and create tuple types for that case.
    private def gather_yield_block_arg_types(a_yield, yield_vars, block, block_arg_types)
      args_size = block.args.size
      splat_index = block.splat_index
      exps_types = Array(Type).new(a_yield.exps.size)

      i = 0
      a_yield.exps.each do |exp|
        exp_type = exp.type?
        return unless exp_type

        if exp.is_a?(Splat)
          unless exp_type.is_a?(TupleInstanceType)
            exp.raise "expected splat expression to be a tuple type, not #{exp_type}"
          end

          exps_types.concat(exp_type.tuple_types)
          i += exp_type.tuple_types.size
        else
          exps_types << exp_type
          i += 1
        end
      end

      if splat_index
        # Error if there are less expressions than the number of block arguments
        if exps_types.size < (args_size - 1)
          block.raise "too many block parameters (given #{args_size - 1}+, expected maximum #{exps_types.size})"
        end
        splat_range = (splat_index..splat_index - args_size)
        exps_types[splat_range] = @program.tuple_of(exps_types[splat_range])
      end

      # Check if there are missing yield expressions to match
      # the (optional) block signature, and if they match the declared types
      if yield_vars
        if exps_types.size < yield_vars.size
          a_yield.raise "wrong number of yield arguments (given #{exps_types.size}, expected #{yield_vars.size})"
        end

        # Check that the types match
        i = 0
        yield_vars.zip(exps_types) do |yield_var, exp_type|
          unless exp_type.implements?(yield_var.type)
            a_yield.raise "argument ##{i + 1} of yield expected to be #{yield_var.type}, not #{exp_type}"
          end
          i += 1
        end
      end

      # Check if tuple unpacking is needed
      if exps_types.size == 1 &&
         (exp_type = exps_types.first).is_a?(TupleInstanceType) &&
         args_size > 1 &&
         !splat_index
        exps_types = exp_type.tuple_types
      end

      # Now move exps_types to block_arg_types
      if block.args.size > exps_types.size
        block.raise "too many block parameters (given #{block.args.size}, expected maximum #{exps_types.size})"
      end

      exps_types.each_with_index do |exp_type, i|
        break if i >= block_arg_types.size

        types = block_arg_types[i] ||= [] of Type
        types << exp_type
      end
    end

    def clone_without_location
      self
    end
  end
end

# TODO: 300 is a pretty big number for the number of nested generic instantiations,
# (think Array(Array(Array(Array(Array(Array(Array(Array(Array(Array(Array(...))))))))))
# but we might want to implement an algorithm that correctly identifies this
# infinite recursion.
private def generic_type_too_nested?(nest_level)
  nest_level > 300
end
