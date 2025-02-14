# Here we process the compiler's command line options and
# execute the relevant commands.
#
# Some commands are implemented in the `commands` directory,
# some in `tools`, some here, and some create a Compiler and
# manipulate it.
#
# Other commands create a `Compiler` and use it to build
# an executable.

require "json"
require "./command/*"
require "./tools/*"

class Crystal::Command
  USAGE = <<-USAGE
    Usage: crystal [command] [switches] [program file] [--] [arguments]

    Command:
        init                     generate a new project
        build                    build an executable
        clear_cache              clear the compiler cache
        docs                     generate documentation
        env                      print Crystal environment information
        eval                     eval code from args or standard input
        i/interactive            starts interactive Crystal
        play                     starts Crystal playground server
        run (default)            build and run program
        spec                     build and run specs (in spec directory)
        tool                     run a tool
        help, --help, -h         show this help
        version, --version, -v   show version

    Run a command followed by --help to see command specific information, ex:
        crystal <command> --help
    USAGE

  COMMANDS_USAGE = <<-USAGE
    Usage: crystal tool [tool] [switches] [program file] [--] [arguments]

    Tool:
        context                  show context for given location
        dependencies             show file dependency tree
        expand                   show macro expansion for given location
        flags                    print all macro `flag?` values
        format                   format project, directories and/or files
        hierarchy                show type hierarchy
        implementations          show implementations for given call in location
        types                    show type of main variables
        unreachable              show methods that are never called
        --help, -h               show this help
    USAGE

  def self.run(options = ARGV)
    new(options).run
  end

  private getter options
  @compiler : Compiler?

  def initialize(@options : Array(String))
    @color = ENV["TERM"]? != "dumb" && !ENV.has_key?("NO_COLOR")
    @error_trace = false
    @progress_tracker = ProgressTracker.new
  end

  def run
    command = options.first?
    case
    when !command
      puts USAGE
      exit
    when command == "init"
      options.shift
      init
    when "build".starts_with?(command)
      options.shift
      build
      report_warnings
      exit 1 if warnings_fail_on_exit?
    when "play".starts_with?(command)
      options.shift
      {% if flag?(:without_playground) %}
        puts "Crystal was compiled without playground support"
        puts "Try the online code evaluation and sharing tool at https://play.crystal-lang.org"
        exit 1
      {% else %}
        playground
      {% end %}
    when "deps".starts_with?(command)
      STDERR.puts "Please use 'shards': 'crystal deps' has been removed"
      exit 1
    when "docs".starts_with?(command)
      options.shift
      docs
    when command == "env"
      options.shift
      env
    when command == "eval"
      options.shift
      eval
    when command.in?("i", "interactive")
      options.shift
      {% if flag?(:without_interpreter) %}
        STDERR.puts "Crystal was compiled without interpreter support"
        exit 1
      {% else %}
        repl
      {% end %}
    when command == "run"
      options.shift
      run_command(single_file: false)
    when "spec/".starts_with?(command)
      options.shift
      spec
    when "tool".starts_with?(command)
      options.shift
      tool
    when command == "clear_cache"
      options.shift
      clear_cache
    when "help".starts_with?(command), "--help" == command, "-h" == command
      puts USAGE
      exit
    when "version".starts_with?(command), "--version" == command, "-v" == command
      puts Crystal::Config.description
      exit
    when File.file?(command)
      run_command(single_file: true)
    else
      if command.ends_with?(".cr")
        error "file '#{command}' does not exist"
      elsif external_command = Process.find_executable("crystal-#{command}")
        options.shift
        Process.exec(external_command, options, env: {"CRYSTAL" => Process.executable_path})
      else
        error "unknown command: #{command}"
      end
    end
  rescue ex : Crystal::CodeError
    report_warnings

    ex.color = @color
    ex.error_trace = @error_trace
    if @config.try(&.output_format) == "json"
      STDERR.puts ex.to_json
    else
      STDERR.puts ex
    end
    exit 1
  rescue ex : Crystal::Error
    report_warnings

    # This unwraps nested errors which could be caused by `require` which wraps
    # errors in order to trace the require path. The causes are listed similarly
    # to `#inspect_with_backtrace` but without the backtrace.
    while cause = ex.cause
      error ex.message, exit_code: nil
      ex = cause
    end

    error ex.message
  rescue ex : OptionParser::Exception
    error ex.message
  rescue ex
    report_warnings

    ex.inspect_with_backtrace STDERR
    error "you've found a bug in the Crystal compiler. Please open an issue, including source code that will allow us to reproduce the bug: https://github.com/crystal-lang/crystal/issues"
  end

  private def tool
    tool = options.first?
    case
    when !tool
      puts COMMANDS_USAGE
      exit
    when "context".starts_with?(tool)
      options.shift
      context
    when "format".starts_with?(tool)
      options.shift
      format
    when "flags" == tool
      options.shift
      flags
    when "expand".starts_with?(tool)
      options.shift
      expand
    when "hierarchy".starts_with?(tool)
      options.shift
      hierarchy
    when "dependencies".starts_with?(tool)
      options.shift
      dependencies
    when "implementations".starts_with?(tool)
      options.shift
      implementations
    when "types".starts_with?(tool)
      options.shift
      types
    when "unreachable".starts_with?(tool)
      options.shift
      unreachable
    when "--help" == tool, "-h" == tool
      puts COMMANDS_USAGE
      exit
    else
      error "unknown tool: #{tool}"
    end
  end

  private def init
    Init.run(options)
  end

  private def build
    config = create_compiler "build"
    config.compile
  end

  private def hierarchy
    config, result = compile_no_codegen "tool hierarchy", hierarchy: true, top_level: true
    @progress_tracker.stage("Tool (hierarchy)") do
      Crystal.print_hierarchy result.program, STDOUT, config.hierarchy_exp, config.output_format
    end
  end

  private def run_command(single_file = false)
    config = create_compiler "run", run: true, single_file: single_file
    if config.specified_output
      config.compile
      report_warnings
      exit 1 if warnings_fail_on_exit?
      return
    end

    output_filename = Crystal.temp_executable(config.output_filename)

    config.compile output_filename

    unless config.compiler.no_codegen?
      report_warnings
      exit 1 if warnings_fail_on_exit?

      execute output_filename, config.arguments, config.compiler
    end
  end

  private def types
    config, result = compile_no_codegen "tool types"
    @progress_tracker.stage("Tool (types)") do
      Crystal.print_types result.node
    end
  end

  private def compile_no_codegen(command, wants_doc = false, hierarchy = false, no_cleanup = false, cursor_command = false, top_level = false, path_filter = false, unreachable_command = false, allowed_formats = ["text", "json"])
    config = create_compiler command, no_codegen: true, hierarchy: hierarchy, cursor_command: cursor_command, path_filter: path_filter, unreachable_command: unreachable_command, allowed_formats: allowed_formats
    config.compiler.no_codegen = true
    config.compiler.no_cleanup = no_cleanup
    config.compiler.wants_doc = wants_doc
    result = top_level ? config.top_level_semantic : config.compile
    {config, result}
  end

  private def execute(output_filename, run_args, compiler, *, error_on_exit = false)
    time = @time && !@progress_tracker.stats?
    status, elapsed_time = @progress_tracker.stage("Execute") do
      begin
        elapsed = Time.measure do
          Process.run(output_filename, args: run_args, input: Process::Redirect::Inherit, output: Process::Redirect::Inherit, error: Process::Redirect::Inherit) do |process|
            {% unless flag?(:wasm32) %}
              # Ignore the signal so we don't exit the running process
              # (the running process can still handle this signal)
              Process.ignore_interrupts!
            {% end %}
          end
        end
        {$?, elapsed}
      ensure
        File.delete?(output_filename)

        # Delete related PDB generated by MSVC, if any exist
        {% if flag?(:msvc) %}
          unless compiler.debug.none?
            basename = output_filename.rchop(".exe")
            File.delete?("#{basename}.pdb")
          end
        {% end %}

        # Delete related dwarf generated by dsymutil, if any exist
        {% if flag?(:darwin) %}
          unless compiler.debug.none?
            File.delete?("#{output_filename}.dwarf")
          end
        {% end %}
      end
    end

    if time
      puts "Execute: #{elapsed_time}"
    end

    if (exit_code = status.exit_code?) && !error_on_exit
      exit exit_code
    end

    unless status.exit_reason.normal?
      STDERR.puts status.description
      STDERR.flush
    end

    exit 1
  end

  record CompilerConfig,
    compiler : Compiler,
    sources : Array(Compiler::Source),
    output_filename : String,
    emit_base_filename : String?,
    arguments : Array(String),
    specified_output : Bool,
    hierarchy_exp : String?,
    cursor_location : String?,
    output_format : String,
    includes : Array(String),
    excludes : Array(String),
    verbose : Bool,
    check : Bool,
    tallies : Bool do
    def compile(output_filename = self.output_filename)
      compiler.emit_base_filename = emit_base_filename || output_filename.rchop(File.extname(output_filename))
      compiler.compile sources, output_filename
    end

    def top_level_semantic
      compiler.top_level_semantic sources
    end
  end

  private def create_compiler(command, no_codegen = false, run = false,
                              hierarchy = false, cursor_command = false,
                              single_file = false, dependencies = false,
                              path_filter = false, unreachable_command = false,
                              allowed_formats = ["text", "json"])
    compiler = new_compiler
    compiler.progress_tracker = @progress_tracker
    compiler.no_codegen = no_codegen
    link_flags = [] of String
    filenames = [] of String
    has_stdin_filename = false
    opt_filenames = nil
    opt_arguments = nil
    opt_output_filename = nil
    specified_output = false
    hierarchy_exp = nil
    cursor_location = nil
    output_format = nil
    excludes = [] of String
    includes = [] of String
    verbose = false
    check = false
    tallies = false

    option_parser = parse_with_crystal_opts do |opts|
      opts.banner = "Usage: crystal #{command} [options] [programfile] [--] [arguments]\n\nOptions:"

      unless no_codegen
        unless run
          opts.on("--cross-compile", "cross-compile") do |cross_compile|
            compiler.cross_compile = true
          end
        end
        opts.on("-d", "--debug", "Add full symbolic debug info") do
          compiler.debug = Crystal::Debug::All
        end
        opts.on("--no-debug", "Skip any symbolic debug info") do
          compiler.debug = Crystal::Debug::None
        end

        opts.on("--frame-pointers auto|always|non-leaf", "Control the preservation of frame pointers") do |value|
          if frame_pointers = FramePointers.parse?(value)
            compiler.frame_pointers = frame_pointers
          else
            error "Invalid value `#{value}` for frame-pointers"
          end
        end
      end

      opts.on("-D FLAG", "--define FLAG", "Define a compile-time flag") do |flag|
        compiler.flags << flag
      end

      unless no_codegen
        valid_emit_values = Compiler::EmitTarget.names
        valid_emit_values.map!(&.gsub('_', '-').downcase)

        opts.on("--emit [#{valid_emit_values.join('|')}]", "Comma separated list of types of output for the compiler to emit") do |emit_values|
          compiler.emit_targets |= validate_emit_values(emit_values.split(',').map(&.strip))
        end
      end

      if hierarchy
        opts.on("-e NAME", "Filter types by NAME regex") do |exp|
          hierarchy_exp = exp
        end
      end

      if cursor_command
        opts.on("-c LOC", "--cursor LOC", "Cursor location with LOC as path/to/file.cr:line:column") do |cursor|
          cursor_location = cursor
        end
      end

      if dependencies
        opts.on("-i <path>", "--include <path>", "Include path") do |f|
          includes << f
        end

        opts.on("-e <path>", "--exclude <path>", "Exclude path (default: lib)") do |f|
          excludes << f
        end

        opts.on("--verbose", "Show skipped and filtered paths") do
          verbose = true
        end
      end

      opts.on("-f #{allowed_formats.join("|")}", "--format #{allowed_formats.join("|")}", "Output format: #{allowed_formats[0]} (default), #{allowed_formats[1..].join(", ")}") do |f|
        output_format = f
      end

      if unreachable_command
        opts.on("--tallies", "Print reachable methods and their call counts as well") do
          tallies = true
        end

        opts.on("--check", "Exits with error if there is any unreachable code") do |f|
          check = true
        end
      end

      opts.on("--error-trace", "Show full error trace") do
        compiler.show_error_trace = true
        @error_trace = true
      end

      opts.on("-h", "--help", "Show this message") do
        puts opts
        exit
      end

      if path_filter
        opts.on("-i <path>", "--include <path>", "Include path") do |f|
          includes << f
        end

        opts.on("-e <path>", "--exclude <path>", "Exclude path (default: lib)") do |f|
          excludes << f
        end
      end

      unless no_codegen
        opts.on("--ll", "Dump ll to Crystal's cache directory") do
          compiler.dump_ll = true
        end
        opts.on("--link-flags FLAGS", "Additional flags to pass to the linker") do |some_link_flags|
          link_flags << some_link_flags
        end
        target_specific_opts(opts, compiler)
        setup_compiler_warning_options(opts, compiler)
      end

      opts.on("--no-color", "Disable colored output") do
        @color = false
        compiler.color = false
      end

      unless no_codegen
        opts.on("--no-codegen", "Don't do code generation") do
          compiler.no_codegen = true
        end
        opts.on("-o ", "Output filename") do |an_output_filename|
          opt_output_filename = an_output_filename
          specified_output = true
        end
      end

      opts.on("--prelude ", "Use given file as prelude") do |prelude|
        compiler.prelude = prelude
      end

      unless no_codegen
        opts.on("--release", "Compile in release mode (-O3 --single-module)") do
          compiler.release!
        end
        opts.on("-O LEVEL", "Optimization mode: 0 (default), 1, 2, 3, s, z") do |level|
          if mode = Compiler::OptimizationMode.from_level?(level)
            compiler.optimization_mode = mode
          else
            raise Error.new("Invalid optimization mode: O#{level}")
          end
        end
      end

      opts.on("-s", "--stats", "Enable statistics output") do
        @progress_tracker.stats = true
      end

      opts.on("-p", "--progress", "Enable progress output") do
        @progress_tracker.progress = true
      end

      opts.on("-t", "--time", "Enable execution time output") do
        @time = true
      end

      unless no_codegen
        opts.on("--single-module", "Generate a single LLVM module") do
          compiler.single_module = true
        end
        opts.on("--threads NUM", "Maximum number of threads to use") do |n_threads|
          compiler.n_threads = n_threads.to_i? || raise Error.new("Invalid thread count: #{n_threads}")
        end
        unless run
          opts.on("--target TRIPLE", "Target triple") do |triple|
            compiler.codegen_target = Codegen::Target.new(triple)
          end
        end
        opts.on("--verbose", "Display executed commands") do
          compiler.verbose = true
        end
        opts.on("--static", "Link statically") do
          compiler.static = true
        end
      end

      opts.on("--stdin-filename ", "Source file name to be read from STDIN") do |stdin_filename|
        has_stdin_filename = true
        filenames << stdin_filename
      end

      if single_file
        opts.before_each do |arg|
          opts.stop if !arg.starts_with?('-') && arg.ends_with?(".cr")
          opts.stop if File.file?(arg)
        end
      end

      opts.unknown_args do |before, after|
        opt_filenames = before
        opt_arguments = after
      end
    end

    compiler.link_flags = link_flags.join(' ') unless link_flags.empty?

    output_filename = opt_output_filename
    filenames += opt_filenames.not_nil!
    arguments = opt_arguments.not_nil!

    if single_file && (files = filenames[1..-1]?)
      arguments = files + arguments
      filenames = [filenames[0]]
    end

    if filenames.size == 0 || (cursor_command && cursor_location.nil?)
      STDERR.puts option_parser
      exit 1
    end

    sources = [] of Compiler::Source
    if has_stdin_filename
      sources << Compiler::Source.new(filenames.shift, STDIN.gets_to_end)
    end
    sources.concat gather_sources(filenames)

    output_extension = compiler.cross_compile? ? compiler.codegen_target.object_extension : compiler.codegen_target.executable_extension
    if output_filename
      if File.extname(output_filename).empty?
        output_filename += output_extension
      end
    else
      first_filename = sources.first.filename
      output_filename = "#{::Path[first_filename].stem}#{output_extension}"

      # Check if we'll overwrite the main source file
      if !compiler.no_codegen? && !run && first_filename == File.expand_path(output_filename)
        error "compilation will overwrite source file '#{Crystal.relative_filename(first_filename)}', either change its extension to '.cr' or specify an output file with '-o'"
      end
    end

    output_format ||= allowed_formats[0]
    unless output_format.in?(allowed_formats)
      error "You have input an invalid format: #{output_format}. Supported formats: #{allowed_formats.join(", ")}"
    end

    error "maximum number of threads cannot be lower than 1" if compiler.n_threads < 1

    if !compiler.no_codegen? && !run && Dir.exists?(output_filename)
      error "can't use `#{output_filename}` as output filename because it's a directory"
    end

    if run
      emit_base_filename = ::Path[sources.first.filename].stem
    end

    @config = CompilerConfig.new compiler, sources, output_filename, emit_base_filename,
      arguments, specified_output, hierarchy_exp, cursor_location, output_format.not_nil!,
      includes, excludes, verbose, check, tallies
  end

  private def gather_sources(filenames)
    filenames.map do |filename|
      filename = File.expand_path(filename)
      Compiler::Source.new(filename, File.read(filename))
    end
  rescue exc : IO::Error
    error exc
  end

  private def setup_simple_compiler_options(compiler, opts)
    opts.on("-d", "--debug", "Add full symbolic debug info") do
      compiler.debug = Crystal::Debug::All
    end
    opts.on("--no-debug", "Skip any symbolic debug info") do
      compiler.debug = Crystal::Debug::None
    end
    opts.on("-D FLAG", "--define FLAG", "Define a compile-time flag") do |flag|
      compiler.flags << flag
    end
    opts.on("--error-trace", "Show full error trace") do
      @error_trace = true
      compiler.show_error_trace = true
    end
    opts.on("--release", "Compile in release mode (-O3 --single-module)") do
      compiler.release!
    end
    opts.on("-O LEVEL", "Optimization mode: 0 (default), 1, 2, 3, s, z") do |level|
      if mode = Compiler::OptimizationMode.from_level?(level)
        compiler.optimization_mode = mode
      else
        raise Error.new("Invalid optimization mode: O#{level}")
      end
    end
    opts.on("--single-module", "Generate a single LLVM module") do
      compiler.single_module = true
    end
    opts.on("--threads NUM", "Maximum number of threads to use") do |n_threads|
      compiler.n_threads = n_threads.to_i? || raise Error.new("Invalid thread count: #{n_threads}")
    end
    opts.on("-s", "--stats", "Enable statistics output") do
      compiler.progress_tracker.stats = true
    end
    opts.on("-p", "--progress", "Enable progress output") do
      compiler.progress_tracker.progress = true
    end
    opts.on("-t", "--time", "Enable execution time output") do
      @time = true
    end
    opts.on("-h", "--help", "Show this message") do
      puts opts
      exit
    end
    opts.on("--no-color", "Disable colored output") do
      @color = false
      compiler.color = false
    end
    target_specific_opts(opts, compiler)
    setup_compiler_warning_options(opts, compiler)
    opts.invalid_option { }
  end

  private def target_specific_opts(opts, compiler)
    opts.on("--mcpu CPU", "Target specific cpu type") do |cpu|
      if cpu == "native"
        compiler.mcpu = LLVM.host_cpu_name
      else
        compiler.mcpu = cpu
      end
    end
    opts.on("--mattr CPU", "Target specific features") do |features|
      compiler.mattr = features
    end
    opts.on("--mcmodel MODEL", "Target specific code model") do |mcmodel|
      compiler.mcmodel = case mcmodel
                         when "default" then LLVM::CodeModel::Default
                         when "small"   then LLVM::CodeModel::Small
                         when "kernel"  then LLVM::CodeModel::Kernel
                         when "medium"  then LLVM::CodeModel::Medium
                         when "large"   then LLVM::CodeModel::Large
                         else
                           error "--mcmodel should be one of: default, kernel, small, medium, large"
                           raise "unreachable"
                         end
    end
  end

  private def setup_compiler_warning_options(opts, compiler)
    opts.on("--warnings all|none", "Which warnings to detect. (default: all)") do |w|
      compiler.warnings.level = case w
                                when "all"
                                  Crystal::WarningLevel::All
                                when "none"
                                  Crystal::WarningLevel::None
                                else
                                  error "--warnings should be all, or none"
                                  raise "unreachable"
                                end
    end
    opts.on("--error-on-warnings", "Treat warnings as errors.") do |w|
      compiler.warnings.error_on_warnings = true
    end
    opts.on("--exclude-warnings <path>", "Exclude warnings from path (default: lib)") do |f|
      compiler.warnings.exclude_lib_path = false
      compiler.warnings.exclude_path(f)
    end

    compiler.warnings.exclude_lib_path = true
  end

  private def validate_emit_values(values)
    emit_targets = Compiler::EmitTarget::None
    values.each do |value|
      if target = Compiler::EmitTarget.parse?(value.gsub('-', '_'))
        emit_targets |= target
      else
        error "invalid emit value '#{value}'"
      end
    end
    emit_targets
  end

  private def error(msg, exit_code = 1)
    # This is for the case where the main command is wrong
    @color = false if ARGV.includes?("--no-color") || ENV["TERM"]? == "dumb" || ENV.has_key?("NO_COLOR")
    Crystal.error msg, @color, exit_code: exit_code
  end

  private def self.crystal_opts
    ENV["CRYSTAL_OPTS"]?.try { |opts| Process.parse_arguments(opts) }
  rescue ex
    raise Error.new("Failed to parse CRYSTAL_OPTS: #{ex.message}")
  end

  # Constructs an `OptionParser` from the given block and runs it twice, first
  # time with `CRYSTAL_OPTS`, second time with the given *options*.
  #
  # Only flags are accepted in the first run; positional arguments, invalid
  # options (where they might be treated as normal arguments), and `--` are all
  # disallowed. The option parser should not define any subcommands.
  def self.parse_with_crystal_opts(options, & : OptionParser ->)
    option_parser = OptionParser.new { |opts| yield opts }

    if crystal_opts = self.crystal_opts
      old_unknown_args = option_parser.@unknown_args
      old_invalid_option = option_parser.@invalid_option
      old_before_each = option_parser.@before_each

      option_parser.unknown_args { }
      option_parser.invalid_option { |opt| raise OptionParser::InvalidOption.new(opt) }
      option_parser.before_each do |opt|
        raise Error.new "CRYSTAL_OPTS may not contain --" if opt == "--"
      end

      option_parser.parse(crystal_opts)
      unless crystal_opts.empty?
        raise Error.new "CRYSTAL_OPTS may not contain positional arguments"
      end

      option_parser.unknown_args(&old_unknown_args) if old_unknown_args
      option_parser.invalid_option(&old_invalid_option)
      if old_before_each
        option_parser.before_each(&old_before_each)
      else
        option_parser.before_each { }
      end
    end

    option_parser.parse(options)
    option_parser
  end

  private def parse_with_crystal_opts(& : OptionParser ->)
    Command.parse_with_crystal_opts(@options) { |opts| yield opts }
  end

  private def new_compiler
    @compiler = Compiler.new
  end
end
