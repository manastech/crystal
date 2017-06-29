# Implementation of the `crystal tool format` command
#
# This is just the command-line part. The formatter
# logic is in `crystal/tools/formatter.cr`.

class Crystal::Command
  record FormatResult, filename : String, code : Code do
    enum Code
      FORMAT
      SYNTAX
      INVALID_BYTE_SEQUENCE
      BUG
    end
  end

  private def format
    @format = "text"
    excludes = ["lib"] of String
    includes = [] of String
    check = nil

    option_parser =
      OptionParser.parse(options) do |opts|
        opts.banner = "Usage: crystal tool format [options] [file or directory]\n\nOptions:"

        opts.on("--check", "Checks that formatting code produces no changes") do |f|
          check = [] of FormatResult
        end

        opts.on("-f text|json", "--format text|json", "Output format text (default) or json") do |f|
          @format = f
        end

        opts.on("-i <path>", "--include <path>", "Include path") do |f|
          includes << f
        end

        opts.on("-e <path>", "--exclude <path>", "Exclude path (default: lib)") do |f|
          excludes << f
        end

        opts.on("-h", "--help", "Show this message") do
          puts opts
          exit
        end

        opts.on("--no-color", "Disable colored output") do
          @color = false
        end
      end

    files = options
    check_files = check

    if files.size == 1
      file = files.first
      if file == "-"
        return format_stdin(check_files)
      elsif File.file?(file)
        return format_single(file, check_files)
      end
    end

    includes = normalize_paths includes
    excludes = normalize_paths excludes
    excludes = excludes - includes

    if files.empty?
      files = Dir["./**/*.cr"]
    else
      files = normalize_paths files
    end

    format_many files, check_files, excludes

    if check_files
      if check_files.empty?
        exit 0
      else
        check_files.each do |result|
          case result.code
          when .format?
            error "formatting '#{result.filename}' produced changes", exit_code: nil
          when .syntax?
            error "'#{result.filename}' has syntax errors", exit_code: nil
          when .invalid_byte_sequence?
            error "'#{result.filename}' is not a valid Crystal source file", exit_code: nil
          when .bug?
            error "there's a bug formatting '#{result.filename}', please report it including the contents of the file: https://github.com/crystal-lang/crystal/issues", exit_code: nil
          end
        end
        exit 1
      end
    end
  end

  private def normalize_paths(paths)
    path_start = ".#{File::SEPARATOR}"
    paths.map do |path|
      path = path_start + path unless path.starts_with?(path_start)
      path.rstrip(File::SEPARATOR)
    end
  end

  private def format_stdin(check_files)
    source = STDIN.gets_to_end

    begin
      result = Crystal.format(source)
      exit(result == source ? 0 : 1) if check_files

      print result
      STDOUT.flush
    rescue ex : InvalidByteSequenceError
      print "Error: ".colorize.toggle(@color).red.bold
      print "source is not a valid Crystal source file: ".colorize.toggle(@color).bold
      puts ex.message
      exit 1
    rescue ex : Crystal::SyntaxException
      if @format == "json"
        puts ex.to_json
      else
        puts ex
      end
      exit 1
    rescue ex
      couldnt_format "STDIN"
      STDERR.puts
      STDERR.flush
      exit 1
    end
  end

  private def format_single(filename, check_files)
    source = File.read(filename)

    begin
      result = Crystal.format(source, filename: filename)
      exit(result == source ? 0 : 1) if check_files

      File.write(filename, result)
    rescue ex : InvalidByteSequenceError
      print "Error: ".colorize.toggle(@color).red.bold
      print "file '#{Crystal.relative_filename(filename)}' is not a valid Crystal source file: ".colorize.toggle(@color).bold
      puts ex.message
      exit 1
    rescue ex : Crystal::SyntaxException
      if @format == "json"
        puts ex.to_json
      else
        puts ex
      end
      exit 1
    rescue ex
      couldnt_format "'#{filename}'"
      STDERR.puts
      STDERR.flush
      exit 1
    end
  end

  private def format_many(files, check_files, excludes)
    files.each do |filename|
      format_file_or_directory filename, check_files, excludes
    end
  end

  private def format_file_or_directory(filename, check_files, excludes)
    if File.file?(filename)
      unless excludes.any? { |exclude| filename.starts_with?(exclude) }
        format_file filename, check_files
      end
    elsif Dir.exists?(filename)
      filename = filename.chomp('/')
      filenames = Dir["#{filename}/**/*.cr"]
      format_many filenames, check_files, excludes
    else
      error "file or directory does not exist: #{filename}"
    end
  end

  private def format_file(filename, check_files)
    source = File.read(filename)

    begin
      result = Crystal.format(source, filename: filename)
      return if result == source

      if check_files
        check_files << FormatResult.new(filename, FormatResult::Code::FORMAT)
      else
        File.write(filename, result)
        STDOUT << "Format".colorize(:green).toggle(@color) << " " << filename << "\n"
      end
    rescue ex : InvalidByteSequenceError
      if check_files
        check_files << FormatResult.new(filename, FormatResult::Code::INVALID_BYTE_SEQUENCE)
      else
        print "Error: ".colorize.toggle(@color).red.bold
        print "file '#{Crystal.relative_filename(filename)}' is not a valid Crystal source file: ".colorize.toggle(@color).bold
        puts ex.message
      end
    rescue ex : Crystal::SyntaxException
      if check_files
        check_files << FormatResult.new(filename, FormatResult::Code::SYNTAX)
      else
        STDOUT << "Syntax Error:".colorize(:yellow).toggle(@color) << " " << ex.message << " at " << filename << ":" << ex.line_number << ":" << ex.column_number << "\n"
      end
    rescue ex
      if check_files
        check_files << FormatResult.new(filename, FormatResult::Code::BUG)
      else
        couldnt_format "'#{filename}'"
        STDERR.puts
        STDERR.flush
      end
    end
  end

  private def couldnt_format(file)
    STDERR << "Error:".colorize(:red).toggle(@color) << ", " <<
      "couldn't format " << file << ", please report a bug including the contents of it: https://github.com/crystal-lang/crystal/issues"
  end
end
