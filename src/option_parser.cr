# `OptionParser` is a class for command-line options processing. It supports:
#
# * Short and long modifier style options (example: `-h`, `--help`)
# * Passing arguments to the flags (example: `-f filename.txt`)
# * Subcommands
# * Automatic help message generation
#
# Run `crystal` for an example of a CLI built with `OptionParser`.
#
# NOTE: To use `OptionParser`, you must explicitly import it with `require "option_parser"`
#
# Short example:
#
# ```
# require "option_parser"
#
# upcase = false
# destination = "World"
#
# OptionParser.parse do |parser|
#   parser.banner = "Usage: salute [arguments]"
#   parser.on("-u", "--upcase", "Upcases the salute") { upcase = true }
#   parser.on("-t NAME", "--to=NAME", "Specifies the name to salute") { |name| destination = name }
#   parser.on("-h", "--help", "Show this help") do
#     puts parser
#     exit
#   end
#   parser.invalid_option do |flag|
#     STDERR.puts "ERROR: #{flag} is not a valid option."
#     STDERR.puts parser
#     exit(1)
#   end
# end
#
# destination = destination.upcase if upcase
# puts "Hello #{destination}!"
# ```
#
# # Subcommands
#
# `OptionParser` also supports subcommands.
#
# Short example:
#
# ```
# require "option_parser"
#
# verbose = false
# salute = false
# welcome = false
# name = "World"
# parser = OptionParser.new do |parser|
#   parser.banner = "Usage: example [subcommand] [arguments]"
#   parser.on("salute", "Salute a name") do
#     salute = true
#     parser.banner = "Usage: example salute [arguments]"
#     parser.on("-t NAME", "--to=NAME", "Specify the name to salute") { |_name| name = _name }
#   end
#   parser.on("welcome", "Print a greeting message") do
#     welcome = true
#     parser.banner = "Usage: example welcome"
#   end
#   parser.on("-v", "--verbose", "Enabled verbose output") { verbose = true }
#   parser.on("-h", "--help", "Show this help") do
#     puts parser
#     exit
#   end
# end
#
# parser.parse
#
# if salute
#   STDERR.puts "Saluting #{name}" if verbose
#   puts "Hello #{name}"
# elsif welcome
#   STDERR.puts "Welcoming #{name}" if verbose
#   puts "Welcome!"
# else
#   puts parser
#   exit(1)
# end
# ```
class OptionParser
  class Exception < ::Exception
  end

  class InvalidOption < Exception
    def initialize(option)
      super("Invalid option: #{option}")
    end
  end

  class MissingOption < Exception
    def initialize(option)
      super("Missing option: #{option}")
    end
  end

  # :nodoc:
  enum FlagValue
    Required
    Optional
    None
    Boolean
  end

  # :nodoc:
  record Handler,
    value_type : FlagValue,
    block : String ->

  record BoolHandler,
    value_type : FlagValue,
    block : Bool ->

  # Creates a new parser, with its configuration specified in the block,
  # and uses it to parse the passed *args* (defaults to `ARGV`).
  #
  # Refer to `#gnu_optional_args?` for the behaviour of the named parameter.
  def self.parse(args = ARGV, *, gnu_optional_args : Bool = false, &) : self
    parser = OptionParser.new(gnu_optional_args: gnu_optional_args)
    yield parser
    parser.parse(args)
    parser
  end

  # Creates a new parser.
  #
  # Refer to `#gnu_optional_args?` for the behaviour of the named parameter.
  def initialize(*, @gnu_optional_args : Bool = false)
    @flags = [] of String
    @handlers = Hash(String, (Handler | BoolHandler)).new
    @stop = false
    @missing_option = ->(option : String) { raise MissingOption.new(option) }
    @invalid_option = ->(option : String) { raise InvalidOption.new(option) }
  end

  # Creates a new parser, with its configuration specified in the block.
  #
  # Refer to `#gnu_optional_args?` for the behaviour of the named parameter.
  def self.new(*, gnu_optional_args : Bool = false, &)
    new(gnu_optional_args: gnu_optional_args).tap { |parser| yield parser }
  end

  # Returns whether the GNU convention is followed for optional arguments.
  #
  # If true, any optional argument must follow the preceding flag in the same
  # token immediately, without any space inbetween:
  #
  # ```
  # require "option_parser"
  #
  # OptionParser.parse(%w(-a1 -a 2 -a --b=3 --b 4), gnu_optional_args: true) do |parser|
  #   parser.on("-a", "--b [x]", "optional") { |x| p x }
  #   parser.unknown_args { |args, _| puts "Remaining: #{args}" }
  # end
  # ```
  #
  # Prints:
  #
  # ```text
  # "1"
  # ""
  # ""
  # "3"
  # ""
  # Remaining: ["2", "4"]
  # ```
  #
  # Without `gnu_optional_args: true`, prints the following instead:
  #
  # ```text
  # "1"
  # "2"
  # "--b=3"
  # "4"
  # Remaining: []
  # ```
  property? gnu_optional_args : Bool

  # Establishes the initial message for the help printout.
  # Typically, you want to write here the name of your program,
  # and a one-line template of its invocation.
  #
  # Example:
  #
  # ```
  # require "option_parser"
  #
  # parser = OptionParser.new
  # parser.banner = "Usage: crystal [command] [switches] [program file] [--] [arguments]"
  # ```
  setter banner : String?

  # Establishes a handler for a *flag* or subcommand.
  #
  # Flags must start with a dash or double dash. They can also have
  # an optional argument, which will get passed to the block.
  # Each flag has a description, which will be used for the help message.
  #
  # Subcommands are any *flag* passed which does not start with a dash. They
  # cannot take arguments. When a subcommand is parsed, all subcommands are
  # removed from the OptionParser, simulating a "tree" of subcommands. All flags
  # remain valid. For a longer example, see the examples at the top of the page.
  #
  # Examples of valid flags:
  #
  # * `-a`, `-B`
  # * `--something-longer`
  # * `-f FILE`, `--file FILE`, `--file=FILE` (these will yield the passed value to the block as a string)
  # * --no-verbose
  #
  # Examples of valid subcommands:
  #
  # * `foo`, `run`
  def on(flag : String, description : String, &block : String ->)
    append_flag flag, description

    flag, value_type = parse_flag_definition(flag)
    @handlers[flag] = Handler.new(value_type, block)
  end

  # Establishes a handler for boolean flags, e.g.
  # # Choose on or off
  # OptionParser.parse(args) do |opts|
  #   opts.bool("--[no-]verbose", "Run verbosely") do |v|
  #     flag = v
  #   end
  # end
  def bool(flag : String, description : String, &block : Bool ->)
    append_flag flag, description

    flag, value_type = parse_flag_definition(flag)
    @handlers["--#{flag}"] = BoolHandler.new(value_type, block)
    @handlers["--no-#{flag}"] = BoolHandler.new(value_type, block)
  end

  # Establishes a handler for a pair of short and long flags.
  #
  # See the other definition of `on` for examples. This method does not support
  # subcommands.
  def on(short_flag : String, long_flag : String, description : String, &block : String ->)
    check_starts_with_dash short_flag, "short_flag", allow_empty: true
    check_starts_with_dash long_flag, "long_flag"

    append_flag "#{short_flag}, #{long_flag}", description

    short_flag, short_value_type = parse_flag_definition(short_flag)
    long_flag, long_value_type = parse_flag_definition(long_flag)

    # Pick the "most required" argument type between both flags
    if short_value_type.required? || long_value_type.required?
      value_type = FlagValue::Required
    elsif short_value_type.optional? || long_value_type.optional?
      value_type = FlagValue::Optional
    else
      value_type = FlagValue::None
    end

    handler = Handler.new(value_type, block)
    @handlers[short_flag] = @handlers[long_flag] = handler
  end

  # --no-option
  # --[no-]option
  # --option
  # -o
  # --option=value
  # --option value
  private def parse_flag_definition(flag : String)
    case flag
    when /\A--no-    ([^\[\]=\s]*)(.+)?\z/x # e.g. --no-option
      {"--no-#{$1}", FlagValue::Optional}
    when /\A--\[no-\]([^\[\]=\s]*)(.+)?\z/x # e.g. --[no-]option # t|f
      {"#{$1}", FlagValue::Boolean}
    when /\A--       (\S+)\s+\[\S+\]\z/x # e.g. --b [x]
      {"--#{$1}", FlagValue::Optional}
    when /\A--       (\S+)(\s+|\=)(\S+)?\z/x # e.g. --file FILE or --file=FILE
      {"--#{$1}", FlagValue::Required}
    when /\A--       \S+\z/x
      # This can't be merged with `else` otherwise /-(.)/ matches
      {flag, FlagValue::None}
    when /\A-(.)\s*\[\S+\]\z/
      {flag[0..1], FlagValue::Optional}
    when /\A-(.)\s+\S+\z/, /\A-(.)\s+\z/, /\A-(.)\S+\z/
      {flag[0..1], FlagValue::Required}
    else
      # This happens for -f without argument
      {flag, FlagValue::None}
    end
  end

  # Adds a separator, with an optional header message, that will be used to
  # print the help. The separator is placed between the flags registered (`#on`)
  # before, and the flags registered after the call.
  #
  # This way, you can group the different options in an easier to read way.
  def separator(message = "") : Nil
    @flags << message.to_s
  end

  # Sets a handler for regular arguments that didn't match any of the setup options.
  #
  # You typically use this to get the main arguments (not modifiers)
  # that your program expects (for example, filenames). The default behaviour
  # is to do nothing. The arguments can also be extracted from the *args* array
  # passed to `#parse` after parsing.
  def unknown_args(&@unknown_args : Array(String), Array(String) ->)
  end

  # Sets a handler for when a option that expects an argument wasn't given any.
  #
  # You typically use this to display a help message.
  # The default behaviour is to raise `MissingOption`.
  def missing_option(&@missing_option : String ->)
  end

  # Sets a handler for option arguments that didn't match any of the setup options.
  #
  # You typically use this to display a help message.
  # The default behaviour is to raise `InvalidOption`.
  def invalid_option(&@invalid_option : String ->)
  end

  # Sets a handler which runs before each argument is parsed. This callback is
  # not passed flag arguments. For example, `--foo=foo_arg --bar bar_arg` would
  # pass `--foo=foo_arg` and `--bar` to the callback only.
  #
  # You typically use this to implement advanced option parsing behaviour such
  # as treating all options after a filename differently (along with `#stop`).
  def before_each(&@before_each : String ->)
  end

  # Stops the current parse and returns immediately, leaving the remaining flags
  # unparsed. This is treated identically to `--` being inserted *behind* the
  # current parsed flag.
  def stop : Nil
    @stop = true
  end

  # Returns all the setup options, formatted in a help message.
  def to_s(io : IO) : Nil
    if banner = @banner
      io << banner
      io << '\n'
    end
    @flags.join io, '\n'
  end

  private def append_flag(flag, description)
    indent = " " * 37
    description = description.gsub("\n", "\n#{indent}")
    if flag.size >= 33
      @flags << "    #{flag}\n#{indent}#{description}"
    else
      @flags << "    #{flag}#{" " * (33 - flag.size)}#{description}"
    end
  end

  private def check_starts_with_dash(arg, name, allow_empty = false)
    return if allow_empty && arg.empty?

    unless arg.starts_with?('-')
      raise ArgumentError.new("Argument '#{name}' (#{arg.inspect}) must start with a dash (-)")
    end
  end

  private def with_preserved_state(&)
    old_flags = @flags.clone
    old_handlers = @handlers.clone
    old_banner = @banner
    old_unknown_args = @unknown_args
    old_missing_option = @missing_option
    old_invalid_option = @invalid_option
    old_before_each = @before_each

    begin
      yield
    ensure
      @flags = old_flags
      @handlers = old_handlers
      @stop = false
      @banner = old_banner
      @unknown_args = old_unknown_args
      @missing_option = old_missing_option
      @invalid_option = old_invalid_option
      @before_each = old_before_each
    end
  end

  # Parses the passed *args* (defaults to `ARGV`), running the handlers associated to each option.
  def parse(args = ARGV) : Nil
    with_preserved_state do
      # List of indexes in `args` which have been handled and must be deleted
      handled_args = [] of Int32
      double_dash_index = nil

      arg_index = 0
      while arg_index < args.size
        arg = args[arg_index]

        if @stop
          double_dash_index = arg_index - 1
          @stop = false
          break
        end

        if before_each = @before_each
          before_each.call(arg)
        end

        # -- means to stop parsing arguments
        if arg == "--"
          double_dash_index = arg_index
          handled_args << arg_index
          break
        end

        if arg.starts_with?("--")
          value_index = arg.index('=')
          if value_index
            flag = arg[0...value_index]
            value = arg[value_index + 1..-1]
          else
            flag = arg
            value = nil
          end
        elsif arg.starts_with?('-')
          if arg.size > 2
            flag = arg[0..1]
            value = arg[2..-1]
          else
            flag = arg
            value = nil
          end
        else
          flag = arg
          value = nil
        end

        # Fetch handler of the flag.
        # If value is given even though handler does not take value, it is invalid, then it is skipped.
        if (handler = @handlers[flag]?) && !(handler.value_type.none? && value)
          handled_args << arg_index

          if !value
            case handler.value_type
            in FlagValue::Required
              value = args[arg_index + 1]?
              if value
                handled_args << arg_index + 1
                arg_index += 1
              else
                @missing_option.call(flag)
              end
            in FlagValue::Optional
              unless gnu_optional_args?
                value = args[arg_index + 1]?
                if value && !@handlers.has_key?(value)
                  handled_args << arg_index + 1
                  arg_index += 1
                else
                  value = nil
                end
              end
            in FlagValue::None
              # do nothing
            in FlagValue::Boolean
              # call the block here and ignore booleans later
              if handler.is_a?(BoolHandler)
                handler.block.call !flag.starts_with?("--no-")
              end
            end
          end

          # If this is a subcommand (flag not starting with -), delete all
          # subcommands since they are no longer valid.
          unless flag.starts_with?('-')
            @handlers.select! { |k, _| k.starts_with?('-') }
            @flags.select!(&.starts_with?("    -"))
          end

          if handler.is_a?(Handler)
            handler.block.call(value || "")
          end
        end

        arg_index += 1
      end

      # We're about to delete all the unhandled arguments in args so double_dash_index
      # is about to change. Arguments are only handled before "--", so we're deleting
      # nothing after "--", which means it's index is decremented by handled_args.size.
      # But actually we also added "--" itself to handled_args so we change it's index
      # by one less.
      if double_dash_index
        double_dash_index -= handled_args.size - 1
      end

      # After argument parsing, delete handled arguments from args.
      # We reverse so that we delete args from
      handled_args.reverse!
      i = 0
      args.reject! do
        # handled_args is sorted in reverse so we know that i <= handled_args.last
        handled = i == handled_args.last?

        # Maintain the i <= handled_args.last invariant
        handled_args.pop if handled

        i += 1

        handled
      end

      # Since we've deleted all handled arguments, `args` is all unknown arguments
      # which we split by the index of any double dash argument
      if unknown_args = @unknown_args
        if double_dash_index
          before_dash = args[0...double_dash_index]
          after_dash = args[double_dash_index..-1]
        else
          before_dash = args
          after_dash = [] of String
        end
        unknown_args.call(before_dash, after_dash)
      end

      # We consider any remaining arguments which start with '-' to be invalid
      args.each_with_index do |arg, index|
        break if double_dash_index && index >= double_dash_index

        if arg.starts_with?('-') && arg != "-"
          @invalid_option.call(arg)
        end
      end
    end
  end
end
