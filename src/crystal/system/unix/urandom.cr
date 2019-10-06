{% skip_file unless flag?(:unix) && !flag?(:openbsd) && !flag?(:linux) %}

module Crystal::System::Random
  @@initialized = false
  @@urandom : ::File?

  private def self.init
    @@initialized = true

    urandom = ::File.new("/dev/urandom")
    return unless urandom.info.type.character_device?

    urandom.close_on_exec = true
    urandom.read_buffering = false
    @@urandom = urandom
  end

  def self.random_bytes(buf : Bytes) : Nil
    init unless @@initialized

    if urandom = @@urandom
      urandom.read_fully(buf)
    else
      raise "Failed to access secure source to generate random bytes!"
    end
  end

  def self.next_u : UInt8
    init unless @@initialized

    if urandom = @@urandom
      urandom.read_bytes(UInt8)
    else
      raise "Failed to access secure source to generate random bytes!"
    end
  end
end
