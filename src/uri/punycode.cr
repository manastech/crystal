# `Punycode` provides an interface for IDNA encoding (RFC 5980),
# which is defined in RFC 3493
#
# Implementation based on Mathias Bynens `punnycode.js` project
# https://github.com/bestiejs/punycode.js/
#
# RFC 3492:
# Method to use non-ascii characters as host name of URI
# https://www.ietf.org/rfc/rfc3492.txt
#
# RFC 5980:
# Internationalized Domain Names in Application
# https://www.ietf.org/rfc/rfc5980.txt
class URI
  class Punycode
    BASE         =  36
    TMIN         =   1
    TMAX         =  26
    SKEW         =  38
    DAMP         = 700
    INITIAL_BIAS =  72
    INITIAL_N    = 128

    DELIMITER = '-'

    BASE36 = "abcdefghijklmnopqrstuvwxyz0123456789"

    private def self.adapt(delta, numpoints, firsttime)
      delta /= firsttime ? DAMP : 2
      delta += delta / numpoints
      k = 0
      while delta > ((BASE - TMIN) * TMAX) / 2
        delta /= BASE - TMIN
        k += BASE
      end
      k + (((BASE - TMIN + 1) * delta) / (delta + SKEW))
    end

    def self.encode(string)
      String.build { |io| encode string, io }
    end

    def self.encode(string, io)
      chars = string.each_char

      h = 0
      all = true
      others = [] of Char

      chars.each do |c|
        if c < '\u0080'
          h += 1
          io << c
          all = false
        else
          others.push c
        end
      end

      return if others.empty?
      others.sort!
      io << DELIMITER unless all

      delta = 0_u32
      n = INITIAL_N
      bias = INITIAL_BIAS
      firsttime = true
      prev = nil

      h += 1
      others.each do |m|
        next if m == prev
        prev = m

        raise Exception.new("Overflow: input needs wider integers to process") if m.ord - n > (Int32::MAX - delta) / h
        delta += (m.ord - n) * h
        n = m.ord + 1

        chars.rewind.each do |c|
          if c < m
            raise Exception.new("Overflow: input needs wider integers to process") if delta > Int32::MAX - 1
            delta += 1
          elsif c == m
            q = delta
            k = BASE
            loop do
              t = k <= bias ? TMIN : k >= bias + TMAX ? TMAX : k - bias
              break if q < t
              io << BASE36[t + ((q - t) % (BASE - t))]
              q = (q - t) / (BASE - t)
              k += BASE
            end
            io << BASE36[q]

            bias = adapt delta, h, firsttime
            delta = 0
            h += 1
            firsttime = false
          end
        end
        delta += 1
      end
    end

    def self.decode(string)
      if delim = string.rindex(DELIMITER)
        output = string[0...delim].chars
        delim += 1
      else
        output = [] of Char
        delim = 0
      end

      n = INITIAL_N
      bias = INITIAL_BIAS
      i = 0
      init = true
      w = oldi = k = 0

      string[delim..-1].each_char do |c|
        if init
          w = 1
          oldi = i
          k = BASE
          init = false
        end

        digit = if 'a' <= c && c <= 'z'
                  c.ord - 0x61
                elsif 'A' <= c && c <= 'Z'
                  c.ord - 0x41
                elsif '0' <= c && c <= '9'
                  c.ord - 0x30 + 26
                else
                  raise ArgumentError.new("Invalid input")
                end

        i += digit * w
        t = k <= bias ? TMIN : k >= bias + TMAX ? TMAX : k - bias

        unless digit < t
          w *= BASE - t
          k += BASE
        else
          outsize = output.size + 1
          bias = adapt i - oldi, outsize, oldi == 0
          n += i / outsize
          i %= outsize
          output.insert i, n.chr
          i += 1
          init = true
        end
      end

      raise ArgumentError.new("Invalid input") unless init

      output.join
    end

    def self.to_ascii(string)
      return string if string.ascii_only?

      String.build do |io|
        first = true
        string.split('.').each do |part|
          unless first
            io << "."
          end

          if part.ascii_only?
            io << part
          else
            io << "xn--"
            encode part, io
          end

          first = false
        end
      end
    end
  end
end
