require "./compiler"

# Logic to transform a value in the stack to a boolean value.

class Crystal::Repl::Compiler
  private def value_to_bool(node : ASTNode, type : NilType)
    put_false node: nil
  end

  private def value_to_bool(node : ASTNode, type : BoolType)
    # Nothing to do
  end

  private def value_to_bool(node : ASTNode, type : PointerInstanceType)
    pointer_is_not_null node: nil
  end

  private def value_to_bool(node : ASTNode, type : NilableProcType)
    # We have {pointer, closure_data} and we need to check if pointer is not null
    pop 8, node: nil
    pointer_is_not_null node: nil
  end

  private def value_to_bool(node : ASTNode, type : NilableReferenceType)
    pointer_is_not_null node: nil
  end

  private def value_to_bool(node : ASTNode, type : NilableReferenceUnionType)
    pointer_is_not_null node: nil
  end

  private def value_to_bool(node : ASTNode, type : MixedUnionType)
    union_to_bool aligned_sizeof_type(type), node: nil
  end

  private def value_to_bool(node : ASTNode, type : NonGenericClassType | GenericClassInstanceType | VirtualType | MetaclassType | VirtualMetaclassType | ReferenceUnionType | IntegerType | CharType | SymbolType | FloatType | EnumType | NonGenericModuleType | GenericModuleInstanceType | GenericModuleInstanceMetaclassType | GenericClassInstanceMetaclassType)
    pop aligned_sizeof_type(type), node: nil
    put_true node: nil
  end

  private def value_to_bool(node : ASTNode, type : TypeDefType)
    # TODO: not tested
    value_to_bool node, type.typedef
  end

  private def value_to_bool(node : ASTNode, type : NoReturnType)
    # Nothing to do
  end

  private def value_to_bool(node : ASTNode, type : Type)
    node.raise "BUG: missing value_to_bool for #{type} (#{type.class})"
  end
end
