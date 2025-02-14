struct LLVM::Target
  def self.each(&)
    target = LibLLVM.get_first_target
    while target
      yield Target.new target
      target = LibLLVM.get_next_target target
    end
  end

  def self.first : self
    first? || raise "No LLVM targets available (did you forget to invoke LLVM.init_native_target?)"
  end

  def self.first? : self?
    target = LibLLVM.get_first_target
    target ? Target.new(target) : nil
  end

  def self.from_triple(triple) : self
    return_code = LibLLVM.get_target_from_triple triple, out target, out error
    raise ArgumentError.new(LLVM.string_and_dispose(error)) unless return_code == 0
    new target
  end

  def initialize(@unwrap : LibLLVM::TargetRef)
  end

  def name
    String.new LibLLVM.get_target_name(self)
  end

  def description
    String.new LibLLVM.get_target_description(self)
  end

  def create_target_machine(triple, cpu = "", features = "",
                            opt_level = LLVM::CodeGenOptLevel::Default,
                            reloc = LLVM::RelocMode::PIC,
                            code_model = LLVM::CodeModel::Default) : LLVM::TargetMachine
    target_machine = LibLLVM.create_target_machine(self, triple, cpu, features, opt_level, reloc, code_model)
    target_machine ? TargetMachine.new(target_machine) : raise "Couldn't create target machine"
  end

  def to_s(io : IO) : Nil
    io << "LLVM::Target(name="
    name.inspect(io)
    io << ", description="
    description.inspect(io)
    io << ')'
  end

  def inspect(io : IO) : Nil
    to_s(io)
  end

  def to_unsafe
    @unwrap
  end
end
