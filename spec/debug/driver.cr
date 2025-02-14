abstract class DebuggerRunner
  CRYSTAL    = ENV["CRYSTAL_SPEC_COMPILER_BIN"]? || "#{REPO_BASE_DIR}/bin/crystal"
  FILE_CHECK = "FileCheck#{File.basename(`#{__DIR__}/../../src/llvm/ext/find-llvm-config.sh`).lchop("llvm-config")}"

  REPO_BASE_DIR      = "#{__DIR__}/../../"
  SESSION_OUTPUT_DIR = File.join(REPO_BASE_DIR, "tmp", "debug")
  DEBUG_BIN          = File.join(REPO_BASE_DIR, ".build", "debug_test_case")

  def initialize(@input : String)
    Dir.mkdir_p(SESSION_OUTPUT_DIR)
    @basename = File.join(SESSION_OUTPUT_DIR, File.basename(@input, File.extname(@input)))
  end

  abstract def name

  def setup
    check_regex = /# (?:#{Regex.escape(name)}-)?check: (.*)/

    File.open("#{@basename}.#{name}-script", "w") do |script|
      script_header(script)

      File.open("#{@basename}.#{name}-assert", "w") do |assert|
        File.each_line(@input) do |line|
          if md = line.match(/# print: (.*)/)
            command = print_command(md[1])
            script.puts command
            assert << "CHECK: "
            debugger_prompt(assert, command)
          elsif md = line.match(check_regex)
            assert.puts "CHECK-NEXT: #{md[1]}"
          elsif line.matches?(/\bdebugger\b/)
            script_continue(script)
          end
        end
      end
    end
  end

  abstract def script_header(script : IO)
  abstract def script_continue(script : IO)
  abstract def print_command(expr)
  abstract def debugger_prompt(assert : IO, command)

  def run_compiler
    Dir.mkdir_p(File.dirname(DEBUG_BIN))
    Process.run(CRYSTAL, ["build", "--debug", @input, "-o", DEBUG_BIN], error: Process::Redirect::Inherit)
  end

  abstract def run_debugger

  def run_file_check
    File.open("#{@basename}.#{name}-session", "r") do |session|
      Process.run(FILE_CHECK, ["#{@basename}.#{name}-assert"], input: session, error: Process::Redirect::Inherit)
    end
  end
end

class LLDBRunner < DebuggerRunner
  CRYSTAL_FORMATTERS = File.expand_path(File.join(REPO_BASE_DIR, "etc", "lldb", "crystal_formatters.py"))

  def name
    "lldb"
  end

  def script_header(script : IO)
    script.puts "version"
    script.puts "command script import #{CRYSTAL_FORMATTERS}"

    # skip signals intentionally raised during GC initialization: https://hboehm.info/gc/debugging.html
    script.puts "breakpoint set -n main -G true -o true -C 'process handle -s false -n false SIGSEGV SIGBUS'"
    script.puts "breakpoint set -n __crystal_main -G true -o true -C 'process handle -s true -n true SIGSEGV SIGBUS'"

    script.puts "run"
  end

  def script_continue(script : IO)
    script.puts "continue"
  end

  def print_command(expr)
    "print #{expr}"
  end

  def debugger_prompt(assert : IO, command)
    assert.puts "(lldb) #{command}"
  end

  def run_debugger
    File.open("#{@basename}.#{name}-session", "w") do |session|
      Process.run("lldb", ["-b", "--source", "#{@basename}.#{name}-script", DEBUG_BIN], output: session)
    end
  end
end

class GDBRunner < DebuggerRunner
  CRYSTAL_FORMATTERS = File.expand_path(File.join(REPO_BASE_DIR, "etc", "gdb", "crystal_formatters.py"))

  def name
    "gdb"
  end

  def script_header(script : IO)
    script.puts "source #{CRYSTAL_FORMATTERS}"

    # skip signals intentionally raised during GC initialization: https://hboehm.info/gc/debugging.html
    script.puts <<-GDB
    tbreak main
    commands
    silent
    handle SIGSEGV nostop noprint
    handle SIGBUS nostop noprint
    continue
    end
    tbreak __crystal_main
    commands
    silent
    handle SIGSEGV stop print
    handle SIGBUS stop print
    continue
    end
    GDB

    script.puts "set trace-commands on"
    script.puts "run"
  end

  def script_continue(script : IO)
    script.puts "continue"
  end

  def print_command(expr)
    "print #{expr}"
  end

  def debugger_prompt(assert : IO, command)
    assert.puts "+#{command}"
  end

  def run_debugger
    File.open("#{@basename}.#{name}-session", "w") do |session|
      Process.run("gdb", ["--batch", "-x", "#{@basename}.#{name}-script", DEBUG_BIN], output: session)
    end
  end
end

input = ARGV.shift
debugger_name = ARGV.shift? || "lldb"

runner = case debugger_name
         when "lldb"
           LLDBRunner.new(input)
         when "gdb"
           GDBRunner.new(input)
         else
           raise "unknown debugger: #{debugger_name}"
         end
runner.setup

status = runner.run_compiler
exit 1 unless status.success?

runner.run_debugger
status = runner.run_file_check
exit status.exit_code
