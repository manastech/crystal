# Supported library versions:
#
# * openssl (1.1.0–3.3+)
# * libressl (2.0–4.0+)
#
# See https://crystal-lang.org/reference/man/required_libraries.html#tls
{% begin %}
  lib LibCrypto
    {% if flag?(:msvc) %}
      {% from_libressl = false %}
      {% ssl_version = nil %}
      {% for dir in Crystal::LIBRARY_PATH.split(Crystal::System::Process::HOST_PATH_DELIMITER) %}
        {% unless ssl_version %}
          {% config_path = "#{dir.id}\\openssl_VERSION" %}
          {% if config_version = read_file?(config_path) %}
            {% ssl_version = config_version.chomp %}
          {% end %}
        {% end %}
      {% end %}
      {% ssl_version ||= "0.0.0" %}
    {% else %}
      # these have to be wrapped in `sh -c` since for MinGW-w64 the compiler
      # passes the command string to `LibC.CreateProcessW`
      {% from_libressl = (`sh -c 'hash pkg-config 2> /dev/null || printf %s false'` != "false") &&
                         (`sh -c 'test -f $(pkg-config --silence-errors --variable=includedir libcrypto)/openssl/opensslv.h || printf %s false'` != "false") &&
                         (`sh -c 'printf "#include <openssl/opensslv.h>\nLIBRESSL_VERSION_NUMBER" | ${CC:-cc} $(pkg-config --cflags --silence-errors libcrypto || true) -E -'`.chomp.split('\n').last != "LIBRESSL_VERSION_NUMBER") %}
      {% ssl_version = `sh -c 'hash pkg-config 2> /dev/null && pkg-config --silence-errors --modversion libcrypto || printf %s 0.0.0'`.split.last.gsub(/[^0-9.]/, "") %}
    {% end %}

    {% if from_libressl %}
      LIBRESSL_VERSION = {{ ssl_version }}
      OPENSSL_VERSION = "0.0.0"
    {% else %}
      LIBRESSL_VERSION = "0.0.0"
      OPENSSL_VERSION = {{ ssl_version }}
    {% end %}
  end
{% end %}

