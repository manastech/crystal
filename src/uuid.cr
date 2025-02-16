require "time"
require "io"

{% if flag?(:without_openssl) %}
  require "crystal/digest/sha1"
  require "crystal/digest/md5"
{% else %}
  require "digest/sha1"
  require "digest/md5"
{% end %}

# Represents a UUID (Universally Unique IDentifier).
#
# NOTE: To use `UUID`, you must explicitly import it with `require "uuid"`
struct UUID
  include Comparable(UUID)

  # Variants with 16 bytes.
  enum Variant
    # Unknown (i.e. custom, your own).
    Unknown
    # Reserved by the NCS for backward compatibility.
    NCS
    # Reserved for RFC 4122 Specification (default).
    RFC4122
    # Reserved for RFC 9562 Specification (default for v7).
    RFC9562 = RFC4122
    # Reserved by Microsoft for backward compatibility.
    Microsoft
    # Reserved for future expansion.
    Future
  end

  # RFC4122 UUID versions.
  enum Version
    # Unknown version.
    Unknown = 0
    # Date-time and NodeID address.
    V1 = 1
    # DCE security.
    V2 = 2
    # MD5 hash and namespace.
    V3 = 3
    # Random.
    V4 = 4
    # SHA1 hash and namespace.
    V5 = 5
    # Prefixed with a UNIX timestamp with millisecond precision, filled in with randomness.
    V7 = 7
  end

  # A Domain represents a Version 2 domain (DCE security).
  enum Domain
    Person = 0
    Group  = 1
    Org    = 2
  end

  # MAC address to be used as NodeID.
  alias MAC = UInt8[6]

  # Namespaces as defined per in the RFC 4122 Appendix C.
  #
  # They are used with the functions `v3` amd `v5` to generate
  # a `UUID` based on a `name`.
  module Namespace
    # A UUID is generated using the provided `name`, which is assumed to be a fully qualified domain name.
    DNS = UUID.new("6ba7b810-9dad-11d1-80b4-00c04fd430c8")
    # A UUID is generated using the provided `name`, which is assumed to be a URL.
    URL = UUID.new("6ba7b811-9dad-11d1-80b4-00c04fd430c8")
    # A UUID is generated using the provided `name`, which is assumed to be an ISO OID.
    OID = UUID.new("6ba7b812-9dad-11d1-80b4-00c04fd430c8")
    # A UUID is generated using the provided `name`, which is assumed to be a X.500 DN in DER or a text output format.
    X500 = UUID.new("6ba7b814-9dad-11d1-80b4-00c04fd430c8")
  end

  @bytes : StaticArray(UInt8, 16)

  # Generates UUID from *bytes*, applying *version* and *variant* to the UUID if
  # present.
  def initialize(@bytes : StaticArray(UInt8, 16), variant : UUID::Variant? = nil, version : UUID::Version? = nil)
    case variant
    when nil
      # do nothing
    when Variant::NCS
      @bytes[8] = (@bytes[8] & 0x7f)
    when Variant::RFC4122, Variant::RFC9562
      @bytes[8] = (@bytes[8] & 0x3f) | 0x80
    when Variant::Microsoft
      @bytes[8] = (@bytes[8] & 0x1f) | 0xc0
    when Variant::Future
      @bytes[8] = (@bytes[8] & 0x1f) | 0xe0
    else
      raise ArgumentError.new "Can't set unknown variant"
    end

    if version
      raise ArgumentError.new "Can't set unknown version" if version.unknown?
      @bytes[6] = (@bytes[6] & 0xf) | (version.to_u8 << 4)
    end
  end

  # Creates UUID from 16-bytes slice. Raises if *slice* isn't 16 bytes long. See
  # `#initialize` for *variant* and *version*.
  def self.new(slice : Slice(UInt8), variant : Variant? = nil, version : Version? = nil)
    raise ArgumentError.new "Invalid bytes length #{slice.size}, expected 16" unless slice.size == 16

    bytes = uninitialized UInt8[16]
    slice.copy_to(bytes.to_slice)

    new(bytes, variant, version)
  end

  # Creates another `UUID` which is a copy of *uuid*, but allows overriding
  # *variant* or *version*.
  def self.new(uuid : UUID, variant : Variant? = nil, version : Version? = nil)
    new(uuid.bytes, variant, version)
  end

  # Creates new UUID by decoding `value` string from hyphenated (ie `ba714f86-cac6-42c7-8956-bcf5105e1b81`),
  # hexstring (ie `89370a4ab66440c8add39e06f2bb6af6`) or URN (ie `urn:uuid:3f9eaf9e-cdb0-45cc-8ecb-0e5b2bfb0c20`)
  # format, raising an `ArgumentError` if the string does not match any of these formats.
  def self.new(value : String, variant : Variant? = nil, version : Version? = nil)
    bytes = uninitialized UInt8[16]

    case value.size
    when 36 # Hyphenated
      {8, 13, 18, 23}.each do |offset|
        if value[offset] != '-'
          raise ArgumentError.new "Invalid UUID string format, expected hyphen at char #{offset}"
        end
      end
      {0, 2, 4, 6, 9, 11, 14, 16, 19, 21, 24, 26, 28, 30, 32, 34}.each_with_index do |offset, i|
        bytes[i] = hex_pair_at value, offset
      end
    when 32 # Hexstring
      16.times do |i|
        bytes[i] = hex_pair_at value, i * 2
      end
    when 45 # URN
      raise ArgumentError.new "Invalid URN UUID format, expected string starting with \"urn:uuid:\"" unless value.starts_with? "urn:uuid:"
      {9, 11, 13, 15, 18, 20, 23, 25, 28, 30, 33, 35, 37, 39, 41, 43}.each_with_index do |offset, i|
        bytes[i] = hex_pair_at value, offset
      end
    else
      raise ArgumentError.new "Invalid string length #{value.size} for UUID, expected 32 (hexstring), 36 (hyphenated) or 45 (urn)"
    end

    new(bytes, variant, version)
  end

  # Creates new UUID by decoding `value` string from hyphenated (ie `ba714f86-cac6-42c7-8956-bcf5105e1b81`),
  # hexstring (ie `89370a4ab66440c8add39e06f2bb6af6`) or URN (ie `urn:uuid:3f9eaf9e-cdb0-45cc-8ecb-0e5b2bfb0c20`)
  # format, returning `nil` if the string does not match any of these formats.
  def self.parse?(value : String, variant : Variant? = nil, version : Version? = nil) : UUID?
    bytes = uninitialized UInt8[16]

    case value.size
    when 36 # Hyphenated
      {8, 13, 18, 23}.each do |offset|
        return if value[offset] != '-'
      end
      {0, 2, 4, 6, 9, 11, 14, 16, 19, 21, 24, 26, 28, 30, 32, 34}.each_with_index do |offset, i|
        if hex = hex_pair_at? value, offset
          bytes[i] = hex
        else
          return
        end
      end
    when 32 # Hexstring
      16.times do |i|
        if hex = hex_pair_at? value, i * 2
          bytes[i] = hex
        else
          return
        end
      end
    when 45 # URN
      return unless value.starts_with? "urn:uuid:"
      {9, 11, 13, 15, 18, 20, 23, 25, 28, 30, 33, 35, 37, 39, 41, 43}.each_with_index do |offset, i|
        if hex = hex_pair_at? value, offset
          bytes[i] = hex
        else
          return
        end
      end
    else
      return
    end

    new(bytes, variant, version)
  end

  # Raises `ArgumentError` if string `value` at index `i` doesn't contain hex
  # digit followed by another hex digit.
  private def self.hex_pair_at(value : String, i) : UInt8
    hex_pair_at?(value, i) || raise ArgumentError.new "Invalid hex character at position #{i * 2} or #{i * 2 + 1}, expected '0' to '9', 'a' to 'f' or 'A' to 'F'"
  end

  # Parses 2 hex digits from `value` at index `i` and `i + 1`, returning `nil`
  # if one or both are not actually hex digits.
  private def self.hex_pair_at?(value : String, i) : UInt8?
    if (ch1 = value[i].to_u8?(16)) && (ch2 = value[i + 1].to_u8?(16))
      ch1 * 16 + ch2
    end
  end

  # Generates RFC 4122 v4 UUID.
  #
  # It is strongly recommended to use a cryptographically random source for
  # *random*, such as `Random::Secure`.
  def self.random(random : Random = Random::Secure, variant : Variant = :rfc4122, version : Version = :v4) : self
    new_bytes = uninitialized UInt8[16]
    random.random_bytes(new_bytes.to_slice)

    new(new_bytes, variant, version)
  end

  # Generates RFC 4122 v1 UUID.
  #
  # The traditional method for generating a `node_id` involves using the machine’s MAC address.
  # However, this approach is only effective if there is only one process running on the machine
  # and if privacy is not a concern. In modern languages, the default is to prioritize security
  # and privacy. Therefore, a pseudo-random `node_id` is generated as described in section 4.5 of
  # the RFC.
  #
  # The sequence number `clock_seq` is used to generate the UUID. This number should be
  # monotonically increasing, with only 14 bits of the clock sequence being used effectively.
  # The clock sequence should be stored in a stable location, such as a file. If it is not
  # stored, a random value is used by default. If not provided the current time milliseconds
  # are used. In case the traditional MAC address based approach should be taken the
  # `node_id` can be provided. Otherwise secure random is used.
  def self.v1(*, clock_seq : UInt16? = nil, node_id : MAC? = nil) : self
    tl = Time.local
    now = (tl.to_unix_ns / 100).to_u64 + 122192928000000000
    seq = ((clock_seq || (tl.nanosecond/1000000).to_u16) & 0x3fff) | 0x8000

    time_low = UInt32.new(now & 0xffffffff)
    time_mid = UInt16.new((now >> 32) & 0xffff)
    time_hi = UInt16.new((now >> 48) & 0x0fff)
    time_hi |= 0x1000 # Version 1

    uuid = uninitialized UInt8[16]
    IO::ByteFormat::BigEndian.encode(time_low, uuid.to_slice[0..3])
    IO::ByteFormat::BigEndian.encode(time_mid, uuid.to_slice[4..5])
    IO::ByteFormat::BigEndian.encode(time_hi, uuid.to_slice[6..7])
    IO::ByteFormat::BigEndian.encode(seq, uuid.to_slice[8..9])

    if node_id
      6.times do |i|
        uuid.to_slice[10 + i] = node_id[i]
      end
    else
      Random::Secure.random_bytes(uuid.to_slice[10..15])
      # set multicast bit as recommended per section 4.5 of the RFC 4122 spec
      # to not conflict with real MAC addresses
      uuid[10] |= 0x01_u8
    end

    new(uuid, version: UUID::Version::V1, variant: UUID::Variant::RFC4122)
  end

  # Generates RFC 4122 v2 UUID.
  #
  # Version 2 UUIDs are generated using the current time, the local machine’s MAC address,
  # and the local user or group ID. However, they are not widely used due to their limitations.
  # For a given domain/id pair, the same token may be returned for a duration of up to 7 minutes
  # and 10 seconds.
  #
  # The `id` depends on the `domain`, for the `Domain::Person` usually the local user id (uid) is
  # used, for `Domain::Group` usually the local group id (gid) is used. In case the traditional
  # MAC address based approach should be taken the `node_id` can be provided. Otherwise secure
  # random is used.
  def self.v2(domain : Domain, id : UInt32, node_id : MAC? = nil) : self
    uuid = v1(node_id: node_id).bytes
    uuid[6] = (uuid[6] & 0x0f) | 0x20 # Version 2
    uuid[9] = domain.to_u8
    IO::ByteFormat::BigEndian.encode(id, uuid.to_slice[0..3])
    new(uuid, version: UUID::Version::V2, variant: UUID::Variant::RFC4122)
  end

  # Generates RFC 4122 v3 UUID using the `name` to generate the UUID, it can be a string of any size.
  # The `namespace` specifies the type of the name, usually one of `Namespace`.
  def self.v3(name : String, namespace : UUID) : self
    klass = {% if flag?(:without_openssl) %}::Crystal::Digest::MD5{% else %}::Digest::MD5{% end %}
    hash = klass.digest do |ctx|
      ctx.update namespace.bytes
      ctx.update name
    end
    new(hash[0...16], version: UUID::Version::V3, variant: UUID::Variant::RFC4122)
  end

  # Generates RFC 4122 v4 UUID.
  #
  # It is strongly recommended to use a cryptographically random source for
  # *random*, such as `Random::Secure`.
  def self.v4(random r : Random = Random::Secure) : self
    random(r)
  end

  # Generates RFC 4122 v5 UUID using the `name` to generate the UUID, it can be a string of any size.
  # The `namespace` specifies the type of the name, usually one of `Namespace`.
  def self.v5(name : String, namespace : UUID) : self
    klass = {% if flag?(:without_openssl) %}::Crystal::Digest::SHA1{% else %}::Digest::SHA1{% end %}
    hash = klass.digest do |ctx|
      ctx.update namespace.bytes
      ctx.update name
    end
    new(hash[0...16], version: UUID::Version::V5, variant: UUID::Variant::RFC4122)
  end

  {% for name in %w(DNS URL OID X500).map(&.id) %}
    # Generates RFC 4122 v3 UUID with the `Namespace::{{ name }}`.
    #
    # * `name`: The name used to generate the UUID, it can be a string of any size.
    def self.v3_{{ name.downcase }}(name : String)
      v3(name, Namespace::{{ name }})
    end

    # Generates RFC 4122 v5 UUID with the `Namespace::{{ name }}`.
    #
    # * `name`: The name used to generate the UUID, it can be a string of any size.
    def self.v5_{{ name.downcase }}(name : String)
      v5(name, Namespace::{{ name }})
    end
  {% end %}

  # Generates an RFC9562-compatible v7 UUID, allowing the values to be sorted
  # chronologically (with 1ms precision) by their raw or hexstring
  # representation.
  def self.v7(random r : Random = Random::Secure)
    buffer = uninitialized UInt8[18]
    value = buffer.to_slice

    # Generate the first 48 bits of the UUID with the current timestamp. We
    # allocated enough room for a 64-bit timestamp to accommodate the
    # NetworkEndian.encode call here, but we only need 48 bits of it so we chop
    # off the first 2 bytes.
    IO::ByteFormat::NetworkEndian.encode Time.utc.to_unix_ms, value
    value = value[2..]

    # Fill in the rest with random bytes
    r.random_bytes(value[6..])

    # Set the version and variant
    value[6] = (value[6] & 0x3F) | 0x70
    value[8] = (value[8] & 0x0F) | 0x80

    new(value, variant: :rfc9562, version: :v7)
  end

  # Generates an empty UUID.
  #
  # ```
  # UUID.empty # => UUID["00000000-0000-4000-0000-000000000000"]
  # ```
  def self.empty : self
    new(StaticArray(UInt8, 16).new(0_u8), UUID::Variant::NCS, UUID::Version::V4)
  end

  # Returns UUID variant based on the [RFC4122 format](https://datatracker.ietf.org/doc/html/rfc4122#section-4.1).
  # See also `#version`
  #
  # ```
  # require "uuid"
  #
  # UUID.new(Slice.new(16, 0_u8), variant: UUID::Variant::NCS).variant       # => UUID::Variant::NCS
  # UUID.new(Slice.new(16, 0_u8), variant: UUID::Variant::RFC4122).variant   # => UUID::Variant::RFC4122
  # UUID.new(Slice.new(16, 0_u8), variant: UUID::Variant::Microsoft).variant # => UUID::Variant::Microsoft
  # UUID.new(Slice.new(16, 0_u8), variant: UUID::Variant::Future).variant    # => UUID::Variant::Future
  # ```
  def variant : UUID::Variant
    case
    when @bytes[8] & 0x80 == 0x00
      Variant::NCS
    when @bytes[8] & 0xc0 == 0x80
      Variant::RFC4122
    when @bytes[8] & 0xe0 == 0xc0
      Variant::Microsoft
    when @bytes[8] & 0xe0 == 0xe0
      Variant::Future
    else
      Variant::Unknown
    end
  end

  # Returns version based on [RFC4122 format](https://datatracker.ietf.org/doc/html/rfc4122#section-4.1).
  # See also `#variant`.
  #
  # ```
  # require "uuid"
  #
  # UUID.new(Slice.new(16, 0_u8), version: UUID::Version::V1).version # => UUID::Version::V1
  # UUID.new(Slice.new(16, 0_u8), version: UUID::Version::V2).version # => UUID::Version::V2
  # UUID.new(Slice.new(16, 0_u8), version: UUID::Version::V3).version # => UUID::Version::V3
  # UUID.new(Slice.new(16, 0_u8), version: UUID::Version::V4).version # => UUID::Version::V4
  # UUID.new(Slice.new(16, 0_u8), version: UUID::Version::V5).version # => UUID::Version::V5
  # ```
  def version : UUID::Version
    case @bytes[6] >> 4
    when 1 then Version::V1
    when 2 then Version::V2
    when 3 then Version::V3
    when 4 then Version::V4
    when 5 then Version::V5
    when 7 then Version::V7
    else        Version::Unknown
    end
  end

  # Returns the binary representation of the UUID.
  def bytes : StaticArray(UInt8, 16)
    @bytes.dup
  end

  # Returns unsafe pointer to 16-bytes.
  def to_unsafe
    @bytes.to_unsafe
  end

  def_equals_and_hash @bytes

  # Convert to `String` in literal format.
  def inspect(io : IO) : Nil
    io << %(UUID[")
    to_s(io)
    io << %("])
  end

  def to_s(io : IO) : Nil
    slice = @bytes.to_slice

    buffer = uninitialized UInt8[36]
    buffer_ptr = buffer.to_unsafe

    buffer_ptr[8] = buffer_ptr[13] = buffer_ptr[18] = buffer_ptr[23] = '-'.ord.to_u8
    slice[0, 4].hexstring(buffer_ptr + 0)
    slice[4, 2].hexstring(buffer_ptr + 9)
    slice[6, 2].hexstring(buffer_ptr + 14)
    slice[8, 2].hexstring(buffer_ptr + 19)
    slice[10, 6].hexstring(buffer_ptr + 24)

    io.write_string(buffer.to_slice)
  end

  def hexstring : String
    @bytes.to_slice.hexstring
  end

  # Returns a `String` that is a valid urn of *self*
  #
  # ```
  # require "uuid"
  #
  # uuid = UUID.empty
  # uuid.urn # => "urn:uuid:00000000-0000-4000-0000-000000000000"
  # uuid2 = UUID.new("c49fc136-9362-4414-81a5-9a7e0fcca0f1")
  # uuid2.urn # => "urn:uuid:c49fc136-9362-4414-81a5-9a7e0fcca0f1"
  # ```
  def urn : String
    String.build(45) do |str|
      str << "urn:uuid:"
      to_s(str)
    end
  end

  def <=>(other : UUID) : Int32
    @bytes <=> other.bytes
  end

  class Error < Exception
  end

  {% for v in %w(1 2 3 4 5 7) %}
    # Returns `true` if UUID is a V{{ v.id }}, `false` otherwise.
    def v{{ v.id }}?
      variant == Variant::RFC4122 && version == Version::V{{ v.id }}
    end

    # Returns `true` if UUID is a V{{ v.id }}, raises `Error` otherwise.
    def v{{ v.id }}!
      unless v{{ v.id }}?
        raise Error.new("Invalid UUID variant #{variant} version #{version}, expected RFC 4122 V{{ v.id }}")
      else
        true
      end
    end
  {% end %}
end
