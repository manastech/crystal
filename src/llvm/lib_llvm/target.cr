require "./types"

lib LibLLVM
  type TargetDataRef = Void*

  fun initialize_aarch64_target_info = LLVMInitializeAArch64TargetInfo
  fun initialize_aarch64_target = LLVMInitializeAArch64Target
  fun initialize_aarch64_target_mc = LLVMInitializeAArch64TargetMC
  fun initialize_aarch64_asm_printer = LLVMInitializeAArch64AsmPrinter
  fun initialize_aarch64_asm_parser = LLVMInitializeAArch64AsmParser
  fun initialize_arm_target_info = LLVMInitializeARMTargetInfo
  fun initialize_arm_target = LLVMInitializeARMTarget
  fun initialize_arm_target_mc = LLVMInitializeARMTargetMC
  fun initialize_arm_asm_printer = LLVMInitializeARMAsmPrinter
  fun initialize_arm_asm_parser = LLVMInitializeARMAsmParser
  fun initialize_avr_target_info = LLVMInitializeAVRTargetInfo
  fun initialize_avr_target = LLVMInitializeAVRTarget
  fun initialize_avr_target_mc = LLVMInitializeAVRTargetMC
  fun initialize_avr_asm_printer = LLVMInitializeAVRAsmPrinter
  fun initialize_avr_asm_parser = LLVMInitializeAVRAsmParser
  fun initialize_webassembly_target_info = LLVMInitializeWebAssemblyTargetInfo
  fun initialize_webassembly_target = LLVMInitializeWebAssemblyTarget
  fun initialize_webassembly_target_mc = LLVMInitializeWebAssemblyTargetMC
  fun initialize_webassembly_asm_printer = LLVMInitializeWebAssemblyAsmPrinter
  fun initialize_webassembly_asm_parser = LLVMInitializeWebAssemblyAsmParser
  fun initialize_x86_target_info = LLVMInitializeX86TargetInfo
  fun initialize_x86_target = LLVMInitializeX86Target
  fun initialize_x86_target_mc = LLVMInitializeX86TargetMC
  fun initialize_x86_asm_printer = LLVMInitializeX86AsmPrinter
  fun initialize_x86_asm_parser = LLVMInitializeX86AsmParser

  fun set_module_data_layout = LLVMSetModuleDataLayout(m : ModuleRef, dl : TargetDataRef)

  fun create_target_data = LLVMCreateTargetData(string_rep : Char*) : TargetDataRef
  fun dispose_target_data = LLVMDisposeTargetData(td : TargetDataRef)
  fun copy_string_rep_of_target_data = LLVMCopyStringRepOfTargetData(td : TargetDataRef) : Char*
  fun size_of_type_in_bits = LLVMSizeOfTypeInBits(td : TargetDataRef, ty : TypeRef) : ULongLong
  fun abi_size_of_type = LLVMABISizeOfType(td : TargetDataRef, ty : TypeRef) : ULongLong
  fun abi_alignment_of_type = LLVMABIAlignmentOfType(td : TargetDataRef, ty : TypeRef) : UInt
  fun offset_of_element = LLVMOffsetOfElement(td : TargetDataRef, struct_ty : TypeRef, element : UInt) : ULongLong
  fun copy_string_rep_of_target_data = LLVMCopyStringRepOfTargetData(td : TargetDataRef) : Char*
end
