require "../syntax"

module Crystal
  def self.format(source, filename = nil, report_warnings : IO? = nil, flags : Array(String)? = nil)
    Crystal::Formatter.format(source, filename: filename, report_warnings: report_warnings, flags: flags)
  end

  class Formatter < Visitor
    def self.format(source, filename = nil, report_warnings : IO? = nil, flags : Array(String)? = nil)
      parser = Parser.new(source)
      parser.filename = filename
      nodes = parser.parse

      # the formatter merely parses the same source again, it shouldn't
      # introduce any new syntax warnings the parser cannot find
      if report_warnings
        parser.warnings.report(report_warnings)
      end

      formatter = new(source, flags: flags)
      formatter.skip_space_or_newline
      nodes.accept formatter
      formatter.finish
    end

    record AlignInfo,
      id : UInt64,
      line : Int32,
      start_column : Int32,
      middle_column : Int32,
      end_column : Int32,
      number : Bool do
      def size
        end_column - start_column
      end
    end

    class CommentInfo
      property start_line : Int32
      property end_line : Int32
      property needs_newline : Bool
      property needs_format : Bool

      def initialize(@start_line : Int32, @needs_format : Bool)
        @end_line = @start_line
        @needs_newline = true
      end
    end

    record HeredocFix,
      start_line : Int32,
      end_line : Int32,
      difference : Int32

    record HeredocInfo,
      node : StringInterpolation,
      token : Token,
      line : Int32,
      column : Int32,
      indent : Int32,
      string_continuation : Int32 do
      include Lexer::HeredocItem
    end

    @lexer : Lexer
    @comment_columns : Array(Int32?)
    @indent : Int32
    @line : Int32
    @column : Int32
    @token : Token
    @output : IO::Memory
    @line_output : IO::Memory
    @wrote_newline : Bool
    @wrote_double_newlines : Bool
    @wrote_comment : Bool
    @macro_state : Token::MacroState
    @inside_macro : Int32
    @inside_cond : Int32
    @inside_lib : Int32
    @inside_struct_or_union : Int32
    @inside_enum : Int32
    @implicit_exception_handler_indent : Int32
    @last_write : String
    @exp_needs_indent : Bool
    @inside_def : Int32
    @when_infos : Array(AlignInfo)
    @hash_infos : Array(AlignInfo)
    @assign_infos : Array(AlignInfo)
    @doc_comments : Array(CommentInfo)
    @current_doc_comment : CommentInfo?
    @hash_in_same_line : Set(ASTNode)
    @shebang : Bool
    @heredoc_fixes : Array(HeredocFix)
    @assign_length : Int32?
    @current_hash : ASTNode?

    getter no_rstrip_lines
    property vars
    property inside_lib
    property inside_enum
    property inside_struct_or_union
    property indent
    property subformat_nesting = 0

    def initialize(source, @flags : Array(String)? = nil)
      @lexer = Lexer.new(source)
      @lexer.comments_enabled = true
      @lexer.count_whitespace = true
      @lexer.wants_raw = true
      @comment_columns = [nil] of Int32?
      @indent = 0
      @line = 0
      @column = 0
      @token = @lexer.next_token

      @output = IO::Memory.new(source.bytesize)
      @line_output = IO::Memory.new
      @wrote_newline = false
      @wrote_double_newlines = false
      @wrote_comment = false
      @macro_state = Token::MacroState.default
      @inside_macro = 0
      @inside_cond = 0
      @inside_lib = 0
      @inside_enum = 0
      @inside_struct_or_union = 0
      @implicit_exception_handler_indent = 0
      @last_write = ""
      @exp_needs_indent = true
      @inside_def = 0

      # When we parse a type, parentheses information is not stored in ASTs, unlike
      # for an Expressions node. So when we are printing a type (Path, ProcNotation, Union, etc.)
      # we increment this when we find a '(', and decrement it when we find ')', but
      # only if `paren_count > 0`: it might be the case of `def foo(x : A)`, but we don't
      # want to print that last ')' when printing the type A.
      @paren_count = 0

      # This stores the column number (if any) of each comment in every line
      @when_infos = [] of AlignInfo
      @hash_infos = [] of AlignInfo
      @assign_infos = [] of AlignInfo
      @doc_comments = [] of CommentInfo
      @current_doc_comment = nil
      @hash_in_same_line = Set(ASTNode).new.compare_by_identity
      @shebang = @token.type.comment? && @token.value.to_s.starts_with?("#!")
      @heredoc_fixes = [] of HeredocFix
      @last_is_heredoc = false
      @last_arg_is_skip = false
      @string_continuation = 0
      @inside_call_or_assign = 0
      @passed_backslash_newline = false

      # Lines that must not be rstripped (HEREDOC lines)
      @no_rstrip_lines = Set(Int32).new

      # Variables for when we format macro code without interpolation
      @vars = [Set(String).new]
    end

    def flag?(flag)
      !!@flags.try(&.includes?(flag))
    end

    def end_visit_any(node)
      case node
      when StringInterpolation
        # Nothing
      else
        @last_is_heredoc = false
      end
    end

    def visit(node : FileNode)
      true
    end

    def visit(node : Expressions)
      if node.expressions.size == 1 && @token.type.op_lparen?
        # If it's (...) with a single expression, we treat it
        # like a single expression, indenting it if needed
        write "("
        next_token_skip_space
        if @token.type.newline?
          next_token_skip_space_or_newline
          write_line
          write_indent(@indent + 2, node.expressions.first)
          skip_space_write_line
          skip_space_or_newline
          write_indent
          write_token :OP_RPAREN
          return false
        end
        skip_space_or_newline
        accept node.expressions.first
        skip_space
        if @token.type.newline?
          skip_space_or_newline
          write_line
          write_indent(@indent + 2)
        end
        skip_space_or_newline
        write ")"
        next_token
        return false
      end

      old_indent = @indent
      next_needs_indent = false

      has_newline = false
      has_paren = false
      has_begin = false

      empty_expressions = node.expressions.size == 1 && node.expressions[0].is_a?(Nop)

      if node.keyword.paren? && @token.type.op_lparen?
        write "("
        next_needs_indent = false
        has_paren = true
        wrote_newline = next_token_skip_space
        if @token.type.newline? || wrote_newline
          @indent += 2
          write_line unless wrote_newline
          next_token_skip_space_or_newline
          next_needs_indent = true
          has_newline = true
        end
      elsif node.keyword.begin? && @token.keyword?(:begin)
        write "begin"
        @indent += 2
        write_line
        next_token
        # Corner case: an empty `begin ... end`.
        # In this case, we should not skip space because it will do in the below loop.
        unless empty_expressions
          skip_space_or_newline
          if @token.type.op_semicolon?
            next_token_skip_space_or_newline
          end
        end
        has_begin = true
        next_needs_indent = true
        has_newline = true
      end

      last_aligned_assign = nil
      last_found_comment = false
      max_length = nil
      skip_space

      node.expressions.each_with_index do |exp, i|
        is_assign = assign?(exp)
        if is_assign && !last_aligned_assign
          last_aligned_assign, max_length = find_assign_chunk(node.expressions, exp, i + 1)
        else
          max_length = nil unless is_assign
        end

        if last?(i, node.expressions)
          needs_two_lines = false
        else
          next_exp = node.expressions[i + 1]
          needs_two_lines = needs_two_lines?(exp, next_exp)
        end

        @assign_length = max_length
        if next_needs_indent
          write_indent(@indent, exp)
        else
          indent(@indent, exp)
        end

        found_comment = skip_space

        if @token.type.op_semicolon?
          if needs_two_lines
            skip_semicolon_or_space_or_newline
          else
            found_comment = skip_semicolon_or_space
            if @token.type.newline?
              write_line
              next_token_skip_space
              next_needs_indent = true
            else
              write "; " unless last?(i, node.expressions) || found_comment
              skip_space_or_newline
              next_needs_indent = found_comment
            end
          end
        else
          next_needs_indent = true
        end

        unless @exp_needs_indent
          next_needs_indent = false
          @exp_needs_indent = true
        end

        if last?(i, node.expressions)
          last_found_comment = skip_space_or_newline last: true, next_comes_end: true
        else
          if needs_two_lines
            unless found_comment
              if @wrote_newline
                write_line unless @wrote_double_newlines
              elsif !@wrote_double_newlines
                write_line
                write_line
              end
              @wrote_double_newlines = true
              found_comment = skip_space_or_newline
              write_line unless found_comment || @wrote_double_newlines
            end
          else
            consume_newlines
          end
        end

        last_aligned_assign = nil if last_aligned_assign.same?(exp)
      end

      @indent = old_indent

      if has_newline && !last_found_comment && (!@wrote_newline || empty_expressions)
        # Right after the last expression but we didn't insert a newline yet
        # so we are still missing a newline following by an indent and the "end" keyword
        write_line
        write_indent
      elsif has_newline && last_found_comment && @wrote_newline
        # Right after the last expression and we did insert a newline (because of a comment)
        # so we are still missing an indent and the "end" keyword
        write_indent
      end

      if has_paren
        write_token :OP_RPAREN
      end

      if has_begin
        check_end
        next_token
        write "end"
      end

      false
    end

    def assign?(exp)
      case exp
      when Assign
        exp.target.is_a?(Path)
      when VisibilityModifier
        assign? exp.exp
      when Arg
        true
      else
        false
      end
    end

    def assign_length(exp)
      case exp
      when Assign
        assign_length exp.target
      when Arg
        exp.name.size
      when VisibilityModifier
        assign_length exp.exp
      when Path
        exp.names.first.size
      else
        0
      end
    end

    def find_assign_chunk(expressions, last, i)
      max_length = assign_length(last)

      while i < expressions.size
        exp = expressions[i]
        exp_location = exp.location
        break unless exp_location

        last_location = last.location
        break unless last_location
        break unless last_location.line_number + 1 == exp_location.line_number

        last = exp
        exp_length = assign_length(exp)
        max_length = exp_length if exp_length > max_length

        i += 1
      end

      {last, max_length}
    end

    def needs_two_lines?(node, next_node)
      return false if node.is_a?(Annotation) || node.is_a?(MacroIf)
      return false if abstract_def?(node) && abstract_def?(next_node)

      needs_two_lines?(node) || needs_two_lines?(next_node)
    end

    def abstract_def?(node)
      case node
      when Def
        node.abstract?
      when VisibilityModifier
        abstract_def? node.exp
      else
        false
      end
    end

    def needs_two_lines?(node)
      case node
      when Def, ClassDef, ModuleDef, LibDef, CStructOrUnionDef, Macro
        true
      when VisibilityModifier
        needs_two_lines? node.exp
      else
        false
      end
    end

    def visit(node : Nop)
      false
    end

    def visit(node : NilLiteral)
      write_keyword :nil

      false
    end

    def visit(node : BoolLiteral)
      check_keyword :false, :true
      write node.value
      next_token

      false
    end

    def visit(node : CharLiteral)
      check :CHAR
      write @token.raw
      next_token

      false
    end

    def visit(node : SymbolLiteral)
      check :SYMBOL
      write @token.raw
      next_token

      false
    end

    def visit(node : NumberLiteral)
      if @token.type.magic_line?
        write @token.type
        next_token
        return false
      end

      check :NUMBER
      write @token.raw
      next_token

      false
    end

    def visit(node : StringLiteral)
      column = @column

      if @token.type.magic_file? || @token.type.magic_dir?
        write @token.type
        next_token
        return false
      end

      check :DELIMITER_START
      is_regex = @token.delimiter_state.kind.regex?

      write @token.raw
      next_string_token

      while true
        case @token.type
        when .string?
          write_sanitized_string_body(@token.delimiter_state.allow_escapes && !is_regex)
          next_string_token
        when .interpolation_start?
          # This is the case of #{__DIR__}
          write "\#{"
          next_token_skip_space_or_newline
          indent(@column, node)
          skip_space_or_newline
          check :OP_RCURLY
          write "}"
          next_string_token
        when .delimiter_end?
          break
        else
          raise "Bug: unexpected token: #{@token.type}"
        end
      end

      write @token.raw
      format_regex_modifiers if is_regex

      if space_slash_newline?
        old_indent = @indent
        @indent = column if @string_continuation == 0
        @string_continuation += 1
        write " \\"
        write_line
        write_indent
        next_token_skip_space_or_newline
        visit(node)
        @indent = old_indent
        @string_continuation -= 1
      else
        next_token
      end

      false
    end

    private def write_sanitized_string_body(escape)
      body = @token.invalid_escape ? @token.value.as(String) : @token.raw
      body = Lexer.escape_forbidden_characters(body) if escape
      write body
    end

    def visit(node : StringInterpolation)
      if @token.delimiter_state.kind.heredoc?
        # For heredoc, only write the start: on a newline will print it
        @lexer.heredocs << {@token.delimiter_state, HeredocInfo.new(node, @token.dup, @line, @column, @indent, @string_continuation)}
        write @token.raw
        next_token
        return false
      end

      check :DELIMITER_START

      visit_string_interpolation(node, @token, @line, @column, @indent, @string_continuation)
    end

    def visit_string_interpolation(node, token, line, column, old_indent, old_string_continuation, wrote_token = false)
      @token = token

      is_regex = token.delimiter_state.kind.regex?
      indent_difference = token.column_number - (column + 1)

      write token.raw unless wrote_token
      next_string_token

      delimiter_state = token.delimiter_state
      is_heredoc = token.delimiter_state.kind.heredoc?
      @last_is_heredoc = is_heredoc

      heredoc_line = @line

      # To detect the first content of interpolation of string literal correctly,
      # we should consume the first string token if this token contains only removed indentation of heredoc.
      if is_heredoc && @token.type.string?
        token_is_indent = @token.raw.bytesize == node.heredoc_indent && @token.raw.each_char.all? &.ascii_whitespace?
        if token_is_indent
          write @token.raw
          next_string_token
        end
      end

      node.expressions.each do |exp|
        if @token.type.delimiter_end?
          # Heredoc cannot contain string continuation,
          # so we are done.
          break if is_heredoc

          # This is for " ... " \
          #     " ... "
          @indent = column if @string_continuation == 0
          @string_continuation += 1

          write @token.raw
          write " \\"
          write_line
          next_token_skip_space_or_newline
          check :DELIMITER_START
          write_indent
          write @token.raw
          next_string_token
        end

        if exp.is_a?(StringLiteral)
          # It might be #{__DIR__}, for example
          if @token.type.interpolation_start?
            write "\#{"
            delimiter_state = @token.delimiter_state
            next_token_skip_space_or_newline
            indent(@column, exp)
            skip_space_or_newline
            check :OP_RCURLY
            write "}"
            @token.delimiter_state = delimiter_state
            next_string_token
          else
            loop do
              check :STRING
              write_sanitized_string_body(delimiter_state.allow_escapes && !is_regex)
              next_string_token

              # On heredoc, pieces of contents are combined due to removing indentation.
              # Thus, we should consume continuous string tokens at once.
              break if !is_heredoc || !@token.type.string?
            end
          end
        else
          check :INTERPOLATION_START
          write "\#{"
          delimiter_state = @token.delimiter_state

          wrote_comment = next_token_skip_space
          has_newline = wrote_comment || @token.type.newline?
          skip_space_or_newline

          if has_newline
            write_line unless wrote_comment
            write_indent(@column + 2)
            indent(@column + 2, exp)
            wrote_comment = skip_space_or_newline
            write_line unless wrote_comment
          else
            indent(@column, exp)
          end

          skip_space_or_newline
          check :OP_RCURLY
          write "}"
          @token.delimiter_state = delimiter_state
          next_string_token
        end
      end

      heredoc_end = @line

      check :DELIMITER_END
      write @token.raw

      if is_heredoc
        if indent_difference > 0
          @heredoc_fixes << HeredocFix.new(heredoc_line, @line, indent_difference)
        end
        (heredoc_line...heredoc_end).each do |line|
          @no_rstrip_lines.add line
        end
        write_line
      end

      format_regex_modifiers if is_regex
      next_token

      @string_continuation = old_string_continuation
      @indent = old_indent unless is_heredoc

      false
    end

    private def consume_heredocs
      @consuming_heredocs = true
      @lexer.heredocs.reverse!
      while heredoc = @lexer.heredocs.pop?
        consume_heredoc(heredoc[0], heredoc[1].as(HeredocInfo))
      end
      @consuming_heredocs = false
    end

    private def consume_heredoc(delimiter_state, info)
      visit_string_interpolation(
        info.node,
        info.token,
        info.line,
        info.column,
        info.indent, info.string_continuation,
        wrote_token: true)
    end

    def visit(node : RegexLiteral)
      # Go back and tokenize again if slash is recognized as divide operator.
      # In this case, slash is tokenized on comment skipping (#4626).
      # However this slash must be a start delimiter of regex because
      # this is parsed as regex literal once before.
      if @token.type.op_slash?
        @lexer.reader.previous_char
        @lexer.column_number -= 1
        slash_is_regex!
        next_token
      end

      accept node.value

      false
    end

    def format_regex_modifiers
      while true
        char = @lexer.current_char
        case char
        when 'i', 'm', 'x'
          write char
          @lexer.next_char
        else
          break
        end
      end
    end

    def space_slash_newline?
      pos, line, col = @lexer.current_pos, @lexer.line_number, @lexer.column_number
      while true
        char = @lexer.current_char
        case char
        when ' ', '\t'
          @lexer.next_char
        when '\\'
          @lexer.current_pos = pos
          return true
        else
          break
        end
      end
      @lexer.current_pos = pos
      @lexer.line_number = line
      @lexer.column_number = col
      false
    end

    def space_newline?
      pos, line, col = @lexer.current_pos, @lexer.line_number, @lexer.column_number
      while true
        char = @lexer.current_char
        case char
        when ' ', '\t'
          @lexer.next_char
        when '\n'
          @lexer.current_pos = pos
          return true
        else
          break
        end
      end
      @lexer.current_pos = pos
      @lexer.line_number = line
      @lexer.column_number = col
      false
    end

    def visit(node : ArrayLiteral)
      case @token.type
      when .op_lsquare?
        format_literal_elements node.elements, :OP_LSQUARE, :OP_RSQUARE
      when .op_lsquare_rsquare?
        write "[]"
        next_token
      when .string_array_start?, .symbol_array_start?
        first = true
        write @token.raw
        count = 0
        while true
          has_space_newline = space_newline?
          if has_space_newline
            write_line
            if count == node.elements.size
              write_indent
            else
              write_indent(@indent + 2)
            end
          end
          next_string_array_token
          case @token.type
          when .string?
            write " " unless first || has_space_newline
            write @token.raw
            first = false
          when .string_array_end?
            write @token.raw
            next_token
            break
          else
            raise "Bug: unexpected token #{@token.type}"
          end
          count += 1
        end
        return false
      else
        name = node.name.not_nil!
        accept name
        skip_space
        format_literal_elements node.elements, :OP_LCURLY, :OP_RCURLY
      end

      if node_of = node.of
        write_keyword " ", :of, " "
        accept node_of
      end

      false
    end

    def visit(node : TupleLiteral)
      format_literal_elements node.elements, :OP_LCURLY, :OP_RCURLY
      false
    end

    def format_literal_elements(elements, prefix : Token::Kind, suffix : Token::Kind)
      slash_is_regex!
      write_token prefix
      has_newlines = false
      wrote_newline = false
      write_space_at_end = false
      next_needs_indent = false
      found_comment = false
      found_first_newline = false

      found_comment = skip_space
      if found_comment || @token.type.newline?
        # add one level of indentation for contents if a newline is present
        offset = @indent + 2
        start_column = @indent + 2

        if elements.empty?
          skip_space_or_newline(offset, last: true, at_least_one: true)
          write_token suffix
          return false
        end

        indent(offset) { consume_newlines }
        skip_space_or_newline
        wrote_newline = true
        next_needs_indent = true
        has_newlines = true
        found_first_newline = true
      else
        # indent contents at the same column as starting token if no newline
        offset = @indent
        start_column = @column
      end

      elements.each_with_index do |element, i|
        # This is to prevent writing `{{` and `{%`
        if prefix.op_lcurly? && i == 0 && !wrote_newline &&
           (@token.type.op_lcurly? || @token.type.op_lcurly_lcurly? || @token.type.op_lcurly_percent? ||
           @token.type.op_percent? || @token.raw.starts_with?("%"))
          write " "
          write_space_at_end = true
        end

        if next_needs_indent
          write_indent(offset, element)
        else
          indent(offset, element)
        end
        has_heredoc_in_line = !@lexer.heredocs.empty?

        last = last?(i, elements)

        found_comment = skip_space(offset, write_comma: (last || has_heredoc_in_line) && has_newlines)

        if @token.type.op_comma?
          if !found_comment && (!last || has_heredoc_in_line)
            write ","
            wrote_comma = true
          end

          slash_is_regex!
          next_token
          found_comment = skip_space(offset, write_comma: last && has_newlines)
          if @token.type.newline?
            if last && !found_comment && !wrote_comma
              write ","
              found_comment = true
            end
            indent(offset) { consume_newlines }
            skip_space_or_newline
            next_needs_indent = true
            has_newlines = true
            offset = start_column
          else
            if !last && !found_comment
              write " "
              next_needs_indent = false
            elsif found_comment
              next_needs_indent = true
              offset = start_column
            end
          end
        end
      end

      finish_list suffix, has_newlines, found_comment, found_first_newline, write_space_at_end
    end

    def visit(node : HashLiteral)
      if name = node.name
        accept name
        skip_space
      end

      old_hash = @current_hash
      @current_hash = node
      format_literal_elements node.entries, :OP_LCURLY, :OP_RCURLY
      @current_hash = old_hash

      if node_of = node.of
        write_keyword " ", :of, " "
        format_hash_entry nil, node_of
      end

      if @hash_in_same_line.includes? node
        @hash_infos.reject! { |info| info.id == node.object_id }
      end

      false
    end

    def accept(node : HashLiteral::Entry)
      format_hash_entry(@current_hash.not_nil!, node)
    end

    def format_hash_entry(hash, entry)
      start_line = @line
      start_column = @column
      found_in_same_line = false

      accept entry.key
      skip_space_or_newline
      middle_column = @column
      if @token.type.op_colon? && entry.key.is_a?(StringLiteral)
        write ": "
        slash_is_regex!
        next_token
        middle_column = @column
        found_in_same_line ||= check_hash_info hash, entry.key, start_line, start_column, middle_column
      else
        slash_is_regex!
        write_token " ", :OP_EQ_GT, " "
        found_in_same_line ||= check_hash_info hash, entry.key, start_line, start_column, middle_column
      end

      skip_space_or_newline
      accept entry.value

      if hash && found_in_same_line
        @hash_in_same_line << hash
      end
    end

    def visit(node : NamedTupleLiteral)
      old_hash = @current_hash
      @current_hash = node
      format_literal_elements node.entries, :OP_LCURLY, :OP_RCURLY
      @current_hash = old_hash

      if @hash_in_same_line.includes? node
        @hash_infos.reject! { |info| info.id == node.object_id }
      end

      false
    end

    def accept(node : NamedTupleLiteral::Entry)
      format_named_tuple_entry(@current_hash.not_nil!, node)
    end

    def format_named_tuple_entry(hash, entry)
      start_line = @line
      start_column = @column
      found_in_same_line = false
      format_named_argument_name(entry.key)
      slash_is_regex!
      write_token :OP_COLON, " "
      middle_column = @column
      found_in_same_line ||= check_hash_info hash, entry.key, start_line, start_column, middle_column
      skip_space_or_newline
      accept entry.value

      if found_in_same_line
        @hash_in_same_line << hash
      end
    end

    def format_named_argument_name(name)
      if @token.type.delimiter_start?
        StringLiteral.new(name).accept self
      else
        write @token
        @lexer.wants_symbol = false
        next_token
        @lexer.wants_symbol = true
      end
    end

    def finish_list(suffix : Token::Kind, has_newlines, found_comment, found_first_newline, write_space_at_end)
      if @token.type == suffix && !found_first_newline
        if @wrote_newline
          write_indent
        else
          write " " if write_space_at_end
        end
      else
        found_comment ||= skip_space_or_newline
        check suffix

        if @wrote_newline
          write_indent
        elsif has_newlines
          unless found_comment
            write ","
            write_line
          end
          write_indent
        elsif write_space_at_end
          write " "
        end
        skip_space_or_newline
      end

      write_token suffix
    end

    def check_hash_info(hash, key, start_line, start_column, middle_column)
      end_column = @column
      found_in_same_line = false
      if @line == start_line
        last_info = @hash_infos.last?
        if last_info && last_info.line == @line
          found_in_same_line = true
        elsif hash
          number = key.is_a?(NumberLiteral)
          @hash_infos << AlignInfo.new(hash.object_id, @line, start_column, middle_column, end_column, number)
        end
      end
      found_in_same_line
    end

    def visit(node : RangeLiteral)
      accept node.from
      skip_space
      write_token(node.exclusive? ? Token::Kind::OP_PERIOD_PERIOD_PERIOD : Token::Kind::OP_PERIOD_PERIOD)
      skip_space
      accept node.to
      false
    end

    def check_open_paren
      if @token.type.op_lparen?
        while @token.type.op_lparen?
          write "("
          next_token_skip_space
          @paren_count += 1
        end
        true
      else
        false
      end
    end

    def check_close_paren
      while @token.type.op_rparen? && @paren_count > 0
        @paren_count -= 1
        write_token :OP_RPAREN
      end
    end

    def visit(node : Path)
      check_open_paren

      # Sometimes the :: is not present because the parser generates ::Nil, for example
      if node.global? && @token.type.op_colon_colon?
        write "::"
        next_token_skip_space_or_newline
      end

      node.names.each_with_index do |name, i|
        skip_space_or_newline
        check :CONST
        write @token.value
        next_token
        skip_space unless last?(i, node.names)
        if @token.type.op_colon_colon?
          write "::"
          next_token
        end
      end

      check_close_paren

      false
    end

    def visit(node : Generic)
      check_open_paren

      name = node.name.as(Path)
      if name.global? && @token.type.op_colon_colon?
        write "::"
        next_token_skip_space_or_newline
      end

      if node.suffix.question?
        node.type_vars[0].accept self
        skip_space
        write_token :OP_QUESTION
        return false
      end

      # Check if it's T* instead of Pointer(T)
      if node.suffix.asterisk?
        # Count nesting asterisk
        asterisks = 1
        while (type_var = node.type_vars.first) && type_var.is_a?(Generic) && type_var.suffix.asterisk?
          node = type_var
          asterisks += 1
        end

        type_var = node.type_vars.first
        accept type_var
        skip_space_or_newline

        while asterisks > 0
          skip_space
          if @token.type.op_star_star? && asterisks >= 2
            write "**"
            next_token
            asterisks -= 2
          else
            write_token :OP_STAR
            asterisks -= 1
          end
        end

        return false
      end

      # Check if it's T[N] instead of StaticArray(T, N)
      if node.suffix.bracket?
        accept node.type_vars[0]
        skip_space_or_newline
        write_token :OP_LSQUARE
        skip_space_or_newline
        accept node.type_vars[1]
        skip_space_or_newline
        write_token :OP_RSQUARE
        return false
      end

      # NOTE: not `name.single_name?` as this is only for the expanded tuple literals
      first_name = name.names.first if name.global? && name.names.size == 1

      # Check if it's {A, B} instead of Tuple(A, B)
      if first_name == "Tuple" && @token.value != "Tuple"
        write_token :OP_LCURLY
        found_comment = skip_space_or_newline
        write_space_at_end = false
        node.type_vars.each_with_index do |type_var, i|
          # This is to prevent writing `{{` and `{%`
          if i == 0 && !found_comment && (@token.type.op_lcurly? || @token.type.op_lcurly_lcurly? || @token.type.op_lcurly_percent? || @token.type.op_percent? || @token.raw.starts_with?("%"))
            write " "
            write_space_at_end = true
          end
          accept type_var
          skip_space_or_newline
          if @token.type.op_comma?
            write ", " unless last?(i, node.type_vars)
            next_token_skip_space_or_newline
          end
          # Write space at end when write space for preventing writing `{{` and `{%` at first.
          write " " if last?(i, node.type_vars) && write_space_at_end
        end
        write_token :OP_RCURLY
        return false
      end

      # Check if it's {x: A, y: B} instead of NamedTuple(x: A, y: B)
      if first_name == "NamedTuple" && @token.value != "NamedTuple"
        write_token :OP_LCURLY
        skip_space_or_newline
        named_args = node.named_args.not_nil!
        named_args.each_with_index do |named_arg, i|
          accept named_arg
          skip_space_or_newline
          if @token.type.op_comma?
            write ", " unless last?(i, named_args)
            next_token_skip_space_or_newline
          end
        end
        write_token :OP_RCURLY
        return false
      end

      accept name
      skip_space_or_newline

      write_token :OP_LPAREN
      skip_space

      # Given that generic type arguments are always inside parentheses
      # we can start counting them from 0 inside them.
      old_paren_count = @paren_count
      @paren_count = 0

      if named_args = node.named_args
        has_newlines, _, _ = format_named_args([] of ASTNode, named_args, @indent + 2)
        # `format_named_args` doesn't skip trailing comma
        if @paren_count == 0 && @token.type.op_comma?
          next_token_skip_space_or_newline
          if has_newlines
            write ","
            write_line
            write_indent
          end
        end
      else
        skip_space_or_newline
        node.type_vars.each_with_index do |type_var, i|
          accept type_var
          if @paren_count == 0
            skip_space_or_newline
            if @token.type.op_comma?
              write ", " unless last?(i, node.type_vars)
              next_token_skip_space_or_newline
            end
          end
        end
      end

      skip_space_or_newline if @paren_count == 0
      write_token :OP_RPAREN

      # Restore the old parentheses count
      @paren_count = old_paren_count

      false
    ensure
      check_close_paren
    end

    def visit(node : Union)
      check_open_paren

      if @token.type.ident? && @token.value == "self?" && node.types.size == 2 &&
         node.types[0].is_a?(Self) && node.types[1].to_s == "::Nil"
        write "self?"
        next_token
        check_close_paren
        return false
      end

      column = @column
      node.types.each_with_index do |type, i|
        if @token.type.op_question?
          # This can happen if it's a nilable type written like T?
          write "?"
          next_token
          break
        end

        accept type

        last = last?(i, node.types)
        if last
          skip_space
        else
          skip_space_or_newline
        end

        while true
          case @token.type
          when .op_bar?
            write " | "
            next_token_skip_space
            if @token.type.newline?
              write_line
              write_indent(column)
              next_token_skip_space_or_newline
            end
          when .op_rparen?
            if @paren_count > 0
              @paren_count -= 1
              write ")"
              next_token_skip_space
            else
              break
            end
          else
            break
          end
        end
      end

      check_close_paren

      false
    end

    def visit(node : If)
      if node.ternary?
        accept node.cond
        skip_space_or_newline
        write_token " ", :OP_QUESTION, " "
        skip_space_or_newline
        accept node.then
        skip_space_or_newline
        write_token " ", :OP_COLON, " "
        skip_space_or_newline
        accept node.else
        return false
      end

      visit_if_or_unless node, :if
    end

    def visit(node : Unless)
      visit_if_or_unless node, :unless
    end

    def visit_if_or_unless(node, keyword : Keyword)
      if !@token.keyword?(keyword) && node.else.is_a?(Nop)
        # Suffix if/unless
        accept node.then
        write_keyword " ", keyword, " "
        inside_cond do
          indent(@column, node.cond)
        end
        return false
      end

      write_keyword keyword, " "
      format_if_at_cond node, keyword

      false
    end

    def format_if_at_cond(node, keyword : Keyword, check_end = true)
      inside_cond do
        indent(@column, node.cond)
      end

      skip_space(@indent + 2)
      skip_semicolon
      format_nested node.then
      skip_space_or_newline(@indent + 2, last: true)
      jump_semicolon

      node_else = node.else

      if @token.keyword?(:else)
        write_indent
        write "else"
        next_token
        skip_space(@indent + 2)
        skip_semicolon
        format_nested node.else
      elsif node_else.is_a?(If) && @token.keyword?(:elsif)
        format_elsif node_else, keyword
      end

      if check_end
        format_end @indent
      end
    end

    def format_elsif(node_else, keyword : Keyword)
      write_indent
      write "elsif "
      next_token_skip_space_or_newline
      format_if_at_cond node_else, keyword, check_end: false
    end

    def visit(node : While)
      format_while_or_until node, :while
    end

    def visit(node : Until)
      format_while_or_until node, :until
    end

    def format_while_or_until(node, keyword : Keyword)
      write_keyword keyword, " "
      inside_cond do
        indent(@column, node.cond)
      end

      format_nested_with_end node.body

      false
    end

    def format_nested(node, indent = @indent, write_end_line = true, write_indent = true)
      slash_is_regex!
      if node.is_a?(Nop)
        skip_space_write_line
      else
        if write_indent
          indent(indent + 2) do
            skip_space_write_line
            skip_space_or_newline
            write_indent(indent + 2, node)
            skip_space_write_line if write_end_line
          end
        else
          skip_space_write_line
          skip_space_or_newline
          accept node
          skip_space_write_line if write_end_line
        end
      end
    end

    def format_nested_with_end(node, column = @indent, write_end_line = true)
      skip_space(column + 2)

      if @token.type.op_semicolon?
        if node.is_a?(Nop)
          skip_semicolon_or_space_or_newline
          check_end
          write "; end"
          next_token
          return false
        else
          next_token_skip_space
        end
      end

      format_nested node, column, write_end_line: write_end_line
      format_end(column)
    end

    def format_end(column)
      skip_space_or_newline(column + 2, last: true)
      check_end
      write_indent(column)
      write "end"
      next_token
    end

    def visit(node : Def)
      @implicit_exception_handler_indent = @indent
      @inside_def += 1
      @vars.push Set(String).new

      write_keyword :abstract, " " if node.abstract?

      write_keyword :def, " ", skip_space_or_newline: false

      if receiver = node.receiver
        skip_space_or_newline
        accept receiver
        skip_space_or_newline
        write_token :OP_PERIOD
      end

      @lexer.wants_def_or_macro_name do
        skip_space_or_newline
      end

      write node.name

      indent do
        next_token

        # this formats `def foo # ...` to `def foo(&) # ...` for yielding
        # methods before consuming the comment line
        if node.block_arity && node.args.empty? && !node.block_arg && !node.double_splat
          write "(&)"
        end

        skip_space consume_newline: false
        next_token_skip_space if @token.type.op_eq?
      end

      to_skip = format_def_args node

      if return_type = node.return_type
        skip_space
        write_token " ", :OP_COLON, " "
        skip_space_or_newline
        accept return_type
      end

      if free_vars = node.free_vars
        skip_space_or_newline
        write " forall "
        next_token
        last_index = free_vars.size - 1
        free_vars.each_with_index do |free_var, i|
          skip_space_or_newline
          check :CONST
          write free_var
          next_token
          skip_space_or_newline if last_index != i
          if @token.type.op_comma?
            write ", "
            next_token_skip_space_or_newline
          end
        end
      end

      body = remove_to_skip node, to_skip

      unless node.abstract?
        format_nested_with_end body
      end

      @vars.pop
      @inside_def -= 1

      false
    end

    def format_def_args(node : Def | Macro)
      yields = node.is_a?(Def) && !node.block_arity.nil?
      format_def_args node.args, node.block_arg, node.splat_index, false, node.double_splat, yields
    end

    def format_def_args(args : Array, block_arg, splat_index, variadic, double_splat, yields)
      # If there are no args, remove extra "()"
      if args.empty? && !block_arg && !double_splat && !variadic
        if @token.type.op_lparen?
          next_token_skip_space_or_newline
          check :OP_RPAREN
          next_token
        end
        return 0
      end

      # Count instance variable arguments. See `at_skip?`.
      to_skip = 0

      wrote_newline = false
      found_first_newline = false

      old_indent = @indent
      @indent = @column + 1

      write_token :OP_LPAREN
      skip_space

      # When "(" follows newline, it turns on two spaces indentation mode.
      if @token.type.newline?
        @indent = old_indent + 2
        found_first_newline = true
        wrote_newline = true

        write_line
        next_token_skip_space_or_newline
      end

      args.each_with_index do |arg, i|
        has_more = !last?(i, args) || double_splat || block_arg || yields || variadic
        wrote_newline = format_def_arg(wrote_newline, has_more, found_first_newline && !has_more) do
          if i == splat_index
            write_token :OP_STAR
            skip_space_or_newline
            next if arg.external_name.empty? # skip empty splat argument.
          end

          format_parameter_annotations(arg)

          arg.accept self
          to_skip += 1 if @last_arg_is_skip
        end
      end

      if double_splat
        wrote_newline = format_def_arg(wrote_newline, block_arg || yields, found_first_newline) do
          write_token :OP_STAR_STAR
          skip_space_or_newline

          to_skip += 1 if at_skip?
          double_splat.accept self
        end
      end

      if block_arg
        wrote_newline = format_def_arg(wrote_newline, false) do
          format_parameter_annotations(block_arg)
          write_token :OP_AMP
          skip_space_or_newline

          to_skip += 1 if at_skip?
          block_arg.accept self
        end
      elsif yields
        wrote_newline = format_def_arg(wrote_newline, false) do
          write "&"
          skip_space_or_newline
        end
      end

      if variadic
        wrote_newline = format_def_arg(wrote_newline, false) do
          write_token :OP_PERIOD_PERIOD_PERIOD
        end
      end

      if found_first_newline && !wrote_newline
        write_line
        wrote_newline = true
      end
      write_indent(found_first_newline ? old_indent : @indent) if wrote_newline
      write_token :OP_RPAREN

      @indent = old_indent

      to_skip
    end

    private def format_parameter_annotations(node)
      return unless (anns = node.parsed_annotations)

      anns.each do |ann|
        ann.accept self

        skip_space

        if @token.type.newline?
          write_line
          write_indent
        else
          write " "
        end

        skip_space_or_newline
      end

      if @token.type.newline?
        skip_space_or_newline
        write_line
        write_indent
      end
    end

    def format_def_arg(wrote_newline, has_more, write_trailing_comma = false, &)
      write_indent if wrote_newline

      yield

      # Write "," before skipping spaces to prevent inserting comment between argument and comma.
      write "," if has_more || (wrote_newline && @token.type.op_comma?) || write_trailing_comma

      just_wrote_newline = skip_space
      if @token.type.newline?
        if has_more
          consume_newlines
          just_wrote_newline = true
        else
          # `last: true` is needed to write newline and comment only if comment is found.
          just_wrote_newline = skip_space_or_newline(last: true)
        end
      end

      if @token.type.op_comma?
        found_comment = next_token_skip_space
        if found_comment
          just_wrote_newline = true
        elsif @token.type.newline?
          if has_more && !just_wrote_newline
            consume_newlines
            just_wrote_newline = true
          else
            just_wrote_newline |= skip_space_or_newline(last: true)
          end
        else
          write " " if has_more && !just_wrote_newline
        end
      elsif @token.type.op_rparen? && has_more && !just_wrote_newline
        # if we found a `)` and there are still more parameters to write, it
        # must have been a missing `&` for a def that yields
        write " "
      end

      just_wrote_newline
    end

    # The parser transforms `def foo(@x); end` to `def foo(x); @x = x; end` so if we
    # find an instance var we later need to skip the first expressions in the body
    def at_skip?
      @token.type.instance_var? || @token.type.class_var?
    end

    def visit(node : FunDef)
      write_keyword :fun, " "

      check :IDENT, :CONST
      write node.name
      next_token_skip_space

      if @token.type.op_eq?
        write " = "
        next_token_skip_space

        if @token.type.newline?
          write_line
          next_token_skip_space_or_newline
          write_indent(@indent + 2)
        end

        if @token.type.delimiter_start?
          indent(@column, StringLiteral.new(node.real_name))
        else
          write node.real_name
          next_token_skip_space
        end
      end

      format_def_args node.args, nil, nil, node.varargs?, nil, false

      if return_type = node.return_type
        skip_space
        write_token " ", :OP_COLON, " "
        skip_space_or_newline
        accept return_type
      end

      if body = node.body
        format_nested_with_end body
      end

      false
    end

    def visit(node : Macro)
      reset_macro_state

      macro_node_line = @line

      write_keyword :macro, " "

      write node.name
      next_token

      if @token.type.op_eq? && node.name.ends_with?('=')
        next_token
      end

      skip_space(consume_newline: false)

      format_def_args node

      if macro_literal_source = macro_literal_contents(node.body)
        format_macro_literal_only(node, macro_literal_source, macro_node_line)
      else
        format_macro_body node
      end

      false
    end

    private def format_macro_literal_only(node, source, macro_node_line)
      # Only format the macro contents if it's valid Crystal code
      Parser.new(source).parse

      formatter, value = subformat(source)

      # The formatted contents might have heredocs for which we must preserve
      # trailing spaces, so here we copy those from the formatter we used
      # to format the contents to this formatter (we add one because we insert
      # a newline before the contents).
      formatter.no_rstrip_lines.each do |line|
        @no_rstrip_lines.add(macro_node_line + line + 1)
      end

      write_line
      write value

      next_macro_token

      until @token.type.macro_end?
        next_macro_token
      end

      skip_space_or_newline
      check :MACRO_END
      write_indent
      write "end"
      next_token
    rescue ex : Crystal::SyntaxException
      format_macro_body node
    end

    def format_macro_body(node)
      if @token.keyword?(:end)
        return format_macro_end
      end

      next_macro_token

      if @token.type.macro_end?
        return format_macro_end
      end

      body = node.body
      if body.is_a?(Expressions) && body.expressions.empty?
        while !@token.type.macro_end?
          next_macro_token
        end
        return format_macro_end
      end

      inside_macro do
        no_indent do
          format_nested body, write_end_line: false, write_indent: false
        end
      end

      skip_space_or_newline
      check :MACRO_END
      write "end"
      next_token
    end

    def format_macro_end
      write_line
      write_indent
      write "end"
      next_token
      false
    end

    def visit(node : MacroLiteral)
      line = @line
      @token.raw.scan("\n") do
        line -= 1
        @no_rstrip_lines.add line
      end

      raw = @token.raw

      # If the macro literal has a backlash, but we are subformatting
      # a macro, we need to escape it (if it got here unescaped it was escaped to
      # begin with.)
      if @subformat_nesting > 0
        raw = raw.gsub("\\", "\\" * (@subformat_nesting + 1))
      end

      write raw
      next_macro_token
      false
    end

    def visit(node : MacroVerbatim)
      reset_macro_state

      # `{% verbatim %}`
      if inside_macro?
        check :MACRO_CONTROL_START
      else
        check :OP_LCURLY_PERCENT
      end
      write "{%"
      next_token_skip_space_or_newline
      check_keyword :verbatim
      write " verbatim"
      next_token_skip_space
      check_keyword :do
      write " do"
      next_token_skip_space
      check :OP_PERCENT_RCURLY
      write " %}"

      @macro_state.control_nest += 1
      check_macro_whitespace
      next_macro_token
      inside_macro { no_indent node.exp }
      @macro_state.control_nest -= 1

      # `{% end %}`
      check :MACRO_CONTROL_START
      write "{%"
      next_token_skip_space_or_newline
      check_keyword :end
      write " end"
      next_token_skip_space
      check :OP_PERCENT_RCURLY
      write " %}"

      if inside_macro?
        check_macro_whitespace
        next_macro_token
      else
        next_token
      end

      false
    end

    def visit(node : MacroExpression)
      reset_macro_state

      old_column = @column

      if node.output?
        if inside_macro?
          check :MACRO_EXPRESSION_START
        else
          check :OP_LCURLY_LCURLY
        end
        write_macro_slashes
        write "{{"
      else
        case @token.type
        when .macro_control_start?, .op_lcurly_percent?
          # OK
        else
          check :MACRO_CONTROL_START
        end
        write_macro_slashes
        write "{%"
      end
      macro_state = @macro_state
      next_token

      has_space = @token.type.space?
      skip_space
      has_newline = @token.type.newline?
      skip_space_or_newline

      if (has_space || !node.output?) && !has_newline
        write " "
      end

      old_indent = @indent
      @indent = @column
      if has_newline
        write_line
        write_indent
      end

      indent(@column, node.exp)

      @indent = old_indent

      skip_space_or_newline
      @macro_state = macro_state

      if node.output?
        if @wrote_newline
          write_indent(old_column)
        elsif has_space && !has_newline
          write " "
        elsif has_newline
          write_line
          write_indent(old_column)
        end
        check :OP_RCURLY
        next_token
        check :OP_RCURLY
        write "}}"
      else
        check :OP_PERCENT_RCURLY
        if @wrote_newline
          write_indent(old_column)
        elsif has_newline
          write_line
          write_indent(old_column)
        else
          write " "
        end
        write "%}"
      end

      if inside_macro?
        check_macro_whitespace
        next_macro_token
      else
        next_token
      end

      false
    end

    def visit(node : MacroIf)
      reset_macro_state

      if inside_macro?
        check :MACRO_CONTROL_START
      else
        check :OP_LCURLY_PERCENT
      end

      write_macro_slashes
      write "{% "

      next_token_skip_space_or_newline

      if @token.keyword?(:begin)
        # This is rewritten to `if true`
        write "begin"
        next_token
      elsif @token.keyword?(:unless)
        # This is rewritten to `if !...`
        node.then, node.else = node.else, node.then
        write "unless "
        next_token_skip_space_or_newline

        outside_macro { indent(@column, node.cond) }
      else
        write_keyword :if, " "
        outside_macro { indent(@column, node.cond) }
      end

      format_macro_if_epilogue(node, @macro_state)
    end

    def format_macro_if_epilogue(node, macro_state, check_end = true)
      skip_space_or_newline
      check :OP_PERCENT_RCURLY
      write " %}"

      @macro_state = macro_state
      @macro_state.control_nest += 1
      check_macro_whitespace

      macro_node_line = @line
      next_macro_token
      format_macro_contents(node.then, macro_node_line)

      unless node.else.is_a?(Nop)
        check :MACRO_CONTROL_START
        next_token_skip_space_or_newline

        if @token.keyword?(:elsif)
          sub_if = node.else.as(MacroIf)
          next_token_skip_space_or_newline
          write_macro_slashes
          write "{% elsif "
          outside_macro { indent(@column, sub_if.cond) }
          format_macro_if_epilogue sub_if, macro_state, check_end: false
        else
          check_keyword :else
          next_token_skip_space_or_newline
          check :OP_PERCENT_RCURLY

          write_macro_slashes
          write "{% else %}"

          @macro_state = macro_state
          @macro_state.control_nest += 1
          check_macro_whitespace

          macro_node_line = @line
          next_macro_token
          format_macro_contents(node.else, macro_node_line)
        end
      end

      @macro_state = macro_state
      if check_end
        check :MACRO_CONTROL_START
        next_token_skip_space_or_newline

        check_end
        next_token_skip_space_or_newline
        check :OP_PERCENT_RCURLY

        write_macro_slashes
        write "{% end %}"

        if inside_macro?
          check_macro_whitespace
          next_macro_token
        else
          next_token
        end
      end

      false
    end

    def visit(node : MacroFor)
      reset_macro_state
      old_macro_state = @macro_state

      if inside_macro?
        check :MACRO_CONTROL_START
      else
        check :OP_LCURLY_PERCENT
      end

      write_macro_slashes
      write "{% "

      next_token_skip_space_or_newline

      write_keyword :for, " "

      outside_macro do
        node.vars.each_with_index do |var, i|
          no_indent var
          unless last?(i, node.vars)
            skip_space_or_newline
            if @token.type.op_comma?
              write ", "
              next_token_skip_space_or_newline
            end
          end
        end
      end

      write_keyword " ", :in, " "

      outside_macro { indent(@column, node.exp) }
      skip_space_or_newline

      check :OP_PERCENT_RCURLY
      write " %}"

      @macro_state.control_nest += 1
      check_macro_whitespace

      macro_node_line = @line
      next_macro_token
      format_macro_contents(node.body, macro_node_line)

      @macro_state = old_macro_state

      check :MACRO_CONTROL_START
      next_token_skip_space_or_newline

      check_end
      next_token_skip_space_or_newline
      check :OP_PERCENT_RCURLY

      write_macro_slashes
      write "{% end %}"

      if inside_macro?
        check_macro_whitespace
        next_macro_token
      else
        next_token
      end

      false
    end

    def visit(node : MacroVar)
      check :MACRO_VAR
      write "%"
      write node.name

      if exps = node.exps
        next_token
        write_token :OP_LCURLY
        skip_space_or_newline
        exps.each_with_index do |exp, i|
          indent(@column, exp)
          skip_space_or_newline
          if @token.type.op_comma?
            write ", " unless last?(i, exps)
            next_token_skip_space_or_newline
          end
        end
        check :OP_RCURLY
        write "}"
      end

      next_macro_token

      false
    end

    # If we are formatting macro contents, if there are nested macro
    # control structures they are definitely escaped with `\`,
    # because otherwise we wouldn't be able to format the contents.
    # So here we append those slashes. In theory the nesting can be
    # very deep but it's usually just one level.
    private def write_macro_slashes
      @subformat_nesting.times do
        write "\\"
      end
    end

    def format_macro_contents(node, macro_node_line)
      # If macro contents don't have interpolations nor newlines, and we
      # are at the top-level (not already inside a macro) then the content
      # must be a valid Crystal expression and we can format it.
      #
      # For example:
      #
      # {% if flag?(:foo) %}
      #   puts "This is an expression that we can format just fine"
      # {% end %}
      if !inside_macro? && (value = macro_literal_contents(node)) && value.includes?("\n")
        # Format the value and append 2 more spaces of indentation
        begin
          formatter, value = subformat(value)
        rescue ex : Crystal::SyntaxException
          raise Crystal::SyntaxException.new(
            ex.message,
            ex.line_number + macro_node_line,
            ex.column_number,
            ex.filename,
            ex.size)
        end

        # The formatted contents might have heredocs for which we must preserve
        # trailing spaces, so here we copy those from the formatter we used
        # to format the contents to this formatter (we add one because we insert
        # a newline before the contents).
        formatter.no_rstrip_lines.each do |line|
          @no_rstrip_lines.add(macro_node_line + line + 1)
        end

        write_line
        write value
        # No need to append a newline because the formatter value
        # will already have it.
        write_indent

        increment_lines(macro_node_line + value.lines.size + 1 - @line)

        line = @line

        # We have to potentially skip multiple macro literal tokens
        while @token.type.macro_literal?
          next_macro_token
        end

        # Skipping the macro literal tokens might have altered `@line`:
        # restore it to what it was before the macro tokens (we are
        # already accounting for the lines in a different way).
        if @line != line
          increment_lines(line - @line)
        end
      else
        inside_macro { no_indent node }
      end
    end

    # Returns the node's String contents if it's composed entirely
    # by MacroLiteral: either a MacroLiteral or an Expression composed
    # only by MacroLiteral.
    private def macro_literal_contents(node) : String?
      return unless only_macro_literal?(node)

      extract_macro_literal_contents(node)
    end

    private def only_macro_literal?(node)
      case node
      when MacroLiteral
        true
      when Expressions
        node.expressions.all? do |exp|
          only_macro_literal?(exp)
        end
      else
        false
      end
    end

    private def extract_macro_literal_contents(node)
      String.build do |io|
        extract_macro_literal_contents(node, io)
      end
    end

    private def extract_macro_literal_contents(node, io)
      if node.is_a?(MacroLiteral)
        io << node.value
      else
        node.as(Expressions).expressions.each do |exp|
          extract_macro_literal_contents(exp, io)
        end
      end
    end

    def subformat(source)
      if @inside_struct_or_union > 0
        mode = Parser::ParseMode::LibStructOrUnion
      elsif @inside_enum < 0
        mode = Parser::ParseMode::Enum
      elsif @inside_lib > 0
        mode = Parser::ParseMode::Lib
      else
        mode = Parser::ParseMode::Normal
      end

      parser = Parser.new(source, var_scopes: @vars.clone)
      # parser.filename = formatter.filename
      nodes = parser.parse(mode)

      formatter = Formatter.new(source)
      formatter.inside_lib = @inside_lib
      formatter.inside_enum = @inside_enum
      formatter.inside_struct_or_union = @inside_struct_or_union
      formatter.indent = @indent + 2
      formatter.skip_space_or_newline
      formatter.write_indent
      formatter.subformat_nesting = @subformat_nesting + 1
      nodes.accept formatter
      {formatter, formatter.finish}
    end

    def visit(node : Arg)
      @last_arg_is_skip = false

      restriction = node.restriction
      default_value = node.default_value

      if @inside_lib > 0
        # This is the case of `fun foo(Char)`
        if !@token.type.ident? && restriction
          accept restriction
          return false
        end
      end

      if node.name.empty?
        skip_space_or_newline
      else
        @vars.last.add(node.name)

        at_skip = at_skip?

        if !at_skip && node.external_name != node.name
          if node.external_name.empty?
            write "_"
          elsif @token.type.delimiter_start?
            accept StringLiteral.new(node.external_name)
          else
            write @token.value
          end
          write " "
          next_token_skip_space_or_newline
        end

        @last_arg_is_skip = at_skip?

        write @token.value
        next_token
      end

      if restriction
        skip_space_or_newline
        write_token " ", :OP_COLON, " "
        skip_space_or_newline
        accept restriction
      end

      if default_value
        # The default value might be a Proc with args, so
        # we need to remember this and restore it later
        old_last_arg_is_skip = @last_arg_is_skip

        skip_space_or_newline

        check_align = check_assign_length node
        write_token " ", :OP_EQ, " "
        before_column = @column
        skip_space_or_newline
        accept default_value
        check_assign_align before_column, default_value if check_align

        @last_arg_is_skip = old_last_arg_is_skip
      end

      # This is the case of an enum member
      if @token.type.op_semicolon?
        next_token
        @lexer.skip_space
        if @token.type.comment?
          write_comment
          @exp_needs_indent = true
        else
          write ";" if @token.type.const?
          write " "
          @exp_needs_indent = @token.type.newline?
        end
      end

      false
    end

    def reset_macro_state
      @macro_state = Token::MacroState.default unless inside_macro?
    end

    def visit(node : Splat)
      visit_splat node, :OP_STAR
    end

    def visit(node : DoubleSplat)
      visit_splat node, :OP_STAR_STAR
    end

    def visit_splat(node, token : Token::Kind)
      write_token token
      skip_space_or_newline
      accept node.exp
      false
    end

    def visit(node : ProcNotation)
      check_open_paren

      paren_count = @paren_count

      if inputs = node.inputs
        # Check if it's ((X, Y) -> Z)
        #                ^    ^
        sub_paren_count = @paren_count
        if check_open_paren
          sub_paren_count = @paren_count
        end

        inputs.each_with_index do |input, i|
          accept input
          if @paren_count == sub_paren_count
            skip_space_or_newline
            if @token.type.op_comma?
              write ", " unless last?(i, inputs)
              next_token_skip_space_or_newline
            end
          end
        end

        if sub_paren_count != paren_count
          check_close_paren
        end
      end

      skip_space_or_newline if paren_count == @paren_count
      check_close_paren
      skip_space

      write " " if inputs
      write_token :OP_MINUS_GT

      if output = node.output
        write " "
        skip_space_or_newline
        accept output
      else
        skip_space
      end

      check_close_paren

      false
    end

    def visit(node : Self)
      check_open_paren
      write_keyword :self
      check_close_paren
      false
    end

    def visit(node : Var)
      write node.name
      next_token
      false
    end

    def visit(node : InstanceVar)
      write node.name
      next_token
      false
    end

    def visit(node : ClassVar)
      write node.name
      next_token
      false
    end

    def visit(node : Global)
      write node.name
      next_token
      false
    end

    def visit(node : ReadInstanceVar)
      accept node.obj

      skip_space_or_newline
      write_token :OP_PERIOD
      skip_space_or_newline
      write node.name
      next_token

      false
    end

    def visit(node : Call)
      # This is the case of `...`
      if node.name == "`"
        accept node.args.first
        return false
      end

      special_call =
        case node.name
        when "as", "as?", "is_a?", "nil?", "responds_to?"
          true
        else
          false
        end

      obj = node.obj

      # Consider the case of `&.as(...)` and similar
      if obj.is_a?(Nop)
        obj = nil
      end

      # Consider the case of `as T`, that is, casting `self` without an explicit `self`
      if special_call && obj.is_a?(Var) && obj.name == "self" && !@token.keyword?(:self)
        obj = nil
      end

      column = @column
      # The indent for arguments and block belonging to this node.
      base_indent = @indent

      # Special case: $1, $2, ...
      if @token.type.global_match_data_index? && node.name.in?("[]", "[]?") && obj.is_a?(Global)
        write "$"
        write @token.value
        next_token
        return false
      end

      write_token :OP_COLON_COLON if node.global?

      if obj
        # This handles unary operators written in prefix notation.
        # The relevant distinction is that the call has a receiver and the
        # current token is not that object but a unary operator.
        if @token.type.unary_operator? && node.name == @token.type.to_s && node.args.empty?
          write @token.type
          next_token_skip_space_or_newline
          accept obj
          return false
        end

        accept obj

        passed_backslash_newline = @token.passed_backslash_newline

        if @token.type.space?
          needs_space = true
        else
          needs_space = node.name != "*" && node.name != "/" && node.name != "**" && node.name != "//"
        end

        slash_is_not_regex!
        skip_space

        # It's something like `foo.bar\n
        #                        .baz`
        if (@token.type.newline?) || @wrote_newline
          base_indent = @indent + 2
          indent(base_indent) { consume_newlines }
          write_indent(base_indent)
        end

        if !@token.type.op_period?
          # It's an operator
          if @token.type.op_lsquare?
            write "["
            next_token_skip_space

            args = node.args

            if node.name == "[]="
              last_arg = args.pop
            end

            has_newlines, found_comment, _ = format_args args, true, node.named_args
            if @token.type.op_comma? || @token.type.newline?
              if has_newlines
                write ","
                found_comment = next_token_skip_space
                write_line unless found_comment
                write_indent
                skip_space_or_newline
              else
                next_token_skip_space_or_newline
              end
            else
              found_comment = skip_space_or_newline
              write_indent if found_comment
            end

            # foo[&.bar]
            if (block = node.block) && @token.type.op_amp?
              has_args = !node.args.empty? || node.named_args
              write "," if has_args
              format_block(block, has_args)
            end

            write_token :OP_RSQUARE

            if node.name == "[]?"
              skip_space

              # This might not be present in the case of `x[y] ||= z`
              if @token.type.op_question?
                write "?"
                next_token
              end
            end

            if last_arg
              skip_space_or_newline

              write " ="
              next_token_skip_space
              accept_assign_value_after_equals last_arg
            end

            return false
          elsif @token.type.op_lsquare_rsquare?
            write "[]"
            next_token

            if node.name == "[]="
              skip_space_or_newline
              write_token " ", :OP_EQ, " "
              skip_space_or_newline
              inside_call_or_assign do
                accept node.args.last
              end
            end

            return false
          else
            write " " if needs_space && !passed_backslash_newline
            write node.name

            # This is the case of a-1 and a+1
            if @token.type.number?
              @lexer.current_pos = @token.start + 1
            end

            slash_is_regex!
          end

          next_token
          passed_backslash_newline = @token.passed_backslash_newline
          found_comment = skip_space

          if found_comment || @token.type.newline?
            if @inside_call_or_assign == 0
              next_indent = @indent + 2
            else
              next_indent = column == 0 ? 2 : column
            end
            indent(next_indent) do
              skip_space_write_line
              skip_space_or_newline
            end
            write_indent(next_indent, node.args.last)
          else
            write " " if needs_space && !passed_backslash_newline
            inside_call_or_assign do
              accept node.args.last
            end
          end

          return false
        end

        @lexer.wants_def_or_macro_name do
          next_token
        end
        skip_space

        if (@token.type.newline?) || @wrote_newline
          base_indent = @indent + 2
          indent(base_indent) { consume_newlines }
          write_indent(base_indent)
        end

        write "."

        skip_space_or_newline
      end

      # This is for foo &.[bar] and &.[bar]?, or foo.[bar] and foo.[bar]?
      if node.name.in?("[]", "[]?") && @token.type.op_lsquare?
        write "["
        next_token_skip_space_or_newline
        format_call_args(node, false, base_indent)
        skip_space_or_newline
        write_token :OP_RSQUARE
        write_token :OP_QUESTION if node.name == "[]?"
        return false
      end

      # This is for foo.[bar] = baz
      if node.name == "[]=" && @token.type.op_lsquare?
        write "["
        next_token_skip_space_or_newline
        args = node.args
        last_arg = args.pop
        format_call_args(node, true, base_indent)
        skip_space_or_newline
        write_token :OP_RSQUARE
        skip_space_or_newline
        write " ="
        next_token_skip_space
        accept_assign_value_after_equals last_arg
        return false
      end

      # This is for foo.[] = bar
      if node.name == "[]=" && @token.type.op_lsquare_rsquare?
        write_token :OP_LSQUARE_RSQUARE
        next_token_skip_space_or_newline
        write " ="
        next_token_skip_space
        accept_assign_value_after_equals node.args.last
        return false
      end

      assignment = Lexer.setter?(node.name)

      if assignment
        write node.name.rchop
      else
        write node.name
      end
      next_token

      passed_backslash_newline = @token.passed_backslash_newline

      if assignment
        skip_space

        next_token
        if @token.type.op_lparen?
          write "=("
          slash_is_regex!
          next_token
          format_call_args(node, true, base_indent)
          skip_space_or_newline
          write_token :OP_RPAREN
        else
          write " ="
          skip_space
          accept_assign_value_after_equals node.args.last
        end

        return false
      end

      has_parentheses = false
      ends_with_newline = false
      has_args = !node.args.empty? || node.named_args

      has_newlines = false
      found_comment = false

      # For special calls we want to format `.as (Int32)` into `.as(Int32)`
      # so we remove the space between "as" and "(".
      skip_space if special_call

      # If the call has a single argument which is a parenthesized `Expressions`,
      # we skip whitespace between the method name and the arg. The parenthesized
      # arg is transformed into a call with parenthesis: `foo (a)` becomes `foo(a)`.
      if node.args.size == 1 &&
         @token.type.space? &&
         !node.named_args && !node.block_arg && !node.block &&
         (expressions = node.args[0].as?(Expressions)) &&
         expressions.keyword.paren? && expressions.expressions.size == 1
        # ...except do not transform `foo ()` into `foo()`, as the former is
        # actually semantically equivalent to `foo(nil)`
        arg = expressions.expressions[0]
        unless arg.is_a?(Nop)
          skip_space
          node.args[0] = arg
        end
      end

      if @token.type.op_lparen?
        slash_is_regex!
        next_token

        # If it's something like `foo.bar()` we rewrite it as `foo.bar`
        # (parentheses are not needed). Also applies for special calls
        # like `nil?` when there might not be a receiver.
        if (obj || special_call) && !has_args && !node.block_arg && !node.block
          skip_space_or_newline
          check :OP_RPAREN
          next_token
          return false
        end

        write "("
        has_parentheses = true
        has_newlines, found_comment, _ = format_call_args(node, true, base_indent)
        found_comment ||= skip_space
        if @token.type.newline?
          ends_with_newline = true
        end
        indent(base_indent + 2) { skip_space_or_newline(last: true, at_least_one: ends_with_newline) }
      elsif has_args || node.block_arg
        write " " unless passed_backslash_newline
        skip_space
        has_newlines, found_comment, _ = format_call_args(node, false, base_indent)
      end

      if block = node.block
        needs_space = !has_parentheses || has_args
        block_indent = base_indent
        skip_space
        if has_parentheses && @token.type.op_comma?
          next_token
          wrote_newline = skip_space(block_indent, write_comma: true)
          if wrote_newline || @token.type.newline?
            unless wrote_newline
              next_token_skip_space_or_newline
              write ","
              write_line
            end
            needs_space = false
            block_indent += 2 if !@token.type.op_rparen? # foo(1, ↵  &.foo) case
            write_indent(block_indent)
          else
            write "," if !@token.type.op_rparen? # foo(1, &.foo) case
          end
        end
        if has_parentheses && @token.type.op_rparen?
          if ends_with_newline
            write_line unless found_comment || @wrote_newline
            write_indent
          end
          write ")"
          next_token_skip_space_or_newline
          indent(block_indent) { format_block block, needs_space }
          return false
        end
        indent(block_indent) { format_block block, needs_space }
        if has_parentheses
          skip_space
          if @token.type.newline?
            ends_with_newline = true
          end
          skip_space_or_newline
        end
      end

      if has_args || node.block_arg
        finish_args(has_parentheses, has_newlines, ends_with_newline, found_comment, base_indent)
      elsif has_parentheses
        skip_space_or_newline
        write_token :OP_RPAREN
      end

      false
    end

    def format_call_args(node : ASTNode, has_parentheses, base_indent)
      indent(base_indent) { format_args node.args, has_parentheses, node.named_args, node.block_arg }
    end

    def format_args(args : Array, has_parentheses, named_args = nil, block_arg = nil, needed_indent = @indent + 2, do_consume_newlines = false)
      has_newlines = false
      found_comment = false
      @inside_call_or_assign += 1

      unless args.empty?
        has_newlines, found_comment, needed_indent = format_args_simple(args, needed_indent, do_consume_newlines)
      end

      if named_args
        has_newlines, named_args_found_comment, needed_indent = format_named_args(args, named_args, needed_indent)
        found_comment = true if args.empty? && named_args_found_comment
      end

      if block_arg
        has_newlines = format_block_arg(block_arg, needed_indent)
      end

      @inside_call_or_assign -= 1

      {has_newlines, found_comment, needed_indent}
    end

    def format_args_simple(args, needed_indent, do_consume_newlines)
      has_newlines = false
      found_comment = false

      if @token.type.newline?
        if do_consume_newlines
          indent(needed_indent) { consume_newlines }
          skip_space_or_newline
        else
          write_line
          indent(needed_indent) { next_token_skip_space_or_newline }
        end
        next_needs_indent = true
        has_newlines = true
      end

      skip_space_or_newline
      args.each_with_index do |arg, i|
        if next_needs_indent
          write_indent(needed_indent, arg)
        else
          indent(@indent, arg)
        end
        next_needs_indent = false
        unless last?(i, args)
          if @last_is_heredoc && @token.type.newline?
            skip_space_or_newline
            write_indent
          else
            skip_space
          end
          slash_is_regex!
          write_token :OP_COMMA

          if @token.passed_backslash_newline
            write_line
            next_needs_indent = true
            has_newlines = true
          else
            found_comment = skip_space(needed_indent)
            if found_comment
              write_indent(needed_indent)
            else
              if @token.type.newline?
                indent(needed_indent) { consume_newlines }
                next_needs_indent = true
                has_newlines = true
              else
                write " "
              end
            end
          end
          skip_space_or_newline
        end
      end

      {has_newlines, found_comment, needed_indent}
    end

    def format_named_args(args, named_args, needed_indent)
      skip_space(needed_indent)

      named_args_column = needed_indent

      if args.empty?
      else
        write_token :OP_COMMA
        found_comment = skip_space(needed_indent)
        if found_comment || @token.type.newline?
          write_indent(needed_indent) unless @last_is_heredoc
        else
          write " "
        end
      end

      format_args named_args, false, needed_indent: named_args_column, do_consume_newlines: true
    end

    def format_block_arg(block_arg, needed_indent)
      skip_space_or_newline
      if @token.type.op_comma?
        write ","
        next_token_skip_space
        if @token.type.newline?
          write_line
          write_indent(needed_indent)
          has_newlines = true
        else
          write " "
        end
      end
      skip_space_or_newline
      write_token :OP_AMP
      skip_space_or_newline
      accept block_arg
      has_newlines
    end

    def finish_args(has_parentheses, has_newlines, ends_with_newline, found_comment, column)
      if has_parentheses
        if @token.type.op_comma?
          next_token
          found_comment |= skip_space(column + 2, write_comma: true)
          if @token.type.newline? && has_newlines
            write ","
            write_line
            skip_space_or_newline(column + 2)
            write_indent(column)
            skip_space_or_newline(column)
          else
            found_comment |= skip_space_or_newline(column + 2)
            if has_newlines
              unless found_comment
                write ","
                write_line
              end
              write_indent(column)
            end
          end
        elsif found_comment
          write_indent(column)
        end
        check :OP_RPAREN

        if ends_with_newline
          write_line unless @wrote_newline
          write_indent(column)
        end
        write ")"
        next_token
      end
    end

    def format_parenthesized_args(args, named_args = nil)
      write "("
      next_token_skip_space
      has_newlines, found_comment, _ = format_args args, true, named_args: named_args
      skip_space
      ends_with_newline = false
      if @token.type.newline?
        ends_with_newline = true
        next_token
      end
      skip_space_or_newline
      finish_args(true, has_newlines, ends_with_newline, found_comment, @indent)
    end

    def visit(node : NamedArgument)
      format_named_argument_name(node.name)
      skip_space_or_newline
      write_token :OP_COLON, " "

      slash_is_regex!

      skip_space_or_newline
      accept node.value

      false
    end

    def format_block(node, needs_space)
      needs_comma = false
      old_inside_call_or_assign = @inside_call_or_assign
      @inside_call_or_assign = 0

      comma_before_comment = false

      if @token.type.op_comma?
        next_token
        next_token if @token.type.space?
        if @token.type.comment?
          write ","
          needs_comma = false
          comma_before_comment = true
          @indent += 2
        else
          needs_comma = true
        end
        skip_space_or_newline
        @indent -= 2 if comma_before_comment
      end

      if @token.keyword?(:do)
        if comma_before_comment
          @indent += 2
          write_indent
        else
          write " "
        end
        write "do"
        next_token
        skip_space(@indent + 2)
        body = format_block_args node.args, node
        old_implicit_exception_handler_indent, @implicit_exception_handler_indent = @implicit_exception_handler_indent, @indent
        format_nested_with_end body
        @implicit_exception_handler_indent = old_implicit_exception_handler_indent
        @indent -= 2
      elsif @token.type.op_lcurly?
        write "," if needs_comma
        write " {"
        next_token_skip_space
        body = format_block_args node.args, node
        next_token_skip_space_or_newline if @token.type.op_semicolon?
        if @token.type.newline?
          format_nested body
          skip_space_or_newline
          write_indent
        else
          unless body.is_a?(Nop)
            write " "
            accept body
          end
          skip_space_or_newline
          write " "
        end
        write_token :OP_RCURLY
      else
        # It's foo &.bar
        write "," if needs_comma
        write " " if needs_space
        write_token :OP_AMP
        skip_space_or_newline
        write "."
        @lexer.wants_def_or_macro_name do
          next_token_skip_space_or_newline
        end

        body = node.body
        case body
        when Call
          call = body
          clear_object call
          indent(@indent, call)
        when IsA
          if body.obj.is_a?(Var)
            if body.nil_check?
              call = Call.new("nil?")
            else
              call = Call.new("is_a?", body.const)
            end
            accept call
          else
            clear_object(body)
            accept body
          end
        when RespondsTo
          if body.obj.is_a?(Var)
            call = Call.new("responds_to?", SymbolLiteral.new(body.name.to_s))
            accept call
          else
            clear_object(body)
            accept body
          end
        when Cast
          if body.obj.is_a?(Var)
            call = Call.new("as", body.to)
            accept call
          else
            clear_object(body)
            accept body
          end
        when NilableCast
          if body.obj.is_a?(Var)
            call = Call.new("as?", body.to)
            accept call
          else
            clear_object(body)
            accept body
          end
        when ReadInstanceVar
          if body.obj.is_a?(Var)
            call = Call.new(body.name)
            accept call
          else
            clear_object(body)
            accept body
          end
        when Not
          if body.exp.is_a?(Var)
            call = Call.new("!")
            accept call
          else
            clear_object(body)
            accept body
          end
        else
          raise "BUG: unexpected node for &. argument, at #{node.location}, not #{body.class}"
        end
      end

      @inside_call_or_assign = old_inside_call_or_assign
    end

    def clear_object(node)
      case node
      when Call
        if node.obj.is_a?(Var)
          node.obj = nil
        else
          clear_object(node.obj)
        end
      when IsA
        if node.obj.is_a?(Var)
          node.obj = Nop.new
        else
          clear_object(node.obj)
        end
      when RespondsTo
        if node.obj.is_a?(Var)
          node.obj = Nop.new
        else
          clear_object(node.obj)
        end
      when Cast
        if node.obj.is_a?(Var)
          node.obj = Nop.new
        else
          clear_object(node.obj)
        end
      when NilableCast
        if node.obj.is_a?(Var)
          node.obj = Nop.new
        else
          clear_object(node.obj)
        end
      when Not
        if node.exp.is_a?(Var)
          node.exp = Nop.new
        else
          clear_object(node.exp)
        end
      end
    end

    def format_block_args(args, node)
      return node.body if args.empty?

      write_token " ", :OP_BAR
      skip_space_or_newline
      args.each_index do |i|
        format_block_arg

        if @token.type.op_comma?
          next_token_skip_space_or_newline
          write ", " unless last?(i, args)
        end
      end
      skip_space_or_newline
      write_token :OP_BAR
      skip_space

      node.body
    end

    def format_block_arg
      if @token.type.op_star?
        write_token :OP_STAR
      end

      case @token.type
      when .op_lparen?
        write "("
        next_token_skip_space_or_newline

        while true
          format_block_arg
          if @token.type.op_comma?
            next_token_skip_space_or_newline
          end

          if @token.type.op_rparen?
            next_token
            write ")"
            break
          else
            write ", "
          end
        end
      when .ident?
        write @token.value
        next_token
      when .underscore?
        write("_")
        next_token
      else
        raise "BUG: unexpected token #{@token.type}"
      end

      skip_space_or_newline
    end

    def remove_to_skip(node, to_skip)
      if to_skip > 0
        body = node.body
        if body.is_a?(ExceptionHandler) && body.implicit
          sub_body = remove_to_skip(body, to_skip)
          body.body = sub_body
          return body
        end

        if body.is_a?(Expressions)
          body.expressions = body.expressions[to_skip..-1]
          case body.expressions.size
          when 0
            Nop.new
          when 1
            body.expressions.first
          else
            body
          end
        else
          Nop.new
        end
      else
        node.body
      end
    end

    def visit(node : IsA)
      if node.nil_check?
        visit Call.new(node.obj, "nil?")
      else
        visit Call.new(node.obj, "is_a?", node.const)
      end
    end

    def visit(node : RespondsTo)
      visit Call.new(node.obj, "responds_to?", SymbolLiteral.new(node.name))
    end

    def visit(node : Or)
      format_binary node, :OP_BAR_BAR, :OP_BAR_BAR_EQ
    end

    def visit(node : And)
      format_binary node, :OP_AMP_AMP, :OP_AMP_AMP_EQ
    end

    def format_binary(node, token : Token::Kind, alternative : Token::Kind)
      column = @column

      accept node.left
      skip_space_or_newline

      # This is the case of `left ||= right`
      if @token.type == alternative
        write " "
        write alternative
        write " "
        next_token_skip_space
        case right = node.right
        when Assign
          accept_assign_value(right.value)
        when Call
          accept_assign_value(right.args.last)
        else
          raise "BUG: expected Assign or Call after op assign, at #{node.location}"
        end
        return false
      end

      write_token " ", token
      found_comment = skip_space
      if found_comment || @token.type.newline?
        if @inside_call_or_assign == 0
          next_indent = @inside_cond == 0 ? @indent + 2 : @indent
        else
          next_indent = column == 0 ? 2 : column
        end
        indent(next_indent) do
          skip_space_write_line
          skip_space_or_newline
        end
        write_indent(next_indent, node.right)
        return false
      end

      skip_space_or_newline
      write " "
      accept node.right

      false
    end

    def visit(node : Not)
      if @token.type.op_bang?
        write_token :OP_BANG
        skip_space_or_newline
        accept node.exp
      else
        # Can be `exp.!`
        accept node.exp
        skip_space_or_newline
        write_token :OP_PERIOD
        skip_space_or_newline
        write_token :OP_BANG
      end

      false
    end

    def visit(node : Assign)
      target = node.target

      @vars.last.add target.name if target.is_a?(Var)

      accept target
      skip_space_or_newline

      check_align = check_assign_length node.target
      slash_is_regex!
      write_token " ", :OP_EQ
      skip_space(consume_newline: false)
      accept_assign_value_after_equals node.value, check_align: check_align

      false
    end

    def visit(node : OpAssign)
      accept node.target
      skip_space_or_newline

      slash_is_regex!
      write " "
      write node.op
      write "="
      next_token_skip_space
      accept_assign_value_after_equals node.value

      false
    end

    def accept_assign_value_after_equals(value, check_align = false)
      if @token.type.newline?
        next_token_skip_space_or_newline
        write_line
        write_indent(@indent + 2, value)
      else
        write " "
        accept_assign_value value, check_align: check_align
      end
    end

    def accept_assign_value(value, check_align = false)
      before_column = @column
      if @token.keyword?(:if) || @token.keyword?(:case) || value.is_a?(MacroIf)
        indent(@column, value)
      else
        inside_call_or_assign do
          accept value
        end
      end
      check_assign_align before_column, value if check_align
    end

    def check_assign_length(exp)
      if assign_length = @assign_length
        target_length = assign_length(exp)
        gap = assign_length - target_length
        gap.times { write " " }
        @assign_length = nil
        true
      else
        false
      end
    end

    def check_assign_align(before_column, exp)
      if exp.is_a?(NumberLiteral)
        @assign_infos << AlignInfo.new(0_u64, @line, before_column, @column, @column, true)
      end
    end

    def visit(node : Require)
      write_keyword :require, " "
      accept StringLiteral.new(node.string)

      false
    end

    def visit(node : VisibilityModifier)
      case node.modifier
      when .private?
        write_keyword :private, " "
      when .protected?
        write_keyword :protected, " "
      when .public?
        # no keyword needed
      end
      accept node.exp

      false
    end

    def visit(node : MagicConstant)
      check node.name
      write node.name
      next_token

      false
    end

    def visit(node : ModuleDef)
      write_keyword :module, " "

      accept node.name
      format_type_vars node.type_vars, node.splat_index

      format_nested_with_end node.body

      false
    end

    def visit(node : AnnotationDef)
      write_keyword :annotation, " "

      accept node.name

      skip_space(@indent + 2)

      if @token.type.op_semicolon?
        skip_semicolon_or_space_or_newline
        check_end
        write "; end"
      else
        skip_space_or_newline
        check_end
        write_line
        write_indent
        write "end"
      end

      next_token
      false
    end

    def visit(node : ClassDef)
      write_keyword :abstract, " " if node.abstract?
      write_keyword (node.struct? ? Keyword::STRUCT : Keyword::CLASS), " "

      accept node.name
      format_type_vars node.type_vars, node.splat_index

      if superclass = node.superclass
        skip_space_or_newline
        write_token " ", :OP_LT, " "
        skip_space_or_newline
        accept superclass
      end

      format_nested_with_end node.body

      false
    end

    def format_type_vars(type_vars, splat_index)
      if type_vars
        skip_space
        write_token :OP_LPAREN
        skip_space_or_newline
        type_vars.each_with_index do |type_var, i|
          write_token :OP_STAR if i == splat_index
          write type_var
          next_token_skip_space_or_newline
          if @token.type.op_comma?
            write ", " unless last?(i, type_vars)
            next_token_skip_space_or_newline
          end
        end
        write_token :OP_RPAREN
        skip_space
      end
    end

    def visit(node : CStructOrUnionDef)
      keyword = node.union? ? Keyword::UNION : Keyword::STRUCT
      write_keyword keyword, " "

      write node.name
      next_token

      @inside_struct_or_union += 1
      format_nested_with_end node.body
      @inside_struct_or_union -= 1

      false
    end

    def visit(node : Include)
      write_keyword :include, " "
      accept node.name

      false
    end

    def visit(node : Extend)
      write_keyword :extend, " "
      accept node.name

      false
    end

    def visit(node : LibDef)
      @inside_lib += 1

      write_keyword :lib, " "

      accept node.name

      format_nested_with_end node.body

      @inside_lib -= 1

      false
    end

    def visit(node : EnumDef)
      write_keyword :enum, " "
      accept node.name

      if base_type = node.base_type
        skip_space
        write_token " ", :OP_COLON, " "
        skip_space_or_newline
        accept base_type
      end

      @inside_enum += 1
      format_nested_with_end Expressions.from(node.members)
      @inside_enum -= 1

      false
    end

    def visit(node : TypeDeclaration)
      accept node.var
      skip_space_or_newline

      # This is for a case like `x, y : Int32`
      if @inside_struct_or_union && @token.type.op_comma?
        @exp_needs_indent = false
        write ", "
        next_token
        return false
      end

      check :OP_COLON
      next_token_skip_space_or_newline
      write " : "
      accept node.declared_type
      if value = node.value
        skip_space
        check :OP_EQ
        next_token_skip_space
        write " ="
        accept_assign_value_after_equals value
      end
      false
    end

    def visit(node : UninitializedVar)
      accept node.var
      skip_space_or_newline
      write_token " ", :OP_EQ, " "
      skip_space_or_newline
      write_keyword :"uninitialized", " "
      skip_space_or_newline
      accept node.declared_type
      false
    end

    def visit(node : Return)
      format_control_expression node, :return
    end

    def visit(node : Break)
      format_control_expression node, :break
    end

    def visit(node : Next)
      format_control_expression node, :next
    end

    def format_control_expression(node, keyword : Keyword)
      write_keyword keyword

      has_parentheses = false
      if @token.type.op_lparen?
        has_parentheses = true
        write "("
        next_token_skip_space_or_newline
      end

      if exp = node.exp
        write " " unless has_parentheses
        skip_space

        # If the number of consecutive `{`s starting a tuple literal is 1 less
        # than the level of tuple nesting in the actual AST node, this means the
        # parser synthesized a TupleLiteral from multiple expressions, e.g.
        #
        #     return {1, 2}, 3, 4
        #     return { {1, 2}, 3, 4 }
        #
        # The tuple depth is 2 in both cases but only 1 leading curly brace is
        # present on the first return.
        if exp.is_a?(TupleLiteral) && opening_curly_brace_count < leading_tuple_depth(exp)
          format_args(exp.elements, has_parentheses)
          skip_space if has_parentheses
        else
          indent(@indent, exp)
          skip_space
        end
      end

      write_token :OP_RPAREN if has_parentheses

      false
    end

    def opening_curly_brace_count
      @lexer.peek_ahead do
        count = 0
        while @lexer.token.type.op_lcurly?
          count += 1
          @lexer.next_token_skip_space_or_newline
        end
        count
      end
    end

    def leading_tuple_depth(exp)
      count = 0
      while exp.is_a?(TupleLiteral)
        count += 1
        exp = exp.elements.first?
      end
      count
    end

    def visit(node : Yield)
      if scope = node.scope
        write_keyword :with, " "
        accept scope
        skip_space_or_newline
        write " "
      end

      write_keyword :yield

      if @token.type.op_lparen?
        format_parenthesized_args(node.exps)
      else
        write " " unless node.exps.empty?
        skip_space
        format_args node.exps, false
      end

      false
    end

    def visit(node : Case)
      slash_is_regex!
      write_keyword :case
      skip_space

      if cond = node.cond
        write " "
        accept cond
      end

      skip_space_write_line

      align_number = node.whens.all? { |a_when| a_when.conds.size === 1 && a_when.conds.first.is_a?(NumberLiteral) }

      node.whens.each_with_index do |a_when, i|
        format_when(node, a_when, last?(i, node.whens), align_number)
        skip_space_or_newline(@indent + 2)
      end

      skip_space_or_newline

      if a_else = node.else
        write_indent
        write_keyword :else
        found_comment = skip_space(@indent + 2)
        if @token.type.newline? || found_comment
          write_line unless found_comment
          format_nested(a_else)
          skip_space_or_newline(@indent + 2)
        else
          while @token.type.op_semicolon?
            next_token_skip_space
          end

          @when_infos << AlignInfo.new(node.object_id, @line, @column, @column, @column, false)
          write " "
          accept a_else
          wrote_newline = @wrote_newline
          found_comment = skip_space_or_newline
          write_line unless found_comment || wrote_newline
        end
      end

      check_end
      write_indent
      write "end"
      next_token

      false
    end

    def format_when(case_node, node, is_last, align_number)
      skip_space_or_newline

      slash_is_regex!
      write_indent
      write_keyword(node.exhaustive? ? Keyword::IN : Keyword::WHEN, " ")
      base_indent = @column
      when_start_line = @line
      when_start_column = @column
      next_needs_indent = false
      node.conds.each_with_index do |cond, i|
        write_indent(base_indent) if next_needs_indent
        accept cond
        next_needs_indent = false
        unless last?(i, node.conds)
          skip_space_or_newline
          if @token.type.op_comma?
            write ","
            slash_is_regex!
            next_token
            found_comment = skip_space
            if found_comment || @token.type.newline?
              write_line unless found_comment
              skip_space_or_newline
              next_needs_indent = true
            else
              write " "
            end
          end
        end
      end
      when_column_middle = @column
      indent { skip_space }
      if @token.type.op_semicolon? || @token.keyword?(:then)
        separator = @token.to_s
        slash_is_regex!
        if @token.type.op_semicolon?
          skip_semicolon_or_space
        else
          next_token_skip_space
        end
        if @token.type.newline?
          format_nested(node.body, @indent)
        else
          write " " if separator == "then"
          write separator
          write " "
          when_column_end = @column
          accept node.body
          wrote_newline = @wrote_newline
          if @line == when_start_line
            @when_infos << AlignInfo.new(case_node.object_id, @line, when_start_column, when_column_middle, when_column_end, align_number)
          end
          found_comment = skip_space
          write_line unless found_comment || wrote_newline
        end
      else
        format_nested(node.body, @indent)
      end

      false
    end

    def visit(node : ImplicitObj)
      false
    end

    def visit(node : Select)
      slash_is_regex!
      write_keyword :select
      skip_space_write_line
      skip_space_or_newline

      node.whens.each do |a_when|
        needs_indent = false
        write_indent
        write_keyword :when
        skip_space_or_newline(@indent + 2)
        write " "
        a_when.conds.first.accept self
        found_comment = skip_space(@indent + 2)
        if @token.type.op_semicolon? || @token.keyword?(:then)
          sep = @token.type.op_semicolon? ? "; " : " then "
          next_token
          skip_space(@indent + 2)
          if @token.type.newline?
            write_line
            skip_space_or_newline(@indent + 2)
            needs_indent = true
          else
            write sep
            skip_space_or_newline(@indent + 2)
          end
        else
          write_line unless found_comment
          skip_space_or_newline(@indent + 2)
          needs_indent = true
        end
        if needs_indent
          format_nested(a_when.body)
        else
          a_when.body.accept self
          write_line
        end
        skip_space_or_newline(@indent + 2)
      end

      if node_else = node.else
        write_indent
        write_keyword :else
        found_comment = skip_space(@indent + 2)
        write_line unless found_comment
        skip_space_or_newline(@indent + 2)
        format_nested(node_else)
        skip_space_or_newline(@indent + 2)
      end

      write_indent
      write_keyword :end

      false
    end

    def visit(node : Annotation)
      write_token :OP_AT_LSQUARE
      skip_space_or_newline

      node.path.accept self
      skip_space_or_newline

      if @token.type.op_lparen?
        has_args = !node.args.empty? || node.named_args
        if has_args
          format_parenthesized_args(node.args, named_args: node.named_args)
        else
          next_token_skip_space_or_newline
          check :OP_RPAREN
          next_token
        end
      end

      skip_space_or_newline
      write_token :OP_RSQUARE

      false
    end

    def visit(node : Cast)
      visit Call.new(node.obj, "as", node.to)
    end

    def visit(node : NilableCast)
      visit Call.new(node.obj, "as?", node.to)
    end

    def visit(node : TypeOf)
      visit Call.new("typeof", node.expressions)
    end

    def visit(node : SizeOf)
      visit Call.new("sizeof", node.exp)
    end

    def visit(node : InstanceSizeOf)
      visit Call.new("instance_sizeof", node.exp)
    end

    def visit(node : AlignOf)
      visit Call.new("alignof", node.exp)
    end

    def visit(node : InstanceAlignOf)
      visit Call.new("instance_alignof", node.exp)
    end

    def visit(node : OffsetOf)
      visit Call.new("offsetof", [node.offsetof_type, node.offset])
    end

    def visit(node : PointerOf)
      visit Call.new("pointerof", node.exp)
    end

    def visit(node : Underscore)
      check :UNDERSCORE
      write "_"
      next_token

      false
    end

    def visit(node : MultiAssign)
      node.targets.each_with_index do |target, i|
        @vars.last.add target.name if target.is_a?(Var)

        accept target
        skip_space_or_newline
        if @token.type.op_comma?
          write ", " unless last?(i, node.targets)
          next_token_skip_space_or_newline
        end
      end

      write_token " ", :OP_EQ
      skip_space
      if @token.type.newline?
        next_token_skip_space_or_newline
        write_line
        if node.values.size == 1
          write_indent(@indent + 2, node.values.first)
          return false
        else
          write_indent(@indent + 2)
        end
      else
        write " "
      end
      format_multi_assign_values node.values

      false
    end

    def format_multi_assign_values(values)
      if values.size == 1
        accept_assign_value values.first
      else
        indent(@column) do
          values.each_with_index do |value, i|
            accept value
            unless last?(i, values)
              skip_space_or_newline
              if @token.type.op_comma?
                write ", "
                next_token_skip_space_or_newline
              end
            end
          end
        end
      end
    end

    def visit(node : ExceptionHandler)
      column = @indent

      implicit_handler = false
      if node.implicit
        accept node.body
        write_line unless skip_space_or_newline last: true
        implicit_handler = true
        column = @implicit_exception_handler_indent
      else
        if node.suffix
          inline = false

          # This is the case of:
          #
          #     begin exp rescue exp end
          #
          # It's parsed as:
          #
          #     begin (exp rescue exp) end
          #
          # So it's a suffix rescue inside a begin/end, but the Parser
          # returns it as an ExceptionHandler node.
          if @token.keyword?(:begin)
            inline = true
            write_keyword :begin
            skip_space_or_newline
            write " "
          end

          accept node.body
          passed_backslash_newline = @token.passed_backslash_newline
          skip_space
          write " " unless passed_backslash_newline
          if @token.keyword?(:rescue)
            write_keyword :rescue
            write " "
            next_token_skip_space_or_newline
            accept node.rescues.not_nil!.first.not_nil!.body
          elsif @token.keyword?(:ensure)
            write_keyword :ensure
            write " "
            next_token_skip_space_or_newline
            accept node.ensure.not_nil!
          else
            raise "expected 'rescue' or 'ensure'"
          end

          if inline
            skip_space_or_newline
            write " "
            write_keyword :end
          end

          return false
        end
      end

      unless implicit_handler
        write_keyword :begin
        format_nested(node.body, column)
      end

      if node_rescues = node.rescues
        node_rescues.each do |node_rescue|
          skip_space_or_newline(column + 2, last: true)
          write_indent(column)
          write_keyword :rescue

          name = node_rescue.name
          if name
            skip_space_or_newline
            write " "
            write name
            next_token
          end

          if types = node_rescue.types
            skip_space_or_newline
            if name
              write_token " ", :OP_COLON, " "
              skip_space_or_newline
            else
              write " "
            end
            types.each_with_index do |type, j|
              accept type
              unless last?(j, types)
                skip_space_or_newline
                if @token.type.op_bar?
                  write " | "
                  next_token_skip_space_or_newline
                end
              end
            end
          end
          format_nested(node_rescue.body, column)
        end
      end

      if node_else = node.else
        skip_space_or_newline(column + 2, last: true)
        write_indent(column)
        write_keyword :else
        format_nested(node_else, column)
      end

      if node_ensure = node.ensure
        skip_space_or_newline(column + 2, last: true)
        write_indent(column)
        write_keyword :ensure
        format_nested(node_ensure, column)
      end

      unless implicit_handler
        skip_space_or_newline(column + 2, last: true)
        check_end
        write_indent(column)
        write "end"
        next_token
      end

      false
    end

    def visit(node : Alias)
      format_alias_or_typedef node, :alias, node.value
    end

    def visit(node : TypeDef)
      format_alias_or_typedef node, :type, node.type_spec
    end

    def format_alias_or_typedef(node, keyword : Keyword, value)
      write_keyword keyword, " "

      name = node.name
      if name.is_a?(Path)
        accept name
      else
        write name
        next_token
      end

      skip_space
      write_token " ", :OP_EQ, " "
      skip_space_or_newline

      accept value

      false
    end

    def visit(node : ProcPointer)
      write_token :OP_MINUS_GT
      skip_space_or_newline

      if node.global?
        write_token :OP_COLON_COLON
        skip_space_or_newline
      end

      if obj = node.obj
        accept obj
        skip_space
        write_token :OP_PERIOD
        skip_space_or_newline
      end

      write node.name
      next_token_skip_space
      next_token_skip_space if @token.type.op_eq?

      if @token.type.op_lparen?
        write "(" unless node.args.empty?
        next_token_skip_space
        node.args.each_with_index do |arg, i|
          accept arg
          skip_space_or_newline
          if @token.type.op_comma?
            write ", " unless last?(i, node.args)
            next_token_skip_space_or_newline
          end
        end
        write ")" unless node.args.empty?
        next_token_skip_space
      end

      false
    end

    def visit(node : ProcLiteral)
      write_token :OP_MINUS_GT
      whitespace_after_op_minus_gt = @token.type.space?
      skip_space_or_newline

      a_def = node.def

      if @token.type.op_lparen?
        write "(" unless a_def.args.empty?
        next_token_skip_space_or_newline

        a_def.args.each_with_index do |arg, i|
          accept arg
          skip_space_or_newline
          if @token.type.op_comma?
            write ", " unless last?(i, a_def.args)
            next_token_skip_space_or_newline
          end
        end

        check :OP_RPAREN
        write ")" unless a_def.args.empty?
        next_token_skip_space_or_newline
      end

      if return_type = a_def.return_type
        check :OP_COLON
        write " : "
        next_token_skip_space_or_newline
        accept return_type
        skip_space_or_newline
      end

      write " "

      is_do = false
      if @token.keyword?(:do)
        write_keyword :do
        is_do = true
      else
        write_token :OP_LCURLY
        write " " if a_def.body.is_a?(Nop)
      end
      skip_space

      if @token.type.newline?
        format_nested a_def.body
      else
        skip_space_or_newline
        unless a_def.body.is_a?(Nop)
          write " "
          accept a_def.body
          write " "
        end
      end

      indent do
        skip_space_or_newline
      end

      if is_do
        check_end
        write_indent
        write "end"
        next_token
      else
        if @wrote_newline
          write_indent
        end
        write_token :OP_RCURLY
      end

      false
    end

    def visit(node : ExternalVar)
      check :GLOBAL
      write @token.value
      next_token_skip_space_or_newline

      if @token.type.op_eq?
        write " = "
        next_token_skip_space_or_newline
        write @token.value
        next_token_skip_space_or_newline
      end

      write_token " ", :OP_COLON, " "
      skip_space_or_newline

      accept node.type_spec

      false
    end

    def visit(node : Out)
      write_keyword :out, " "
      accept node.exp

      false
    end

    def visit(node : Metaclass)
      accept node.name
      skip_space

      write_token :OP_PERIOD
      skip_space_or_newline
      write_keyword :class

      false
    end

    def visit(node : Block)
      # Handled in format_block
      false
    end

    def visit(node : When)
      # Handled in format_when
      false
    end

    def visit(node : Rescue)
      # Handled in visit(node : ExceptionHandler)
      false
    end

    def visit(node : MacroId)
      false
    end

    def visit(node : MetaVar)
      false
    end

    def visit(node : Asm)
      write_keyword :asm
      skip_space_or_newline

      column = @column
      has_newlines = false

      write_token :OP_LPAREN
      skip_space

      if @token.type.newline?
        @indent += 2
        consume_newlines
        has_newlines = true
      end
      skip_space_or_newline

      string = StringLiteral.new(node.text)

      if has_newlines
        write_indent(@indent, string)
      else
        indent(@column, string)
      end

      skip_space

      if @token.type.newline?
        consume_newlines
        if node.outputs || node.inputs
          column += 4
          write_indent(column)
        end
      end

      skip_space_or_newline

      if node.volatile? || node.alignstack? || node.intel? || node.can_throw?
        expected_parts = 4
      elsif node.clobbers
        expected_parts = 3
      elsif node.inputs
        expected_parts = 2
      elsif node.outputs
        expected_parts = 1
      else
        expected_parts = 0
      end

      write " " if expected_parts > 0
      colon_column = @column

      part_index = 0
      while part_index < expected_parts
        if @token.type.op_colon_colon?
          write_token :OP_COLON_COLON
          part_index += 2
        elsif @token.type.op_colon?
          write_token :OP_COLON
          part_index += 1
        end
        skip_space
        consume_newlines

        case part_index
        when 1
          if outputs = node.outputs
            visit_asm_parts outputs, colon_column do |output|
              accept output
            end
          end
        when 2
          if inputs = node.inputs
            visit_asm_parts inputs, colon_column do |input|
              accept input
            end
          end
        when 3
          if clobbers = node.clobbers
            visit_asm_parts clobbers, colon_column do |clobber|
              accept StringLiteral.new(clobber)
            end
          end
        when 4
          parts = [node.volatile?, node.alignstack?, node.intel?, node.can_throw?].select(&.itself)
          visit_asm_parts parts, colon_column do
            accept StringLiteral.new("")
          end
        else break
        end
      end

      # Mop up any trailing unused : or ::, don't write them since they should be removed
      while @token.type.in?(Token::Kind::OP_COLON, Token::Kind::OP_COLON_COLON)
        next_token_skip_space_or_newline
      end

      skip_space_or_newline

      if has_newlines
        @indent -= 2

        write_line unless @wrote_newline
        write_indent
      end

      write_token :OP_RPAREN

      false
    end

    def visit(node : AsmOperand)
      accept StringLiteral.new(node.constraint)

      skip_space_or_newline
      write_token :OP_LPAREN
      skip_space_or_newline
      accept node.exp
      skip_space_or_newline
      write_token :OP_RPAREN

      false
    end

    def visit_asm_parts(parts, colon_column, &) : Nil
      if @wrote_newline
        write_indent
      else
        write " "
      end

      column = @column

      parts.each_with_index do |part, i|
        yield part
        skip_space

        if @token.type.op_comma?
          write "," unless last?(i, parts)
          next_token_skip_space
        end

        if @token.type.newline?
          if last?(i, parts)
            next_token_skip_space_or_newline
            if @token.type.op_colon? || @token.type.op_colon_colon?
              write_line
              write_indent(colon_column)
            end
          else
            consume_newlines
            write_indent(last?(i, parts) ? colon_column : column)
            skip_space_or_newline
          end
        else
          skip_space_or_newline
          if last?(i, parts)
            if @token.type.op_colon? || @token.type.op_colon_colon?
              write " "
            end
          else
            write " "
          end
        end
      end
    end

    def visit(node : ASTNode)
      raise "BUG: unexpected node: #{node.class} at #{node.location}"
    end

    def to_s(io : IO) : Nil
      io << @output
    end

    def next_token
      current_line_number = @lexer.line_number
      @token = @lexer.next_token
      if @token.type.delimiter_start?
        increment_lines(@lexer.line_number - current_line_number)
      elsif @token.type.newline?
        if !@lexer.heredocs.empty? && !@consuming_heredocs
          write_line
          consume_heredocs
        end
      end
      @token
    end

    def next_string_token
      current_line_number = @lexer.line_number
      @token = @lexer.next_string_token(@token.delimiter_state)
      increment_lines(@lexer.line_number - current_line_number)
      @token
    end

    def next_string_array_token
      @token = @lexer.next_string_array_token
    end

    def next_macro_token
      current_line_number = @lexer.line_number

      char = @lexer.current_char
      @token = @lexer.next_macro_token(@macro_state, false)
      @macro_state = @token.macro_state

      increment_lines(@lexer.line_number - current_line_number)

      # Unescape
      if char == '\\' && !@token.raw.starts_with?(char)
        @token.raw = "\\#{@token.raw}"
      end
    end

    def next_token_skip_space
      next_token
      skip_space
    end

    def next_token_skip_space_or_newline
      next_token
      skip_space_or_newline
    end

    def skip_space(write_comma : Bool = false, consume_newline : Bool = true)
      base_column = @column
      has_space = false

      if @token.type.space?
        if @token.passed_backslash_newline
          if write_comma
            write ", "
          else
            write " "
          end
          write "\\"
          write_line
          @indent += 2 unless @passed_backslash_newline
          write_indent
          next_token
          @passed_backslash_newline = true
          if @token.type.space? || @token.type.comment?
            return skip_space(write_comma, consume_newline)
          else
            return false
          end
        end

        next_token
        has_space = true
      end

      if @token.type.comment?
        needs_space = has_space && base_column != 0
        if write_comma
          write ", "
        else
          write " " if needs_space
        end
        write_comment(needs_indent: !needs_space, consume_newline: consume_newline)
        true
      else
        false
      end
    end

    def skip_space(indent : Int32, write_comma = false)
      indent(indent) { skip_space(write_comma) }
    end

    def skip_space_or_newline(last : Bool = false, at_least_one : Bool = false, next_comes_end : Bool = false)
      just_wrote_line = @wrote_newline
      base_column = @column
      has_space = false
      newlines = 0
      while true
        case @token.type
        when .space?
          has_space = true
          next_token
        when .newline?
          newlines += 1
          next_token
        when .op_semicolon?
          next_token
        else
          break
        end
      end
      if @token.type.comment?
        needs_space = has_space && newlines == 0 && base_column != 0
        if needs_space
          write " "
        elsif last && newlines > 0
          if newlines > 1
            write_line if !just_wrote_line && !@wrote_newline
            write_line
          elsif !@wrote_newline
            write_line
          elsif at_least_one
            write_line
          end
        end
        write_comment(needs_indent: !needs_space, next_comes_end: last)
        true
      else
        false
      end
    end

    def skip_space_or_newline(indent : Int32, last : Bool = false, at_least_one : Bool = false, next_comes_end : Bool = false)
      indent(indent) { skip_space_or_newline(last, at_least_one, next_comes_end) }
    end

    def slash_is_regex!
      @lexer.slash_is_regex!
    end

    def slash_is_not_regex!
      @lexer.slash_is_not_regex!
    end

    def skip_space_write_line
      found_comment = skip_space
      write_line unless found_comment || @wrote_newline
      found_comment
    end

    def skip_semicolon
      while @token.type.op_semicolon?
        next_token
      end
    end

    def skip_semicolon_or_space
      found_comment = false
      while true
        case @token.type
        when .op_semicolon?
          next_token
        when .space?
          found_comment ||= skip_space
        else
          break
        end
      end
      found_comment
    end

    def skip_semicolon_or_space_or_newline
      while true
        case @token.type
        when .op_semicolon?
          next_token
        when .space?, .newline?
          skip_space_or_newline
        else
          break
        end
      end
    end

    def jump_semicolon
      skip_space
      skip_semicolon
      skip_space_or_newline
    end

    def write_comment(needs_indent = true, consume_newline = true, next_comes_end = false)
      while @token.type.comment?
        empty_line = @line_output.empty?
        if empty_line
          write_indent if needs_indent
        end

        value = @token.value.to_s.strip
        raw_after_comment_value = value[1..-1]
        after_comment_value = raw_after_comment_value.strip
        if after_comment_value.starts_with?("=>")
          value = "\# => #{after_comment_value[2..-1].strip}"
        elsif after_comment_value.each_char.all? { |c| c.ascii_whitespace? || c == '#' }
          # Nothing, leave sequences of whitespaces and '#' as is
        else
          char_1 = value[1]?
          if char_1 && !char_1.ascii_whitespace?
            value = "\# #{value[1..-1].strip}"
          end
        end

        if !@last_write.empty? && !@last_write[-1].ascii_whitespace?
          write " "
        end

        unless @line_output.to_s.strip.empty?
          @comment_columns[-1] = @column
        end

        if empty_line
          current_doc_comment = @current_doc_comment

          if after_comment_value.starts_with?("```")
            # Determine code fence language (what comes after "```")
            language = after_comment_value.lchop("```").strip

            if current_doc_comment && language.empty?
              # A code fence ends when nothing comes after "```"
              current_doc_comment.end_line = @line - 1
              @doc_comments << current_doc_comment if current_doc_comment.needs_format
              @current_doc_comment = nil
            else
              # Normalize crystal language tag
              if language.in?("cr", "crystal")
                value = value.rchop(language)
                language = ""
              end

              # We only format crystal code (empty by default means crystal)
              needs_format = language.empty?
              @current_doc_comment = CommentInfo.new(@line + 1, needs_format)
            end
          end
        end

        @wrote_comment = true
        write value
        next_token_skip_space
        if consume_newline
          consume_newlines(next_comes_end: next_comes_end)
          skip_space_or_newline
        end
      end
    end

    def consume_newlines(next_comes_end = false)
      if @token.type.newline?
        write_line unless @wrote_newline
        next_token_skip_space

        if @token.type.newline? && !next_comes_end
          write_line
          @wrote_double_newlines = true
        end

        skip_space_or_newline(last: next_comes_end, at_least_one: true)
      end
    end

    def indent(&)
      @indent += 2
      value = yield
      @indent -= 2
      value
    end

    def indent(node : ASTNode)
      indent { accept node }
    end

    def indent(indent : Int, &)
      old_indent = @indent
      @indent = indent
      value = yield
      @passed_backslash_newline = false
      @indent = old_indent
      value
    end

    def indent(indent : Int, node : ASTNode | HashLiteral::Entry | NamedTupleLiteral::Entry)
      indent(indent) { accept node }
    end

    def no_indent(node : ASTNode)
      no_indent { accept node }
    end

    def no_indent(&)
      old_indent = @indent
      @indent = 0
      yield
      @indent = old_indent
    end

    def write_indent
      write_indent @indent
    end

    def write_indent(indent)
      indent.times { write " " }
    end

    def write_indent(indent, node)
      write_indent(indent) unless node.is_a?(Nop)
      indent(indent, node)
    end

    def write_indent(indent = @indent, &)
      write_indent(indent)
      indent(indent) { yield }
    end

    def write(string : String)
      @output << string
      @line_output << string
      last_newline = string.rindex('\n')
      if last_newline
        @column = string.size - last_newline - 1
      else
        @column += string.size
      end

      @wrote_newline = false
      @wrote_double_newlines = false
      @last_write = string
    end

    def write(obj)
      write obj.to_s
    end

    def write_line
      @wrote_double_newlines = false
      @current_doc_comment = nil unless @wrote_comment
      @wrote_comment = false

      @output.puts
      @line_output.clear
      @column = 0
      @wrote_newline = true
      increment_line
      @last_write = ""
      if @passed_backslash_newline
        @passed_backslash_newline = false
        @indent -= 2
      end
    end

    def increment_line
      @line += 1
      @comment_columns << nil
    end

    def decrement_line
      @line -= 1
      @comment_columns.pop
    end

    def increment_lines(count)
      if count < 0
        (-count).times { decrement_line }
      else
        count.times { increment_line }
      end
    end

    def finish
      raise "BUG: unclosed parenthesis" if @paren_count > 0

      skip_space
      write_line
      skip_space_or_newline last: true

      # rstrip instead of string in case this is a subformat
      # (we want to preserve the leading indentation)
      result = to_s.rstrip

      lines = result.split('\n')
      fix_heredocs(lines)
      align_infos(lines, @when_infos)
      align_infos(lines, @hash_infos)
      align_infos(lines, @assign_infos)
      align_comments(lines)
      format_doc_comments(lines)
      line_number = -1
      lines.map! do |line|
        line_number += 1
        if @no_rstrip_lines.includes?(line_number)
          line
        else
          line.rstrip
        end
      end
      result = lines.join('\n') + '\n'
      result = "" if result == "\n"
      if @shebang
        result = result[0] + result[2..-1]
      end
      result
    end

    def fix_heredocs(lines)
      @heredoc_fixes.each do |fix|
        min_difference = (fix.start_line..fix.end_line).min_of do |line_number|
          leading_space_count(lines[line_number], fix.difference)
        end
        indent_before_start = leading_space_count(lines[fix.start_line - 1], fix.difference)
        min_difference = Math.max(min_difference - indent_before_start, 0)

        fix.start_line.upto(fix.end_line) do |line_number|
          line = lines[line_number]
          lines[line_number] = line[min_difference..]
        end
      end
    end

    def leading_space_count(line, max_count)
      max_count.times do |index|
        return index unless line.byte_at?(index) == 0x20 # ' '
      end
      max_count
    end

    # Align series of successive inline when/else (in a case),
    # or hash literals (the left side of the =>)
    def align_infos(lines, align_infos)
      max_size = nil
      last_info = nil

      align_infos.each_with_index do |align_info, i|
        if max_size
          align_info lines, align_info, max_size
        else
          last_info, max_size = find_last_info(align_infos, align_info, i + 1)
          align_info lines, align_info, max_size
        end

        if last_info && align_info.line == last_info.line
          last_info = nil
          max_size = nil
        end
      end
    end

    def find_last_info(align_infos, base, i)
      max_size = base.size

      while i < align_infos.size
        current = align_infos[i]
        break unless current.id == base.id
        break unless base.line + 1 == current.line

        base = current
        max_size = base.size if base.size > 0 && base.size > max_size

        i += 1
      end

      {base, max_size}
    end

    def align_info(lines, info, max_size)
      gap = max_size - info.size
      return if gap == 0

      line = lines[info.line]

      if info.number
        middle = info.start_column
      else
        middle = info.middle_column
      end

      before = line[0...middle]
      after = line[middle..-1]
      result = String.build do |str|
        str << before
        gap.times { str << ' ' }
        str << after
      end

      lines[info.line] = result

      # Make sure to move the comment in this line too
      comment_column = @comment_columns[info.line]?
      if comment_column
        comment_column += gap
        @comment_columns[info.line] = comment_column
      end
    end

    # Align series of successive comments
    def align_comments(lines)
      max_column = nil

      lines.each_with_index do |line, i|
        comment_column = @comment_columns[i]?
        if comment_column
          if max_column
            lines[i] = align_comment line, i, comment_column, max_column
          else
            max_column = find_max_column(lines, i + 1, comment_column)
            lines[i] = align_comment line, i, comment_column, max_column
          end
        else
          max_column = nil
        end
      end
    end

    def find_max_column(lines, base, max)
      while base < @comment_columns.size
        comment_column = @comment_columns[base]?
        break unless comment_column

        max = comment_column if comment_column > max
        base += 1
      end

      max
    end

    def align_comment(line, i, comment_column, max_column)
      return line if comment_column == max_column

      source_line = line[0...comment_column]
      comment_line = line[comment_column..-1]
      gap = max_column - comment_column

      result = String.build do |str|
        str << source_line
        gap.times { str << ' ' }
        str << comment_line
      end
      result
    end

    def format_doc_comments(lines)
      @doc_comments.reverse_each do |doc_comment|
        next if doc_comment.start_line > doc_comment.end_line

        first_line = lines[doc_comment.start_line]
        sharp_index = first_line.index('#').not_nil!

        comment = String.build do |str|
          (doc_comment.start_line..doc_comment.end_line).each do |i|
            line = lines[i].strip[1..-1]
            line = line[1..-1] if line[0]? == ' '
            str << line
            str << '\n'
          end
        end

        begin
          formatted_comment = Formatter.format(comment)
          formatted_lines = formatted_comment.lines
          formatted_lines.map! do |line|
            String.build do |str|
              sharp_index.times { str << ' ' }
              str << "# "
              str << line
            end
          end
          lines[doc_comment.start_line..doc_comment.end_line] = formatted_lines
        rescue Crystal::SyntaxException
          # For now we don't care if doc comments have syntax errors,
          # they shouldn't prevent formatting the real code
        end
      end
    end

    def write_keyword(keyword : Keyword)
      check_keyword keyword
      write keyword
      next_token
    end

    def write_keyword(before : String, keyword : Keyword)
      write before
      write_keyword keyword
    end

    def write_keyword(keyword : Keyword, after : String, skip_space_or_newline = true)
      write_keyword keyword
      write after
      skip_space_or_newline() if skip_space_or_newline
    end

    def write_keyword(before : String, keyword : Keyword, after : String)
      passed_backslash_newline = @token.passed_backslash_newline
      skip_space
      if passed_backslash_newline && before == " "
        # Nothing
      else
        write before
      end
      write_keyword keyword
      write after
      skip_space_or_newline
    end

    def write_token(type : Token::Kind)
      check type
      write type
      next_token
    end

    def write_token(before : String, type : Token::Kind)
      write before
      write_token type
    end

    def write_token(type : Token::Kind, after : String)
      write_token type
      write after
    end

    def write_token(before : String, type : Token::Kind, after : String)
      write before
      write_token type
      write after
    end

    def check_keyword(*keywords : Keyword)
      raise "expecting keyword #{keywords.join " or "}, not `#{@token.type}, #{@token.value}`, at #{@token.location}" unless keywords.any? { |k| @token.keyword?(k) }
    end

    def check(*token_types : Token::Kind)
      unless token_types.includes? @token.type
        raise "expecting #{token_types.join " or "}, not `#{@token.type}, #{@token.value}`, at #{@token.location}"
      end
    end

    def check_end
      if @token.type.op_semicolon?
        next_token_skip_space_or_newline
      end
      check_keyword :end
    end

    def last?(index, collection)
      index == collection.size - 1
    end

    def inside_macro(&)
      @inside_macro += 1
      yield
      @inside_macro -= 1
    end

    def outside_macro(&)
      old_inside_macro = @inside_macro
      @inside_macro = 0
      yield
      @inside_macro = old_inside_macro
    end

    def inside_macro?
      @inside_macro != 0
    end

    def check_macro_whitespace
      if @lexer.current_char == '\\' && @lexer.peek_next_char.ascii_whitespace?
        @lexer.next_char
        write "\\"
        write @lexer.skip_macro_whitespace
        @macro_state.whitespace = true
        increment_line
        true
      else
        false
      end
    end

    def inside_cond(&)
      @inside_cond += 1
      yield
      @inside_cond -= 1
    end

    def inside_call_or_assign(&)
      @inside_call_or_assign += 1
      yield
      @inside_call_or_assign -= 1
    end
  end
end
