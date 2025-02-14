require "option_parser"
require "file_utils"
require "colorize"
require "crystal/digest/md5"
{% if flag?(:msvc) %}
  require "./loader"
{% end %}
{% if flag?(:preview_mt) %}
  require "wait_group"
{% end %}

module Crystal
  @[Flags]
  enum Debug
    LineNumbers
    Variables
    Default     = LineNumbers
  end

  enum FramePointers
    Auto
    Always
    NonLeaf
  end

  # Main interface to the compiler.
  #
  # A Compiler parses source code, type checks it and
  # optionally generates an executable.
  class Compiler
    DEFAULT_LINKER = ENV["CC"]? || {{ env("CRYSTAL_CONFIG_CC") || "cc" }}
    MSVC_LINKER    = ENV["CC"]? || {{ env("CRYSTAL_CONFIG_CC") || "cl.exe" }}

    # A source to the compiler: its filename and source code.
    record Source,
      filename : String,
      code : String

    # The result of a compilation: the program containing all
    # the type and method definitions, and the parsed program
    # as an ASTNode.
    record Result,
      program : Program,
      node : ASTNode

    # If `true`, doesn't generate an executable but instead
    # creates a `.o` file and outputs a command line to link
    # it in the target machine.
    property? cross_compile = false

    # Compiler flags. These will be true when checked in macro
    # code by the `flag?(...)` macro method.
    property flags = [] of String

    # Controls generation of frame pointers.
    property frame_pointers = FramePointers::Auto

    # If `true`, the executable will be generated with debug code
    # that can be understood by `gdb` and `lldb`.
    property debug = Debug::Default

    # If `true`, `.ll` files will be generated in the default cache
    # directory for each generated LLVM module.
    property? dump_ll = false

    # Additional link flags to pass to the linker.
    property link_flags : String?

    # Sets the mcpu. Check LLVM docs to learn about this.
    property mcpu : String?

    # Sets the mattr (features). Check LLVM docs to learn about this.
    property mattr : String?

    # If `false`, color won't be used in output messages.
    property? color = true

    # If `true`, skip cleanup process on semantic analysis.
    property? no_cleanup = false

    # If `true`, no executable will be generated after compilation
    # (useful to type-check a program)
    property? no_codegen = false

    # Maximum number of LLVM modules that are compiled in parallel
    property n_threads : Int32 = {% if flag?(:preview_mt) %}
      ENV["CRYSTAL_WORKERS"]?.try(&.to_i?) || 4
    {% elsif flag?(:win32) %}
      1
    {% else %}
      8
    {% end %}

    # Default prelude file to use. This ends up adding a
    # `require "prelude"` (or whatever name is set here) to
    # the source file to compile.
    property prelude = "prelude"

    # Optimization mode
    enum OptimizationMode
      # [default] no optimization, fastest compilation, slowest runtime
      O0 = 0

      # low, compilation slower than O0, runtime faster than O0
      O1 = 1

      # middle, compilation slower than O1, runtime faster than O1
      O2 = 2

      # high, slowest compilation, fastest runtime
      # enables with --release flag
      O3 = 3

      # optimize for size, enables most O2 optimizations but aims for smaller
      # code size
      Os

      # optimize aggressively for size rather than speed
      Oz

      def suffix
        ".#{to_s.downcase}"
      end

      def self.from_level?(level : String) : self?
        case level
        when "0" then O0
        when "1" then O1
        when "2" then O2
        when "3" then O3
        when "s" then Os
        when "z" then Oz
        end
      end
    end

    # Sets the Optimization mode.
    property optimization_mode = OptimizationMode::O0

    # Sets the code model. Check LLVM docs to learn about this.
    property mcmodel = LLVM::CodeModel::Default

    # If `true`, generates a single LLVM module. By default
    # one LLVM module is created for each type in a program.
    # --release automatically enable this option
    property? single_module = false

    # A `ProgressTracker` object which tracks compilation progress.
    property progress_tracker = ProgressTracker.new

    # Codegen target to use in the compilation.
    # If not set, asks LLVM the default one for the current machine.
    property codegen_target = Config.host_target

    # If `true`, prints the link command line that is performed
    # to create the executable.
    property? verbose = false

    # If `true`, doc comments are attached to types and methods
    # and can later be used to generate API docs.
    property? wants_doc = false

    # Warning settings and all detected warnings.
    property warnings = WarningCollection.new

    @[Flags]
    enum EmitTarget
      ASM
      OBJ
      LLVM_BC
      LLVM_IR
    end

    # Can be set to a set of flags to emit other files other
    # than the executable file:
    # * asm: assembly files
    # * llvm-bc: LLVM bitcode
    # * llvm-ir: LLVM IR
    # * obj: object file
    property emit_targets : EmitTarget = EmitTarget::None

    # Base filename to use for `emit` output.
    property emit_base_filename : String?

    # By default the compiler cleans up the default cache directory
    # to keep the most recent 10 directories used. If this is set
    # to `false` that cleanup is not performed.
    property? cleanup = true

    # Default standard output to use in a compilation.
    property stdout : IO = STDOUT

    # Default standard error to use in a compilation.
    property stderr : IO = STDERR

    # Whether to show error trace
    property? show_error_trace = false

    # Whether to link statically
    property? static = false

    property dependency_printer : DependencyPrinter? = nil

    # Program that was created for the last compilation.
    property! program : Program

    # Compiles the given *source*, with *output_filename* as the name
    # of the generated executable.
    #
    # Raises `Crystal::CodeError` if there's an error in the
    # source code.
    #
    # Raises `InvalidByteSequenceError` if the source code is not
    # valid UTF-8.
    def compile(source : Source | Array(Source), output_filename : String) : Result
      source = [source] unless source.is_a?(Array)
      program = new_program(source)
      node = parse program, source
      node = program.semantic node, cleanup: !no_cleanup?
      units = codegen program, node, source, output_filename unless @no_codegen

      @progress_tracker.clear
      print_macro_run_stats(program)
      print_codegen_stats(units)

      Result.new program, node
    end

    # Runs the semantic pass on the given source, without generating an
    # executable nor analyzing methods. The returned `Program` in the result will
    # contain all types and methods. This can be useful to generate
    # API docs, analyze type relationships, etc.
    #
    # Raises `Crystal::CodeError` if there's an error in the
    # source code.
    #
    # Raises `InvalidByteSequenceError` if the source code is not
    # valid UTF-8.
    def top_level_semantic(source : Source | Array(Source)) : Result
      source = [source] unless source.is_a?(Array)
      program = new_program(source)
      node = parse program, source
      node, processor = program.top_level_semantic(node)

      @progress_tracker.clear
      print_macro_run_stats(program)

      Result.new program, node
    end

    # Set maximum level of optimization.
    def release!
      @optimization_mode = OptimizationMode::O3
      @single_module = true
    end

    def release?
      @optimization_mode.o3? && @single_module
    end

    private def new_program(sources)
      @program = program = Program.new
      program.compiler = self
      program.filename = sources.first.filename
      program.codegen_target = codegen_target
      program.target_machine = create_target_machine
      program.flags << "release" if release?
      program.flags << "debug" unless debug.none?
      program.flags << "static" if static?
      program.flags.concat @flags
      program.wants_doc = wants_doc?
      program.color = color?
      program.stdout = stdout
      program.show_error_trace = show_error_trace?
      program.progress_tracker = @progress_tracker
      program.warnings = @warnings
      program
    end

    private def parse(program, sources : Array)
      @progress_tracker.stage("Parse") do
        nodes = sources.map do |source|
          # We add the source to the list of required file,
          # so it can't be required again
          program.requires.add source.filename
          parse(program, source).as(ASTNode)
        end
        nodes = Expressions.from(nodes)

        # Prepend the prelude to the parsed program
        location = Location.new(program.filename, 1, 1)
        nodes = Expressions.new([Require.new(prelude).at(location), nodes] of ASTNode)

        # And normalize
        program.normalize(nodes)
      end
    end

    private def parse(program, source : Source)
      parser = program.new_parser(source.code)
      parser.filename = source.filename
      parser.wants_doc = wants_doc?
      parser.parse
    rescue ex : InvalidByteSequenceError
      stderr.print colorize("Error: ").red.bold
      stderr.print colorize("file '#{Crystal.relative_filename(source.filename)}' is not a valid Crystal source file: ").bold
      stderr.puts ex.message
      exit 1
    end

    private def bc_flags_changed?(output_dir)
      bc_flags_changed = true
      current_bc_flags = "#{@codegen_target}|#{@mcpu}|#{@mattr}|#{@link_flags}|#{@mcmodel}"
      bc_flags_filename = "#{output_dir}/bc_flags#{optimization_mode.suffix}"
      if File.file?(bc_flags_filename)
        previous_bc_flags = File.read(bc_flags_filename).strip
        bc_flags_changed = previous_bc_flags != current_bc_flags
      end
      File.write(bc_flags_filename, current_bc_flags)
      bc_flags_changed
    end

    private def codegen(program, node : ASTNode, sources, output_filename)
      {% if LibLLVM::IS_LT_130 %}
        if @codegen_target.architecture == "aarch64"
          stderr.puts "Error: Target #{@codegen_target} requires a Crystal compiler built with LLVM 13 or a later version."
          exit 1
        end
      {% end %}

      llvm_modules = @progress_tracker.stage("Codegen (crystal)") do
        program.codegen node, debug: debug, frame_pointers: frame_pointers,
          single_module: @single_module || @cross_compile || !@emit_targets.none?
      end

      output_dir = CacheDir.instance.directory_for(sources)

      bc_flags_changed = bc_flags_changed? output_dir
      target_triple = target_machine.triple

      units = llvm_modules.map do |type_name, info|
        llvm_mod = info.mod
        llvm_mod.target = target_triple
        CompilationUnit.new(self, program, type_name, llvm_mod, output_dir, bc_flags_changed)
      end

      {% if LibLLVM::IS_LT_170 %}
        # initialize the legacy pass manager once in the main thread/process
        # before we start codegen in threads (MT) or processes (fork)
        init_llvm_legacy_pass_manager unless optimization_mode.o0?
      {% end %}

      if @cross_compile
        cross_compile program, units, output_filename
      else
        units = with_file_lock(output_dir) do
          codegen program, units, output_filename, output_dir
        end

        {% if flag?(:darwin) %}
          run_dsymutil(output_filename) unless debug.none?
        {% end %}

        {% if flag?(:msvc) %}
          copy_dlls(program, output_filename) unless static?
        {% end %}
      end

      CacheDir.instance.cleanup if @cleanup

      units
    end

    private def with_file_lock(output_dir, &)
      File.open(File.join(output_dir, "compiler.lock"), "w") do |file|
        file.flock_exclusive do
          yield
        end
      end
    end

    private def run_dsymutil(filename)
      dsymutil = Process.find_executable("dsymutil")
      return unless dsymutil

      @progress_tracker.stage("dsymutil") do
        Process.run(dsymutil, ["--flat", filename])
      end
    end

    private def copy_dlls(program, output_filename)
      not_found = nil
      output_directory = File.dirname(output_filename)

      program.each_dll_path do |path, found|
        if found
          dest = File.join(output_directory, File.basename(path))
          File.copy(path, dest) unless File.exists?(dest)
        else
          not_found ||= [] of String
          not_found << path
        end
      end

      if not_found
        stderr << "Warning: The following DLLs are required at run time, but Crystal is unable to locate them in CRYSTAL_LIBRARY_PATH, the compiler's directory, or PATH: "
        not_found.sort!.join(stderr, ", ")
      end
    end

    private def cross_compile(program, units, output_filename)
      unit = units.first
      llvm_mod = unit.llvm_mod

      @progress_tracker.stage("Codegen (bc+obj)") do
        optimize llvm_mod, target_machine unless @optimization_mode.o0?

        unit.emit(@emit_targets, emit_base_filename || output_filename)

        target_machine.emit_obj_to_file llvm_mod, output_filename
      end
      object_names = [output_filename]
      output_filename = output_filename.rchop(unit.object_extension)
      _, command, args = linker_command(program, object_names, output_filename, nil)
      print_command(command, args)
    end

    private def print_command(command, args)
      stdout.puts command.sub(%("${@}"), args && Process.quote(args))
    end

    private def linker_command(program : Program, object_names, output_filename, output_dir, expand = false)
      if program.has_flag? "msvc"
        lib_flags = program.lib_flags(@cross_compile)
        lib_flags = expand_lib_flags(lib_flags) if expand

        object_arg = Process.quote_windows(object_names)
        output_arg = Process.quote_windows("/Fe#{output_filename}")

        linker, link_args = program.msvc_compiler_and_flags
        linker = Process.quote_windows(linker)
        link_args.map! { |arg| Process.quote_windows(arg) }

        link_args << "/DEBUG:FULL /PDBALTPATH:%_PDB%" unless debug.none?
        link_args << "/INCREMENTAL:NO /STACK:0x800000"
        link_args << lib_flags
        @link_flags.try { |flags| link_args << flags }

        {% if flag?(:msvc) %}
          unless @cross_compile
            extra_suffix = static? ? "-static" : "-dynamic"
            search_result = Loader.search_libraries(Process.parse_arguments_windows(link_args.join(' ').gsub('\n', ' ')), extra_suffix: extra_suffix)
            if not_found = search_result.not_found?
              error "Cannot locate the .lib files for the following libraries: #{not_found.join(", ")}"
            end

            link_args = search_result.remaining_args.concat(search_result.library_paths).map { |arg| Process.quote_windows(arg) }
          end
        {% end %}

        args = %(/nologo #{object_arg} #{output_arg} /link #{link_args.join(' ')}).gsub("\n", " ")
        cmd = "#{linker} #{args}"

        if cmd.to_utf16.size > 32000
          # The command line would be too big, pass the args through a UTF-16-encoded file instead.
          # TODO: Use a proper way to write encoded text to a file when that's supported.
          # The first character is the BOM; it will be converted in the same endianness as the rest.
          args_16 = "\ufeff#{args}".to_utf16
          args_bytes = args_16.to_unsafe_bytes

          args_filename = "#{output_dir}/linker_args.txt"
          File.write(args_filename, args_bytes)
          cmd = "#{linker} #{Process.quote_windows("@" + args_filename)}"
        end

        {linker, cmd, nil}
      elsif program.has_flag? "wasm32"
        link_flags = @link_flags || ""
        {"wasm-ld", %(wasm-ld "${@}" -o #{Process.quote_posix(output_filename)} #{link_flags} -lc #{program.lib_flags(@cross_compile)}), object_names}
      elsif program.has_flag? "avr"
        link_flags = @link_flags || ""
        link_flags += " --target=avr-unknown-unknown -mmcu=#{@mcpu} -Wl,--gc-sections"
        {DEFAULT_LINKER, %(#{DEFAULT_LINKER} "${@}" -o #{Process.quote_posix(output_filename)} #{link_flags} #{program.lib_flags(@cross_compile)}), object_names}
      elsif program.has_flag?("win32") && program.has_flag?("gnu")
        link_flags = @link_flags || ""
        link_flags += " -Wl,--stack,0x800000"
        lib_flags = program.lib_flags(@cross_compile)
        lib_flags = expand_lib_flags(lib_flags) if expand
        cmd = %(#{DEFAULT_LINKER} #{Process.quote_windows(object_names)} -o #{Process.quote_windows(output_filename)} #{link_flags} #{lib_flags}).gsub('\n', ' ')

        if cmd.size > 32000
          # The command line would be too big, pass the args through a file instead.
          # GCC response file does not interpret those args as shell-escaped
          # arguments, we must rebuild the whole command line
          args_filename = "#{output_dir}/linker_args.txt"
          File.open(args_filename, "w") do |f|
            object_names.each do |object_name|
              f << object_name.gsub(GCC_RESPONSE_FILE_TR) << ' '
            end
            f << "-o " << output_filename.gsub(GCC_RESPONSE_FILE_TR) << ' '
            f << link_flags << ' ' << lib_flags
          end
          cmd = "#{DEFAULT_LINKER} #{Process.quote_windows("@" + args_filename)}"
        end

        {DEFAULT_LINKER, cmd, nil}
      else
        link_flags = @link_flags || ""
        link_flags += " -rdynamic"

        if program.has_flag?("freebsd") || program.has_flag?("openbsd")
          # pkgs are installed to usr/local/lib but it's not in LIBRARY_PATH by
          # default; we declare it to ease linking on these platforms:
          link_flags += " -L/usr/local/lib"
        end

        {DEFAULT_LINKER, %(#{DEFAULT_LINKER} "${@}" -o #{Process.quote_posix(output_filename)} #{link_flags} #{program.lib_flags(@cross_compile)}), object_names}
      end
    end

    private GCC_RESPONSE_FILE_TR = {
      " ":  %q(\ ),
      "'":  %q(\'),
      "\"": %q(\"),
      "\\": "\\\\",
    }

    private def expand_lib_flags(lib_flags)
      lib_flags.gsub(/`(.*?)`/) do
        command = $1
        begin
          error_io = IO::Memory.new
          output = Process.run(command, shell: true, output: :pipe, error: error_io) do |process|
            process.output.gets_to_end
          end
          unless $?.success?
            error_io.rewind
            error "Error executing subcommand for linker flags: #{command.inspect}: #{error_io}"
          end
          output.chomp
        rescue exc
          error "Error executing subcommand for linker flags: #{command.inspect}: #{exc}"
        end
      end
    end

    private def codegen(program, units : Array(CompilationUnit), output_filename, output_dir)
      object_names = units.map &.object_filename
      target_triple = target_machine.triple

      @progress_tracker.stage("Codegen (bc+obj)") do
        @progress_tracker.stage_progress_total = units.size

        n_threads = @n_threads.clamp(1..units.size)

        if n_threads == 1
          sequential_codegen(units)
        else
          parallel_codegen(units, n_threads)
        end

        if units.size == 1
          units.first.emit(@emit_targets, emit_base_filename || output_filename)
        end
      end

      # We check again because maybe this directory was created in between (maybe with a macro run)
      if Dir.exists?(output_filename)
        error "can't use `#{output_filename}` as output filename because it's a directory"
      end

      output_filename = File.expand_path(output_filename)

      @progress_tracker.stage("Codegen (linking)") do
        Dir.cd(output_dir) do
          run_linker *linker_command(program, object_names, output_filename, output_dir, expand: true)
        end
      end

      units
    end

    private def sequential_codegen(units)
      units.each do |unit|
        unit.compile
        @progress_tracker.stage_progress += 1
      end
    end

    private def parallel_codegen(units, n_threads)
      {% if flag?(:preview_mt) %}
        raise "LLVM isn't multithreaded and cannot fork compiler in multithread mode." unless LLVM.multithreaded?
        mt_codegen(units, n_threads)
      {% elsif LibC.has_method?("fork") %}
        fork_codegen(units, n_threads)
      {% else %}
        raise "Cannot fork compiler. `Crystal::System::Process.fork` is not implemented on this system."
      {% end %}
    end

    private def mt_codegen(units, n_threads)
      channel = Channel(CompilationUnit).new(n_threads * 2)
      wg = WaitGroup.new
      mutex = Mutex.new

      n_threads.times do
        wg.spawn do
          while unit = channel.receive?
            unit.compile(isolate_context: true)
            mutex.synchronize { @progress_tracker.stage_progress += 1 }
          end
        end
      end

      units.each do |unit|
        # We generate the bitcode in the main thread because LLVM contexts
        # must be unique per compilation unit, but we share different contexts
        # across many modules (or rely on the global context); trying to
        # codegen in parallel would segfault!
        #
        # Luckily generating the bitcode is quick and once the bitcode is
        # generated we don't need the global LLVM contexts anymore but can
        # parse the bitcode in an isolated context and we can parallelize the
        # slowest part: the optimization pass & compiling the object file.
        unit.generate_bitcode

        channel.send(unit)
      end
      channel.close

      wg.wait
    end

    private def fork_codegen(units, n_threads)
      workers = fork_workers(n_threads) do |input, output|
        while i = input.gets(chomp: true).presence
          unit = units[i.to_i]
          unit.compile
          result = {name: unit.name, reused: unit.reused_previous_compilation?}
          output.puts result.to_json
        end
      rescue ex
        result = {exception: {name: ex.class.name, message: ex.message, backtrace: ex.backtrace}}
        output.puts result.to_json
      end

      overqueue = 1
      indexes = Atomic(Int32).new(0)
      channel = Channel(String).new(n_threads)
      completed = Channel(Nil).new(n_threads)

      workers.each do |pid, input, output|
        spawn do
          overqueued = 0

          overqueue.times do
            if (index = indexes.add(1)) < units.size
              input.puts index
              overqueued += 1
            end
          end

          while (index = indexes.add(1)) < units.size
            input.puts index

            if response = output.gets(chomp: true)
              channel.send response
            else
              Crystal::System.print_error "\nBUG: a codegen process failed\n"
              exit 1
            end
          end

          overqueued.times do
            if response = output.gets(chomp: true)
              channel.send response
            else
              Crystal::System.print_error "\nBUG: a codegen process failed\n"
              exit 1
            end
          end

          input << '\n'
          input.close
          output.close

          Process.new(pid).wait
          completed.send(nil)
        end
      end

      spawn do
        n_threads.times { completed.receive }
        channel.close
      end

      while response = channel.receive?
        result = JSON.parse(response)

        if ex = result["exception"]?
          Crystal::System.print_error "\nBUG: a codegen process failed: %s (%s)\n", ex["message"].as_s, ex["name"].as_s
          ex["backtrace"].as_a?.try(&.each { |frame| Crystal::System.print_error "  from %s\n", frame })
          exit 1
        end

        if @progress_tracker.stats?
          if result["reused"].as_bool
            name = result["name"].as_s
            unit = units.find { |unit| unit.name == name }.not_nil!
            unit.reused_previous_compilation = true
          end
        end
        @progress_tracker.stage_progress += 1
      end
    end

    private def fork_workers(n_threads, &)
      workers = [] of {Int32, IO::FileDescriptor, IO::FileDescriptor}

      n_threads.times do
        iread, iwrite = IO.pipe
        oread, owrite = IO.pipe

        iwrite.flush_on_newline = true
        owrite.flush_on_newline = true

        pid = Crystal::System::Process.fork do
          iwrite.close
          oread.close

          yield iread, owrite

          iread.close
          owrite.close
          exit 0
        end

        iread.close
        owrite.close

        workers << {pid, iwrite, oread}
      end

      workers
    end

    private def print_macro_run_stats(program)
      return unless @progress_tracker.stats?
      return if program.compiled_macros_cache.empty?

      puts
      puts "Macro runs:"
      program.compiled_macros_cache.each do |filename, compiled_macro_run|
        print " - "
        print filename
        print ": "
        if compiled_macro_run.reused
          print "reused previous compilation (#{compiled_macro_run.elapsed})"
        else
          print compiled_macro_run.elapsed
        end
        puts
      end
    end

    private def print_codegen_stats(units)
      return unless @progress_tracker.stats?
      return unless units

      reused = units.count(&.reused_previous_compilation?)

      puts
      puts "Codegen (bc+obj):"
      case reused
      when units.size
        puts " - all previous .o files were reused"
      when .zero?
        puts " - no previous .o files were reused"
      else
        puts " - #{reused}/#{units.size} .o files were reused"
        puts
        puts "These modules were not reused:"
        units.each do |unit|
          next if unit.reused_previous_compilation?
          puts " - #{unit.original_name} (#{unit.name}.bc)"
        end
      end
    end

    getter(target_machine : LLVM::TargetMachine) do
      create_target_machine
    end

    def create_target_machine
      @codegen_target.to_target_machine(@mcpu || "", @mattr || "", @optimization_mode, @mcmodel)
    rescue ex : ArgumentError
      stderr.print colorize("Error: ").red.bold
      stderr.print "llc: "
      stderr.puts ex.message
      exit 1
    end

    {% if LibLLVM::IS_LT_170 %}
      property! pass_manager_builder : LLVM::PassManagerBuilder

      private def init_llvm_legacy_pass_manager
        registry = LLVM::PassRegistry.instance
        registry.initialize_all

        builder = LLVM::PassManagerBuilder.new
        builder.size_level = 0

        case optimization_mode
        in .o3?
          builder.opt_level = 3
          builder.use_inliner_with_threshold = 275
        in .o2?
          builder.opt_level = 2
          builder.use_inliner_with_threshold = 275
        in .o1?
          builder.opt_level = 1
          builder.use_inliner_with_threshold = 150
        in .o0?
          # default behaviour, no optimizations
        in .os?
          builder.opt_level = 2
          builder.size_level = 1
          builder.use_inliner_with_threshold = 50
        in .oz?
          builder.opt_level = 2
          builder.size_level = 2
          builder.use_inliner_with_threshold = 5
        end

        @pass_manager_builder = builder
      end

      private def optimize_with_pass_manager(llvm_mod)
        fun_pass_manager = llvm_mod.new_function_pass_manager
        pass_manager_builder.populate fun_pass_manager
        fun_pass_manager.run llvm_mod

        module_pass_manager = LLVM::ModulePassManager.new
        pass_manager_builder.populate module_pass_manager
        module_pass_manager.run llvm_mod
      end
    {% end %}

    protected def optimize(llvm_mod, target_machine)
      {% if LibLLVM::IS_LT_130 %}
        optimize_with_pass_manager(llvm_mod)
      {% else %}
        {% if LibLLVM::IS_LT_170 %}
          # PassBuilder doesn't support Os and Oz before LLVM 17
          if @optimization_mode.os? || @optimization_mode.oz?
            return optimize_with_pass_manager(llvm_mod)
          end
        {% end %}

        LLVM::PassBuilderOptions.new do |options|
          LLVM.run_passes(llvm_mod, "default<#{@optimization_mode}>", target_machine, options)
        end
      {% end %}
    end

    private def run_linker(linker_name, command, args)
      print_command(command, args) if verbose?

      begin
        Process.run(command, args, shell: true,
          input: Process::Redirect::Close, output: Process::Redirect::Inherit, error: Process::Redirect::Pipe) do |process|
          process.error.each_line(chomp: false) do |line|
            hint_string = colorize("(this usually means you need to install the development package for lib\\1)").yellow.bold
            line = line.gsub(/cannot find -l(\S+)\b/, "cannot find -l\\1 #{hint_string}")
            line = line.gsub(/unable to find library -l(\S+)\b/, "unable to find library -l\\1 #{hint_string}")
            line = line.gsub(/library not found for -l(\S+)\b/, "library not found for -l\\1 #{hint_string}")
            STDERR << line
          end
        end
      rescue exc : File::AccessDeniedError | File::NotFoundError
        linker_not_found exc.class, linker_name
      end

      status = $?
      unless status.success?
        exit_code = status.exit_code?
        case exit_code
        when 126
          linker_not_found File::AccessDeniedError, linker_name
        when 127
          linker_not_found File::NotFoundError, linker_name
        when nil
          # abnormal exit
          exit_code = 1
        end
        error "execution of command failed with exit status #{status}: #{command}", exit_code: exit_code
      end
    end

    private def linker_not_found(exc_class, linker_name)
      verbose_info = "\nRun with `--verbose` to print the full linker command." unless verbose?
      case exc_class
      when File::AccessDeniedError
        error "Could not execute linker: `#{linker_name}`: Permission denied#{verbose_info}"
      else
        error "Could not execute linker: `#{linker_name}`: File not found#{verbose_info}"
      end
    end

    private def error(msg, exit_code = 1)
      Crystal.error msg, @color, exit_code, stderr: stderr
    end

    private def colorize(obj)
      obj.colorize.toggle(@color)
    end

    # An LLVM::Module with information to compile it.
    class CompilationUnit
      getter compiler
      getter name
      getter original_name
      getter llvm_mod
      property? reused_previous_compilation = false
      getter object_extension : String
      @memory_buffer : LLVM::MemoryBuffer?
      @object_name : String?
      @bc_name : String?

      def initialize(@compiler : Compiler, program : Program, @name : String,
                     @llvm_mod : LLVM::Module, @output_dir : String, @bc_flags_changed : Bool)
        @name = "_main" if @name == ""
        @original_name = @name
        @name = String.build do |str|
          @name.each_char do |char|
            case char
            when 'a'..'z', '0'..'9', '_'
              str << char
            when 'A'..'Z'
              # Because OSX has case insensitive filenames, try to avoid
              # clash of 'a' and 'A' by using 'A-' for 'A'.
              str << char << '-'
            else
              str << char.ord
            end
          end
        end

        if @name.size > 50
          # 17 chars from name + 1 (dash) + 32 (md5) = 50
          @name = "#{@name[0..16]}-#{::Crystal::Digest::MD5.hexdigest(@name)}"
        end

        @name = "#{@name}#{@compiler.optimization_mode.suffix}"
        @object_extension = compiler.codegen_target.object_extension
      end

      def generate_bitcode
        @memory_buffer ||= llvm_mod.write_bitcode_to_memory_buffer
      end

      # To compile a file we first generate a `.bc` file and then create an
      # object file from it. These `.bc` files are stored in the cache
      # directory.
      #
      # On a next compilation of the same project, and if the compile flags
      # didn't change (a combination of the target triple, mcpu and link flags,
      # amongst others), we check if the new `.bc` file is exactly the same as
      # the old one. In that case the `.o` file will also be the same, so we
      # simply reuse the old one. Generating an `.o` file is what takes most
      # time.
      #
      # However, instead of directly generating the final `.o` file from the
      # `.bc` file, we generate it to a temporary name (`.o.tmp`) and then we
      # rename that file to `.o`. We do this because the compiler could be
      # interrupted while the `.o` file is being generated, leading to a
      # corrupted file that later would cause compilation issues. Moving a file
      # is an atomic operation so no corrupted `.o` file should be generated.
      def compile(isolate_context = false)
        if must_compile?
          isolate_module_context if isolate_context
          update_bitcode_cache
          compile_to_object
        else
          @reused_previous_compilation = true
        end
        dump_llvm_ir
      end

      private def must_compile?
        memory_buffer = generate_bitcode

        can_reuse_previous_compilation =
          compiler.emit_targets.none? && !@bc_flags_changed && File.exists?(bc_name) && File.exists?(object_name)

        if can_reuse_previous_compilation
          memory_io = IO::Memory.new(memory_buffer.to_slice)
          changed = File.open(bc_name) { |bc_file| !IO.same_content?(bc_file, memory_io) }

          # If the user cancelled a previous compilation
          # it might be that the .o file is empty
          if !changed && File.size(object_name) > 0
            memory_buffer.dispose
            return false
          else
            # We need to compile, so we'll write the memory buffer to file
          end
        end

        true
      end

      # Parse the previously generated bitcode into the LLVM module using a
      # dedicated context, so we can safely optimize & compile the module in
      # multiple threads (llvm contexts can't be shared across threads).
      private def isolate_module_context
        @llvm_mod = LLVM::Module.parse(@memory_buffer.not_nil!, LLVM::Context.new)
      end

      private def update_bitcode_cache
        return unless memory_buffer = @memory_buffer

        # Delete existing .o file. It cannot be used anymore.
        File.delete?(object_name)
        # Create the .bc file (for next compilations)
        File.write(bc_name, memory_buffer.to_slice)
        memory_buffer.dispose
      end

      private def compile_to_object
        temporary_object_name = self.temporary_object_name
        target_machine = compiler.create_target_machine
        compiler.optimize llvm_mod, target_machine unless compiler.optimization_mode.o0?
        target_machine.emit_obj_to_file llvm_mod, temporary_object_name
        File.rename(temporary_object_name, object_name)
      end

      private def dump_llvm_ir
        llvm_mod.print_to_file ll_name if compiler.dump_ll?
      end

      def emit(emit_targets : EmitTarget, output_filename)
        if emit_targets.asm?
          compiler.target_machine.emit_asm_to_file llvm_mod, "#{output_filename}.s"
        end
        if emit_targets.llvm_bc?
          FileUtils.cp(bc_name, "#{output_filename}.bc")
        end
        if emit_targets.llvm_ir?
          llvm_mod.print_to_file "#{output_filename}.ll"
        end
        if emit_targets.obj?
          FileUtils.cp(object_name, output_filename + @object_extension)
        end
      end

      def object_name
        Crystal.relative_filename("#{@output_dir}/#{object_filename}")
      end

      def object_filename
        @name + @object_extension
      end

      def temporary_object_name
        Crystal.relative_filename("#{@output_dir}/#{object_filename}.tmp")
      end

      def bc_name
        "#{@output_dir}/#{@name}.bc"
      end

      def bc_name_new
        "#{@output_dir}/#{@name}.new.bc"
      end

      def ll_name
        "#{@output_dir}/#{@name}.ll"
      end
    end
  end
end
