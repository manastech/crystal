require "./html/entities"

# Provides HTML escaping and unescaping methods.
#
# For HTML *parsing* see module XML, especially `XML.parse_html`.
#
# NOTE: To use `HTML`, you must explicitly import it with `require "html"`
module HTML
  private SUBSTITUTIONS = {
    '&'  => "&amp;",
    '<'  => "&lt;",
    '>'  => "&gt;",
    '"'  => "&quot;",
    '\'' => "&#39;",
  }

  # Escapes special characters in HTML, namely
  # `&`, `<`, `>`, `"` and `'`.
  #
  # ```
  # require "html"
  #
  # HTML.escape("Crystal & You") # => "Crystal &amp; You"
  # ```
  # See also `URI.encode_path`
  def self.escape(string : String) : String
    string.gsub(SUBSTITUTIONS)
  end

  # Same as `escape(string)` but outputs the result to
  # the given *io*.
  #
  # ```
  # require "html"
  #
  # io = IO::Memory.new
  # HTML.escape("Crystal & You", io) # => nil
  # io.to_s                          # => "Crystal &amp; You"
  # ```
  def self.escape(string : String, io : IO) : Nil
    escape(string.to_slice, io)
  end

  # Same as `escape(String, IO)` but accepts `Bytes` instead of `String`.
  #
  # The slice is assumed to be valid UTF-8.
  def self.escape(string : Bytes, io : IO) : Nil
    last_copy_at = 0
    string.each_with_index do |byte, index|
      str = case byte
            when '&'  then "&amp;"
            when '<'  then "&lt;"
            when '>'  then "&gt;"
            when '"'  then "&quot;"
            when '\'' then "&#39;"
            else
              next
            end

      io.write_string(string[last_copy_at, index &- last_copy_at])
      last_copy_at = index &+ 1
      io << str
    end
    io.write_string(string[last_copy_at, string.size &- last_copy_at])
  end

  # These replacements permit compatibility with old numeric entities that
  # assumed Windows-1252 encoding.
  # http://www.whatwg.org/specs/web-apps/current-work/multipage/tokenization.html#consume-a-character-reference
  private CHARACTER_REPLACEMENTS = {
    '\u20AC', # First entry is what 0x80 should be replaced with.
    '\u0081',
    '\u201A',
    '\u0192',
    '\u201E',
    '\u2026',
    '\u2020',
    '\u2021',
    '\u02C6',
    '\u2030',
    '\u0160',
    '\u2039',
    '\u0152',
    '\u008D',
    '\u017D',
    '\u008F',
    '\u0090',
    '\u2018',
    '\u2019',
    '\u201C',
    '\u201D',
    '\u2022',
    '\u2013',
    '\u2014',
    '\u02DC',
    '\u2122',
    '\u0161',
    '\u203A',
    '\u0153',
    '\u009D',
    '\u017E',
    '\u0178', # Last entry is 0x9F.
    # 0x00->'\uFFFD' is handled programmatically.
    # 0x0D->'\u000D' is a no-op.
  }

  # Returns a string where named and numeric character references
  # (e.g. &amp;gt;, &amp;#62;, &amp;#x3e;) in *string* are replaced with the corresponding
  # unicode characters. This method decodes all HTML5 entities including those
  # without a trailing semicolon (such as "&amp;copy").
  #
  # ```
  # require "html"
  #
  # HTML.unescape("Crystal &amp; You") # => "Crystal & You"
  # ```
  def self.unescape(string : String) : String
    return string unless string.includes?('&')

    String.build(string.bytesize) do |io|
      unescape(string.to_slice, io)
    end
  end

  private def self.unescape(slice, io)
    while bytesize = slice.index('&'.ord)
      io.write(slice[0, bytesize])
      slice += bytesize &+ 1

      ptr = unescape_entity(slice.to_unsafe, io)
      slice += ptr - slice.to_unsafe
    end

    io.write slice
  end

  private def self.unescape_entity(ptr, io)
    if '#' === ptr.value
      unescape_numbered_entity(ptr, io)
    else
      unescape_named_entity(ptr, io)
    end
  end

  private def self.unescape_numbered_entity(ptr, io)
    start_ptr = ptr

    ptr += 1

    hex = ptr.value.unsafe_chr.in?('x', 'X')
    if hex
      ptr += 1
      base = 16
    else
      base = 10
    end

    x = 0_u32

    # skip leading zeros
    while ptr.value === '0'
      ptr += 1
    end
    number_start_ptr = ptr

    while digit = ptr.value.unsafe_chr.to_i?(base)
      # The number of consumed digits is limited to the representation of
      # Char::MAX_CODEPOINT which is below that of UInt32::MAX
      x &*= base
      x &+= digit

      ptr += 1
    end

    if ptr - number_start_ptr > 8
      # size exceeds maxlength, so it can't be a valid codepoint and might have
      # overflow.
      x = 0_u32
    end

    size = ptr - start_ptr - (hex ? 2 : 1)
    unless size > 0 && (char = decode_codepoint(x))
      # No characters matched or invalid codepoint
      io << '&'
      return start_ptr
    end

    char.to_s(io)

    if ptr.value === ';'
      ptr += 1
    end

    return ptr
  end

  # see https://html.spec.whatwg.org/multipage/parsing.html#numeric-character-reference-end-state
  private def self.decode_codepoint(codepoint)
    case codepoint
    when 0x80..0x9F
      # Replace characters from Windows-1252 with UTF-8 equivalents.
      CHARACTER_REPLACEMENTS[codepoint - 0x80]
    when 0,
         .>(Char::MAX_CODEPOINT),
         0xD800..0xDFFF # unicode surrogate characters
      # Replace invalid characters with replacement character.
      '\uFFFD'
    else
      # don't replace disallowed codepoints
      unless codepoint == 0x007F ||
             # unicode noncharacters
             (0xFDD0..0xFDEF).includes?(codepoint) ||
             # last two of each plane (nonchars) disallowed
             codepoint & 0xFFFF >= 0xFFFE ||
             # unicode control characters except space
             (codepoint < 0x0020 && !codepoint.in?(0x0009, 0x000A, 0x000C))
        codepoint.unsafe_chr
      end
    end
  end

  private def self.unescape_named_entity(ptr, io)
    # Consume the maximum number of characters possible, with the
    # consumed characters matching one of the named references.
    start_ptr = ptr

    while ptr.value.unsafe_chr.ascii_alphanumeric?
      ptr += 1
    end

    if ptr == start_ptr
      io << '&'
      return start_ptr
    end

    # The entity name cannot be longer than the longest name in the lookup tables.
    entity_name = Slice.new(start_ptr, Math.min(ptr - start_ptr, MAX_ENTITY_NAME_SIZE))

    # If we can't find an entity on the first try, we need to search each prefix
    # of it, starting from the largest.
    while entity_name.size >= 2
      case
      when x = SINGLE_CHAR_ENTITIES[entity_name]?
        io << x
      when x = DOUBLE_CHAR_ENTITIES[entity_name]?
        io << x
      else
        entity_name = entity_name[0..-2]
        next
      end

      ptr = start_ptr + entity_name.size
      if ptr.value === ';'
        ptr += 1
      end

      return ptr
    end

    # range -1 includes the leading '&'
    start_ptr -= 1
    io.write Slice.new(start_ptr, ptr - start_ptr)
    ptr
  end
end
