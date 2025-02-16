class LLVM::TargetMachine
  @layout : LLVM::TargetData?

  def initialize(@unwrap : LibLLVM::TargetMachineRef)
  end

  def target
    target = LibLLVM.get_target_machine_target(self)
    target ? Target.new(target) : raise "Couldn't get target"
  end

  def data_layout : LLVM::TargetData
    @layout ||= begin
      layout = LibLLVM.create_target_data_layout(self)
      raise "Missing layout for #{self}" unless layout
      layout = TargetData.new(layout)

      # LLVM 18 makes all 128-bit integers 16-byte-aligned for x86 and x86-64
      # targets, in order to support non-LLVM intrinsics that expect correctly
      # aligned integers; we backport this behavior to previous LLVM versions
      {% if LibLLVM::IS_LT_180 %}
        if target.name.in?("x86", "x86-64")
          data_layout = layout.to_data_layout_string
          unless data_layout.includes?("i128:128")
            layout.dispose
            layout = TargetData.new(LibLLVM.create_target_data(data_layout + "-i128:128"))
          end
        end
      {% end %}

      layout
    end
  end

  def triple : String
    triple_c = LibLLVM.get_target_machine_triple(self)
    LLVM.string_and_dispose(triple_c)
  end

  def cpu : String
    cpu_c = LibLLVM.get_target_machine_cpu(self)
    LLVM.string_and_dispose(cpu_c)
  end

  def emit_obj_to_file(llvm_mod, filename)
    emit_to_file llvm_mod, filename, LLVM::CodeGenFileType::ObjectFile
  end

  def emit_asm_to_file(llvm_mod, filename)
    emit_to_file llvm_mod, filename, LLVM::CodeGenFileType::AssemblyFile
  end

  def enable_global_isel=(enable : Bool)
    {{ LibLLVM::IS_LT_180 ? LibLLVMExt : LibLLVM }}.set_target_machine_global_isel(self, enable ? 1 : 0)
    enable
  end

  private def emit_to_file(llvm_mod, filename, type)
    status = {{ LibLLVM::IS_LT_180 ? LibLLVMExt : LibLLVM }}.target_machine_emit_to_file(self, llvm_mod, filename, type, out error_msg)
    unless status == 0
      raise LLVM.string_and_dispose(error_msg)
    end
    true
  end

  def abi
    triple = self.triple
    case triple
    when /x86_64.+windows-(?:msvc|gnu)/
      ABI::X86_Win64.new(self)
    when /x86_64|amd64/
      ABI::X86_64.new(self)
    when /i386|i486|i586|i686/
      ABI::X86.new(self)
    when /aarch64|arm64/
      ABI::AArch64.new(self)
    when /arm/
      ABI::ARM.new(self)
    when /avr/
      ABI::AVR.new(self, cpu)
    when /wasm32/
      ABI::Wasm32.new(self)
    else
      raise "Unsupported ABI for target triple: #{triple}"
    end
  end

  def to_unsafe
    @unwrap
  end

  def finalize
    LibLLVM.dispose_target_machine(@unwrap)
  end
end
