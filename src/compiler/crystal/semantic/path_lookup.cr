module Crystal
  class Type
    # Looks up a *path* (for example: `Foo::Bar::Baz`) relative to `self`.
    #
    # For example, given:
    #
    # ```
    # class Foo
    #   class Bar
    #     class Baz
    #     end
    #   end
    # end
    # ```
    #
    # If `self` is `Foo` and we invoke `lookup_path(["Bar", "Baz"])` on it,
    # we'll get `Foo::Bar::Baz` as the return value.
    #
    # The path is searched in the current type's ancestors, and optionally
    # in its namespace, according to *lookup_in_namespace*.
    #
    # Returns `nil` if the path can't be found.
    #
    # *include_private* controls whether private types are found inside
    # other types (when doing Foo::Bar, Bar won't be found if it's private).
    #
    # *location* can be passed and is the location where the lookup happens,
    # and is useful to find file-private types.
    #
    # The result can be an `ASTNode` in the case the path denotes a type variable
    # whose variable is an `ASTNode`. One such example is the `N` of `StaticArray(T, N)`
    # for some instantiated `StaticArray`.
    #
    # If the path is global (for example ::Foo::Bar), the search starts at
    # the top level.
    def lookup_path(path : Path, lookup_in_namespace = true, include_private = false, location = path.location) : Type | ASTNode | Nil
      location = nil if path.global?
      (path.global? ? program : self).lookup_path(path.names, lookup_in_namespace, include_private, location)
    end

    # :ditto:
    def lookup_path(names : Array(String), lookup_in_namespace = true, include_private = false, location = nil) : Type | ASTNode | Nil
      type = self
      names.each_with_index do |name, i|
        # The search must continue in the namespace only for the first path
        # item: for subsequent path items only the parents must be looked up
        type = type.lookup_path_item(name, i == 0, lookup_in_namespace && i == 0, i == 0 || include_private, location)
        return unless type

        # Stop if this is the last name
        break if i == names.size - 1

        # An intermediate match could be an ASTNode, for example
        # when searching T::N::X, and T denotes a static array:
        # in this case we can't continue searching past `N`
        return unless type.is_a?(Type)
      end

      # If this is a TypeParameter resulting from the formal argument of e.g. an
      # inherited generic instance, we must solve this immediately whenever
      # possible. For example:
      #
      # ```
      # class Foo(T1); end
      #
      # class Bar(T2) < Foo(T2); end
      # ```
      #
      # Looking up `T1` under `Bar(Int32)`'s context will return `T2`, which is
      # the formal argument in `Foo(T2)`, and we solve it to return `Int32`. On
      # the other hand, looking up `T1` under `Bar`'s context will return `nil`.
      if type.is_a?(TypeParameter)
        if solved = type.solve?(self).as?(Var)
          return solved.type
        elsif !solved.nil?
          # If the context were `Bar(1)` instead, then `solved` is that AST node
          # itself (i.e. `1`), rather than a `Var` with the type of the solved
          # type argument.
          return solved
        end
      end

      type
    end

    # Looks up a single path item relative to *self`.
    #
    # If *lookup_in_namespace* is `true`, if the type is not found
    # in `self` or `self`'s parents, the path item is searched in this
    # type's namespace. This parameter is useful because when writing
    # `Foo::Bar::Baz`, `Foo` should be searched in enclosing namespaces,
    # but `Bar` and `Baz` not.
    #
    # If *lookup_self* is `true`, if the type is not found under `self` but has
    # the same name as `self`, then `self` is returned. This has higher
    # precedence than ancestors and the enclosing namespace.
    def lookup_path_item(name : String, lookup_self, lookup_in_namespace, include_private, location) : Type | ASTNode | Nil
      # First search in our types
      type = lookup_name(name)
      if type
        if type.private? && !include_private
          return nil
        end

        return type
      end

      # Try ourself for the first path item, unless we are the top-level
      if lookup_self && self != program
        if self.is_a?(NamedType) && name == self.name
          return self
        end
      end

      # Then try out parents, but don't search in our parents namespace
      parents.try &.each do |parent|
        match = parent.lookup_path_item(name, false, false, include_private, location)
        return match if match
      end

      # Try our namespace, unless we are the top-level
      if lookup_in_namespace && self != program
        return namespace.lookup_path_item(name, false, lookup_in_namespace, include_private, location)
      end

      nil
    end
  end

  class Program
    def lookup_path_item(name : String, lookup_self, lookup_in_namespace, include_private, location)
      # Check if there's a private type in location
      if location && (original_filename = location.original_filename) &&
         (file_module = file_module?(original_filename)) &&
         (item = file_module.types[name]?)
        return item
      end

      super
    end
  end

  module GenericType
    def lookup_path_item(name : String, lookup_self, lookup_in_namespace, include_private, location)
      # If we are Foo(T) and somebody looks up the type T, we return `nil` because we don't
      # know what type T is, and we don't want to continue search in the namespace
      if type_vars.includes?(name)
        return nil
      end
      super
    end
  end

  class GenericInstanceType
    def lookup_path_item(name : String, lookup_self, lookup_in_namespace, include_private, location)
      # Check if *name* is a type variable
      if type_var = type_vars[name]?
        if type_var.is_a?(Var)
          type_var.type
        else
          type_var
        end
      else
        generic_type.lookup_path_item(name, lookup_self, lookup_in_namespace, include_private, location)
      end
    end
  end

  class UnionType
    def lookup_path_item(name : String, lookup_self, lookup_in_namespace, include_private, location)
      # Union type does not currently inherit GenericClassInstanceType,
      # so we check if *name* is the only type variable of Union(*T)
      if name == "T"
        return program.tuple_of(union_types)
      end
      program.lookup_path_item(name, lookup_self, lookup_in_namespace, include_private, location)
    end
  end

  class AliasType
    def lookup_path_item(name : String, lookup_self, lookup_in_namespace, include_private, location)
      if aliased_type = aliased_type?
        aliased_type.lookup_path_item(name, lookup_self, lookup_in_namespace, include_private, location)
      else
        super
      end
    end
  end

  class TypeDefType
    delegate lookup_path, to: typedef
  end

  class MetaclassType
    delegate lookup_path, to: instance_type
  end

  class GenericClassInstanceMetaclassType
    delegate lookup_path, to: instance_type
  end

  class GenericModuleInstanceMetaclassType
    delegate lookup_path, to: instance_type
  end

  class VirtualType
    delegate lookup_path, to: base_type
  end

  class VirtualMetaclassType
    delegate lookup_path, to: instance_type
  end
end
