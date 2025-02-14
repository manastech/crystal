require "./compiler"

# In this file we define the operations that cast types to other types,
# be it to expand them to fit "bigger" types (upcast) or to shrink them
# when a type is restricted, like when using `is_a?` (downcast).
# This is similar to codegen/cast.cr except that instead of producing
# LLVM code it works on the value on the top of the stack.
class Crystal::Repl::Compiler
  private def upcast(node : ASTNode, from : Type, to : Type)
    from = from.remove_indirection
    to = to.remove_indirection

    return if from == to

    upcast_distinct(node, from, to)
  end

  private def upcast(node : ASTNode, from : Nil, to : Type)
    # Nothing to do when casting from nil (NoReturn), as it's NoReturn
  end

  private def upcast_distinct(node : ASTNode, from : TypeDefType, to : Type)
    upcast_distinct node, from.typedef, to
  end

  private def upcast_distinct(node : ASTNode, from : NilableReferenceType, to : MixedUnionType)
    put_nilable_type_in_union(aligned_sizeof_type(to), node: nil)
  end

  private def upcast_distinct(node : ASTNode, from : MixedUnionType, to : MixedUnionType)
    # It might happen that some types inside the union `value_type` are not inside `target_type`,
    # for example with named tuple of same keys with different order. In that case we need cast
    # those value to the correct type before finally storing them in the target union.
    needs_union_value_cast = from.union_types.any? do |from_element|
      needs_value_cast_inside_union?(from_element, to)
    end

    if needs_union_value_cast
      # Compute the values that need a cast
      types_needing_cast = from.union_types.select do |union_type|
        needs_value_cast_inside_union?(union_type, to)
      end

      end_jumps = [] of Int32

      types_needing_cast.each do |type_needing_cast|
        # Find compatible type
        compatible_type = to.union_types.find! { |union_type| type_needing_cast.implements?(union_type) }

        # Get the type id of the "from" union
        from_type_id = get_union_type_id(aligned_sizeof_type(from), node: node)

        # Check if `from_type_id` is the same as `type_needing_cast`
        put_i32 type_id(type_needing_cast), node: node
        cmp_i32 node: node
        cmp_eq node: node

        # If they are not the same, continue
        branch_unless 0, node: nil
        cond_jump_location = patch_location

        # We need to upcast from type_needing_cast to compatible_type
        upcast(node, type_needing_cast, compatible_type)

        # Then we need to set the correct union type id
        put_union_type_id(type_id(compatible_type), aligned_sizeof_type(to), node: node)

        # Then jump to the end
        jump 0, node: nil
        end_jumps << patch_location

        # The unless above should jump here, which is the start
        # of the next if, or just the end
        patch_jump(cond_jump_location)
      end
    end

    # Putting a smaller union type inside a bigger one is just extending the value
    difference = aligned_sizeof_type(to) - aligned_sizeof_type(from)

    if difference > 0
      push_zeros(difference, node: nil)
    end

    # If needs_union_value_cast was true, we have a bunch of
    # if .. then that need to jump to the end of everything.
    # Here we do that.
    if end_jumps
      end_jumps.each do |end_jump|
        patch_jump(end_jump)
      end
    end
  end

  private def needs_value_cast_inside_union?(value_type, union_type)
    # A type needs a special cast if:
    # 1. It's a tuple or named tuple
    # 2. It's not inside the target union
    # 3. There's a compatible type inside the target union
    return false unless value_type.is_a?(TupleInstanceType) || value_type.is_a?(NamedTupleInstanceType)
    !union_type.union_types.any?(&.==(value_type)) &&
      union_type.union_types.any? { |ut| value_type.implements?(ut) || ut.implements?(value_type) }
  end

  private def upcast_distinct(node : ASTNode, from : NilType, to : MixedUnionType)
    # Nil inside a union is all zeros
    push_zeros(aligned_sizeof_type(to), node: nil)
  end

  private def upcast_distinct(node : ASTNode, from : PrimitiveType | EnumType | NonGenericClassType | GenericClassInstanceType | GenericClassInstanceMetaclassType | MetaclassType, to : MixedUnionType)
    # It might happen that `from` is not of the union but it's compatible with one of them.
    # We need to first cast the value to the compatible type and to `to`.
    # This same logic exists in codegen/cast.cr
    case from
    when TupleInstanceType, NamedTupleInstanceType
      unless to.union_types.any? &.==(from)
        compatible_type = to.union_types.find! { |ut| from.implements?(ut) }
        upcast(node, from, compatible_type)
        return upcast(node, compatible_type, to)
      end
    end

    put_in_union(type_id(from), aligned_sizeof_type(from), aligned_sizeof_type(to), node: nil)
  end

  private def upcast_distinct(node : ASTNode, from : VirtualMetaclassType, to : MixedUnionType)
    # We have a type ID (8 bytes) in the stack.
    # We need to put that into a union whose:
    # - tag will be the type ID (8 bytes)
    # - value will be the type ID (8 bytes) followed by zeros to fill up the union size

    # We already have 8 bytes in the stack. That's the tag.
    # Now we put the type ID again for the value. So far we have 16 bytes in total.
    dup 8, node: nil

    # Then fill out the rest of the union
    remaining = aligned_sizeof_type(to) - 16
    push_zeros remaining, node: nil if remaining > 0
  end

  private def upcast_distinct(node : ASTNode, from : ReferenceUnionType | NilableReferenceUnionType | VirtualType, to : MixedUnionType)
    put_reference_type_in_union(aligned_sizeof_type(to), node: nil)
  end

  private def upcast_distinct(node : ASTNode, from : VirtualType, to : VirtualType)
    # TODO: not tested
    # Nothing to do: both are represented as pointers which already carry the type ID
  end

  private def upcast_distinct(node : ASTNode, from : ReferenceUnionType, to : VirtualType)
    # TODO: not tested
    # Nothing to do: both are represented as pointers which already carry the type ID
  end

  private def upcast_distinct(node : ASTNode, from : NonGenericClassType, to : VirtualType)
    # Nothing: both are represented as pointers
  end

  private def upcast_distinct(node : ASTNode, from : GenericClassInstanceType, to : VirtualType)
    # TODO: not tested
    # Nothing to do: both are represented as pointers which already carry the type ID
  end

  private def upcast_distinct(node : ASTNode, from : NilableReferenceType | NilableReferenceUnionType, to : NilType)
    # TODO: not tested
    # TODO: this is actually a downcast so it's not right, but this is also present
    # in the main compiler so something should be fixed there first
    pop aligned_sizeof_type(from), node: nil
  end

  private def upcast_distinct(node : ASTNode, from : NilType, to : NilableReferenceType)
    put_i64 0_i64, node: nil
  end

  private def upcast_distinct(node : ASTNode, from : Type, to : NilableReferenceType)
    # Nothing: both are represented as pointers
  end

  private def upcast_distinct(node : ASTNode, from : NilType, to : NilableReferenceUnionType)
    # Transform nil (nothing) into a null pointer
    put_i64 0_i64, node: nil
  end

  private def upcast_distinct(node : ASTNode, from : Type, to : NilableReferenceUnionType)
    # Nothing: both are represented as pointers
  end

  private def upcast_distinct(node : ASTNode, from : Type, to : ReferenceUnionType)
    # Nothing: both are represented as pointers
  end

  private def upcast_distinct(node : ASTNode, from : NilType, to : NilableProcType)
    # This is Proc.new(Pointer(Void).null, Pointer(Void).null)
    put_i64 0, node: nil
    put_i64 0, node: nil
  end

  private def upcast_distinct(node : ASTNode, from : ProcInstanceType, to : ProcInstanceType)
    # TODO: not tested (happens for example with Proc(NoReturn) to Proc(Nil))
    # Nothing
  end

  private def upcast_distinct(node : ASTNode, from : ProcInstanceType, to : NilableProcType)
    # Nothing
  end

  # TODO: remove these two because they are probably not needed
  private def upcast_distinct(node : ASTNode, from : NoReturnType, to : Type)
    # Nothing
  end

  private def upcast_distinct(node : ASTNode, from : Type, to : NoReturnType)
    # Nothing
  end

  private def upcast_distinct(node : ASTNode, from : EnumType, to : IntegerType)
    # TODO: not tested
    # Nothing
  end

  private def upcast_distinct(node : ASTNode, from : TupleInstanceType, to : TupleInstanceType)
    # If we are here it means the tuples are different
    cast_tuple(node, from, to)

    # Finally, we must pop the original tuple that was casted
    pop_from_offset aligned_sizeof_type(from), aligned_sizeof_type(to), node: nil
  end

  private def upcast_distinct(node : ASTNode, from : NamedTupleInstanceType, to : NamedTupleInstanceType)
    # If we are here it means the tuples are different
    cast_named_tuple(node, from, to)

    # Finally, we must pop the original tuple that was casted
    pop_from_offset aligned_sizeof_type(from), aligned_sizeof_type(to), node: nil
  end

  # Unpacks a tuple into a series of types.
  # Each of the tuple elements is upcasted to the corresponding type in `to_types`.
  # Every individual element is stack-aligned. Use `#cast_tuple` instead if they
  # should follow their natural alignments inside a target tuple type.
  # It's the caller's responsibility to pop the original, unpacked tuple, from the
  # stack if needed.
  private def unpack_tuple(node : ASTNode, from : TupleInstanceType, to_types : Array(Type))
    from_aligned_size = aligned_sizeof_type(from)
    to_element_offset = 0

    to_types.each_with_index do |to_element_type, i|
      from_element_type = from.tuple_types[i]

      from_inner_size = inner_sizeof_type(from_element_type)

      from_element_offset = @context.offset_of(from, i)

      # Copy inner size bytes from the tuple.
      # The interpreter will make sure to align this value.
      # Go back `from_aligned_size` plus any elements already pushed onto the stack,
      # but then move forward (subtracting) to reach the element in `from`.
      copy_from(from_aligned_size - from_element_offset + to_element_offset, from_inner_size, node: nil)

      # Then upcast it to the target tuple element type
      upcast node, from_element_type, to_element_type

      # Now we have element_type in front of the tuple so we must skip it
      to_element_offset += aligned_sizeof_type(to_element_type)
    end
  end

  private def cast_tuple(node : ASTNode, from : TupleInstanceType, to : TupleInstanceType)
    from_aligned_size = aligned_sizeof_type(from)
    to_aligned_size = aligned_sizeof_type(to)
    to_element_offset = 0

    to.tuple_types.each_with_index do |to_element_type, i|
      from_element_type = from.tuple_types[i]

      from_inner_size = inner_sizeof_type(from_element_type)

      from_element_offset = @context.offset_of(from, i)

      # Copy inner size bytes from the tuple.
      # The interpreter will make sure to align this value.
      # Go back `from_aligned_size` plus any elements already pushed onto the stack,
      # but then move forward (subtracting) to reach the element in `from`.
      copy_from(from_aligned_size - from_element_offset + to_element_offset, from_inner_size, node: nil)

      # Then upcast it to the target tuple element type
      upcast node, from_element_type, to_element_type

      # the new value is stack-aligned; adjust as necessary to follow the
      # element's natural alignment inside the target type
      next_to_offset =
        if i == to.tuple_types.size - 1
          aligned_sizeof_type(to)
        else
          @context.offset_of(to, i + 1)
        end

      difference = next_to_offset - to_element_offset - aligned_sizeof_type(to_element_type)
      if difference > 0
        push_zeros(difference, node: nil)
      elsif difference < 0
        pop(-difference, node: nil)
      end

      # Now we have element_type in front of the tuple so we must skip it
      to_element_offset = next_to_offset
    end
  end

  private def cast_named_tuple(node : ASTNode, from : NamedTupleInstanceType, to : NamedTupleInstanceType)
    from_aligned_size = aligned_sizeof_type(from)
    to_aligned_size = aligned_sizeof_type(to)
    to_element_offset = 0

    from_entry_indices = to.entries.map_with_index do |to_entry, i|
      from.entries.index! do |other_entry|
        other_entry.name == to_entry.name
      end
    end

    to.entries.each_with_index do |to_entry, i|
      from_entry_index = from_entry_indices[i]
      from_entry = from.entries[from_entry_index]

      from_element_type = from_entry.type
      to_element_type = to_entry.type

      from_inner_size = inner_sizeof_type(from_element_type)

      from_element_offset = @context.offset_of(from, from_entry_index)

      # Copy inner size bytes from the tuple.
      # The interpreter will make sure to align this value.
      # Go back `from_aligned_size` plus any elements already pushed onto the stack,
      # but then move forward (subtracting) to reach the element in `from`.
      copy_from(from_aligned_size - from_element_offset + to_element_offset, from_inner_size, node: nil)

      # Then upcast it to the target tuple element type
      upcast node, from_element_type, to_element_type

      # the new value is stack-aligned; adjust as necessary to follow the
      # element's natural alignment inside the target type
      next_to_offset =
        if i == to.entries.size - 1
          aligned_sizeof_type(to)
        else
          @context.offset_of(to, i + 1)
        end

      difference = next_to_offset - to_element_offset - aligned_sizeof_type(to_element_type)
      if difference > 0
        push_zeros(difference, node: nil)
      elsif difference < 0
        pop(-difference, node: nil)
      end

      # Now we have element_type in front of the tuple so we must skip it
      to_element_offset = next_to_offset
    end
  end

  private def upcast_distinct(node : ASTNode, from : NilType, to : VoidType)
    # TODO: not tested
    # Nothing to do
  end

  private def upcast_distinct(node : ASTNode, from : MetaclassType | VirtualMetaclassType | GenericClassInstanceMetaclassType, to : VirtualMetaclassType)
  end

  private def upcast_distinct(node : ASTNode, from : Type, to : Type)
    node.raise "BUG: missing upcast_distinct from #{from} to #{to} (#{from.class} to #{to.class})"
  end

  private def downcast(node : ASTNode, from : Type, to : Type)
    from = from.remove_indirection
    to = to.remove_indirection

    return if from == to

    downcast_distinct(node, from, to)
  end

  private def downcast(node : ASTNode, from : Type, to : Nil)
    # Nothing to do when casting to nil (NoReturn)
  end

  private def downcast_distinct(node : ASTNode, from : Type, to : TypeDefType)
    downcast_distinct node, from, to.typedef
  end

  private def downcast_distinct(node : ASTNode, from : MixedUnionType, to : MixedUnionType)
    # It might happen that some types inside the union `from_type` are not inside `to_type`,
    # for example with named tuple of same keys with different order. In that case we need cast
    # those value to the correct type before finally storing them in the target union.
    needs_union_value_cast = from.union_types.any? do |from_element|
      needs_value_cast_inside_union?(from_element, to)
    end

    if needs_union_value_cast # Compute the values that need a cast
      node.raise "BUG: missing mixed union downcast from #{from} to #{to}"
    end

    difference = aligned_sizeof_type(from) - aligned_sizeof_type(to)

    if difference > 0
      pop(difference, node: nil)
    end
  end

  private def downcast_distinct(node : ASTNode, from : MixedUnionType, to : PrimitiveType | EnumType | NonGenericClassType | GenericClassInstanceType | GenericClassInstanceMetaclassType | NilableReferenceType | NilableProcType | NilableReferenceUnionType | ReferenceUnionType | MetaclassType | VirtualType | VirtualMetaclassType)
    remove_from_union(aligned_sizeof_type(from), aligned_sizeof_type(to), node: nil)
  end

  private def downcast_distinct(node : ASTNode, from : NilableReferenceType, to : NonGenericClassType | GenericClassInstanceType)
    # Nothing to do
  end

  private def downcast_distinct(node : ASTNode, from : NilableReferenceType, to : NilType)
    pop sizeof(Pointer(Void)), node: nil
  end

  private def downcast_distinct(node : ASTNode, from : NilableReferenceUnionType, to : VirtualType | NonGenericClassType | GenericClassInstanceType | NilableReferenceType)
    # Nothing to do
  end

  private def downcast_distinct(node : ASTNode, from : NilableReferenceUnionType, to : ReferenceUnionType)
    # TODO: not tested
    # Nothing to do
  end

  private def downcast_distinct(node : ASTNode, from : NilableReferenceUnionType, to : NilableReferenceUnionType)
    # TODO: not tested
    # Nothing to do
  end

  private def downcast_distinct(node : ASTNode, from : NilableReferenceUnionType, to : NilType)
    # TODO: not tested
    pop aligned_sizeof_type(from), node: nil
  end

  private def downcast_distinct(node : ASTNode, from : ReferenceUnionType, to : VirtualType | NonGenericClassType | GenericClassInstanceType | ReferenceUnionType)
    # Nothing to do
  end

  private def downcast_distinct(node : ASTNode, from : NilableProcType, to : ProcInstanceType)
    # Nothing to do
  end

  private def downcast_distinct(node : ASTNode, from : ProcInstanceType, to : ProcInstanceType)
    # Nothing to do
    # This is when Proc(T) is casted to Proc(Nil)
  end

  private def downcast_distinct(node : ASTNode, from : NilableProcType, to : NilType)
    # TODO: not tested
    pop 16, node: nil
  end

  private def downcast_distinct(node : ASTNode, from : VirtualType, to : NonGenericClassType | GenericClassInstanceType | ReferenceUnionType | NilableReferenceUnionType)
    # Nothing to do
  end

  private def downcast_distinct(node : ASTNode, from : VirtualType, to : VirtualType)
    # TODO: not tested
    # Nothing to do
  end

  private def downcast_distinct(node : ASTNode, from : VirtualMetaclassType, to : MetaclassType | VirtualMetaclassType | GenericClassInstanceMetaclassType | GenericModuleInstanceMetaclassType)
    # Nothing to do
  end

  # TODO: remove these two because they are probably not needed
  private def downcast_distinct(node : ASTNode, from : NoReturnType, to : Type)
    # Nothing
  end

  private def downcast_distinct(node : ASTNode, from : Type, to : NoReturnType)
    # Nothing
  end

  private def downcast_distinct(node : ASTNode, from : Type, to : Type)
    node.raise "BUG: missing downcast_distinct from #{from} to #{to} (#{from.class} to #{to.class})"
  end
end
