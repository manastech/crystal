# Implementation of the `crystal eval` command

class Crystal::Command
  private def eval
    compiler = new_compiler
    opt_program_source = nil
    program_args = [] of String

    parse_with_crystal_opts do |opts|
      opts.banner = "Usage: crystal eval [options] [source]\n\nOptions:"
      setup_simple_compiler_options compiler, opts

      opts.unknown_args do |before_dash, after_dash|
        opt_program_source = before_dash.join " "
        program_args = after_dash
      end
    end

    program_source = opt_program_source
    if program_source.nil?
      program_source = STDIN.gets_to_end
    end

    sources = [Compiler::Source.new("eval", program_source)]

    output_filename = Crystal.temp_executable "eval"

    compiler.compile sources, output_filename
    execute output_filename, program_args, compiler
  end
end
