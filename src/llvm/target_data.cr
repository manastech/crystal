struct LLVM::TargetData
  def initialize(@unwrap : LibLLVM::TargetDataRef)
  end

  def size_in_bits(type)
    LibLLVM.size_of_type_in_bits(self, type)
  end

  def size_in_bytes(type)
    size_in_bits = size_in_bits(type)
    size_in_bits // 8 &+ (size_in_bits & 0x7 != 0 ? 1 : 0)
  end

  def abi_size(type)
    LibLLVM.abi_size_of_type(self, type)
  end

  def abi_alignment(type)
    LibLLVM.abi_alignment_of_type(self, type)
  end

  def dispose : Nil
    LibLLVM.dispose_target_data(self)
  end

  def to_unsafe
    @unwrap
  end

  def offset_of_element(struct_type, element)
    # element_count = LibLLVM.count_struct_element_types(struct_type)
    # raise "Invalid element idx!" unless element < element_count
    LibLLVM.offset_of_element(self, struct_type, element)
  end

  def to_data_layout_string : String
    LLVM.string_and_dispose(LibLLVM.copy_string_rep_of_target_data(self))
  end
end
