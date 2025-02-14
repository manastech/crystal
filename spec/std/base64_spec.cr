require "spec"
require "base64"
require "crystal/digest/md5"
require "spec/helpers/string"

# rearrange parameters for `assert_prints`
{% for method in %w(encode strict_encode urlsafe_encode) %}
  private def base64_{{ method.id }}(io : IO, data, *args)
    Base64.{{ method.id }}(data, io, *args)
  end

  private def base64_{{ method.id }}(data, *args)
    Base64.{{ method.id }}(data, *args)
  end
{% end %}

describe "Base64" do
  context "simple test" do
    eqs = {"" => "", "a" => "YQ==\n", "ab" => "YWI=\n", "abc" => "YWJj\n",
           "abcd" => "YWJjZA==\n", "abcde" => "YWJjZGU=\n", "abcdef" => "YWJjZGVm\n",
           "abcdefg" => "YWJjZGVmZw==\n"}
    eqs.each do |a, b|
      it "encode #{a.inspect} to #{b.inspect}" do
        assert_prints base64_encode(a), b
      end
      it "decode from #{b.inspect} to #{a.inspect}" do
        Base64.decode(b).should eq(a.to_slice)
        Base64.decode_string(b).should eq(a)
      end
    end
  end

  context "\n in multiple places" do
    eqs = {"abcd" => "YWJj\nZA==\n", "abcde" => "YWJj\nZGU=\n", "abcdef" => "YWJj\nZGVm\n",
           "abcdefg" => "YWJj\nZGVmZw==\n", "abcdefg" => "YWJj\nZGVm\nZw==\n",
    }
    eqs.each do |a, b|
      it "decode from #{b.inspect} to #{a.inspect}" do
        Base64.decode(b).should eq(a.to_slice)
        Base64.decode_string(b).should eq(a)
      end
    end
  end

  it "encodes byte slice" do
    slice = Bytes.new(5) { 1_u8 }
    assert_prints base64_encode(slice), "AQEBAQE=\n"
    assert_prints base64_strict_encode(slice), "AQEBAQE="
  end

  it "encodes empty slice" do
    slice = Bytes.empty
    assert_prints base64_encode(slice), ""
    assert_prints base64_strict_encode(slice), ""
  end

  it "encodes static array" do
    array = uninitialized StaticArray(UInt8, 5)
    (0...5).each { |i| array[i] = 1_u8 }
    assert_prints base64_encode(array), "AQEBAQE=\n"
    assert_prints base64_strict_encode(array), "AQEBAQE="
  end

  context "encoding an IO" do
    encode_buffer = IO::Memory.new
    decode_buffer = IO::Memory.new

    before_each do
      # Clear out each buffer before each spec
      encode_buffer = IO::Memory.new
      decode_buffer = IO::Memory.new
    end

    # Base64 operates on 3-byte segments at a time.
    {
      0, # Testing an empty buffer
      1, # incomplete segment
      2, # still an incomplete segment
      3, # 1 complete segment
      4, # 1 byte over the segment size
      5, # 2 bytes over the segment size
      6, # 2 segments
      7,
      8190,          # 1 segment below the buffer size
      8191,          # 2 bytes below the buffer size
      8192,          # 1 byte belowbuffer size
      8193,          # encoding buffer size
      8194,          # 1 byte over the buffer size
      8195,          # 2 bytes over the buffer size
      8196,          # 1 segment over the buffer size
      (1 << 20) - 1, # Just under 1MB
      (1 << 20),     # 1MB
      (1 << 20) + 1, # just over 1MB
      2 << 20,       # 2MB
    }.each do |bytesize|
      it "encodes #{bytesize.format} bytes from an IO to another IO" do
        string = " " * bytesize
        decode_buffer << string

        Base64.encode decode_buffer.rewind, encode_buffer.rewind

        encode_buffer.to_s.should eq Base64.encode(string)
      end
    end
  end

  describe "base" do
    eqs = {"Send reinforcements"                                                    => "U2VuZCByZWluZm9yY2VtZW50cw==\n",
           "Now is the time for all good coders\nto learn Crystal"                  => "Tm93IGlzIHRoZSB0aW1lIGZvciBhbGwgZ29vZCBjb2RlcnMKdG8gbGVhcm4g\nQ3J5c3RhbA==\n",
           "This is line one\nThis is line two\nThis is line three\nAnd so on...\n" => "VGhpcyBpcyBsaW5lIG9uZQpUaGlzIGlzIGxpbmUgdHdvClRoaXMgaXMgbGlu\nZSB0aHJlZQpBbmQgc28gb24uLi4K\n",
           "hahah⊙ⓧ⊙"                                                               => "aGFoYWjiipnik6fiipk=\n"}
    eqs.each do |a, b|
      it "encode #{a.inspect} to #{b.inspect}" do
        assert_prints base64_encode(a), b
      end
      it "decode from #{b.inspect} to #{a.inspect}" do
        Base64.decode(b).should eq(a.to_slice)
        Base64.decode_string(b).should eq(a)
      end
    end

    it "decode from strict form" do
      Base64.decode_string("Tm93IGlzIHRoZSB0aW1lIGZvciBhbGwgZ29vZCBjb2RlcnMKdG8gbGVhcm4gQ3J5c3RhbA==").should eq(
        "Now is the time for all good coders\nto learn Crystal")
    end

    it "encode to stream returns number of written characters" do
      io = IO::Memory.new
      count = Base64.encode("Now is the time for all good coders\nto learn Crystal", io)
      count.should eq 74
    end

    it "decode from stream returns number of written bytes" do
      io = IO::Memory.new
      count = Base64.decode("Tm93IGlzIHRoZSB0aW1lIGZvciBhbGwgZ29vZCBjb2RlcnMKdG8gbGVhcm4gQ3J5c3RhbA==", io)
      count.should eq 52
    end

    it "big message" do
      a = "a" * 100000
      b = Base64.encode(a)
      Crystal::Digest::MD5.hexdigest(Base64.decode_string(b)).should eq(Crystal::Digest::MD5.hexdigest(a))
    end

    it "works for most characters" do
      a = String.build(65536 * 4) do |buf|
        65536.times { |i| buf << (i + 1).unsafe_chr }
      end
      b = Base64.encode(a)
      Crystal::Digest::MD5.hexdigest(Base64.decode_string(b)).should eq(Crystal::Digest::MD5.hexdigest(a))
    end
  end

  describe "decode cases" do
    it "decode \r\n" do
      decoded = "hahah⊙ⓧ⊙"
      {"aGFo\r\nYWjiipnik6fiipk=\r\n", "aGFo\r\nYWjiipnik6fiipk=\r\n\r\n"}.each do |encoded|
        Base64.decode(encoded).should eq(decoded.to_slice)
        Base64.decode_string(encoded).should eq(decoded)
      end
    end

    it "decode \n in multiple places" do
      decoded = "hahah⊙ⓧ⊙"
      {"aGFoYWjiipnik6fiipk=", "aGFo\nYWjiipnik6fiipk=", "aGFo\nYWji\nipnik6fiipk=",
       "aGFo\nYWji\nipni\nk6fiipk=", "aGFo\nYWji\nipni\nk6fi\nipk=",
       "aGFo\nYWji\nipni\nk6fi\nipk=\n"}.each do |encoded|
        Base64.decode(encoded).should eq(decoded.to_slice)
        Base64.decode_string(encoded).should eq(decoded)
      end
    end

    it "raise error when \n in incorrect place" do
      expect_raises Base64::Error do
        Base64.decode("aG\nFoYWjiipnik6fiipk=")
      end

      expect_raises Base64::Error do
        Base64.decode_string("aG\nFoYWjiipnik6fiipk=")
      end
    end

    it "raise error when incorrect symbol" do
      expect_raises Base64::Error do
        Base64.decode("()")
      end

      expect_raises Base64::Error do
        Base64.decode_string("()")
      end
    end

    it "raise error when incorrect size" do
      expect_raises Base64::Error do
        Base64.decode("a")
      end

      expect_raises Base64::Error do
        Base64.decode_string("a")
      end
    end

    it "decode small tail after last \n, was a bug" do
      s = "Tm93IGlzIHRoZSB0aW1lIGZvciBhbGwgZ29vZCBjb2RlcnMKdG8gbGVhcm4g\nnA==\n"
      Base64.decode(s).should eq Bytes[78, 111, 119, 32, 105, 115, 32, 116, 104, 101, 32, 116, 105, 109, 101, 32, 102, 111, 114, 32, 97, 108, 108, 32, 103, 111, 111, 100, 32, 99, 111, 100, 101, 114, 115, 10, 116, 111, 32, 108, 101, 97, 114, 110, 32, 156]
    end
  end

  describe "strict" do
    it "encode" do
      assert_prints base64_strict_encode("Now is the time for all good coders\nto learn Crystal"),
        "Tm93IGlzIHRoZSB0aW1lIGZvciBhbGwgZ29vZCBjb2RlcnMKdG8gbGVhcm4gQ3J5c3RhbA=="
    end
    it "with spec symbols" do
      s = String.build { |b| (160..179).each { |i| b << i.chr } }
      se = "wqDCocKiwqPCpMKlwqbCp8KowqnCqsKrwqzCrcKuwq/CsMKxwrLCsw=="
      assert_prints base64_strict_encode(s), se
    end

    it "encode to stream returns number of written characters" do
      s = String.build { |b| (160..179).each { |i| b << i.chr } }
      io = IO::Memory.new
      Base64.strict_encode(s, io).should eq(56)
    end
  end

  describe "urlsafe" do
    it "work" do
      s = String.build { |b| (160..179).each { |i| b << i.chr } }
      se = "wqDCocKiwqPCpMKlwqbCp8KowqnCqsKrwqzCrcKuwq_CsMKxwrLCsw=="
      assert_prints base64_urlsafe_encode(s), se
    end

    it "encode to stream returns number of written characters" do
      s = String.build { |b| (160..179).each { |i| b << i.chr } }
      io = IO::Memory.new
      Base64.urlsafe_encode(s, io).should eq(56)
    end
  end
end
