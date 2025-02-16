# `StringScanner` provides for lexical scanning operations on a `String`.
#
# NOTE: To use `StringScanner`, you must explicitly import it with `require "string_scanner"`
#
# ### Example
#
# ```
# require "string_scanner"
#
# s = StringScanner.new("This is an example string")
# s.eos? # => false
#
# s.scan(/\w+/) # => "This"
# s.scan(/\w+/) # => nil
# s.scan(/\s+/) # => " "
# s.scan(/\s+/) # => nil
# s.scan(/\w+/) # => "is"
# s.eos?        # => false
#
# s.scan(/\s+/) # => " "
# s.scan(/\w+/) # => "an"
# s.scan(/\s+/) # => " "
# s.scan(/\w+/) # => "example"
# s.scan(/\s+/) # => " "
# s.scan(/\w+/) # => "string"
# s.eos?        # => true
#
# s.scan(/\s+/) # => nil
# s.scan(/\w+/) # => nil
# ```
#
# Scanning a string means remembering the position of a _scan offset_, which is
# just an index. Scanning moves the offset forward, and matches are sought
# after the offset; usually immediately after it.
#
# ### Method Categories
#
# Methods that advance the scan offset:
# * `#scan`
# * `#scan_until`
# * `#skip`
# * `#skip_until`
# * `#read_byte`
# * `#read_char`
#
# Methods that look ahead:
# * `#peek`
# * `#check`
# * `#check_until`
#
# Methods that deal with the position of the offset:
# * `#offset`
# * `#offset=`
# * `#eos?`
# * `#reset`
# * `#terminate`
#
# Methods that deal with the last match:
# * `#[]`
# * `#[]?`
#
# Miscellaneous methods:
# * `#inspect`
# * `#string`
class StringScanner
  @last_match : Regex::MatchData | StringMatchData | Nil

  def initialize(@str : String)
    @byte_offset = 0
  end

  # Sets the *position* of the scan offset.
  def offset=(position : Int)
    raise IndexError.new unless position >= 0
    @byte_offset = Math.min(position, @str.bytesize)
  end

  # Returns the current position of the scan offset.
  def offset : Int32
    @byte_offset
  end

  # Tries to match with *pattern* at the current position. If there's a match,
  # the scanner advances the scan offset, the last match is saved, and it
  # returns the matched string. Otherwise, the scanner returns `nil`.
  #
  # ```
  # require "string_scanner"
  #
  # s = StringScanner.new("test string")
  # s.scan(/\w+/)  # => "test"
  # s.scan(/\w+/)  # => nil
  # s.scan(/\s\w/) # => " s"
  # s.scan('t')    # => "t"
  # s.scan("ring") # => "ring"
  # s.scan(/.*/)   # => ""
  # ```
  def scan(pattern : Regex, *, options : Regex::MatchOptions = Regex::MatchOptions::None) : String?
    match(pattern, advance: true, options: options | Regex::MatchOptions::ANCHORED)
  end

  # :ditto:
  def scan(pattern : String) : String?
    match(pattern, advance: true, anchored: true)
  end

  # :ditto:
  def scan(pattern : Char) : String?
    match(pattern, advance: true, anchored: true)
  end

  # Scans the string _until_ the *pattern* is matched. Returns the substring up
  # to and including the end of the match, the last match is saved, and
  # advances the scan offset. Returns `nil` if no match.
  #
  # ```
  # require "string_scanner"
  #
  # s = StringScanner.new("test string")
  # s.scan_until(/ s/) # => "test s"
  # s.scan_until(/ s/) # => nil
  # s.scan_until('r')  # => "tr"
  # s.scan_until("ng") # => "ing"
  # ```
  def scan_until(pattern : Regex, *, options : Regex::MatchOptions = Regex::MatchOptions::None) : String?
    match(pattern, advance: true, options: options)
  end

  # :ditto:
  def scan_until(pattern : String) : String?
    match(pattern, advance: true, anchored: false)
  end

  # :ditto:
  def scan_until(pattern : Char) : String?
    match(pattern, advance: true, anchored: false)
  end

  private def match(pattern : Regex, advance = true, options = Regex::MatchOptions::ANCHORED)
    match = pattern.match_at_byte_index(@str, @byte_offset, options)
    @last_match = match
    if match
      start = @byte_offset
      new_byte_offset = match.byte_end(0).to_i
      @byte_offset = new_byte_offset if advance

      @str.byte_slice(start, new_byte_offset - start)
    else
      nil
    end
  end

  private def match(pattern : String | Char, advance = true, anchored = true)
    @last_match = nil
    if pattern.bytesize > @str.bytesize - @byte_offset
      nil
    elsif anchored
      i = 0
      # check string starts with string or char
      unsafe_ptr = @str.to_unsafe + @byte_offset
      pattern.each_byte do |byte|
        return nil unless unsafe_ptr[i] == byte
        i += 1
      end
      # ok, it starts
      result = pattern.to_s
      @last_match = StringMatchData.new(result)
      @byte_offset += pattern.bytesize if advance
      result
    elsif (found = @str.byte_index(pattern, @byte_offset))
      finish = found + pattern.bytesize
      result = @str.byte_slice(@byte_offset, finish - @byte_offset)
      @byte_offset = finish if advance
      @last_match = StringMatchData.new(result)
      result
    end
  end

  # Attempts to skip over the given *pattern* beginning with the scan offset.
  # In other words, the pattern is not anchored to the current scan offset.
  #
  # If there's a match, the scanner advances the scan offset, the last match is
  # saved, and it returns the size of the skipped match. Otherwise it returns
  # `nil` and does not advance the offset.
  #
  # This method is the same as `#scan`, but without returning the matched
  # string.
  def skip(pattern : Regex, *, options : Regex::MatchOptions = Regex::MatchOptions::None) : Int32?
    match = scan(pattern, options: options)
    match.size if match
  end

  # :ditto:
  def skip(pattern : String) : Int32?
    match = scan(pattern)
    match.size if match
  end

  # :ditto:
  def skip(pattern : Char) : Int32?
    match = scan(pattern)
    match.size if match
  end

  # Attempts to skip _until_ the given *pattern* is found after the scan
  # offset. In other words, the pattern is not anchored to the current scan
  # offset.
  #
  # If there's a match, the scanner advances the scan offset, the last match is
  # saved, and it returns the size of the skip. Otherwise it returns `nil`
  # and does not advance the
  # offset.
  #
  # This method is the same as `#scan_until`, but without returning the matched
  # string.
  def skip_until(pattern : Regex, *, options : Regex::MatchOptions = Regex::MatchOptions::None) : Int32?
    match = scan_until(pattern, options: options)
    match.size if match
  end

  # :ditto:
  def skip_until(pattern : String) : Int32?
    match = scan_until(pattern)
    match.size if match
  end

  # :ditto:
  def skip_until(pattern : Char) : Int32?
    match = scan_until(pattern)
    match.size if match
  end

  # Returns the value that `#scan` would return, without advancing the scan
  # offset. The last match is still saved, however.
  #
  # ```
  # require "string_scanner"
  #
  # s = StringScanner.new("this is a string")
  # s.offset = 5
  # s.check(/\w+/) # => "is"
  # s.check(/\w+/) # => "is"
  # ```
  def check(pattern : Regex, *, options : Regex::MatchOptions = Regex::MatchOptions::None) : String?
    match(pattern, advance: false, options: options | Regex::MatchOptions::ANCHORED)
  end

  # :ditto:
  def check(pattern : String) : String?
    match(pattern, advance: false, anchored: true)
  end

  # :ditto:
  def check(pattern : Char) : String?
    match(pattern, advance: false, anchored: true)
  end

  # Returns the value that `#scan_until` would return, without advancing the
  # scan offset. The last match is still saved, however.
  #
  # ```
  # require "string_scanner"
  #
  # s = StringScanner.new("test string")
  # s.check_until(/tr/) # => "test str"
  # s.check_until(/g/)  # => "test string"
  # ```
  def check_until(pattern : Regex, *, options : Regex::MatchOptions = Regex::MatchOptions::None) : String?
    match(pattern, advance: false, options: options)
  end

  # :ditto:
  def check_until(pattern : String) : String?
    match(pattern, advance: false, anchored: false)
  end

  # :ditto:
  def check_until(pattern : Char) : String?
    match(pattern, advance: false, anchored: false)
  end

  # Returns the *n*-th subgroup in the most recent match.
  #
  # Raises an exception if there was no last match or if there is no subgroup.
  #
  # ```
  # require "string_scanner"
  #
  # s = StringScanner.new("Fri Dec 12 1975 14:39")
  # regex = /(?<wday>\w+) (?<month>\w+) (?<day>\d+)/
  # s.scan(regex) # => "Fri Dec 12"
  # s[0]          # => "Fri Dec 12"
  # s[1]          # => "Fri"
  # s[2]          # => "Dec"
  # s[3]          # => "12"
  # s["wday"]     # => "Fri"
  # s["month"]    # => "Dec"
  # s["day"]      # => "12"
  # ```
  def [](n) : String
    @last_match.not_nil![n]
  end

  # Returns the nilable *n*-th subgroup in the most recent match.
  #
  # Returns `nil` if there was no last match or if there is no subgroup.
  #
  # ```
  # require "string_scanner"
  #
  # s = StringScanner.new("Fri Dec 12 1975 14:39")
  # regex = /(?<wday>\w+) (?<month>\w+) (?<day>\d+)/
  # s.scan(regex)  # => "Fri Dec 12"
  # s[0]?          # => "Fri Dec 12"
  # s[1]?          # => "Fri"
  # s[2]?          # => "Dec"
  # s[3]?          # => "12"
  # s[4]?          # => nil
  # s["wday"]?     # => "Fri"
  # s["month"]?    # => "Dec"
  # s["day"]?      # => "12"
  # s["year"]?     # => nil
  # s.scan(/more/) # => nil
  # s[0]?          # => nil
  # ```
  def []?(n) : String?
    @last_match.try(&.[n]?)
  end

  # Returns `true` if the scan offset is at the end of the string.
  #
  # ```
  # require "string_scanner"
  #
  # s = StringScanner.new("this is a string")
  # s.eos?                # => false
  # s.scan(/(\w+\s?){4}/) # => "this is a string"
  # s.eos?                # => true
  # ```
  def eos? : Bool
    @byte_offset >= @str.bytesize
  end

  # Resets the scan offset to the beginning and clears the last match.
  def reset
    @last_match = nil
    @byte_offset = 0
  end

  # Moves the scan offset to the end of the string and clears the last match.
  def terminate
    @last_match = nil
    @byte_offset = @str.bytesize
  end

  # Returns the string being scanned.
  def string : String
    @str
  end

  # Extracts a string corresponding to string[offset,*len*], without advancing
  # the scan offset.
  def peek(len) : String
    @str[offset, len]
  end

  # Returns the remainder of the string after the scan offset.
  #
  # ```
  # require "string_scanner"
  #
  # s = StringScanner.new("this is a string")
  # s.scan(/(\w+\s?){2}/) # => "this is "
  # s.rest                # => "a string"
  # ```
  def rest : String
    @str.byte_slice(@byte_offset, @str.bytesize - @byte_offset)
  end

  # Returns one byte from the current offset.
  # ```
  # require "string_scanner"
  #
  # s = StringScanner.new("あ")
  # s.read_byte # => 227
  # s.read_byte # => 129
  # s.read_byte # => 130
  # ```
  def read_byte : UInt8?
    return nil if eos?
    byte = @str.byte_at(@byte_offset)
    @byte_offset += 1
    byte
  end

  # Returns one char from the current offset.
  # ```
  # require "string_scanner"
  #
  # s = StringScanner.new("ab")
  # s.read_char # => 'a'
  # s.read_char # => 'b'
  # ```
  def read_char : Char?
    reader = Char::Reader.new(@str, @byte_offset)
    char = reader.current_char
    @byte_offset += char.bytesize
    char
  end

  # Writes a representation of the scanner.
  #
  # Includes the current position of the offset, the total size of the string,
  # and five characters near the current position.
  def inspect(io : IO) : Nil
    io << "#<StringScanner "
    offset = offset()
    io << offset << '/' << @str.size
    start = Math.min(Math.max(offset - 2, 0), Math.max(0, @str.size - 5))
    io << " \"" << @str[start, 5] << "\" >"
  end

  # :nodoc:
  struct StringMatchData
    def initialize(@str : String)
    end

    def []?(n : Int) : String?
      return unless n == 0 || n == -1
      @str
    end

    def [](n : Int) : String
      self[n]? || raise IndexError.new("Invalid capture group index: #{n}")
    end

    def []?(group_name : String) : String?
      nil
    end

    def [](group_name : String) : String
      raise KeyError.new("Capture group '#{group_name}' does not exist")
    end

    def []?(range : Range) : Array(String)?
      start, count = Indexable.range_to_index_and_count(range, 1) || return nil
      start, count = Indexable.normalize_start_and_count(start, count, 1) { return nil }
      return [] of String if count == 0
      [@str]
    end

    def [](range : Range) : Array(String)
      self[range]? || raise IndexError.new
    end
  end
end
