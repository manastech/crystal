# Supported library versions:
#
# * libpcre2 (recommended: 10.36+)
#
# See https://crystal-lang.org/reference/man/required_libraries.html#regular-expression-engine
@[Link("pcre2-8", pkg_config: "libpcre2-8")]
{% if compare_versions(Crystal::VERSION, "1.11.0-dev") >= 0 %}
  @[Link(dll: "pcre2-8.dll")]
{% end %}
lib LibPCRE2
  alias Int = LibC::Int

  UNSET = ~LibC::SizeT.new(0)

  # The following option bits can be passed to pcre2_compile(), pcre2_match(),
  # or pcre2_dfa_match(). PCRE2_NO_UTF_CHECK affects only the function to which it
  # is passed. Put these bits at the most significant end of the options word so
  # others can be added next to them

  ANCHORED     = 0x80000000_u32
  NO_UTF_CHECK = 0x40000000_u32
  ENDANCHORED  = 0x20000000_u32

  # The following option bits can be passed only to pcre2_compile(). However,
  # they may affect compilation, JIT compilation, and/or interpretive execution.
  # The following tags indicate which:

  # C   alters what is compiled by pcre2_compile()
  # J   alters what is compiled by pcre2_jit_compile()
  # M   is inspected during pcre2_match() execution
  # D   is inspected during pcre2_dfa_match() execution

  ALLOW_EMPTY_CLASS   = 0x00000001_u32 # C
  ALT_BSUX            = 0x00000002_u32 # C
  AUTO_CALLOUT        = 0x00000004_u32 # C
  CASELESS            = 0x00000008_u32 # C
  DOLLAR_ENDONLY      = 0x00000010_u32 #   J M D
  DOTALL              = 0x00000020_u32 # C
  DUPNAMES            = 0x00000040_u32 # C
  EXTENDED            = 0x00000080_u32 # C
  FIRSTLINE           = 0x00000100_u32 #   J M D
  MATCH_UNSET_BACKREF = 0x00000200_u32 # C J M
  MULTILINE           = 0x00000400_u32 # C
  NEVER_UCP           = 0x00000800_u32 # C
  NEVER_UTF           = 0x00001000_u32 # C
  NO_AUTO_CAPTURE     = 0x00002000_u32 # C
  NO_AUTO_POSSESS     = 0x00004000_u32 # C
  NO_DOTSTAR_ANCHOR   = 0x00008000_u32 # C
  NO_START_OPTIMIZE   = 0x00010000_u32 #   J M D
  UCP                 = 0x00020000_u32 # C J M D
  UNGREEDY            = 0x00040000_u32 # C
  UTF                 = 0x00080000_u32 # C J M D
  NEVER_BACKSLASH_C   = 0x00100000_u32 # C
  ALT_CIRCUMFLEX      = 0x00200000_u32 #   J M D
  ALT_VERBNAMES       = 0x00400000_u32 # C
  USE_OFFSET_LIMIT    = 0x00800000_u32 #   J M D
  EXTENDED_MORE       = 0x01000000_u32 # C
  LITERAL             = 0x02000000_u32 # C
  MATCH_INVALID_UTF   = 0x04000000_u32 #   J M D

  # An additional compile options word is available in the compile context.

  EXTRA_ALLOW_SURROGATE_ESCAPES = 0x00000001_u32 # C
  EXTRA_BAD_ESCAPE_IS_LITERAL   = 0x00000002_u32 # C
  EXTRA_MATCH_WORD              = 0x00000004_u32 # C
  EXTRA_MATCH_LINE              = 0x00000008_u32 # C
  EXTRA_ESCAPED_CR_IS_LF        = 0x00000010_u32 # C
  EXTRA_ALT_BSUX                = 0x00000020_u32 # C
  EXTRA_ALLOW_LOOKAROUND_BSK    = 0x00000040_u32 # C
  EXTRA_CASELESS_RESTRICT       = 0x00000080_u32 # C
  EXTRA_ASCII_BSD               = 0x00000100_u32 # C
  EXTRA_ASCII_BSS               = 0x00000200_u32 # C
  EXTRA_ASCII_BSW               = 0x00000400_u32 # C
  EXTRA_ASCII_POSIX             = 0x00000800_u32 # C

  # These are for pcre2_jit_compile().

  JIT_COMPLETE     = 0x00000001_u32 # For full matching
  JIT_PARTIAL_SOFT = 0x00000002_u32
  JIT_PARTIAL_HARD = 0x00000004_u32
  JIT_INVALID_UTF  = 0x00000100_u32

  # These are for pcre2_match(), pcre2_dfa_match(), pcre2_jit_match(), and
  # pcre2_substitute(). Some are allowed only for one of the functions, and in
  # these cases it is noted below. Note that PCRE2_ANCHORED, PCRE2_ENDANCHORED and
  # PCRE2_NO_UTF_CHECK can also be passed to these functions (though
  # pcre2_jit_match() ignores the latter since it bypasses all sanity checks).

  NOTBOL                      = 0x00000001_u32
  NOTEOL                      = 0x00000002_u32
  NOTEMPTY                    = 0x00000004_u32 # ) These two must be kept
  NOTEMPTY_ATSTART            = 0x00000008_u32 # ) adjacent to each other.
  PARTIAL_SOFT                = 0x00000010_u32
  PARTIAL_HARD                = 0x00000020_u32
  DFA_RESTART                 = 0x00000040_u32 # pcre2_dfa_match() only
  DFA_SHORTEST                = 0x00000080_u32 # pcre2_dfa_match() only
  SUBSTITUTE_GLOBAL           = 0x00000100_u32 # pcre2_substitute() only
  SUBSTITUTE_EXTENDED         = 0x00000200_u32 # pcre2_substitute() only
  SUBSTITUTE_UNSET_EMPTY      = 0x00000400_u32 # pcre2_substitute() only
  SUBSTITUTE_UNKNOWN_UNSET    = 0x00000800_u32 # pcre2_substitute() only
  SUBSTITUTE_OVERFLOW_LENGTH  = 0x00001000_u32 # pcre2_substitute() only
  NO_JIT                      = 0x00002000_u32 # Not for pcre2_dfa_match()
  COPY_MATCHED_SUBJECT        = 0x00004000_u32
  SUBSTITUTE_LITERAL          = 0x00008000_u32 # pcre2_substitute() only
  SUBSTITUTE_MATCHED          = 0x00010000_u32 # pcre2_substitute() only
  SUBSTITUTE_REPLACEMENT_ONLY = 0x00020000_u32 # pcre2_substitute() only

  enum Error
    #  "Expected" matching error codes: no match and partial match.

    NOMATCH = -1
    PARTIAL = -2

    #  Error codes for UTF-8 validity checks

    UTF8_ERR1  =  -3
    UTF8_ERR2  =  -4
    UTF8_ERR3  =  -5
    UTF8_ERR4  =  -6
    UTF8_ERR5  =  -7
    UTF8_ERR6  =  -8
    UTF8_ERR7  =  -9
    UTF8_ERR8  = -10
    UTF8_ERR9  = -11
    UTF8_ERR10 = -12
    UTF8_ERR11 = -13
    UTF8_ERR12 = -14
    UTF8_ERR13 = -15
    UTF8_ERR14 = -16
    UTF8_ERR15 = -17
    UTF8_ERR16 = -18
    UTF8_ERR17 = -19
    UTF8_ERR18 = -20
    UTF8_ERR19 = -21
    UTF8_ERR20 = -22
    UTF8_ERR21 = -23

    #  Error codes for UTF-16 validity checks

    UTF16_ERR1 = -24
    UTF16_ERR2 = -25
    UTF16_ERR3 = -26

    #  Error codes for UTF-32 validity checks

    UTF32_ERR1 = -27
    UTF32_ERR2 = -28

    # Miscellaneous error codes for pcre2[_dfa]_match(), substring extraction
    # functions, context functions, and serializing functions. They are in numerical
    # order. Originally they were in alphabetical order too, but now that PCRE2 is
    # released, the numbers must not be changed.

    BADDATA           = -29
    MIXEDTABLES       = -30 # Name was changed
    BADMAGIC          = -31
    BADMODE           = -32
    BADOFFSET         = -33
    BADOPTION         = -34
    BADREPLACEMENT    = -35
    BADUTFOFFSET      = -36
    CALLOUT           = -37 # Never used by PCRE2 itself
    DFA_BADRESTART    = -38
    DFA_RECURSE       = -39
    DFA_UCOND         = -40
    DFA_UFUNC         = -41
    DFA_UITEM         = -42
    DFA_WSSIZE        = -43
    INTERNAL          = -44
    JIT_BADOPTION     = -45
    JIT_STACKLIMIT    = -46
    MATCHLIMIT        = -47
    NOMEMORY          = -48
    NOSUBSTRING       = -49
    NOUNIQUESUBSTRING = -50
    NULL              = -51
    RECURSELOOP       = -52
    DEPTHLIMIT        = -53
    RECURSIONLIMIT    = -53 # Obsolete synonym
    UNAVAILABLE       = -54
    UNSET             = -55
    BADOFFSETLIMIT    = -56
    BADREPESCAPE      = -57
    REPMISSINGBRACE   = -58
    BADSUBSTITUTION   = -59
    BADSUBSPATTERN    = -60
    TOOMANYREPLACE    = -61
    BADSERIALIZEDDATA = -62
    HEAPLIMIT         = -63
    CONVERT_SYNTAX    = -64
    INTERNAL_DUPMATCH = -65
    DFA_UINVALID_UTF  = -66

    def utf8_validity?
      in?(UTF8_ERR21..UTF8_ERR1)
    end
  end

  INFO_ALLOPTIONS     =  0
  INFO_ARGOPTIONS     =  1
  INFO_BACKREFMAX     =  2
  INFO_BSR            =  3
  INFO_CAPTURECOUNT   =  4
  INFO_FIRSTCODEUNIT  =  5
  INFO_FIRSTCODETYPE  =  6
  INFO_FIRSTBITMAP    =  7
  INFO_HASCRORLF      =  8
  INFO_JCHANGED       =  9
  INFO_JITSIZE        = 10
  INFO_LASTCODEUNIT   = 11
  INFO_LASTCODETYPE   = 12
  INFO_MATCHEMPTY     = 13
  INFO_MATCHLIMIT     = 14
  INFO_MAXLOOKBEHIND  = 15
  INFO_MINLENGTH      = 16
  INFO_NAMECOUNT      = 17
  INFO_NAMEENTRYSIZE  = 18
  INFO_NAMETABLE      = 19
  INFO_NEWLINE        = 20
  INFO_DEPTHLIMIT     = 21
  INFO_RECURSIONLIMIT = 21 # Obsolete synonym
  INFO_SIZE           = 22
  INFO_HASBACKSLASHC  = 23
  INFO_FRAMESIZE      = 24
  INFO_HEAPLIMIT      = 25
  INFO_EXTRAOPTIONS   = 26

  # Request types for pcre2_config().

  CONFIG_BSR               =  0
  CONFIG_JIT               =  1
  CONFIG_JITTARGET         =  2
  CONFIG_LINKSIZE          =  3
  CONFIG_MATCHLIMIT        =  4
  CONFIG_NEWLINE           =  5
  CONFIG_PARENSLIMIT       =  6
  CONFIG_DEPTHLIMIT        =  7
  CONFIG_RECURSIONLIMIT    =  7 # Obsolete synonym
  CONFIG_STACKRECURSE      =  8 # Obsolete
  CONFIG_UNICODE           =  9
  CONFIG_UNICODE_VERSION   = 10
  CONFIG_VERSION           = 11
  CONFIG_HEAPLIMIT         = 12
  CONFIG_NEVER_BACKSLASH_C = 13
  CONFIG_COMPILED_WIDTHS   = 14
  CONFIG_TABLES_LENGTH     = 15

  type Code = Void
  type CompileContext = Void
  type MatchData = Void
  type GeneralContext = Void

  fun get_error_message = pcre2_get_error_message_8(errorcode : Int, buffer : UInt8*, bufflen : LibC::SizeT) : Int

  fun compile = pcre2_compile_8(pattern : UInt8*, length : LibC::SizeT, options : UInt32, errorcode : Int*, erroroffset : LibC::SizeT*, ccontext : CompileContext*) : Code*
  fun code_free = pcre2_code_free_8(code : Code*) : Void

  type MatchContext = Void*
  fun match_context_create = pcre2_match_context_create_8(gcontext : Void*) : MatchContext*

  fun jit_compile = pcre2_jit_compile_8(code : Code*, options : UInt32) : Int

  type JITStack = Void

  fun jit_stack_create = pcre2_jit_stack_create_8(startsize : LibC::SizeT, maxsize : LibC::SizeT, gcontext : GeneralContext*) : JITStack*
  fun jit_stack_assign = pcre2_jit_stack_assign_8(mcontext : MatchContext*, callable_function : Void* -> JITStack*, callable_data : Void*) : Void
  fun jit_stack_free = pcre2_jit_stack_free_8(JITStack*) : Void

  fun pattern_info = pcre2_pattern_info_8(code : Code*, what : UInt32, where : Void*) : Int

  fun match = pcre2_match_8(code : Code*, subject : UInt8*, length : LibC::SizeT, startoffset : LibC::SizeT, options : UInt32, match_data : MatchData*, mcontext : MatchContext*) : Int
  fun match_data_create = pcre2_match_data_create_8(ovecsize : UInt32, gcontext : GeneralContext*) : MatchData*
  fun match_data_create_from_pattern = pcre2_match_data_create_from_pattern_8(code : Code*, gcontext : GeneralContext*) : MatchData*
  fun match_data_free = pcre2_match_data_free_8(match_data : MatchData*) : Void

  fun substring_nametable_scan = pcre2_substring_nametable_scan_8(code : Code*, name : UInt8*, first : UInt8*, last : UInt8*) : Int

  fun get_ovector_pointer = pcre2_get_ovector_pointer_8(match_data : MatchData*) : LibC::SizeT*
  fun get_ovector_count = pcre2_get_ovector_count_8(match_data : MatchData*) : UInt32

  fun config = pcre2_config_8(what : UInt32, where : Void*) : Int
end
