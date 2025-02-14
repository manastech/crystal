# Implementation of the `crystal tool apply-types` command
#
# This provides the CLI interface for `crystal/tools/typer.cr`

class Crystal::Command
  private def apply_types
    prelude = "prelude"
    type_blocks = false
    type_splats = false
    type_double_splats = false
    excludes = ["lib"]
    stats = false
    progress = false
    error_trace = false

    parser = OptionParser.new do |opts|
      opts.banner = <<-USAGE
        Usage: crystal tool apply-types [options] entrypoint [def_locator [def_locator [...]]]

        A def_locator comes in 4 formats:

        * A directory name ('src')
        * A file ('src/my_project.cr')
        * A line number in a file ('src/my_project.cr:3')
        * The location of the def method to be typed, specifically ('src/my_project.cr:3:3')

        If a `def` definition matches a provided def_locator and is missing type restrictions, they will be added.
        If no def_locators are provided, then the directory of the entrypoint is used.

        Options:
        USAGE

      opts.on("-h", "--help", "Show this message") do
        puts opts
        exit
      end

      opts.on("--exclude [DIRECTORY]", "Exclude a directory from being typed") do |ex|
        excludes << ex
      end

      opts.on("--error-trace", "Show full error trace") do
        error_trace = true
      end

      opts.on("--prelude [PRELUDE]", "Use given file as prelude. Use empty string to skip prelude entirely.") do |new_prelude|
        prelude = new_prelude
      end

      opts.on("--include-blocks", "Enable adding types to named block arguments (these usually get typed with Proc(Nil) and isn't helpful)") do
        type_blocks = true
      end

      opts.on("--include-double-splats", "Enable adding types to double splats") do
        type_double_splats = true
      end

      opts.on("--include-splats", "Enable adding types to splats") do
        type_splats = true
      end

      opts.on("--stats", "Enable statistics output") do
        stats = true
      end

      opts.on("--progress", "Enable progress output") do
        progress = true
      end
    end

    parser.parse(options)

    unless entrypoint = options.shift?
      puts parser
      exit
    end

    def_locators = options

    results = SourceTyper.new(
      entrypoint,
      def_locators,
      excludes,
      type_blocks,
      type_splats,
      type_double_splats,
      prelude,
      stats,
      progress,
      error_trace
    ).run

    if results.empty?
      puts "No type restrictions added"
    else
      results.each do |filename, file_contents|
        File.write(filename, file_contents)
      end
    end
  end
end
