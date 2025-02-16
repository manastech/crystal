require "spec"
require "http/content"

describe HTTP::ChunkedContent do
  it "delays reading the next chunk as soon as one is consumed (#3270)" do
    mem = IO::Memory.new("4\r\n123\n\r\n0\r\n\r\n")
    content = HTTP::ChunkedContent.new(mem)
    bytes = uninitialized UInt8[4]
    bytes_read = content.read(bytes.to_slice)
    bytes_read.should eq(4)
    String.new(bytes.to_slice).should eq("123\n")
    mem.pos.should eq(7) # only this chunk was read
  end

  it "peeks" do
    mem = IO::Memory.new("4\r\n123\n\r\n0\r\n\r\n")
    content = HTTP::ChunkedContent.new(mem)

    content.peek.should eq("123\n".to_slice)
    content.skip(4)
    content.peek.should eq Bytes.empty
  end

  it "peeks into next chunk" do
    mem = IO::Memory.new("4\r\n123\n\r\n3\r\n456\r\n0\r\n\r\n")
    content = HTTP::ChunkedContent.new(mem)

    content.skip(4)
    content.peek.should eq("456".to_slice)
    content.gets_to_end.should eq("456")
  end

  it "skips" do
    mem = IO::Memory.new("4\r\n123\n\r\n0\r\n\r\n")
    content = HTTP::ChunkedContent.new(mem)

    content.skip(2)
    content.read_char.should eq('3')

    expect_raises(IO::EOFError) do
      content.skip(10)
    end
  end

  it "skips (2)" do
    mem = IO::Memory.new("4\r\n123\n\r\n0\r\n\r\n")
    content = HTTP::ChunkedContent.new(mem)

    content.skip(2)
    content.gets_to_end.should eq("3\n")
  end

  it "skips (3)" do
    mem = IO::Memory.new("4\r\n123\n\r\n3\r\n456\r\n0\r\n\r\n")
    content = HTTP::ChunkedContent.new(mem)

    content.skip(4)
    content.gets_to_end.should eq("456")
  end

  it "skips to the end when closed" do
    mem = IO::Memory.new("4\r\n123\n\r\n3\r\n456\r\n0\r\n\r\n")
    content = HTTP::ChunkedContent.new(mem)

    content.close

    mem.pos.should eq mem.bytesize
  end

  it "#gets reads multiple chunks" do
    mem = IO::Memory.new("1\r\nA\r\n1\r\nB\r\n0\r\n\r\n")
    content = HTTP::ChunkedContent.new(mem)

    content.gets.should eq "AB"
    mem.pos.should eq mem.bytesize
  end

  it "#gets reads multiple chunks with \n" do
    # The RFC format requires CRLF, but several standard implementations also
    # accept LF, so we should too.
    mem = IO::Memory.new("1\nA\n1\nB\n0\n\n")
    content = HTTP::ChunkedContent.new(mem)

    content.gets.should eq "AB"
    mem.pos.should eq mem.bytesize
  end

  it "#read reads empty content" do
    mem = IO::Memory.new("0\r\n\r\n")
    content = HTTP::ChunkedContent.new(mem)

    content.read(Bytes.new(5)).should eq 0
    mem.pos.should eq mem.bytesize
  end

  it "#read_byte reads empty content" do
    mem = IO::Memory.new("0\r\n\r\n")
    content = HTTP::ChunkedContent.new(mem)

    content.read_byte.should be_nil
    mem.pos.should eq mem.bytesize
  end

  it "#peek reads empty content" do
    mem = IO::Memory.new("0\r\n\r\n")
    content = HTTP::ChunkedContent.new(mem)

    content.peek.should eq Bytes.empty
    mem.pos.should eq mem.bytesize
  end

  it "#read handles interrupted io" do
    mem = IO::Memory.new("3\r\n123\r\n")
    content = HTTP::ChunkedContent.new(mem)

    content.skip(3)
    expect_raises IO::EOFError do
      content.read Bytes.new(5)
    end
  end

  it "#read_byte handles interrupted io" do
    mem = IO::Memory.new("3\r\n123\r\n")
    content = HTTP::ChunkedContent.new(mem)

    content.skip(3)
    expect_raises IO::EOFError do
      content.read_byte
    end
  end

  it "#peek handles interrupted io" do
    mem = IO::Memory.new("3\r\n123\r\n")
    content = HTTP::ChunkedContent.new(mem)

    content.skip(3)
    expect_raises IO::EOFError do
      content.peek
    end
  end

  it "#read handles empty data" do
    mem = IO::Memory.new("3\r\n")
    content = HTTP::ChunkedContent.new(mem)

    expect_raises IO::EOFError do
      content.read Bytes.new(1)
    end
  end

  it "#read_byte handles empty data" do
    mem = IO::Memory.new("3\r\n")
    content = HTTP::ChunkedContent.new(mem)

    expect_raises IO::Error do
      content.read_byte
    end
  end

  it "#peek handles empty data" do
    mem = IO::Memory.new("3\r\n")
    content = HTTP::ChunkedContent.new(mem)

    expect_raises IO::EOFError do
      content.peek
    end
  end

  it "handles empty io" do
    mem = IO::Memory.new("")
    chunked = HTTP::ChunkedContent.new(mem)
    expect_raises IO::EOFError do
      chunked.gets
    end
  end

  it "reads chunk extensions" do
    mem = IO::Memory.new(%(1;progress=50;foo="bar"\r\nA\r\n1;progress=100\r\nB\r\n0\r\n\r\n"))

    chunked = HTTP::ChunkedContent.new(mem)
    chunked.gets(2).should eq "AB"
  end

  it "reads chunked trailer part" do
    mem = IO::Memory.new("0\r\nAdditional-Header: Foo\r\n\r\n")

    chunked = HTTP::ChunkedContent.new(mem)
    chunked.gets.should be_nil
    mem.gets.should be_nil
    chunked.headers.should eq HTTP::Headers{"Additional-Header" => "Foo"}
  end

  it "fails if unterminated chunked trailer part" do
    mem = IO::Memory.new("0\r\nAdditional-Header: Foo")

    chunked = HTTP::ChunkedContent.new(mem)
    expect_raises IO::EOFError do
      chunked.gets
    end
  end

  describe "long trailer part" do
    it "fails for long single header" do
      mem = IO::Memory.new("0\r\nFoo: Bar Baz Qux\r\n\r\n")

      chunked = HTTP::ChunkedContent.new(mem, max_headers_size: 12)
      expect_raises(IO::Error, "Trailing headers too long") do
        chunked.gets
      end
      chunked.headers.should be_empty
    end

    it "fails for long combined headers" do
      mem = IO::Memory.new("0\r\nFoo: Bar\r\nBaz: Qux\r\n\r\n")

      chunked = HTTP::ChunkedContent.new(mem, max_headers_size: 12)
      expect_raises(IO::Error, "Trailing headers too long") do
        chunked.gets
      end
      chunked.headers.should eq HTTP::Headers{"Foo" => "Bar"}
    end
  end

  it "fails if not properly delimited" do
    mem = IO::Memory.new("0\r\n")

    chunked = HTTP::ChunkedContent.new(mem)
    expect_raises IO::EOFError do
      chunked.gets
    end
  end

  it "fails if not properly delimited" do
    mem = IO::Memory.new("1\r\nA\r\n0\r\n")

    chunked = HTTP::ChunkedContent.new(mem)
    expect_raises IO::EOFError do
      chunked.gets
    end
  end

  it "fails if invalid chunk size" do
    mem = IO::Memory.new("G\r\n")

    chunked = HTTP::ChunkedContent.new(mem)
    expect_raises IO::Error, "Invalid HTTP chunked content: invalid chunk size" do
      chunked.gets
    end
  end

  it "#read stops reading after final chunk" do
    mem = IO::Memory.new("0\r\n\r\n1\r\nA\r\n0\r\n\r\n")

    chunked = HTTP::ChunkedContent.new(mem)
    chunked.read(Bytes.new(8)).should eq 0
    mem.pos.should eq 5
    chunked.read(Bytes.new(8)).should eq 0
    mem.pos.should eq 5
  end

  it "#read_byte stops reading after final chunk" do
    mem = IO::Memory.new("0\r\n\r\n1\r\nA\r\n0\r\n\r\n")

    chunked = HTTP::ChunkedContent.new(mem)
    chunked.read_byte.should be_nil
    mem.pos.should eq 5
    chunked.read_byte.should be_nil
    mem.pos.should eq 5
  end

  it "#peek stops reading after final chunk" do
    mem = IO::Memory.new("0\r\n\r\n1\r\nA\r\n0\r\n\r\n")

    chunked = HTTP::ChunkedContent.new(mem)
    chunked.peek.should eq Bytes.empty
    mem.pos.should eq 5
    chunked.peek.should eq Bytes.empty
    mem.pos.should eq 5
  end
end
