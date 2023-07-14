require "option_parser"
require "file_utils"
require "colorize"
require "crystal/digest/md5"
{% if flag?(:msvc) %}
  require "./loader"
  require "crystal/system/win32/visual_studio"
  require "crystal/system/win32/windows_sdk"
{% end %}

module Crystal
  @[Flags]
  enum Debug
    LineNumbers
    Variables
    Default     = LineNumbers
  end

  # Main interface to the compiler.
  #
  # A Compiler parses source code, type checks it and
  # optionally generates an executable.
  class Compiler
    private DEFAULT_LINKER = ENV["CC"]? || "cc"
    private MSVC_LINKER    = ENV["CC"]? || "cl.exe"

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
    property n_threads : Int32 = {% if flag?(:preview_mt) || flag?(:win32) %} 1 {% else %} 8 {% end %}

    # Default prelude file to use. This ends up adding a
    # `require "prelude"` (or whatever name is set here) to
    # the source file to compile.
    property prelude = "prelude"

    # If `true`, runs LLVM optimizations.
    property? release = false

    # Sets the code model. Check LLVM docs to learn about this.
    property mcmodel = LLVM::CodeModel::Default

    # If `true`, generates a single LLVM module. By default
    # one LLVM module is created for each type in a program.
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

    # Program that was created for the last compilation.
    property! program : Program

    # Compiles the given *source*, with *output_filename* as the name
    # of the generated executable.
    #
    # If *combine_rpath* is true, add the compiler itself's RPATH to the
    # generated executable via `CrystalLibraryPath.add_compiler_rpath`. This is
    # used by the `run` / `eval` / `spec` commands as well as the macro `run`
    # (via `Crystal::Program#macro_compile`), and never during cross-compiling.
    #
    # Raises `Crystal::CodeError` if there's an error in the
    # source code.
    #
    # Raises `InvalidByteSequenceError` if the source code is not
    # valid UTF-8.
    def compile(source : Source | Array(Source), output_filename : String, *, combine_rpath : Bool = false) : Result
      if combine_rpath
        return CrystalLibraryPath.add_compiler_rpath { compile(source, output_filename, combine_rpath: false) }
      end

      source = [source] unless source.is_a?(Array)
      program = new_program(source)
      node = parse program, source
      node = program.semantic node, cleanup: !no_cleanup?
      result = codegen program, node, source, output_filename unless @no_codegen

      @progress_tracker.clear
      print_macro_run_stats(program)
      print_codegen_stats(result)

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

    private def new_program(sources)
      @program = program = Program.new
      program.compiler = self
      program.filename = sources.first.filename
      program.codegen_target = codegen_target
      program.target_machine = target_machine
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
      current_bc_flags = "#{@codegen_target}|#{@mcpu}|#{@mattr}|#{@release}|#{@link_flags}|#{@mcmodel}"
      bc_flags_filename = "#{output_dir}/bc_flags"
      if File.file?(bc_flags_filename)
        previous_bc_flags = File.read(bc_flags_filename).strip
        bc_flags_changed = previous_bc_flags != current_bc_flags
      end
      File.write(bc_flags_filename, current_bc_flags)
      bc_flags_changed
    end

    private def codegen(program, node : ASTNode, sources, output_filename)
      llvm_modules = @progress_tracker.stage("Codegen (crystal)") do
        program.codegen node, debug: debug, single_module: @single_module || @release || @cross_compile || !@emit_targets.none?
      end

      output_dir = CacheDir.instance.directory_for(sources)

      bc_flags_changed = bc_flags_changed? output_dir
      target_triple = target_machine.triple

      units = llvm_modules.map do |type_name, info|
        llvm_mod = info.mod
        llvm_mod.target = target_triple
        CompilationUnit.new(self, program, type_name, llvm_mod, output_dir, bc_flags_changed)
      end

      if @cross_compile
        cross_compile program, units, output_filename
      else
        result = with_file_lock(output_dir) do
          codegen program, units, output_filename, output_dir
        end

        {% if flag?(:darwin) %}
          run_dsymutil(output_filename) unless debug.none?
        {% end %}
      end

      CacheDir.instance.cleanup if @cleanup

      result
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

    private def cross_compile(program, units, output_filename)
      unit = units.first
      llvm_mod = unit.llvm_mod

      @progress_tracker.stage("Codegen (bc+obj)") do
        optimize llvm_mod if @release

        unit.emit(@emit_targets, emit_base_filename || output_filename)

        target_machine.emit_obj_to_file llvm_mod, output_filename
      end

      _, command, args = linker_command(program, [output_filename], output_filename, nil)
      print_command(command, args)
    end

    private def print_command(command, args)
      stdout.puts command.sub(%("${@}"), args && Process.quote(args))
    end

    private def linker_command(program : Program, object_names, output_filename, output_dir, expand = false)
      if program.has_flag? "msvc"
        lib_flags = program.lib_flags
        # Execute and expand `subcommands`.
        lib_flags = lib_flags.gsub(/`(.*?)`/) { `#{$1}` } if expand

        object_arg = Process.quote_windows(object_names)
        output_arg = Process.quote_windows("/Fe#{output_filename}")

        linker = MSVC_LINKER
        link_args = [] of String

        # if the compiler and the target both have the `msvc` flag, we are not
        # cross-compiling and therefore we should attempt detecting MSVC's
        # standard paths
        {% if flag?(:msvc) %}
          if msvc_path = Crystal::System::VisualStudio.find_latest_msvc_path
            if win_sdk_libpath = Crystal::System::WindowsSDK.find_win10_sdk_libpath
              host_bits = {{ flag?(:aarch64) ? "ARM64" : flag?(:bits64) ? "x64" : "x86" }}
              target_bits = program.has_flag?("aarch64") ? "arm64" : program.has_flag?("bits64") ? "x64" : "x86"

              # MSVC build tools and Windows SDK found; recreate `LIB` environment variable
              # that is normally expected on the MSVC developer command prompt
              link_args << Process.quote_windows("/LIBPATH:#{msvc_path.join("atlmfc", "lib", target_bits)}")
              link_args << Process.quote_windows("/LIBPATH:#{msvc_path.join("lib", target_bits)}")
              link_args << Process.quote_windows("/LIBPATH:#{win_sdk_libpath.join("ucrt", target_bits)}")
              link_args << Process.quote_windows("/LIBPATH:#{win_sdk_libpath.join("um", target_bits)}")

              # use exact path for compiler instead of relying on `PATH`
              # (letter case shouldn't matter in most cases but being exact doesn't hurt here)
              target_bits = target_bits.sub("arm", "ARM")
              linker = Process.quote_windows(msvc_path.join("bin", "Host#{host_bits}", target_bits, "cl.exe").to_s) unless ENV.has_key?("CC")
            end
          end
        {% end %}

        link_args << "/DEBUG:FULL /PDBALTPATH:%_PDB%" unless debug.none?
        link_args << "/INCREMENTAL:NO /STACK:0x800000"
        link_args << lib_flags
        @link_flags.try { |flags| link_args << flags }

        {% if flag?(:msvc) %}
          unless @cross_compile
            extra_suffix = program.has_flag?("preview_dll") ? "-dynamic" : "-static"
            search_result = Loader.search_libraries(Process.parse_arguments_windows(link_args.join(' ').gsub('\n', ' ')), extra_suffix: extra_suffix)
            if not_found = search_result.not_found?
              error "Cannot locate the .lib files for the following libraries: #{not_found.join(", ")}"
            end

            link_args = search_result.remaining_args.concat(search_result.library_paths).map { |arg| Process.quote_windows(arg) }

            if program.has_flag?("preview_win32_delay_load")
              # "LINK : warning LNK4199: /DELAYLOAD:foo.dll ignored; no imports found from foo.dll"
              # it is harmless to skip this error because not all import libraries are always used, much
              # less the individual DLLs they refer to
              link_args << "/IGNORE:4199"

              dlls = Set(String).new
              search_result.library_paths.each do |library_path|
                Crystal::System::LibraryArchive.imported_dlls(library_path).each do |dll|
                  dlls << dll.downcase
                end
              end
              dlls.delete "kernel32.dll"
              dlls.each { |dll| link_args << "/DELAYLOAD:#{dll}" }
            end
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
        {"wasm-ld", %(wasm-ld "${@}" -o #{Process.quote_posix(output_filename)} #{link_flags} -lc #{program.lib_flags}), object_names}
      else
        link_flags = @link_flags || ""
        link_flags += " -rdynamic"

        {DEFAULT_LINKER, %(#{DEFAULT_LINKER} "${@}" -o #{Process.quote_posix(output_filename)} #{link_flags} #{program.lib_flags}), object_names}
      end
    end

    private def codegen(program, units : Array(CompilationUnit), output_filename, output_dir)
      object_names = units.map &.object_filename

      target_triple = target_machine.triple
      reused = [] of String

      @progress_tracker.stage("Codegen (bc+obj)") do
        @progress_tracker.stage_progress_total = units.size

        if units.size == 1
          first_unit = units.first
          first_unit.compile
          reused << first_unit.name if first_unit.reused_previous_compilation?
          first_unit.emit(@emit_targets, emit_base_filename || output_filename)
        else
          reused = codegen_many_units(program, units, target_triple)
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

      {units, reused}
    end

    private def codegen_many_units(program, units, target_triple)
      all_reused = [] of String

      wants_stats_or_progress = @progress_tracker.stats? || @progress_tracker.progress?

      # If threads is 1 and no stats/progress is needed we can avoid
      # fork/spawn/channels altogether. This is particularly useful for
      # CI because there forking eventually leads to "out of memory" errors.
      if @n_threads == 1
        units.each do |unit|
          unit.compile
          all_reused << unit.name if wants_stats_or_progress && unit.reused_previous_compilation?
        end
        return all_reused
      end

      {% if !Crystal::System::Process.class.has_method?("fork") %}
        raise "Cannot fork compiler. `Crystal::System::Process.fork` is not implemented on this system."
      {% elsif flag?(:preview_mt) %}
        raise "Cannot fork compiler in multithread mode"
      {% else %}
        jobs_count = 0
        wait_channel = Channel(Array(String)).new(@n_threads)

        units.each_slice(Math.max(units.size // @n_threads, 1)) do |slice|
          jobs_count += 1
          spawn do
            # For stats output we want to count how many previous
            # .o files were reused, mainly to detect performance regressions.
            # Because we fork, we must communicate using a pipe.
            reused = [] of String
            if wants_stats_or_progress
              pr, pw = IO.pipe
              spawn do
                pr.each_line do |line|
                  unit_info = JSON.parse(line)
                  reused << unit_info["name"].as_s if unit_info["reused"].as_bool

                  module_idx = unit_info["idx"].as_i
                  slice.update(module_idx) do |unit|
                    unit.compilation_time = unit_info["time"].as_f.seconds
                    unit
                  end

                  @progress_tracker.stage_progress += 1
                end
              end
            end

            codegen_process = Crystal::System::Process.fork do
              pipe_w = pw
              slice.each_with_index do |unit, idx|
                unit.compile
                if pipe_w
                  unit_json = {
                    name:   unit.name,
                    reused: unit.reused_previous_compilation?,
                    idx:    idx,
                    time:   unit.compilation_time.total_seconds,
                  }.to_json
                  pipe_w.puts unit_json
                end
              end
            end
            Process.new(codegen_process).wait

            if pipe_w = pw
              pipe_w.close
              Fiber.yield
            end

            wait_channel.send reused
          end
        end

        jobs_count.times do
          reused = wait_channel.receive
          all_reused.concat(reused)
        end

        all_reused
      {% end %}
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

    private def print_codegen_stats(result)
      return unless @progress_tracker.stats?
      return unless result

      units, reused = result

      puts
      puts "Codegen (bc+obj):"
      if units.size == reused.size
        puts " - all previous .o files were reused"
      elsif reused.size == 0
        puts " - no previous .o files were reused"
      else
        puts " - #{reused.size}/#{units.size} .o files were reused"
        not_reused = units.reject { |u| reused.includes?(u.name) }
        puts
        puts "These modules were not reused:"
        not_reused.each do |unit|
          puts " - #{unit.original_name} (#{unit.name}.bc)"
        end
      end

      if units.size != reused.size
        puts
        puts("Top 10 slowest modules:")
        units.sort_by! { |u| u.compilation_time * -1 }
        units.first(10).each do |unit|
          puts " - #{unit.compilation_time} #{unit.original_name} (#{unit.name}.bc)"
        end
      end
    end

    getter(target_machine : LLVM::TargetMachine) do
      @codegen_target.to_target_machine(@mcpu || "", @mattr || "", @release, @mcmodel)
    rescue ex : ArgumentError
      stderr.print colorize("Error: ").red.bold
      stderr.print "llc: "
      stderr.puts ex.message
      exit 1
    end

    {% if LibLLVM::IS_LT_130 %}
      protected def optimize(llvm_mod)
        fun_pass_manager = llvm_mod.new_function_pass_manager
        pass_manager_builder.populate fun_pass_manager
        fun_pass_manager.run llvm_mod
        module_pass_manager.run llvm_mod
      end

      @module_pass_manager : LLVM::ModulePassManager?

      private def module_pass_manager
        @module_pass_manager ||= begin
          mod_pass_manager = LLVM::ModulePassManager.new
          pass_manager_builder.populate mod_pass_manager
          mod_pass_manager
        end
      end

      @pass_manager_builder : LLVM::PassManagerBuilder?

      private def pass_manager_builder
        @pass_manager_builder ||= begin
          registry = LLVM::PassRegistry.instance
          registry.initialize_all

          builder = LLVM::PassManagerBuilder.new
          builder.opt_level = 3
          builder.size_level = 0
          builder.use_inliner_with_threshold = 275
          builder
        end
      end
    {% else %}
      protected def optimize(llvm_mod)
        LLVM::PassBuilderOptions.new do |options|
          LLVM.run_passes(llvm_mod, "default<O3>", target_machine, options)
        end
      end
    {% end %}

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
        if status.normal_exit?
          case status.exit_code
          when 126
            linker_not_found File::AccessDeniedError, linker_name
          when 127
            linker_not_found File::NotFoundError, linker_name
          end
        end
        code = status.normal_exit? ? status.exit_code : 1
        error "execution of command failed with exit status #{status}: #{command}", exit_code: code
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
      getter? reused_previous_compilation = false
      property compilation_time : Time::Span = Time::Span::ZERO
      @object_extension : String

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

        @object_extension = compiler.codegen_target.object_extension
      end

      def compile
        @compilation_time = Time.measure do
          compile_to_object
        end
      end

      private def compile_to_object
        bc_name = self.bc_name
        object_name = self.object_name
        temporary_object_name = self.temporary_object_name

        # To compile a file we first generate a `.bc` file and then
        # create an object file from it. These `.bc` files are stored
        # in the cache directory.
        #
        # On a next compilation of the same project, and if the compile
        # flags didn't change (a combination of the target triple, mcpu,
        # release and link flags, amongst others), we check if the new
        # `.bc` file is exactly the same as the old one. In that case
        # the `.o` file will also be the same, so we simply reuse the
        # old one. Generating an `.o` file is what takes most time.
        #
        # However, instead of directly generating the final `.o` file
        # from the `.bc` file, we generate it to a temporary name (`.o.tmp`)
        # and then we rename that file to `.o`. We do this because the compiler
        # could be interrupted while the `.o` file is being generated, leading
        # to a corrupted file that later would cause compilation issues.
        # Moving a file is an atomic operation so no corrupted `.o` file should
        # be generated.

        must_compile = true
        can_reuse_previous_compilation =
          compiler.emit_targets.none? && !@bc_flags_changed && File.exists?(bc_name) && File.exists?(object_name)

        memory_buffer = llvm_mod.write_bitcode_to_memory_buffer

        if can_reuse_previous_compilation
          memory_io = IO::Memory.new(memory_buffer.to_slice)
          changed = File.open(bc_name) { |bc_file| !IO.same_content?(bc_file, memory_io) }

          # If the user cancelled a previous compilation
          # it might be that the .o file is empty
          if !changed && File.size(object_name) > 0
            must_compile = false
            memory_buffer.dispose
            memory_buffer = nil
          else
            # We need to compile, so we'll write the memory buffer to file
          end
        end

        # If there's a memory buffer, it means we must create a .o from it
        if memory_buffer
          # Delete existing .o file. It cannot be used anymore.
          File.delete?(object_name)
          # Create the .bc file (for next compilations)
          File.write(bc_name, memory_buffer.to_slice)
          memory_buffer.dispose
        end

        if must_compile
          compiler.optimize llvm_mod if compiler.release?
          compiler.target_machine.emit_obj_to_file llvm_mod, temporary_object_name
          File.rename(temporary_object_name, object_name)
        else
          @reused_previous_compilation = true
        end

        dump_llvm_ir
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
