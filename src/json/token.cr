class JSON::Token
  enum Kind
    Null
    False
    True
    Int
    Float
    String
    BeginArray
    EndArray
    BeginObject
    EndObject
    Colon
    Comma
    EOF
    IntAsString
  end

  property kind : Kind
  property string_value : String

  def int_value : Int64
    raw_value.to_i64
  rescue exc : ArgumentError
    raise ParseException.new(exc.message, line_number, column_number)
  end

  def int_as_string_value : String
    raw_value.to_s
  rescue exc : ArgumentError
    raise ParseException.new(exc.message, line_number, column_number)
  end

  def float_value : Float64
    raw_value.to_f64
  rescue exc : ArgumentError
    raise ParseException.new(exc.message, line_number, column_number)
  end

  property line_number : Int32
  property column_number : Int32
  property raw_value : String

  def initialize
    @kind = :EOF
    @line_number = 0
    @column_number = 0
    @string_value = ""
    @raw_value = ""
  end

  def to_s(io : IO) : Nil
    case @kind
    when .null?
      io << "null"
    when .false?
      io << "false"
    when .true?
      io << "true"
    when .int?
      raw_value.to_s(io)
    when .float?
      raw_value.to_s(io)
    when .string?, .int_as_string?
      string_value.to_s(io)
    when .begin_array?
      io << '['
    when .end_array?
      io << ']'
    when .begin_object?
      io << '{'
    when .end_object?
      io << '}'
    when .colon?
      io << ':'
    when .comma?
      io << ','
    when .eof?
      io << "<EOF>"
    else
      raise "Unknown token kind: #{@kind}"
    end
  end
end
