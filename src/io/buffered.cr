# The `IO::Buffered` mixin enhances an `IO` with input/output buffering.
#
# The buffering behaviour can be turned on/off with the `#sync=` and
# `#read_buffering=` methods.
#
# Additionally, several methods, like `#gets`, are implemented in a more
# efficient way.
module IO::Buffered
  @in_buffer = Pointer(UInt8).null
  @out_buffer = Pointer(UInt8).null
  @in_buffer_rem = Bytes.empty
  @out_count = 0
  @sync = false
  @read_buffering = true
  @flush_on_newline = false
  @buffer_size = IO::DEFAULT_BUFFER_SIZE

  # Reads at most *slice.size* bytes from the wrapped `IO` into *slice*.
  # Returns the number of bytes read.
  #
  # TODO: Add return type restriction `Int32`
  abstract def unbuffered_read(slice : Bytes)

  # Writes *slice* entirely into the wrapped `IO`.
  #
  # TODO: Add return type restriction `Nil`
  abstract def unbuffered_write(slice : Bytes)

  # Flushes the wrapped `IO`.
  #
  # TODO: Add return type restriction `Nil`
  abstract def unbuffered_flush

  # Closes the wrapped `IO`.
  #
  # TODO: Add return type restriction `Nil`
  abstract def unbuffered_close

  # Rewinds the wrapped `IO`.
  #
  # TODO: Add return type restriction `Nil`
  abstract def unbuffered_rewind

  # Return the buffer size used
  def buffer_size : Int32
    @buffer_size
  end

  # Set the buffer size of both the read and write buffer
  # Cannot be changed after any of the buffers have been allocated
  def buffer_size=(value)
    if (@in_buffer || @out_buffer) && (buffer_size != value)
      raise ArgumentError.new("Cannot change buffer_size after buffers have been allocated")
    end
    @buffer_size = value
  end

  # :nodoc:
  def read_byte : UInt8?
    check_open

    fill_buffer if read_buffering? && @in_buffer_rem.empty?
    if @in_buffer_rem.empty?
      return nil if read_buffering?

      byte = uninitialized UInt8
      if read(Slice.new(pointerof(byte), 1)) == 1
        byte
      else
        nil
      end
    else
      b = @in_buffer_rem[0]
      @in_buffer_rem += 1
      b
    end
  end

  # Buffered implementation of `IO#read(slice)`.
  def read(slice : Bytes) : Int32
    check_open

    count = slice.size
    return 0 if count == 0

    if @in_buffer_rem.empty?
      # If we are asked to read more than half the buffer's size,
      # read directly into the slice, as it's not worth the extra
      # memory copy.
      if !read_buffering? || count >= @buffer_size // 2
        return unbuffered_read(slice[0, count]).to_i
      else
        fill_buffer
        return 0 if @in_buffer_rem.empty?
      end
    end

    to_read = Math.min(count, @in_buffer_rem.size)
    slice.copy_from(@in_buffer_rem.to_unsafe, to_read)
    @in_buffer_rem += to_read
    to_read
  end

  # Returns the bytes hold in the read buffer.
  #
  # This method only performs a read to return
  # peek data if the current buffer is empty:
  # otherwise no read is performed and whatever
  # is in the buffer is returned.
  def peek : Bytes
    check_open

    if @in_buffer_rem.empty?
      fill_buffer
      if @in_buffer_rem.empty?
        return Bytes.empty # EOF
      end
    end

    @in_buffer_rem
  end

  # :nodoc:
  def skip(bytes_count) : Nil
    check_open

    if bytes_count <= @in_buffer_rem.size
      @in_buffer_rem += bytes_count
      return
    end

    bytes_count -= @in_buffer_rem.size
    @in_buffer_rem = Bytes.empty

    super(bytes_count)
  end

  # Buffered implementation of `IO#write(slice)`.
  def write(slice : Bytes) : Nil
    check_open

    return if slice.empty?

    count = slice.size

    if sync?
      return unbuffered_write(slice)
    end

    if flush_on_newline?
      index = slice[0, count.to_i32].rindex('\n'.ord.to_u8)
      if index
        flush
        index += 1
        unbuffered_write slice[0, index]
        slice += index
        count -= index
      end
    end

    if count >= @buffer_size
      flush
      return unbuffered_write slice[0, count]
    end

    if count > @buffer_size - @out_count
      flush
    end

    slice.copy_to(out_buffer + @out_count, count)
    @out_count += count
  end

  # :nodoc:
  def write_byte(byte : UInt8)
    check_open

    if sync?
      return super
    end

    if @out_count >= @buffer_size
      flush
    end
    out_buffer[@out_count] = byte
    @out_count += 1

    if flush_on_newline? && byte === '\n'
      flush
    end
  end

  # Returns the current position (in bytes) in this `IO`.
  #
  # ```
  # File.write("testfile", "hello")
  #
  # file = File.new("testfile")
  # file.pos     # => 0
  # file.gets(2) # => "he"
  # file.pos     # => 2
  # ```
  def pos : Int64
    flush
    in_rem = @in_buffer_rem.size

    # TODO In 2.0 we should make `unbuffered_pos` an abstract method of Buffered
    if self.responds_to?(:unbuffered_pos)
      self.unbuffered_pos - in_rem
    else
      super - in_rem
    end
  end

  # Turns on/off `IO` **write** buffering. When *sync* is set to `true`, no buffering
  # will be done (that is, writing to this `IO` is immediately synced to the
  # underlying `IO`).
  def sync=(sync)
    flush if sync && !@sync
    @sync = !!sync
  end

  # Determines if this `IO` does write buffering. If `true`, no buffering is done.
  def sync? : Bool
    @sync
  end

  # Turns on/off `IO` **read** buffering.
  def read_buffering=(read_buffering)
    @read_buffering = !!read_buffering
  end

  # Determines whether this `IO` buffers reads.
  def read_buffering? : Bool
    @read_buffering
  end

  # Turns on/off flushing the underlying `IO` when a newline is written.
  def flush_on_newline=(flush_on_newline)
    @flush_on_newline = !!flush_on_newline
  end

  # Determines if this `IO` flushes automatically when a newline is written.
  def flush_on_newline? : Bool
    @flush_on_newline
  end

  # Flushes any buffered data and the underlying `IO`. Returns `self`.
  def flush
    unbuffered_write(Slice.new(out_buffer, @out_count)) if @out_count > 0
    unbuffered_flush
    @out_count = 0
    self
  end

  # Flushes and closes the underlying `IO`.
  def close : Nil
    flush if @out_count > 0
  ensure
    unbuffered_close
  end

  # Rewinds the underlying `IO`. Returns `self`.
  def rewind
    unbuffered_rewind
    @in_buffer_rem = Bytes.empty
    self
  end

  # Unsafe, direct access to the underlying read buffer.
  protected def unsafe_read_buffer
    @in_buffer_rem
  end

  private def fill_buffer
    in_buffer = in_buffer()
    size = unbuffered_read(Slice.new(in_buffer, @buffer_size)).to_i
    @in_buffer_rem = Slice.new(in_buffer, size)
  end

  private def in_buffer
    @in_buffer ||= GC.malloc_atomic(@buffer_size.to_u32).as(UInt8*)
  end

  private def out_buffer
    @out_buffer ||= GC.malloc_atomic(@buffer_size.to_u32).as(UInt8*)
  end
end
