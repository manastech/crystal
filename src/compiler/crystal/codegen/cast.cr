require "./codegen"

# Here lies the logic to cast values between different types. There are three operations:
#
# ## Assign
#
# ```
# target_pointer : target_type <- value : value_type
# ```
#
# This happens when we store a value inside a variable (a variable is represented as
# pointer to the real value).
#
# If the type of the target and value are the same we can simply store the value inside
# the pointer.
#
# Otherwise, it's the case of a value having a "smaller" type than the variable's type,
# for example when assigning an Int32 into a union of Int32 | String, or when assigning
# a Bar into a Foo, with Bar < Foo, etc. In those cases we need to do some extra stuff,
# for example store the value's type id in the union and then the real value in the second
# slot of a union, casted to the union's type.
#
# ## Upcast
#
# ```
# (value : from_type).as(to_type)
# ```
#
# This happens when a value is "boxed" inside a "bigger" one. For example in this method:
#
# ```
# def foo
#   condition ? 1 : nil
# end
# ```
#
# foo's type is Int32 | Nil, with one branch of the 'if' being Int32 and the other Nil.
# In this case we need to "box" the Int32 value inside the union, and the same for Nil.
#
# This is different than doing an assign because we don't assign the value, we simply
# box it. Later that value might be stored inside a value with such type, but we keep
# it as two different operations because assigning involves fewer operations (to store
# a value inside a union we simply store the type id and the value, instead of allocating
# a union in the stack and the copying the union inside the final destination).
#
# ## Downcast
#
# ```
# (value : from_type).as(to_type)
# ```
#
# This happens when a value is casted from a "bigger" type to a "smaller" type. For example:
#
# ```
# def foo
#   condition ? 1 : nil
# end
#
# # 1.
# foo.as(Int32) # here a downcast happens, from `Int32 | Nil` to `Int32`
#
# # 2.
# if foo.is_a?(Int32)
#   foo # here a downcast happens, from `Int32 | Nil` to `Int32`
# end
# ```
#
# In this case we usually need to unbox a value from a union, or cast a more general
# type into a specific type (such as when casting a Foo to a Bar, with Bar < Foo).

