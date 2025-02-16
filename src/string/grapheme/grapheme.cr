require "./properties"

class String
  # Iterates the grapheme boundaries in this string and yields for each grapheme
  # cluster the byte index of the first character and the byte index of the last
  # byte of the last character in the cluster. That is the byte span of the
  # respective grapheme cluster in the entire string.
  # The third input value is the last character itself, which can be used
  # to avoid multiple decoding in single-char graphemes.
  private def each_grapheme_boundary(& : Range(Int32, Int32), Char -> Nil) : Nil
    state = Grapheme::Property::Start

    reader = Char::Reader.new(self)
    last_char = reader.current_char
    # cache last_property to avoid re-calculation on the following iteration
    last_property = Grapheme::Property.from(last_char)
    last_boundary = 0

    while reader.has_next?
      char = reader.next_char
      property = Grapheme::Property.from(char)
      boundary, state = Grapheme.break?(last_property, property, state)

      if boundary
        index = reader.pos
        yield last_boundary...index, last_char

        last_boundary = index
      end

      last_char = char
      last_property = property
    end
  end

  # :nodoc:
  class GraphemeIterator
    include Iterator(Grapheme)

    @last_char : Char
    @last_property : Grapheme::Property

    def initialize(str : String)
      @reader = Char::Reader.new(str)
      @state = Grapheme::Property::Start
      @last_char = @reader.current_char
      # cache last_property to avoid re-calculation on the following iteration
      @last_property = Grapheme::Property.from(@last_char)
      @last_boundary = 0
    end

    def next
      return stop unless @reader.has_next?

      while char = @reader.next_char
        property = Grapheme::Property.from(char)
        boundary, @state = Grapheme.break?(@last_property, property, @state)

        last_char = @last_char
        @last_char = char
        @last_property = property

        if boundary
          index = @reader.pos
          grapheme = Grapheme.new(@reader.string, @last_boundary...index, last_char)
          @last_boundary = index

          return grapheme
        end
      end

      Grapheme.new(@reader.string, @last_boundary..@reader.string.bytesize, @last_char)
    end
  end

  # `Grapheme` represents a Unicode grapheme cluster, which describes the smallest
  # functional unit of a writing system. This is also called a *user-perceived character*.
  #
  # In the latin alphabet, most graphemes consist of a single Unicode codepoint
  # (equivalent to `Char`). But a grapheme can also consist of a sequence of codepoints,
  # which combine into a single unit.
  #
  # For example, the string `"e\u0301"` consists of two characters, the latin small letter `e`
  # and the combining acute accent `´`. Together, they form a single grapheme: `é`.
  # That same grapheme could alternatively be described in a single codepoint, `\u00E9` (latin small letter e with acute).
  # But the combinatory possibilities are far bigger than the amount of directly
  # available codepoints.
  #
  # ```
  # "e\u0301".size # => 2
  # "é".size       # => 1
  #
  # "e\u0301".grapheme_size # => 1
  # "é".grapheme_size       # => 1
  # ```
  #
  # This combination of codepoints is common in some non-latin scripts. It's also
  # often used with emojis to create customized combination. For example, the
  # thumbs up sign `👍` (`U+1F44D`) combined with an emoji modifier such as
  # `U+1F3FC` assign a colour to the emoji.
  #
  # Instances of this type can be acquired via `String#each_grapheme` or `String#graphemes`.
  #
  # The algorithm to determine boundaries between grapheme clusters is specified
  # in the [Unicode Standard Annex #29](https://www.unicode.org/reports/tr29/#Grapheme_Cluster_Boundaries).
  @[Experimental("The grapheme API is still under development. Join the discussion at [#11610](https://github.com/crystal-lang/crystal/issues/11610).")]
  struct Grapheme
    # For efficiency reasons we avoid allocating a string for graphemes consisting
    # of only a single character.
    # As a trade-off, this leads to multi dispatch on this ivar. But that's
    # acceptable compared to the allocation overhead.
    #
    # Graphemes consisting of a single character are always represented as
    # `Char`, never as `String` to simplify comparability. This invariant is
    # protected by the constructor.
    @cluster : Char | String

    # :nodoc:
    def self.new(string : String, range : Range(Int32, Int32), char : Char) : self
      if char.bytesize == range.size
        new(char)
      else
        new(string.byte_slice(range.begin, range.end - range.begin))
      end
    end

    # :nodoc:
    def initialize(@cluster)
    end

    # Appends the characters in this grapheme cluster to *io*.
    def to_s(io : IO) : Nil
      io << @cluster
    end

    # Returns the characters in this grapheme cluster.
    def to_s : String
      case cluster = @cluster
      in Char
        cluster.to_s
      in String
        cluster
      end
    end

    # Appends a representation of this grapheme cluster to *io*.
    def inspect(io : IO) : Nil
      io << "String::Grapheme("
      @cluster.inspect(io)
      io << ")"
    end

    # Returns the number of characters in this grapheme cluster.
    def size : Int32
      case cluster = @cluster
      in Char
        1
      in String
        cluster.size
      end
    end

    # Returns the number of bytes in the UTF-8 representation of this grapheme cluster.
    def bytesize : Int32
      @cluster.bytesize
    end

    # Returns `true` if *other* is equivalent to `self`.
    #
    # Two graphemes are considered equivalent if they contain the same sequence
    # of codepoints.
    def ==(other : self) : Bool
      @cluster == other.@cluster
    end

    # Returns `true` if *string* is equivalent to `self`.
    #
    # A string and a grapheme are equivalent if they contain the same sequence of codepoints.
    def ==(string : String) : Bool
      return false unless string.bytesize == bytesize

      case cluster = @cluster
      in Char
        cluster == string[0]
      in String
        cluster == string
      end
    end

    # :nodoc:
    def self.break?(c1 : Char, c2 : Char) : Bool
      break?(Property.from(c1), Property.from(c2))
    end

    # :nodoc:
    #
    # Returns whether there is a grapheme break between boundclasses lbc and tbc.
    #
    # Please note that evaluation of GB10 (grapheme breaks between emoji zwj sequences)
    # and GB 12/13 (regional indicator code points) require knowledge of previous characters
    # which is not handled by this overload. This may result in an incorrect break before
    # an E_Modifier class codepoint and an incorrectly missing break between two
    # REGIONAL_INDICATOR class code points if such support does not exist in the caller.
    #
    # The rules are graphically displayed in a table on https://www.unicode.org/Public/UCD/latest/ucd/auxiliary/GraphemeBreakTest.html
    #
    # The implementation is inspired by https://github.com/JuliaStrings/utf8proc/blob/462093b3924c7491defc67fda4bc7a27baf9b088/utf8proc.c#L261
    def self.break?(lbc : Property, tbc : Property) : Bool
      return true if lbc.start?                                                   # GB1
      return false if lbc.cr? && tbc.lf?                                          # GB3
      return true if lbc.cr? || lbc.lf? || lbc.control?                           # GB4
      return true if tbc.cr? || tbc.lf? || tbc.control?                           # GB5
      return false if lbc.l? && (tbc.l? || tbc.v? || tbc.lv? || tbc.lvt?)         # GB6
      return false if (lbc.lv? || lbc.v?) && (tbc.v? || tbc.t?)                   # GB7
      return false if (lbc.lvt? || lbc.t?) && tbc.t?                              # GB8
      return false if tbc.extend? || tbc.zwj?                                     # GB9
      return false if tbc.spacing_mark?                                           # GB9a
      return false if lbc.prepend?                                                # GB9b
      return false if lbc.extended_plus_zero_width? && tbc.extended_pictographic? # GB11 (requires additional handling)
      return false if lbc.regional_indicator? && tbc.regional_indicator?          # GB12/13 (requires additional handling)
      true                                                                        # GB999
    end

    # :nodoc:
    def self.break?(c1 : Char, c2 : Char, state : Property) : {Bool, Property}
      break?(Property.from(c1), Property.from(c2), state)
    end

    # :nodoc:
    #
    # Returns whether there is a grapheme break between boundclasses lbc and tbc.
    #
    # Please note that evaluation of GB10 (grapheme breaks between emoji zwj sequences)
    # and GB 12/13 (regional indicator code points) require knowledge of previous characters
    # which is accounted for in the state argument. The caller is expected to
    # store the returned state and pass it when calling this method the next time.
    # The initial value is `Property::Start`.
    #
    # The implementation is inspired by https://github.com/JuliaStrings/utf8proc/blob/462093b3924c7491defc67fda4bc7a27baf9b088/utf8proc.c#L291
    def self.break?(lbc : Property, tbc : Property, state : Property) : {Bool, Property}
      if state.start?
        state = lbc_override = lbc
      else
        lbc_override = state
      end

      break_permitted = break?(lbc_override, tbc)

      # Special support for GB 12/13 made possible by GB999. After two RI
      # class codepoints we want to force a break. Do this by resetting the
      # second RI's bound class to UTF8PROC_BOUNDCLASS_OTHER, to force a break
      # after that character according to GB999 (unless of course such a break is
      # forbidden by a different rule such as GB9).
      if state == tbc && tbc.regional_indicator?
        state = Property::Any
        # Special support for GB11 (emoji extend* zwj / emoji)
      elsif state.extended_pictographic?
        if tbc.extend? # fold EXTEND codepoints into emoji
          state = Property::ExtendedPictographic
        elsif tbc.zwj?
          state = Property::ExtendedPlusZeroWidth # state to record emoji+zwg combo
        else
          state = tbc
        end
      else
        state = tbc
      end

      {break_permitted, state}
    end
  end
end
