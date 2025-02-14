require "./codegen"

class Crystal::CodeGenVisitor
  def type_id(value, type)
    type_id_impl(value, type.remove_indirection)
  end

  def type_id(type)
    type_id_impl(type.remove_indirection)
  end

  private def type_id_impl(value, type : NilableReferenceType)
    builder.select null_pointer?(value), type_id(@program.nil), type_id(type.not_nil_type)
  end

  private def type_id_impl(value, type : ReferenceUnionType)
    load(llvm_context.int32, value)
  end

  private def type_id_impl(value, type : VirtualType)
    load(llvm_context.int32, value)
  end

  private def type_id_impl(value, type : NilableReferenceUnionType)
    nil_block, not_nil_block, exit_block = new_blocks "nil", "not_nil", "exit"
    phi_table = LLVM::PhiTable.new

    cond null_pointer?(value), nil_block, not_nil_block

    position_at_end nil_block
    phi_table.add insert_block, type_id(@program.nil)
    br exit_block

    position_at_end not_nil_block
    phi_table.add insert_block, load(llvm_context.int32, value)
    br exit_block

    position_at_end exit_block
    phi llvm_context.int32, phi_table
  end

  private def type_id_impl(value, type : NilableProcType)
    fun_ptr = extract_value value, 0
    builder.select null_pointer?(fun_ptr), type_id(@program.nil), type_id(type.proc_type)
  end

  private def type_id_impl(value, type : VirtualMetaclassType)
    value
  end

  private def type_id_impl(value, type : Program)
    type_id(type)
  end

  private def type_id_impl(value, type : FileModule)
    type_id(type)
  end

  private def type_id_impl(value, type : AliasType)
    type_id value, type.aliased_type
  end

  private def type_id_impl(value, type)
    type_id(type)
  end

  private def type_id_impl(type)
    int(@program.llvm_id.type_id(type))
  end
end
