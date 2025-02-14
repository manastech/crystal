require "csv"

# A CSV parser. It lets you consume a CSV row by row.
#
# Most of the time `CSV#parse` and `CSV#each_row` are more convenient.
class CSV::Parser
  # Creates a parser from a `String` or `IO`.
  # Optionally takes the optional *separator* and *quote_char* arguments for
  # specifying non-standard cell separators and quote characters
  def initialize(string_or_io : String | IO, separator : Char = DEFAULT_SEPARATOR, quote_char : Char = DEFAULT_QUOTE_CHAR)
    @lexer = CSV::Lexer.new(string_or_io, separator, quote_char)
    @max_row_size = 3
  end

  # Returns the remaining rows.
  def parse : Array(Array(String))
    rows = [] of Array(String)
    each_row { |row| rows << row }
    rows
  end

  def parse_to_h : Array(Hash(String, String))
    rows = [] of Hash(String, String)
    if headers = next_row
      while row = next_row
        if parsed_row = parse_row_to_h_internal(headers, row)
          rows << parsed_row
        end
      end
    end
    rows
  end

  # Yields each of the remaining rows as an `Array(String)`.
  def each_row(&) : Nil
    while row = next_row
      yield row
    end
  end

  # Returns an `Iterator` of `Array(String)` for the remaining rows.
  def each_row
    RowIterator.new(self)
  end

  # Returns the next row in the CSV, if any, or `nil`.
  def next_row : Array(String) | Nil
    token = @lexer.next_token
    if token.kind == Token::Kind::Eof
      return nil
    end

    row = Array(String).new(@max_row_size)
    next_row_internal(token, row)
  end

  # Reads the next row into the given *array*.
  # Returns that same array, if a row was found, or `nil`.
  def next_row(array : Array(String)) : Array(String) | Nil
    token = @lexer.next_token
    if token.kind == Token::Kind::Eof
      return nil
    end

    next_row_internal(token, array)
  end

  # Rewinds this parser to the beginning.
  def rewind : Nil
    @lexer.rewind
  end

  private def next_row_internal(token, row)
    while true
      case token.kind
      when Token::Kind::Cell
        row << token.value
        token = @lexer.next_token
      else # :newline, :eof
        @max_row_size = row.size if row.size > @max_row_size
        return row
      end
    end
  end

  private def parse_row_to_h_internal(headers : Array(String), row : Array(String)) : Hash(String, String) | Nil
    h = {} of String => String
    row.empty? ? return nil : headers.each_with_index { |header, i| h[header] = row[i] }
    return h
  end

  private struct RowIterator
    include Iterator(Array(String))

    @parser : Parser

    def initialize(@parser)
    end

    def next
      @parser.next_row || stop
    end
  end
end
