# Implementation of the `crystal docs` command
#
# This is just the command-line part. Everything else
# is in `crystal/tools/doc/`

class Crystal::Command
  private VALID_OUTPUT_FORMATS = %w(html json)

  private def docs
    output_format = "html"
    output_directory = File.join(".", "docs")
    sitemap_base_url = nil
    sitemap_priority = "1.0"
    sitemap_changefreq = "never"
    project_info = Doc::ProjectInfo.new

    compiler = new_compiler

    OptionParser.parse(@options) do |opts|
      opts.banner = <<-'BANNER'
        Usage: crystal docs [options]

        Generates API documentation from inline docstrings in all Crystal files inside ./src directory.

        Options:
        BANNER

      opts.on("--project-name=NAME", "Set project name") do |value|
        project_info.name = value
      end

      opts.on("--project-version=VERSION", "Set project version") do |value|
        project_info.version = value
      end

      opts.on("--source-refname=REFNAME", "Set source refname (e.g. git tag, commit hash)") do |value|
        project_info.refname = value
      end

      opts.on("--source-url-pattern=REFNAME", "Set URL pattern for source code links") do |value|
        project_info.source_url_pattern = value
      end

      opts.on("--output=DIR", "-o DIR", "Set the output directory (default: #{output_directory})") do |value|
        output_directory = value
      end
      opts.on("--format=FORMAT", "-f FORMAT", "Set the output format [#{VALID_OUTPUT_FORMATS.join(", ")}] (default: #{output_format})") do |value|
        if !VALID_OUTPUT_FORMATS.includes? value
          STDERR.puts "Invalid format '#{value}'"
          abort opts
        end
        output_format = value
      end

      opts.on("--json-config-url=URL", "Set the URL pointing to a config file (used for discovering versions)") do |value|
        project_info.json_config_url = value
      end

      opts.on("--canonical-base-url=URL", %(Indicate the preferred URL with rel="canonical" link element)) do |value|
        project_info.canonical_base_url = value
      end

      opts.on("--sitemap-base-url=URL", "-b URL", "Set the sitemap base URL and generates sitemap") do |value|
        sitemap_base_url = value
      end

      opts.on("--sitemap-priority=PRIO", "Set the sitemap priority (default: 1.0)") do |value|
        sitemap_priority = value
      end

      opts.on("--sitemap-changefreq=FREQ", "Set the sitemap changefreq (default: never)") do |value|
        sitemap_changefreq = value
      end

      opts.on("-D FLAG", "--define FLAG", "Define a compile-time flag") do |flag|
        compiler.flags << flag
      end

      opts.on("--error-trace", "Show full error trace") do
        compiler.show_error_trace = true
      end

      opts.on("--no-color", "Disable colored output") do
        @color = false
        compiler.color = false
      end

      opts.on("--prelude ", "Use given file as prelude") do |prelude|
        compiler.prelude = prelude
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

      opts.on("-h", "--help", "Show this message") do
        puts opts
        exit
      end

      setup_compiler_warning_options(opts, compiler)
    end

    project_info.fill_with_defaults

    unless project_info.name?
      STDERR.puts "Couldn't determine name from shard.yml, please provide --project-name option"
    end

    unless project_info.version?
      STDERR.puts "Couldn't determine version from git or shard.yml, please provide --project-version option"
    end

    if Crystal::Doc::MarkdDocRenderer::SANITIZER.nil?
      STDERR.puts "Crystal built without LibXML2 support, documentation sanitization disabled"
    end

    unless project_info.name? && project_info.version?
      abort
    end

    if options.empty?
      sources = [Compiler::Source.new("require", %(require "./src/**"))]
      included_dirs = [] of String
    else
      filenames = options
      sources = gather_sources(filenames)
      included_dirs = sources.map { |source| File.dirname(source.filename) }
    end

    included_dirs << File.expand_path("./src")

    compiler.flags << "docs"
    compiler.wants_doc = true
    result = compiler.top_level_semantic sources

    Doc::Generator.new(result.program, included_dirs, output_directory, output_format, sitemap_base_url, sitemap_priority, sitemap_changefreq, project_info).run

    report_warnings
    exit 1 if warnings_fail_on_exit?
  end
end
