# This file includes an implementation of (U)Int128 modulo/division operations

# :nodoc:
fun __divti3(a : Int128, b : Int128) : Int128
  # Ported from https://github.com/llvm/llvm-project/blob/ce59ccd04023cab3a837da14079ca2dcbfebb70c/compiler-rt/lib/builtins/int_div_impl.inc

  s_a = a >> 127       # s_a = a < 0 ? -1 : 0
  s_b = b >> 127       # s_b = b < 0 ? -1 : 0
  a = (a ^ s_a) &- s_a # negate if s_a == -1
  b = (b ^ s_b) &- s_b # negate if s_b == -1
  s_a ^= s_b           # sign of quotient
  quo, _ = _u128_div_rem(a.to_u128!, b.to_u128!)
  ((quo ^ s_a) &- s_a).to_i128! # negate if s_a == -1
end

# :nodoc:
fun __modti3(a : Int128, b : Int128) : Int128
  # Ported from https://github.com/llvm/llvm-project/blob/ce59ccd04023cab3a837da14079ca2dcbfebb70c/compiler-rt/lib/builtins/int_div_impl.inc

  s = b >> 127     # s = b < 0 ? -1 : 0
  b = (b ^ s) &- s # negate if s == -1
  s = a >> 127     # s = a < 0 ? -1 : 0
  a = (a ^ s) &- s # negate if s == -1
  _, rem = _u128_div_rem(a.to_u128!, b.to_u128!)
  (rem.to_i128! ^ s) &- s # negate if s == -1
end

# :nodoc:
fun __udivti3(a : UInt128, b : UInt128) : UInt128
  # Ported from https://github.com/llvm/llvm-project/blob/ce59ccd04023cab3a837da14079ca2dcbfebb70c/compiler-rt/lib/builtins/int_div_impl.inc

  quo, _ = _u128_div_rem(a, b)
  quo
end

# :nodoc:
fun __umodti3(a : UInt128, b : UInt128) : UInt128
  # Ported from https://github.com/llvm/llvm-project/blob/ce59ccd04023cab3a837da14079ca2dcbfebb70c/compiler-rt/lib/builtins/int_div_impl.inc

  _, rem = _u128_div_rem(a, b)
  rem
end

# :nodoc:
def _carrying_mul(lhs : UInt64, rhs : UInt64) : Tuple(UInt64, UInt64)
  # Ported from https://github.com/rust-lang/compiler-builtins/blob/2be2bc086bd9b3c0fc8eb8d2dc7df025e6ffd318/src/int/specialized_div_rem/trifecta.rs

  tmp = lhs.to_u128! &* rhs.to_u128!
  {tmp.to_u64!, (tmp >> 64).to_u64!}
end

# :nodoc:
def _carrying_mul_add(lhs : UInt64, mul : UInt64, add : UInt64) : Tuple(UInt64, UInt64)
  # Ported from https://github.com/rust-lang/compiler-builtins/blob/2be2bc086bd9b3c0fc8eb8d2dc7df025e6ffd318/src/int/specialized_div_rem/trifecta.rs

  tmp = lhs.to_u128!
  tmp &*= mul.to_u128!
  tmp &+= add.to_u128!
  {tmp.to_u64!, (tmp >> 64).to_u64!}
end

