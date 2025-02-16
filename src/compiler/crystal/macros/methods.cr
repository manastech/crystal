require "../semantic/ast"
require "./macros"
require "semantic_version"

module Crystal
  class MacroInterpreter
    private def find_source_file(filename, &)
      # Support absolute paths
      if filename.starts_with?('/')
        filename = "#{filename}.cr" unless filename.ends_with?(".cr")

        if File.exists?(filename)
          unless File.file?(filename)
            return yield "#{filename.inspect} is not a file"
          end
        else
          return yield "can't find file #{filename.inspect}"
        end
      else
        begin
          relative_to = @location.try &.original_filename
          found_filenames = @program.find_in_path(filename, relative_to)
        rescue ex
          return yield ex.message
        end

        unless found_filenames
          return yield "can't find file #{filename.inspect}"
        end

        if found_filenames.size > 1
          return yield "#{filename.inspect} is a directory"
        end

        filename = found_filenames.first
      end
      filename
    end

    delegate warnings, to: @program

    def interpret_top_level_call(node)
      interpret_top_level_call?(node) ||
        node.raise("undefined macro method: '#{node.name}'")
    end

    def interpret_top_level_call?(node)
      # Please order method names in lexicographical order
      case node.name
      when "compare_versions"
        interpret_compare_versions(node)
      when "debug"
        interpret_debug(node)
      when "env"
        interpret_env(node)
      when "flag?", "host_flag?"
        interpret_flag?(node)
      when "parse_type"
        interpret_parse_type(node)
      when "puts"
        interpret_puts(node)
      when "print"
        interpret_print(node)
      when "p", "pp"
        interpret_p(node)
      when "p!", "pp!"
        interpret_pp!(node)
      when "skip_file"
        interpret_skip_file(node)
      when "system", "`"
        interpret_system(node)
      when "raise"
        interpret_raise(node)
      when "warning"
        interpret_warning(node)
      when "file_exists?"
        interpret_file_exists?(node)
      when "read_file"
        interpret_read_file(node)
      when "read_file?"
        interpret_read_file(node, nilable: true)
      when "run"
        interpret_run(node)
      else
        nil
      end
    end

    def interpret_compare_versions(node)
      interpret_check_args_toplevel do |first_arg, second_arg|
        first = accept first_arg
        first_string = first.to_string("first argument to 'compare_versions'")

        second = accept second_arg
        second_string = second.to_string("second argument to 'compare_versions'")

        first_version = begin
          SemanticVersion.parse(first_string)
        rescue ex
          first_arg.raise ex.message
        end

        second_version = begin
          SemanticVersion.parse(second_string)
        rescue ex
          second_arg.raise ex.message
        end

        @last = NumberLiteral.new(first_version <=> second_version)
      end
    end

    def interpret_debug(node)
      if node.args.size >= 1
        node.args.first.accept self
        format = @last.truthy?
      elsif named_args = node.named_args
        format_arg = named_args.find { |arg| arg.name == "format" }
        if format_arg
          format_arg.value.accept self
          format = @last.truthy?
        end
      else
        format = true
      end

      if format
        begin
          @program.stdout.puts Crystal::Formatter.format(@str.to_s)
        rescue
          @program.stdout.puts @str
        end
      else
        @program.stdout.puts @str
      end

      @last = Nop.new
    end

    def interpret_env(node)
      interpret_check_args_toplevel do |arg|
        arg.accept self
        cmd = @last.to_macro_id
        env_value = ENV[cmd]?
        @last = env_value ? StringLiteral.new(env_value) : NilLiteral.new
      end
    end

    def interpret_flag?(node)
      interpret_check_args_toplevel do |arg|
        arg.accept self
        flag_name = @last.to_macro_id
        flags = case node.name
                when "flag?"
                  @program.flags
                when "host_flag?"
                  @program.host_flags
                else
                  raise "Bug: unexpected macro method #{node.name}"
                end
        @last = BoolLiteral.new(flags.includes?(flag_name))
      end
    end

    def interpret_parse_type(node)
      interpret_check_args_toplevel do |arg|
        arg.accept self
        type_name = case last = @last
                    when StringLiteral then last.value
                    else
                      arg.raise "argument to parse_type must be a StringLiteral, not #{last.class_desc}"
                    end

        arg.raise "argument to parse_type cannot be an empty value" if type_name.blank?

        begin
          parser = @program.new_parser type_name
          parser.next_token
          type = parser.parse_bare_proc_type
          parser.check :EOF
          @last = type
        rescue ex : Crystal::SyntaxException
          arg.raise "Invalid type name: #{type_name.inspect}"
        end
      end
    end

    def interpret_puts(node)
      node.args.each do |arg|
        arg.accept self
        last = @last

        # The only difference in macro land between `p` and `puts` is that
        # `puts` with a string literal shouldn't show the string quotes
        last = last.value if last.is_a?(StringLiteral)

        @program.stdout.puts last
      end

      @last = Nop.new
    end

    def interpret_print(node)
      node.args.each do |arg|
        arg.accept self
        last = @last
        last = last.value if last.is_a?(StringLiteral)

        @program.stdout.print last
      end

      @last = Nop.new
    end

    def interpret_p(node)
      node.args.each do |arg|
        arg.accept self
        @program.stdout.puts @last
      end

      @last = Nop.new
    end

    def interpret_pp!(node)
      strings = [] of {String, String}

      node.args.each do |arg|
        arg.accept self
        strings.push({arg.to_s, @last.to_s})
      end

      max_size = strings.max_of &.[0].size
      strings.each do |left, right|
        @program.stdout.puts "#{left.ljust(max_size)} # => #{right}"
      end

      @last = Nop.new
    end

    def interpret_skip_file(node)
      raise SkipMacroException.new(@str.to_s, macro_expansion_pragmas)
    end

    def interpret_system(node)
      cmd = node.args.map do |arg|
        arg.accept self
        @last.to_macro_id
      end
      cmd = cmd.join " "

      begin
        result = `#{cmd}`
      rescue exc : File::Error | IO::Error
        # Taking the os_error message to avoid duplicating the "error executing process: "
        # prefix of the error message and ensure uniqueness between all error messages.
        node.raise "error executing command: #{cmd}: #{exc.os_error.try(&.message) || exc.message}"
      rescue exc
        node.raise "error executing command: #{cmd}: #{exc.message}"
      end

      if $?.success?
        @last = MacroId.new(result)
      elsif result.empty?
        node.raise "error executing command: #{cmd}, got exit status #{$?}"
      else
        node.raise "error executing command: #{cmd}, got exit status #{$?}:\n\n#{result}\n"
      end
    end

    def interpret_raise(node)
      macro_raise(node, node.args, self, Crystal::TopLevelMacroRaiseException)
    end

    def interpret_warning(node)
      macro_warning(node, node.args, self)
    end

    def interpret_file_exists?(node)
      interpret_check_args_toplevel do |arg|
        arg.accept self
        filename = @last.to_macro_id

        @last = BoolLiteral.new(File.exists?(filename))
      end
    end

    def interpret_read_file(node, nilable = false)
      interpret_check_args_toplevel do |arg|
        arg.accept self
        filename = @last.to_macro_id

        begin
          @last = StringLiteral.new(File.read(filename))
        rescue ex
          node.raise ex.to_s unless nilable
          @last = NilLiteral.new
        end
      end
    end

    def interpret_run(node)
      if node.args.size == 0
        node.wrong_number_of_arguments "macro '::run'", 0, "1+"
      end

      node.args.first.accept self
      original_filename = @last.to_macro_id

      filename = find_source_file(original_filename) do |error_message|
        node.raise "error executing macro 'run': #{error_message}"
      end

      run_args = [] of String
      node.args.each_with_index do |arg, i|
        next if i == 0

        arg.accept self
        run_args << @last.to_macro_id
      end

      result = @program.macro_run(filename, run_args)
      if result.status.success?
        @last = MacroId.new(result.stdout)
      else
        command = "#{Process.quote(original_filename)} #{Process.quote(run_args)}"

        message = IO::Memory.new
        message << "Error executing run (exit code: #{result.status}): #{command}\n"

        if result.stdout.empty? && result.stderr.empty?
          message << "\nGot no output."
        else
          Colorize.reset(message)

          unless result.stdout.empty?
            message.puts
            message << "stdout:".colorize.mode(:bold)
            message.puts
            message.puts
            result.stdout.each_line do |line|
              message << "    "
              message << line
              message << '\n'
            end
            message << '\n'
          end

          unless result.stderr.empty?
            message.puts
            message << "stderr:".colorize.mode(:bold)
            message.puts
            message.puts
            result.stderr.each_line do |line|
              message << "    "
              message << line
              message << '\n'
            end
            message << '\n'
          end
        end

        node.raise message.to_s
      end
    end
  end

  class ASTNode
    def to_macro_id
      to_s
    end

    def to_string(context)
      case self
      when StringLiteral then self.value
      when SymbolLiteral then self.value
      when MacroId       then self.value
      else
        raise "expected #{context} to be a StringLiteral, SymbolLiteral or MacroId, not #{class_desc}"
      end
    end

    def truthy?
      case self
      when NilLiteral, Nop
        false
      when BoolLiteral
        self.value
      else
        true
      end
    end

    def interpret(method : String, args : Array(ASTNode), named_args : Hash(String, ASTNode)?, block : Crystal::Block?, interpreter : Crystal::MacroInterpreter, name_loc : Location?)
      case method
      when "id"
        interpret_check_args { MacroId.new(to_macro_id) }
      when "stringify"
        interpret_check_args { stringify }
      when "symbolize"
        interpret_check_args { symbolize }
      when "class_name"
        interpret_check_args { class_name }
      when "doc"
        interpret_check_args do
          StringLiteral.new self.doc || ""
        end
      when "doc_comment"
        interpret_check_args do
          MacroId.new (self.doc || "").gsub("\n", "\n# ")
        end
      when "raise"
        macro_raise self, args, interpreter, Crystal::MacroRaiseException
      when "warning"
        macro_warning self, args, interpreter
      when "filename"
        interpret_check_args do
          filename = location.try &.original_filename
          filename ? StringLiteral.new(filename) : NilLiteral.new
        end
      when "line_number"
        interpret_check_args do
          line_number = location.try &.expanded_location.try &.line_number
          line_number ? NumberLiteral.new(line_number) : NilLiteral.new
        end
      when "column_number"
        interpret_check_args do
          column_number = location.try &.expanded_location.try &.column_number
          column_number ? NumberLiteral.new(column_number) : NilLiteral.new
        end
      when "end_line_number"
        interpret_check_args do
          line_number = end_location.try &.expanded_location.try &.line_number
          line_number ? NumberLiteral.new(line_number) : NilLiteral.new
        end
      when "end_column_number"
        interpret_check_args do
          column_number = end_location.try &.expanded_location.try &.column_number
          column_number ? NumberLiteral.new(column_number) : NilLiteral.new
        end
      when "=="
        interpret_check_args do |arg|
          BoolLiteral.new(self == arg)
        end
      when "!="
        interpret_check_args do |arg|
          BoolLiteral.new(self != arg)
        end
      when "!"
        interpret_check_args { BoolLiteral.new(!truthy?) }
      when "nil?"
        interpret_check_args { BoolLiteral.new(is_a?(NilLiteral) || is_a?(Nop)) }
      else
        raise "undefined macro method '#{class_desc}##{method}'", exception_type: Crystal::UndefinedMacroMethodError
      end
    end

    def interpret_compare(other)
      raise "can't compare #{self} to #{other}"
    end

    def stringify
      StringLiteral.new(to_s)
    end

    def symbolize
      SymbolLiteral.new(to_s)
    end

    def class_name
      StringLiteral.new(class_desc)
    end
  end

  class NilLiteral
    def to_macro_id
      "nil"
    end
  end

  class BoolLiteral
    def to_macro_id
      @value ? "true" : "false"
    end
  end

  class NumberLiteral
    def interpret(method : String, args : Array(ASTNode), named_args : Hash(String, ASTNode)?, block : Crystal::Block?, interpreter : Crystal::MacroInterpreter, name_loc : Location?)
      case method
      when ">"
        bool_bin_op(method, args, named_args, block) { |me, other| me > other }
      when ">="
        bool_bin_op(method, args, named_args, block) { |me, other| me >= other }
      when "<"
        bool_bin_op(method, args, named_args, block) { |me, other| me < other }
      when "<="
        bool_bin_op(method, args, named_args, block) { |me, other| me <= other }
      when "<=>"
        num_bin_op(method, args, named_args, block) do |me, other|
          (me <=> other) || (return NilLiteral.new)
        end
      when "+"
        interpret_check_args(min_count: 0) do |other|
          if other
            raise "can't #{method} with #{other}" unless other.is_a?(NumberLiteral)
            NumberLiteral.new(to_number + other.to_number)
          else
            self
          end
        end
      when "-"
        interpret_check_args(min_count: 0) do |other|
          if other
            raise "can't #{method} with #{other}" unless other.is_a?(NumberLiteral)
            NumberLiteral.new(to_number - other.to_number)
          else
            num = to_number
            raise "undefined method '-' for unsigned integer literal: #{self}" if num.is_a?(Int::Unsigned)
            NumberLiteral.new(-num)
          end
        end
      when "*"
        num_bin_op(method, args, named_args, block) { |me, other| me * other }
      when "/"
        num_bin_op(method, args, named_args, block) { |me, other| me / other }
      when "//"
        num_bin_op(method, args, named_args, block) { |me, other| me // other }
      when "**"
        num_bin_op(method, args, named_args, block) { |me, other| me ** other }
      when "%"
        int_bin_op(method, args, named_args, block) { |me, other| me % other }
      when "&"
        int_bin_op(method, args, named_args, block) { |me, other| me & other }
      when "|"
        int_bin_op(method, args, named_args, block) { |me, other| me | other }
      when "^"
        int_bin_op(method, args, named_args, block) { |me, other| me ^ other }
      when "<<"
        int_bin_op(method, args, named_args, block) { |me, other| me << other }
      when ">>"
        int_bin_op(method, args, named_args, block) { |me, other| me >> other }
      when "~"
        interpret_check_args do
          num = to_number
          raise "undefined method '~' for float literal: #{self}" unless num.is_a?(Int)
          NumberLiteral.new(~num)
        end
      when "kind"
        interpret_check_args { SymbolLiteral.new(kind.to_s) }
      when "to_number"
        interpret_check_args { MacroId.new(to_number.to_s) }
      when "zero?"
        interpret_check_args { BoolLiteral.new(zero?) }
      else
        super
      end
    end

    def interpret_compare(other : NumberLiteral)
      to_number <=> other.to_number
    end

    def bool_bin_op(method, args, named_args, block, &)
      interpret_check_args do |other|
        raise "can't #{method} with #{other}" unless other.is_a?(NumberLiteral)
        BoolLiteral.new(yield to_number, other.to_number)
      end
    end

    def num_bin_op(method, args, named_args, block, &)
      interpret_check_args do |other|
        raise "can't #{method} with #{other}" unless other.is_a?(NumberLiteral)
        NumberLiteral.new(yield to_number, other.to_number)
      end
    end

    def int_bin_op(method, args, named_args, block, &)
      interpret_check_args do |other|
        raise "can't #{method} with #{other}" unless other.is_a?(NumberLiteral)
        me = to_number
        other = other.to_number

        case {me, other}
        when {Int, Int}
          NumberLiteral.new(yield me, other)
        when {Float, _}
          raise "undefined method '#{method}' for float literal: #{self}"
        else
          raise "argument to NumberLiteral##{method} can't be float literal: #{self}"
        end
      end
    end

    def to_number
      case @kind
      in .i8?   then @value.to_i8
      in .i16?  then @value.to_i16
      in .i32?  then @value.to_i32
      in .i64?  then @value.to_i64
      in .i128? then @value.to_i128
      in .u8?   then @value.to_u8
      in .u16?  then @value.to_u16
      in .u32?  then @value.to_u32
      in .u64?  then @value.to_u64
      in .u128? then @value.to_u128
      in .f32?  then @value.to_f32
      in .f64?  then @value.to_f64
      end
    end
  end

  class CharLiteral
    def to_macro_id
      @value.to_s
    end

    def interpret(method : String, args : Array(ASTNode), named_args : Hash(String, ASTNode)?, block : Crystal::Block?, interpreter : Crystal::MacroInterpreter, name_loc : Location?)
      case method
      when "ord"
        interpret_check_args { NumberLiteral.new(ord) }
      else
        super
      end
    end

    def ord
      @value.ord
    end
  end

  class StringLiteral
    def interpret(method : String, args : Array(ASTNode), named_args : Hash(String, ASTNode)?, block : Crystal::Block?, interpreter : Crystal::MacroInterpreter, name_loc : Location?)
      case method
      when "==", "!="
        interpret_check_args do |arg|
          case arg
          when MacroId
            if method == "=="
              BoolLiteral.new(@value == arg.value)
            else
              BoolLiteral.new(@value != arg.value)
            end
          else
            super
          end
        end
      when "[]"
        interpret_check_args do |arg|
          case arg
          when RangeLiteral
            range = arg.interpret_to_nilable_range(interpreter)
            StringLiteral.new(@value[range])
          else
            raise "wrong argument for StringLiteral#[] (#{arg.class_desc}): #{arg}"
          end
        end
      when "=~"
        interpret_check_args do |arg|
          case arg
          when RegexLiteral
            regex = regex_value(arg)
            BoolLiteral.new(!!(@value =~ regex))
          else
            BoolLiteral.new(false)
          end
        end
      when ">"
        interpret_check_args do |arg|
          case arg
          when StringLiteral, MacroId
            return BoolLiteral.new(interpret_compare(arg) > 0)
          else
            raise "Can't compare StringLiteral with #{arg.class_desc}"
          end
        end
      when "<"
        interpret_check_args do |arg|
          case arg
          when StringLiteral, MacroId
            return BoolLiteral.new(interpret_compare(arg) < 0)
          else
            raise "Can't compare StringLiteral with #{arg.class_desc}"
          end
        end
      when "+"
        interpret_check_args do |arg|
          case arg
          when CharLiteral
            piece = arg.value
          when StringLiteral
            piece = arg.value
          else
            raise "StringLiteral#+ expects char or string, not #{arg.class_desc}"
          end
          StringLiteral.new(@value + piece)
        end
      when "camelcase"
        interpret_check_args(named_params: ["lower"]) do
          lower = if named_args && (lower_arg = named_args["lower"]?)
                    lower_arg
                  else
                    BoolLiteral.new false
                  end

          raise "named argument 'lower' to StringLiteral#camelcase must be a bool, not #{lower.class_desc}" unless lower.is_a?(BoolLiteral)

          StringLiteral.new(@value.camelcase(lower: lower.value))
        end
      when "capitalize"
        interpret_check_args { StringLiteral.new(@value.capitalize) }
      when "chars"
        interpret_check_args { ArrayLiteral.map(@value.chars, Path.global("Char")) { |value| CharLiteral.new(value) } }
      when "chomp"
        interpret_check_args { StringLiteral.new(@value.chomp) }
      when "downcase"
        interpret_check_args { StringLiteral.new(@value.downcase) }
      when "empty?"
        interpret_check_args { BoolLiteral.new(@value.empty?) }
      when "ends_with?"
        interpret_check_args do |arg|
          case arg
          when CharLiteral
            piece = arg.value
          when StringLiteral
            piece = arg.value
          else
            raise "StringLiteral#ends_with? expects char or string, not #{arg.class_desc}"
          end
          BoolLiteral.new(@value.ends_with?(piece))
        end
      when "gsub"
        interpret_check_args do |first, second|
          raise "first argument to StringLiteral#gsub must be a regex, not #{first.class_desc}" unless first.is_a?(RegexLiteral)
          raise "second argument to StringLiteral#gsub must be a string, not #{second.class_desc}" unless second.is_a?(StringLiteral)

          regex = regex_value(first)

          StringLiteral.new(value.gsub(regex, second.value))
        end
      when "identify"
        interpret_check_args { StringLiteral.new(@value.tr(":", "_")) }
      when "includes?"
        interpret_check_args do |arg|
          case arg
          when CharLiteral
            piece = arg.value
          when StringLiteral
            piece = arg.value
          else
            raise "StringLiteral#includes? expects char or string, not #{arg.class_desc}"
          end
          BoolLiteral.new(@value.includes?(piece))
        end
      when "scan"
        interpret_check_args do |arg|
          unless arg.is_a?(RegexLiteral)
            raise "StringLiteral#scan expects a regex, not #{arg.class_desc}"
          end

          regex = regex_value(arg)

          matches = ArrayLiteral.new(
            of: Generic.new(
              Path.global("Hash"),
              [
                Union.new([Path.global("Int32"), Path.global("String")] of ASTNode),
                Union.new([Path.global("String"), Path.global("Nil")] of ASTNode),
              ] of ASTNode
            )
          )

          @value.scan(regex) do |match_data|
            captures = HashLiteral.new(
              of: HashLiteral::Entry.new(
                Union.new([Path.global("Int32"), Path.global("String")] of ASTNode),
                Union.new([Path.global("String"), Path.global("Nil")] of ASTNode),
              )
            )

            match_data.to_h.each do |capture, substr|
              case capture
              in Int32
                key = NumberLiteral.new(capture)
              in String
                key = StringLiteral.new(capture)
              end

              case substr
              in String
                value = StringLiteral.new(substr)
              in Nil
                value = NilLiteral.new
              end

              captures.entries << HashLiteral::Entry.new(key, value)
            end

            matches.elements << captures
          end

          matches
        end
      when "size"
        interpret_check_args { NumberLiteral.new(@value.size) }
      when "lines"
        interpret_check_args { ArrayLiteral.map(@value.lines, Path.global("String")) { |value| StringLiteral.new(value) } }
      when "split"
        interpret_check_args(min_count: 0) do |arg|
          if arg
            case arg
            when CharLiteral
              splitter = arg.value
            when StringLiteral
              splitter = arg.value
            else
              splitter = arg.to_s
            end

            ArrayLiteral.map(@value.split(splitter), Path.global("String")) { |value| StringLiteral.new(value) }
          else
            ArrayLiteral.map(@value.split, Path.global("String")) { |value| StringLiteral.new(value) }
          end
        end
      when "count"
        interpret_check_args do |arg|
          case arg
          when CharLiteral
            chr = arg.value
          else
            raise "StringLiteral#count expects char, not #{arg.class_desc}"
          end
          NumberLiteral.new(@value.count(chr))
        end
      when "starts_with?"
        interpret_check_args do |arg|
          case arg
          when CharLiteral
            piece = arg.value
          when StringLiteral
            piece = arg.value
          else
            raise "StringLiteral#starts_with? expects char or string, not #{arg.class_desc}"
          end
          BoolLiteral.new(@value.starts_with?(piece))
        end
      when "strip"
        interpret_check_args { StringLiteral.new(@value.strip) }
      when "titleize"
        interpret_check_args { StringLiteral.new(@value.titleize) }
      when "to_i"
        value = interpret_check_args(min_count: 0) do |base|
          if base
            raise "argument to StringLiteral#to_i must be a number, not #{base.class_desc}" unless base.is_a?(NumberLiteral)
            @value.to_i64?(base.to_number.to_i)
          else
            @value.to_i64?
          end
        end

        if value
          NumberLiteral.new(value.to_s, :i32)
        else
          raise "StringLiteral#to_i: #{@value} is not an integer"
        end
      when "to_utf16"
        interpret_check_args do
          slice = @value.to_utf16

          # include the trailing zero that isn't counted in the slice but was
          # generated by String#to_utf16 so the literal can be passed to C
          # functions that expect a null terminated UInt16*
          args = Slice(UInt16).new(slice.to_unsafe, slice.size + 1).to_a do |codepoint|
            NumberLiteral.new(codepoint).as(ASTNode)
          end
          literal_node = Call.new(Generic.new(Path.global("Slice"), [Path.global("UInt16")] of ASTNode), "literal", args)

          # but keep the trailing zero hidden in the exposed slice
          Call.new(literal_node, "[]", [NumberLiteral.new("0", :i32), NumberLiteral.new(slice.size)] of ASTNode)
        end
      when "tr"
        interpret_check_args do |first, second|
          raise "first argument to StringLiteral#tr must be a string, not #{first.class_desc}" unless first.is_a?(StringLiteral)
          raise "second argument to StringLiteral#tr must be a string, not #{second.class_desc}" unless second.is_a?(StringLiteral)

          StringLiteral.new(@value.tr(first.value, second.value))
        end
      when "underscore"
        interpret_check_args { StringLiteral.new(@value.underscore) }
      when "upcase"
        interpret_check_args { StringLiteral.new(@value.upcase) }
      else
        super
      end
    end

    def interpret_compare(other : StringLiteral | MacroId)
      value <=> other.value
    end

    def to_macro_id
      @value
    end

    def regex_value(arg)
      regex_value = arg.value
      if regex_value.is_a?(StringLiteral)
        Regex.new(regex_value.value, arg.options)
      else
        raise "regex interpolations not yet allowed in macros"
      end
    end
  end

  class StringInterpolation
    def interpret(method : String, args : Array(ASTNode), named_args : Hash(String, ASTNode)?, block : Crystal::Block?, interpreter : Crystal::MacroInterpreter, name_loc : Location?)
      case method
      when "expressions"
        interpret_check_args { ArrayLiteral.map(expressions, &.itself) }
      else
        super
      end
    end
  end

  class ArrayLiteral
    def interpret(method : String, args : Array(ASTNode), named_args : Hash(String, ASTNode)?, block : Crystal::Block?, interpreter : Crystal::MacroInterpreter, name_loc : Location?)
      case method
      when "of"
        interpret_check_args { @of || Nop.new }
      when "type"
        interpret_check_args { @name || Nop.new }
      when "clear"
        interpret_check_args do
          elements.clear
          self
        end
      else
        value = interpret_array_or_tuple_method(self, ArrayLiteral, method, args, named_args, block, interpreter)
        value || super
      end
    end
  end

  class HashLiteral
    def interpret(method : String, args : Array(ASTNode), named_args : Hash(String, ASTNode)?, block : Crystal::Block?, interpreter : Crystal::MacroInterpreter, name_loc : Location?)
      case method
      when "empty?"
        interpret_check_args { BoolLiteral.new(entries.empty?) }
      when "keys"
        interpret_check_args { ArrayLiteral.map entries, &.key }
      when "size"
        interpret_check_args { NumberLiteral.new(entries.size) }
      when "to_a"
        interpret_check_args do
          ArrayLiteral.map(entries) { |entry| TupleLiteral.new([entry.key, entry.value] of ASTNode) }
        end
      when "values"
        interpret_check_args { ArrayLiteral.map entries, &.value }
      when "each"
        interpret_check_args(uses_block: true) do
          block_arg_key = block.args[0]?
          block_arg_value = block.args[1]?

          entries.each do |entry|
            interpreter.define_var(block_arg_key.name, entry.key) if block_arg_key
            interpreter.define_var(block_arg_value.name, entry.value) if block_arg_value
            interpreter.accept block.body
          end

          NilLiteral.new
        end
      when "map"
        interpret_check_args(uses_block: true) do
          block_arg_key = block.args[0]?
          block_arg_value = block.args[1]?

          ArrayLiteral.map(entries) do |entry|
            interpreter.define_var(block_arg_key.name, entry.key) if block_arg_key
            interpreter.define_var(block_arg_value.name, entry.value) if block_arg_value
            interpreter.accept block.body
          end
        end
      when "double_splat"
        interpret_check_args(min_count: 0) do |arg|
          if arg
            unless arg.is_a?(Crystal::StringLiteral)
              arg.raise "argument to double_splat must be a StringLiteral, not #{arg.class_desc}"
            end

            if entries.empty?
              to_double_splat
            else
              to_double_splat(arg.value)
            end
          else
            to_double_splat
          end
        end
      when "[]"
        interpret_check_args do |key|
          entry = entries.find &.key.==(key)
          entry.try(&.value) || NilLiteral.new
        end
      when "[]="
        interpret_check_args do |key, value|
          index = entries.index &.key.==(key)
          if index
            entries[index] = HashLiteral::Entry.new(key, value)
          else
            entries << HashLiteral::Entry.new(key, value)
          end

          value
        end
      when "of_key"
        interpret_check_args { @of.try(&.key) || Nop.new }
      when "of_value"
        interpret_check_args { @of.try(&.value) || Nop.new }
      when "has_key?"
        interpret_check_args do |key|
          BoolLiteral.new(entries.any? &.key.==(key))
        end
      when "type"
        interpret_check_args { @name || Nop.new }
      when "clear"
        interpret_check_args do
          entries.clear
          self
        end
      else
        super
      end
    end

    private def to_double_splat(trailing_string = "")
      MacroId.new(entries.join(", ") do |entry|
        "#{entry.key} => #{entry.value}"
      end + trailing_string)
    end
  end

  class NamedTupleLiteral
    def interpret(method : String, args : Array(ASTNode), named_args : Hash(String, ASTNode)?, block : Crystal::Block?, interpreter : Crystal::MacroInterpreter, name_loc : Location?)
      case method
      when "empty?"
        interpret_check_args { BoolLiteral.new(entries.empty?) }
      when "keys"
        interpret_check_args { ArrayLiteral.map(entries) { |entry| MacroId.new(entry.key) } }
      when "size"
        interpret_check_args { NumberLiteral.new(entries.size) }
      when "to_a"
        interpret_check_args do
          ArrayLiteral.map(entries) { |entry| TupleLiteral.new([MacroId.new(entry.key), entry.value] of ASTNode) }
        end
      when "values"
        interpret_check_args { ArrayLiteral.map entries, &.value }
      when "each"
        interpret_check_args(uses_block: true) do
          block_arg_key = block.args[0]?
          block_arg_value = block.args[1]?

          entries.each do |entry|
            interpreter.define_var(block_arg_key.name, MacroId.new(entry.key)) if block_arg_key
            interpreter.define_var(block_arg_value.name, entry.value) if block_arg_value
            interpreter.accept block.body
          end

          NilLiteral.new
        end
      when "map"
        interpret_check_args(uses_block: true) do
          block_arg_key = block.args[0]?
          block_arg_value = block.args[1]?

          ArrayLiteral.map(entries) do |entry|
            interpreter.define_var(block_arg_key.name, MacroId.new(entry.key)) if block_arg_key
            interpreter.define_var(block_arg_value.name, entry.value) if block_arg_value
            interpreter.accept block.body
          end
        end
      when "double_splat"
        interpret_check_args(min_count: 0) do |arg|
          if arg
            unless arg.is_a?(Crystal::StringLiteral)
              arg.raise "argument to double_splat must be a StringLiteral, not #{arg.class_desc}"
            end

            if entries.empty?
              to_double_splat
            else
              to_double_splat(arg.value)
            end
          else
            to_double_splat
          end
        end
      when "[]"
        interpret_check_args do |key|
          case key
          when SymbolLiteral, MacroId, StringLiteral
            key = key.value
          else
            raise "argument to [] must be a symbol or string, not #{key.class_desc}:\n\n#{key}"
          end

          entry = entries.find &.key.==(key)
          entry.try(&.value) || NilLiteral.new
        end
      when "[]="
        interpret_check_args do |key, value|
          case key
          when SymbolLiteral, MacroId, StringLiteral
            key = key.value
          else
            raise "expected 'NamedTupleLiteral#[]=' first argument to be a SymbolLiteral or MacroId, not #{key.class_desc}"
          end

          index = entries.index &.key.==(key)
          if index
            entries[index] = NamedTupleLiteral::Entry.new(key, value)
          else
            entries << NamedTupleLiteral::Entry.new(key, value)
          end

          value
        end
      when "has_key?"
        interpret_check_args do |key|
          case key
          when SymbolLiteral, MacroId, StringLiteral
            key = key.value
          else
            raise "expected 'NamedTupleLiteral#has_key?' first argument to be a SymbolLiteral, StringLiteral or MacroId, not #{key.class_desc}"
          end

          BoolLiteral.new(entries.any? &.key.==(key))
        end
      else
        super
      end
    end

    private def to_double_splat(trailing_string = "")
      MacroId.new(entries.join(", ") do |entry|
        "#{Symbol.quote_for_named_argument(entry.key)}: #{entry.value}"
      end + trailing_string)
    end
  end

  class TupleLiteral
    def interpret(method : String, args : Array(ASTNode), named_args : Hash(String, ASTNode)?, block : Crystal::Block?, interpreter : Crystal::MacroInterpreter, name_loc : Location?)
      value = interpret_array_or_tuple_method(self, TupleLiteral, method, args, named_args, block, interpreter)
      value || super
    end
  end

  class RangeLiteral
    def interpret(method : String, args : Array(ASTNode), named_args : Hash(String, ASTNode)?, block : Crystal::Block?, interpreter : Crystal::MacroInterpreter, name_loc : Location?)
      case method
      when "begin"
        interpret_check_args { self.from }
      when "end"
        interpret_check_args { self.to }
      when "excludes_end?"
        interpret_check_args { BoolLiteral.new(self.exclusive?) }
      when "each"
        interpret_check_args(uses_block: true) do
          block_arg = block.args.first?

          interpret_to_range(interpreter).each do |num|
            interpreter.define_var(block_arg.name, NumberLiteral.new(num)) if block_arg
            interpreter.accept block.body
          end

          NilLiteral.new
        end
      when "map"
        interpret_check_args(uses_block: true) do
          block_arg = block.args.first?

          interpret_map(interpreter) do |num|
            interpreter.define_var(block_arg.name, NumberLiteral.new(num)) if block_arg
            interpreter.accept block.body
          end
        end
      when "to_a"
        interpret_check_args do
          interpret_map(interpreter) do |num|
            NumberLiteral.new(num)
          end
        end
      else
        super
      end
    end

    def interpret_map(interpreter, &)
      ArrayLiteral.map(interpret_to_range(interpreter)) do |num|
        yield num
      end
    end

    def interpret_to_range(interpreter)
      node = interpreter.accept(self.from)
      from = case node
             when NumberLiteral
               node.to_number.to_i
             else
               raise "range begin must be a NumberLiteral, not #{node.class_desc}"
             end

      node = interpreter.accept(self.to)
      to = case node
           when NumberLiteral
             node.to_number.to_i
           else
             raise "range end must be a NumberLiteral, not #{node.class_desc}"
           end

      Range.new(from, to, self.exclusive?)
    end

    def interpret_to_nilable_range(interpreter)
      node = interpreter.accept(self.from)
      from = case node
             when NumberLiteral
               node.to_number.to_i
             when NilLiteral, Nop
               nil
             else
               raise "range begin must be a NumberLiteral | NilLiteral | Nop, not #{node.class_desc}"
             end

      node = interpreter.accept(self.to)
      to = case node
           when NumberLiteral
             node.to_number.to_i
           when NilLiteral, Nop
             nil
           else
             raise "range end must be a NumberLiteral | NilLiteral | Nop, not #{node.class_desc}"
           end

      Range.new(from, to, self.exclusive?)
    end
  end

  class RegexLiteral
    def interpret(method : String, args : Array(ASTNode), named_args : Hash(String, ASTNode)?, block : Crystal::Block?, interpreter : Crystal::MacroInterpreter, name_loc : Location?)
      case method
      when "source"
        interpret_check_args { @value }
      when "options"
        interpret_check_args do
          options = [] of Symbol
          options << :i if @options.ignore_case?
          options << :m if @options.multiline?
          options << :x if @options.extended?
          ArrayLiteral.map(options, Path.global("Symbol")) { |opt| SymbolLiteral.new(opt.to_s) }
        end
      else
        super
      end
    end
  end

  class MetaMacroVar < ASTNode
    def to_macro_id
      @name
    end

    def interpret(method : String, args : Array(ASTNode), named_args : Hash(String, ASTNode)?, block : Crystal::Block?, interpreter : Crystal::MacroInterpreter, name_loc : Location?)
      case method
      when "name"
        interpret_check_args { MacroId.new(@name) }
      when "type"
        interpret_check_args do
          if type = @type
            TypeNode.new(type)
          else
            NilLiteral.new
          end
        end
      when "default_value"
        interpret_check_args do
          default_value || NilLiteral.new
        end
      when "has_default_value?"
        interpret_check_args do
          BoolLiteral.new(!!default_value)
        end
      when "annotation"
        fetch_annotation(self, method, args, named_args, block) do |type|
          self.var.annotation(type)
        end
      when "annotations"
        fetch_annotations(self, method, args, named_args, block) do |type|
          annotations = type ? self.var.annotations(type) : self.var.all_annotations
          return ArrayLiteral.new if annotations.nil?
          ArrayLiteral.map(annotations, &.itself)
        end
      else
        super
      end
    end
  end

  class Block
    def interpret(method : String, args : Array(ASTNode), named_args : Hash(String, ASTNode)?, block : Crystal::Block?, interpreter : Crystal::MacroInterpreter, name_loc : Location?)
      case method
      when "body"
        interpret_check_args { @body }
      when "args"
        interpret_check_args do
          ArrayLiteral.map(@args) { |arg| MacroId.new(arg.name) }
        end
      when "splat_index"
        interpret_check_args do
          @splat_index ? NumberLiteral.new(@splat_index.not_nil!) : NilLiteral.new
        end
      else
        super
      end
    end
  end

  class ProcNotation
    def interpret(method : String, args : Array(ASTNode), named_args : Hash(String, ASTNode)?, block : Crystal::Block?, interpreter : Crystal::MacroInterpreter, name_loc : Location?)
      case method
      when "inputs"
        interpret_check_args do
          if inputs = @inputs
            ArrayLiteral.map(inputs, &.itself)
          else
            ArrayLiteral.new
          end
        end
      when "output"
        interpret_check_args { @output || NilLiteral.new }
      when "resolve"
        interpret_check_args { interpreter.resolve(self) }
      when "resolve?"
        interpret_check_args { interpreter.resolve?(self) || NilLiteral.new }
      else
        super
      end
    end
  end

  class ProcLiteral
    def interpret(method : String, args : Array(ASTNode), named_args : Hash(String, ASTNode)?, block : Crystal::Block?, interpreter : Crystal::MacroInterpreter, name_loc : Location?)
      case method
      when "args", "body", "return_type"
        @def.interpret(method, args, named_args, block, interpreter, location)
      else
        super
      end
    end
  end

  class ProcPointer
    def interpret(method : String, args : Array(ASTNode), named_args : Hash(String, ASTNode)?, block : Crystal::Block?, interpreter : Crystal::MacroInterpreter, name_loc : Location?)
      case method
      when "obj"
        interpret_check_args { @obj || NilLiteral.new }
      when "name"
        interpret_check_args { MacroId.new(@name) }
      when "args"
        interpret_check_args { ArrayLiteral.map(@args, &.itself) }
      when "global?"
        interpret_check_args { BoolLiteral.new(@global) }
      else
        super
      end
    end
  end

  class Expressions
    def interpret(method : String, args : Array(ASTNode), named_args : Hash(String, ASTNode)?, block : Crystal::Block?, interpreter : Crystal::MacroInterpreter, name_loc : Location?)
      case method
      when "expressions"
        interpret_check_args do
          ArrayLiteral.map(@expressions) { |expression| expression }
        end
      else
        super
      end
    end
  end

  class BinaryOp
    def interpret(method : String, args : Array(ASTNode), named_args : Hash(String, ASTNode)?, block : Crystal::Block?, interpreter : Crystal::MacroInterpreter, name_loc : Location?)
      case method
      when "left"
        interpret_check_args { @left }
      when "right"
        interpret_check_args { @right }
      else
        super
      end
    end
  end

  class TypeDeclaration
    def interpret(method : String, args : Array(ASTNode), named_args : Hash(String, ASTNode)?, block : Crystal::Block?, interpreter : Crystal::MacroInterpreter, name_loc : Location?)
      case method
      when "var"
        interpret_check_args do
          var = @var
          var = MacroId.new(var.name) if var.is_a?(Var)
          var
        end
      when "type"
        interpret_check_args { @declared_type }
      when "value"
        interpret_check_args { @value || Nop.new }
      else
        super
      end
    end
  end

  class UninitializedVar
    def interpret(method : String, args : Array(ASTNode), named_args : Hash(String, ASTNode)?, block : Crystal::Block?, interpreter : Crystal::MacroInterpreter, name_loc : Location?)
      case method
      when "var"
        interpret_check_args do
          var = @var
          var = MacroId.new(var.name) if var.is_a?(Var)
          var
        end
      when "type"
        interpret_check_args { @declared_type }
      else
        super
      end
    end
  end

  class Union
    def interpret(method : String, args : Array(ASTNode), named_args : Hash(String, ASTNode)?, block : Crystal::Block?, interpreter : Crystal::MacroInterpreter, name_loc : Location?)
      case method
      when "resolve"
        interpret_check_args { interpreter.resolve(self) }
      when "resolve?"
        interpret_check_args { interpreter.resolve?(self) || NilLiteral.new }
      when "types"
        interpret_check_args { ArrayLiteral.map(@types, &.itself) }
      else
        super
      end
    end
  end

  class Arg
    def interpret(method : String, args : Array(ASTNode), named_args : Hash(String, ASTNode)?, block : Crystal::Block?, interpreter : Crystal::MacroInterpreter, name_loc : Location?)
      case method
      when "name"
        interpret_check_args { MacroId.new(external_name) }
      when "internal_name"
        interpret_check_args { MacroId.new(name) }
      when "default_value"
        interpret_check_args { default_value || Nop.new }
      when "restriction"
        interpret_check_args { restriction || Nop.new }
      when "annotation"
        fetch_annotation(self, method, args, named_args, block) do |type|
          self.annotation(type)
        end
      when "annotations"
        fetch_annotations(self, method, args, named_args, block) do |type|
          annotations = type ? self.annotations(type) : self.all_annotations
          return ArrayLiteral.new if annotations.nil?
          ArrayLiteral.map(annotations, &.itself)
        end
      else
        super
      end
    end
  end

  class Def
    def interpret(method : String, args : Array(ASTNode), named_args : Hash(String, ASTNode)?, block : Crystal::Block?, interpreter : Crystal::MacroInterpreter, name_loc : Location?)
      case method
      when "name"
        interpret_check_args { MacroId.new(@name) }
      when "args"
        interpret_check_args { ArrayLiteral.map @args, &.itself }
      when "splat_index"
        interpret_check_args do
          @splat_index ? NumberLiteral.new(@splat_index.not_nil!) : NilLiteral.new
        end
      when "double_splat"
        interpret_check_args { @double_splat || Nop.new }
      when "block_arg"
        interpret_check_args { @block_arg || Nop.new }
      when "accepts_block?"
        interpret_check_args { BoolLiteral.new(@block_arity != nil) }
      when "return_type"
        interpret_check_args { @return_type || Nop.new }
      when "free_vars"
        interpret_check_args do
          if (free_vars = @free_vars) && !free_vars.empty?
            ArrayLiteral.map(free_vars) { |free_var| MacroId.new(free_var) }
          else
            empty_no_return_array
          end
        end
      when "body"
        interpret_check_args { @body }
      when "receiver"
        interpret_check_args { @receiver || Nop.new }
      when "visibility"
        interpret_check_args do
          visibility_to_symbol(@visibility)
        end
      when "abstract?"
        interpret_check_args { BoolLiteral.new(@abstract) }
      when "annotation"
        fetch_annotation(self, method, args, named_args, block) do |type|
          self.annotation(type)
        end
      when "annotations"
        fetch_annotations(self, method, args, named_args, block) do |type|
          annotations = type ? self.annotations(type) : self.all_annotations
          return ArrayLiteral.new if annotations.nil?
          ArrayLiteral.map(annotations, &.itself)
        end
      else
        super
      end
    end
  end

  class Primitive
    def interpret(method : String, args : Array(ASTNode), named_args : Hash(String, ASTNode)?, block : Crystal::Block?, interpreter : Crystal::MacroInterpreter, name_loc : Location?)
      case method
      when "name"
        interpret_check_args { SymbolLiteral.new(@name) }
      else
        super
      end
    end
  end

  class Macro
    def interpret(method : String, args : Array(ASTNode), named_args : Hash(String, ASTNode)?, block : Crystal::Block?, interpreter : Crystal::MacroInterpreter, name_loc : Location?)
      case method
      when "name"
        interpret_check_args { MacroId.new(@name) }
      when "args"
        interpret_check_args { ArrayLiteral.map @args, &.itself }
      when "splat_index"
        interpret_check_args do
          @splat_index ? NumberLiteral.new(@splat_index.not_nil!) : NilLiteral.new
        end
      when "double_splat"
        interpret_check_args { @double_splat || Nop.new }
      when "block_arg"
        interpret_check_args { @block_arg || Nop.new }
      when "body"
        interpret_check_args { @body }
      when "visibility"
        interpret_check_args do
          visibility_to_symbol(@visibility)
        end
      else
        super
      end
    end
  end

  class MacroExpression
    def interpret(method : String, args : Array(ASTNode), named_args : Hash(String, ASTNode)?, block : Crystal::Block?, interpreter : Crystal::MacroInterpreter, name_loc : Location?)
      case method
      when "exp"
        interpret_check_args { @exp }
      when "output?"
        interpret_check_args { BoolLiteral.new(@output) }
      else
        super
      end
    end
  end

  class MacroIf
    def interpret(method : String, args : Array(ASTNode), named_args : Hash(String, ASTNode)?, block : Crystal::Block?, interpreter : Crystal::MacroInterpreter, name_loc : Location?)
      case method
      when "cond"
        interpret_check_args { @cond }
      when "then"
        interpret_check_args { @then }
      when "else"
        interpret_check_args { @else }
      when "is_unless?"
        interpret_check_args { BoolLiteral.new @is_unless }
      else
        super
      end
    end
  end

  class MacroFor
    def interpret(method : String, args : Array(ASTNode), named_args : Hash(String, ASTNode)?, block : Crystal::Block?, interpreter : Crystal::MacroInterpreter, name_loc : Location?)
      case method
      when "vars"
        interpret_check_args { ArrayLiteral.map(@vars, &.itself) }
      when "exp"
        interpret_check_args { @exp }
      when "body"
        interpret_check_args { @body }
      else
        super
      end
    end
  end

  class MacroLiteral
    def interpret(method : String, args : Array(ASTNode), named_args : Hash(String, ASTNode)?, block : Crystal::Block?, interpreter : Crystal::MacroInterpreter, name_loc : Location?)
      case method
      when "value"
        interpret_check_args { MacroId.new(@value) }
      else
        super
      end
    end
  end

  class MacroVar
    def interpret(method : String, args : Array(ASTNode), named_args : Hash(String, ASTNode)?, block : Crystal::Block?, interpreter : Crystal::MacroInterpreter, name_loc : Location?)
      case method
      when "name"
        interpret_check_args { MacroId.new(@name) }
      when "expressions"
        interpret_check_args do
          if exps = @exps
            ArrayLiteral.map(exps, &.itself)
          else
            empty_no_return_array
          end
        end
      else
        super
      end
    end
  end

  class UnaryExpression
    def interpret(method : String, args : Array(ASTNode), named_args : Hash(String, ASTNode)?, block : Crystal::Block?, interpreter : Crystal::MacroInterpreter, name_loc : Location?)
      case method
      when "exp"
        interpret_check_args { @exp }
      else
        super
      end
    end
  end

  class Include
    def interpret(method : String, args : Array(ASTNode), named_args : Hash(String, ASTNode)?, block : Crystal::Block?, interpreter : Crystal::MacroInterpreter, name_loc : Location?)
      case method
      when "name"
        interpret_check_args { @name }
      else
        super
      end
    end
  end

  class Extend
    def interpret(method : String, args : Array(ASTNode), named_args : Hash(String, ASTNode)?, block : Crystal::Block?, interpreter : Crystal::MacroInterpreter, name_loc : Location?)
      case method
      when "name"
        interpret_check_args { @name }
      else
        super
      end
    end
  end

  class Alias
    def interpret(method : String, args : Array(ASTNode), named_args : Hash(String, ASTNode)?, block : Crystal::Block?, interpreter : Crystal::MacroInterpreter, name_loc : Location?)
      case method
      when "name"
        interpret_check_args { @name }
      when "type"
        interpret_check_args { @value }
      else
        super
      end
    end
  end

  class OffsetOf
    def interpret(method : String, args : Array(ASTNode), named_args : Hash(String, ASTNode)?, block : Crystal::Block?, interpreter : Crystal::MacroInterpreter, name_loc : Location?)
      case method
      when "type"
        interpret_check_args { @offsetof_type }
      when "offset"
        interpret_check_args { @offset }
      else
        super
      end
    end
  end

  class Metaclass
    def interpret(method : String, args : Array(ASTNode), named_args : Hash(String, ASTNode)?, block : Crystal::Block?, interpreter : Crystal::MacroInterpreter, name_loc : Location?)
      case method
      when "instance"
        interpret_check_args { @name }
      when "resolve"
        interpret_check_args { interpreter.resolve(self) }
      when "resolve?"
        interpret_check_args { interpreter.resolve?(self) || NilLiteral.new }
      else
        super
      end
    end
  end

  class VisibilityModifier
    def interpret(method : String, args : Array(ASTNode), named_args : Hash(String, ASTNode)?, block : Crystal::Block?, interpreter : Crystal::MacroInterpreter, name_loc : Location?)
      case method
      when "exp"
        interpret_check_args { @exp }
      when "visibility"
        interpret_check_args do
          visibility_to_symbol(@modifier)
        end
      else
        super
      end
    end
  end

  class IsA
    def interpret(method : String, args : Array(ASTNode), named_args : Hash(String, ASTNode)?, block : Crystal::Block?, interpreter : Crystal::MacroInterpreter, name_loc : Location?)
      case method
      when "receiver"
        interpret_check_args { @obj }
      when "arg"
        interpret_check_args { @const }
      else
        super
      end
    end
  end

  class RespondsTo
    def interpret(method : String, args : Array(ASTNode), named_args : Hash(String, ASTNode)?, block : Crystal::Block?, interpreter : Crystal::MacroInterpreter, name_loc : Location?)
      case method
      when "receiver"
        interpret_check_args { @obj }
      when "name"
        interpret_check_args { StringLiteral.new(@name) }
      else
        super
      end
    end
  end

  class Require
    def interpret(method : String, args : Array(ASTNode), named_args : Hash(String, ASTNode)?, block : Crystal::Block?, interpreter : Crystal::MacroInterpreter, name_loc : Location?)
      case method
      when "path"
        interpret_check_args { StringLiteral.new(@string) }
      else
        super
      end
    end
  end

  class Asm
    def interpret(method : String, args : Array(ASTNode), named_args : Hash(String, ASTNode)?, block : Crystal::Block?, interpreter : Crystal::MacroInterpreter, name_loc : Location?)
      case method
      when "text"
        interpret_check_args { StringLiteral.new(@text) }
      when "outputs"
        interpret_check_args do
          if outputs = @outputs
            ArrayLiteral.map(outputs, &.itself)
          else
            empty_no_return_array
          end
        end
      when "inputs"
        interpret_check_args do
          if inputs = @inputs
            ArrayLiteral.map(inputs, &.itself)
          else
            empty_no_return_array
          end
        end
      when "clobbers"
        interpret_check_args do
          if clobbers = @clobbers
            ArrayLiteral.map(clobbers) { |clobber| StringLiteral.new(clobber) }
          else
            empty_no_return_array
          end
        end
      when "volatile?"
        interpret_check_args { BoolLiteral.new(@volatile) }
      when "alignstack?"
        interpret_check_args { BoolLiteral.new(@alignstack) }
      when "intel?"
        interpret_check_args { BoolLiteral.new(@intel) }
      when "can_throw?"
        interpret_check_args { BoolLiteral.new(@can_throw) }
      else
        super
      end
    end
  end

  class AsmOperand
    def interpret(method : String, args : Array(ASTNode), named_args : Hash(String, ASTNode)?, block : Crystal::Block?, interpreter : Crystal::MacroInterpreter, name_loc : Location?)
      case method
      when "constraint"
        interpret_check_args { StringLiteral.new(@constraint) }
      when "exp"
        interpret_check_args { @exp }
      else
        super
      end
    end
  end

  class MacroId
    def interpret(method : String, args : Array(ASTNode), named_args : Hash(String, ASTNode)?, block : Crystal::Block?, interpreter : Crystal::MacroInterpreter, name_loc : Location?)
      case method
      when "==", "!="
        interpret_check_args do |arg|
          case arg
          when StringLiteral, SymbolLiteral
            if method == "=="
              BoolLiteral.new(@value == arg.value)
            else
              BoolLiteral.new(@value != arg.value)
            end
          else
            super
          end
        end
      when "stringify", "class_name", "symbolize"
        super
      else
        value = StringLiteral.new(@value).interpret(method, args, named_args, block, interpreter, location)
        value = MacroId.new(value.value) if value.is_a?(StringLiteral)
        value
      end
    rescue UndefinedMacroMethodError
      raise "undefined macro method '#{class_desc}##{method}'", exception_type: Crystal::UndefinedMacroMethodError
    end

    def interpret_compare(other : MacroId | StringLiteral)
      value <=> other.value
    end
  end

  class SymbolLiteral
    def interpret(method : String, args : Array(ASTNode), named_args : Hash(String, ASTNode)?, block : Crystal::Block?, interpreter : Crystal::MacroInterpreter, name_loc : Location?)
      case method
      when "==", "!="
        interpret_check_args do |arg|
          case arg
          when MacroId
            if method == "=="
              BoolLiteral.new(@value == arg.value)
            else
              BoolLiteral.new(@value != arg.value)
            end
          else
            super
          end
        end
      when "stringify", "class_name", "symbolize"
        super
      else
        value = StringLiteral.new(@value).interpret(method, args, named_args, block, interpreter, location)
        value = SymbolLiteral.new(value.value) if value.is_a?(StringLiteral)
        value
      end
    rescue UndefinedMacroMethodError
      raise "undefined macro method '#{class_desc}##{method}'", exception_type: Crystal::UndefinedMacroMethodError
    end
  end

  class TypeNode
    def interpret(method : String, args : Array(ASTNode), named_args : Hash(String, ASTNode)?, block : Crystal::Block?, interpreter : Crystal::MacroInterpreter, name_loc : Location?)
      case method
      when "abstract?"
        interpret_check_args { BoolLiteral.new(type.abstract?) }
      when "union?"
        interpret_check_args { BoolLiteral.new(type.is_a?(UnionType)) }
      when "module?"
        interpret_check_args { BoolLiteral.new(type.module?) }
      when "class?"
        interpret_check_args { BoolLiteral.new(type.class? && !type.struct?) }
      when "struct?"
        interpret_check_args { BoolLiteral.new(type.class? && type.struct?) }
      when "nilable?"
        interpret_check_args { BoolLiteral.new(type.nilable?) }
      when "union_types"
        interpret_check_args { TypeNode.union_types(self) }
      when "name"
        interpret_check_args(named_params: ["generic_args"]) do
          generic_args = parse_generic_args_argument(self, method, named_args, default: true)
          MacroId.new(type.devirtualize.to_s(generic_args: generic_args))
        end
      when "type_vars"
        interpret_check_args { TypeNode.type_vars(type) }
      when "instance_vars"
        interpret_check_args { TypeNode.instance_vars(type, name_loc) }
      when "class_vars"
        interpret_check_args { TypeNode.class_vars(type) }
      when "ancestors"
        interpret_check_args { TypeNode.ancestors(type) }
      when "superclass"
        interpret_check_args { TypeNode.superclass(type) }
      when "subclasses"
        interpret_check_args { TypeNode.subclasses(type) }
      when "all_subclasses"
        interpret_check_args { TypeNode.all_subclasses(type) }
      when "includers"
        interpret_check_args { TypeNode.includers(type) }
      when "constants"
        interpret_check_args { TypeNode.constants(type) }
      when "constant"
        interpret_check_args do |arg|
          value = arg.to_string("argument to 'TypeNode#constant'")
          TypeNode.constant(type, value)
        end
      when "has_constant?"
        interpret_check_args do |arg|
          value = arg.to_string("argument to 'TypeNode#has_constant?'")
          TypeNode.has_constant?(type, value)
        end
      when "methods"
        interpret_check_args { TypeNode.methods(type) }
      when "has_method?"
        interpret_check_args do |arg|
          value = arg.to_string("argument to 'TypeNode#has_method?'")
          TypeNode.has_method?(type, value)
        end
      when "annotation"
        fetch_annotation(self, method, args, named_args, block) do |type|
          self.type.annotation(type)
        end
      when "annotations"
        fetch_annotations(self, method, args, named_args, block) do |type|
          annotations = type ? self.type.annotations(type) : self.type.all_annotations
          return ArrayLiteral.new if annotations.nil?
          ArrayLiteral.map(annotations, &.itself)
        end
      when "size"
        interpret_check_args do
          type = self.type.instance_type
          case type
          when TupleInstanceType
            NumberLiteral.new(type.tuple_types.size)
          when NamedTupleInstanceType
            NumberLiteral.new(type.entries.size)
          else
            raise "undefined method 'size' for TypeNode of type #{type} (must be a tuple or named tuple type)"
          end
        end
      when "keys"
        interpret_check_args do
          type = self.type.instance_type
          if type.is_a?(NamedTupleInstanceType)
            ArrayLiteral.map(type.entries) { |entry| MacroId.new(entry.name) }
          else
            raise "undefined method 'keys' for TypeNode of type #{type} (must be a named tuple type)"
          end
        end
      when "[]"
        interpret_check_args do |arg|
          type = self.type.instance_type
          case type
          when NamedTupleInstanceType
            case arg
            when SymbolLiteral
              key = arg.value
            when MacroId
              key = arg.value
            else
              return NilLiteral.new
            end
            index = type.name_index(key)
            unless index
              return NilLiteral.new
            end
            TypeNode.new(type.entries[index].type)
          when TupleInstanceType
            case arg
            when NumberLiteral
              index = arg.to_number.to_i
              type = type.tuple_types[index]?
              unless type
                return NilLiteral.new
              end
              TypeNode.new(type)
            else
              return NilLiteral.new
            end
          else
            raise "undefined method '[]' for TypeNode of type #{type} (must be a tuple or named tuple type)"
          end
        end
      when "class"
        interpret_check_args { TypeNode.new(type.metaclass) }
      when "instance"
        interpret_check_args { TypeNode.new(type.instance_type) }
      when "==", "!="
        interpret_check_args do |arg|
          return super unless arg.is_a?(TypeNode)

          self_type = self.type.devirtualize
          other_type = arg.type.devirtualize

          case method
          when "=="
            BoolLiteral.new(self_type == other_type)
          else # "!="
            BoolLiteral.new(self_type != other_type)
          end
        end
      when "<", "<=", ">", ">="
        interpret_check_args do |arg|
          unless arg.is_a?(TypeNode)
            raise "TypeNode##{method} expects TypeNode, not #{arg.class_desc}"
          end

          self_type = self.type.devirtualize
          other_type = arg.type.devirtualize

          case method
          when "<"
            value = self_type != other_type && self_type.implements?(other_type)
          when "<="
            value = self_type.implements?(other_type)
          when ">"
            value = self_type != other_type && other_type.implements?(self_type)
          else # ">="
            value = other_type.implements?(self_type)
          end
          BoolLiteral.new(!!value)
        end
      when "overrides?"
        interpret_check_args do |arg1, arg2|
          unless arg1.is_a?(TypeNode)
            raise "TypeNode##{method} expects TypeNode as a first argument, not #{arg1.class_desc}"
          end

          value = arg2.to_string("second argument to 'TypeNode#overrides?")
          TypeNode.overrides?(type, arg1.type, value)
        end
      when "resolve"
        interpret_check_args { self }
      when "resolve?"
        interpret_check_args { self }
      when "private?"
        interpret_check_args { BoolLiteral.new(type.private?) }
      when "public?"
        interpret_check_args { BoolLiteral.new(!type.private?) }
      when "visibility"
        interpret_check_args do
          if type.private?
            SymbolLiteral.new("private")
          else
            SymbolLiteral.new("public")
          end
        end
      when "has_inner_pointers?"
        interpret_check_args { TypeNode.has_inner_pointers?(type, name_loc) }
      else
        super
      end
    end

    def self.includers(type)
      case type
      when NonGenericModuleType, GenericModuleType, GenericModuleInstanceType
        types = type.raw_including_types
        return empty_no_return_array unless types
        ArrayLiteral.map(types) do |including_type|
          TypeNode.new including_type
        end
      else
        empty_no_return_array
      end
    end

    def self.type_vars(type)
      if type.is_a?(GenericClassInstanceType) || type.is_a?(GenericModuleInstanceType)
        if type.is_a?(TupleInstanceType)
          if type.tuple_types.empty?
            empty_no_return_array
          else
            ArrayLiteral.map(type.tuple_types) do |tuple_type|
              TypeNode.new(tuple_type)
            end
          end
        else
          if type.type_vars.empty?
            empty_no_return_array
          else
            ArrayLiteral.map(type.type_vars.values) do |type_var|
              if type_var.is_a?(Var)
                TypeNode.new(type_var.type)
              else
                type_var
              end
            end
          end
        end
      elsif type.is_a?(GenericType)
        t = type.as(GenericType)
        if t.type_vars.empty?
          empty_no_return_array
        else
          ArrayLiteral.map(t.type_vars) do |type_var|
            MacroId.new(type_var)
          end
        end
      else
        empty_no_return_array
      end
    end

    def self.instance_vars(type, name_loc)
      if type.is_a?(InstanceVarContainer)
        unless type.program.top_level_semantic_complete?
          message = "`TypeNode#instance_vars` cannot be called in the top-level scope: instance vars are not yet initialized"
          if name_loc
            raise Crystal::TypeException.new(message, name_loc)
          else
            raise Crystal::TypeException.new(message)
          end
        end
        ArrayLiteral.map(type.all_instance_vars) do |name, ivar|
          meta_var = MetaMacroVar.new(name[1..-1], ivar.type)
          meta_var.var = ivar
          meta_var.default_value = type.get_instance_var_initializer(name).try(&.value)
          meta_var
        end
      else
        empty_no_return_array
      end
    end

    def self.has_inner_pointers?(type, name_loc)
      unless type.program.top_level_semantic_complete?
        message = "`TypeNode#has_inner_pointers?` cannot be called in the top-level scope: instance vars are not yet initialized"
        if name_loc
          raise Crystal::TypeException.new(message, name_loc)
        else
          raise Crystal::TypeException.new(message)
        end
      end

      BoolLiteral.new(type.has_inner_pointers?)
    end

    def self.class_vars(type)
      if type.is_a?(ClassVarContainer)
        ArrayLiteral.map(type.all_class_vars) do |name, ivar|
          meta_var = MetaMacroVar.new(name[2..-1], ivar.type)
          meta_var.var = ivar
          meta_var.default_value = ivar.initializer.try(&.node)
          meta_var
        end
      else
        empty_no_return_array
      end
    end

    def self.ancestors(type)
      ancestors = type.ancestors
      if ancestors.empty?
        empty_no_return_array
      else
        ArrayLiteral.map(type.ancestors) { |ancestor| TypeNode.new(ancestor) }
      end
    end

    def self.superclass(type)
      superclass = type.superclass
      superclass ? TypeNode.new(superclass) : NilLiteral.new
    rescue
      NilLiteral.new
    end

    def self.subclasses(type)
      subclasses = type.devirtualize.subclasses
      if subclasses.empty?
        empty_no_return_array
      else
        ArrayLiteral.map(subclasses) { |subtype| TypeNode.new(subtype) }
      end
    end

    def self.all_subclasses(type)
      subclasses = type.devirtualize.all_subclasses
      if subclasses.empty?
        empty_no_return_array
      else
        ArrayLiteral.map(subclasses) { |subtype| TypeNode.new(subtype) }
      end
    end

    def self.union_types(type_node)
      type = type_node.type

      if type.is_a?(UnionType)
        ArrayLiteral.map(type.union_types) { |uniontype| TypeNode.new(uniontype) }
      else
        ArrayLiteral.new([type_node] of ASTNode)
      end
    end

    def self.constants(type)
      if type.types.empty?
        empty_no_return_array
      else
        names = type.types.map { |name, member_type| MacroId.new(name).as(ASTNode) }
        ArrayLiteral.new names
      end
    end

    def self.has_constant?(type, name)
      BoolLiteral.new(type.types.has_key?(name))
    end

    def self.constant(type, name)
      type = type.types[name]?
      case type
      when Const
        type.value
      when Type
        TypeNode.new(type)
      else
        NilLiteral.new
      end
    end

    def self.methods(type)
      defs = [] of ASTNode
      type.defs.try &.each do |name, metadatas|
        metadatas.each do |metadata|
          defs << metadata.def
        end
      end
      ArrayLiteral.new(defs)
    end

    def self.has_method?(type, name)
      BoolLiteral.new(!!type.has_def?(name))
    end

    def self.overrides?(type, target, method)
      overrides = type.lookup_defs(method).any? do |a_def|
        a_def.owner != target && a_def.macro_owner != target && !target.implements?(a_def.owner)
      end
      BoolLiteral.new(!!overrides)
    end
  end

  class SymbolLiteral
    def to_macro_id
      @value
    end
  end

  class Var
    def to_macro_id
      @name
    end
  end

  class Call
    def interpret(method : String, args : Array(ASTNode), named_args : Hash(String, ASTNode)?, block : Crystal::Block?, interpreter : Crystal::MacroInterpreter, name_loc : Location?)
      case method
      when "name"
        interpret_check_args { MacroId.new(name) }
      when "receiver"
        interpret_check_args { obj || Nop.new }
      when "args"
        interpret_check_args { ArrayLiteral.map self.args, &.itself }
      when "named_args"
        interpret_check_args do
          if named_args = self.named_args
            ArrayLiteral.map(named_args) { |arg| arg }
          else
            Nop.new
          end
        end
      when "block"
        interpret_check_args { self.block || Nop.new }
      when "block_arg"
        interpret_check_args { self.block_arg || Nop.new }
      when "global?"
        interpret_check_args { BoolLiteral.new(@global) }
      else
        super
      end
    end

    def to_macro_id
      if !obj && !block && args.empty?
        @name
      else
        to_s
      end
    end
  end

  class NamedArgument
    def interpret(method : String, args : Array(ASTNode), named_args : Hash(String, ASTNode)?, block : Crystal::Block?, interpreter : Crystal::MacroInterpreter, name_loc : Location?)
      case method
      when "name"
        interpret_check_args { MacroId.new(name) }
      when "value"
        interpret_check_args { value }
      else
        super
      end
    end
  end

  class If
    def interpret(method : String, args : Array(ASTNode), named_args : Hash(String, ASTNode)?, block : Crystal::Block?, interpreter : Crystal::MacroInterpreter, name_loc : Location?)
      case method
      when "cond"
        interpret_check_args { @cond }
      when "then"
        interpret_check_args { @then }
      when "else"
        interpret_check_args { @else }
      else
        super
      end
    end
  end

  class Case
    def interpret(method : String, args : Array(ASTNode), named_args : Hash(String, ASTNode)?, block : Crystal::Block?, interpreter : Crystal::MacroInterpreter, name_loc : Location?)
      case method
      when "cond"
        interpret_check_args { cond || Nop.new }
      when "whens"
        interpret_check_args { ArrayLiteral.map whens, &.itself }
      when "else"
        interpret_check_args { self.else || Nop.new }
      when "exhaustive?"
        interpret_check_args { BoolLiteral.new(@exhaustive) }
      else
        super
      end
    end
  end

  class Select
    def interpret(method : String, args : Array(ASTNode), named_args : Hash(String, ASTNode)?, block : Crystal::Block?, interpreter : Crystal::MacroInterpreter, name_loc : Location?)
      case method
      when "whens"
        interpret_check_args { ArrayLiteral.map whens, &.itself }
      when "else"
        interpret_check_args { self.else || Nop.new }
      else
        super
      end
    end
  end

  class When
    def interpret(method : String, args : Array(ASTNode), named_args : Hash(String, ASTNode)?, block : Crystal::Block?, interpreter : Crystal::MacroInterpreter, name_loc : Location?)
      case method
      when "conds"
        interpret_check_args { ArrayLiteral.map(conds, &.itself) }
      when "body"
        interpret_check_args { body }
      when "exhaustive?"
        interpret_check_args { BoolLiteral.new(@exhaustive) }
      else
        super
      end
    end
  end

  class ExceptionHandler
    def interpret(method : String, args : Array(ASTNode), named_args : Hash(String, ASTNode)?, block : Crystal::Block?, interpreter : Crystal::MacroInterpreter, name_loc : Location?)
      case method
      when "body"
        interpret_check_args { @body }
      when "rescues"
        interpret_check_args { (rescues = @rescues) ? ArrayLiteral.map(rescues, &.itself) : NilLiteral.new }
      when "else"
        interpret_check_args { @else || Nop.new }
      when "ensure"
        interpret_check_args { @ensure || Nop.new }
      else
        super
      end
    end
  end

  class Rescue
    def interpret(method : String, args : Array(ASTNode), named_args : Hash(String, ASTNode)?, block : Crystal::Block?, interpreter : Crystal::MacroInterpreter, name_loc : Location?)
      case method
      when "body"
        interpret_check_args { body }
      when "types"
        interpret_check_args { (types = @types) ? ArrayLiteral.map(types, &.itself) : NilLiteral.new }
      when "name"
        interpret_check_args { (name = @name) ? MacroId.new(name) : Nop.new }
      else
        super
      end
    end
  end

  class ControlExpression
    def interpret(method : String, args : Array(ASTNode), named_args : Hash(String, ASTNode)?, block : Crystal::Block?, interpreter : Crystal::MacroInterpreter, name_loc : Location?)
      case method
      when "exp"
        interpret_check_args { exp || Nop.new }
      else
        super
      end
    end
  end

  class Yield
    def interpret(method : String, args : Array(ASTNode), named_args : Hash(String, ASTNode)?, block : Crystal::Block?, interpreter : Crystal::MacroInterpreter, name_loc : Location?)
      case method
      when "expressions"
        interpret_check_args { ArrayLiteral.map(@exps, &.itself) }
      when "scope"
        interpret_check_args { scope || Nop.new }
      else
        super
      end
    end
  end

  class Assign
    def interpret(method : String, args : Array(ASTNode), named_args : Hash(String, ASTNode)?, block : Crystal::Block?, interpreter : Crystal::MacroInterpreter, name_loc : Location?)
      case method
      when "target"
        interpret_check_args { target }
      when "value"
        interpret_check_args { value }
      else
        super
      end
    end
  end

  class MultiAssign
    def interpret(method : String, args : Array(ASTNode), named_args : Hash(String, ASTNode)?, block : Crystal::Block?, interpreter : Crystal::MacroInterpreter, name_loc : Location?)
      case method
      when "targets"
        interpret_check_args { ArrayLiteral.map(targets, &.itself) }
      when "values"
        interpret_check_args { ArrayLiteral.map(values, &.itself) }
      else
        super
      end
    end
  end

  class InstanceVar
    def to_macro_id
      @name
    end

    def interpret(method : String, args : Array(ASTNode), named_args : Hash(String, ASTNode)?, block : Crystal::Block?, interpreter : Crystal::MacroInterpreter, name_loc : Location?)
      case method
      when "name"
        interpret_check_args { MacroId.new(@name) }
      else
        super
      end
    end
  end

  class ReadInstanceVar
    def interpret(method : String, args : Array(ASTNode), named_args : Hash(String, ASTNode)?, block : Crystal::Block?, interpreter : Crystal::MacroInterpreter, name_loc : Location?)
      case method
      when "obj"
        interpret_check_args { @obj }
      when "name"
        interpret_check_args { MacroId.new(@name) }
      else
        super
      end
    end
  end

  class ClassVar
    def to_macro_id
      @name
    end

    def interpret(method : String, args : Array(ASTNode), named_args : Hash(String, ASTNode)?, block : Crystal::Block?, interpreter : Crystal::MacroInterpreter, name_loc : Location?)
      case method
      when "name"
        interpret_check_args { MacroId.new(@name) }
      else
        super
      end
    end
  end

  class Global
    def to_macro_id
      @name
    end

    def interpret(method : String, args : Array(ASTNode), named_args : Hash(String, ASTNode)?, block : Crystal::Block?, interpreter : Crystal::MacroInterpreter, name_loc : Location?)
      case method
      when "name"
        interpret_check_args { MacroId.new(@name) }
      else
        super
      end
    end
  end

  class Path
    def interpret(method : String, args : Array(ASTNode), named_args : Hash(String, ASTNode)?, block : Crystal::Block?, interpreter : Crystal::MacroInterpreter, name_loc : Location?)
      case method
      when "names"
        interpret_check_args do
          ArrayLiteral.map(@names) { |name| MacroId.new(name) }
        end
      when "global"
        interpreter.warnings.add_warning_at(name_loc, "Deprecated Path#global. Use `#global?` instead")
        interpret_check_args { BoolLiteral.new(@global) }
      when "global?"
        interpret_check_args { BoolLiteral.new(@global) }
      when "resolve"
        interpret_check_args { interpreter.resolve(self) }
      when "resolve?"
        interpret_check_args { interpreter.resolve?(self) || NilLiteral.new }
      when "types"
        interpret_check_args { ArrayLiteral.new([self] of ASTNode) }
      else
        super
      end
    end

    def to_macro_id
      String.build do |io|
        io << "::" if global?

        @names.join(io, "::")
      end
    end
  end

  class While
    def interpret(method : String, args : Array(ASTNode), named_args : Hash(String, ASTNode)?, block : Crystal::Block?, interpreter : Crystal::MacroInterpreter, name_loc : Location?)
      case method
      when "cond"
        interpret_check_args { @cond }
      when "body"
        interpret_check_args { @body }
      else
        super
      end
    end
  end

  class Cast
    def interpret(method : String, args : Array(ASTNode), named_args : Hash(String, ASTNode)?, block : Crystal::Block?, interpreter : Crystal::MacroInterpreter, name_loc : Location?)
      case method
      when "obj"
        interpret_check_args { obj }
      when "to"
        interpret_check_args { to }
      else
        super
      end
    end
  end

  class NilableCast
    def interpret(method : String, args : Array(ASTNode), named_args : Hash(String, ASTNode)?, block : Crystal::Block?, interpreter : Crystal::MacroInterpreter, name_loc : Location?)
      case method
      when "obj"
        interpret_check_args { obj }
      when "to"
        interpret_check_args { to }
      else
        super
      end
    end
  end

  class TypeOf
    def interpret(method : String, args : Array(ASTNode), named_args : Hash(String, ASTNode)?, block : Crystal::Block?, interpreter : Crystal::MacroInterpreter, name_loc : Location?)
      case method
      when "args"
        interpret_check_args { ArrayLiteral.map(@expressions, &.itself) }
      else
        super
      end
    end
  end

  class Generic
    def interpret(method : String, args : Array(ASTNode), named_args : Hash(String, ASTNode)?, block : Crystal::Block?, interpreter : Crystal::MacroInterpreter, name_loc : Location?)
      case method
      when "name"
        interpret_check_args { name }
      when "type_vars"
        interpret_check_args { ArrayLiteral.map(type_vars, &.itself) }
      when "named_args"
        interpret_check_args do
          if named_args = @named_args
            NamedTupleLiteral.new(named_args.map { |arg| NamedTupleLiteral::Entry.new(arg.name, arg.value) })
          else
            NilLiteral.new
          end
        end
      when "resolve"
        interpret_check_args { interpreter.resolve(self) }
      when "resolve?"
        interpret_check_args { interpreter.resolve?(self) || NilLiteral.new }
      when "types"
        interpret_check_args { ArrayLiteral.new([self] of ASTNode) }
      else
        super
      end
    end
  end

  class Annotation
    def interpret(method : String, args : Array(ASTNode), named_args : Hash(String, ASTNode)?, block : Crystal::Block?, interpreter : Crystal::MacroInterpreter, name_loc : Location?)
      case method
      when "name"
        interpret_check_args { @path }
      when "[]"
        interpret_check_args do |arg|
          case arg
          when NumberLiteral
            index = arg.to_number.to_i
            return self.args[index]? || NilLiteral.new
          when SymbolLiteral then name = arg.value
          when StringLiteral then name = arg.value
          when MacroId       then name = arg.value
          else
            raise "argument to [] must be a number, symbol or string, not #{arg.class_desc}:\n\n#{arg}"
          end

          named_arg = self.named_args.try &.find do |named_arg|
            named_arg.name == name
          end
          named_arg.try(&.value) || NilLiteral.new
        end
      when "args"
        interpret_check_args do
          TupleLiteral.map self.args, &.itself
        end
      when "named_args"
        interpret_check_args do
          get_named_annotation_args self
        end
      else
        super
      end
    end
  end

  class ClassDef
    def interpret(method : String, args : Array(ASTNode), named_args : Hash(String, ASTNode)?, block : Crystal::Block?, interpreter : Crystal::MacroInterpreter, name_loc : Location?)
      case method
      when "kind"
        interpret_check_args { MacroId.new(@struct ? "struct" : "class") }
      when "name"
        type_definition_generic_name(self, method, args, named_args, block)
      when "superclass"
        interpret_check_args { @superclass || Nop.new }
      when "type_vars"
        interpret_check_args do
          if (type_vars = @type_vars) && type_vars.present?
            ArrayLiteral.map(type_vars) { |type_var| MacroId.new(type_var) }
          else
            empty_no_return_array
          end
        end
      when "splat_index"
        interpret_check_args do
          if splat_index = @splat_index
            NumberLiteral.new(splat_index)
          else
            NilLiteral.new
          end
        end
      when "body"
        interpret_check_args { @body }
      when "abstract?"
        interpret_check_args { BoolLiteral.new(@abstract) }
      when "struct?"
        interpret_check_args { BoolLiteral.new(@struct) }
      else
        super
      end
    end
  end

  class ModuleDef
    def interpret(method : String, args : Array(ASTNode), named_args : Hash(String, ASTNode)?, block : Crystal::Block?, interpreter : Crystal::MacroInterpreter, name_loc : Location?)
      case method
      when "kind"
        interpret_check_args { MacroId.new("module") }
      when "name"
        type_definition_generic_name(self, method, args, named_args, block)
      when "type_vars"
        interpret_check_args do
          if (type_vars = @type_vars) && type_vars.present?
            ArrayLiteral.map(type_vars) { |type_var| MacroId.new(type_var) }
          else
            empty_no_return_array
          end
        end
      when "splat_index"
        interpret_check_args do
          if splat_index = @splat_index
            NumberLiteral.new(splat_index)
          else
            NilLiteral.new
          end
        end
      when "body"
        interpret_check_args { @body }
      else
        super
      end
    end
  end

  class EnumDef
    def interpret(method : String, args : Array(ASTNode), named_args : Hash(String, ASTNode)?, block : Crystal::Block?, interpreter : Crystal::MacroInterpreter, name_loc : Location?)
      case method
      when "kind"
        interpret_check_args { MacroId.new("enum") }
      when "name"
        interpret_check_args(named_params: ["generic_args"]) do
          # parse the argument, but ignore it otherwise
          parse_generic_args_argument(self, method, named_args, default: true)
          @name
        end
      when "base_type"
        interpret_check_args { @base_type || Nop.new }
      when "body"
        interpret_check_args { Expressions.from(@members) }
      else
        super
      end
    end
  end

  class AnnotationDef
    def interpret(method : String, args : Array(ASTNode), named_args : Hash(String, ASTNode)?, block : Crystal::Block?, interpreter : Crystal::MacroInterpreter, name_loc : Location?)
      case method
      when "kind"
        interpret_check_args { MacroId.new("annotation") }
      when "name"
        interpret_check_args(named_params: ["generic_args"]) do
          # parse the argument, but ignore it otherwise
          parse_generic_args_argument(self, method, named_args, default: true)
          @name
        end
      when "body"
        interpret_check_args { Nop.new }
      else
        super
      end
    end
  end

  class LibDef
    def interpret(method : String, args : Array(ASTNode), named_args : Hash(String, ASTNode)?, block : Crystal::Block?, interpreter : Crystal::MacroInterpreter, name_loc : Location?)
      case method
      when "kind"
        interpret_check_args { MacroId.new("lib") }
      when "name"
        interpret_check_args(named_params: ["generic_args"]) do
          # parse the argument, but ignore it otherwise
          parse_generic_args_argument(self, method, named_args, default: true)
          @name
        end
      when "body"
        interpret_check_args { @body }
      else
        super
      end
    end
  end

  class CStructOrUnionDef
    def interpret(method : String, args : Array(ASTNode), named_args : Hash(String, ASTNode)?, block : Crystal::Block?, interpreter : Crystal::MacroInterpreter, name_loc : Location?)
      case method
      when "kind"
        interpret_check_args { MacroId.new(@union ? "union" : "struct") }
      when "name"
        interpret_check_args(named_params: ["generic_args"]) do
          # parse the argument, but ignore it otherwise
          parse_generic_args_argument(self, method, named_args, default: true)
          Path.new(@name)
        end
      when "body"
        interpret_check_args { @body }
      when "union?"
        interpret_check_args { BoolLiteral.new(@union) }
      else
        super
      end
    end
  end

  class FunDef
    def interpret(method : String, args : Array(ASTNode), named_args : Hash(String, ASTNode)?, block : Crystal::Block?, interpreter : Crystal::MacroInterpreter, name_loc : Location?)
      case method
      when "name"
        interpret_check_args { MacroId.new(@name) }
      when "real_name"
        interpret_check_args { @real_name != @name ? StringLiteral.new(@real_name) : Nop.new }
      when "args"
        interpret_check_args { ArrayLiteral.map(@args, &.itself) }
      when "variadic?"
        interpret_check_args { BoolLiteral.new(@varargs) }
      when "return_type"
        interpret_check_args { @return_type || Nop.new }
      when "body"
        interpret_check_args { @body || Nop.new }
      when "has_body?"
        interpret_check_args { BoolLiteral.new(!@body.nil?) }
      else
        super
      end
    end
  end

  class TypeDef
    def interpret(method : String, args : Array(ASTNode), named_args : Hash(String, ASTNode)?, block : Crystal::Block?, interpreter : Crystal::MacroInterpreter, name_loc : Location?)
      case method
      when "name"
        interpret_check_args { Path.new(@name).at(@name_location) }
      when "type"
        interpret_check_args { @type_spec }
      else
        super
      end
    end
  end

  class ExternalVar
    def interpret(method : String, args : Array(ASTNode), named_args : Hash(String, ASTNode)?, block : Crystal::Block?, interpreter : Crystal::MacroInterpreter, name_loc : Location?)
      case method
      when "name"
        interpret_check_args { MacroId.new(@name) }
      when "real_name"
        interpret_check_args { (real_name = @real_name) ? StringLiteral.new(real_name) : Nop.new }
      when "type"
        interpret_check_args { @type_spec }
      else
        super
      end
    end
  end
end

private def get_named_annotation_args(object)
  if named_args = object.named_args
    Crystal::NamedTupleLiteral.new(named_args.map { |arg| Crystal::NamedTupleLiteral::Entry.new(arg.name, arg.value) })
  else
    Crystal::NamedTupleLiteral.new
  end
end

private def interpret_array_or_tuple_method(object, klass, method, args, named_args, block, interpreter)
  case method
  when "any?"
    interpret_check_args(node: object, uses_block: true) do
      block_arg = block.args.first?

      Crystal::BoolLiteral.new(object.elements.any? do |elem|
        interpreter.define_var(block_arg.name, elem) if block_arg
        interpreter.accept(block.body).truthy?
      end)
    end
  when "all?"
    interpret_check_args(node: object, uses_block: true) do
      block_arg = block.args.first?

      Crystal::BoolLiteral.new(object.elements.all? do |elem|
        interpreter.define_var(block_arg.name, elem) if block_arg
        interpreter.accept(block.body).truthy?
      end)
    end
  when "splat"
    interpret_check_args(node: object, min_count: 0) do |arg|
      if arg
        unless arg.is_a?(Crystal::StringLiteral)
          arg.raise "argument to splat must be a StringLiteral, not #{arg.class_desc}"
        end

        if object.elements.empty?
          Crystal::MacroId.new("")
        else
          Crystal::MacroId.new((object.elements.join ", ") + arg.value)
        end
      else
        Crystal::MacroId.new(object.elements.join ", ")
      end
    end
  when "empty?"
    interpret_check_args(node: object) { Crystal::BoolLiteral.new(object.elements.empty?) }
  when "find"
    interpret_check_args(node: object, uses_block: true) do
      block_arg = block.args.first?

      found = object.elements.find do |elem|
        interpreter.define_var(block_arg.name, elem) if block_arg
        interpreter.accept(block.body).truthy?
      end
      found ? found : Crystal::NilLiteral.new
    end
  when "first"
    interpret_check_args(node: object) { object.elements.first? || Crystal::NilLiteral.new }
  when "includes?"
    interpret_check_args(node: object) do |arg|
      Crystal::BoolLiteral.new(object.elements.includes?(arg))
    end
  when "join"
    interpret_check_args(node: object) do |arg|
      Crystal::StringLiteral.new(object.elements.map(&.to_macro_id).join arg.to_macro_id)
    end
  when "last"
    interpret_check_args(node: object) { object.elements.last? || Crystal::NilLiteral.new }
  when "size"
    interpret_check_args(node: object) { Crystal::NumberLiteral.new(object.elements.size) }
  when "each"
    interpret_check_args(node: object, uses_block: true) do
      block_arg = block.args.first?

      object.elements.each do |elem|
        interpreter.define_var(block_arg.name, elem) if block_arg
        interpreter.accept block.body
      end

      Crystal::NilLiteral.new
    end
  when "each_with_index"
    interpret_check_args(node: object, uses_block: true) do
      block_arg = block.args[0]?
      index_arg = block.args[1]?

      object.elements.each_with_index do |elem, idx|
        interpreter.define_var(block_arg.name, elem) if block_arg
        interpreter.define_var(index_arg.name, Crystal::NumberLiteral.new idx) if index_arg
        interpreter.accept block.body
      end

      Crystal::NilLiteral.new
    end
  when "map"
    interpret_check_args(node: object, uses_block: true) do
      block_arg = block.args.first?

      klass.map(object.elements) do |elem|
        interpreter.define_var(block_arg.name, elem) if block_arg
        interpreter.accept block.body
      end
    end
  when "map_with_index"
    interpret_check_args(node: object, uses_block: true) do
      block_arg = block.args[0]?
      index_arg = block.args[1]?

      klass.map_with_index(object.elements) do |elem, idx|
        interpreter.define_var(block_arg.name, elem) if block_arg
        interpreter.define_var(index_arg.name, Crystal::NumberLiteral.new idx) if index_arg
        interpreter.accept block.body
      end
    end
  when "select"
    interpret_check_args(node: object, uses_block: true) do
      filter(object, klass, block, interpreter)
    end
  when "reject"
    interpret_check_args(node: object, uses_block: true) do
      filter(object, klass, block, interpreter, keep: false)
    end
  when "reduce"
    interpret_check_args(node: object, min_count: 0, uses_block: true) do |memo|
      accumulate_arg = block.args.first?
      value_arg = block.args[1]?

      if memo
        object.elements.reduce(memo) do |accumulate, elem|
          interpreter.define_var(accumulate_arg.name, accumulate) if accumulate_arg
          interpreter.define_var(value_arg.name, elem) if value_arg
          interpreter.accept block.body
        end
      else
        object.elements.reduce do |accumulate, elem|
          interpreter.define_var(accumulate_arg.name, accumulate) if accumulate_arg
          interpreter.define_var(value_arg.name, elem) if value_arg
          interpreter.accept block.body
        end
      end
    end
  when "shuffle"
    interpret_check_args(node: object) { klass.new(object.elements.shuffle) }
  when "sort"
    interpret_check_args(node: object) { klass.new(object.elements.sort { |x, y| x.interpret_compare(y) }) }
  when "sort_by"
    interpret_check_args(node: object, uses_block: true) do
      sort_by(object, klass, block, interpreter)
    end
  when "uniq"
    interpret_check_args(node: object) { klass.new(object.elements.uniq) }
  when "[]"
    interpret_check_args(node: object, min_count: 1) do |from, to|
      if to
        from = interpreter.accept(from)
        to = interpreter.accept(to)

        unless from.is_a?(Crystal::NumberLiteral)
          from.raise "expected first argument to RangeLiteral#[] to be a number, not #{from.class_desc}"
        end

        unless to.is_a?(Crystal::NumberLiteral)
          to.raise "expected second argument to RangeLiteral#[] to be a number, not #{from.class_desc}"
        end

        from = from.to_number.to_i
        to = to.to_number.to_i

        begin
          klass.new(object.elements[from, to])
        rescue ex
          object.raise ex.message
        end
      else
        case arg = from
        when Crystal::NumberLiteral
          index = arg.to_number.to_i
          object.elements[index]? || Crystal::NilLiteral.new
        when Crystal::RangeLiteral
          range = arg.interpret_to_nilable_range(interpreter)
          begin
            klass.new(object.elements[range])
          rescue ex
            object.raise ex.message
          end
        else
          arg.raise "argument to [] must be a number or range, not #{arg.class_desc}:\n\n#{arg}"
        end
      end
    end
  when "[]="
    interpret_check_args(node: object) do |index_node, value|
      unless index_node.is_a?(Crystal::NumberLiteral)
        index_node.raise "expected index argument to ArrayLiteral#[]= to be a number, not #{index_node.class_desc}"
      end

      index = index_node.to_number.to_i
      index += object.elements.size if index < 0

      unless 0 <= index < object.elements.size
        index_node.raise "index out of bounds (index: #{index}, size: #{object.elements.size})"
      end

      object.elements[index] = value
      value
    end
  when "unshift"
    interpret_check_args(node: object) do |arg|
      object.elements.unshift(arg)
      object
    end
  when "push", "<<"
    interpret_check_args(node: object) do |arg|
      object.elements << arg
      object
    end
  when "+"
    interpret_check_args(node: object) do |arg|
      case arg
      when Crystal::TupleLiteral then other_elements = arg.elements
      when Crystal::ArrayLiteral then other_elements = arg.elements
      else
        arg.raise "argument to `#{klass}#+` must be a tuple or array, not #{arg.class_desc}:\n\n#{arg}"
      end
      klass.new(object.elements + other_elements)
    end
  when "-"
    interpret_check_args(node: object) do |arg|
      case arg
      when Crystal::TupleLiteral then other_elements = arg.elements
      when Crystal::ArrayLiteral then other_elements = arg.elements
      else
        arg.raise "argument to `#{klass}#-` must be a tuple or array, not #{arg.class_desc}:\n\n#{arg}"
      end
      klass.new(object.elements - other_elements)
    end
  else
    nil
  end
end

# Checks the following in an invocation of a macro `foo`:
#
# * The number of macro arguments to `foo` matches the number of block
#   parameters to this macro. If `min_count` is given then only that many macro
#   parameters are required, others are optional and this macro's corresponding
#   block parameter will receive `nil` instead.
# * If `named_params` is true, any named arguments to `foo` are allowed. If it
#   is falsey (the default), no named arguments are allowed. Otherwise, only
#   named arguments included by `named_params` are allowed. The block parameters
#   of this macro are unaffected by named arguments.
# * There is a block supplied to `foo` if and only if `uses_block` is true.
#
# `top_level` affects how error messages are formatted.
#
# Accesses the `method`, `args`, `named_args`, and `block` variables in the
# current scope.
private macro interpret_check_args(*, node = self, min_count = nil, named_params = nil, uses_block = false, top_level = false, &block)
  {% if uses_block %}
    unless block
      %full_name = full_macro_name({{ node }}, method, {{ top_level }})
      {{ node }}.raise "#{%full_name} is expected to be invoked with a block, but no block was given"
    end
  {% else %}
    if block
      %full_name = full_macro_name({{ node }}, method, {{ top_level }})
      {{ node }}.raise "#{%full_name} is not expected to be invoked with a block, but a block was given"
    end
  {% end %}

  {% if !named_params %}
    if named_args && !named_args.empty?
      %full_name = full_macro_name({{ node }}, method, {{ top_level }})
      {{ node }}.raise "named arguments are not allowed here"
    end
  {% elsif named_params != true %}
    if named_args
      allowed_keys = {{ named_params }}
      named_args.each_key do |name|
        {{ node }}.raise "no named parameter '#{name}'" unless allowed_keys.includes?(name)
      end
    end
  {% end %}

  {% if min_count %}
    unless {{ min_count }} <= args.size <= {{ block.args.size }}
      %full_name = full_macro_name({{ node }}, method, {{ top_level }})
      {{ node }}.wrong_number_of_arguments %full_name, args.size, {{ min_count }}..{{ block.args.size }}
    end

    {% for var, i in block.args %}
      {{ var }} = args[{{ i }}]{% if i >= min_count %}?{% end %}
    {% end %}
  {% else %}
    unless args.size == {{ block.args.size }}
      %full_name = full_macro_name({{ node }}, method, {{ top_level }})
      {{ node }}.wrong_number_of_arguments %full_name, args.size, {{ block.args.size }}
    end

    {% for var, i in block.args %}
      {{ var }} = args[{{ i }}]
    {% end %}
  {% end %}

  {{ block.body }}
end

private macro interpret_check_args_toplevel(*, min_count = nil, uses_block = false, &block)
  method = node.name
  args = node.args
  named_args = node.named_args
  block = node.block
  interpret_check_args(node: node, min_count: {{ min_count }}, uses_block: {{ uses_block }}, top_level: true) {{ block }}
end

private def full_macro_name(node, method, top_level)
  if top_level
    "macro '::#{method}'"
  else
    "macro '#{node.class_desc}##{method}'"
  end
end

private def visibility_to_symbol(visibility)
  visibility_name =
    case visibility
    when .private?
      "private"
    when .protected?
      "protected"
    else
      "public"
    end
  Crystal::SymbolLiteral.new(visibility_name)
end

private def parse_generic_args_argument(node, method, named_args, *, default)
  case named_arg = named_args.try &.["generic_args"]?
  when Nil
    default
  when Crystal::BoolLiteral
    named_arg.value
  else
    named_arg.raise "named argument 'generic_args' to #{node.class_desc}##{method} must be a BoolLiteral, not #{named_arg.class_desc}"
  end
end

private def type_definition_generic_name(node, method, args, named_args, block)
  interpret_check_args(node: node, named_params: ["generic_args"]) do
    if parse_generic_args_argument(node, method, named_args, default: true) && (type_vars = node.type_vars)
      type_vars = type_vars.map_with_index do |type_var, i|
        param = Crystal::MacroId.new(type_var)
        param = Crystal::Splat.new(param) if i == node.splat_index
        param
      end
      Crystal::Generic.new(node.name, type_vars)
    else
      node.name
    end
  end
end

private def macro_raise(node, args, interpreter, exception_type)
  msg = args.map do |arg|
    arg.accept interpreter
    interpreter.last.to_macro_id
  end
  msg = msg.join " "

  node.raise msg, exception_type: exception_type
end

private def macro_warning(node, args, interpreter)
  msg = args.map do |arg|
    arg.accept interpreter
    interpreter.last.to_macro_id
  end
  msg = msg.join " "

  interpreter.warnings.add_warning_at(node.location, msg)

  Crystal::NilLiteral.new
end

private def empty_no_return_array
  Crystal::ArrayLiteral.new(of: Crystal::Path.global("NoReturn"))
end

private def filter(object, klass, block, interpreter, keep = true)
  block_arg = block.args.first?

  klass.new(object.elements.select do |elem|
    interpreter.define_var(block_arg.name, elem) if block_arg
    block_result = interpreter.accept(block.body).truthy?
    keep ? block_result : !block_result
  end)
end

private def fetch_annotation(node, method, args, named_args, block, &)
  interpret_check_args(node: node) do |arg|
    unless arg.is_a?(Crystal::TypeNode)
      args[0].raise "argument to '#{node.class_desc}#annotation' must be a TypeNode, not #{arg.class_desc}"
    end

    type = arg.type
    unless type.is_a?(Crystal::AnnotationType)
      args[0].raise "argument to '#{node.class_desc}#annotation' must be an annotation type, not #{type} (#{type.type_desc})"
    end

    value = yield type
    value || Crystal::NilLiteral.new
  end
end

private def fetch_annotations(node, method, args, named_args, block, &)
  interpret_check_args(node: node, min_count: 0) do |arg|
    unless arg
      return yield(nil) || Crystal::NilLiteral.new
    end

    unless arg.is_a?(Crystal::TypeNode)
      args[0].raise "argument to '#{node.class_desc}#annotation' must be a TypeNode, not #{arg.class_desc}"
    end

    type = arg.type
    unless type.is_a?(Crystal::AnnotationType)
      args[0].raise "argument to '#{node.class_desc}#annotation' must be an annotation type, not #{type} (#{type.type_desc})"
    end

    value = yield type
    value || Crystal::NilLiteral.new
  end
end

private def sort_by(object, klass, block, interpreter)
  block_arg = block.args.first?

  klass.new(object.elements.sort_by do |elem|
    block_arg.try { |arg| interpreter.define_var(arg.name, elem) }
    result = interpreter.accept(block.body)
    InterpretCompareWrapper.new(result)
  end)
end

private record InterpretCompareWrapper, node : Crystal::ASTNode do
  include Comparable(self)

  def <=>(other : self)
    node.interpret_compare(other.node)
  end
end
