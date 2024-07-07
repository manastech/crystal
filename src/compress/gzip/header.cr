# A header in a gzip stream.
class Compress::Gzip::Header
  property modification_time : Time
  property os : UInt8
  property extra = Bytes.empty
  property name : String?
  property comment : String?

  # :nodoc:
  @[Flags]
  enum Flg : UInt8
    TEXT
    HCRC
    EXTRA
    NAME
    COMMENT
  end

  # :nodoc:
  def initialize
    @modification_time = Time.utc
    @os = 255_u8 # Unknown
  end

  # :nodoc:
  def initialize(first_byte : UInt8, io : IO)
    header = [first_byte]
    h = Bytes.new(9)
    io.read_fully(h)
    header.concat(h)

    if header[0] != ID1 || header[1] != ID2 || header[2] != DEFLATE
      raise Error.new("Invalid gzip header")
    end

    flg = Flg.new(header[3])

    seconds = IO::ByteFormat::LittleEndian.decode(Int32, header[4, 4].to_unsafe.to_slice(4))
    @modification_time = Time.unix(seconds).to_local

    xfl = header[8]
    @os = header[9]

    if flg.extra?
      xlen = io.read_bytes(UInt16, IO::ByteFormat::LittleEndian)
      header.concat(xlen.unsafe_as(StaticArray(UInt8, 2)))
      @extra = Bytes.new(xlen)
      io.read_fully(@extra)
      header.concat(@extra)
    end

    if flg.name?
      name = io.gets('\0').not_nil!
      header.concat(name.bytes)
      @name = name.chomp('\0')
    end

    if flg.comment?
      comment = io.gets('\0').not_nil!
      header.concat(comment.bytes)
      @comment = comment.chomp('\0')
    end

    if flg.hcrc?
      crc16 = io.read_bytes(UInt16, IO::ByteFormat::LittleEndian)

      crc32 = ::Digest::CRC32.checksum(header.to_unsafe.to_slice(header.size))
      if crc32.unsafe_as(StaticArray(UInt16, 2))[0] != crc16
        raise Error.new("Header CRC16 checksum mismatch")
      end
    end
  end

  # :nodoc:
  def to_io(io)
    # header
    io.write_byte ID1
    io.write_byte ID2

    # compression method
    io.write_byte DEFLATE

    # flg
    flg = Flg::None
    flg |= Flg::EXTRA unless @extra.empty?
    flg |= Flg::NAME if @name
    flg |= Flg::COMMENT if @comment
    io.write_byte flg.value

    # time
    io.write_bytes(modification_time.to_unix.to_u32, IO::ByteFormat::LittleEndian)

    # xfl
    io.write_byte 0_u8

    # os
    io.write_byte os

    unless @extra.empty?
      io.write_bytes(@extra.size.to_u16, IO::ByteFormat::LittleEndian)
      io.write(@extra)
    end

    if name = @name
      io << name
      io.write_byte 0_u8
    end

    if comment = @comment
      io << comment
      io.write_byte 0_u8
    end
  end
end
