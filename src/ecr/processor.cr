module ECR
  extend self

  DefaultBufferName = "__str__"

  # :nodoc:
  macro process_string(string, filename, buffer_name = nil, quote = true)
    {%
      buffer_name = (buffer_name || DefaultBufferName).id

      tokens = [] of _
      chars = string.chars
      pos = 0
      line_number = 1
      column_number = 1

      looper = [nil]
      looper.each do
        looper << nil # while true

        start_line_number = line_number
        start_column_number = column_number

        if chars[pos].nil?
          looper.clear # break
        elsif chars[pos] == '<' && chars[pos + 1] == '%'
          column_number += 2
          pos += 2

          suppress_leading = chars[pos] == '-'
          if suppress_leading
            column_number += 1
            pos += 1
          end

          if chars[pos] == '='
            type = :output
            column_number += 1
            pos += 1
          elsif chars[pos] == '%'
            type = :string
            column_number += 1
            pos += 1
          else
            type = :control
          end

          start_line_number = line_number
          start_column_number = column_number
          start_pos = pos

          looper2 = [nil]
          looper2.each do
            looper2 << nil # while true

            if chars[pos].nil?
              if type == :output
                raise "Unexpected end of file inside <%= ..."
              elsif type == :string
                raise "Unexpected end of file inside <%% ..."
              else
                raise "Unexpected end of file inside <% ..."
              end
            elsif (chars[pos] == '-' && chars[pos + 1] == '%' && chars[pos + 2] == '>') ||
                  (chars[pos] == '%' && chars[pos + 1] == '>')
              suppress_trailing = chars[pos] == '-'
              value = type == :string ? "<%" + string[start_pos...pos + 2] : string[start_pos...pos]
              column_number += suppress_trailing ? 3 : 2
              pos += suppress_trailing ? 3 : 2
              tokens << {
                type:              type,
                value:             value,
                line_number:       start_line_number,
                column_number:     start_column_number,
                suppress_leading:  suppress_leading && type != :string,
                suppress_trailing: suppress_trailing && type != :string,
              }
              looper2.clear # break
            elsif chars[pos] == '\n'
              line_number += 1
              column_number = 1
              pos += 1
            else
              column_number += 1
              pos += 1
            end
          end
        else
          start_pos = pos

          looper3 = [nil]
          looper3.each do
            looper3 << nil # while true

            if chars[pos].nil? || (chars[pos] == '<' && chars[pos + 1] == '%')
              looper3.clear # break
            elsif chars[pos] == '\n'
              line_number += 1
              column_number = 1
              pos += 1
            else
              column_number += 1
              pos += 1
            end
          end

          tokens << {
            type:          :string,
            value:         string[start_pos...pos],
            line_number:   start_line_number,
            column_number: start_column_number,
          }
        end
      end

      pieces = [] of String
      tokens.each_with_index do |token, i|
        if token[:type] == :string
          value = token[:value]
          if i > 0 && tokens[i - 1][:suppress_trailing]
            value = value.gsub(/\A.*\n/, "")
          end
          if i < tokens.size - 1 && tokens[i + 1][:suppress_leading]
            value = value.gsub(/ +\z/, "")
          end
          pieces << buffer_name
          pieces << " << "
          pieces << value.stringify
          pieces << '\n'
        elsif token[:type] == :output
          pieces << "#<loc:push>("
          pieces << "#<loc:" << filename.stringify << ',' << token[:line_number] << ',' << token[:column_number] << '>'
          pieces << token[:value]
          pieces << ")#<loc:pop>.to_s "
          pieces << buffer_name
          pieces << '\n'
        else
          pieces << "#<loc:push>"
          pieces << "#<loc:" << filename.stringify << ',' << token[:line_number] << ',' << token[:column_number] << '>'
          pieces << ' ' unless token[:value].starts_with?(' ')
          pieces << token[:value]
          pieces << "#<loc:pop>"
          pieces << '\n'
        end
      end
      program = pieces.map(&.id).join("")
    %}{{ quote ? program : program.id }}
  end
end
