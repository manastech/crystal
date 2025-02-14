require "html"
{% unless flag?(:docs) %}
  require "compiler/crystal/syntax"
{% end %}

abstract class Crystal::SyntaxHighlighter
  # Parses *code* as Crystal source code and processes it.
  def highlight(code : String)
    lexer = Lexer.new(code)
    lexer.comments_enabled = true
    lexer.count_whitespace = true
    lexer.wants_raw = true

    highlight_normal_state lexer
  end

  # Renders *token* with text *value*.
  abstract def render(type : TokenType, value : String)

  # Renders a delimiter sequence.
  abstract def render_delimiter(& : -> _)

  # Renders an interpolation sequence.
  abstract def render_interpolation(& : -> _)

  # Renders a string array sequence.
  abstract def render_string_array(& : -> _)

  # Describes the type of a highlighter token.
  enum TokenType
    NEWLINE
    SPACE
    COMMENT
    NUMBER
    CHAR
    SYMBOL
    CONST
    STRING
    IDENT
    KEYWORD
    SELF
    PRIMITIVE_LITERAL
    OPERATOR
    DELIMITER_START
    DELIMITED_TOKEN
    DELIMITER_END
    INTERPOLATION
    STRING_ARRAY_START
    STRING_ARRAY_TOKEN
    STRING_ARRAY_END
    UNDERSCORE
    UNKNOWN
  end

  private def consume_space_or_newline(lexer)
    while true
      char = lexer.current_char
      case char
      when '\n'
        lexer.next_char
        lexer.incr_line_number 1
        render :NEWLINE, "\n"
      when .ascii_whitespace?
        lexer.next_char
        render :SPACE, char.to_s
      else
        break
      end
    end
  end

  private def slash_is_not_regex(last_token_type type, space_before)
    return nil if type.nil?

    type.number? || type.const? || type.instance_var? ||
      type.class_var? || type.op_rparen? ||
      type.op_rsquare? || type.op_rcurly? || !space_before
  end

  private def highlight_normal_state(lexer, break_on_rcurly = false)
    last_is_def = false
    heredoc_stack = [] of Token
    last_token_type = nil
    space_before = false

    while true
      previous_delimiter_state = lexer.token.delimiter_state

      token = lexer.next_token

      case token.type
      when .delimiter_start?
        case
        when last_is_def && token.raw == "`"
          render :IDENT, token.raw # colorize 'def `'
        when last_is_def && token.raw == "/"
          render :IDENT, token.raw # colorize 'def /'

          if lexer.current_char == '/'
            render :IDENT, "/" # colorize 'def //'
            lexer.reader.next_char if lexer.reader.has_next?
          end
        when token.raw == "/" && slash_is_not_regex(last_token_type, space_before)
          render :OPERATOR, token.raw
        when token.delimiter_state.kind.heredoc?
          heredoc_stack << token.dup
          highlight_token token, last_is_def
        else
          highlight_delimiter_state lexer, token
          token.delimiter_state = previous_delimiter_state
        end
      when .string_array_start?, .symbol_array_start?
        highlight_string_array lexer, token
      when .op_rcurly?
        break if break_on_rcurly

        highlight_token token, last_is_def
      when .eof?
        break
      else
        highlight_token token, last_is_def
      end

      case token.type
      when .newline?
        heredoc_stack.each_with_index do |token, i|
          highlight_delimiter_state lexer, token, heredoc: true
          unless i == heredoc_stack.size - 1
            # Next token to heredoc's end is either NEWLINE or EOF.
            token = lexer.next_token

            case token.type
            when .eof?
              raise "Unterminated heredoc"
            else
              highlight_token token, last_is_def
            end
          end
        end
        heredoc_stack.clear
      when .ident?
        if last_is_def
          last_is_def = false
        end
      end

      unless token.type.space?
        last_token_type = token.type
        last_is_def = token.keyword? :def
      end
      space_before = token.type.space?
    end
  end

  private def highlight_token(token : Token, last_is_def)
    case token.type
    when .newline?
      render :NEWLINE, "\n"
    when .space?
      render :SPACE, token.value.to_s
    when .comment?
      render :COMMENT, token.value.to_s
    when .number?
      render :NUMBER, token.raw
    when .char?
      render :CHAR, token.raw
    when .symbol?
      render :SYMBOL, token.raw
    when .delimiter_start?
      render :STRING, token.raw
    when .const?, .op_colon_colon?
      render :CONST, token.to_s
    when .ident?
      if last_is_def
        render :IDENT, token.to_s
      else
        case token.value
        when Keyword::TRUE, Keyword::FALSE, Keyword::NIL
          render :PRIMITIVE_LITERAL, token.to_s
        when Keyword::SELF
          render :SELF, token.to_s
        when Keyword
          render :KEYWORD, token.to_s
        else
          render :UNKNOWN, token.to_s
        end
      end
    when .op_lparen?, .op_rparen?, .op_lsquare?, .op_rsquare?, .op_lcurly?, .op_rcurly?, .op_at_lsquare?, # ( ) { } [ ] @[
         .op_comma?, .op_period?, .op_period_period?, .op_period_period_period?,                          # , . .. ...
         .op_colon?, .op_semicolon?, .op_question?, .op_dollar_question?, .op_dollar_tilde?               # : ; ? $? $~
      # Operators that should not be colorized
      render :UNKNOWN, token.to_s
    when .op_lsquare_rsquare?, .op_lsquare_rsquare_question?, .op_lsquare_rsquare_eq?, .op_lt_eq_gt?,        # [] []? []= <=>
         .op_plus?, .op_minus?, .op_star?, .op_slash?, .op_slash_slash?,                                     # + - * / //
         .op_eq_eq?, .op_lt?, .op_lt_eq?, .op_gt?, .op_gt_eq?, .op_bang_eq?, .op_eq_tilde?, .op_bang_tilde?, # == < <= > >= != =~ !~
         .op_amp?, .op_bar?, .op_caret?, .op_tilde?, .op_star_star?, .op_gt_gt?, .op_lt_lt?, .op_percent?    # & | ^ ~ ** >> << %
      # Operators acceptable in def
      if last_is_def
        render :IDENT, token.to_s
      else
        render :OPERATOR, token.to_s
      end
    when .operator?
      # Colorize any other operator
      render :OPERATOR, token.to_s
    when .underscore?
      render :UNDERSCORE, "_"
    when .global_match_data_index?
      render :UNKNOWN, "$" + token.value.to_s
    else
      render :UNKNOWN, token.to_s
    end
  end

  private def highlight_delimiter_state(lexer, token, *, heredoc = false)
    render_delimiter do
      render :DELIMITER_START, token.raw unless heredoc
      while true
        token = lexer.next_string_token(token.delimiter_state)
        case token.type
        when .delimiter_end?
          render :DELIMITER_END, token.raw
          break
        when .interpolation_start?
          render_interpolation do
            highlight_normal_state lexer, break_on_rcurly: true
          end
        else
          render :DELIMITED_TOKEN, token.raw
        end
      end
    end
  end

  private def highlight_string_array(lexer, token)
    render_string_array do
      render :STRING_ARRAY_START, token.raw
      while true
        consume_space_or_newline(lexer)
        token = lexer.next_string_array_token
        case token.type
        when .string?
          render :STRING_ARRAY_TOKEN, token.raw
        when .string_array_end?
          render :STRING_ARRAY_END, token.raw
          break
        when .eof?
          if token.delimiter_state.kind.string_array?
            raise "Unterminated string array literal"
          else # .symbol_array?
            raise "Unterminated symbol array literal"
          end
        else
          raise "BUG: Shouldn't happen"
        end
      end
    end
  end
end
