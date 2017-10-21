require "random/secure"

# :nodoc:
struct Crystal::Hasher
  # Implementation of a Hasher to compute a fast and safe hash
  # value for primitive and basic Crystal objects. All other
  # hashes are computed based on these.
  #
  # The algorithm bases on https://github.com/funny-falcon/funny_hash
  #
  # It is two multiply-rotate 64bit hash functions, combined
  # within finalizer.
  #
  # Both hash functions combines previous state with a block value
  # before multiplication. One function multiplies new state
  # as is (and then rotates state), other multiplies new state
  # already rotated by 32 bits.
  #
  # This way algorithm ensures that every block bit affects at
  # least 1 bit of every state, and certainly many bits of some
  # state. So effect of this bit could not be easily canceled
  # with following blocks. (Cause next blocks have to cancel
  # bits on non-intersecting positions in both states).
  # Rotation by 32bit with multiplication also provides good
  # inter-block avalanche.
  #
  # Finalizer performs murmur-like finalization on both functions,
  # and then combines them with addition. It greatly reduce
  # possibility of state deduction.
  #
  # Note, it provides good protection from HashDos iif:
  # - seed is securely random and not exposed to attacker,
  # - hash result is also not exposed to attacker in a way other
  #   than effect of using it Hash implementation.
  # Do not output calculated hash value to user's console/form/
  # html/api response, etc. Use some from digest package instead.

  @@seed = uninitialized UInt64[2]
  Random::Secure.random_bytes(Slice.new(pointerof(@@seed).as(UInt8*), sizeof(typeof(@@seed))))

  @a : UInt64 = @@seed[0]
  @b : UInt64 = @@seed[1]

  private C1 = 0xacd5ad43274593b9_u64
  private C2 = 0x6956abd6ed268a3d_u64

  private def rotl32(v : UInt64)
    v.unsafe_shl(32) | v.unsafe_shr(32)
  end

  private def permute(v : UInt64)
    @a = rotl32(@a ^ v) * C1
    @b = (rotl32(@b) ^ v) * C2
    self
  end

  def result
    a, b = @a, @b
    a ^= a >> 33
    b ^= b >> 32
    a *= C1
    b *= C2
    a ^= a >> 32
    b ^= b >> 33
    a + b
  end

  def nil
    self
  end

  def bool(value)
    (value ? 1 : 0).hash(self)
  end

  def int(value)
    permute(value.to_u64)
  end

  def float(value)
    permute(value.to_f64.unsafe_as(UInt64))
  end

  def char(value)
    value.ord.hash(self)
  end

  def enum(value)
    value.value.hash(self)
  end

  def symbol(value)
    value.to_i.hash(self)
  end

  def reference(value)
    permute(value.object_id.to_u64)
  end

  def string(value)
    bytes(value.to_slice)
  end

  def bytes(value)
    bsz = value.size
    v = bsz.to_u64 << 56
    u = value.to_unsafe
    bsz.unsafe_div(8).downto(1) do
      # force correct unaligned read
      t8 = uninitialized UInt64
      pointerof(t8).as(UInt8*).copy_from(u, 8)
      permute(t8)
      u += 8
    end
    if (bsz & 4) != 0
      # force correct unaligned read
      t4 = uninitialized UInt32
      pointerof(t4).as(UInt8*).copy_from(u, 4)
      v |= t4.to_u64 << 24
      u += 4
    end
    if (r = bsz & 3) != 0
      v |= u[0].to_u64 | (u[r/2].to_u64 << 8) | (u[r - 1].to_u64 << 16)
    end
    permute(v)
    self
  end

  def class(value)
    value.crystal_type_id.hash(self)
  end
end
