# Provides methods and classes for parsing and generating CSV
# (comma-separated values) strings.
#
# This module conforms to [RFC 4180](https://tools.ietf.org/html/rfc4180).
#
# NOTE: To use `CSV` or its children, you must explicitly import it with `require "csv"`
#
# ### Parsing
#
# Several ways of parsing CSV are provided. The most straight-forward, but
# slow or inefficient for some scenarios, is `CSV#parse`, which returns
# an array of arrays of all data.
#
# Rows can be traversed in a linear fashion with `CSV#each_row`, or
# using an `Iterator`.
#
# To parse a CSV in an efficient way, optionally being able to access
# row values from header names, create an instance of a `CSV`.
#
# ### Parsing with `CSV#new`
#
# A CSV instance holds a cursor to the current row in the CSV. The cursor
# is advanced by invoking `#next`, which returns `true` if a next row was found,
# and `false` otherwise. A first call to `#next` is required to position the
# CSV parser in the first row.
#
# Once positioned in a row, values can be obtained with the several `#[]` methods,
# which can accept a header name, column position, or header name pattern as a `Regex`.
#
# Additionally, a `Row` object can be obtained with the `#row` method which
# provides similar methods and can be converted to an `Array` or `Hash`.
#
# ### Example
#
# ```
# require "csv"
#
# csv = CSV.new("Name, Age\nJohn, 20\nPeter, 30", headers: true)
# csv.next # => true
#
# csv["Name"]  # => "John"
# csv[0]       # => "John"
# csv[-2]      # => "John"
# csv[/name/i] # => "John"
#
# csv["Age"] # => " 20"
#
# csv.row.to_a # => ["John", " 20"]
# csv.row.to_h # => {"Name" => "John", "Age" => " 20"}
#
# csv.next    # => true
# csv["Name"] # => "Peter"
#
# csv.next # => false
# ```
#
# ### Building
#
# To create CSV data, check `CSV#build` and the `CSV::Builder` class.
class CSV
  DEFAULT_SEPARATOR  = ','
  DEFAULT_QUOTE_CHAR = '"'

  # Parses a CSV or `IO` into an array.
  #
  # Takes optional *separator* and *quote_char* arguments for defining
  # non-standard csv cell separators and quote characters.
  #
  # ```
  # require "csv"
  #
  # CSV.parse("one,two\nthree")
  # # => [["one", "two"], ["three"]]
  # CSV.parse("one;two\n'three;'", separator: ';', quote_char: '\'')
  # # => [["one", "two"], ["three;"]]
  # ```
  def self.parse(string_or_io : String | IO, separator : Char = DEFAULT_SEPARATOR, quote_char : Char = DEFAULT_QUOTE_CHAR) : Array(Array(String))
    Parser.new(string_or_io, separator, quote_char).parse
  end

  # Parses a CSV or `IO` into an array of hashes using the first row as headers.
  #
  # Takes optional *separator* and *quote_char* arguments for defining
  # non-standard csv cell separators and quote characters.
  #
  # ```
  # require "csv"
  #
  # CSV.parse_to_hashes("name,age,city\nJohn,30,New York\nJane,25,San Francisco")
  # # => [
  # #   {"name" => "John", "age" => "30", "city" => "New York"},
  # #   {"name" => "Jane", "age" => "25", "city" => "San Francisco"}
  # # ]
  # ```
  def self.parse_to_h(string_or_io : String | IO, separator : Char = DEFAULT_SEPARATOR, quote_char : Char = DEFAULT_QUOTE_CHAR) : Array(Hash(String, String))
    Parser.new(string_or_io, separator, quote_char).parse_to_h
  end

  # Yields each of a CSV's rows as an `Array(String)`.
  #
  # See `CSV.parse` about the *separator* and *quote_char* arguments.
  #
  # ```
  # require "csv"
  #
  # CSV.each_row("one,two\nthree") do |row|
  #   puts row
  # end
  # ```
  #
  # Output:
  #
  # ```
  # ["one", "two"]
  # ["three"]
  # ```
  def self.each_row(string_or_io : String | IO, separator : Char = DEFAULT_SEPARATOR, quote_char : Char = DEFAULT_QUOTE_CHAR, &)
    Parser.new(string_or_io, separator, quote_char).each_row do |row|
      yield row
    end
  end

  # Returns an `Iterator` of `Array(String)` over a CSV's rows.
  #
  # See `CSV.parse` about the *separator* and *quote_char* arguments.
  #
  # ```
  # require "csv"
  #
  # rows = CSV.each_row("one,two\nthree")
  # rows.next # => ["one", "two"]
  # rows.next # => ["three"]
  # ```
  def self.each_row(string_or_io : String | IO, separator : Char = DEFAULT_SEPARATOR, quote_char : Char = DEFAULT_QUOTE_CHAR)
    Parser.new(string_or_io, separator, quote_char).each_row
  end

  # Builds a CSV. This yields a `CSV::Builder` to the given block.
  #
  # Takes optional *quoting* argument to define quote behavior.
  #
  # ```
  # require "csv"
  #
  # result = CSV.build do |csv|
  #   csv.row "one", "two"
  #   csv.row "three"
  # end
  # result # => "one,two\nthree\n"
  # result = CSV.build(quoting: CSV::Builder::Quoting::ALL) do |csv|
  #   csv.row "one", "two"
  #   csv.row "three"
  # end
  # result # => "\"one\",\"two\"\n\"three\"\n"
  # ```
  #
  # See: `CSV::Builder::Quoting`
  def self.build(separator : Char = DEFAULT_SEPARATOR, quote_char : Char = DEFAULT_QUOTE_CHAR, quoting : Builder::Quoting = Builder::Quoting::RFC, &) : String
    String.build do |io|
      build(io, separator, quote_char, quoting) { |builder| yield builder }
    end
  end

  # Appends CSV data to the given `IO`. This yields a `CSV::Builder`
  # that writes to the given `IO`.
  #
  # ```
  # require "csv"
  #
  # io = IO::Memory.new
  # io.puts "HEADER"
  # CSV.build(io) do |csv|
  #   csv.row "one", "two"
  #   csv.row "three"
  # end
  # io.to_s # => "HEADER\none,two\nthree\n"
  # ```
  def self.build(io : IO, separator : Char = DEFAULT_SEPARATOR, quote_char : Char = DEFAULT_QUOTE_CHAR, quoting : Builder::Quoting = Builder::Quoting::RFC, &) : Nil
    builder = Builder.new(io, separator, quote_char, quoting)
    yield builder
    io.flush
  end

  @headers : Array(String)?
  @indices : Hash(String, Int32)?

  # Creates a new instance from the given `String` or `IO`.
  #
  # * If *strip* is `true`, row values are stripped with `String#strip` before being
  # returned from methods.
  # * If *headers* is `true`, row values can be accessed with header names or patterns.
  # Headers are always stripped.
  #
  # See `CSV.parse` about the *separator* and *quote_char* arguments.
  def initialize(string_or_io : String | IO, headers = false, @strip = false, separator : Char = DEFAULT_SEPARATOR, quote_char : Char = DEFAULT_QUOTE_CHAR)
    @parser = Parser.new(string_or_io, separator, quote_char)
    if headers
      headers = @parser.next_row || ([] of String)
      headers = @headers = headers.map &.strip
      indices = @indices = {} of String => Int32
      headers.each_with_index do |header, index|
        indices.put_if_absent(header, index)
      end
    end
    @traversed = false
  end

  # Creates a new instance from the given `String` or `IO`, and yields it to
  # the given block once for each row in the CSV.
  #
  # * If *strip* is `true`, row values are stripped with `String#strip` before being
  # returned from methods.
  # * If *headers* is `true`, row values can be accessed with header names or patterns.
  # Headers are always stripped.
  #
  # See `CSV.parse` about the *separator* and *quote_char* arguments.
  def self.new(string_or_io : String | IO, headers = false, strip = false, separator : Char = DEFAULT_SEPARATOR, quote_char : Char = DEFAULT_QUOTE_CHAR, &)
    csv = new(string_or_io, headers, strip, separator, quote_char)
    csv.each do
      yield csv
    end
    csv
  end

  # Returns this CSV headers. Their values are always stripped.
  # Raises `CSV::Error` if headers were not requested.
  def headers : Array(String)
    @headers || raise(Error.new("Headers not requested"))
  end

  # Invokes the block once for each row in this CSV, yielding `self`.
  def each(&) : Nil
    while self.next
      yield self
    end
  end

  # Advanced the cursor to the next row. Must be called once to position
  # the cursor in the first row. Returns `true` if a next row was found,
  # `false` otherwise.
  def next : Bool
    return false if @traversed

    row = @row ||= [] of String
    row.clear
    @row = @parser.next_row(row)
    if @row
      true
    else
      @traversed = true
      false
    end
  end

  # Returns the current row's value corresponding to the given *header* name.
  # Raises `KeyError` if no such header exists.
  # Raises `CSV::Error` if headers were not requested.
  def [](header : String) : String
    row_internal[header]
  end

  # Returns the current row's value corresponding to the given *header* name.
  # Returns `nil` if no such header exists.
  # Raises `CSV::Error` if headers were not requested.
  def []?(header : String) : String?
    row_internal[header]?
  end

  # Returns the current row's value at the given column index.
  # A negative index counts from the end.
  # Raises `IndexError` if no such column exists.
  def [](column : Int) : String
    row_internal[column]
  end

  # Returns the current row's value at the given column index.
  # A negative index counts from the end.
  # Returns `nil` if no such column exists.
  def []?(column : Int) : String?
    row_internal[column]?
  end

  # Returns the current row's value corresponding to the given *header_pattern*.
  # Raises `KeyError` if no such header exists.
  # Raises `CSV::Error` if headers were not requested.
  def [](header_pattern : Regex, *, options : Regex::MatchOptions = Regex::MatchOptions::None) : String
    row_internal[header_pattern, options: options]
  end

  # Returns the current row's value corresponding to the given *header_pattern*.
  # Returns `nil` if no such header exists.
  # Raises `CSV::Error` if headers were not requested.
  def []?(header_pattern : Regex, *, options : Regex::MatchOptions = Regex::MatchOptions::None) : String?
    row_internal[header_pattern, options: options]?
  end

  # Returns a tuple of the current row's values at given indices
  # A negative index counts from the end.
  # Raises `IndexError` if any column doesn't exist
  # The behavior of returning a tuple is similar to `Hash#values_at`
  def values_at(*columns : Int)
    columns.map { |column| row_internal[column] }
  end

  # Returns a tuple of the current row's values corresponding to the given *headers*
  # Raises `KeyError` if any header doesn't exist.
  # Raises `CSV::Error` if headers were not requested
  # The behavior of returning a tuple is similar to `Hash#values_at`
  def values_at(*headers : String)
    headers.map { |header| row_internal[header] }
  end

  # Returns the current row as a `Row` instance.
  def row : Row
    Row.new(self, current_row.dup)
  end

  # Rewinds this CSV to the beginning, rewinding the underlying IO if any.
  def rewind : Nil
    @parser.rewind
    @parser.next_row if @headers
    @traversed = false
  end

  private def row_internal
    Row.new(self, current_row)
  end

  private def current_row
    row = @row
    return row if row

    if @traversed
      raise Error.new("After last row")
    else
      raise Error.new("Before first row")
    end
  end

  # :nodoc:
  def indices : Hash(String, Int32)
    @indices || raise(Error.new("Headers not requested"))
  end

  # :nodoc:
  getter? strip

  # :nodoc:
  def headers? : Array(String)?
    @headers
  end

  # A Row of a `CSV::WithHeaders` instance.
  struct Row
    private getter csv : CSV
    @row : Array(String)

    # :nodoc:
    def initialize(@csv, @row)
    end

    # Returns the current row's value corresponding to the given *header* name.
    # Raises `KeyError` if no such header exists.
    # Raises `CSV::Error` if headers were not requested.
    def [](header : String) : String
      value = self.[]?(header)
      raise KeyError.new("Missing header: #{header}") unless value
      value
    end

    # Returns this row's value corresponding to the given *header* name.
    # Returns `nil` if no such header exists.
    # Raises `CSV::Error` if headers were not requested.
    def []?(header : String) : String?
      index = csv.indices[header]?
      if index
        maybe_strip(@row[index]? || "")
      else
        nil
      end
    end

    # Returns this row's value at the given column index.
    # A negative index counts from the end.
    # Raises `IndexError` if no such column exists.
    def [](column : Int) : String
      value = self.[]?(column)
      raise IndexError.new("Missing column index: #{column}") unless value
      value
    end

    # Returns this row's value at the given column index.
    # A negative index counts from the end.
    # Returns `nil` if no such column exists.
    def []?(column : Int) : String?
      size = csv.headers?.try(&.size) || @row.size

      column += size if column < 0

      value = @row[column]?
      value ||= "" if 0 <= column < size
      value ? maybe_strip(value) : nil
    end

    # Returns this row's value corresponding to the given *header_pattern*.
    # Raises `KeyError` if no such header exists.
    # Raises `CSV::Error` if headers were not requested.
    def [](header_pattern : Regex, *, options : Regex::MatchOptions = Regex::MatchOptions::None) : String
      value = self.[]?(header_pattern, options: options)
      raise KeyError.new("Missing header pattern: #{header_pattern}") unless value
      value
    end

    # Returns this row's value corresponding to the given *header_pattern*.
    # Returns `nil` if no such header exists.
    # Raises `CSV::Error` if headers were not requested.
    def []?(header_pattern : Regex, *, options : Regex::MatchOptions = Regex::MatchOptions::None) : String?
      csv.headers.each_with_index do |header, i|
        if header.matches?(header_pattern, options: options)
          return maybe_strip(@row[i]? || "")
        end
      end
      nil
    end

    # Returns the number of columns in this row, regardless of the number
    # of headers (if requested).
    def size : Int32
      @row.size
    end

    # Converts this row to an `Array`.
    def to_a : Array(String)
      @row.map!(&.strip) if csv.strip?
      @row
    end

    # Converts this row to a `Hash`.
    def to_h : Hash(String, String)
      h = {} of String => String
      csv.headers.each_with_index do |header, i|
        h[header] = maybe_strip(@row[i]? || "")
      end
      h
    end

    # Returns a tuple of this row's values at given indices
    # A negative index counts from the end.
    # Raises `IndexError` if any column doesn't exist
    # The behavior of returning a tuple is similar to `Hash#values_at`
    def values_at(*columns : Int)
      columns.map { |column| self[column] }
    end

    # Returns a tuple of this row's values corresponding to the given *headers*
    # Raises `KeyError` if any header doesn't exist.
    # Raises `CSV::Error` if headers were not requested
    # The behavior of returning a tuple is similar to `Hash#values_at`
    def values_at(*headers : String)
      headers.map { |header| self[header] }
    end

    private def maybe_strip(value)
      csv.strip? ? value.strip : value
    end
  end
end

require "./csv/**"
