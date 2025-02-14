{% begin %}
  {% if flag?(:msvc) && !flag?(:static) %}
    {% config = nil %}
    {% for dir in Crystal::LIBRARY_PATH.split(Crystal::System::Process::HOST_PATH_DELIMITER) %}
      {% config ||= read_file?("#{dir.id}/llvm_VERSION") %}
    {% end %}

    {% lines = config ? config.lines.map(&.chomp) : nil %}
    {% llvm_version = env("LLVM_VERSION") || (lines && lines[0]) %}
    {% llvm_targets = env("LLVM_TARGETS") || (lines && lines[1]) %}
    {% llvm_ldflags = env("LLVM_LDFLAGS") || (lines && lines[2]) %}

    @[Link("llvm")]
    {% if compare_versions(Crystal::VERSION, "1.11.0-dev") >= 0 %}
      @[Link(dll: "LLVM-C.dll")]
    {% end %}
    lib LibLLVM
    end
  {% else %}
    {% llvm_config = env("LLVM_CONFIG") || `sh #{__DIR__}/ext/find-llvm-config`.stringify %}
    {% llvm_version = env("LLVM_VERSION") || `#{llvm_config.id} --version`.stringify %}
    {% llvm_targets = env("LLVM_TARGETS") || `#{llvm_config.id} --targets-built`.stringify %}
    {% llvm_ldflags = env("LLVM_LDFLAGS") || "`#{llvm_config.id} --libs --system-libs --ldflags#{" --link-static".id if flag?(:static)}#{" 2> /dev/null".id unless flag?(:win32)}`" %}

    {% unless flag?(:win32) %}
      @[Link("stdc++")]
      lib LibLLVM
      end
    {% end %}
  {% end %}

  {% llvm_version ||= Crystal::DESCRIPTION.gsub(/.*LLVM: ([^\n]*).*/m, "\\1") %}

  {% unless llvm_targets %}
    {% if flag?(:i386) || flag?(:x86_64) %}
      {% llvm_targets = "X86" %}
    {% elsif flag?(:arm) %}
      {% llvm_targets = "ARM" %}
    {% elsif flag?(:aarch64) %}
      {% llvm_targets = "AArch64" %}
    {% elsif flag?(:wasm32) %}
      {% llvm_targets = "WebAssembly" %}
    {% elsif flag?(:avr) %}
      {% llvm_targets = "AVR" %}
    {% end %}
  {% end %}

  {% if llvm_ldflags %}
    @[Link(ldflags: {{ llvm_ldflags }})]
  {% end %}
  lib LibLLVM
    VERSION = {{ llvm_version.strip.gsub(/git/, "").gsub(/-?rc.*/, "") }}
    BUILT_TARGETS = {{ llvm_targets.strip.downcase.split(' ').map(&.id.symbolize) }}
  end
{% end %}

# Supported library versions:
#
# * LLVM (8-20; aarch64 requires 13+)
#
# See https://crystal-lang.org/reference/man/required_libraries.html#other-stdlib-libraries
{% begin %}
  lib LibLLVM
    IS_LT_90 = {{compare_versions(LibLLVM::VERSION, "9.0.0") < 0}}
    IS_LT_100 = {{compare_versions(LibLLVM::VERSION, "10.0.0") < 0}}
    IS_LT_110 = {{compare_versions(LibLLVM::VERSION, "11.0.0") < 0}}
    IS_LT_120 = {{compare_versions(LibLLVM::VERSION, "12.0.0") < 0}}
    IS_LT_130 = {{compare_versions(LibLLVM::VERSION, "13.0.0") < 0}}
    IS_LT_140 = {{compare_versions(LibLLVM::VERSION, "14.0.0") < 0}}
    IS_LT_150 = {{compare_versions(LibLLVM::VERSION, "15.0.0") < 0}}
    IS_LT_160 = {{compare_versions(LibLLVM::VERSION, "16.0.0") < 0}}
    IS_LT_170 = {{compare_versions(LibLLVM::VERSION, "17.0.0") < 0}}
    IS_LT_180 = {{compare_versions(LibLLVM::VERSION, "18.0.0") < 0}}
    IS_LT_190 = {{compare_versions(LibLLVM::VERSION, "19.0.0") < 0}}
    IS_LT_200 = {{compare_versions(LibLLVM::VERSION, "20.0.0") < 0}}
  end
{% end %}

lib LibLLVM
  alias Char = LibC::Char
  alias Int = LibC::Int
  alias UInt = LibC::UInt
  alias LongLong = LibC::LongLong
  alias ULongLong = LibC::ULongLong
  alias Double = LibC::Double
  alias SizeT = LibC::SizeT
end

require "./lib_llvm/**"
