require "deque"

class IO::Pipe < IO
  getter reader, writer

  def initialize(@read_blocking = false, @write_blocking = false, initial_capacity : Int32 = 8192)
    @buffer = Deque(UInt8).new(initial_capacity: initial_capacity)
    # TODO: Mutex for atomic reads/writes?

    @reader = uninitialized Reader
    @writer = uninitialized Writer

    @reader = Reader.new(self)
    @writer = Writer.new(self)
  end

  def read(slice : Bytes)
    count = 0
    index = 0

    while index < slice.size
      # TODO: Implement read blocking
      if byte = @buffer.shift?
        slice[index] = byte
        count = (index += 1)
      else
        break
      end
    end
    count
  end

  def write(slice : Bytes) : Nil
    # TODO: Implement write blocking
    slice.each do |byte|
      @buffer << byte
    end
  end

  def peek
    # TODO: Figure out what `closed?` even means here
    return if closed?

    bytes = Bytes.new(@buffer.size)
    @buffer.each_with_index do |byte, index|
      bytes[index] = byte
    end

    bytes
  end

  def [](index : Int)
    {@reader, @writer}[index]
  end

  class Reader < IO
    def initialize(@pipe : Pipe)
    end

    def read(slice : Bytes)
      @pipe.read slice
    end

    def write(slice : Bytes) : Nil
      raise Error.new("Can't write to an IO::Pipe::Reader")
    end
  end

  class Writer < IO
    def initialize(@pipe : Pipe)
    end

    def read(slice : Bytes)
      raise Error.new("Can't read from an IO::Pipe::Writer")
    end

    def write(slice : Bytes) : Nil
      @pipe.write slice
    end
  end
end
