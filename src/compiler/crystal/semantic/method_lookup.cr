require "../types"

# Looking up matches involves two steps:
#
# 1. Lookup is done with autocasting disabled.
#
# In this scenario as soon as we find an exact match we don't look at other
# overloads because the exact match will prevent them from being considered.
#
# If no matches are found we try again but this time with autocasting enabled.
# In `semantic/call.cr` this is when `with_autocast` is `true`, and this is when
# `analyze_all` will be `true` here.
#
# 2. Lookup is done with autocasting enabled.
#
# In this mode the types for NumberLiteral and SymbolLiteral are not the usual
# types but instead the special NumberAutocastType and SymbolAutocastType.
#
# In this mode we also need to stop as soon as we find an exact match
# (which just means when the first overload matches with autocasting, which
# is for example when passing 1 to an Int64 restriction) but we still need
# to analyze all possible methods in case there's an ambiguity. For example:
#
# ```
# def foo(x : Int64)
# end
#
# def foo(x : Int8)
# end
#
# foo(1)
# ```
#
# In the example above we can't just stop at the first overload because
# we need to analyze the second overload to find out that the call is ambiguous.
#
# However, consider this:
#
# ```
# def foo(x : Int64)
# end
#
# def foo(x : *Int64)
# end
#
# foo(1)
# ```
#
# In this case there's no ambiguity: 1 means `Int64`. However, the first overload
# is an exact match and there's no need to consider the second overload in the
# multidispatch. However, we do need to analyze it to check if there's an ambiguity.

