require "./target"
require "./types"

lib LibLLVM
  type TargetMachineRef = Void*
  type TargetRef = Void*

  fun get_first_target = LLVMGetFirstTarget : TargetRef
  fun get_next_target = LLVMGetNextTarget(t : TargetRef) : TargetRef
  fun get_target_from_triple = LLVMGetTargetFromTriple(triple : Char*, t : TargetRef*, error_message : Char**) : Bool
  fun get_target_name = LLVMGetTargetName(t : TargetRef) : Char*
  fun get_target_description = LLVMGetTargetDescription(t : TargetRef) : Char*

  fun create_target_machine = LLVMCreateTargetMachine(t : TargetRef, triple : Char*, cpu : Char*, features : Char*, level : LLVM::CodeGenOptLevel, reloc : LLVM::RelocMode, code_model : LLVM::CodeModel) : TargetMachineRef
  fun dispose_target_machine = LLVMDisposeTargetMachine(t : TargetMachineRef)
  fun get_target_machine_target = LLVMGetTargetMachineTarget(t : TargetMachineRef) : TargetRef
  fun get_target_machine_triple = LLVMGetTargetMachineTriple(t : TargetMachineRef) : Char*
  fun get_target_machine_cpu = LLVMGetTargetMachineCPU(t : TargetMachineRef) : Char*
  fun create_target_data_layout = LLVMCreateTargetDataLayout(t : TargetMachineRef) : TargetDataRef
  {% unless LibLLVM::IS_LT_180 %}
    fun set_target_machine_global_isel = LLVMSetTargetMachineGlobalISel(t : TargetMachineRef, enable : Bool)
    fun target_machine_emit_to_file = LLVMTargetMachineEmitToFile(t : TargetMachineRef, m : ModuleRef, filename : Char*, codegen : LLVM::CodeGenFileType, error_message : Char**) : Bool
  {% end %}

  fun get_default_target_triple = LLVMGetDefaultTargetTriple : Char*
  fun normalize_target_triple = LLVMNormalizeTargetTriple(triple : Char*) : Char*
  fun get_host_cpu_name = LLVMGetHostCPUName : Char*
end
