require "./libxml2"

module XML
  class PullParser
    @reader : Reader
    @current_name : String
    @readable : Bool

    delegate line_number, to: @reader
    delegate column_number, to: @reader

    def initialize(input)
      @reader = Reader.new input
      current_name = nil
      @readable = true

      loop do
        case @reader.node_type
        when .element?
          current_name = @reader.name
          break
        end
        @readable = @reader.read
      end

      if current_name.nil?
        raise ParseException.new("Tag name not found", @reader.line_number, @reader.column_number)
      else
        @current_name = current_name
      end
    end

    def location
      {line_number, column_number}
    end

    def readable?
      @readable
    end

    def name
      @current_name
    end

    def read_name : String
      @readable = @reader.read
      loop do
        case @reader.node_type
        when .element?
          @current_name = @reader.name
          break
        when .end_element?
          @current_name = @reader.name
          @readable = @reader.read
          break
        when .none?
          break
        end
        @readable = @reader.read
      end
      @readable = @reader.read

      if @current_name.nil?
        raise ParseException.new("Tag name not found", @reader.line_number, @reader.column_number)
      else
        @current_name
      end
    end

    def read_raw : String
      value = ""

      loop do
        case @reader.node_type
        when .text?
          value = @reader.value
          break
        when .end_element?
          @readable = @reader.read
          break
        when .none?
          break
        end
        @readable = @reader.read
      end
      @readable = @reader.read

      value
    end

    def read_string : String
      value = read_raw

      if value.nil?
        raise ParseException.new("String value not found", @reader.line_number, @reader.column_number)
      else
        value
      end
    end

    def read_int : Int64
      value = read_raw

      if value.nil?
        raise ParseException.new("String value not found", @reader.line_number, @reader.column_number)
      else
        value.to_i64
      end
    end

    def read_bool : Bool
      value = read_raw

      case value
      when "t", "true"
        true
      when "f", "false"
        false
      else
        raise XML::SerializableError.new(
          "failed to parse bool",
          Bool.name,
          nil,
          Int32::MIN
        )
      end
    end

    def read_array
    end
  end

  class ParseException < XML::Error
    getter line_number : Int32
    getter column_number : Int32

    def initialize(message, @line_number = 0, @column_number = 0, cause = nil)
      super(
        "#{message} at line #{@line_number}, column #{@column_number}",
        line_number,
        column_number,
        cause
      )
    end

    def location : {Int32, Int32}
      {line_number, column_number}
    end
  end
end
