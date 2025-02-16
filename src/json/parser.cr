require "./lexer"

class JSON::Parser
  property max_nesting = 512

  def initialize(string_or_io : String | IO)
    @lexer = JSON::Lexer.new(string_or_io)
    @nest = 0
    next_token
  end

  def parse : Any
    json = parse_value
    check :EOF
    json
  end

  private def parse_value
    case token.kind
    when .int?
      value_and_next_token token.int_value
    when .float?
      value_and_next_token token.float_value
    when .int_as_string?
      value_and_next_token token.int_as_string_value
    when .string?
      value_and_next_token token.string_value
    when .null?
      value_and_next_token nil
    when .true?
      value_and_next_token true
    when .false?
      value_and_next_token false
    when .begin_array?
      parse_array
    when .begin_object?
      parse_object
    else
      unexpected_token
    end
  end

  private def parse_array
    next_token

    ary = [] of Any

    nest do
      unless token.kind.end_array?
        while true
          ary << parse_value

          case token.kind
          when .comma?
            next_token
            unexpected_token if token.kind.end_array?
          when .end_array?
            break
          else
            unexpected_token
          end
        end
      end
    end

    next_token

    Any.new(ary)
  end

  private def parse_object
    next_token_expect_object_key

    object = {} of String => Any

    nest do
      unless token.kind.end_object?
        while true
          check :string
          key = token.string_value

          next_token

          check :colon
          next_token

          value = parse_value

          object[key] = value

          case token.kind
          when .comma?
            next_token_expect_object_key
            unexpected_token if token.kind.end_object?
          when .end_object?
            break
          else
            unexpected_token
          end
        end
      end
    end

    next_token

    Any.new(object)
  end

  private delegate token, to: @lexer
  private delegate next_token, to: @lexer
  private delegate next_token_expect_object_key, to: @lexer

  private def value_and_next_token(value)
    next_token
    Any.new(value)
  end

  private def check(kind : Token::Kind)
    unexpected_token unless token.kind == kind
  end

  private def unexpected_token
    parse_exception "unexpected token '#{token}'"
  end

  private def parse_exception(msg)
    raise ParseException.new(msg, token.line_number, token.column_number)
  end

  private def nest(&)
    @nest += 1
    if @nest > @max_nesting
      parse_exception "Nesting of #{@nest} is too deep"
    end

    yield
    @nest -= 1
  end
end