class Crystal::CodeGenVisitor
  def assign(target_pointer, target_type, value_type, value)
    return if @builder.end

    target_type = target_type.remove_indirection
    value_type = value_type.remove_indirection

    if target_type == value_type
      if target_type.nil_type?
        value
      else
        store to_rhs(value, target_type), target_pointer
      end
    else
      assign_distinct target_pointer, target_type, value_type, value
    end
  end

  def assign_distinct(target_pointer, target_type : NilableReferenceType, value_type : Type, value)
    store upcast(value, target_type, value_type), target_pointer
  end

  def assign_distinct(target_pointer, target_type : ReferenceUnionType, value_type : ReferenceUnionType, value)
    store value, target_pointer
  end

  def assign_distinct(target_pointer, target_type : ReferenceUnionType, value_type : VirtualType, value)
    store value, target_pointer
  end

  def assign_distinct(target_pointer, target_type : ReferenceUnionType, value_type : Type, value)
    store cast_to(value, target_type), target_pointer
  end

  def assign_distinct(target_pointer, target_type : NilableReferenceUnionType, value_type : Type, value)
    store upcast(value, target_type, value_type), target_pointer
  end

  def assign_distinct(target_pointer, target_type : MixedUnionType, value_type : MixedUnionType, value)
    # It might happen that some types inside the union `value_type` are not inside `target_type`,
    # for example with named tuple of same keys with different order. In that case we need cast
    # those value to the correct type before finally storing them in the target union.
    needs_union_value_cast = value_type.union_types.any? do |vt|
      needs_value_cast_inside_union?(vt, target_type)
    end

    if needs_union_value_cast # Compute the values that need a cast
      types_needing_cast = value_type.union_types.select do |vt|
        needs_value_cast_inside_union?(vt, target_type)
      end
      # Fetch the value's type id
      value_type_id, union_value_ptr = union_type_and_value_pointer(value, value_type)

      exit_label = new_block "exit"

      types_needing_cast.each_with_index do |type_needing_cast, i|
        # Find compatible type
        compatible_type = target_type.union_types.find! { |ut| type_needing_cast.implements?(ut) }
        llvm_compatible_type = llvm_type(compatible_type)

        matches_label, doesnt_match_label = new_blocks "matches", "doesnt_match_label"
        cmp_result = equal?(value_type_id, type_id(type_needing_cast))
        cond cmp_result, matches_label, doesnt_match_label

        position_at_end matches_label

        # Store value
        casted_value = cast_to_pointer(union_value_ptr, type_needing_cast)
        compatible_ptr = alloca llvm_compatible_type
        assign(compatible_ptr, compatible_type, type_needing_cast, casted_value)
        store_in_union target_type, target_pointer, compatible_type, load(llvm_compatible_type, compatible_ptr)
        br exit_label

        position_at_end doesnt_match_label
      end

      assign_distinct_union_types(target_pointer, target_type, value_type, value)
      br exit_label

      position_at_end exit_label
    else
      assign_distinct_union_types(target_pointer, target_type, value_type, value)
    end
  end

  def needs_value_cast_inside_union?(value_type, union_type)
    # A type needs a special cast if:
    # 1. It's a tuple or named tuple
    # 2. It's not inside the target union
    # 3. There's a compatible type inside the target union
    return false unless value_type.is_a?(TupleInstanceType) || value_type.is_a?(NamedTupleInstanceType)
    !union_type.union_types.any?(&.==(value_type)) &&
      union_type.union_types.any? { |ut| value_type.implements?(ut) || ut.implements?(value_type) }
  end

  def assign_distinct(target_pointer, target_type : MixedUnionType, value_type : NilableReferenceType, value)
    store_in_union target_type, target_pointer, value_type, value
  end

  def assign_distinct(target_pointer, target_type : MixedUnionType, value_type : VoidType, value)
    store_void_in_union target_type, target_pointer
  end

  def assign_distinct(target_pointer, target_type : MixedUnionType, value_type : BoolType, value)
    store_bool_in_union target_type, target_pointer, value
  end

  def assign_distinct(target_pointer, target_type : MixedUnionType, value_type : NilType, value)
    store_nil_in_union target_type, target_pointer
  end

  def assign_distinct(target_pointer, target_type : MixedUnionType, value_type : Type, value)
    case value_type
    when TupleInstanceType, NamedTupleInstanceType
      # It might happen that `value_type` is not of the union but it's compatible with one of them.
      # We need to first cast the value to the compatible type and then store it in the value.
      unless target_type.union_types.any? &.==(value_type)
        compatible_type = target_type.union_types.find! { |ut| value_type.implements?(ut) }
        value = upcast(value, compatible_type, value_type)
        return assign(target_pointer, target_type, compatible_type, value)
      end
    end

    value = to_rhs(value, value_type)
    store_in_union target_type, target_pointer, value_type, value
  end

  def assign_distinct(target_pointer, target_type : VirtualType, value_type : MixedUnionType, value)
    _, union_value_ptr = union_type_and_value_pointer(value, value_type)
    casted_value = cast_to_pointer(union_value_ptr, target_type)
    store load(llvm_type(target_type), casted_value), target_pointer
  end

  def assign_distinct(target_pointer, target_type : VirtualType, value_type : Type, value)
    store cast_to(value, target_type), target_pointer
  end

  def assign_distinct(target_pointer, target_type : VirtualMetaclassType, value_type : MetaclassType | GenericClassInstanceMetaclassType | GenericModuleInstanceMetaclassType | VirtualMetaclassType, value)
    store value, target_pointer
  end

  def assign_distinct(target_pointer, target_type : VirtualMetaclassType, value_type : UnionType, value)
    # Can happen when assigning Foo+.class <- Bar.class | Baz.class with Bar < Foo and Baz < Foo
    _, union_value_ptr = union_type_and_value_pointer(value, value_type)
    casted_value = cast_to_pointer(union_value_ptr, target_type)
    store load(llvm_type(target_type), casted_value), target_pointer
  end

  def assign_distinct(target_pointer, target_type : NilableProcType, value_type : NilType, value)
    nilable_fun = make_nilable_fun target_type
    store nilable_fun, target_pointer
  end

  def assign_distinct(target_pointer, target_type : NilableProcType, value_type : ProcInstanceType, value)
    store value, target_pointer
  end

  def assign_distinct(target_pointer, target_type : NilableProcType, value_type : TypeDefType, value)
    assign_distinct target_pointer, target_type, value_type.typedef, value
  end

  def assign_distinct(target_pointer, target_type : TupleInstanceType, value_type : TupleInstanceType, value)
    target_struct_type = llvm_type(target_type)
    value_struct_type = llvm_type(value_type)

    index = 0
    target_type.tuple_types.zip(value_type.tuple_types) do |target_tuple_type, value_tuple_type|
      target_ptr = aggregate_index(target_struct_type, target_pointer, index)
      value_ptr = aggregate_index(value_struct_type, value, index)
      loaded_value = to_lhs(value_ptr, value_tuple_type)
      assign(target_ptr, target_tuple_type, value_tuple_type, loaded_value)
      index += 1
    end
    value
  end

  def assign_distinct(target_pointer, target_type : NamedTupleInstanceType, value_type : NamedTupleInstanceType, value)
    target_struct_type = llvm_type(target_type)
    value_struct_type = llvm_type(value_type)

    value_type.entries.each_with_index do |entry, index|
      value_ptr = aggregate_index(value_struct_type, value, index)
      value_at_index = to_lhs(value_ptr, entry.type)
      target_index = target_type.name_index(entry.name).not_nil!
      target_index_type = target_type.name_type(entry.name)
      target_ptr = aggregate_index(target_struct_type, target_pointer, target_index)
      assign target_ptr, target_index_type, entry.type, value_at_index
    end
  end

  def assign_distinct(target_pointer, target_type : ProcInstanceType, value_type : ProcInstanceType, value)
    # Cast of a non-void proc to a void proc
    value = to_rhs(value, target_type)
    store value, target_pointer
  end

  def assign_distinct(target_pointer, target_type : ProcInstanceType, value_type : MixedUnionType, value)
    # The only case when a union is assigned to a proc is when
    # target_type is Proc(*T, Nil) and all the types in the union are Proc(*T, R).
    # In that case we can simply get the union value and cast it to the target type.
    # Cast of a non-void proc to a void proc
    _, union_value_ptr = union_type_and_value_pointer(value, value_type)
    value = cast_to_pointer(union_value_ptr, target_type)
    store load(llvm_type(target_type), value), target_pointer
  end

  def assign_distinct(target_pointer, target_type : Type, value_type : Type, value)
    raise "BUG: trying to assign #{target_type} (#{target_type.class}) <- #{value_type} (#{value_type.class})"
  end

  def downcast(value, to_type, from_type : VoidType, already_loaded, *, extern = false)
    value
  end

  # *extern* is only used in `CodeGenVisitor#read_instance_var`, and it is
  # irrelevant whenever `already_loaded == true`
  def downcast(value, to_type, from_type : Type, already_loaded, *, extern = false)
    return llvm_nil if @builder.end

    from_type = from_type.remove_indirection
    to_type = to_type.remove_indirection

    unless already_loaded
      value = extern ? extern_to_lhs(value, from_type) : to_lhs(value, from_type)
    end
    if from_type != to_type
      value = downcast_distinct value, to_type, from_type
    end
    value
  end

  def downcast_distinct(value, to_type : NilType, from_type : Type)
    llvm_nil
  end

  def downcast_distinct(value, to_type, from_type : MetaclassType | GenericClassInstanceMetaclassType | GenericModuleInstanceMetaclassType | VirtualMetaclassType)
    value
  end

  def downcast_distinct(value, to_type : VirtualType, from_type : VirtualType)
    value
  end

  def downcast_distinct(value, to_type : ReferenceUnionType, from_type : VirtualType)
    # This happens if the restriction is a union:
    # we keep each of the union types as the result, we don't fully merge
    value
  end

  def downcast_distinct(value, to_type : NonGenericClassType | GenericClassInstanceType, from_type : VirtualType)
    cast_to value, to_type
  end

  def downcast_distinct(value, to_type : VirtualType, from_type : NilableReferenceType)
    cast_to value, to_type
  end

  def downcast_distinct(value, to_type : Type, from_type : NilableReferenceType)
    value
  end

  def downcast_distinct(value, to_type : ProcInstanceType, from_type : NilableProcType)
    value
  end

  def downcast_distinct(value, to_type : TypeDefType, from_type : NilableProcType)
    downcast_distinct value, to_type.typedef, from_type
  end

  def downcast_distinct(value, to_type : PointerInstanceType, from_type : PointerInstanceType)
    # cast of a pointer being cast to Void*
    cast_to_void_pointer value
  end

  def downcast_distinct(value, to_type : ReferenceUnionType, from_type : ReferenceUnionType)
    value
  end

  def downcast_distinct(value, to_type : VirtualType, from_type : ReferenceUnionType)
    value
  end

  def downcast_distinct(value, to_type : Type, from_type : ReferenceUnionType)
    cast_to value, to_type
  end

  def downcast_distinct(value, to_type : VirtualType, from_type : NilableReferenceUnionType)
    value
  end

  def downcast_distinct(value, to_type : ReferenceUnionType, from_type : NilableReferenceUnionType)
    value
  end

  def downcast_distinct(value, to_type : NilableReferenceType, from_type : NilableReferenceUnionType)
    cast_to value, to_type
  end

  def downcast_distinct(value, to_type : Type, from_type : NilableReferenceUnionType)
    cast_to value, to_type
  end

  def downcast_distinct(value, to_type : MixedUnionType, from_type : MixedUnionType)
    # It might happen that some types inside the union `from_type` are not inside `to_type`,
    # for example with named tuple of same keys with different order. In that case we need cast
    # those value to the correct type before finally storing them in the target union.
    needs_union_value_cast = from_type.union_types.any? do |vt|
      needs_value_cast_inside_union?(vt, to_type)
    end

    if needs_union_value_cast
      # Compute the values that need a cast
      types_needing_cast = from_type.union_types.select do |vt|
        needs_value_cast_inside_union?(vt, to_type)
      end

      # Fetch the value's type id
      from_type_id, union_value_ptr = union_type_and_value_pointer(value, from_type)

      Phi.open(self, to_type, @needs_value) do |phi|
        types_needing_cast.each_with_index do |type_needing_cast, i|
          # Find compatible type
          compatible_type = to_type.union_types.find!(&.implements?(type_needing_cast))

          matches_label, doesnt_match_label = new_blocks "matches", "doesnt_match_label"
          cmp_result = equal?(from_type_id, type_id(type_needing_cast))
          cond cmp_result, matches_label, doesnt_match_label

          position_at_end matches_label

          casted_value = cast_to_pointer(union_value_ptr, type_needing_cast)
          downcasted_value = downcast(casted_value, compatible_type, type_needing_cast, true)
          final_value = upcast(downcasted_value, to_type, compatible_type)
          phi.add final_value, to_type

          position_at_end doesnt_match_label
        end

        final_value = cast_to_pointer value, to_type
        phi.add final_value, to_type, last: true
      end
    else
      downcast_distinct_union_types(value, to_type, from_type)
    end
  end

  def downcast_distinct(value, to_type : NilableReferenceType, from_type : MixedUnionType)
    _, value_ptr = union_type_and_value_pointer(value, from_type)
    load(llvm_type(to_type), cast_to_pointer(value_ptr, to_type))
  end

  def downcast_distinct(value, to_type : BoolType, from_type : MixedUnionType)
    _, value_ptr = union_type_and_value_pointer(value, from_type)
    value = cast_to_pointer(value_ptr, @program.int8)
    value = load(llvm_context.int8, value)
    trunc value, llvm_context.int1
  end

  def downcast_distinct(value, to_type : Type, from_type : MixedUnionType)
    # It might happen that to_type is not of the union but it's compatible with one of them.
    # We need to first cast the value to the compatible type and to to_type
    case to_type
    when TupleInstanceType, NamedTupleInstanceType
      unless from_type.union_types.any? &.==(to_type)
        compatible_type = from_type.union_types.find! { |ut| to_type.implements?(ut) }
        value = downcast(value, compatible_type, from_type, true)
        value = downcast(value, to_type, compatible_type, true)
        return value
      end
    end

    _, value_ptr = union_type_and_value_pointer(value, from_type)
    value = cast_to_pointer(value_ptr, to_type)
    to_lhs value, to_type
  end

  def downcast_distinct(value, to_type : ProcInstanceType, from_type : ProcInstanceType)
    # Nothing to do
    value
  end

  def downcast_distinct(value, to_type : TupleInstanceType, from_type : TupleInstanceType)
    target_struct_type = llvm_type(to_type)
    value_struct_type = llvm_type(from_type)
    target_pointer = alloca(target_struct_type)

    index = 0
    to_type.tuple_types.zip(from_type.tuple_types) do |target_tuple_type, value_tuple_type|
      target_ptr = aggregate_index(target_struct_type, target_pointer, index)
      value_ptr = aggregate_index(value_struct_type, value, index)
      loaded_value = to_lhs(value_ptr, value_tuple_type)
      downcasted_value = downcast(loaded_value, target_tuple_type, value_tuple_type, true)
      downcasted_value = to_rhs(downcasted_value, target_tuple_type)
      store downcasted_value, target_ptr
      index += 1
    end
    target_pointer
  end

  def downcast_distinct(value, to_type : NamedTupleInstanceType, from_type : NamedTupleInstanceType)
    target_struct_type = llvm_type(to_type)
    value_struct_type = llvm_type(from_type)
    target_pointer = alloca(target_struct_type)

    from_type.entries.each_with_index do |entry, index|
      value_ptr = aggregate_index(value_struct_type, value, index)
      value_at_index = to_lhs(value_ptr, entry.type)
      target_index = to_type.name_index(entry.name).not_nil!
      target_index_type = to_type.name_type(entry.name)
      downcasted_value = downcast(value_at_index, target_index_type, entry.type, true)
      downcasted_value = to_rhs(downcasted_value, target_index_type)
      store downcasted_value, aggregate_index(target_struct_type, target_pointer, target_index)
    end
    target_pointer
  end

  # This is the case of the automatic cast between integer types
  def downcast_distinct(value, to_type : IntegerType, from_type : IntegerType)
    codegen_cast(from_type, to_type, value)
  end

  # This is the case of the automatic cast between integer type and float type
  def downcast_distinct(value, to_type : FloatType, from_type : IntegerType)
    codegen_cast(from_type, to_type, value)
  end

  # This is the case of the automatic cast between float types
  def downcast_distinct(value, to_type : FloatType, from_type : FloatType)
    codegen_cast(from_type, to_type, value)
  end

  # This is the case of the automatic cast between symbol and enum
  def downcast_distinct(value, to_type : EnumType, from_type : SymbolType)
    # value has the value of the symbol inside the symbol table,
    # so we first get which symbol name that is, and then match
    # it to one of the enum members
    index = value.const_int_get_sext_value
    symbol = @symbols_by_index[index].underscore

    to_type.types.each do |name, value|
      if name.underscore == symbol
        accept(value.as(Const).value)
        return @last
      end
    end

    raise "Bug: expected to find enum member of #{to_type} matching symbol #{symbol}"
  end

  def downcast_distinct(value, to_type : Type, from_type : Type)
    raise "BUG: trying to downcast #{to_type} (#{to_type.class}) <- #{from_type} (#{from_type.class})"
  end

  def upcast(value, to_type, from_type)
    return llvm_nil if @builder.end

    from_type = from_type.remove_indirection
    to_type = to_type.remove_indirection

    if to_type != from_type
      value = upcast_distinct(value, to_type, from_type)
    end
    value
  end

  def upcast_distinct(value, to_type : MetaclassType | GenericClassInstanceMetaclassType | GenericModuleInstanceMetaclassType | VirtualMetaclassType, from_type)
    value
  end

  def upcast_distinct(value, to_type : VirtualType, from_type)
    cast_to value, to_type
  end

  def upcast_distinct(value, to_type : NilableReferenceType, from_type : NilType?)
    llvm_type(to_type).null
  end

  def upcast_distinct(value, to_type : NilableReferenceType, from_type : Type)
    value
  end

  def upcast_distinct(value, to_type : NilableReferenceUnionType, from_type : NilType?)
    llvm_type(to_type).null
  end

  def upcast_distinct(value, to_type : NilableReferenceUnionType, from_type : Type)
    cast_to value, to_type
  end

  def upcast_distinct(value, to_type : NilableProcType, from_type : NilType)
    make_nilable_fun to_type
  end

  def upcast_distinct(value, to_type : NilableProcType, from_type : ProcInstanceType)
    value
  end

  def upcast_distinct(value, to_type : NilableProcType, from_type : TypeDefType)
    upcast_distinct value, to_type, from_type.typedef
  end

  def upcast_distinct(value, to_type : ReferenceUnionType, from_type)
    cast_to value, to_type
  end

  def upcast_distinct(value, to_type : MixedUnionType, from_type : MixedUnionType)
    # It might happen that some types inside the union `from_type` are not inside `to_type`,
    # for example with named tuple of same keys with different order. In that case we need cast
    # those value to the correct type before finally storing them in the target union.
    needs_union_value_cast = from_type.union_types.any? do |vt|
      needs_value_cast_inside_union?(vt, to_type)
    end

    if needs_union_value_cast
      # Compute the values that need a cast
      types_needing_cast = from_type.union_types.select do |vt|
        needs_value_cast_inside_union?(vt, to_type)
      end

      # Fetch the value's type id
      from_type_id, union_value_ptr = union_type_and_value_pointer(value, from_type)

      Phi.open(self, to_type, @needs_value) do |phi|
        types_needing_cast.each_with_index do |type_needing_cast, i|
          # Find compatible type
          compatible_type = to_type.union_types.find! { |ut| type_needing_cast.implements?(ut) }

          matches_label, doesnt_match_label = new_blocks "matches", "doesnt_match_label"
          cmp_result = equal?(from_type_id, type_id(type_needing_cast))
          cond cmp_result, matches_label, doesnt_match_label

          position_at_end matches_label

          casted_value = cast_to_pointer(union_value_ptr, type_needing_cast)
          upcasted_value = upcast(casted_value, compatible_type, type_needing_cast)
          final_value = upcast(upcasted_value, to_type, compatible_type)
          phi.add final_value, to_type

          position_at_end doesnt_match_label
        end

        final_value = cast_to_pointer value, to_type
        phi.add final_value, to_type, last: true
      end
    else
      upcast_distinct_union_types(value, to_type, from_type)
    end
  end

  def upcast_distinct(value, to_type : MixedUnionType, from_type : VoidType)
    union_ptr = alloca(llvm_type(to_type))
    store_void_in_union to_type, union_ptr
    union_ptr
  end

  def upcast_distinct(value, to_type : MixedUnionType, from_type : BoolType)
    union_ptr = alloca(llvm_type(to_type))
    store_bool_in_union to_type, union_ptr, value
    union_ptr
  end

  def upcast_distinct(value, to_type : MixedUnionType, from_type : NilType)
    union_ptr = alloca(llvm_type(to_type))
    store_nil_in_union to_type, union_ptr
    union_ptr
  end

  def upcast_distinct(value, to_type : MixedUnionType, from_type : Type)
    # It might happen that from_type is not of the union but it's compatible with one of them.
    # We need to first cast the value to the compatible type and to to_type
    case from_type
    when TupleInstanceType, NamedTupleInstanceType
      unless to_type.union_types.any? &.==(from_type)
        compatible_type = to_type.union_types.find! { |ut| from_type.implements?(ut) }
        value = upcast(value, compatible_type, from_type)
        return upcast(value, to_type, compatible_type)
      end
    end

    union_ptr = alloca(llvm_type(to_type))
    store_in_union(to_type, union_ptr, from_type, to_rhs(value, from_type))
    union_ptr
  end

  def upcast_distinct(value, to_type : EnumType, from_type : Type)
    value
  end

  def upcast_distinct(value, to_type : TupleInstanceType, from_type : TupleInstanceType)
    target_ptr = alloca llvm_type(to_type)
    assign(target_ptr, to_type, from_type, value)
    target_ptr
  end

  def upcast_distinct(value, to_type : NamedTupleInstanceType, from_type : NamedTupleInstanceType)
    target_ptr = alloca llvm_type(to_type)
    assign(target_ptr, to_type, from_type, value)
    target_ptr
  end

  def upcast_distinct(value, to_type : GenericClassInstanceType, from_type : Type)
    cast_to value, to_type
  end

  def upcast_distinct(value, to_type : Type, from_type : Type)
    raise "BUG: trying to upcast #{to_type} (#{to_type.class}) <- #{from_type} (#{from_type.class})"
  end
end
