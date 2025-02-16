# Supported library versions:
#
# * libgmp
# * libmpir
#
# See https://crystal-lang.org/reference/man/required_libraries.html#big-numbers
{% if flag?(:win32) && !flag?(:gnu) %}
  @[Link("mpir")]
  {% if compare_versions(Crystal::VERSION, "1.11.0-dev") >= 0 %}
    @[Link(dll: "mpir.dll")]
  {% end %}
{% else %}
  @[Link("gmp")]
{% end %}
lib LibGMP
  alias Int = LibC::Int
  alias Long = LibC::Long
  alias ULong = LibC::ULong

  # MPIR uses its own `mpir_si` and `mpir_ui` typedefs in places where GMP uses
  # the LibC types, when the function name has `si` or `ui`; we follow this
  # distinction
  {% if flag?(:win32) && !flag?(:gnu) && flag?(:bits64) %}
    alias SI = LibC::LongLong
    alias UI = LibC::ULongLong
  {% else %}
    alias SI = LibC::Long
    alias UI = LibC::ULong
  {% end %}

  alias SizeT = LibC::SizeT
  alias Double = LibC::Double
  alias BitcntT = UI

  alias MpExp = LibC::Long

  {% if flag?(:win32) && !flag?(:gnu) %}
    alias MpSize = LibC::LongLong
  {% else %}
    alias MpSize = LibC::Long
  {% end %}

  # NOTE: this assumes GMP is configured by build time to define
  # `_LONG_LONG_LIMB=1` on Windows
  {% if flag?(:win32) %}
    alias MpLimb = LibC::ULongLong
  {% else %}
    alias MpLimb = LibC::ULong
  {% end %}

  struct MPZ
    _mp_alloc : Int
    _mp_size : Int
    _mp_d : MpLimb*
  end

  # # Initialization

  fun init = __gmpz_init(x : MPZ*)
  fun init2 = __gmpz_init2(x : MPZ*, bits : BitcntT)
  fun init_set_ui = __gmpz_init_set_ui(rop : MPZ*, op : UI)
  fun init_set_si = __gmpz_init_set_si(rop : MPZ*, op : SI)
  fun init_set_d = __gmpz_init_set_d(rop : MPZ*, op : Double)
  fun init_set_str = __gmpz_init_set_str(rop : MPZ*, str : UInt8*, base : Int) : Int

  # # I/O

  fun set_ui = __gmpz_set_ui(rop : MPZ*, op : UI)
  fun set_si = __gmpz_set_si(rop : MPZ*, op : SI)
  fun set_d = __gmpz_set_d(rop : MPZ*, op : Double)
  fun set_q = __gmpz_set_q(rop : MPZ*, op : MPQ*)
  fun set_f = __gmpz_set_f(rop : MPZ*, op : MPF*)
  fun set_str = __gmpz_set_str(rop : MPZ*, str : UInt8*, base : Int) : Int
  fun get_str = __gmpz_get_str(str : UInt8*, base : Int, op : MPZ*) : UInt8*
  fun get_si = __gmpz_get_si(op : MPZ*) : SI
  fun get_ui = __gmpz_get_ui(op : MPZ*) : UI
  fun get_d = __gmpz_get_d(op : MPZ*) : Double
  fun get_d_2exp = __gmpz_get_d_2exp(exp : Long*, op : MPZ*) : Double

  # # Arithmetic

  fun add = __gmpz_add(rop : MPZ*, op1 : MPZ*, op2 : MPZ*)
  fun add_ui = __gmpz_add_ui(rop : MPZ*, op1 : MPZ*, op2 : UI)

  fun sub = __gmpz_sub(rop : MPZ*, op1 : MPZ*, op2 : MPZ*)
  fun sub_ui = __gmpz_sub_ui(rop : MPZ*, op1 : MPZ*, op2 : UI)
  fun ui_sub = __gmpz_ui_sub(rop : MPZ*, op1 : UI, op2 : MPZ*)

  fun mul = __gmpz_mul(rop : MPZ*, op1 : MPZ*, op2 : MPZ*)
  fun mul_si = __gmpz_mul_si(rop : MPZ*, op1 : MPZ*, op2 : SI)
  fun mul_ui = __gmpz_mul_ui(rop : MPZ*, op1 : MPZ*, op2 : UI)

  fun fdiv_q = __gmpz_fdiv_q(rop : MPZ*, op1 : MPZ*, op2 : MPZ*)
  fun fdiv_q_ui = __gmpz_fdiv_q_ui(rop : MPZ*, op1 : MPZ*, op2 : UI)

  fun tdiv_q = __gmpz_tdiv_q(rop : MPZ*, op1 : MPZ*, op2 : MPZ*)
  fun tdiv_q_ui = __gmpz_tdiv_q_ui(rop : MPZ*, op1 : MPZ*, op2 : UI)

  fun fdiv_r = __gmpz_fdiv_r(rop : MPZ*, op1 : MPZ*, op2 : MPZ*)
  fun fdiv_r_ui = __gmpz_fdiv_r_ui(rop : MPZ*, op1 : MPZ*, op2 : UI)

  fun fdiv_qr = __gmpz_fdiv_qr(q : MPZ*, r : MPZ*, n : MPZ*, d : MPZ*)
  fun fdiv_qr_ui = __gmpz_fdiv_qr_ui(q : MPZ*, r : MPZ*, n : MPZ*, d : UI) : UI

  fun tdiv_r = __gmpz_tdiv_r(rop : MPZ*, op1 : MPZ*, op2 : MPZ*)
  fun tdiv_r_ui = __gmpz_tdiv_r_ui(rop : MPZ*, op1 : MPZ*, op2 : UI)
  fun tdiv_ui = __gmpz_tdiv_ui(op1 : MPZ*, op2 : UI) : UI

  fun tdiv_qr = __gmpz_tdiv_qr(q : MPZ*, r : MPZ*, n : MPZ*, d : MPZ*)
  fun tdiv_qr_ui = __gmpz_tdiv_qr_ui(q : MPZ*, r : MPZ*, n : MPZ*, d : UI) : UI

  fun divisible_p = __gmpz_divisible_p(n : MPZ*, d : MPZ*) : Int
  fun divisible_ui_p = __gmpz_divisible_ui_p(n : MPZ*, d : UI) : Int

  fun neg = __gmpz_neg(rop : MPZ*, op : MPZ*)
  fun abs = __gmpz_abs(rop : MPZ*, op : MPZ*)

  fun pow_ui = __gmpz_pow_ui(rop : MPZ*, base : MPZ*, exp : UI)
  fun fac_ui = __gmpz_fac_ui(rop : MPZ*, n : UI)

  fun sqrt = __gmpz_sqrt(rop : MPZ*, op : MPZ*)

  fun invert = __gmpz_invert(rop : MPZ*, op1 : MPZ*, op2 : MPZ*)

  # # Bitwise operations

  fun and = __gmpz_and(rop : MPZ*, op1 : MPZ*, op2 : MPZ*)
  fun ior = __gmpz_ior(rop : MPZ*, op1 : MPZ*, op2 : MPZ*)
  fun xor = __gmpz_xor(rop : MPZ*, op1 : MPZ*, op2 : MPZ*)
  fun com = __gmpz_com(rop : MPZ*, op : MPZ*)

  fun tstbit = __gmpz_tstbit(op : MPZ*, bit_index : BitcntT) : Int

  fun fdiv_q_2exp = __gmpz_fdiv_q_2exp(q : MPZ*, n : MPZ*, b : BitcntT)
  fun mul_2exp = __gmpz_mul_2exp(rop : MPZ*, op1 : MPZ*, op2 : BitcntT)

  # # Logic

  fun popcount = __gmpz_popcount(op : MPZ*) : BitcntT
  fun scan0 = __gmpz_scan0(op : MPZ*, starting_bit : BitcntT) : BitcntT
  fun scan1 = __gmpz_scan1(op : MPZ*, starting_bit : BitcntT) : BitcntT
  fun sizeinbase = __gmpz_sizeinbase(op : MPZ*, base : Int) : SizeT

  # # Comparison

  fun cmp = __gmpz_cmp(op1 : MPZ*, op2 : MPZ*) : Int
  fun cmp_si = __gmpz_cmp_si(op1 : MPZ*, op2 : SI) : Int
  fun cmp_ui = __gmpz_cmp_ui(op1 : MPZ*, op2 : UI) : Int
  fun cmp_d = __gmpz_cmp_d(op1 : MPZ*, op2 : Double) : Int

  # # Number Theoretic Functions

  fun gcd = __gmpz_gcd(rop : MPZ*, op1 : MPZ*, op2 : MPZ*)
  fun gcd_ui = __gmpz_gcd_ui(rop : MPZ*, op1 : MPZ*, op2 : UI) : UI
  fun lcm = __gmpz_lcm(rop : MPZ*, op1 : MPZ*, op2 : MPZ*)
  fun lcm_ui = __gmpz_lcm_ui(rop : MPZ*, op1 : MPZ*, op2 : UI)
  fun invert = __gmpz_invert(rop : MPZ*, op1 : MPZ*, op2 : MPZ*) : Int
  fun remove = __gmpz_remove(rop : MPZ*, op : MPZ*, f : MPZ*) : BitcntT

  # # Miscellaneous Functions

  {% if flag?(:win32) && !flag?(:gnu) %}
    fun fits_ui_p = __gmpz_fits_ui_p(op : MPZ*) : Int
    fun fits_si_p = __gmpz_fits_si_p(op : MPZ*) : Int
  {% else %}
    fun fits_ulong_p = __gmpz_fits_ulong_p(op : MPZ*) : Int
    fun fits_slong_p = __gmpz_fits_slong_p(op : MPZ*) : Int
  {% end %}

  # # Special Functions

  fun size = __gmpz_size(op : MPZ*) : SizeT
  fun limbs_read = __gmpz_limbs_read(x : MPZ*) : MpLimb*
  fun limbs_write = __gmpz_limbs_write(x : MPZ*, n : MpSize) : MpLimb*
  fun limbs_finish = __gmpz_limbs_finish(x : MPZ*, s : MpSize)

  # MPQ
  struct MPQ
    _mp_num : MPZ
    _mp_den : MPZ
  end

  # # Initialization
  fun mpq_init = __gmpq_init(x : MPQ*)
  fun mpq_set_num = __gmpq_set_num(x : MPQ*, num : MPZ*)
  fun mpq_set_den = __gmpq_set_den(x : MPQ*, den : MPZ*)
  fun mpq_get_num = __gmpq_get_num(rop : MPZ*, op : MPQ*)
  fun mpq_get_den = __gmpq_get_den(rop : MPZ*, op : MPQ*)
  fun mpq_canonicalize = __gmpq_canonicalize(x : MPQ*)

  # # Conversion
  fun mpq_get_str = __gmpq_get_str(str : UInt8*, base : Int, op : MPQ*) : UInt8*
  fun mpq_get_d = __gmpq_get_d(op : MPQ*) : Double
  fun mpq_set_d = __gmpq_set_d(rop : MPQ*, op : Double)
  fun mpq_set_f = __gmpq_set_f(rop : MPQ*, op : MPF*)

  # # Arithmetic
  fun mpq_add = __gmpq_add(rop : MPQ*, op1 : MPQ*, op2 : MPQ*)
  fun mpq_sub = __gmpq_sub(rop : MPQ*, op1 : MPQ*, op2 : MPQ*)
  fun mpq_mul = __gmpq_mul(rop : MPQ*, op1 : MPQ*, op2 : MPQ*)
  fun mpq_div = __gmpq_div(rop : MPQ*, op1 : MPQ*, op2 : MPQ*)
  fun mpq_inv = __gmpq_inv(rop : MPQ*, op1 : MPQ*)
  fun mpq_neg = __gmpq_neg(rop : MPQ*, op1 : MPQ*)
  fun mpq_abs = __gmpq_abs(rop : MPQ*, op1 : MPQ*)

  fun mpq_div_2exp = __gmpq_div_2exp(q : MPQ*, n : MPQ*, b : BitcntT)
  fun mpq_mul_2exp = __gmpq_mul_2exp(rop : MPQ*, op1 : MPQ*, op2 : BitcntT)

  # # Compare
  fun mpq_cmp = __gmpq_cmp(op1 : MPQ*, op2 : MPQ*) : Int
  fun mpq_cmp_z = __gmpq_cmp_z(op1 : MPQ*, op2 : MPZ*) : Int
  fun mpq_cmp_ui = __gmpq_cmp_ui(op1 : MPQ*, num2 : UI, den2 : UI) : Int
  fun mpq_cmp_si = __gmpq_cmp_si(op1 : MPQ*, num2 : SI, den2 : SI) : Int
  fun mpq_equal = __gmpq_equal(op1 : MPQ*, op2 : MPQ*) : Int

  # MPF
  struct MPF
    _mp_prec : Int
    _mp_size : Int
    _mp_exp : MpExp
    _mp_d : MpLimb*
  end

  # # Initialization
  fun mpf_init = __gmpf_init(x : MPF*)
  fun mpf_init2 = __gmpf_init2(x : MPF*, prec : BitcntT)
  fun mpf_init_set_d = __gmpf_init_set_d(rop : MPF*, op : Double)
  fun mpf_init_set_str = __gmpf_init_set_str(rop : MPF*, str : UInt8*, base : Int) : Int
  fun mpf_init_set_ui = __gmpf_init_set_ui(rop : MPF*, op : UI)
  fun mpf_init_set_si = __gmpf_init_set_si(rop : MPF*, op : SI)

  # # Precision
  fun mpf_set_default_prec = __gmpf_set_default_prec(prec : BitcntT)
  fun mpf_get_default_prec = __gmpf_get_default_prec : BitcntT
  fun mpf_get_prec = __gmpf_get_prec(op : MPF*) : BitcntT

  # # Conversion
  fun mpf_get_str = __gmpf_get_str(str : UInt8*, expptr : MpExp*, base : Int, n_digits : LibC::SizeT, op : MPF*) : UInt8*
  fun mpf_get_d = __gmpf_get_d(op : MPF*) : Double
  fun mpf_set_d = __gmpf_set_d(rop : MPF*, op : Double)
  fun mpf_set = __gmpf_set(rop : MPF*, op : MPF*)
  fun mpf_set_z = __gmpf_set_z(rop : MPF*, op : MPZ*)
  fun mpf_set_q = __gmpf_set_q(rop : MPF*, op : MPQ*)
  fun mpf_get_si = __gmpf_get_si(op : MPF*) : SI
  fun mpf_get_ui = __gmpf_get_ui(op : MPF*) : UI
  fun mpf_get_d_2exp = __gmpf_get_d_2exp(exp : Long*, op : MPF*) : Double

  # # Arithmetic
  fun mpf_add = __gmpf_add(rop : MPF*, op1 : MPF*, op2 : MPF*)
  fun mpf_add_ui = __gmpf_add_ui(rop : MPF*, op1 : MPF*, op2 : UI)
  fun mpf_sub = __gmpf_sub(rop : MPF*, op1 : MPF*, op2 : MPF*)
  fun mpf_sub_ui = __gmpf_sub_ui(rop : MPF*, op1 : MPF*, op2 : UI)
  fun mpf_mul = __gmpf_mul(rop : MPF*, op1 : MPF*, op2 : MPF*)
  fun mpf_mul_ui = __gmpf_mul_ui(rop : MPF*, op1 : MPF*, op2 : UI)
  fun mpf_div = __gmpf_div(rop : MPF*, op1 : MPF*, op2 : MPF*)
  fun mpf_div_ui = __gmpf_div_ui(rop : MPF*, op1 : MPF*, op2 : UI)
  fun mpf_ui_div = __gmpf_ui_div(rop : MPF*, op1 : UI, op2 : MPF*)
  fun mpf_neg = __gmpf_neg(rop : MPF*, op : MPF*)
  fun mpf_abs = __gmpf_abs(rop : MPF*, op : MPF*)
  fun mpf_sqrt = __gmpf_sqrt(rop : MPF*, op : MPF*)
  fun mpf_pow_ui = __gmpf_pow_ui(rop : MPF*, op1 : MPF*, op2 : SI)
  fun mpf_mul_2exp = __gmpf_mul_2exp(rop : MPF*, op1 : MPF*, op2 : BitcntT)
  fun mpf_div_2exp = __gmpf_div_2exp(rop : MPF*, op1 : MPF*, op2 : BitcntT)

  # # Comparison
  fun mpf_cmp = __gmpf_cmp(op1 : MPF*, op2 : MPF*) : Int
  fun mpf_cmp_d = __gmpf_cmp_d(op1 : MPF*, op2 : Double) : Int
  fun mpf_cmp_ui = __gmpf_cmp_ui(op1 : MPF*, op2 : UI) : Int
  fun mpf_cmp_si = __gmpf_cmp_si(op1 : MPF*, op2 : SI) : Int
  fun mpf_cmp_z = __gmpf_cmp_z(op1 : MPF*, op2 : MPZ*) : Int

  # # Miscellaneous
  fun mpf_ceil = __gmpf_ceil(rop : MPF*, op : MPF*)
  fun mpf_floor = __gmpf_floor(rop : MPF*, op : MPF*)
  fun mpf_trunc = __gmpf_trunc(rop : MPF*, op : MPF*)
  fun mpf_integer_p = __gmpf_integer_p(op : MPF*) : Int

  # # Memory

  fun set_memory_functions = __gmp_set_memory_functions(malloc : SizeT -> Void*, realloc : Void*, SizeT, SizeT -> Void*, free : Void*, SizeT ->)
end

LibGMP.set_memory_functions(
  ->(size) { GC.malloc(size) },
  ->(ptr, old_size, new_size) { GC.realloc(ptr, new_size) },
  ->(ptr, size) { GC.free(ptr) }
)
