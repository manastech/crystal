require "bit_array"

# Levenshtein distance methods.
#
# NOTE: To use `Levenshtein`, you must explicitly import it with `require "levenshtein"`
module Levenshtein
  # Computes the [levenshtein distance](http://en.wikipedia.org/wiki/Levenshtein_distance) of two strings.
  #
  # ```
  # require "levenshtein"
  #
  # Levenshtein.distance("algorithm", "altruistic") # => 6
  # Levenshtein.distance("hello", "hallo")          # => 1
  # Levenshtein.distance("こんにちは", "こんちは")           # => 1
  # Levenshtein.distance("hey", "hey")              # => 0
  # ```
  # If *cutoff* is given then the method is allowed to end once the loweset
  # possible bound is greater than *cutoff* and return that lower bound.
  # This can improve performance in cases when values over *cutoff*
  # don't need to be exact.
  #
  # ```
  # require "levenshtein"
  #
  # string1 = File.read("file_with_really_long_string")
  # string2 = File.read("another_file_with_long_string")
  #
  # Levenshtein.distance(string1, string2, 1000) # => 1275
  # Levenshtein.distance(string1, string2)       # => 2543
  # ```
  # In this example the first call to *distance* will return
  # a result faster than the second.
  def self.distance(string1 : String, string2 : String, cutoff : Int? = nil) : Int32
    return 0 if string1 == string2

    s_size = string1.size
    l_size = string2.size

    if l_size < s_size
      string1, string2 = string2, string1
      l_size, s_size = s_size, l_size
    end

    return l_size if s_size == 0
    if cutoff && cutoff < l_size - s_size
      return l_size - s_size
    end

    if string1.ascii_only? && string2.ascii_only?
      if l_size < 32
        myers32_ascii(string1, string2)
      else
        myers_ascii(string1, string2, cutoff)
      end
    else
      if l_size < 64
        dynamic_matrix(string1, string2)
      else
        myers_unicode(string1, string2, cutoff)
      end
    end
  end

  # Finds the closest string to a given string amongst many strings.
  #
  # ```
  # require "levenshtein"
  #
  # finder = Levenshtein::Finder.new "hallo"
  # finder.test "hay"
  # finder.test "hall"
  # finder.test "hallo world"
  #
  # finder.best_match # => "hall"
  # ```
  class Finder
    # :nodoc:
    record Entry,
      value : String,
      distance : Int32

    @tolerance : Int32

    def initialize(@target : String, tolerance : Int? = nil)
      @tolerance = tolerance || (target.size / 5.0).ceil.to_i
    end

    def test(name : String, value : String = name)
      distance = Levenshtein.distance(@target, name, @tolerance)
      if distance <= @tolerance
        if best_entry = @best_entry
          if distance < best_entry.distance
            @best_entry = Entry.new(value, distance)
          end
        else
          @best_entry = Entry.new(value, distance)
        end
      end
    end

    def best_match : String?
      @best_entry.try &.value
    end

    def self.find(name, tolerance = nil, &)
      sn = new name, tolerance
      yield sn
      sn.best_match
    end

    def self.find(name, all_names, tolerance = nil) : String?
      find(name, tolerance) do |similar|
        all_names.each do |a_name|
          similar.test(a_name)
        end
      end
    end
  end

  # Finds the best match for *name* among strings added within the given block.
  # *tolerance* can be used to set maximum Levenshtein distance allowed.
  #
  # ```
  # require "levenshtein"
  #
  # best_match = Levenshtein.find("hello") do |l|
  #   l.test "hulk"
  #   l.test "holk"
  #   l.test "halka"
  #   l.test "ello"
  # end
  # best_match # => "ello"
  # ```
  def self.find(name, tolerance = nil, &) : String?
    Finder.find(name, tolerance) do |sn|
      yield sn
    end
  end

  # Finds the best match for *name* among strings provided in *all_names*.
  # *tolerance* can be used to set maximum Levenshtein distance allowed.
  #
  # ```
  # require "levenshtein"
  #
  # Levenshtein.find("hello", ["hullo", "hel", "hall", "hell"], 2) # => "hullo"
  # Levenshtein.find("hello", ["hurlo", "hel", "hall"], 1)         # => nil
  # ```
  def self.find(name, all_names, tolerance = nil) : String?
    Finder.find(name, all_names, tolerance)
  end

  # Measures Levenshtein distance by filling Dynamic Programming Matrix
  private def self.dynamic_matrix(string1 : String, string2 : String) : Int32
    s_size = string1.size
    l_size = string2.size

    costs = Slice(Int32).new(s_size + 1) { |i| i }
    last_cost = 0

    if string1.single_byte_optimizable? && string2.single_byte_optimizable?
      s = string1.to_unsafe
      l = string2.to_unsafe

      l_size.times do |i|
        last_cost = i + 1

        s_size.times do |j|
          sub_cost = l[i] == s[j] ? 0 : 1
          cost = Math.min(Math.min(last_cost + 1, costs[j + 1] + 1), costs[j] + sub_cost)
          costs[j] = last_cost
          last_cost = cost
        end
        costs[s_size] = last_cost
      end

      last_cost
    else
      reader = Char::Reader.new(string2)

      # Use an array instead of a reader to decode the second string only once
      chars = string1.chars

      reader.each_with_index do |char1, i|
        last_cost = i + 1

        chars.each_with_index do |char2, j|
          sub_cost = char1 == char2 ? 0 : 1
          cost = Math.min(Math.min(last_cost + 1, costs[j + 1] + 1), costs[j] + sub_cost)
          costs[j] = last_cost
          last_cost = cost
        end
        costs[s_size] = last_cost
      end

      last_cost
    end
  end

  # Myers Algorithm for ascii strings less than 32 bits in length
  #
  # This implmentation runs much faster than others for strings less
  # than 32 bits in length.
  private def self.myers32_ascii(string1 : String, string2 : String) : Int32
    w = 32
    one = 1_u32
    zero = 0_u32

    m = string1.size
    n = string2.size
    lpos = one << (m - 1)
    score = m

    # Setup char->bit-vector dictionary
    pmr = StaticArray(UInt32, 128).new(zero)
    s1 = string1.to_unsafe
    s2 = string2.to_unsafe

    vp = UInt32::MAX
    vn = zero

    # populate dictionary
    count = m
    count.times do |i|
      pmr[s1[i]] |= one << i
    end

    n.times do |i|
      # find char in dictionary
      pm = pmr[s2[i]]
      d0 = (((pm & vp) &+ vp) ^ vp) | pm | vn
      hp = vn | ~(d0 | vp)
      hn = d0 & vp
      if ((hp & lpos) != 0)
        score += 1
      elsif ((hn & lpos) != 0)
        score -= 1
      end
      hnx = (hn << 1)
      hpx = (hp << 1)
      vp = hnx | ~(d0 | hpx | one)
      vn = d0 & (hpx | one)
    end
    score
  end

  # Myers Algorithm for ASCII and Unicode
  #
  # The algorithm uses uses a dictionary to store string char location as bits
  # ASCII implementation uses StaticArray while for full Unicode a Hash is used
  # The bit width depends on the architecture
  {% begin %}
    {% width = flag?(:bits64) ? 64 : 32 %}
    {% for enc in ["ascii", "unicode"] %}
      private def self.myers_{{ enc.id }}(string1 : String, string2 : String, cutoff : Int? = nil) : Int32
        w = {{ width }}
        one = 1_u{{ width }}
        zero = 0_u{{ width }}
  
        m = string1.size
        n = string2.size
        rmax = (m / w).ceil.to_i
        hna = BitArray.new(n)
        hpa = BitArray.new(n)

        cutoff = cutoff || n
        # assign here so compiler guarantees int as return
        score = m
        # Setup char->bit-vector dictionary
        {% if enc == "ascii" %}
          pmr = StaticArray(UInt{{ width }}, 128).new(zero) 
          s1 = string1.to_unsafe
          s2 = string2.to_unsafe
        {% else %}
          pmr = Hash(Int32, UInt{{ width }}).new(w) { zero }
          reader = Char::Reader.new(string1)
          chars = string2.chars
        {% end %}
  
        rmax.times do |r|
          vp = UInt{{ width }}::MAX
          vn = zero

          last_r = (r == rmax-1)
          score = last_r ? m : (r+1)*w
          hmax = last_r ? ((m-1) % w) : w-1
          lpos = one << hmax

          # populate dictionary
          start = r*w
          count = last_r && ((m % w) != 0) ? (m % w) : w
          count.times do |i|
            {% if enc == "ascii" %}
              pmr[s1[start+i]] |= one << i
            {% else %}
              pmr[reader.current_char.ord] |= one << i
              reader.next_char
            {% end %}
          end

          n.times do |i|
            hn0 = hna[i].to_unsafe
            hp0 = hpa[i].to_unsafe
            # find char in dictionary
            {% if enc == "ascii" %}
              pm = pmr[s2[i]] | hn0
            {% else %}
              pm = pmr[chars[i].ord] | hn0
            {% end %}
            d0 = (((pm & vp) &+ vp) ^ vp) | pm | vn
            hp = vn | ~ (d0 | vp)
            hn = d0 & vp
            score += 1 if ((hp & lpos) != 0)
            score -= 1 if ((hn & lpos) != 0)
            hnx = (hn << 1) | hn0
            hpx = (hp << 1) | hp0
            # Horizontal arrays don't need to be saved on last run
            unless (last_r)
              hna[i] = (hn >> (w-1)) == 1
              hpa[i] = (hp >> (w-1)) == 1
            end
            nc = (r == 0) ? one : zero
            vp = hnx | ~ (d0 | hpx | nc)
            vn = d0 & (hpx | nc)
          end
          if last_r
            return score
          elsif score-(m-((r+1)*w)) > cutoff
            return score-(m-((r+1)*w))
          end
          # clear dictionary
          {% if enc == "ascii" %}
            pmr.fill(zero)
          {% else %}
            pmr.clear
          {% end %}
        end
        score
      end
    {% end %}
  {% end %}
end