{% if flag?(:win32) %}
  @[Link("crypto")]
  @[Link("crypt32")] # CertOpenStore, ...
  @[Link("user32")]  # GetProcessWindowStation, GetUserObjectInformationW, _MessageBoxW
{% else %}
  @[Link("crypto", pkg_config: "libcrypto")]
{% end %}
{% if compare_versions(Crystal::VERSION, "1.11.0-dev") >= 0 %}
  # TODO: if someone brings their own OpenSSL 1.x.y on Windows, will this have a different name?
  @[Link(dll: "libcrypto-3-x64.dll")]
{% end %}
lib LibCrypto
  alias Char = LibC::Char
  alias Int = LibC::Int
  alias UInt = LibC::UInt
  alias Long = LibC::Long
  alias ULong = LibC::ULong
  alias SizeT = LibC::SizeT

  type X509 = Void*
  type X509_EXTENSION = Void*
  type X509_NAME = Void*
  type X509_NAME_ENTRY = Void*
  type X509_STORE = Void*
  type X509_STORE_CTX = Void*

  struct Bio
    method : Void*
    callback : BIO_callback_fn
    {% if compare_versions(LIBRESSL_VERSION, "3.5.0") >= 0 %}
      callback_ex : BIO_callback_fn_ex
    {% end %}
    cb_arg : Char*
    init : Int
    shutdown : Int
    flags : Int
    retry_reason : Int
    num : Int
    ptr : Void*
    next_bio : Void*
    prev_bio : Void*
    references : Int
    num_read : ULong
    num_write : ULong
  end

  alias BIO_callback_fn = (Bio*, Int, Char*, Int, Long, Long) -> Long
  alias BIO_callback_fn_ex = (Bio*, Int, Char, SizeT, Int, Long, Int, SizeT*) -> Long

  PKCS5_SALT_LEN     =  8
  EVP_MAX_KEY_LENGTH = 32
  EVP_MAX_IV_LENGTH  = 16

  CTRL_EOF           =  2
  CTRL_PUSH          =  6
  CTRL_POP           =  7
  CTRL_FLUSH         = 11
  CTRL_SET_KTLS_SEND = 72
  CTRL_GET_KTLS_SEND = 73
  CTRL_GET_KTLS_RECV = 76

  alias BioMethodWrite = (Bio*, Char*, SizeT, SizeT*) -> Int
  alias BioMethodWriteOld = (Bio*, Char*, Int) -> Int
  alias BioMethodRead = (Bio*, Char*, SizeT, SizeT*) -> Int
  alias BioMethodReadOld = (Bio*, Char*, Int) -> Int
  alias BioMethodPuts = (Bio*, Char*) -> Int
  alias BioMethodGets = (Bio*, Char*, Int) -> Int
  alias BioMethodCtrl = (Bio*, Int, Long, Void*) -> Long
  alias BioMethodCreate = Bio* -> Int
  alias BioMethodDestroy = Bio* -> Int
  alias BioMethodCallbackCtrl = (Bio*, Int, Void*) -> Long

  {% if compare_versions(LibCrypto::OPENSSL_VERSION, "1.1.0") >= 0 || compare_versions(LibCrypto::LIBRESSL_VERSION, "2.7.0") >= 0 %}
    type BioMethod = Void
  {% else %}
    struct BioMethod
      type_id : Int
      name : Char*
      bwrite : BioMethodWriteOld
      bread : BioMethodReadOld
      bputs : BioMethodPuts
      bgets : BioMethodGets
      ctrl : BioMethodCtrl
      create : BioMethodCreate
      destroy : BioMethodDestroy
      callback_ctrl : BioMethodCallbackCtrl
    end
  {% end %}

  fun BIO_new(BioMethod*) : Bio*
  fun BIO_free(Bio*) : Int

  {% if compare_versions(LibCrypto::OPENSSL_VERSION, "1.1.0") >= 0 || compare_versions(LibCrypto::LIBRESSL_VERSION, "2.7.0") >= 0 %}
    fun BIO_set_data(Bio*, Void*)
    fun BIO_get_data(Bio*) : Void*
    fun BIO_set_init(Bio*, Int)
    fun BIO_set_shutdown(Bio*, Int)

    fun BIO_meth_new(Int, Char*) : BioMethod*
    fun BIO_meth_set_read(BioMethod*, BioMethodReadOld)
    fun BIO_meth_set_write(BioMethod*, BioMethodWriteOld)
    fun BIO_meth_set_puts(BioMethod*, BioMethodPuts)
    fun BIO_meth_set_gets(BioMethod*, BioMethodGets)
    fun BIO_meth_set_ctrl(BioMethod*, BioMethodCtrl)
    fun BIO_meth_set_create(BioMethod*, BioMethodCreate)
    fun BIO_meth_set_destroy(BioMethod*, BioMethodDestroy)
    fun BIO_meth_set_callback_ctrl(BioMethod*, BioMethodCallbackCtrl)
  {% end %}
  # LibreSSL does not define these symbols
  {% if compare_versions(LibCrypto::OPENSSL_VERSION, "1.1.1") >= 0 %}
    fun BIO_meth_set_read_ex(BioMethod*, BioMethodRead)
    fun BIO_meth_set_write_ex(BioMethod*, BioMethodWrite)
  {% end %}

  fun sha1 = SHA1(data : Char*, length : SizeT, md : Char*) : Char*

  type EVP_MD = Void*

  fun evp_md4 = EVP_md4 : EVP_MD
  fun evp_md5 = EVP_md5 : EVP_MD
  fun evp_ripemd160 = EVP_ripemd160 : EVP_MD
  fun evp_sha1 = EVP_sha1 : EVP_MD
  fun evp_sha224 = EVP_sha224 : EVP_MD
  fun evp_sha256 = EVP_sha256 : EVP_MD
  fun evp_sha384 = EVP_sha384 : EVP_MD
  fun evp_sha512 = EVP_sha512 : EVP_MD

  alias EVP_CIPHER = Void*
  alias EVP_CIPHER_CTX = Void*

  alias ASN1_OBJECT = Void*
  alias ASN1_STRING = Char*

  fun obj_txt2obj = OBJ_txt2obj(s : Char*, no_name : Int) : ASN1_OBJECT
  fun obj_nid2sn = OBJ_nid2sn(n : Int) : Char*
  fun obj_obj2nid = OBJ_obj2nid(obj : ASN1_OBJECT) : Int
  fun obj_ln2nid = OBJ_ln2nid(ln : Char*) : Int
  fun obj_sn2nid = OBJ_sn2nid(sn : Char*) : Int
  {% if compare_versions(OPENSSL_VERSION, "1.0.2") >= 0 || LIBRESSL_VERSION != "0.0.0" %}
    fun obj_find_sigid_algs = OBJ_find_sigid_algs(sigid : Int32, pdig_nid : Int32*, ppkey_nid : Int32*) : Int32
  {% end %}

  fun asn1_object_free = ASN1_OBJECT_free(obj : ASN1_OBJECT)
  fun asn1_string_data = ASN1_STRING_data(x : ASN1_STRING) : Char*
  fun asn1_string_length = ASN1_STRING_length(x : ASN1_STRING) : Int
  fun asn1_string_print = ASN1_STRING_print(out : Bio*, v : ASN1_STRING) : Int
  fun i2t_asn1_object = i2t_ASN1_OBJECT(buf : Char*, buf_len : Int, a : ASN1_OBJECT) : Int

  struct EVP_MD_CTX_Struct
    digest : EVP_MD
    engine : Void*
    flags : UInt32
    pctx : Void*
    update_fun : Void*
  end

  alias EVP_MD_CTX = EVP_MD_CTX_Struct*

  struct HMAC_CTX_Struct
    md : EVP_MD
    md_ctx : EVP_MD_CTX_Struct
    i_ctx : EVP_MD_CTX_Struct
    o_ctx : EVP_MD_CTX_Struct
    key_length : UInt32
    key : UInt8[128]
  end

  alias HMAC_CTX = HMAC_CTX_Struct*

  fun hmac_ctx_init = HMAC_CTX_init(ctx : HMAC_CTX)
  fun hmac_ctx_cleanup = HMAC_CTX_cleanup(ctx : HMAC_CTX)
  fun hmac_init_ex = HMAC_Init_ex(ctx : HMAC_CTX, key : Void*, len : Int32, md : EVP_MD, engine : Void*) : Int32
  fun hmac_update = HMAC_Update(ctx : HMAC_CTX, data : UInt8*, len : LibC::SizeT) : Int32
  fun hmac_final = HMAC_Final(ctx : HMAC_CTX, md : UInt8*, len : UInt32*) : Int32
  fun hmac_ctx_copy = HMAC_CTX_copy(dst : HMAC_CTX, src : HMAC_CTX) : Int32

  fun x509_digest = X509_digest(x509 : X509, evp_md : EVP_MD, hash : UInt8*, len : Int32*) : Int32
  fun evp_get_digestbyname = EVP_get_digestbyname(name : UInt8*) : EVP_MD
  fun evp_digestinit_ex = EVP_DigestInit_ex(ctx : EVP_MD_CTX, type : EVP_MD, engine : Void*) : Int32
  fun evp_digestupdate = EVP_DigestUpdate(ctx : EVP_MD_CTX, data : UInt8*, count : LibC::SizeT) : Int32
  fun evp_md_ctx_copy = EVP_MD_CTX_copy(dst : EVP_MD_CTX, src : EVP_MD_CTX) : Int32
  fun evp_md_ctx_md = EVP_MD_CTX_md(ctx : EVP_MD_CTX) : EVP_MD

  {% if compare_versions(OPENSSL_VERSION, "3.0.0") >= 0 %}
    fun evp_md_size = EVP_MD_get_size(md : EVP_MD) : Int32
    fun evp_md_block_size = EVP_MD_get_block_size(md : EVP_MD) : LibC::Int
  {% else %}
    fun evp_md_size = EVP_MD_size(md : EVP_MD) : Int32
    fun evp_md_block_size = EVP_MD_block_size(md : EVP_MD) : LibC::Int
  {% end %}

  fun evp_digestfinal_ex = EVP_DigestFinal_ex(ctx : EVP_MD_CTX, md : UInt8*, size : UInt32*) : Int32

  {% if compare_versions(OPENSSL_VERSION, "1.1.0") >= 0 || compare_versions(LibCrypto::LIBRESSL_VERSION, "2.7.0") >= 0 %}
    fun evp_md_ctx_new = EVP_MD_CTX_new : EVP_MD_CTX
    fun evp_md_ctx_free = EVP_MD_CTX_free(ctx : EVP_MD_CTX)
  {% else %}
    fun evp_md_ctx_new = EVP_MD_CTX_create : EVP_MD_CTX
    fun evp_md_ctx_free = EVP_MD_CTX_destroy(ctx : EVP_MD_CTX)
  {% end %}

  fun evp_get_cipherbyname = EVP_get_cipherbyname(name : UInt8*) : EVP_CIPHER

  {% if compare_versions(OPENSSL_VERSION, "3.0.0") >= 0 %}
    fun evp_cipher_name = EVP_CIPHER_get_name(cipher : EVP_CIPHER) : UInt8*
    fun evp_cipher_nid = EVP_CIPHER_get_nid(cipher : EVP_CIPHER) : Int32
    fun evp_cipher_block_size = EVP_CIPHER_get_block_size(cipher : EVP_CIPHER) : Int32
    fun evp_cipher_key_length = EVP_CIPHER_get_key_length(cipher : EVP_CIPHER) : Int32
    fun evp_cipher_iv_length = EVP_CIPHER_get_iv_length(cipher : EVP_CIPHER) : Int32
    fun evp_cipher_flags = EVP_CIPHER_get_flags(cipher : EVP_CIPHER) : CipherFlags
  {% else %}
    fun evp_cipher_name = EVP_CIPHER_name(cipher : EVP_CIPHER) : UInt8*
    fun evp_cipher_nid = EVP_CIPHER_nid(cipher : EVP_CIPHER) : Int32
    fun evp_cipher_block_size = EVP_CIPHER_block_size(cipher : EVP_CIPHER) : Int32
    fun evp_cipher_key_length = EVP_CIPHER_key_length(cipher : EVP_CIPHER) : Int32
    fun evp_cipher_iv_length = EVP_CIPHER_iv_length(cipher : EVP_CIPHER) : Int32
    fun evp_cipher_flags = EVP_CIPHER_flags(cipher : EVP_CIPHER) : CipherFlags
  {% end %}

  fun evp_cipher_ctx_new = EVP_CIPHER_CTX_new : EVP_CIPHER_CTX
  fun evp_cipher_ctx_free = EVP_CIPHER_CTX_free(ctx : EVP_CIPHER_CTX)
  fun evp_cipherinit_ex = EVP_CipherInit_ex(ctx : EVP_CIPHER_CTX, type : EVP_CIPHER, engine : Void*, key : UInt8*, iv : UInt8*, enc : Int32) : Int32
  fun evp_cipherupdate = EVP_CipherUpdate(ctx : EVP_CIPHER_CTX, out : UInt8*, outl : Int32*, in : UInt8*, inl : Int32) : Int32
  fun evp_cipherfinal_ex = EVP_CipherFinal_ex(ctx : EVP_CIPHER_CTX, out : UInt8*, outl : Int32*) : Int32
  fun evp_cipher_ctx_set_padding = EVP_CIPHER_CTX_set_padding(ctx : EVP_CIPHER_CTX, padding : Int32) : Int32
  fun evp_cipher_ctx_cipher = EVP_CIPHER_CTX_cipher(ctx : EVP_CIPHER_CTX) : EVP_CIPHER

  @[Flags]
  enum CipherFlags : ULong
    EVP_CIPH_FLAG_DEFAULT_ASN1      =   0x1000
    EVP_CIPH_FLAG_LENGTH_BITS       =   0x2000
    EVP_CIPH_FLAG_FIPS              =   0x4000
    EVP_CIPH_FLAG_NON_FIPS_ALLOW    =   0x8000
    EVP_CIPH_FLAG_CUSTOM_CIPHER     = 0x100000
    EVP_CIPH_FLAG_AEAD_CIPHER       = 0x200000
    EVP_CIPH_FLAG_TLS1_1_MULTIBLOCK = 0x400000
    EVP_CIPH_FLAG_PIPELINE          = 0x800000
  end

  fun hmac = HMAC(evp : EVP_MD, key : Char*, key_len : Int,
                  d : Char*, n : SizeT, md : Char*, md_len : UInt*) : Char*

  fun rand_bytes = RAND_bytes(buf : Char*, num : Int) : Int
  fun err_get_error = ERR_get_error : ULong
  fun err_error_string = ERR_error_string(e : ULong, buf : Char*) : Char*

  {% if compare_versions(OPENSSL_VERSION, "3.0.0") >= 0 %}
    ERR_SYSTEM_FLAG = Int32::MAX.to_u32 + 1
    ERR_SYSTEM_MASK = Int32::MAX.to_u32
    ERR_REASON_MASK = 0x7FFFFF
  {% end %}

  struct MD5Context
    a : UInt
    b : UInt
    c : UInt
    d : UInt
    nl : UInt
    nh : UInt
    data : UInt[16]
    num : UInt
  end

  fun md5_init = MD5_Init(c : MD5Context*) : Int
  fun md5_update = MD5_Update(c : MD5Context*, data : Void*, len : LibC::SizeT) : Int
  fun md5_final = MD5_Final(md : UInt8*, c : MD5Context*) : Int
  fun md5_transform = MD5_Transform(c : MD5Context*, b : UInt8*)
  fun md5 = MD5(data : UInt8*, length : LibC::SizeT, md : UInt8*) : UInt8*

  fun pkcs5_pbkdf2_hmac_sha1 = PKCS5_PBKDF2_HMAC_SHA1(pass : LibC::Char*, passlen : LibC::Int, salt : UInt8*, saltlen : LibC::Int, iter : LibC::Int, keylen : LibC::Int, out : UInt8*) : LibC::Int
  {% if compare_versions(OPENSSL_VERSION, "1.0.0") >= 0 || LIBRESSL_VERSION != "0.0.0" %}
    fun pkcs5_pbkdf2_hmac = PKCS5_PBKDF2_HMAC(pass : LibC::Char*, passlen : LibC::Int, salt : UInt8*, saltlen : LibC::Int, iter : LibC::Int, digest : EVP_MD, keylen : LibC::Int, out : UInt8*) : LibC::Int
  {% end %}

  NID_X9_62_prime256v1 = 415

  alias EC_KEY = Void*
  fun ec_key_new_by_curve_name = EC_KEY_new_by_curve_name(nid : Int) : EC_KEY
  fun ec_key_free = EC_KEY_free(key : EC_KEY)

  struct GENERAL_NAME
    type : LibC::Int
    value : ASN1_STRING
  end

  # GEN_URI  = 6
  GEN_DNS   = 2
  GEN_IPADD = 7

  NID_undef            =  0
  NID_commonName       = 13
  NID_subject_alt_name = 85

  {% if compare_versions(OPENSSL_VERSION, "1.1.0") >= 0 %}
    fun sk_free = OPENSSL_sk_free(st : Void*)
    fun sk_num = OPENSSL_sk_num(x0 : Void*) : Int
    fun sk_pop_free = OPENSSL_sk_pop_free(st : Void*, callback : (Void*) ->)
    fun sk_value = OPENSSL_sk_value(x0 : Void*, x1 : Int) : Void*
  {% else %}
    fun sk_free(st : Void*)
    fun sk_num(x0 : Void*) : Int
    fun sk_pop_free(st : Void*, callback : (Void*) ->)
    fun sk_value(x0 : Void*, x1 : Int) : Void*
  {% end %}

  fun d2i_X509(a : X509*, ppin : UInt8**, length : Long) : X509
  fun x509_dup = X509_dup(a : X509) : X509
  fun x509_free = X509_free(a : X509)
  fun x509_get_subject_name = X509_get_subject_name(a : X509) : X509_NAME
  fun x509_new = X509_new : X509
  fun x509_set_subject_name = X509_set_subject_name(x : X509, name : X509_NAME) : Int
  fun x509_store_ctx_get_current_cert = X509_STORE_CTX_get_current_cert(x : X509_STORE_CTX) : X509
  fun x509_verify_cert = X509_verify_cert(x : X509_STORE_CTX) : Int
  fun x509_add_ext = X509_add_ext(x : X509, ex : X509_EXTENSION, loc : Int) : X509_EXTENSION
  fun x509_get_ext = X509_get_ext(x : X509, idx : Int) : X509_EXTENSION
  fun x509_get_ext_count = X509_get_ext_count(x : X509) : Int
  fun x509_get_ext_d2i = X509_get_ext_d2i(x : X509, nid : Int, crit : Int*, idx : Int*) : Void*
  {% if compare_versions(OPENSSL_VERSION, "1.0.2") >= 0 || LIBRESSL_VERSION != "0.0.0" %}
    fun x509_get_signature_nid = X509_get_signature_nid(x509 : X509) : Int32
  {% end %}

  MBSTRING_UTF8 = 0x1000

  fun x509_name_add_entry_by_txt = X509_NAME_add_entry_by_txt(name : X509_NAME, field : Char*, type : Int, bytes : Char*, len : Int, loc : Int, set : Int) : X509_NAME
  fun x509_name_dup = X509_NAME_dup(a : X509_NAME) : X509_NAME
  fun x509_name_entry_count = X509_NAME_entry_count(name : X509_NAME) : Int
  fun x509_name_free = X509_NAME_free(a : X509_NAME)
  fun x509_name_get_entry = X509_NAME_get_entry(name : X509_NAME, loc : Int) : X509_NAME_ENTRY
  fun x509_name_get_index_by_nid = X509_NAME_get_index_by_NID(name : X509_NAME, nid : Int, lastpos : Int) : Int
  fun x509_name_new = X509_NAME_new : X509_NAME

  fun x509_name_entry_get_data = X509_NAME_ENTRY_get_data(ne : X509_NAME_ENTRY) : ASN1_STRING
  fun x509_name_entry_get_object = X509_NAME_ENTRY_get_object(ne : X509_NAME_ENTRY) : ASN1_OBJECT

  fun x509_extension_dup = X509_EXTENSION_dup(a : X509_EXTENSION) : X509_EXTENSION
  fun x509_extension_free = X509_EXTENSION_free(a : X509_EXTENSION)
  fun x509_extension_get_object = X509_EXTENSION_get_object(a : X509_EXTENSION) : ASN1_OBJECT
  fun x509_extension_get_data = X509_EXTENSION_get_data(a : X509_EXTENSION) : ASN1_STRING
  fun x509_extension_create_by_nid = X509_EXTENSION_create_by_NID(ex : X509_EXTENSION, nid : Int, crit : Int, data : ASN1_STRING) : X509_EXTENSION
  fun x509v3_ext_nconf_nid = X509V3_EXT_nconf_nid(conf : Void*, ctx : Void*, ext_nid : Int, value : Char*) : X509_EXTENSION
  fun x509v3_ext_print = X509V3_EXT_print(out : Bio*, ext : X509_EXTENSION, flag : Int, indent : Int) : Int

  fun x509_store_add_cert = X509_STORE_add_cert(ctx : X509_STORE, x : X509) : Int

  {% unless compare_versions(OPENSSL_VERSION, "1.1.0") >= 0 || compare_versions(LibCrypto::LIBRESSL_VERSION, "3.0.0") >= 0 %}
    fun err_load_crypto_strings = ERR_load_crypto_strings
    fun openssl_add_all_algorithms = OPENSSL_add_all_algorithms_noconf
  {% end %}

  {% if compare_versions(OPENSSL_VERSION, "1.0.2") >= 0 || LIBRESSL_VERSION != "0.0.0" %}
    type X509VerifyParam = Void*

    @[Flags]
    enum X509VerifyFlags : ULong
      CB_ISSUER_CHECK      =      0x1
      USE_CHECK_TIME       =      0x2
      CRL_CHECK            =      0x4
      CRL_CHECK_ALL        =      0x8
      IGNORE_CRITICAL      =     0x10
      X509_STRICT          =     0x20
      ALLOW_PROXY_CERTS    =     0x40
      POLICY_CHECK         =     0x80
      EXPLICIT_POLICY      =    0x100
      INHIBIT_ANY          =    0x200
      INHIBIT_MAP          =    0x400
      NOTIFY_POLICY        =    0x800
      EXTENDED_CRL_SUPPORT =   0x1000
      USE_DELTAS           =   0x2000
      CHECK_SS_SIGNATURE   =   0x4000
      TRUSTED_FIRST        =   0x8000
      SUITEB_128_LOS_ONLY  =  0x10000
      SUITEB_192_LOS       =  0x20000
      SUITEB_128_LOS       =  0x30000
      PARTIAL_CHAIN        =  0x80000
      NO_ALT_CHAINS        = 0x100000
    end

    fun x509_verify_param_lookup = X509_VERIFY_PARAM_lookup(name : UInt8*) : X509VerifyParam
    fun x509_verify_param_set1_host = X509_VERIFY_PARAM_set1_host(param : X509VerifyParam, name : UInt8*, len : SizeT) : Int
    fun x509_verify_param_set1_ip_asc = X509_VERIFY_PARAM_set1_ip_asc(param : X509VerifyParam, ip : UInt8*) : Int
    fun x509_verify_param_set_flags = X509_VERIFY_PARAM_set_flags(param : X509VerifyParam, flags : X509VerifyFlags) : Int
  {% end %}
end
