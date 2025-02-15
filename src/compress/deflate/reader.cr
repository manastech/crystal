# A read-only `IO` object to decompress data in the DEFLATE format.
#
# Instances of this class wrap another IO object. When you read from this instance
# instance, it reads data from the underlying IO, decompresses it, and returns
# it to the caller.
class Compress::Deflate::Reader < IO
  include IO::Buffered

  # If `#sync_close?` is `true`, closing this IO will close the underlying IO.
  property? sync_close : Bool

  # Returns `true` if this reader is closed.
  getter? closed = false

  # Dictionary passed in the constructor
  getter dict : Bytes?

  # Peeked bytes from the underlying IO
  @peek : Bytes?

  # Creates an instance of Flate::Reader.
  def initialize(@io : IO, @sync_close : Bool = false, @dict : Bytes? = nil)
    @buf = uninitialized UInt8[1] # input buffer used by zlib
    @stream = LibZ::ZStream.new
    ret = LibZ.inflateInit2(pointerof(@stream), -LibZ::MAX_BITS, LibZ.zlibVersion, sizeof(LibZ::ZStream))
    raise Compress::Deflate::Error.new(ret, @stream) unless ret.ok?

    @peek = nil
    @end = false
  end

  def finalize
    return if closed?

    LibZ.inflateEnd(pointerof(@stream))
  end

  # Creates a new reader from the given *io*, yields it to the given block,
  # and closes it at its end.
  def self.open(io : IO, sync_close : Bool = false, dict : Bytes? = nil, &)
    reader = new(io, sync_close: sync_close, dict: dict)
    yield reader ensure reader.close
  end

  # Creates an instance of Flate::Reader for the gzip format.
  # has written.
  def self.gzip(input, sync_close : Bool = false) : self
    new input, wbits: GZIP, sync_close: sync_close
  end

  # Creates an instance of Flate::Reader for the gzip format, yields it to the given block, and closes
  # it at its end.
  def self.gzip(input, sync_close : Bool = false, &)
    reader = gzip input, sync_close: sync_close
    yield reader ensure reader.close
  end

  # Always raises `IO::Error` because this is a read-only `IO`.
  def unbuffered_write(slice : Bytes) : NoReturn
    raise IO::Error.new "Can't write to Compress::Deflate::Reader"
  end

  # See `IO#read`.
  def unbuffered_read(slice : Bytes) : Int32
    check_open

    return 0 if slice.empty?
    return 0 if @end

    while true
      if @stream.avail_in == 0
        # Try to peek into the underlying IO, so we can feed more
        # data into zlib
        @peek = @io.peek
        if peek = @peek
          @stream.next_in = peek
          @stream.avail_in = peek.size
        else
          # If peeking is not possible, we are cautious and
          # read byte per byte to avoid reading more data beyond
          # the compressed data (for example, if the compressed stream
          # is part of a zip/gzip file).
          @stream.next_in = @buf.to_unsafe
          @stream.avail_in = @io.read(@buf.to_slice).to_u32
        end
      end

      old_avail_in = @stream.avail_in

      @stream.avail_out = slice.size.to_u32
      @stream.next_out = slice.to_unsafe

      ret = LibZ.inflate(pointerof(@stream), LibZ::Flush::NO_FLUSH)
      read_bytes = slice.size - @stream.avail_out

      # If we were able to peek, skip the used bytes in the underlying IO
      avail_in_diff = old_avail_in - @stream.avail_in
      if @peek && avail_in_diff > 0
        @io.skip(avail_in_diff)
      end

      case ret
      when .need_dict?
        if dict = @dict
          ret = LibZ.inflateSetDictionary(pointerof(@stream), dict, dict.size)
          next if ret.ok?
        end

        raise Compress::Deflate::Error.new(ret, @stream)
      when .errno?,
           .data_error?,
           .mem_error?,
           .buf_error?,
           .version_error?
        raise Compress::Deflate::Error.new(ret, @stream)
      when .stream_end?
        @end = true
        return read_bytes
      else
        # LibZ.inflate might not write any data to the output slice because
        # it might need more input. We can know this happened because *ret*
        # is not STREAM_END.
        if read_bytes == 0
          next
        else
          return read_bytes
        end
      end
    end
  end

  def unbuffered_flush : NoReturn
    raise IO::Error.new "Can't flush Compress::Deflate::Reader"
  end

  # Closes this reader.
  def unbuffered_close : Nil
    return if @closed
    @closed = true

    ret = LibZ.inflateEnd(pointerof(@stream))
    raise Compress::Deflate::Error.new(ret, @stream) unless ret.ok?

    @io.close if @sync_close
  end

  def unbuffered_rewind : Nil
    check_open

    @io.rewind

    initialize(@io, @sync_close, @dict)
  end

  def inspect(io : IO) : Nil
    to_s(io)
  end
end
