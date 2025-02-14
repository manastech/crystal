require "./codegen"

class Crystal::CodeGenVisitor
  def codegen_cond(type)
    codegen_cond_impl(type.remove_indirection)
  end

  private def codegen_cond_impl(type : NilType)
    llvm_false
  end

  private def codegen_cond_impl(type : BoolType)
    @last
  end

  private def codegen_cond_impl(type : TypeDefType)
    codegen_cond type.typedef
  end

  private def codegen_cond_impl(type : NilableReferenceType | NilableReferenceUnionType | PointerInstanceType)
    not_null_pointer? @last
  end

  private def codegen_cond_impl(type : NilableProcType)
    fun_ptr = extract_value @last, 0
    not_null_pointer? fun_ptr
  end

  private def codegen_cond_impl(type : MixedUnionType)
    union_types = type.expand_union_types

    has_nil = union_types.any? &.nil_type?
    has_bool = union_types.any? &.bool_type?
    has_pointer = union_types.any?(PointerInstanceType)

    cond = llvm_true

    if has_nil || has_bool || has_pointer
      type_id, value_ptr = union_type_and_value_pointer(@last, type)

      if has_nil
        is_nil = equal? type_id, type_id(@program.nil)
        cond = and cond, not(is_nil)
      end

      if has_bool
        value = load(llvm_context.int1, pointer_cast value_ptr, llvm_context.int1.pointer)
        is_bool = equal? type_id, type_id(@program.bool)
        cond = and cond, not(and(is_bool, not(value)))
      end

      if has_pointer
        union_types.each do |union_type|
          next unless union_type.is_a?(PointerInstanceType)

          is_pointer = equal? type_id, type_id(union_type)
          pointer_value = load(llvm_type(union_type), cast_to_pointer(value_ptr, union_type))
          pointer_null = null_pointer?(pointer_value)
          cond = and cond, not(and(is_pointer, pointer_null))
        end
      end
    end

    cond
  end

  private def codegen_cond_impl(type : Type)
    llvm_true
  end
end