module Crystal
  record NamedArgumentType, name : String, type : Type do
    def self.from_args(named_args : Array(NamedArgument)?, with_autocast = false)
      named_args.try &.map do |named_arg|
        new(named_arg.name, named_arg.value.type(with_autocast: with_autocast))
      end
    end
  end

  record CallSignature,
    name : String,
    arg_types : Array(Type),
    block : Block?,
    named_args : Array(NamedArgumentType)?

  class Type
    def lookup_matches(signature, owner = self, path_lookup = self, matches_array = nil, analyze_all = false)
      matches = lookup_matches_without_parents(signature, owner, path_lookup, matches_array, analyze_all: analyze_all)
      return matches if matches.cover_all?

      matches_array = matches.matches

      cover = matches.cover

      is_new = owner.metaclass? && signature.name == "new"
      if is_new
        # For a `new` method we need to do this in case a `new` is defined
        # in a module type
        my_parents = instance_type.parents.try &.map(&.metaclass)
      else
        my_parents = parents
      end

      # `new` must only be searched in ancestors if this type itself doesn't define
      # an `initialize` or `self.new` method. This was already computed in `new.cr`
      # and can be known by invoking `lookup_new_in_ancestors?`
      if my_parents && !(is_new && !lookup_new_in_ancestors?)
        my_parents.each do |parent|
          matches = parent.lookup_matches(signature, owner, parent, matches_array, analyze_all: analyze_all)
          if matches.cover_all?
            return matches
          else
            matches_array = matches.matches
          end

          # If this is a `new` method, once a parent defines an `initialize`
          # method and we couldn't find any matches we must not go up in the
          # hierarchy.
          break if is_new && parent.has_def_without_parents?(signature.name)
        end
      end

      Matches.new(matches_array, cover, owner, false)
    end

    def lookup_matches_without_parents(signature, owner = self, path_lookup = self, matches_array = nil, analyze_all = false)
      if defs = self.defs.try &.[signature.name]?
        context = MatchContext.new(owner, path_lookup)

        exact_match = nil

        defs.each do |item|
          next if item.def.abstract?

          # If the def has a macro owner, which means that the original
          # def was defined via a `macro def` and copied to a subtype,
          # we need to use the type that defined the `macro def` as a
          # type lookup for arguments.
          macro_owner = item.def.macro_owner?
          context.defining_type = macro_owner if macro_owner
          context.self_restriction_type = item.def.self_restriction_type
          context.def_free_vars = item.def.free_vars
          context.bound_free_vars.try &.clear

          match = signature.match(item, context)

          next if exact_match

          if match
            matches_array ||= [] of Match
            matches_array << match

            # If the argument types are compatible with the match's argument types,
            # we are done. We don't just compare types with ==, there is a special case:
            # a function type with return T can be transpass a restriction of a function
            # with the same arguments but which returns Void.
            if signature.matches_exactly?(match)
              exact_match = Matches.new(matches_array, true, owner)
              break unless analyze_all
            end

            context = MatchContext.new(owner, path_lookup)
          else
            context.defining_type = path_lookup if macro_owner
            context.self_restriction_type = nil
            context.def_free_vars = nil
            context.bound_free_vars.try &.clear
          end
        end

        if exact_match
          return exact_match
        end
      end

      Matches.new(matches_array, Cover.create(signature, matches_array), owner)
    end

    def lookup_matches_with_modules(signature, owner = self, path_lookup = self, matches_array = nil, analyze_all = false)
      matches = lookup_matches_without_parents(signature, owner, path_lookup, matches_array, analyze_all: analyze_all)
      return matches unless matches.empty?

      is_new = owner.metaclass? && signature.name == "new"
      if is_new
        # For a `new` method we need to do this in case a `new` is defined
        # in a module type
        my_parents = instance_type.parents.try &.map(&.metaclass)
      else
        my_parents = parents
      end

      # `new` must only be searched in ancestors if this type itself doesn't define
      # an `initialize` or `self.new` method. This was already computed in `new.cr`
      # and can be known by invoking `lookup_new_in_ancestors?`
      if my_parents && !(!lookup_new_in_ancestors? && is_new)
        my_parents.each do |parent|
          break unless parent.module?

          matches = parent.lookup_matches_with_modules(signature, owner, parent, matches_array, analyze_all: analyze_all)
          return matches unless matches.empty?
        end
      end

      Matches.new(matches_array, Cover.create(signature, matches_array), owner, false)
    end
  end

  struct CallSignature
    def match(def_metadata, context)
      signature = self

      # If yieldness isn't the same there's no match
      if def_metadata.yields != !!signature.block
        return nil
      end

      # If there are more positional arguments than those required, there's no match
      # (if there's less they might be matched with named arguments)
      if signature.arg_types.size > def_metadata.max_size
        return nil
      end

      a_def = def_metadata.def
      arg_types = signature.arg_types
      named_args = signature.named_args
      splat_index = a_def.splat_index
      splat_restriction = a_def.args[splat_index].restriction if splat_index
      double_splat = a_def.double_splat
      double_splat_restriction = double_splat.try &.restriction

      # If there are arguments past the splat index and no named args, there's no match,
      # unless all args past it have default values
      if splat_index && a_def.args.size > splat_index + 1 && !named_args
        unless (splat_index + 1...a_def.args.size).all? { |i| a_def.args[i].default_value }
          return nil
        end
      end

      # If there are named args we must check that all mandatory args
      # are covered by positional arguments or named arguments.
      if named_args
        mandatory_args = BitArray.new(a_def.args.size)
      elsif signature.arg_types.size < def_metadata.min_size
        # Otherwise, they must be matched by positional arguments
        return nil
      end

      matched_arg_types = nil
      matched_named_arg_types = nil

      # If there's a restriction on a splat (that's not a splat restriction),
      # zero splatted args don't match
      if splat_index && splat_restriction &&
         !splat_restriction.is_a?(Splat) &&
         Splat.size(a_def, arg_types) == 0
        return nil
      end

      if splat_restriction.is_a?(Splat)
        splat_arg_types = [] of Type
      end

      a_def.match(arg_types) do |arg, arg_index, arg_type, arg_type_index|
        # Don't match argument against splat restriction
        if arg_index == splat_index && splat_arg_types
          splat_arg_types << arg_type
          next
        end

        match_arg_type = arg_type.restrict(arg, context)
        if match_arg_type
          if !named_args && !splat_arg_types && match_arg_type.same?(arg_type) && arg_types.size == 1
            # Optimization: no need to create matched_arg_types if
            # the call has a single argument and it exactly matches the restriction
            break
          end

          matched_arg_types ||= [] of Type
          matched_arg_types.push match_arg_type
          mandatory_args[arg_index] = true if mandatory_args
        else
          return nil
        end
      end

      # Match splat arguments against splat restriction
      if splat_arg_types && splat_restriction.is_a?(Splat)
        tuple_type = context.instantiated_type.program.tuple_of(splat_arg_types)
        match_arg_type = tuple_type.restrict(splat_restriction.exp, context)
        unless match_arg_type
          return nil
        end

        matched_arg_types ||= [] of Type
        matched_arg_types.concat(splat_arg_types)
      end

      found_unmatched_named_arg = false

      if double_splat_restriction.is_a?(DoubleSplat)
        double_splat_entries = [] of NamedArgumentType
      end

      # Check named args
      if named_args
        min_index = signature.arg_types.size
        named_args.each do |named_arg|
          found_index = a_def.args.index { |arg| arg.external_name == named_arg.name }
          if found_index
            # A named arg can't target the splat index
            if found_index == splat_index
              return nil
            end

            # Check whether the named arg refers to an argument that was already specified
            if mandatory_args
              if mandatory_args[found_index]
                return nil
              end
              mandatory_args[found_index] = true
            else
              if found_index < min_index
                return nil
              end
            end

            match_arg_type = named_arg.type.restrict(a_def.args[found_index], context)
            unless match_arg_type
              return nil
            end

            matched_named_arg_types ||= [] of NamedArgumentType
            matched_named_arg_types << NamedArgumentType.new(named_arg.name, match_arg_type)
          else
            # If there's a double splat it's OK, the named arg will be put there
            if a_def.double_splat
              match_arg_type = named_arg.type

              # If there's a restriction on the double splat, check that it matches
              if double_splat_restriction
                if double_splat_entries
                  double_splat_entries << named_arg
                else
                  match_arg_type = named_arg.type.restrict(double_splat_restriction, context)
                  unless match_arg_type
                    return nil
                  end
                end
              end

              matched_named_arg_types ||= [] of NamedArgumentType
              matched_named_arg_types << NamedArgumentType.new(named_arg.name, match_arg_type)

              found_unmatched_named_arg = true
              next
            end

            return nil
          end
        end
      end

      # Match double splat arguments against double splat restriction
      if double_splat_entries && double_splat_restriction.is_a?(DoubleSplat)
        named_tuple_type = context.instantiated_type.program.named_tuple_of(double_splat_entries)
        value = named_tuple_type.restrict(double_splat_restriction.exp, context)
        unless value
          return nil
        end
      end

      # Check that all mandatory args were specified
      # (either with positional arguments or with named arguments)
      if mandatory_args
        a_def.args.each_with_index do |arg, index|
          if index != splat_index && !arg.default_value && !mandatory_args[index]
            return nil
          end
        end
      end

      # If there's a restriction on a double splat, zero matching named arguments don't match
      if double_splat && double_splat_restriction &&
         !double_splat_restriction.is_a?(DoubleSplat) && !found_unmatched_named_arg
        return nil
      end

      # We reuse a match context without free vars, but we create
      # new ones when there are free vars.
      context = context.clone if context.bound_free_vars

      Match.new(a_def, (matched_arg_types || arg_types), context, matched_named_arg_types)
    end

    def matches_exactly?(match : Match, *, with_autocast : Bool = false)
      arg_types_equal = self.arg_types.equals?(match.arg_types) do |x, y|
        x.compatible_with?(y)
      end
      if (match_named_args = match.named_arg_types) && (signature_named_args = self.named_args) &&
         match_named_args.size == signature_named_args.size
        match_named_args = match_named_args.sort_by &.name
        signature_named_args = signature_named_args.sort_by &.name
        named_arg_types_equal = signature_named_args.equals?(match_named_args) do |x, y|
          x.name == y.name && x.type.compatible_with?(y.type)
        end
      else
        named_arg_types_equal = !match.named_arg_types && !self.named_args
      end

      arg_types_equal && named_arg_types_equal
    end
  end

  class AliasType
    delegate lookup_matches, lookup_matches_without_parents, to: aliased_type
  end

  module VirtualTypeLookup
    record Change, type : ModuleType, def : Def

    def virtual_lookup(type)
      type
    end

    def lookup_matches(signature, owner = self, path_lookup = self, analyze_all = false)
      is_new = virtual_metaclass? && signature.name == "new"

      base_type_lookup = virtual_lookup(base_type)
      base_type_matches = base_type_lookup.lookup_matches(signature, self, analyze_all: analyze_all)

      # If there are no subclasses no need to look further
      if leaf?
        return base_type_matches
      end

      base_type_covers_all = base_type_matches.cover_all?

      # If the base type doesn't cover every possible type combination, it's a failure
      if !abstract? && !base_type_covers_all
        return Matches.new(base_type_matches.matches, base_type_matches.cover, base_type_lookup, false)
      end

      type_to_matches = nil
      matches = base_type_matches.matches
      changes = nil

      # Traverse all subtypes
      instance_type.subtypes(base_type).each do |subtype|
        subtype_lookup = virtual_lookup(subtype)
        subtype_virtual_lookup = virtual_lookup(subtype.virtual_type)

        # Check matches but without parents: only included modules
        subtype_matches = subtype_lookup.lookup_matches_with_modules(signature, subtype_virtual_lookup, subtype_virtual_lookup, analyze_all: analyze_all)

        # For Foo+.class#new we need to check that this subtype doesn't define
        # an incompatible initialize: if so, we return empty matches, because
        # all subtypes must have an initialize with the same number of arguments.
        if is_new && subtype_matches.empty?
          other_initializers = subtype_lookup.instance_type.lookup_defs_with_modules("initialize")
          unless other_initializers.empty?
            return Matches.new(nil, false)
          end
        end

        # If we didn't find a match in a subclass, and the base type match is a macro
        # def, we need to copy it to the subclass so that @name, @instance_vars and other
        # macro vars resolve correctly.
        if subtype_matches.empty?
          new_subtype_matches = nil

          base_type_matches.each do |base_type_match|
            if base_type_match.def.macro_def?
              # We need to force any `self` restrictions in the base type match
              # to refer to that base type, instead of whichever subtype is
              # currently used to evaluate the copied def. We must do this even
              # before any def is actually copied.
              old_self = base_type_match.def.self_restriction_type
              base_type_match.def.self_restriction_type = base_type

              # We need to copy each submatch if it's a macro def
              full_subtype_matches = subtype_lookup.lookup_matches(signature, subtype_virtual_lookup, subtype_virtual_lookup, analyze_all: analyze_all)
              full_subtype_matches.each do |full_subtype_match|
                cloned_def = full_subtype_match.def.clone
                cloned_def.macro_owner = full_subtype_match.def.macro_owner
                cloned_def.owner = subtype_lookup

                # We want to add this cloned def at the end, because if we search subtype matches
                # in the next iteration we will find it, and we don't want that.
                changes ||= [] of Change

                # On a generic instance type, we must add the macro method to the
                # generic type, not the instance (this will make it so that the method
                # is found on any generic instance type)
                change_owner = subtype_lookup
                change_owner = change_owner.generic_type if change_owner.is_a?(GenericInstanceType)

                if change_owner.is_a?(ModuleType)
                  changes << Change.new(change_owner, cloned_def)
                end

                new_subtype_matches ||= [] of Match
                new_subtype_matches.push Match.new(cloned_def, full_subtype_match.arg_types, MatchContext.new(subtype_lookup, full_subtype_match.context.defining_type, full_subtype_match.context.bound_free_vars), full_subtype_match.named_arg_types)
              end

              # Reset the `self` restriction override
              base_type_match.def.self_restriction_type = old_self
            end
          end

          if new_subtype_matches
            subtype_matches = Matches.new(new_subtype_matches, Cover.create(signature, new_subtype_matches))
          end
        end

        if !subtype.leaf? && subtype_matches.size > 0
          type_to_matches ||= {} of Type => Matches
          type_to_matches[subtype] = subtype_matches
        end

        # If the subtype is non-abstract but doesn't cover all,
        # we need to check if a parent covers it
        if !subtype.abstract? && !base_type_covers_all && !subtype_matches.cover_all?
          unless covered_by_superclass?(subtype, type_to_matches)
            return Matches.new(subtype_matches.matches, subtype_matches.cover, subtype_lookup, false)
          end
        end

        if !subtype_matches.empty? && (subtype_matches_matches = subtype_matches.matches)
          if subtype.abstract? && !self.is_a?(VirtualMetaclassType) && subtype.subclasses.empty?
            # No need to add matches if for an abstract class without subclasses
          else
            # We need to insert the matches before the previous ones
            # because subtypes are more specific matches
            if matches
              subtype_matches_matches.concat matches
            end
            matches = subtype_matches_matches
          end
        end
      end

      changes.try &.each do |change|
        change.type.add_def change.def
      end

      Matches.new(matches, !!(matches && matches.size > 0), self)
    end

    def covered_by_superclass?(subtype, type_to_matches)
      superclass = subtype.superclass
      while superclass && superclass != base_type
        superclass_matches = type_to_matches.try &.[superclass]?
        if superclass_matches && superclass_matches.cover_all?
          return true
        end
        superclass = superclass.superclass
      end
      false
    end
  end

  class VirtualMetaclassType
    def virtual_lookup(type)
      type.metaclass
    end
  end
end
