require "spec"
require "adler32"

describe Adler32 do
  it "should be able to calculate adler32" do
    adler = Adler32.checksum("foo").to_s(16)
    adler.should eq("2820145")
  end

  it "should be able to calculate adler32 combined" do
    adler1 = Adler32.checksum("hello")
    adler2 = Adler32.checksum(" world!")
    combined = Adler32.combine(adler1, adler2, " world!".size)
    Adler32.checksum("hello world!").should eq(combined)
  end
end
