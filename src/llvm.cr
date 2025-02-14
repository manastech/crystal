require "./llvm/**"
require "c/string"

module LLVM
  @@initialized = false

  # Returns the runtime version of LLVM.
  #
  # Starting with LLVM 16, this method returns the version as reported by
  # `LLVMGetVersion` at runtime. Older versions of LLVM do not expose this
  # information, so the value falls back to `LibLLVM::VERSION` which is
  # determined at compile time and might slightly be out of sync to the
  # dynamic library loaded at runtime.
  def self.version
    {% if LibLLVM.has_method?(:get_version) %}
      LibLLVM.get_version(out major, out minor, out patch)
      "#{major}.#{minor}.#{patch}"
    {% else %}
      LibLLVM::VERSION
    {% end %}
  end

  def self.init_x86 : Nil
    return if @@initialized_x86
    @@initialized_x86 = true

    {% if LibLLVM::BUILT_TARGETS.includes?(:x86) %}
      LibLLVM.initialize_x86_target_info
      LibLLVM.initialize_x86_target
      LibLLVM.initialize_x86_target_mc
      LibLLVM.initialize_x86_asm_printer
      LibLLVM.initialize_x86_asm_parser
      LibLLVM.link_in_mc_jit
    {% else %}
      raise "ERROR: LLVM was built without X86 target"
    {% end %}
  end

  def self.init_aarch64 : Nil
    return if @@initialized_aarch64
    @@initialized_aarch64 = true

    {% if LibLLVM::BUILT_TARGETS.includes?(:aarch64) %}
      LibLLVM.initialize_aarch64_target_info
      LibLLVM.initialize_aarch64_target
      LibLLVM.initialize_aarch64_target_mc
      LibLLVM.initialize_aarch64_asm_printer
      LibLLVM.initialize_aarch64_asm_parser
      LibLLVM.link_in_mc_jit
    {% else %}
      raise "ERROR: LLVM was built without AArch64 target"
    {% end %}
  end

  def self.init_arm : Nil
    return if @@initialized_arm
    @@initialized_arm = true

    {% if LibLLVM::BUILT_TARGETS.includes?(:arm) %}
      LibLLVM.initialize_arm_target_info
      LibLLVM.initialize_arm_target
      LibLLVM.initialize_arm_target_mc
      LibLLVM.initialize_arm_asm_printer
      LibLLVM.initialize_arm_asm_parser
      LibLLVM.link_in_mc_jit
    {% else %}
      raise "ERROR: LLVM was built without ARM target"
    {% end %}
  end

  def self.init_avr : Nil
    return if @@initialized_avr
    @@initialized_avr = true

    {% if LibLLVM::BUILT_TARGETS.includes?(:avr) %}
      LibLLVM.initialize_avr_target_info
      LibLLVM.initialize_avr_target
      LibLLVM.initialize_avr_target_mc
      LibLLVM.initialize_avr_asm_printer
      LibLLVM.initialize_avr_asm_parser
      LibLLVM.link_in_mc_jit
    {% else %}
      raise "ERROR: LLVM was built without AVR target"
    {% end %}
  end

  def self.init_webassembly : Nil
    return if @@initialized_webassembly
    @@initialized_webassembly = true

    {% if LibLLVM::BUILT_TARGETS.includes?(:webassembly) %}
      LibLLVM.initialize_webassembly_target_info
      LibLLVM.initialize_webassembly_target
      LibLLVM.initialize_webassembly_target_mc
      LibLLVM.initialize_webassembly_asm_printer
      LibLLVM.initialize_webassembly_asm_parser
      LibLLVM.link_in_mc_jit
    {% else %}
      raise "ERROR: LLVM was built without WebAssembly target"
    {% end %}
  end

  def self.init_native_target : Nil
    {% if flag?(:i386) || flag?(:x86_64) %}
      init_x86
    {% elsif flag?(:aarch64) %}
      init_aarch64
    {% elsif flag?(:arm) %}
      init_arm
    {% elsif flag?(:wasm32) %}
      init_webassembly
    {% elsif flag?(:avr) %}
      init_avr
    {% else %}
      {% raise "Unsupported platform" %}
    {% end %}
  end

  def self.init_all_targets : Nil
    {% for target in %i(x86 aarch64 arm avr webassembly) %}
      {% if LibLLVM::BUILT_TARGETS.includes?(target) %}
        init_{{ target.id }}
      {% end %}
    {% end %}
  end

  @[Deprecated("This method has no effect")]
  def self.start_multithreaded : Bool
    if multithreaded?
      true
    else
      LibLLVM.start_multithreaded != 0
    end
  end

  @[Deprecated("This method has no effect")]
  def self.stop_multithreaded
    if multithreaded?
      LibLLVM.stop_multithreaded
    end
  end

  def self.multithreaded? : Bool
    LibLLVM.is_multithreaded != 0
  end

  def self.default_target_triple : String
    chars = LibLLVM.get_default_target_triple
    case triple = string_and_dispose(chars)
    when .starts_with?("aarch64-unknown-linux-android")
      # remove API version
      "aarch64-unknown-linux-android"
    when .starts_with?("x86_64-pc-solaris")
      # remove API version
      "x86_64-pc-solaris"
    else
      triple
    end
  end

  def self.host_cpu_name : String
    String.new LibLLVM.get_host_cpu_name
  end

  def self.normalize_triple(triple : String) : String
    normalized = LibLLVM.normalize_target_triple(triple)
    normalized = LLVM.string_and_dispose(normalized)

    normalized
  end

  def self.to_io(chars, io) : Nil
    io.write_string Slice.new(chars, LibC.strlen(chars))
    LibLLVM.dispose_message(chars)
  end

  def self.string_and_dispose(chars) : String
    string = String.new(chars)
    LibLLVM.dispose_message(chars)
    string
  end

  protected def self.assert(error : LibLLVM::ErrorRef)
    if error
      chars = LibLLVM.get_error_message(error)
      raise String.new(chars).tap { LibLLVM.dispose_error_message(chars) }
    end
  end

  {% unless LibLLVM::IS_LT_130 %}
    def self.run_passes(module mod : Module, passes : String, target_machine : TargetMachine, options : PassBuilderOptions)
      LibLLVM.run_passes(mod, passes, target_machine, options)
    end
  {% end %}

  DEBUG_METADATA_VERSION = 3
end
