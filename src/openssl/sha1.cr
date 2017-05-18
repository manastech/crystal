require "./lib_crypto"

# Binds the OpenSSL SHA1 hash functions.
#
# Warning: SHA1 is no longer a cryptograpically safe hash, and should not be
# used for secure applications.
class OpenSSL::SHA1
  def self.hash(data : String)
    hash(data.to_unsafe, LibC::SizeT.new(data.bytesize))
  end

  def self.hash(data : UInt8*, bytesize : LibC::SizeT)
    buffer = uninitialized UInt8[20]
    LibCrypto.sha1(data, bytesize, buffer)
    buffer
  end
end
