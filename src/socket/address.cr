require "./common"
require "uri"

class Socket
  abstract struct Address
    getter family : Family
    getter size : Int32

    # Returns either an `IPAddress` or `UNIXAddress` from the internal OS
    # representation. Only INET, INET6 and UNIX families are supported.
    def self.from(sockaddr : LibC::Sockaddr*, addrlen) : Address
      case family = Family.new(sockaddr.value.sa_family)
      when Family::INET6
        IPAddress.new(sockaddr.as(LibC::SockaddrIn6*), addrlen.to_i)
      when Family::INET
        IPAddress.new(sockaddr.as(LibC::SockaddrIn*), addrlen.to_i)
      when Family::UNIX
        UNIXAddress.new(sockaddr.as(LibC::SockaddrUn*), addrlen.to_i)
      else
        raise "Unsupported family type: #{family} (#{family.value})"
      end
    end

    # :ditto:
    def self.from(sockaddr : LibC::Sockaddr*) : Address
      case family = Family.new(sockaddr.value.sa_family)
      when Family::INET6
        sockaddr = sockaddr.as(LibC::SockaddrIn6*)

        IPAddress.new(sockaddr, sizeof(typeof(sockaddr)))
      when Family::INET
        sockaddr = sockaddr.as(LibC::SockaddrIn*)

        IPAddress.new(sockaddr, sizeof(typeof(sockaddr)))
      when Family::UNIX
        sockaddr = sockaddr.as(LibC::SockaddrUn*)

        UNIXAddress.new(sockaddr, sizeof(typeof(sockaddr)))
      else
        raise "Unsupported family type: #{family} (#{family.value})"
      end
    end

    # Parses a `Socket::Address` from an URI.
    #
    # Supported formats:
    # * `ip://<host>:<port>`
    # * `tcp://<host>:<port>`
    # * `udp://<host>:<port>`
    # * `unix://<path>`
    #
    # See `IPAddress.parse` and `UNIXAddress.parse` for details.
    def self.parse(uri : URI) : self
      case uri.scheme
      when "ip", "tcp", "udp"
        IPAddress.parse uri
      when "unix"
        UNIXAddress.parse uri
      else
        raise Socket::Error.new "Unsupported address type: #{uri.scheme}"
      end
    end

    # :ditto:
    def self.parse(uri : String) : self
      parse URI.parse(uri)
    end

    def initialize(@family : Family, @size : Int32)
    end

    abstract def to_unsafe : LibC::Sockaddr*
  end

  # IP address representation.
  #
  # Holds a binary representation of an IP address, either translated from a
  # `String`, or directly received from an opened connection (e.g.
  # `Socket#local_address`, `Socket#receive`).
  #
  # `IPAddress` won't resolve domains, including `localhost`. If you must
  # resolve an IP, or don't know whether a `String` contains an IP or a domain
  # name, you should use `Addrinfo.resolve` instead.
  struct IPAddress < Address
    UNSPECIFIED  = "0.0.0.0"
    UNSPECIFIED6 = "::"
    LOOPBACK     = "127.0.0.1"
    LOOPBACK6    = "::1"
    BROADCAST    = "255.255.255.255"
    BROADCAST6   = "ff0X::1"

    getter port : Int32
    getter scope_id : UInt32

    @addr : LibC::In6Addr | LibC::InAddr

    # Creates an `IPAddress` from the given IPv4 or IPv6 *address* and *port*
    # number.
    #
    # *address* is parsed using `.parse_v4_fields?` and `.parse_v6_fields?`.
    # Raises `Socket::Error` if *address* does not contain a valid IP address or
    # the port number is out of range.
    #
    # ```
    # require "socket"
    #
    # Socket::IPAddress.new("127.0.0.1", 8080)                 # => Socket::IPAddress(127.0.0.1:8080)
    # Socket::IPAddress.new("fe80::2ab2:bdff:fe59:8e2c", 1234) # => Socket::IPAddress([fe80::2ab2:bdff:fe59:8e2c]:1234)
    # ```
    def self.new(address : String, port : Int32)
      raise Error.new("Invalid port number: #{port}") unless IPAddress.valid_port?(port)

      addr_part, _, scope_part = address.partition('%')
      if v4_fields = parse_v4_fields?(addr_part)
        addr = v4(v4_fields, port.to_u16!)
      elsif v6_fields = parse_v6_fields?(addr_part)
        # `scope_id` is only relevant for link-local addresses, i.e. beginning with "fe80:".
        scope_id = 0u32
        if v6_fields[0] == 0xfe80 && !scope_part.empty?
          # Scope can be given either as a network interface name or directly as the interface index.
          # When given a name we need to find the corresponding interface index.
          # TODO: clarify whether this should be an ArgumentError or a Socket::Error
          if scope_part.to_u32?
            scope_id_parsed = scope_part.to_u32
            raise ArgumentError.new("Invalid IPv6 link-local scope index '#{scope_part}' in address '#{address}'") unless scope_id_parsed.positive?
            scope_id = scope_id_parsed
          else
            scope_id_parsed = LibC.if_nametoindex(scope_part).not_nil!
            raise ArgumentError.new("IPv6 link-local scope interface '#{scope_part}' not found (in address '#{address}').") unless scope_id_parsed.positive?
            scope_id = scope_id_parsed
          end
        end
        addr = v6(v6_fields, port.to_u16!, scope_id)
      else
        raise Error.new("Invalid IP address: #{address}")
      end

      addr
    end

    # Creates an `IPAddress` from the internal OS representation. Supports both
    # INET and INET6 families.
    def self.from(sockaddr : LibC::Sockaddr*, addrlen) : IPAddress
      case family = Family.new(sockaddr.value.sa_family)
      when Family::INET6
        new(sockaddr.as(LibC::SockaddrIn6*), addrlen.to_i)
      when Family::INET
        new(sockaddr.as(LibC::SockaddrIn*), addrlen.to_i)
      else
        raise "Unsupported family type: #{family} (#{family.value})"
      end
    end

    # :ditto:
    def self.from(sockaddr : LibC::Sockaddr*) : IPAddress
      case family = Family.new(sockaddr.value.sa_family)
      when Family::INET6
        sockaddr = sockaddr.as(LibC::SockaddrIn6*)

        new(sockaddr, sizeof(typeof(sockaddr)))
      when Family::INET
        sockaddr = sockaddr.as(LibC::SockaddrIn*)

        new(sockaddr, sizeof(typeof(sockaddr)))
      else
        raise "Unsupported family type: #{family} (#{family.value})"
      end
    end

    # Parses a `Socket::IPAddress` from an URI.
    #
    # It expects the URI to include `<scheme>://<host>:<port>` where `scheme` as
    # well as any additional URI components (such as `path` or `query`) are ignored.
    #
    # `host` must be an IP address (v4 or v6), otherwise `Socket::Error` will be
    # raised. Domain names will not be resolved.
    #
    # ```
    # require "socket"
    #
    # Socket::IPAddress.parse("tcp://127.0.0.1:8080") # => Socket::IPAddress.new("127.0.0.1", 8080)
    # Socket::IPAddress.parse("udp://[::1]:8080")     # => Socket::IPAddress.new("::1", 8080)
    # ```
    def self.parse(uri : URI) : IPAddress
      host = uri.host.presence
      raise Socket::Error.new("Invalid IP address: missing host") unless host

      port = uri.port
      raise Socket::Error.new("Invalid IP address: missing port") unless port

      # remove ipv6 brackets
      if host.starts_with?('[') && host.ends_with?(']')
        host = host.byte_slice(1, host.bytesize - 2)
      end

      new(host, port)
    end

    # :ditto:
    def self.parse(uri : String) : self
      parse URI.parse(uri)
    end

    # Parses *str* as an IPv4 address and returns its fields, or returns `nil`
    # if *str* does not contain a valid IPv4 address.
    #
    # The format of IPv4 addresses follows
    # [RFC 3493, section 6.3](https://datatracker.ietf.org/doc/html/rfc3493#section-6.3).
    # No extensions (e.g. octal fields, fewer than 4 fields) are supported.
    #
    # ```
    # require "socket"
    #
    # Socket::IPAddress.parse_v4_fields?("192.168.0.1")     # => UInt8.static_array(192, 168, 0, 1)
    # Socket::IPAddress.parse_v4_fields?("255.255.255.254") # => UInt8.static_array(255, 255, 255, 254)
    # Socket::IPAddress.parse_v4_fields?("01.2.3.4")        # => nil
    # ```
    def self.parse_v4_fields?(str : String) : UInt8[4]?
      parse_v4_fields?(str.to_slice)
    end

    private def self.parse_v4_fields?(bytes : Bytes)
      # port of https://git.musl-libc.org/cgit/musl/tree/src/network/inet_pton.c?id=7e13e5ae69a243b90b90d2f4b79b2a150f806335
      fields = StaticArray(UInt8, 4).new(0)
      ptr = bytes.to_unsafe
      finish = ptr + bytes.size

      4.times do |i|
        decimal = 0_u32
        old_ptr = ptr

        3.times do
          break unless ptr < finish
          ch = ptr.value &- 0x30
          break unless ch <= 0x09
          decimal = decimal &* 10 &+ ch
          ptr += 1
        end

        return nil if ptr == old_ptr                             # no decimal
        return nil if ptr - old_ptr > 1 && old_ptr.value === '0' # octal etc.
        return nil if decimal > 0xFF                             # overflow

        fields[i] = decimal.to_u8!

        break if i == 3
        return nil unless ptr < finish && ptr.value === '.'
        ptr += 1
      end

      fields if ptr == finish
    end

    # Parses *str* as an IPv6 address and returns its fields, or returns `nil`
    # if *str* does not contain a valid IPv6 address.
    #
    # The format of IPv6 addresses follows
    # [RFC 4291, section 2.2](https://datatracker.ietf.org/doc/html/rfc4291#section-2.2).
    # Both canonical and non-canonical forms are supported.
    #
    # ```
    # require "socket"
    #
    # Socket::IPAddress.parse_v6_fields?("::1")                 # => UInt16.static_array(0, 0, 0, 0, 0, 0, 0, 1)
    # Socket::IPAddress.parse_v6_fields?("a:0b:00c:000d:E:F::") # => UInt16.static_array(10, 11, 12, 13, 14, 15, 0, 0)
    # Socket::IPAddress.parse_v6_fields?("::ffff:192.168.1.1")  # => UInt16.static_array(0, 0, 0, 0, 0, 0xffff, 0xc0a8, 0x0101)
    # Socket::IPAddress.parse_v6_fields?("1::2::")              # => nil
    # ```
    def self.parse_v6_fields?(str : String) : UInt16[8]?
      parse_v6_fields?(str.to_slice)
    end

    private def self.parse_v6_fields?(bytes : Bytes)
      # port of https://git.musl-libc.org/cgit/musl/tree/src/network/inet_pton.c?id=7e13e5ae69a243b90b90d2f4b79b2a150f806335
      ptr = bytes.to_unsafe
      finish = ptr + bytes.size

      if ptr < finish && ptr.value === ':'
        ptr += 1
        return nil unless ptr < finish && ptr.value === ':'
      end

      fields = StaticArray(UInt16, 8).new(0)
      brk = -1
      need_v4 = false

      i = 0
      while true
        if ptr < finish && ptr.value === ':' && brk < 0
          brk = i
          fields[i] = 0
          ptr += 1
          break if ptr == finish
          return nil if i == 7
          i &+= 1
          next
        end

        field = 0_u16
        old_ptr = ptr

        4.times do
          break unless ptr < finish
          ch = from_hex(ptr.value)
          break unless ch <= 0x0F
          field = field.unsafe_shl(4) | ch
          ptr += 1
        end

        return nil if ptr == old_ptr # no field

        fields[i] = field
        break if ptr == finish && (brk >= 0 || i == 7)
        return nil if i == 7

        unless ptr < finish && ptr.value === ':'
          return nil if !(ptr < finish && ptr.value === '.') || (i < 6 && brk < 0)
          need_v4 = true
          i &+= 1
          fields[i] = 0
          ptr = old_ptr
          break
        end

        ptr += 1
        i &+= 1
      end

      if brk >= 0
        fields_brk = fields.to_unsafe + brk
        (fields_brk + 7 - i).move_from(fields_brk, i &+ 1 &- brk)
        fields_brk.clear(7 &- i)
      end

      if need_v4
        x0, x1, x2, x3 = parse_v4_fields?(Slice.new(ptr, finish - ptr)) || return nil
        fields[6] = x0.to_u16! << 8 | x1
        fields[7] = x2.to_u16! << 8 | x3
      end

      fields
    end

    private def self.from_hex(ch : UInt8)
      if 0x30 <= ch <= 0x39
        ch &- 0x30
      elsif 0x41 <= ch <= 0x46
        ch &- 0x37
      elsif 0x61 <= ch <= 0x66
        ch &- 0x57
      else
        0xFF_u8
      end
    end

    # Returns the IPv4 address with the given address *fields* and *port*
    # number.
    def self.v4(fields : UInt8[4], port : UInt16) : self
      addr_value = UInt32.zero
      fields.each_with_index do |field, i|
        addr_value = (addr_value << 8) | field
      end

      addr = LibC::SockaddrIn.new(
        sin_family: LibC::AF_INET,
        sin_port: endian_swap(port),
        sin_addr: LibC::InAddr.new(s_addr: endian_swap(addr_value)),
      )
      new(pointerof(addr), sizeof(typeof(addr)))
    end

    # Returns the IPv4 address `x0.x1.x2.x3:port`.
    #
    # Raises `Socket::Error` if any field or the port number is out of range.
    def self.v4(x0 : Int, x1 : Int, x2 : Int, x3 : Int, *, port : Int) : self
      fields = StaticArray[x0, x1, x2, x3].map { |field| to_v4_field(field) }
      port = valid_port?(port) ? port.to_u16! : raise Error.new("Invalid port number: #{port}")
      v4(fields, port)
    end

    private def self.to_v4_field(field)
      0 <= field <= 0xff ? field.to_u8! : raise Error.new("Invalid IPv4 field: #{field}")
    end

    # Returns the IPv6 address with the given address *fields*, *port* number
    # and scope identifier.
    def self.v6(fields : UInt16[8], port : UInt16, scope_id : UInt32 = 0u32) : self
      fields.map! { |field| endian_swap(field) }
      addr = LibC::SockaddrIn6.new(
        sin6_family: LibC::AF_INET6,
        sin6_port: endian_swap(port),
        sin6_addr: ipv6_from_addr16(fields),
        sin6_scope_id: scope_id,
      )
      new(pointerof(addr), sizeof(typeof(addr)))
    end

    # Returns the IPv6 address `[x0:x1:x2:x3:x4:x5:x6:x7]:port`.
    #
    # Raises `Socket::Error` if any field or the port number is out of range.
    def self.v6(x0 : Int, x1 : Int, x2 : Int, x3 : Int, x4 : Int, x5 : Int, x6 : Int, x7 : Int, *, port : Int, scope_id : UInt32 = 0u32) : self
      fields = StaticArray[x0, x1, x2, x3, x4, x5, x6, x7].map { |field| to_v6_field(field) }
      port = valid_port?(port) ? port.to_u16! : raise Error.new("Invalid port number: #{port}")
      v6(fields, port, scope_id)
    end

    private def self.to_v6_field(field)
      0 <= field <= 0xffff ? field.to_u16! : raise Error.new("Invalid IPv6 field: #{field}")
    end

    # Returns the IPv4-mapped IPv6 address with the given IPv4 address *fields*
    # and *port* number.
    def self.v4_mapped_v6(fields : UInt8[4], port : UInt16) : self
      v6_fields = StaticArray[
        0_u16, 0_u16, 0_u16, 0_u16, 0_u16, 0xffff_u16,
        fields[0].to_u16! << 8 | fields[1],
        fields[2].to_u16! << 8 | fields[3],
      ]
      v6(v6_fields, port)
    end

    # Returns the IPv4-mapped IPv6 address `[::ffff:x0.x1.x2.x3]:port`.
    #
    # Raises `Socket::Error` if any field or the port number is out of range.
    def self.v4_mapped_v6(x0 : Int, x1 : Int, x2 : Int, x3 : Int, *, port : Int) : self
      v4_fields = StaticArray[x0, x1, x2, x3].map { |field| to_v4_field(field) }
      port = valid_port?(port) ? port.to_u16! : raise Error.new("Invalid port number: #{port}")
      v4_mapped_v6(v4_fields, port)
    end

    private def self.ipv6_from_addr16(bytes : UInt16[8])
      addr = LibC::In6Addr.new
      {% if flag?(:darwin) || flag?(:bsd) %}
        addr.__u6_addr.__u6_addr16 = bytes
      {% elsif flag?(:linux) && flag?(:musl) %}
        addr.__in6_union.__s6_addr16 = bytes
      {% elsif flag?(:wasm32) %}
        bytes.each_with_index do |byte, i|
          addr.s6_addr[2 * i] = byte.to_u8!
          addr.s6_addr[2 * i + 1] = (byte >> 8).to_u8!
        end
      {% elsif flag?(:linux) %}
        addr.__in6_u.__u6_addr16 = bytes
      {% elsif flag?(:solaris) %}
        addr._S6_un._S6_u16 = bytes
      {% elsif flag?(:win32) %}
        addr.u.word = bytes
      {% else %}
        {% raise "Unsupported platform" %}
      {% end %}
      addr
    end

    protected def initialize(sockaddr : LibC::SockaddrIn6*, @size)
      @family = Family::INET6
      @addr = sockaddr.value.sin6_addr
      @scope_id = sockaddr.value.sin6_scope_id
      @port = IPAddress.endian_swap(sockaddr.value.sin6_port).to_i
    end

    protected def initialize(sockaddr : LibC::SockaddrIn*, @size)
      @family = Family::INET
      @addr = sockaddr.value.sin_addr
      @scope_id = 0u32
      @port = IPAddress.endian_swap(sockaddr.value.sin_port).to_i
    end

    # Returns `true` if *address* is a valid IPv4 or IPv6 address.
    def self.valid?(address : String) : Bool
      valid_v4?(address) || valid_v6?(address)
    end

    # Returns `true` if *address* is a valid IPv6 address.
    def self.valid_v6?(address : String) : Bool
      !parse_v6_fields?(address).nil?
    end

    # Returns `true` if *address* is a valid IPv4 address.
    def self.valid_v4?(address : String) : Bool
      !parse_v4_fields?(address).nil?
    end

    # Returns a `String` representation of the IP address, without the port
    # number.
    #
    # IPv6 addresses are canonicalized according to
    # [RFC 5952, section 4](https://datatracker.ietf.org/doc/html/rfc5952#section-4).
    # IPv4-mapped IPv6 addresses use the mixed notation according to RFC 5952,
    # section 5.
    #
    # ```
    # require "socket"
    #
    # v4 = Socket::IPAddress.v4(UInt8.static_array(127, 0, 0, 1), 8080)
    # v4.address # => "127.0.0.1"
    #
    # v6 = Socket::IPAddress.v6(UInt16.static_array(0x2001, 0xdb8, 0, 0, 1, 0, 0, 1), 443)
    # v6.address # => "2001:db8::1:0:0:1"
    #
    # mapped = Socket::IPAddress.v4_mapped_v6(UInt8.static_array(192, 168, 1, 15), 55001)
    # mapped.address # => "::ffff:192.168.1.15"
    # ```
    #
    # To obtain both the address and the port number in one string, see `#to_s`.
    def address : String
      case addr = @addr
      in LibC::InAddr
        String.build(IPV4_MAX_SIZE) do |io|
          address_to_s(io, addr)
        end
      in LibC::In6Addr
        String.build(IPV6_MAX_SIZE) do |io|
          address_to_s(io, addr)
        end
      end
    end

    private IPV4_MAX_SIZE = 15 # "255.255.255.255".size

    # NOTE: INET6_ADDRSTRLEN is 46 bytes (including the terminating null
    # character), but it is only attainable for mixed-notation addresses that
    # use all 24 hexadecimal digits in the IPv6 field part, which we do not
    # support
    private IPV6_MAX_SIZE = 39 # "ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff".size

    # Returns `true` if this IP is a loopback address.
    #
    # In the IPv4 family, loopback addresses are all addresses in the subnet
    # `127.0.0.0/24`. In IPv6 `::1` is the loopback address.
    def loopback? : Bool
      case addr = @addr
      in LibC::InAddr
        addr.s_addr & 0x000000ff_u32 == 0x0000007f_u32
      in LibC::In6Addr
        addr8 = ipv6_addr8(addr)
        num = addr8.unsafe_as(UInt128)
        # TODO: Use UInt128 literals
        num == (1_u128 << 120) ||                         # "::1"
          num & UInt128::MAX >> 24 == 0x7fffff_u128 << 80 # "::ffff:127.0.0.1/104"
      end
    end

    # Returns `true` if this IP is an unspecified address, either the IPv4 address `0.0.0.0` or the IPv6 address `::`.
    def unspecified? : Bool
      case addr = @addr
      in LibC::InAddr
        addr.s_addr == 0_u32
      in LibC::In6Addr
        ipv6_addr8(addr) == StaticArray[0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8]
      end
    end

    # Returns `true` if this IP is a private address.
    #
    # IPv4 addresses in `10.0.0.0/8`, `172.16.0.0/12` and `192.168.0.0/16` as defined in [RFC 1918](https://tools.ietf.org/html/rfc1918)
    # and IPv6 Unique Local Addresses in `fc00::/7` as defined in [RFC 4193](https://tools.ietf.org/html/rfc4193) are considered private.
    def private? : Bool
      case addr = @addr
      in LibC::InAddr
        addr.s_addr & 0x000000ff_u32 == 0x00000000a_u32 ||     # 10.0.0.0/8
          addr.s_addr & 0x000000f0ff_u32 == 0x0000010ac_u32 || # 172.16.0.0/12
          addr.s_addr & 0x000000ffff_u32 == 0x0000a8c0_u32     # 192.168.0.0/16
      in LibC::In6Addr
        ipv6_addr8(addr)[0] & 0xfe_u8 == 0xfc_u8
      end
    end

    # Returns `true` if this IP is a link-local address.
    #
    # IPv4 addresses in `169.254.0.0/16` reserved by [RFC 3927](https://www.rfc-editor.org/rfc/rfc3927) and Link-Local IPv6
    # Unicast Addresses in `fe80::/10` reserved by [RFC 4291](https://tools.ietf.org/html/rfc4291) are considered link-local.
    def link_local?
      case addr = @addr
      in LibC::InAddr
        addr.s_addr & 0x000000ffff_u32 == 0x0000fea9_u32 # 169.254.0.0/16
      in LibC::In6Addr
        ipv6_addr8(addr).unsafe_as(UInt128) & 0xc0ff_u128 == 0x80fe_u128
      end
    end

    private def ipv6_addr8(addr : LibC::In6Addr)
      {% if flag?(:darwin) || flag?(:bsd) %}
        addr.__u6_addr.__u6_addr8
      {% elsif flag?(:linux) && flag?(:musl) %}
        addr.__in6_union.__s6_addr
      {% elsif flag?(:wasm32) %}
        addr.s6_addr
      {% elsif flag?(:linux) %}
        addr.__in6_u.__u6_addr8
      {% elsif flag?(:solaris) %}
        addr._S6_un._S6_u8
      {% elsif flag?(:win32) %}
        addr.u.byte
      {% else %}
        {% raise "Unsupported platform" %}
      {% end %}
    end

    def_equals_and_hash family, port, address_value

    protected def address_value
      case addr = @addr
      in LibC::InAddr
        addr.s_addr
      in LibC::In6Addr
        ipv6_addr8(addr).unsafe_as(UInt128)
      end
    end

    # Writes the `String` representation of the IP address plus the port number
    # to the given *io*.
    #
    # IPv6 addresses are canonicalized according to
    # [RFC 5952, section 4](https://datatracker.ietf.org/doc/html/rfc5952#section-4),
    # and surrounded within a pair of square brackets according to
    # [RFC 3986](https://datatracker.ietf.org/doc/html/rfc3986).
    # IPv4-mapped IPv6 addresses use the mixed notation according to RFC 5952,
    # section 5.
    #
    # To obtain the address alone without the port number, see `#address`.
    def to_s(io : IO) : Nil
      case addr = @addr
      in LibC::InAddr
        address_to_s(io, addr)
        io << ':' << port
      in LibC::In6Addr
        io << '['
        address_to_s(io, addr)
        io << ']' << ':' << port
      end
    end

    private def address_to_s(io : IO, addr : LibC::InAddr)
      io << (addr.s_addr & 0xFF)
      io << '.' << (addr.s_addr >> 8 & 0xFF)
      io << '.' << (addr.s_addr >> 16 & 0xFF)
      io << '.' << (addr.s_addr >> 24)
    end

    private def address_to_s(io : IO, addr : LibC::In6Addr)
      bytes = ipv6_addr8(addr)
      if Slice.new(bytes.to_unsafe, 10).all?(&.zero?) && bytes[10] == 0xFF && bytes[11] == 0xFF
        io << "::ffff:" << bytes[12] << '.' << bytes[13] << '.' << bytes[14] << '.' << bytes[15]
      else
        fields = bytes.unsafe_as(StaticArray(UInt16, 8)).map! { |field| IPAddress.endian_swap(field) }

        zeros_start = nil
        zeros_count_max = 1

        count = 0
        fields.each_with_index do |field, i|
          if field == 0
            count += 1
            if count > zeros_count_max
              zeros_start = i - count + 1
              zeros_count_max = count
            end
          else
            count = 0
          end
        end

        i = 0
        while i < 8
          if i == zeros_start
            io << ':'
            i += zeros_count_max
            io << ':' if i == 8
          else
            io << ':' if i > 0
            fields[i].to_s(io, base: 16)
            i += 1
          end
        end
      end
    end

    private IPV4_FULL_MAX_SIZE = IPV4_MAX_SIZE + 6 # ":65535".size
    private IPV6_FULL_MAX_SIZE = IPV6_MAX_SIZE + 8 # "[".size + "]:65535".size

    # Returns a `String` representation of the IP address plus the port number.
    #
    # IPv6 addresses are canonicalized according to
    # [RFC 5952, section 4](https://datatracker.ietf.org/doc/html/rfc5952#section-4),
    # and surrounded within a pair of square brackets according to
    # [RFC 3986](https://datatracker.ietf.org/doc/html/rfc3986).
    # IPv4-mapped IPv6 addresses use the mixed notation according to RFC 5952,
    # section 5.
    #
    # ```
    # require "socket"
    #
    # v4 = Socket::IPAddress.v4(UInt8.static_array(127, 0, 0, 1), 8080)
    # v4.to_s # => "127.0.0.1:8080"
    #
    # v6 = Socket::IPAddress.v6(UInt16.static_array(0x2001, 0xdb8, 0, 0, 1, 0, 0, 1), 443)
    # v6.to_s # => "[2001:db8::1:0:0:1]:443"
    #
    # mapped = Socket::IPAddress.v4_mapped_v6(UInt8.static_array(192, 168, 1, 15), 55001)
    # mapped.to_s # => "[::ffff:192.168.1.15]:55001"
    # ```
    #
    # To obtain the address alone without the port number, see `#address`.
    def to_s : String
      String.build(@addr.is_a?(LibC::InAddr) ? IPV4_FULL_MAX_SIZE : IPV6_FULL_MAX_SIZE) do |io|
        to_s(io)
      end
    end

    def inspect(io : IO) : Nil
      io << "Socket::IPAddress("
      to_s(io)
      io << ")"
    end

    def inspect : String
      # 19 == "Socket::IPAddress(".size + ")".size
      String.build((@addr.is_a?(LibC::InAddr) ? IPV4_FULL_MAX_SIZE : IPV6_FULL_MAX_SIZE) + 19) do |io|
        inspect(io)
      end
    end

    def pretty_print(pp)
      pp.text inspect
    end

    def to_unsafe : LibC::Sockaddr*
      case addr = @addr
      in LibC::InAddr
        to_sockaddr_in(addr)
      in LibC::In6Addr
        to_sockaddr_in6(addr)
      end
    end

    private def to_sockaddr_in6(addr)
      sockaddr = Pointer(LibC::SockaddrIn6).malloc
      sockaddr.value.sin6_family = family
      sockaddr.value.sin6_port = IPAddress.endian_swap(port.to_u16!)
      sockaddr.value.sin6_addr = addr
      if @family == Family::INET6 && link_local?
        sockaddr.value.sin6_scope_id = @scope_id
      else
        sockaddr.value.sin6_scope_id = 0
      end
      sockaddr.as(LibC::Sockaddr*)
    end

    private def to_sockaddr_in(addr)
      sockaddr = Pointer(LibC::SockaddrIn).malloc
      sockaddr.value.sin_family = family
      sockaddr.value.sin_port = IPAddress.endian_swap(port.to_u16!)
      sockaddr.value.sin_addr = addr
      sockaddr.as(LibC::Sockaddr*)
    end

    protected def self.endian_swap(x : Int::Primitive) : Int::Primitive
      {% if IO::ByteFormat::NetworkEndian != IO::ByteFormat::SystemEndian %}
        x.byte_swap
      {% else %}
        x
      {% end %}
    end

    # Returns `true` if *port* is a valid port number.
    #
    # Valid port numbers are in the range `0..65_535`.
    def self.valid_port?(port : Int) : Bool
      port.in?(0..UInt16::MAX)
    end
  end

  # UNIX address representation.
  #
  # Holds the local path of an UNIX address, usually coming from an opened
  # connection (e.g. `Socket#local_address`, `Socket#receive`).
  #
  # Example:
  # ```
  # require "socket"
  #
  # Socket::UNIXAddress.new("/tmp/my.sock")
  # ```
  struct UNIXAddress < Address
    getter path : String

    # :nodoc:
    MAX_PATH_SIZE = {% if flag?(:wasm32) %}
                      0
                    {% else %}
                      sizeof(typeof(LibC::SockaddrUn.new.sun_path)) - 1
                    {% end %}

    def initialize(@path : String)
      if @path.bytesize > MAX_PATH_SIZE
        raise ArgumentError.new("Path size exceeds the maximum size of #{MAX_PATH_SIZE} bytes")
      end
      @family = Family::UNIX
      @size = {% if flag?(:wasm32) %}
                1
              {% else %}
                sizeof(LibC::SockaddrUn)
              {% end %}
    end

    # Creates an `UNIXSocket` from the internal OS representation.
    def self.from(sockaddr : LibC::Sockaddr*, addrlen) : UNIXAddress
      {% if flag?(:wasm32) %}
        raise NotImplementedError.new "Socket::UNIXAddress.from"
      {% else %}
        new(sockaddr.as(LibC::SockaddrUn*), addrlen.to_i)
      {% end %}
    end

    # :ditto:
    def self.from(sockaddr : LibC::Sockaddr*) : UNIXAddress
      {% if flag?(:wasm32) %}
        raise NotImplementedError.new "Socket::UNIXAddress.from"
      {% else %}
        sockaddr = sockaddr.as(LibC::SockaddrUn*)

        new(sockaddr, sizeof(typeof(sockaddr)))
      {% end %}
    end

    # Parses a `Socket::UNIXAddress` from an URI.
    #
    # It expects the URI to include `<scheme>://<path>` where `scheme` as well
    # as any additional URI components (such as `fragment` or `query`) are ignored.
    #
    # If `host` is not empty, it will be prepended to `path` to form a relative
    # path.
    #
    # ```
    # require "socket"
    #
    # Socket::UNIXAddress.parse("unix:///foo.sock") # => Socket::UNIXAddress.new("/foo.sock")
    # Socket::UNIXAddress.parse("unix://foo.sock")  # => Socket::UNIXAddress.new("foo.sock")
    # ```
    def self.parse(uri : URI) : UNIXAddress
      unix_path = String.build do |io|
        io << uri.host
        if port = uri.port
          io << ':' << port
        end
        if path = uri.path.presence
          io << path
        end
      end

      raise Socket::Error.new("Invalid UNIX address: missing path") if unix_path.empty?

      {% if flag?(:wasm32) %}
        raise NotImplementedError.new "Socket::UNIXAddress.parse"
      {% else %}
        UNIXAddress.new(unix_path)
      {% end %}
    end

    # :ditto:
    def self.parse(uri : String) : self
      parse URI.parse(uri)
    end

    {% unless flag?(:wasm32) %}
      protected def initialize(sockaddr : LibC::SockaddrUn*, size)
        @family = Family::UNIX
        @path = String.new(sockaddr.value.sun_path.to_unsafe)
        @size = size || sizeof(LibC::SockaddrUn)
      end
    {% end %}

    def_equals_and_hash path

    def to_s(io : IO) : Nil
      io << path
    end

    def to_unsafe : LibC::Sockaddr*
      {% if flag?(:wasm32) %}
        raise NotImplementedError.new "Socket::UNIXAddress#to_unsafe"
      {% else %}
        sockaddr = Pointer(LibC::SockaddrUn).malloc
        sockaddr.value.sun_family = family
        sockaddr.value.sun_path.to_unsafe.copy_from(@path.to_unsafe, @path.bytesize + 1)
        sockaddr.as(LibC::Sockaddr*)
      {% end %}
    end
  end

  # Returns `true` if the string represents a valid IPv4 or IPv6 address.
  @[Deprecated("Use `IPAddress.valid?` instead")]
  def self.ip?(string : String)
    IPAddress.valid?(string)
  end
end
