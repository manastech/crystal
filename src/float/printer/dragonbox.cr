# Source port of Dragonbox's reference implementation in C++.
#
# The following is their license:
#
#   Copyright 2020-2021 Junekey Jeon
#
#   The contents of this file may be used under the terms of
#   the Apache License v2.0 with LLVM Exceptions.
#
#      (See accompanying file LICENSE-Apache or copy at
#       https://llvm.org/foundation/relicensing/LICENSE.txt)
#
#   Alternatively, the contents of this file may be used under the terms of
#   the Boost Software License, Version 1.0.
#      (See accompanying file LICENSE-Boost or copy at
#       https://www.boost.org/LICENSE_1_0.txt)
#
#   Unless required by applicable law or agreed to in writing, this software
#   is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
#   KIND, either express or implied.
module Float::Printer::Dragonbox
  # Current revision: https://github.com/jk-jeon/dragonbox/tree/b5b4f65a83da14019bcec7ae31965216215a3e10
  #
  # Assumes the following policies:
  #
  # * `jkj::dragonbox::policy::sign::ignore`
  # * `jkj::dragonbox::policy::trailing_zero::ignore`
  # * `jkj::dragonbox::policy::decimal_to_binary_rounding::nearest_to_even` (default)
  # * `jkj::dragonbox::policy::binary_to_decimal_rounding::to_even` (default)
  # * `jkj::dragonbox::policy::cache::full` (default)

  # :nodoc:
  # Utilities for wide unsigned integer arithmetic.
  module WUInt
    # TODO: use built-in integer type
    record UInt128, high : UInt64, low : UInt64 do
      def unsafe_add!(n : UInt64) : self
        sum = @low &+ n
        @high &+= (sum < @low ? 1 : 0)
        @low = sum
        self
      end
    end

    def self.umul64(x : UInt32, y : UInt32) : UInt64
      x.to_u64 &* y
    end

    # Get 128-bit result of multiplication of two 64-bit unsigned integers.
    def self.umul128(x : UInt64, y : UInt64) : UInt128
      a = (x >> 32).to_u32!
      b = x.to_u32!
      c = (y >> 32).to_u32!
      d = y.to_u32!

      ac = umul64(a, c)
      bc = umul64(b, c)
      ad = umul64(a, d)
      bd = umul64(b, d)

      intermediate = (bd >> 32) &+ ad.to_u32! &+ bc.to_u32!

      UInt128.new(
        high: ac &+ (intermediate >> 32) &+ (ad >> 32) &+ (bc >> 32),
        low: (intermediate << 32) &+ bd.to_u32!,
      )
    end

    def self.umul128_upper64(x : UInt64, y : UInt64) : UInt64
      a = (x >> 32).to_u32!
      b = x.to_u32!
      c = (y >> 32).to_u32!
      d = y.to_u32!

      ac = umul64(a, c)
      bc = umul64(b, c)
      ad = umul64(a, d)
      bd = umul64(b, d)

      intermediate = (bd >> 32) &+ ad.to_u32! &+ bc.to_u32!
      ac &+ (intermediate >> 32) &+ (ad >> 32) &+ (bc >> 32)
    end

    # Get upper 64-bits of multiplication of a 64-bit unsigned integer and a 128-bit unsigned integer.
    def self.umul192_upper64(x : UInt64, y : UInt128) : UInt64
      g0 = umul128(x, y.high)
      g0.unsafe_add! umul128_upper64(x, y.low)
      g0.high
    end

    # Get upper 32-bits of multiplication of a 32-bit unsigned integer and a 64-bit unsigned integer.
    def self.umul96_upper32(x : UInt32, y : UInt64) : UInt32
      # a = 0_u32
      b = x
      c = (y >> 32).to_u32!
      d = y.to_u32!

      # ac = 0_u64
      bc = umul64(b, c)
      # ad = 0_u64
      bd = umul64(b, d)

      intermediate = (bd >> 32) &+ bc
      (intermediate >> 32).to_u32!
    end

    # Get middle 64-bits of multiplication of a 64-bit unsigned integer and a 128-bit unsigned integer.
    def self.umul192_middle64(x : UInt64, y : UInt128) : UInt64
      g01 = x &* y.high
      g10 = umul128_upper64(x, y.low)
      g01 &+ g10
    end

    # Get lower 64-bits of multiplication of a 32-bit unsigned integer and a 64-bit unsigned integer.
    def self.umul96_lower64(x : UInt32, y : UInt64) : UInt64
      y &* x
    end
  end

  # :nodoc:
  # Utilities for fast log computation.
  module Log
    def self.floor_log10_pow2(e : Int)
      # Precondition: `-1700 <= e <= 1700`
      (e &* 1262611) >> 22
    end

    def self.floor_log2_pow10(e : Int)
      # Precondition: `-1233 <= e <= 1233`
      (e &* 1741647) >> 19
    end

    def self.floor_log10_pow2_minus_log10_4_over_3(e : Int)
      # Precondition: `-1700 <= e <= 1700`
      (e &* 1262611 &- 524031) >> 22
    end
  end

  # :nodoc:
  # Utilities for fast divisibility tests.
  module Div
    CACHED_POWERS_OF_5_TABLE_U32 = [
      {0x00000001_u32, 0xffffffff_u32},
      {0xcccccccd_u32, 0x33333333_u32},
      {0xc28f5c29_u32, 0x0a3d70a3_u32},
      {0x26e978d5_u32, 0x020c49ba_u32},
      {0x3afb7e91_u32, 0x0068db8b_u32},
      {0x0bcbe61d_u32, 0x0014f8b5_u32},
      {0x68c26139_u32, 0x000431bd_u32},
      {0xae8d46a5_u32, 0x0000d6bf_u32},
      {0x22e90e21_u32, 0x00002af3_u32},
      {0x3a2e9c6d_u32, 0x00000897_u32},
      {0x3ed61f49_u32, 0x000001b7_u32},
      {0x0c913975_u32, 0x00000057_u32},
      {0xcf503eb1_u32, 0x00000011_u32},
      {0xf6433fbd_u32, 0x00000003_u32},
      {0x3140a659_u32, 0x00000002_u32},
      {0x70402145_u32, 0x00000009_u32},
      {0x7cd9a041_u32, 0x00000001_u32},
      {0xe5c5200d_u32, 0x00000001_u32},
      {0xfac10669_u32, 0x00000005_u32},
      {0x6559ce15_u32, 0x00000001_u32},
      {0xaddec2d1_u32, 0x00000002_u32},
      {0x892c8d5d_u32, 0x00000003_u32},
      {0x1b6f4f79_u32, 0x00000001_u32},
      {0x6be30fe5_u32, 0x00000001_u32},
    ]

    CACHED_POWERS_OF_5_TABLE_U64 = [
      {0x0000000000000001_u64, 0xffffffffffffffff_u64},
      {0xcccccccccccccccd_u64, 0x3333333333333333_u64},
      {0x8f5c28f5c28f5c29_u64, 0x0a3d70a3d70a3d70_u64},
      {0x1cac083126e978d5_u64, 0x020c49ba5e353f7c_u64},
      {0xd288ce703afb7e91_u64, 0x0068db8bac710cb2_u64},
      {0x5d4e8fb00bcbe61d_u64, 0x0014f8b588e368f0_u64},
      {0x790fb65668c26139_u64, 0x000431bde82d7b63_u64},
      {0xe5032477ae8d46a5_u64, 0x0000d6bf94d5e57a_u64},
      {0xc767074b22e90e21_u64, 0x00002af31dc46118_u64},
      {0x8e47ce423a2e9c6d_u64, 0x0000089705f4136b_u64},
      {0x4fa7f60d3ed61f49_u64, 0x000001b7cdfd9d7b_u64},
      {0x0fee64690c913975_u64, 0x00000057f5ff85e5_u64},
      {0x3662e0e1cf503eb1_u64, 0x000000119799812d_u64},
      {0xa47a2cf9f6433fbd_u64, 0x0000000384b84d09_u64},
      {0x54186f653140a659_u64, 0x00000000b424dc35_u64},
      {0x7738164770402145_u64, 0x0000000024075f3d_u64},
      {0xe4a4d1417cd9a041_u64, 0x000000000734aca5_u64},
      {0xc75429d9e5c5200d_u64, 0x000000000170ef54_u64},
      {0xc1773b91fac10669_u64, 0x000000000049c977_u64},
      {0x26b172506559ce15_u64, 0x00000000000ec1e4_u64},
      {0xd489e3a9addec2d1_u64, 0x000000000002f394_u64},
      {0x90e860bb892c8d5d_u64, 0x000000000000971d_u64},
      {0x502e79bf1b6f4f79_u64, 0x0000000000001e39_u64},
      {0xdcd618596be30fe5_u64, 0x000000000000060b_u64},
    ]

    module CHECK_DIVISIBILITY_AND_DIVIDE_BY_POW10_INFO_F32
      MAGIC_NUMBER        = 0xcccd_u32
      BITS_FOR_COMPARISON =         16
      THRESHOLD           = 0x3333_u32
      SHIFT_AMOUNT        =         19
    end

    module CHECK_DIVISIBILITY_AND_DIVIDE_BY_POW10_INFO_F64
      MAGIC_NUMBER        = 0x147c29_u32
      BITS_FOR_COMPARISON =           12
      THRESHOLD           =     0xa3_u32
      SHIFT_AMOUNT        =           27
    end

    def self.divisible_by_power_of_5?(x : UInt32, exp : Int)
      mod_inv, max_quotients = CACHED_POWERS_OF_5_TABLE_U32[exp]
      x &* mod_inv <= max_quotients
    end

    def self.divisible_by_power_of_5?(x : UInt64, exp : Int)
      mod_inv, max_quotients = CACHED_POWERS_OF_5_TABLE_U64[exp]
      x &* mod_inv <= max_quotients
    end

    def self.divisible_by_power_of_2?(x : Int::Unsigned, exp : Int)
      x.trailing_zeros_count >= exp
    end

    def self.check_divisibility_and_divide_by_pow10_k1(n : UInt32)
      bits_for_comparison = CHECK_DIVISIBILITY_AND_DIVIDE_BY_POW10_INFO_F32::BITS_FOR_COMPARISON
      comparison_mask = ~(UInt32::MAX << bits_for_comparison)

      n &*= CHECK_DIVISIBILITY_AND_DIVIDE_BY_POW10_INFO_F32::MAGIC_NUMBER
      c = ((n >> 1) | (n << (bits_for_comparison - 1))) & comparison_mask
      n >>= CHECK_DIVISIBILITY_AND_DIVIDE_BY_POW10_INFO_F32::SHIFT_AMOUNT
      {n, c <= CHECK_DIVISIBILITY_AND_DIVIDE_BY_POW10_INFO_F32::THRESHOLD}
    end

    def self.check_divisibility_and_divide_by_pow10_k2(n : UInt32)
      bits_for_comparison = CHECK_DIVISIBILITY_AND_DIVIDE_BY_POW10_INFO_F64::BITS_FOR_COMPARISON
      comparison_mask = ~(UInt32::MAX << bits_for_comparison)

      n &*= CHECK_DIVISIBILITY_AND_DIVIDE_BY_POW10_INFO_F64::MAGIC_NUMBER
      c = ((n >> 2) | (n << (bits_for_comparison - 2))) & comparison_mask
      n >>= CHECK_DIVISIBILITY_AND_DIVIDE_BY_POW10_INFO_F64::SHIFT_AMOUNT
      {n, c <= CHECK_DIVISIBILITY_AND_DIVIDE_BY_POW10_INFO_F64::THRESHOLD}
    end
  end

  # :nodoc:
  module ImplInfoMethods(D)
    def extract_exponent_bits(u : D::CarrierUInt)
      exponent_bits_mask = ~(UInt32::MAX << D::EXPONENT_BITS)
      ((u >> D::SIGNIFICAND_BITS) & exponent_bits_mask).to_u32!
    end

    def remove_exponent_bits(u : D::CarrierUInt, exponent_bits)
      D::SignedSignificand.new!(u ^ (D::CarrierUInt.new!(exponent_bits) << D::SIGNIFICAND_BITS))
    end

    def remove_sign_bit_and_shift(s : D::SignedSignificand)
      D::CarrierUInt.new!(s) << 1
    end

    def check_divisibility_and_divide_by_pow10(n : UInt32)
      {% if D::KAPPA == 1 %}
        Div.check_divisibility_and_divide_by_pow10_k1(n)
      {% elsif D::KAPPA == 2 %}
        Div.check_divisibility_and_divide_by_pow10_k2(n)
      {% else %}
        {% raise "expected kappa == 1 or kappa == 2" %}
      {% end %}
    end

    def get_cache(k : Int)
      # Precondition: `D::MIN_K <= k <= D::MAX_K`
      D::CACHE.unsafe_fetch(k - D::MIN_K)
    end
  end

  # :nodoc:
  module ImplInfo_Float32
    extend ImplInfoMethods(self)

    SIGNIFICAND_BITS =   23
    EXPONENT_BITS    =    8
    MIN_EXPONENT     = -126
    MAX_EXPONENT     =  127
    EXPONENT_BIAS    = -127
    DECIMAL_DIGITS   =    9

    alias CarrierUInt = UInt32
    alias SignedSignificand = Int32
    CARRIER_BITS = 32

    KAPPA =   1
    MIN_K = -31
    # MAX_K = 46
    CACHE_BITS = 64

    DIVISIBILITY_CHECK_BY_5_THRESHOLD                   =  39
    CASE_FC_PM_HALF_LOWER_THRESHOLD                     =  -1
    CASE_FC_PM_HALF_UPPER_THRESHOLD                     =   6
    CASE_FC_LOWER_THRESHOLD                             =  -2
    CASE_FC_UPPER_THRESHOLD                             =   6
    SHORTER_INTERVAL_TIE_LOWER_THRESHOLD                = -35
    SHORTER_INTERVAL_TIE_UPPER_THRESHOLD                = -35
    CASE_SHORTER_INTERVAL_LEFT_ENDPOINT_LOWER_THRESHOLD =   2
    CASE_SHORTER_INTERVAL_LEFT_ENDPOINT_UPPER_THRESHOLD =   3

    BIG_DIVISOR   = 10_u32 ** (KAPPA + 1)
    SMALL_DIVISOR = 10_u32 ** KAPPA

    CACHE = [
      0x81ceb32c4b43fcf5_u64,
      0xa2425ff75e14fc32_u64,
      0xcad2f7f5359a3b3f_u64,
      0xfd87b5f28300ca0e_u64,
      0x9e74d1b791e07e49_u64,
      0xc612062576589ddb_u64,
      0xf79687aed3eec552_u64,
      0x9abe14cd44753b53_u64,
      0xc16d9a0095928a28_u64,
      0xf1c90080baf72cb2_u64,
      0x971da05074da7bef_u64,
      0xbce5086492111aeb_u64,
      0xec1e4a7db69561a6_u64,
      0x9392ee8e921d5d08_u64,
      0xb877aa3236a4b44a_u64,
      0xe69594bec44de15c_u64,
      0x901d7cf73ab0acda_u64,
      0xb424dc35095cd810_u64,
      0xe12e13424bb40e14_u64,
      0x8cbccc096f5088cc_u64,
      0xafebff0bcb24aaff_u64,
      0xdbe6fecebdedd5bf_u64,
      0x89705f4136b4a598_u64,
      0xabcc77118461cefd_u64,
      0xd6bf94d5e57a42bd_u64,
      0x8637bd05af6c69b6_u64,
      0xa7c5ac471b478424_u64,
      0xd1b71758e219652c_u64,
      0x83126e978d4fdf3c_u64,
      0xa3d70a3d70a3d70b_u64,
      0xcccccccccccccccd_u64,
      0x8000000000000000_u64,
      0xa000000000000000_u64,
      0xc800000000000000_u64,
      0xfa00000000000000_u64,
      0x9c40000000000000_u64,
      0xc350000000000000_u64,
      0xf424000000000000_u64,
      0x9896800000000000_u64,
      0xbebc200000000000_u64,
      0xee6b280000000000_u64,
      0x9502f90000000000_u64,
      0xba43b74000000000_u64,
      0xe8d4a51000000000_u64,
      0x9184e72a00000000_u64,
      0xb5e620f480000000_u64,
      0xe35fa931a0000000_u64,
      0x8e1bc9bf04000000_u64,
      0xb1a2bc2ec5000000_u64,
      0xde0b6b3a76400000_u64,
      0x8ac7230489e80000_u64,
      0xad78ebc5ac620000_u64,
      0xd8d726b7177a8000_u64,
      0x878678326eac9000_u64,
      0xa968163f0a57b400_u64,
      0xd3c21bcecceda100_u64,
      0x84595161401484a0_u64,
      0xa56fa5b99019a5c8_u64,
      0xcecb8f27f4200f3a_u64,
      0x813f3978f8940984_u64,
      0xa18f07d736b90be5_u64,
      0xc9f2c9cd04674ede_u64,
      0xfc6f7c4045812296_u64,
      0x9dc5ada82b70b59d_u64,
      0xc5371912364ce305_u64,
      0xf684df56c3e01bc6_u64,
      0x9a130b963a6c115c_u64,
      0xc097ce7bc90715b3_u64,
      0xf0bdc21abb48db20_u64,
      0x96769950b50d88f4_u64,
      0xbc143fa4e250eb31_u64,
      0xeb194f8e1ae525fd_u64,
      0x92efd1b8d0cf37be_u64,
      0xb7abc627050305ad_u64,
      0xe596b7b0c643c719_u64,
      0x8f7e32ce7bea5c6f_u64,
      0xb35dbf821ae4f38b_u64,
      0xe0352f62a19e306e_u64,
    ]
  end

  # :nodoc:
  module ImplInfo_Float64
    extend ImplInfoMethods(self)

    SIGNIFICAND_BITS =    52
    EXPONENT_BITS    =    11
    MIN_EXPONENT     = -1022
    MAX_EXPONENT     =  1023
    EXPONENT_BIAS    = -1023
    DECIMAL_DIGITS   =    17

    alias CarrierUInt = UInt64
    alias SignedSignificand = Int64
    CARRIER_BITS = 64

    KAPPA =    2
    MIN_K = -292
    # MAX_K = 326
    CACHE_BITS = 128

    DIVISIBILITY_CHECK_BY_5_THRESHOLD                   =  86
    CASE_FC_PM_HALF_LOWER_THRESHOLD                     =  -2
    CASE_FC_PM_HALF_UPPER_THRESHOLD                     =   9
    CASE_FC_LOWER_THRESHOLD                             =  -4
    CASE_FC_UPPER_THRESHOLD                             =   9
    SHORTER_INTERVAL_TIE_LOWER_THRESHOLD                = -77
    SHORTER_INTERVAL_TIE_UPPER_THRESHOLD                = -77
    CASE_SHORTER_INTERVAL_LEFT_ENDPOINT_LOWER_THRESHOLD =   2
    CASE_SHORTER_INTERVAL_LEFT_ENDPOINT_UPPER_THRESHOLD =   3

    BIG_DIVISOR   = 10_u32 ** (KAPPA + 1)
    SMALL_DIVISOR = 10_u32 ** KAPPA

    # TODO: this is needed to avoid generating lots of allocas
    # in LLVM, which makes LLVM really slow. The compiler should
    # try to avoid/reuse temporary allocas.
    # Explanation: https://github.com/crystal-lang/crystal/issues/4516#issuecomment-306226171
    private def self.put(array, high, low) : Nil
      array << WUInt::UInt128.new(high: high, low: low)
    end

    CACHE = begin
      cache = [] of WUInt::UInt128
      put(cache, 0xff77b1fcbebcdc4f_u64, 0x25e8e89c13bb0f7b_u64)
      put(cache, 0x9faacf3df73609b1_u64, 0x77b191618c54e9ad_u64)
      put(cache, 0xc795830d75038c1d_u64, 0xd59df5b9ef6a2418_u64)
      put(cache, 0xf97ae3d0d2446f25_u64, 0x4b0573286b44ad1e_u64)
      put(cache, 0x9becce62836ac577_u64, 0x4ee367f9430aec33_u64)
      put(cache, 0xc2e801fb244576d5_u64, 0x229c41f793cda740_u64)
      put(cache, 0xf3a20279ed56d48a_u64, 0x6b43527578c11110_u64)
      put(cache, 0x9845418c345644d6_u64, 0x830a13896b78aaaa_u64)
      put(cache, 0xbe5691ef416bd60c_u64, 0x23cc986bc656d554_u64)
      put(cache, 0xedec366b11c6cb8f_u64, 0x2cbfbe86b7ec8aa9_u64)
      put(cache, 0x94b3a202eb1c3f39_u64, 0x7bf7d71432f3d6aa_u64)
      put(cache, 0xb9e08a83a5e34f07_u64, 0xdaf5ccd93fb0cc54_u64)
      put(cache, 0xe858ad248f5c22c9_u64, 0xd1b3400f8f9cff69_u64)
      put(cache, 0x91376c36d99995be_u64, 0x23100809b9c21fa2_u64)
      put(cache, 0xb58547448ffffb2d_u64, 0xabd40a0c2832a78b_u64)
      put(cache, 0xe2e69915b3fff9f9_u64, 0x16c90c8f323f516d_u64)
      put(cache, 0x8dd01fad907ffc3b_u64, 0xae3da7d97f6792e4_u64)
      put(cache, 0xb1442798f49ffb4a_u64, 0x99cd11cfdf41779d_u64)
      put(cache, 0xdd95317f31c7fa1d_u64, 0x40405643d711d584_u64)
      put(cache, 0x8a7d3eef7f1cfc52_u64, 0x482835ea666b2573_u64)
      put(cache, 0xad1c8eab5ee43b66_u64, 0xda3243650005eed0_u64)
      put(cache, 0xd863b256369d4a40_u64, 0x90bed43e40076a83_u64)
      put(cache, 0x873e4f75e2224e68_u64, 0x5a7744a6e804a292_u64)
      put(cache, 0xa90de3535aaae202_u64, 0x711515d0a205cb37_u64)
      put(cache, 0xd3515c2831559a83_u64, 0x0d5a5b44ca873e04_u64)
      put(cache, 0x8412d9991ed58091_u64, 0xe858790afe9486c3_u64)
      put(cache, 0xa5178fff668ae0b6_u64, 0x626e974dbe39a873_u64)
      put(cache, 0xce5d73ff402d98e3_u64, 0xfb0a3d212dc81290_u64)
      put(cache, 0x80fa687f881c7f8e_u64, 0x7ce66634bc9d0b9a_u64)
      put(cache, 0xa139029f6a239f72_u64, 0x1c1fffc1ebc44e81_u64)
      put(cache, 0xc987434744ac874e_u64, 0xa327ffb266b56221_u64)
      put(cache, 0xfbe9141915d7a922_u64, 0x4bf1ff9f0062baa9_u64)
      put(cache, 0x9d71ac8fada6c9b5_u64, 0x6f773fc3603db4aa_u64)
      put(cache, 0xc4ce17b399107c22_u64, 0xcb550fb4384d21d4_u64)
      put(cache, 0xf6019da07f549b2b_u64, 0x7e2a53a146606a49_u64)
      put(cache, 0x99c102844f94e0fb_u64, 0x2eda7444cbfc426e_u64)
      put(cache, 0xc0314325637a1939_u64, 0xfa911155fefb5309_u64)
      put(cache, 0xf03d93eebc589f88_u64, 0x793555ab7eba27cb_u64)
      put(cache, 0x96267c7535b763b5_u64, 0x4bc1558b2f3458df_u64)
      put(cache, 0xbbb01b9283253ca2_u64, 0x9eb1aaedfb016f17_u64)
      put(cache, 0xea9c227723ee8bcb_u64, 0x465e15a979c1cadd_u64)
      put(cache, 0x92a1958a7675175f_u64, 0x0bfacd89ec191eca_u64)
      put(cache, 0xb749faed14125d36_u64, 0xcef980ec671f667c_u64)
      put(cache, 0xe51c79a85916f484_u64, 0x82b7e12780e7401b_u64)
      put(cache, 0x8f31cc0937ae58d2_u64, 0xd1b2ecb8b0908811_u64)
      put(cache, 0xb2fe3f0b8599ef07_u64, 0x861fa7e6dcb4aa16_u64)
      put(cache, 0xdfbdcece67006ac9_u64, 0x67a791e093e1d49b_u64)
      put(cache, 0x8bd6a141006042bd_u64, 0xe0c8bb2c5c6d24e1_u64)
      put(cache, 0xaecc49914078536d_u64, 0x58fae9f773886e19_u64)
      put(cache, 0xda7f5bf590966848_u64, 0xaf39a475506a899f_u64)
      put(cache, 0x888f99797a5e012d_u64, 0x6d8406c952429604_u64)
      put(cache, 0xaab37fd7d8f58178_u64, 0xc8e5087ba6d33b84_u64)
      put(cache, 0xd5605fcdcf32e1d6_u64, 0xfb1e4a9a90880a65_u64)
      put(cache, 0x855c3be0a17fcd26_u64, 0x5cf2eea09a550680_u64)
      put(cache, 0xa6b34ad8c9dfc06f_u64, 0xf42faa48c0ea481f_u64)
      put(cache, 0xd0601d8efc57b08b_u64, 0xf13b94daf124da27_u64)
      put(cache, 0x823c12795db6ce57_u64, 0x76c53d08d6b70859_u64)
      put(cache, 0xa2cb1717b52481ed_u64, 0x54768c4b0c64ca6f_u64)
      put(cache, 0xcb7ddcdda26da268_u64, 0xa9942f5dcf7dfd0a_u64)
      put(cache, 0xfe5d54150b090b02_u64, 0xd3f93b35435d7c4d_u64)
      put(cache, 0x9efa548d26e5a6e1_u64, 0xc47bc5014a1a6db0_u64)
      put(cache, 0xc6b8e9b0709f109a_u64, 0x359ab6419ca1091c_u64)
      put(cache, 0xf867241c8cc6d4c0_u64, 0xc30163d203c94b63_u64)
      put(cache, 0x9b407691d7fc44f8_u64, 0x79e0de63425dcf1e_u64)
      put(cache, 0xc21094364dfb5636_u64, 0x985915fc12f542e5_u64)
      put(cache, 0xf294b943e17a2bc4_u64, 0x3e6f5b7b17b2939e_u64)
      put(cache, 0x979cf3ca6cec5b5a_u64, 0xa705992ceecf9c43_u64)
      put(cache, 0xbd8430bd08277231_u64, 0x50c6ff782a838354_u64)
      put(cache, 0xece53cec4a314ebd_u64, 0xa4f8bf5635246429_u64)
      put(cache, 0x940f4613ae5ed136_u64, 0x871b7795e136be9a_u64)
      put(cache, 0xb913179899f68584_u64, 0x28e2557b59846e40_u64)
      put(cache, 0xe757dd7ec07426e5_u64, 0x331aeada2fe589d0_u64)
      put(cache, 0x9096ea6f3848984f_u64, 0x3ff0d2c85def7622_u64)
      put(cache, 0xb4bca50b065abe63_u64, 0x0fed077a756b53aa_u64)
      put(cache, 0xe1ebce4dc7f16dfb_u64, 0xd3e8495912c62895_u64)
      put(cache, 0x8d3360f09cf6e4bd_u64, 0x64712dd7abbbd95d_u64)
      put(cache, 0xb080392cc4349dec_u64, 0xbd8d794d96aacfb4_u64)
      put(cache, 0xdca04777f541c567_u64, 0xecf0d7a0fc5583a1_u64)
      put(cache, 0x89e42caaf9491b60_u64, 0xf41686c49db57245_u64)
      put(cache, 0xac5d37d5b79b6239_u64, 0x311c2875c522ced6_u64)
      put(cache, 0xd77485cb25823ac7_u64, 0x7d633293366b828c_u64)
      put(cache, 0x86a8d39ef77164bc_u64, 0xae5dff9c02033198_u64)
      put(cache, 0xa8530886b54dbdeb_u64, 0xd9f57f830283fdfd_u64)
      put(cache, 0xd267caa862a12d66_u64, 0xd072df63c324fd7c_u64)
      put(cache, 0x8380dea93da4bc60_u64, 0x4247cb9e59f71e6e_u64)
      put(cache, 0xa46116538d0deb78_u64, 0x52d9be85f074e609_u64)
      put(cache, 0xcd795be870516656_u64, 0x67902e276c921f8c_u64)
      put(cache, 0x806bd9714632dff6_u64, 0x00ba1cd8a3db53b7_u64)
      put(cache, 0xa086cfcd97bf97f3_u64, 0x80e8a40eccd228a5_u64)
      put(cache, 0xc8a883c0fdaf7df0_u64, 0x6122cd128006b2ce_u64)
      put(cache, 0xfad2a4b13d1b5d6c_u64, 0x796b805720085f82_u64)
      put(cache, 0x9cc3a6eec6311a63_u64, 0xcbe3303674053bb1_u64)
      put(cache, 0xc3f490aa77bd60fc_u64, 0xbedbfc4411068a9d_u64)
      put(cache, 0xf4f1b4d515acb93b_u64, 0xee92fb5515482d45_u64)
      put(cache, 0x991711052d8bf3c5_u64, 0x751bdd152d4d1c4b_u64)
      put(cache, 0xbf5cd54678eef0b6_u64, 0xd262d45a78a0635e_u64)
      put(cache, 0xef340a98172aace4_u64, 0x86fb897116c87c35_u64)
      put(cache, 0x9580869f0e7aac0e_u64, 0xd45d35e6ae3d4da1_u64)
      put(cache, 0xbae0a846d2195712_u64, 0x8974836059cca10a_u64)
      put(cache, 0xe998d258869facd7_u64, 0x2bd1a438703fc94c_u64)
      put(cache, 0x91ff83775423cc06_u64, 0x7b6306a34627ddd0_u64)
      put(cache, 0xb67f6455292cbf08_u64, 0x1a3bc84c17b1d543_u64)
      put(cache, 0xe41f3d6a7377eeca_u64, 0x20caba5f1d9e4a94_u64)
      put(cache, 0x8e938662882af53e_u64, 0x547eb47b7282ee9d_u64)
      put(cache, 0xb23867fb2a35b28d_u64, 0xe99e619a4f23aa44_u64)
      put(cache, 0xdec681f9f4c31f31_u64, 0x6405fa00e2ec94d5_u64)
      put(cache, 0x8b3c113c38f9f37e_u64, 0xde83bc408dd3dd05_u64)
      put(cache, 0xae0b158b4738705e_u64, 0x9624ab50b148d446_u64)
      put(cache, 0xd98ddaee19068c76_u64, 0x3badd624dd9b0958_u64)
      put(cache, 0x87f8a8d4cfa417c9_u64, 0xe54ca5d70a80e5d7_u64)
      put(cache, 0xa9f6d30a038d1dbc_u64, 0x5e9fcf4ccd211f4d_u64)
      put(cache, 0xd47487cc8470652b_u64, 0x7647c32000696720_u64)
      put(cache, 0x84c8d4dfd2c63f3b_u64, 0x29ecd9f40041e074_u64)
      put(cache, 0xa5fb0a17c777cf09_u64, 0xf468107100525891_u64)
      put(cache, 0xcf79cc9db955c2cc_u64, 0x7182148d4066eeb5_u64)
      put(cache, 0x81ac1fe293d599bf_u64, 0xc6f14cd848405531_u64)
      put(cache, 0xa21727db38cb002f_u64, 0xb8ada00e5a506a7d_u64)
      put(cache, 0xca9cf1d206fdc03b_u64, 0xa6d90811f0e4851d_u64)
      put(cache, 0xfd442e4688bd304a_u64, 0x908f4a166d1da664_u64)
      put(cache, 0x9e4a9cec15763e2e_u64, 0x9a598e4e043287ff_u64)
      put(cache, 0xc5dd44271ad3cdba_u64, 0x40eff1e1853f29fe_u64)
      put(cache, 0xf7549530e188c128_u64, 0xd12bee59e68ef47d_u64)
      put(cache, 0x9a94dd3e8cf578b9_u64, 0x82bb74f8301958cf_u64)
      put(cache, 0xc13a148e3032d6e7_u64, 0xe36a52363c1faf02_u64)
      put(cache, 0xf18899b1bc3f8ca1_u64, 0xdc44e6c3cb279ac2_u64)
      put(cache, 0x96f5600f15a7b7e5_u64, 0x29ab103a5ef8c0ba_u64)
      put(cache, 0xbcb2b812db11a5de_u64, 0x7415d448f6b6f0e8_u64)
      put(cache, 0xebdf661791d60f56_u64, 0x111b495b3464ad22_u64)
      put(cache, 0x936b9fcebb25c995_u64, 0xcab10dd900beec35_u64)
      put(cache, 0xb84687c269ef3bfb_u64, 0x3d5d514f40eea743_u64)
      put(cache, 0xe65829b3046b0afa_u64, 0x0cb4a5a3112a5113_u64)
      put(cache, 0x8ff71a0fe2c2e6dc_u64, 0x47f0e785eaba72ac_u64)
      put(cache, 0xb3f4e093db73a093_u64, 0x59ed216765690f57_u64)
      put(cache, 0xe0f218b8d25088b8_u64, 0x306869c13ec3532d_u64)
      put(cache, 0x8c974f7383725573_u64, 0x1e414218c73a13fc_u64)
      put(cache, 0xafbd2350644eeacf_u64, 0xe5d1929ef90898fb_u64)
      put(cache, 0xdbac6c247d62a583_u64, 0xdf45f746b74abf3a_u64)
      put(cache, 0x894bc396ce5da772_u64, 0x6b8bba8c328eb784_u64)
      put(cache, 0xab9eb47c81f5114f_u64, 0x066ea92f3f326565_u64)
      put(cache, 0xd686619ba27255a2_u64, 0xc80a537b0efefebe_u64)
      put(cache, 0x8613fd0145877585_u64, 0xbd06742ce95f5f37_u64)
      put(cache, 0xa798fc4196e952e7_u64, 0x2c48113823b73705_u64)
      put(cache, 0xd17f3b51fca3a7a0_u64, 0xf75a15862ca504c6_u64)
      put(cache, 0x82ef85133de648c4_u64, 0x9a984d73dbe722fc_u64)
      put(cache, 0xa3ab66580d5fdaf5_u64, 0xc13e60d0d2e0ebbb_u64)
      put(cache, 0xcc963fee10b7d1b3_u64, 0x318df905079926a9_u64)
      put(cache, 0xffbbcfe994e5c61f_u64, 0xfdf17746497f7053_u64)
      put(cache, 0x9fd561f1fd0f9bd3_u64, 0xfeb6ea8bedefa634_u64)
      put(cache, 0xc7caba6e7c5382c8_u64, 0xfe64a52ee96b8fc1_u64)
      put(cache, 0xf9bd690a1b68637b_u64, 0x3dfdce7aa3c673b1_u64)
      put(cache, 0x9c1661a651213e2d_u64, 0x06bea10ca65c084f_u64)
      put(cache, 0xc31bfa0fe5698db8_u64, 0x486e494fcff30a63_u64)
      put(cache, 0xf3e2f893dec3f126_u64, 0x5a89dba3c3efccfb_u64)
      put(cache, 0x986ddb5c6b3a76b7_u64, 0xf89629465a75e01d_u64)
      put(cache, 0xbe89523386091465_u64, 0xf6bbb397f1135824_u64)
      put(cache, 0xee2ba6c0678b597f_u64, 0x746aa07ded582e2d_u64)
      put(cache, 0x94db483840b717ef_u64, 0xa8c2a44eb4571cdd_u64)
      put(cache, 0xba121a4650e4ddeb_u64, 0x92f34d62616ce414_u64)
      put(cache, 0xe896a0d7e51e1566_u64, 0x77b020baf9c81d18_u64)
      put(cache, 0x915e2486ef32cd60_u64, 0x0ace1474dc1d122f_u64)
      put(cache, 0xb5b5ada8aaff80b8_u64, 0x0d819992132456bb_u64)
      put(cache, 0xe3231912d5bf60e6_u64, 0x10e1fff697ed6c6a_u64)
      put(cache, 0x8df5efabc5979c8f_u64, 0xca8d3ffa1ef463c2_u64)
      put(cache, 0xb1736b96b6fd83b3_u64, 0xbd308ff8a6b17cb3_u64)
      put(cache, 0xddd0467c64bce4a0_u64, 0xac7cb3f6d05ddbdf_u64)
      put(cache, 0x8aa22c0dbef60ee4_u64, 0x6bcdf07a423aa96c_u64)
      put(cache, 0xad4ab7112eb3929d_u64, 0x86c16c98d2c953c7_u64)
      put(cache, 0xd89d64d57a607744_u64, 0xe871c7bf077ba8b8_u64)
      put(cache, 0x87625f056c7c4a8b_u64, 0x11471cd764ad4973_u64)
      put(cache, 0xa93af6c6c79b5d2d_u64, 0xd598e40d3dd89bd0_u64)
      put(cache, 0xd389b47879823479_u64, 0x4aff1d108d4ec2c4_u64)
      put(cache, 0x843610cb4bf160cb_u64, 0xcedf722a585139bb_u64)
      put(cache, 0xa54394fe1eedb8fe_u64, 0xc2974eb4ee658829_u64)
      put(cache, 0xce947a3da6a9273e_u64, 0x733d226229feea33_u64)
      put(cache, 0x811ccc668829b887_u64, 0x0806357d5a3f5260_u64)
      put(cache, 0xa163ff802a3426a8_u64, 0xca07c2dcb0cf26f8_u64)
      put(cache, 0xc9bcff6034c13052_u64, 0xfc89b393dd02f0b6_u64)
      put(cache, 0xfc2c3f3841f17c67_u64, 0xbbac2078d443ace3_u64)
      put(cache, 0x9d9ba7832936edc0_u64, 0xd54b944b84aa4c0e_u64)
      put(cache, 0xc5029163f384a931_u64, 0x0a9e795e65d4df12_u64)
      put(cache, 0xf64335bcf065d37d_u64, 0x4d4617b5ff4a16d6_u64)
      put(cache, 0x99ea0196163fa42e_u64, 0x504bced1bf8e4e46_u64)
      put(cache, 0xc06481fb9bcf8d39_u64, 0xe45ec2862f71e1d7_u64)
      put(cache, 0xf07da27a82c37088_u64, 0x5d767327bb4e5a4d_u64)
      put(cache, 0x964e858c91ba2655_u64, 0x3a6a07f8d510f870_u64)
      put(cache, 0xbbe226efb628afea_u64, 0x890489f70a55368c_u64)
      put(cache, 0xeadab0aba3b2dbe5_u64, 0x2b45ac74ccea842f_u64)
      put(cache, 0x92c8ae6b464fc96f_u64, 0x3b0b8bc90012929e_u64)
      put(cache, 0xb77ada0617e3bbcb_u64, 0x09ce6ebb40173745_u64)
      put(cache, 0xe55990879ddcaabd_u64, 0xcc420a6a101d0516_u64)
      put(cache, 0x8f57fa54c2a9eab6_u64, 0x9fa946824a12232e_u64)
      put(cache, 0xb32df8e9f3546564_u64, 0x47939822dc96abfa_u64)
      put(cache, 0xdff9772470297ebd_u64, 0x59787e2b93bc56f8_u64)
      put(cache, 0x8bfbea76c619ef36_u64, 0x57eb4edb3c55b65b_u64)
      put(cache, 0xaefae51477a06b03_u64, 0xede622920b6b23f2_u64)
      put(cache, 0xdab99e59958885c4_u64, 0xe95fab368e45ecee_u64)
      put(cache, 0x88b402f7fd75539b_u64, 0x11dbcb0218ebb415_u64)
      put(cache, 0xaae103b5fcd2a881_u64, 0xd652bdc29f26a11a_u64)
      put(cache, 0xd59944a37c0752a2_u64, 0x4be76d3346f04960_u64)
      put(cache, 0x857fcae62d8493a5_u64, 0x6f70a4400c562ddc_u64)
      put(cache, 0xa6dfbd9fb8e5b88e_u64, 0xcb4ccd500f6bb953_u64)
      put(cache, 0xd097ad07a71f26b2_u64, 0x7e2000a41346a7a8_u64)
      put(cache, 0x825ecc24c873782f_u64, 0x8ed400668c0c28c9_u64)
      put(cache, 0xa2f67f2dfa90563b_u64, 0x728900802f0f32fb_u64)
      put(cache, 0xcbb41ef979346bca_u64, 0x4f2b40a03ad2ffba_u64)
      put(cache, 0xfea126b7d78186bc_u64, 0xe2f610c84987bfa9_u64)
      put(cache, 0x9f24b832e6b0f436_u64, 0x0dd9ca7d2df4d7ca_u64)
      put(cache, 0xc6ede63fa05d3143_u64, 0x91503d1c79720dbc_u64)
      put(cache, 0xf8a95fcf88747d94_u64, 0x75a44c6397ce912b_u64)
      put(cache, 0x9b69dbe1b548ce7c_u64, 0xc986afbe3ee11abb_u64)
      put(cache, 0xc24452da229b021b_u64, 0xfbe85badce996169_u64)
      put(cache, 0xf2d56790ab41c2a2_u64, 0xfae27299423fb9c4_u64)
      put(cache, 0x97c560ba6b0919a5_u64, 0xdccd879fc967d41b_u64)
      put(cache, 0xbdb6b8e905cb600f_u64, 0x5400e987bbc1c921_u64)
      put(cache, 0xed246723473e3813_u64, 0x290123e9aab23b69_u64)
      put(cache, 0x9436c0760c86e30b_u64, 0xf9a0b6720aaf6522_u64)
      put(cache, 0xb94470938fa89bce_u64, 0xf808e40e8d5b3e6a_u64)
      put(cache, 0xe7958cb87392c2c2_u64, 0xb60b1d1230b20e05_u64)
      put(cache, 0x90bd77f3483bb9b9_u64, 0xb1c6f22b5e6f48c3_u64)
      put(cache, 0xb4ecd5f01a4aa828_u64, 0x1e38aeb6360b1af4_u64)
      put(cache, 0xe2280b6c20dd5232_u64, 0x25c6da63c38de1b1_u64)
      put(cache, 0x8d590723948a535f_u64, 0x579c487e5a38ad0f_u64)
      put(cache, 0xb0af48ec79ace837_u64, 0x2d835a9df0c6d852_u64)
      put(cache, 0xdcdb1b2798182244_u64, 0xf8e431456cf88e66_u64)
      put(cache, 0x8a08f0f8bf0f156b_u64, 0x1b8e9ecb641b5900_u64)
      put(cache, 0xac8b2d36eed2dac5_u64, 0xe272467e3d222f40_u64)
      put(cache, 0xd7adf884aa879177_u64, 0x5b0ed81dcc6abb10_u64)
      put(cache, 0x86ccbb52ea94baea_u64, 0x98e947129fc2b4ea_u64)
      put(cache, 0xa87fea27a539e9a5_u64, 0x3f2398d747b36225_u64)
      put(cache, 0xd29fe4b18e88640e_u64, 0x8eec7f0d19a03aae_u64)
      put(cache, 0x83a3eeeef9153e89_u64, 0x1953cf68300424ad_u64)
      put(cache, 0xa48ceaaab75a8e2b_u64, 0x5fa8c3423c052dd8_u64)
      put(cache, 0xcdb02555653131b6_u64, 0x3792f412cb06794e_u64)
      put(cache, 0x808e17555f3ebf11_u64, 0xe2bbd88bbee40bd1_u64)
      put(cache, 0xa0b19d2ab70e6ed6_u64, 0x5b6aceaeae9d0ec5_u64)
      put(cache, 0xc8de047564d20a8b_u64, 0xf245825a5a445276_u64)
      put(cache, 0xfb158592be068d2e_u64, 0xeed6e2f0f0d56713_u64)
      put(cache, 0x9ced737bb6c4183d_u64, 0x55464dd69685606c_u64)
      put(cache, 0xc428d05aa4751e4c_u64, 0xaa97e14c3c26b887_u64)
      put(cache, 0xf53304714d9265df_u64, 0xd53dd99f4b3066a9_u64)
      put(cache, 0x993fe2c6d07b7fab_u64, 0xe546a8038efe402a_u64)
      put(cache, 0xbf8fdb78849a5f96_u64, 0xde98520472bdd034_u64)
      put(cache, 0xef73d256a5c0f77c_u64, 0x963e66858f6d4441_u64)
      put(cache, 0x95a8637627989aad_u64, 0xdde7001379a44aa9_u64)
      put(cache, 0xbb127c53b17ec159_u64, 0x5560c018580d5d53_u64)
      put(cache, 0xe9d71b689dde71af_u64, 0xaab8f01e6e10b4a7_u64)
      put(cache, 0x9226712162ab070d_u64, 0xcab3961304ca70e9_u64)
      put(cache, 0xb6b00d69bb55c8d1_u64, 0x3d607b97c5fd0d23_u64)
      put(cache, 0xe45c10c42a2b3b05_u64, 0x8cb89a7db77c506b_u64)
      put(cache, 0x8eb98a7a9a5b04e3_u64, 0x77f3608e92adb243_u64)
      put(cache, 0xb267ed1940f1c61c_u64, 0x55f038b237591ed4_u64)
      put(cache, 0xdf01e85f912e37a3_u64, 0x6b6c46dec52f6689_u64)
      put(cache, 0x8b61313bbabce2c6_u64, 0x2323ac4b3b3da016_u64)
      put(cache, 0xae397d8aa96c1b77_u64, 0xabec975e0a0d081b_u64)
      put(cache, 0xd9c7dced53c72255_u64, 0x96e7bd358c904a22_u64)
      put(cache, 0x881cea14545c7575_u64, 0x7e50d64177da2e55_u64)
      put(cache, 0xaa242499697392d2_u64, 0xdde50bd1d5d0b9ea_u64)
      put(cache, 0xd4ad2dbfc3d07787_u64, 0x955e4ec64b44e865_u64)
      put(cache, 0x84ec3c97da624ab4_u64, 0xbd5af13bef0b113f_u64)
      put(cache, 0xa6274bbdd0fadd61_u64, 0xecb1ad8aeacdd58f_u64)
      put(cache, 0xcfb11ead453994ba_u64, 0x67de18eda5814af3_u64)
      put(cache, 0x81ceb32c4b43fcf4_u64, 0x80eacf948770ced8_u64)
      put(cache, 0xa2425ff75e14fc31_u64, 0xa1258379a94d028e_u64)
      put(cache, 0xcad2f7f5359a3b3e_u64, 0x096ee45813a04331_u64)
      put(cache, 0xfd87b5f28300ca0d_u64, 0x8bca9d6e188853fd_u64)
      put(cache, 0x9e74d1b791e07e48_u64, 0x775ea264cf55347e_u64)
      put(cache, 0xc612062576589dda_u64, 0x95364afe032a819e_u64)
      put(cache, 0xf79687aed3eec551_u64, 0x3a83ddbd83f52205_u64)
      put(cache, 0x9abe14cd44753b52_u64, 0xc4926a9672793543_u64)
      put(cache, 0xc16d9a0095928a27_u64, 0x75b7053c0f178294_u64)
      put(cache, 0xf1c90080baf72cb1_u64, 0x5324c68b12dd6339_u64)
      put(cache, 0x971da05074da7bee_u64, 0xd3f6fc16ebca5e04_u64)
      put(cache, 0xbce5086492111aea_u64, 0x88f4bb1ca6bcf585_u64)
      put(cache, 0xec1e4a7db69561a5_u64, 0x2b31e9e3d06c32e6_u64)
      put(cache, 0x9392ee8e921d5d07_u64, 0x3aff322e62439fd0_u64)
      put(cache, 0xb877aa3236a4b449_u64, 0x09befeb9fad487c3_u64)
      put(cache, 0xe69594bec44de15b_u64, 0x4c2ebe687989a9b4_u64)
      put(cache, 0x901d7cf73ab0acd9_u64, 0x0f9d37014bf60a11_u64)
      put(cache, 0xb424dc35095cd80f_u64, 0x538484c19ef38c95_u64)
      put(cache, 0xe12e13424bb40e13_u64, 0x2865a5f206b06fba_u64)
      put(cache, 0x8cbccc096f5088cb_u64, 0xf93f87b7442e45d4_u64)
      put(cache, 0xafebff0bcb24aafe_u64, 0xf78f69a51539d749_u64)
      put(cache, 0xdbe6fecebdedd5be_u64, 0xb573440e5a884d1c_u64)
      put(cache, 0x89705f4136b4a597_u64, 0x31680a88f8953031_u64)
      put(cache, 0xabcc77118461cefc_u64, 0xfdc20d2b36ba7c3e_u64)
      put(cache, 0xd6bf94d5e57a42bc_u64, 0x3d32907604691b4d_u64)
      put(cache, 0x8637bd05af6c69b5_u64, 0xa63f9a49c2c1b110_u64)
      put(cache, 0xa7c5ac471b478423_u64, 0x0fcf80dc33721d54_u64)
      put(cache, 0xd1b71758e219652b_u64, 0xd3c36113404ea4a9_u64)
      put(cache, 0x83126e978d4fdf3b_u64, 0x645a1cac083126ea_u64)
      put(cache, 0xa3d70a3d70a3d70a_u64, 0x3d70a3d70a3d70a4_u64)
      put(cache, 0xcccccccccccccccc_u64, 0xcccccccccccccccd_u64)
      put(cache, 0x8000000000000000_u64, 0x0000000000000000_u64)
      put(cache, 0xa000000000000000_u64, 0x0000000000000000_u64)
      put(cache, 0xc800000000000000_u64, 0x0000000000000000_u64)
      put(cache, 0xfa00000000000000_u64, 0x0000000000000000_u64)
      put(cache, 0x9c40000000000000_u64, 0x0000000000000000_u64)
      put(cache, 0xc350000000000000_u64, 0x0000000000000000_u64)
      put(cache, 0xf424000000000000_u64, 0x0000000000000000_u64)
      put(cache, 0x9896800000000000_u64, 0x0000000000000000_u64)
      put(cache, 0xbebc200000000000_u64, 0x0000000000000000_u64)
      put(cache, 0xee6b280000000000_u64, 0x0000000000000000_u64)
      put(cache, 0x9502f90000000000_u64, 0x0000000000000000_u64)
      put(cache, 0xba43b74000000000_u64, 0x0000000000000000_u64)
      put(cache, 0xe8d4a51000000000_u64, 0x0000000000000000_u64)
      put(cache, 0x9184e72a00000000_u64, 0x0000000000000000_u64)
      put(cache, 0xb5e620f480000000_u64, 0x0000000000000000_u64)
      put(cache, 0xe35fa931a0000000_u64, 0x0000000000000000_u64)
      put(cache, 0x8e1bc9bf04000000_u64, 0x0000000000000000_u64)
      put(cache, 0xb1a2bc2ec5000000_u64, 0x0000000000000000_u64)
      put(cache, 0xde0b6b3a76400000_u64, 0x0000000000000000_u64)
      put(cache, 0x8ac7230489e80000_u64, 0x0000000000000000_u64)
      put(cache, 0xad78ebc5ac620000_u64, 0x0000000000000000_u64)
      put(cache, 0xd8d726b7177a8000_u64, 0x0000000000000000_u64)
      put(cache, 0x878678326eac9000_u64, 0x0000000000000000_u64)
      put(cache, 0xa968163f0a57b400_u64, 0x0000000000000000_u64)
      put(cache, 0xd3c21bcecceda100_u64, 0x0000000000000000_u64)
      put(cache, 0x84595161401484a0_u64, 0x0000000000000000_u64)
      put(cache, 0xa56fa5b99019a5c8_u64, 0x0000000000000000_u64)
      put(cache, 0xcecb8f27f4200f3a_u64, 0x0000000000000000_u64)
      put(cache, 0x813f3978f8940984_u64, 0x4000000000000000_u64)
      put(cache, 0xa18f07d736b90be5_u64, 0x5000000000000000_u64)
      put(cache, 0xc9f2c9cd04674ede_u64, 0xa400000000000000_u64)
      put(cache, 0xfc6f7c4045812296_u64, 0x4d00000000000000_u64)
      put(cache, 0x9dc5ada82b70b59d_u64, 0xf020000000000000_u64)
      put(cache, 0xc5371912364ce305_u64, 0x6c28000000000000_u64)
      put(cache, 0xf684df56c3e01bc6_u64, 0xc732000000000000_u64)
      put(cache, 0x9a130b963a6c115c_u64, 0x3c7f400000000000_u64)
      put(cache, 0xc097ce7bc90715b3_u64, 0x4b9f100000000000_u64)
      put(cache, 0xf0bdc21abb48db20_u64, 0x1e86d40000000000_u64)
      put(cache, 0x96769950b50d88f4_u64, 0x1314448000000000_u64)
      put(cache, 0xbc143fa4e250eb31_u64, 0x17d955a000000000_u64)
      put(cache, 0xeb194f8e1ae525fd_u64, 0x5dcfab0800000000_u64)
      put(cache, 0x92efd1b8d0cf37be_u64, 0x5aa1cae500000000_u64)
      put(cache, 0xb7abc627050305ad_u64, 0xf14a3d9e40000000_u64)
      put(cache, 0xe596b7b0c643c719_u64, 0x6d9ccd05d0000000_u64)
      put(cache, 0x8f7e32ce7bea5c6f_u64, 0xe4820023a2000000_u64)
      put(cache, 0xb35dbf821ae4f38b_u64, 0xdda2802c8a800000_u64)
      put(cache, 0xe0352f62a19e306e_u64, 0xd50b2037ad200000_u64)
      put(cache, 0x8c213d9da502de45_u64, 0x4526f422cc340000_u64)
      put(cache, 0xaf298d050e4395d6_u64, 0x9670b12b7f410000_u64)
      put(cache, 0xdaf3f04651d47b4c_u64, 0x3c0cdd765f114000_u64)
      put(cache, 0x88d8762bf324cd0f_u64, 0xa5880a69fb6ac800_u64)
      put(cache, 0xab0e93b6efee0053_u64, 0x8eea0d047a457a00_u64)
      put(cache, 0xd5d238a4abe98068_u64, 0x72a4904598d6d880_u64)
      put(cache, 0x85a36366eb71f041_u64, 0x47a6da2b7f864750_u64)
      put(cache, 0xa70c3c40a64e6c51_u64, 0x999090b65f67d924_u64)
      put(cache, 0xd0cf4b50cfe20765_u64, 0xfff4b4e3f741cf6d_u64)
      put(cache, 0x82818f1281ed449f_u64, 0xbff8f10e7a8921a4_u64)
      put(cache, 0xa321f2d7226895c7_u64, 0xaff72d52192b6a0d_u64)
      put(cache, 0xcbea6f8ceb02bb39_u64, 0x9bf4f8a69f764490_u64)
      put(cache, 0xfee50b7025c36a08_u64, 0x02f236d04753d5b4_u64)
      put(cache, 0x9f4f2726179a2245_u64, 0x01d762422c946590_u64)
      put(cache, 0xc722f0ef9d80aad6_u64, 0x424d3ad2b7b97ef5_u64)
      put(cache, 0xf8ebad2b84e0d58b_u64, 0xd2e0898765a7deb2_u64)
      put(cache, 0x9b934c3b330c8577_u64, 0x63cc55f49f88eb2f_u64)
      put(cache, 0xc2781f49ffcfa6d5_u64, 0x3cbf6b71c76b25fb_u64)
      put(cache, 0xf316271c7fc3908a_u64, 0x8bef464e3945ef7a_u64)
      put(cache, 0x97edd871cfda3a56_u64, 0x97758bf0e3cbb5ac_u64)
      put(cache, 0xbde94e8e43d0c8ec_u64, 0x3d52eeed1cbea317_u64)
      put(cache, 0xed63a231d4c4fb27_u64, 0x4ca7aaa863ee4bdd_u64)
      put(cache, 0x945e455f24fb1cf8_u64, 0x8fe8caa93e74ef6a_u64)
      put(cache, 0xb975d6b6ee39e436_u64, 0xb3e2fd538e122b44_u64)
      put(cache, 0xe7d34c64a9c85d44_u64, 0x60dbbca87196b616_u64)
      put(cache, 0x90e40fbeea1d3a4a_u64, 0xbc8955e946fe31cd_u64)
      put(cache, 0xb51d13aea4a488dd_u64, 0x6babab6398bdbe41_u64)
      put(cache, 0xe264589a4dcdab14_u64, 0xc696963c7eed2dd1_u64)
      put(cache, 0x8d7eb76070a08aec_u64, 0xfc1e1de5cf543ca2_u64)
      put(cache, 0xb0de65388cc8ada8_u64, 0x3b25a55f43294bcb_u64)
      put(cache, 0xdd15fe86affad912_u64, 0x49ef0eb713f39ebe_u64)
      put(cache, 0x8a2dbf142dfcc7ab_u64, 0x6e3569326c784337_u64)
      put(cache, 0xacb92ed9397bf996_u64, 0x49c2c37f07965404_u64)
      put(cache, 0xd7e77a8f87daf7fb_u64, 0xdc33745ec97be906_u64)
      put(cache, 0x86f0ac99b4e8dafd_u64, 0x69a028bb3ded71a3_u64)
      put(cache, 0xa8acd7c0222311bc_u64, 0xc40832ea0d68ce0c_u64)
      put(cache, 0xd2d80db02aabd62b_u64, 0xf50a3fa490c30190_u64)
      put(cache, 0x83c7088e1aab65db_u64, 0x792667c6da79e0fa_u64)
      put(cache, 0xa4b8cab1a1563f52_u64, 0x577001b891185938_u64)
      put(cache, 0xcde6fd5e09abcf26_u64, 0xed4c0226b55e6f86_u64)
      put(cache, 0x80b05e5ac60b6178_u64, 0x544f8158315b05b4_u64)
      put(cache, 0xa0dc75f1778e39d6_u64, 0x696361ae3db1c721_u64)
      put(cache, 0xc913936dd571c84c_u64, 0x03bc3a19cd1e38e9_u64)
      put(cache, 0xfb5878494ace3a5f_u64, 0x04ab48a04065c723_u64)
      put(cache, 0x9d174b2dcec0e47b_u64, 0x62eb0d64283f9c76_u64)
      put(cache, 0xc45d1df942711d9a_u64, 0x3ba5d0bd324f8394_u64)
      put(cache, 0xf5746577930d6500_u64, 0xca8f44ec7ee36479_u64)
      put(cache, 0x9968bf6abbe85f20_u64, 0x7e998b13cf4e1ecb_u64)
      put(cache, 0xbfc2ef456ae276e8_u64, 0x9e3fedd8c321a67e_u64)
      put(cache, 0xefb3ab16c59b14a2_u64, 0xc5cfe94ef3ea101e_u64)
      put(cache, 0x95d04aee3b80ece5_u64, 0xbba1f1d158724a12_u64)
      put(cache, 0xbb445da9ca61281f_u64, 0x2a8a6e45ae8edc97_u64)
      put(cache, 0xea1575143cf97226_u64, 0xf52d09d71a3293bd_u64)
      put(cache, 0x924d692ca61be758_u64, 0x593c2626705f9c56_u64)
      put(cache, 0xb6e0c377cfa2e12e_u64, 0x6f8b2fb00c77836c_u64)
      put(cache, 0xe498f455c38b997a_u64, 0x0b6dfb9c0f956447_u64)
      put(cache, 0x8edf98b59a373fec_u64, 0x4724bd4189bd5eac_u64)
      put(cache, 0xb2977ee300c50fe7_u64, 0x58edec91ec2cb657_u64)
      put(cache, 0xdf3d5e9bc0f653e1_u64, 0x2f2967b66737e3ed_u64)
      put(cache, 0x8b865b215899f46c_u64, 0xbd79e0d20082ee74_u64)
      put(cache, 0xae67f1e9aec07187_u64, 0xecd8590680a3aa11_u64)
      put(cache, 0xda01ee641a708de9_u64, 0xe80e6f4820cc9495_u64)
      put(cache, 0x884134fe908658b2_u64, 0x3109058d147fdcdd_u64)
      put(cache, 0xaa51823e34a7eede_u64, 0xbd4b46f0599fd415_u64)
      put(cache, 0xd4e5e2cdc1d1ea96_u64, 0x6c9e18ac7007c91a_u64)
      put(cache, 0x850fadc09923329e_u64, 0x03e2cf6bc604ddb0_u64)
      put(cache, 0xa6539930bf6bff45_u64, 0x84db8346b786151c_u64)
      put(cache, 0xcfe87f7cef46ff16_u64, 0xe612641865679a63_u64)
      put(cache, 0x81f14fae158c5f6e_u64, 0x4fcb7e8f3f60c07e_u64)
      put(cache, 0xa26da3999aef7749_u64, 0xe3be5e330f38f09d_u64)
      put(cache, 0xcb090c8001ab551c_u64, 0x5cadf5bfd3072cc5_u64)
      put(cache, 0xfdcb4fa002162a63_u64, 0x73d9732fc7c8f7f6_u64)
      put(cache, 0x9e9f11c4014dda7e_u64, 0x2867e7fddcdd9afa_u64)
      put(cache, 0xc646d63501a1511d_u64, 0xb281e1fd541501b8_u64)
      put(cache, 0xf7d88bc24209a565_u64, 0x1f225a7ca91a4226_u64)
      put(cache, 0x9ae757596946075f_u64, 0x3375788de9b06958_u64)
      put(cache, 0xc1a12d2fc3978937_u64, 0x0052d6b1641c83ae_u64)
      put(cache, 0xf209787bb47d6b84_u64, 0xc0678c5dbd23a49a_u64)
      put(cache, 0x9745eb4d50ce6332_u64, 0xf840b7ba963646e0_u64)
      put(cache, 0xbd176620a501fbff_u64, 0xb650e5a93bc3d898_u64)
      put(cache, 0xec5d3fa8ce427aff_u64, 0xa3e51f138ab4cebe_u64)
      put(cache, 0x93ba47c980e98cdf_u64, 0xc66f336c36b10137_u64)
      put(cache, 0xb8a8d9bbe123f017_u64, 0xb80b0047445d4184_u64)
      put(cache, 0xe6d3102ad96cec1d_u64, 0xa60dc059157491e5_u64)
      put(cache, 0x9043ea1ac7e41392_u64, 0x87c89837ad68db2f_u64)
      put(cache, 0xb454e4a179dd1877_u64, 0x29babe4598c311fb_u64)
      put(cache, 0xe16a1dc9d8545e94_u64, 0xf4296dd6fef3d67a_u64)
      put(cache, 0x8ce2529e2734bb1d_u64, 0x1899e4a65f58660c_u64)
      put(cache, 0xb01ae745b101e9e4_u64, 0x5ec05dcff72e7f8f_u64)
      put(cache, 0xdc21a1171d42645d_u64, 0x76707543f4fa1f73_u64)
      put(cache, 0x899504ae72497eba_u64, 0x6a06494a791c53a8_u64)
      put(cache, 0xabfa45da0edbde69_u64, 0x0487db9d17636892_u64)
      put(cache, 0xd6f8d7509292d603_u64, 0x45a9d2845d3c42b6_u64)
      put(cache, 0x865b86925b9bc5c2_u64, 0x0b8a2392ba45a9b2_u64)
      put(cache, 0xa7f26836f282b732_u64, 0x8e6cac7768d7141e_u64)
      put(cache, 0xd1ef0244af2364ff_u64, 0x3207d795430cd926_u64)
      put(cache, 0x8335616aed761f1f_u64, 0x7f44e6bd49e807b8_u64)
      put(cache, 0xa402b9c5a8d3a6e7_u64, 0x5f16206c9c6209a6_u64)
      put(cache, 0xcd036837130890a1_u64, 0x36dba887c37a8c0f_u64)
      put(cache, 0x802221226be55a64_u64, 0xc2494954da2c9789_u64)
      put(cache, 0xa02aa96b06deb0fd_u64, 0xf2db9baa10b7bd6c_u64)
      put(cache, 0xc83553c5c8965d3d_u64, 0x6f92829494e5acc7_u64)
      put(cache, 0xfa42a8b73abbf48c_u64, 0xcb772339ba1f17f9_u64)
      put(cache, 0x9c69a97284b578d7_u64, 0xff2a760414536efb_u64)
      put(cache, 0xc38413cf25e2d70d_u64, 0xfef5138519684aba_u64)
      put(cache, 0xf46518c2ef5b8cd1_u64, 0x7eb258665fc25d69_u64)
      put(cache, 0x98bf2f79d5993802_u64, 0xef2f773ffbd97a61_u64)
      put(cache, 0xbeeefb584aff8603_u64, 0xaafb550ffacfd8fa_u64)
      put(cache, 0xeeaaba2e5dbf6784_u64, 0x95ba2a53f983cf38_u64)
      put(cache, 0x952ab45cfa97a0b2_u64, 0xdd945a747bf26183_u64)
      put(cache, 0xba756174393d88df_u64, 0x94f971119aeef9e4_u64)
      put(cache, 0xe912b9d1478ceb17_u64, 0x7a37cd5601aab85d_u64)
      put(cache, 0x91abb422ccb812ee_u64, 0xac62e055c10ab33a_u64)
      put(cache, 0xb616a12b7fe617aa_u64, 0x577b986b314d6009_u64)
      put(cache, 0xe39c49765fdf9d94_u64, 0xed5a7e85fda0b80b_u64)
      put(cache, 0x8e41ade9fbebc27d_u64, 0x14588f13be847307_u64)
      put(cache, 0xb1d219647ae6b31c_u64, 0x596eb2d8ae258fc8_u64)
      put(cache, 0xde469fbd99a05fe3_u64, 0x6fca5f8ed9aef3bb_u64)
      put(cache, 0x8aec23d680043bee_u64, 0x25de7bb9480d5854_u64)
      put(cache, 0xada72ccc20054ae9_u64, 0xaf561aa79a10ae6a_u64)
      put(cache, 0xd910f7ff28069da4_u64, 0x1b2ba1518094da04_u64)
      put(cache, 0x87aa9aff79042286_u64, 0x90fb44d2f05d0842_u64)
      put(cache, 0xa99541bf57452b28_u64, 0x353a1607ac744a53_u64)
      put(cache, 0xd3fa922f2d1675f2_u64, 0x42889b8997915ce8_u64)
      put(cache, 0x847c9b5d7c2e09b7_u64, 0x69956135febada11_u64)
      put(cache, 0xa59bc234db398c25_u64, 0x43fab9837e699095_u64)
      put(cache, 0xcf02b2c21207ef2e_u64, 0x94f967e45e03f4bb_u64)
      put(cache, 0x8161afb94b44f57d_u64, 0x1d1be0eebac278f5_u64)
      put(cache, 0xa1ba1ba79e1632dc_u64, 0x6462d92a69731732_u64)
      put(cache, 0xca28a291859bbf93_u64, 0x7d7b8f7503cfdcfe_u64)
      put(cache, 0xfcb2cb35e702af78_u64, 0x5cda735244c3d43e_u64)
      put(cache, 0x9defbf01b061adab_u64, 0x3a0888136afa64a7_u64)
      put(cache, 0xc56baec21c7a1916_u64, 0x088aaa1845b8fdd0_u64)
      put(cache, 0xf6c69a72a3989f5b_u64, 0x8aad549e57273d45_u64)
      put(cache, 0x9a3c2087a63f6399_u64, 0x36ac54e2f678864b_u64)
      put(cache, 0xc0cb28a98fcf3c7f_u64, 0x84576a1bb416a7dd_u64)
      put(cache, 0xf0fdf2d3f3c30b9f_u64, 0x656d44a2a11c51d5_u64)
      put(cache, 0x969eb7c47859e743_u64, 0x9f644ae5a4b1b325_u64)
      put(cache, 0xbc4665b596706114_u64, 0x873d5d9f0dde1fee_u64)
      put(cache, 0xeb57ff22fc0c7959_u64, 0xa90cb506d155a7ea_u64)
      put(cache, 0x9316ff75dd87cbd8_u64, 0x09a7f12442d588f2_u64)
      put(cache, 0xb7dcbf5354e9bece_u64, 0x0c11ed6d538aeb2f_u64)
      put(cache, 0xe5d3ef282a242e81_u64, 0x8f1668c8a86da5fa_u64)
      put(cache, 0x8fa475791a569d10_u64, 0xf96e017d694487bc_u64)
      put(cache, 0xb38d92d760ec4455_u64, 0x37c981dcc395a9ac_u64)
      put(cache, 0xe070f78d3927556a_u64, 0x85bbe253f47b1417_u64)
      put(cache, 0x8c469ab843b89562_u64, 0x93956d7478ccec8e_u64)
      put(cache, 0xaf58416654a6babb_u64, 0x387ac8d1970027b2_u64)
      put(cache, 0xdb2e51bfe9d0696a_u64, 0x06997b05fcc0319e_u64)
      put(cache, 0x88fcf317f22241e2_u64, 0x441fece3bdf81f03_u64)
      put(cache, 0xab3c2fddeeaad25a_u64, 0xd527e81cad7626c3_u64)
      put(cache, 0xd60b3bd56a5586f1_u64, 0x8a71e223d8d3b074_u64)
      put(cache, 0x85c7056562757456_u64, 0xf6872d5667844e49_u64)
      put(cache, 0xa738c6bebb12d16c_u64, 0xb428f8ac016561db_u64)
      put(cache, 0xd106f86e69d785c7_u64, 0xe13336d701beba52_u64)
      put(cache, 0x82a45b450226b39c_u64, 0xecc0024661173473_u64)
      put(cache, 0xa34d721642b06084_u64, 0x27f002d7f95d0190_u64)
      put(cache, 0xcc20ce9bd35c78a5_u64, 0x31ec038df7b441f4_u64)
      put(cache, 0xff290242c83396ce_u64, 0x7e67047175a15271_u64)
      put(cache, 0x9f79a169bd203e41_u64, 0x0f0062c6e984d386_u64)
      put(cache, 0xc75809c42c684dd1_u64, 0x52c07b78a3e60868_u64)
      put(cache, 0xf92e0c3537826145_u64, 0xa7709a56ccdf8a82_u64)
      put(cache, 0x9bbcc7a142b17ccb_u64, 0x88a66076400bb691_u64)
      put(cache, 0xc2abf989935ddbfe_u64, 0x6acff893d00ea435_u64)
      put(cache, 0xf356f7ebf83552fe_u64, 0x0583f6b8c4124d43_u64)
      put(cache, 0x98165af37b2153de_u64, 0xc3727a337a8b704a_u64)
      put(cache, 0xbe1bf1b059e9a8d6_u64, 0x744f18c0592e4c5c_u64)
      put(cache, 0xeda2ee1c7064130c_u64, 0x1162def06f79df73_u64)
      put(cache, 0x9485d4d1c63e8be7_u64, 0x8addcb5645ac2ba8_u64)
      put(cache, 0xb9a74a0637ce2ee1_u64, 0x6d953e2bd7173692_u64)
      put(cache, 0xe8111c87c5c1ba99_u64, 0xc8fa8db6ccdd0437_u64)
      put(cache, 0x910ab1d4db9914a0_u64, 0x1d9c9892400a22a2_u64)
      put(cache, 0xb54d5e4a127f59c8_u64, 0x2503beb6d00cab4b_u64)
      put(cache, 0xe2a0b5dc971f303a_u64, 0x2e44ae64840fd61d_u64)
      put(cache, 0x8da471a9de737e24_u64, 0x5ceaecfed289e5d2_u64)
      put(cache, 0xb10d8e1456105dad_u64, 0x7425a83e872c5f47_u64)
      put(cache, 0xdd50f1996b947518_u64, 0xd12f124e28f77719_u64)
      put(cache, 0x8a5296ffe33cc92f_u64, 0x82bd6b70d99aaa6f_u64)
      put(cache, 0xace73cbfdc0bfb7b_u64, 0x636cc64d1001550b_u64)
      put(cache, 0xd8210befd30efa5a_u64, 0x3c47f7e05401aa4e_u64)
      put(cache, 0x8714a775e3e95c78_u64, 0x65acfaec34810a71_u64)
      put(cache, 0xa8d9d1535ce3b396_u64, 0x7f1839a741a14d0d_u64)
      put(cache, 0xd31045a8341ca07c_u64, 0x1ede48111209a050_u64)
      put(cache, 0x83ea2b892091e44d_u64, 0x934aed0aab460432_u64)
      put(cache, 0xa4e4b66b68b65d60_u64, 0xf81da84d5617853f_u64)
      put(cache, 0xce1de40642e3f4b9_u64, 0x36251260ab9d668e_u64)
      put(cache, 0x80d2ae83e9ce78f3_u64, 0xc1d72b7c6b426019_u64)
      put(cache, 0xa1075a24e4421730_u64, 0xb24cf65b8612f81f_u64)
      put(cache, 0xc94930ae1d529cfc_u64, 0xdee033f26797b627_u64)
      put(cache, 0xfb9b7cd9a4a7443c_u64, 0x169840ef017da3b1_u64)
      put(cache, 0x9d412e0806e88aa5_u64, 0x8e1f289560ee864e_u64)
      put(cache, 0xc491798a08a2ad4e_u64, 0xf1a6f2bab92a27e2_u64)
      put(cache, 0xf5b5d7ec8acb58a2_u64, 0xae10af696774b1db_u64)
      put(cache, 0x9991a6f3d6bf1765_u64, 0xacca6da1e0a8ef29_u64)
      put(cache, 0xbff610b0cc6edd3f_u64, 0x17fd090a58d32af3_u64)
      put(cache, 0xeff394dcff8a948e_u64, 0xddfc4b4cef07f5b0_u64)
      put(cache, 0x95f83d0a1fb69cd9_u64, 0x4abdaf101564f98e_u64)
      put(cache, 0xbb764c4ca7a4440f_u64, 0x9d6d1ad41abe37f1_u64)
      put(cache, 0xea53df5fd18d5513_u64, 0x84c86189216dc5ed_u64)
      put(cache, 0x92746b9be2f8552c_u64, 0x32fd3cf5b4e49bb4_u64)
      put(cache, 0xb7118682dbb66a77_u64, 0x3fbc8c33221dc2a1_u64)
      put(cache, 0xe4d5e82392a40515_u64, 0x0fabaf3feaa5334a_u64)
      put(cache, 0x8f05b1163ba6832d_u64, 0x29cb4d87f2a7400e_u64)
      put(cache, 0xb2c71d5bca9023f8_u64, 0x743e20e9ef511012_u64)
      put(cache, 0xdf78e4b2bd342cf6_u64, 0x914da9246b255416_u64)
      put(cache, 0x8bab8eefb6409c1a_u64, 0x1ad089b6c2f7548e_u64)
      put(cache, 0xae9672aba3d0c320_u64, 0xa184ac2473b529b1_u64)
      put(cache, 0xda3c0f568cc4f3e8_u64, 0xc9e5d72d90a2741e_u64)
      put(cache, 0x8865899617fb1871_u64, 0x7e2fa67c7a658892_u64)
      put(cache, 0xaa7eebfb9df9de8d_u64, 0xddbb901b98feeab7_u64)
      put(cache, 0xd51ea6fa85785631_u64, 0x552a74227f3ea565_u64)
      put(cache, 0x8533285c936b35de_u64, 0xd53a88958f87275f_u64)
      put(cache, 0xa67ff273b8460356_u64, 0x8a892abaf368f137_u64)
      put(cache, 0xd01fef10a657842c_u64, 0x2d2b7569b0432d85_u64)
      put(cache, 0x8213f56a67f6b29b_u64, 0x9c3b29620e29fc73_u64)
      put(cache, 0xa298f2c501f45f42_u64, 0x8349f3ba91b47b8f_u64)
      put(cache, 0xcb3f2f7642717713_u64, 0x241c70a936219a73_u64)
      put(cache, 0xfe0efb53d30dd4d7_u64, 0xed238cd383aa0110_u64)
      put(cache, 0x9ec95d1463e8a506_u64, 0xf4363804324a40aa_u64)
      put(cache, 0xc67bb4597ce2ce48_u64, 0xb143c6053edcd0d5_u64)
      put(cache, 0xf81aa16fdc1b81da_u64, 0xdd94b7868e94050a_u64)
      put(cache, 0x9b10a4e5e9913128_u64, 0xca7cf2b4191c8326_u64)
      put(cache, 0xc1d4ce1f63f57d72_u64, 0xfd1c2f611f63a3f0_u64)
      put(cache, 0xf24a01a73cf2dccf_u64, 0xbc633b39673c8cec_u64)
      put(cache, 0x976e41088617ca01_u64, 0xd5be0503e085d813_u64)
      put(cache, 0xbd49d14aa79dbc82_u64, 0x4b2d8644d8a74e18_u64)
      put(cache, 0xec9c459d51852ba2_u64, 0xddf8e7d60ed1219e_u64)
      put(cache, 0x93e1ab8252f33b45_u64, 0xcabb90e5c942b503_u64)
      put(cache, 0xb8da1662e7b00a17_u64, 0x3d6a751f3b936243_u64)
      put(cache, 0xe7109bfba19c0c9d_u64, 0x0cc512670a783ad4_u64)
      put(cache, 0x906a617d450187e2_u64, 0x27fb2b80668b24c5_u64)
      put(cache, 0xb484f9dc9641e9da_u64, 0xb1f9f660802dedf6_u64)
      put(cache, 0xe1a63853bbd26451_u64, 0x5e7873f8a0396973_u64)
      put(cache, 0x8d07e33455637eb2_u64, 0xdb0b487b6423e1e8_u64)
      put(cache, 0xb049dc016abc5e5f_u64, 0x91ce1a9a3d2cda62_u64)
      put(cache, 0xdc5c5301c56b75f7_u64, 0x7641a140cc7810fb_u64)
      put(cache, 0x89b9b3e11b6329ba_u64, 0xa9e904c87fcb0a9d_u64)
      put(cache, 0xac2820d9623bf429_u64, 0x546345fa9fbdcd44_u64)
      put(cache, 0xd732290fbacaf133_u64, 0xa97c177947ad4095_u64)
      put(cache, 0x867f59a9d4bed6c0_u64, 0x49ed8eabcccc485d_u64)
      put(cache, 0xa81f301449ee8c70_u64, 0x5c68f256bfff5a74_u64)
      put(cache, 0xd226fc195c6a2f8c_u64, 0x73832eec6fff3111_u64)
      put(cache, 0x83585d8fd9c25db7_u64, 0xc831fd53c5ff7eab_u64)
      put(cache, 0xa42e74f3d032f525_u64, 0xba3e7ca8b77f5e55_u64)
      put(cache, 0xcd3a1230c43fb26f_u64, 0x28ce1bd2e55f35eb_u64)
      put(cache, 0x80444b5e7aa7cf85_u64, 0x7980d163cf5b81b3_u64)
      put(cache, 0xa0555e361951c366_u64, 0xd7e105bcc332621f_u64)
      put(cache, 0xc86ab5c39fa63440_u64, 0x8dd9472bf3fefaa7_u64)
      put(cache, 0xfa856334878fc150_u64, 0xb14f98f6f0feb951_u64)
      put(cache, 0x9c935e00d4b9d8d2_u64, 0x6ed1bf9a569f33d3_u64)
      put(cache, 0xc3b8358109e84f07_u64, 0x0a862f80ec4700c8_u64)
      put(cache, 0xf4a642e14c6262c8_u64, 0xcd27bb612758c0fa_u64)
      put(cache, 0x98e7e9cccfbd7dbd_u64, 0x8038d51cb897789c_u64)
      put(cache, 0xbf21e44003acdd2c_u64, 0xe0470a63e6bd56c3_u64)
      put(cache, 0xeeea5d5004981478_u64, 0x1858ccfce06cac74_u64)
      put(cache, 0x95527a5202df0ccb_u64, 0x0f37801e0c43ebc8_u64)
      put(cache, 0xbaa718e68396cffd_u64, 0xd30560258f54e6ba_u64)
      put(cache, 0xe950df20247c83fd_u64, 0x47c6b82ef32a2069_u64)
      put(cache, 0x91d28b7416cdd27e_u64, 0x4cdc331d57fa5441_u64)
      put(cache, 0xb6472e511c81471d_u64, 0xe0133fe4adf8e952_u64)
      put(cache, 0xe3d8f9e563a198e5_u64, 0x58180fddd97723a6_u64)
      put(cache, 0x8e679c2f5e44ff8f_u64, 0x570f09eaa7ea7648_u64)
      put(cache, 0xb201833b35d63f73_u64, 0x2cd2cc6551e513da_u64)
      put(cache, 0xde81e40a034bcf4f_u64, 0xf8077f7ea65e58d1_u64)
      put(cache, 0x8b112e86420f6191_u64, 0xfb04afaf27faf782_u64)
      put(cache, 0xadd57a27d29339f6_u64, 0x79c5db9af1f9b563_u64)
      put(cache, 0xd94ad8b1c7380874_u64, 0x18375281ae7822bc_u64)
      put(cache, 0x87cec76f1c830548_u64, 0x8f2293910d0b15b5_u64)
      put(cache, 0xa9c2794ae3a3c69a_u64, 0xb2eb3875504ddb22_u64)
      put(cache, 0xd433179d9c8cb841_u64, 0x5fa60692a46151eb_u64)
      put(cache, 0x849feec281d7f328_u64, 0xdbc7c41ba6bcd333_u64)
      put(cache, 0xa5c7ea73224deff3_u64, 0x12b9b522906c0800_u64)
      put(cache, 0xcf39e50feae16bef_u64, 0xd768226b34870a00_u64)
      put(cache, 0x81842f29f2cce375_u64, 0xe6a1158300d46640_u64)
      put(cache, 0xa1e53af46f801c53_u64, 0x60495ae3c1097fd0_u64)
      put(cache, 0xca5e89b18b602368_u64, 0x385bb19cb14bdfc4_u64)
      put(cache, 0xfcf62c1dee382c42_u64, 0x46729e03dd9ed7b5_u64)
      put(cache, 0x9e19db92b4e31ba9_u64, 0x6c07a2c26a8346d1_u64)
      put(cache, 0xc5a05277621be293_u64, 0xc7098b7305241885_u64)
      put(cache, 0xf70867153aa2db38_u64, 0xb8cbee4fc66d1ea7_u64)
      cache
    end
  end

  # :nodoc:
  module Impl(F, ImplInfo)
    def self.break_rounding_tie(significand)
      significand % 2 == 0 ? significand : significand - 1
    end

    def self.compute_nearest_normal(two_fc, exponent, is_closed)
      # Step 1: Schubfach multiplier calculation

      # Compute k and beta.
      minus_k = Log.floor_log10_pow2(exponent) - ImplInfo::KAPPA
      cache = ImplInfo.get_cache(-minus_k)
      beta_minus_1 = exponent + Log.floor_log2_pow10(-minus_k)

      # Compute zi and deltai.
      # 10^kappa <= deltai < 10^(kappa + 1)
      deltai = compute_delta(cache, beta_minus_1)
      two_fr = two_fc | 1
      zi = compute_mul(two_fr << beta_minus_1, cache)

      # Step 2: Try larger divisor
      big_divisor = ImplInfo::BIG_DIVISOR
      small_divisor = ImplInfo::SMALL_DIVISOR

      significand = zi // big_divisor
      r = (zi - significand * big_divisor).to_u32!

      case r
      when .>(deltai)
        # do nothing
      when .<(deltai)
        # Exclude the right endpoint if necessary.
        if r == 0 && !is_closed && is_product_integer_pm_half?(two_fr, exponent, minus_k)
          significand -= 1
          r = big_divisor
        else
          ret_exponent = minus_k + ImplInfo::KAPPA + 1
          return {significand, ret_exponent}
        end
      else
        # r == deltai; compare fractional parts.
        # Check conditions in the order different from the paper
        # to take advantage of short-circuiting.
        two_fl = two_fc - 1
        unless (!is_closed || !is_product_integer_pm_half?(two_fl, exponent, minus_k)) && !compute_mul_parity(two_fl, cache, beta_minus_1)
          ret_exponent = minus_k + ImplInfo::KAPPA + 1
          return {significand, ret_exponent}
        end
      end

      # Step 3: Find the significand with the smaller divisor
      significand *= 10
      ret_exponent = minus_k + ImplInfo::KAPPA

      dist = r - deltai // 2 + small_divisor // 2
      approx_y_parity = ((dist ^ (small_divisor // 2)) & 1) != 0

      # Is dist divisible by 10^kappa?
      dist, divisible_by_10_to_the_kappa = ImplInfo.check_divisibility_and_divide_by_pow10(dist)

      # Add dist / 10^kappa to the significand.
      significand += dist

      if divisible_by_10_to_the_kappa
        # Check z^(f) >= epsilon^(f)
        # We have either yi == zi - epsiloni or yi == (zi - epsiloni) - 1,
        # where yi == zi - epsiloni if and only if z^(f) >= epsilon^(f)
        # Since there are only 2 possibilities, we only need to care about the parity.
        # Also, zi and r should have the same parity since the divisor
        # is an even number.
        if compute_mul_parity(two_fc, cache, beta_minus_1) != approx_y_parity
          significand -= 1
        elsif is_product_integer?(two_fc, exponent, minus_k)
          # If z^(f) >= epsilon^(f), we might have a tie
          # when z^(f) == epsilon^(f), or equivalently, when y is an integer.
          # For tie-to-up case, we can just choose the upper one.
          significand = break_rounding_tie(significand)
        end
      end

      {significand, ret_exponent}
    end

    def self.compute_nearest_shorter(exponent)
      # Compute k and beta.
      minus_k = Log.floor_log10_pow2_minus_log10_4_over_3(exponent)
      beta_minus_1 = exponent + Log.floor_log2_pow10(-minus_k)

      # Compute xi and zi.
      cache = ImplInfo.get_cache(-minus_k)

      xi = compute_left_endpoint_for_shorter_interval_case(cache, beta_minus_1)
      zi = compute_right_endpoint_for_shorter_interval_case(cache, beta_minus_1)

      # If we don't accept the left endpoint or
      # if the left endpoint is not an integer, increase it.
      xi += 1 if !is_left_endpoint_integer_shorter_interval?(exponent)

      # Try bigger divisor.
      significand = zi // 10

      # If succeed, return.
      if significand * 10 >= xi
        ret_exponent = minus_k + 1
        return {significand, ret_exponent}
      end

      # Otherwise, compute the round-up of y
      significand = compute_round_up_for_shorter_interval_case(cache, beta_minus_1)
      ret_exponent = minus_k

      # When tie occurs, choose one of them according to the rule.
      if ImplInfo::SHORTER_INTERVAL_TIE_LOWER_THRESHOLD <= exponent <= ImplInfo::SHORTER_INTERVAL_TIE_UPPER_THRESHOLD
        significand = break_rounding_tie(significand)
      elsif significand < xi
        significand += 1
      end

      {significand, ret_exponent}
    end

    def self.compute_mul(u, cache)
      {% if F == Float32 %}
        WUInt.umul96_upper32(u, cache)
      {% else %}
        # F == Float64
        WUInt.umul192_upper64(u, cache)
      {% end %}
    end

    def self.compute_delta(cache, beta_minus_1) : UInt32
      {% if F == Float32 %}
        (cache >> (ImplInfo::CACHE_BITS - 1 - beta_minus_1)).to_u32!
      {% else %}
        # F == Float64
        (cache.high >> (ImplInfo::CARRIER_BITS - 1 - beta_minus_1)).to_u32!
      {% end %}
    end

    def self.compute_mul_parity(two_f, cache, beta_minus_1) : Bool
      {% if F == Float32 %}
        ((WUInt.umul96_lower64(two_f, cache) >> (64 - beta_minus_1)) & 1) != 0
      {% else %}
        # F == Float64
        ((WUInt.umul192_middle64(two_f, cache) >> (64 - beta_minus_1)) & 1) != 0
      {% end %}
    end

    def self.compute_left_endpoint_for_shorter_interval_case(cache, beta_minus_1)
      significand_bits = ImplInfo::SIGNIFICAND_BITS

      ImplInfo::CarrierUInt.new!(
        {% if F == Float32 %}
          (cache - (cache >> (significand_bits + 2))) >> (ImplInfo::CACHE_BITS - significand_bits - 1 - beta_minus_1)
        {% else %}
          # F == Float64
          (cache.high - (cache.high >> (significand_bits + 2))) >> (ImplInfo::CARRIER_BITS - significand_bits - 1 - beta_minus_1)
        {% end %}
      )
    end

    def self.compute_right_endpoint_for_shorter_interval_case(cache, beta_minus_1)
      significand_bits = ImplInfo::SIGNIFICAND_BITS

      ImplInfo::CarrierUInt.new!(
        {% if F == Float32 %}
          (cache + (cache >> (significand_bits + 1))) >> (ImplInfo::CACHE_BITS - significand_bits - 1 - beta_minus_1)
        {% else %}
          # F == Float64
          (cache.high + (cache.high >> (significand_bits + 1))) >> (ImplInfo::CARRIER_BITS - significand_bits - 1 - beta_minus_1)
        {% end %}
      )
    end

    def self.compute_round_up_for_shorter_interval_case(cache, beta_minus_1)
      significand_bits = ImplInfo::SIGNIFICAND_BITS

      {% if F == Float32 %}
        (ImplInfo::CarrierUInt.new!(cache >> (ImplInfo::CACHE_BITS - significand_bits - 2 - beta_minus_1)) + 1) // 2
      {% else %}
        # F == Float64
        ((cache.high >> (ImplInfo::CARRIER_BITS - significand_bits - 2 - beta_minus_1)) + 1) // 2
      {% end %}
    end

    def self.is_left_endpoint_integer_shorter_interval?(exponent)
      ImplInfo::CASE_SHORTER_INTERVAL_LEFT_ENDPOINT_LOWER_THRESHOLD <=
        exponent <= ImplInfo::CASE_SHORTER_INTERVAL_LEFT_ENDPOINT_UPPER_THRESHOLD
    end

    def self.is_product_integer_pm_half?(two_f, exponent, minus_k)
      # Case I: f = fc +- 1/2

      return false if exponent < ImplInfo::CASE_FC_PM_HALF_LOWER_THRESHOLD
      # For k >= 0
      return true if exponent <= ImplInfo::CASE_FC_PM_HALF_UPPER_THRESHOLD
      # For k < 0
      return false if exponent > ImplInfo::DIVISIBILITY_CHECK_BY_5_THRESHOLD
      Div.divisible_by_power_of_5?(two_f, minus_k)
    end

    def self.is_product_integer?(two_f, exponent, minus_k)
      # Case II: f = fc + 1
      # Case III: f = fc

      # Exponent for 5 is negative
      return false if exponent > ImplInfo::DIVISIBILITY_CHECK_BY_5_THRESHOLD
      return Div.divisible_by_power_of_5?(two_f, minus_k) if exponent > ImplInfo::CASE_FC_UPPER_THRESHOLD
      # Both exponents are nonnegative
      return true if exponent >= ImplInfo::CASE_FC_LOWER_THRESHOLD
      # Exponent for 2 is negative
      Div.divisible_by_power_of_2?(two_f, minus_k - exponent + 1)
    end

    def self.to_decimal(signed_significand_bits, exponent_bits)
      two_fc = ImplInfo.remove_sign_bit_and_shift(signed_significand_bits)
      exponent = exponent_bits.to_i

      # Is the input a normal number?
      if exponent != 0
        exponent += ImplInfo::EXPONENT_BIAS - ImplInfo::SIGNIFICAND_BITS

        # Shorter interval case; proceed like Schubfach.
        # One might think this condition is wrong,
        # since when exponent_bits == 1 and two_fc == 0,
        # the interval is actullay regular.
        # However, it turns out that this seemingly wrong condition
        # is actually fine, because the end result is anyway the same.
        #
        # [binary32]
        # floor( (fc-1/2) * 2^e ) = 1.175'494'28... * 10^-38
        # floor( (fc-1/4) * 2^e ) = 1.175'494'31... * 10^-38
        # floor(    fc    * 2^e ) = 1.175'494'35... * 10^-38
        # floor( (fc+1/2) * 2^e ) = 1.175'494'42... * 10^-38
        #
        # Hence, shorter_interval_case will return 1.175'494'4 * 10^-38.
        # 1.175'494'3 * 10^-38 is also a correct shortest representation
        # that will be rejected if we assume shorter interval,
        # but 1.175'494'4 * 10^-38 is closer to the true value so it doesn't matter.
        #
        # [binary64]
        # floor( (fc-1/2) * 2^e ) = 2.225'073'858'507'201'13... * 10^-308
        # floor( (fc-1/4) * 2^e ) = 2.225'073'858'507'201'25... * 10^-308
        # floor(    fc    * 2^e ) = 2.225'073'858'507'201'38... * 10^-308
        # floor( (fc+1/2) * 2^e ) = 2.225'073'858'507'201'63... * 10^-308
        #
        # Hence, shorter_interval_case will return 2.225'073'858'507'201'4 * 10^-308.
        # This is indeed of the shortest length, and it is the unique one
        # closest to the true value among valid representations of the same length.
        return compute_nearest_shorter(exponent) if two_fc == 0

        two_fc |= two_fc.class.new(1) << (ImplInfo::SIGNIFICAND_BITS + 1)
      else # Is the input a subnormal number?
        exponent = ImplInfo::MIN_EXPONENT - ImplInfo::SIGNIFICAND_BITS
      end

      compute_nearest_normal(two_fc, exponent, signed_significand_bits % 2 == 0)
    end
  end

  {% for f, uint in {Float32 => UInt32, Float64 => UInt64} %}
    # Provides a decimal representation of *x*.
    #
    # Returns a `Tuple` of `{significand, decimal_exponent}` such that
    # `x == significand * 10.0 ** decimal_exponent`. This decimal representation
    # is the shortest possible while still maintaining the round-trip guarantee.
    # There may be trailing zeros in `significand`.
    def self.to_decimal(x : {{ f }}) : Tuple({{ uint }}, Int32)
      br = x.unsafe_as({{ uint }})
      exponent_bits = ImplInfo_{{ f }}.extract_exponent_bits(br)
      s = ImplInfo_{{ f }}.remove_exponent_bits(br, exponent_bits)
      Impl({{ f }}, ImplInfo_{{ f }}).to_decimal(s, exponent_bits)
    end
  {% end %}
end