# :nodoc:
def _u128_div_rem(duo : UInt128, div : UInt128) : Tuple(UInt128, UInt128)
  # Ported from https://github.com/rust-lang/compiler-builtins/blob/2be2bc086bd9b3c0fc8eb8d2dc7df025e6ffd318/src/int/specialized_div_rem/trifecta.rs

  # Rust also has another algorithm for 128-bit integer division
  # for microarchitectures that have slow hardware integer division.

  # This algorithm is called the trifecta algorithm because it uses three main algorithms:
  # - short division for small divisors
  # - the two possibility algorithm for large divisors
  # - an undersubtracting long division algorithm for intermediate cases

  div_lz = div.leading_zeros_count
  duo_lz = duo.leading_zeros_count

  if div_lz <= duo_lz
    # Resulting quotient is 0 or 1 at this point
    # The highest set bit of `duo` needs to be at least one place higher than `div` for the quotient to be more than one.
    if duo >= div
      return {1_u128, duo - div}
    else
      return {0_u128, duo}
    end
  end

  # Use 64-bit integer division if possible
  if duo_lz >= 64
    # duo fits in a 64-bit integer
    # Because of the previous branch (div_lz <= duo_lz), div will also fit in an 64-bit integer
    quo_local1 = duo.to_u64! // div.to_u64!
    rem_local1 = duo.to_u64! % div.to_u64!
    return {quo_local1.to_u128!, rem_local1.to_u128!}
  end

  # Short division branch
  if div_lz >= 96
    duo_hi = (duo >> 64).to_u64!
    div_0 = div.to_u32!.to_u64!
    quo_hi = duo_hi // div_0
    rem_3 = duo_hi % div_0

    duo_mid = (duo >> 32).to_u32!.to_u64! | (rem_3 << 32)
    quo_1 = duo_mid // div_0
    rem_2 = duo_mid % div_0

    duo_lo = duo.to_u32!.to_u64! | (rem_2 << 32)
    quo_0 = duo_lo // div_0
    rem_1 = duo_lo % div_0

    return {quo_0.to_u128! | (quo_1.to_u128! << 32) | (quo_hi.to_u128! << 64), rem_1.to_u128!}
  end

  # Relative leading significant bits (cannot overflow because of above branches)
  lz_diff = div_lz - duo_lz

  if lz_diff < 32
    # Two possibility division algorithm

    # The most significant bits of duo and div are within 32 bits of each other.
    # If we take the n most significant bits of duo and divide them by the corresponding bits in div, it produces the quotient value quo.
    # It happens that quo or quo - 1 will always be the correct quotient for the whole number.

    shift = 64 - duo_lz
    duo_sig_n = (duo >> shift).to_u64!
    div_sig_n = (div >> shift).to_u64!
    quo_local2 = duo_sig_n // div_sig_n

    # The larger quo can overflow, so a manual carrying mul is used with manual overflow checking.
    div_lo = div.to_u64!
    div_hi = (div >> 64).to_u64!
    tmp_lo, carry = _carrying_mul(quo_local2, div_lo)
    tmp_hi, overflow = _carrying_mul_add(quo_local2, div_hi, carry)
    tmp = tmp_lo.to_u128! | (tmp_hi.to_u128! << 64)
    if (overflow != 0) || (duo < tmp)
      # In `duo &+ div &- tmp`, both the subtraction and addition can overflow, but the result is always a correct positive number.
      return {(quo_local2 - 1).to_u128!, duo &+ div &- tmp}
    else
      return {quo_local2.to_u128!, duo - tmp}
    end
  end

  # Undersubtracting long division algorithm.

  quo = UInt128.zero
  div_extra = 96 - div_lz                  # Number of lesser significant bits that aren't part of div_sig_32
  div_sig_32 = (div >> div_extra).to_u32!  # Most significant 32 bits of div
  div_sig_32_add1 = div_sig_32.to_u64! + 1 # This must be a UInt64 because this can overflow

  loop do
    duo_extra = 64 - duo_lz                # Number of lesser significant bits that aren't part of duo_sig_n
    duo_sig_n = (duo >> duo_extra).to_u64! # Most significant 64 bits of duo

    # The two possibility algorithm requires that the difference between most significant bits is less than 32
    if div_extra <= duo_extra
      # Undersubtracting long division step
      quo_part = (duo_sig_n // div_sig_32_add1).to_u128!
      extra_shl = duo_extra - div_extra

      # Addition to the quotient
      quo += (quo_part << extra_shl)

      # Subtraction from duo. At least 31 bits are cleared from duo here
      duo -= ((div &* quo_part) << extra_shl)
    else
      # Two possibility algorithm

      shift = 64 - duo_lz
      duo_sig_n = (duo >> shift).to_u64!
      div_sig_n = (div >> shift).to_u64!
      quo_part = duo_sig_n // div_sig_n
      div_lo = div.to_u64!
      div_hi = (div >> 64).to_u64!

      tmp_lo, carry = _carrying_mul(quo_part, div_lo)
      # The undersubtracting long division algorithm has already run once, so overflow beyond 128 bits is impossible
      tmp_hi, _ = _carrying_mul_add(quo_part, div_hi, carry)
      tmp = tmp_lo.to_u128! | (tmp_hi.to_u128! << 64)

      if duo < tmp
        return {quo + (quo_part - 1), duo &+ div &- tmp}
      else
        return {quo + quo_part, duo - tmp}
      end
    end

    duo_lz = duo.leading_zeros_count

    if div_lz <= duo_lz
      # Quotient can have 0 or 1 added to it
      if div <= duo
        return {quo + 1, duo - div}
      else
        return {quo, duo}
      end
    end

    # This can only happen if div_sd < 64
    if 64 <= duo_lz
      quo_local3 = duo.to_u64! // div.to_u64!
      rem_local2 = duo.to_u64! % div.to_u64!
      return {quo + quo_local3, rem_local2.to_u128!}
    end
  end
end
