require "./lib_crypto"

{% begin %}
  lib LibSSL
    {{ `#{__DIR__}/version.sh libssl` }}
  end
{% end %}

{% if LibSSL::LDFLAGS %}
  @[Link(ldflags: "{{LibSSL::LDFLAGS.id}} -lssl -lcrypto")]
{% else %}
  @[Link(ldflags: "`command -v pkg-config > /dev/null && pkg-config --libs --silence-errors libssl || printf %s '-lssl -lcrypto'`")]
{% end %}
lib LibSSL
  alias Int = LibC::Int
  alias Char = LibC::Char
  alias Long = LibC::Long
  alias ULong = LibC::ULong

  type SSLMethod = Void*
  type SSLContext = Void*
  type SSL = Void*

  alias VerifyCallback = (Int, LibCrypto::X509_STORE_CTX) -> Int
  alias CertVerifyCallback = (LibCrypto::X509_STORE_CTX, Void*) -> Int

  enum SSLFileType
    PEM  = 1
    ASN1 = 2
  end

  enum SSLError : Int
    NONE             = 0
    SSL              = 1
    WANT_READ        = 2
    WANT_WRITE       = 3
    WANT_X509_LOOKUP = 4
    SYSCALL          = 5
    ZERO_RETURN      = 6
    WANT_CONNECT     = 7
    WANT_ACCEPT      = 8
  end

  @[Flags]
  enum VerifyMode : Int
    NONE                 = 0
    PEER                 = 1
    FAIL_IF_NO_PEER_CERT = 2
    CLIENT_ONCE          = 4
  end

  enum SSLCtrl : Int
    SET_TLSEXT_HOSTNAME = 55
  end

  enum TLSExt : Long
    NAMETYPE_host_name = 0
  end

  # SSL_CTRL_SET_TMP_RSA = 2
  # SSL_CTRL_SET_TMP_DH = 3
  SSL_CTRL_SET_TMP_ECDH = 4

  SSL_CTRL_OPTIONS       = 32
  SSL_CTRL_MODE          = 33
  SSL_CTRL_CLEAR_OPTIONS = 77
  SSL_CTRL_CLEAR_MODE    = 78

  enum Options : ULong
    LEGACY_SERVER_CONNECT       = 0x00000004
    SAFARI_ECDHE_ECDSA_BUG      = 0x00000040
    DONT_INSERT_EMPTY_FRAGMENTS = 0x00000800

    # Various bug workarounds that should be rather harmless.
    # This used to be `0x000FFFFF` before 0.9.7
    ALL = 0x80000BFF

    NO_QUERY_MTU     = 0x00001000
    COOKIE_EXCHANGE  = 0x00002000
    NO_TICKET        = 0x00004000
    CISCO_ANYCONNECT = 0x00008000

    NO_SESSION_RESUMPTION_ON_RENEGOTIATION = 0x00010000
    NO_COMPRESSION                         = 0x00020000
    ALLOW_UNSAFE_LEGACY_RENEGOTIATION      = 0x00040000
    CIPHER_SERVER_PREFERENCE               = 0x00400000
    TLS_ROLLBACK_BUG                       = 0x00800000

    NO_SSL_V3   = 0x02000000
    NO_TLS_V1   = 0x04000000
    NO_TLS_V1_2 = 0x08000000
    NO_TLS_V1_1 = 0x10000000

    NETSCAPE_CA_DN_BUG              = 0x20000000
    NETSCAPE_DEMO_CIPHER_CHANGE_BUG = 0x40000000
    CRYPTOPRO_TLSEXT_BUG            = 0x80000000

    {% if OPENSSL_VERSION_NUMBER >= 0x1_01_00_00_0 %}
      MICROSOFT_SESS_ID_BUG            = 0x00000000
      NETSCAPE_CHALLENGE_BUG           = 0x00000000
      NETSCAPE_REUSE_CIPHER_CHANGE_BUG = 0x00000000
      SSLREF2_REUSE_CERT_TYPE_BUG      = 0x00000000
      MICROSOFT_BIG_SSL_V3_BUFFER       = 0x00000000
      SSLEAY_080_CLIENT_DH_BUG         = 0x00000000
      TLS_D5_BUG                       = 0x00000000
      TLS_BLOCK_PADDING_BUG            = 0x00000000
      NO_SSL_V2                         = 0x00000000
      SINGLE_ECDH_USE                  = 0x00000000
      SINGLE_DH_USE                    = 0x00000000
    {% else %}
      MICROSOFT_SESS_ID_BUG            = 0x00000001
      NETSCAPE_CHALLENGE_BUG           = 0x00000002
      NETSCAPE_REUSE_CIPHER_CHANGE_BUG = 0x00000008
      SSLREF2_REUSE_CERT_TYPE_BUG      = 0x00000010
      MICROSOFT_BIG_SSL_V3_BUFFER       = 0x00000020
      SSLEAY_080_CLIENT_DH_BUG         = 0x00000080
      TLS_D5_BUG                       = 0x00000100
      TLS_BLOCK_PADDING_BUG            = 0x00000200
      NO_SSL_V2                         = 0x01000000
      SINGLE_ECDH_USE                  = 0x00080000
      SINGLE_DH_USE                    = 0x00100000
    {% end %}
  end

  @[Flags]
  enum Modes : ULong
    ENABLE_PARTIAL_WRITE       = 0x00000001
    ACCEPT_MOVING_WRITE_BUFFER = 0x00000002
    AUTO_RETRY                 = 0x00000004
    NO_AUTO_CHAIN              = 0x00000008
    RELEASE_BUFFERS            = 0x00000010
    SEND_CLIENTHELLO_TIME      = 0x00000020
    SEND_SERVERHELLO_TIME      = 0x00000040
    SEND_FALLBACK_SCSV         = 0x00000080
  end

  OPENSSL_NPN_UNSUPPORTED = 0
  OPENSSL_NPN_NEGOTIATED  = 1
  OPENSSL_NPN_NO_OVERLAP  = 2

  SSL_TLSEXT_ERR_OK            = 0
  SSL_TLSEXT_ERR_ALERT_WARNING = 1
  SSL_TLSEXT_ERR_ALERT_FATAL   = 2
  SSL_TLSEXT_ERR_NOACK         = 3

  fun tlsv1_method = TLSv1_method : SSLMethod
  fun tlsv1_1_method = TLSv1_1_method : SSLMethod
  fun tlsv1_2_method = TLSv1_2_method : SSLMethod

  fun ssl_get_error = SSL_get_error(handle : SSL, ret : Int) : SSLError
  fun ssl_get_servername = SSL_get_servername(ssl : SSL, host_type : TLSExt) : UInt8*
  fun ssl_set_bio = SSL_set_bio(handle : SSL, rbio : LibCrypto::Bio*, wbio : LibCrypto::Bio*)
  fun ssl_select_next_proto = SSL_select_next_proto(output : Char**, output_len : Char*, input : Char*, input_len : Int, client : Char*, client_len : Int) : Int
  fun ssl_ctrl = SSL_ctrl(handle : SSL, cmd : Int, larg : Long, parg : Void*) : Long
  fun ssl_free = SSL_free(handle : SSL)

  @[Raises]
  fun ssl_new = SSL_new(context : SSLContext) : SSL

  @[Raises]
  fun ssl_connect = SSL_connect(handle : SSL) : Int

  @[Raises]
  fun ssl_accept = SSL_accept(handle : SSL) : Int

  @[Raises]
  fun ssl_write = SSL_write(handle : SSL, text : UInt8*, length : Int) : Int

  @[Raises]
  fun ssl_read = SSL_read(handle : SSL, buffer : UInt8*, read_size : Int) : Int

  @[Raises]
  fun ssl_shutdown = SSL_shutdown(handle : SSL) : Int

  fun ssl_ctx_new = SSL_CTX_new(method : SSLMethod) : SSLContext
  fun ssl_ctx_free = SSL_CTX_free(context : SSLContext)
  fun ssl_ctx_set_cipher_list = SSL_CTX_set_cipher_list(ctx : SSLContext, ciphers : Char*) : Int
  fun ssl_ctx_use_certificate_chain_file = SSL_CTX_use_certificate_chain_file(ctx : SSLContext, file : UInt8*) : Int
  fun ssl_ctx_use_privatekey_file = SSL_CTX_use_PrivateKey_file(ctx : SSLContext, file : UInt8*, filetype : SSLFileType) : Int
  fun ssl_ctx_get_verify_mode = SSL_CTX_get_verify_mode(ctx : SSLContext) : VerifyMode
  fun ssl_ctx_set_verify = SSL_CTX_set_verify(ctx : SSLContext, mode : VerifyMode, callback : VerifyCallback)
  fun ssl_ctx_set_default_verify_paths = SSL_CTX_set_default_verify_paths(ctx : SSLContext) : Int
  fun ssl_ctx_ctrl = SSL_CTX_ctrl(ctx : SSLContext, cmd : Int, larg : ULong, parg : Void*) : ULong

  {% if OPENSSL_VERSION_NUMBER >= 0x1_01_00_00_0 %}
    fun ssl_ctx_get_options = SSL_CTX_get_options(ctx : SSLContext) : ULong
    fun ssl_ctx_set_options = SSL_CTX_set_options(ctx : SSLContext, larg : ULong) : ULong
    fun ssl_ctx_clear_options = SSL_CTX_clear_options(ctx : SSLContext, larg : ULong) : ULong
  {% end %}

  @[Raises]
  fun ssl_ctx_load_verify_locations = SSL_CTX_load_verify_locations(ctx : SSLContext, ca_file : UInt8*, ca_path : UInt8*) : Int

  {% if OPENSSL_VERSION_NUMBER <= 0x1_00_01_00_0 %}
    fun ssl_ctx_set_cert_verify_callback = SSL_CTX_set_cert_verify_callback(ctx : SSLContext, callback : CertVerifyCallback, arg : Void*)
  {% end %}

  {% if OPENSSL_VERSION_NUMBER >= 0x1_01_00_00_0 %}
    fun tls_method = TLS_method : SSLMethod
  {% else %}
    fun ssl_library_init = SSL_library_init
    fun ssl_load_error_strings = SSL_load_error_strings
    fun sslv23_method = SSLv23_method : SSLMethod
  {% end %}

  {% if OPENSSL_VERSION_NUMBER >= 0x1_00_02_00_0 || LIBRESSL_VERSION_NUMBER >= 0x2_05_00_00_0 %}
    alias ALPNCallback = (SSL, Char**, Char*, Char*, Int, Void*) -> Int

    fun ssl_get0_alpn_selected = SSL_get0_alpn_selected(handle : SSL, data : Char**, len : LibC::UInt*) : Void
    fun ssl_ctx_set_alpn_select_cb = SSL_CTX_set_alpn_select_cb(ctx : SSLContext, cb : ALPNCallback, arg : Void*) : Void
  {% end %}

  {% if OPENSSL_VERSION_NUMBER >= 0x1_00_02_00_0 %}
    alias X509VerifyParam = LibCrypto::X509VerifyParam

    fun dtls_method = DTLS_method : SSLMethod

    fun ssl_get0_param = SSL_get0_param(handle : SSL) : X509VerifyParam
    fun ssl_ctx_get0_param = SSL_CTX_get0_param(ctx : SSLContext) : X509VerifyParam
    fun ssl_ctx_set1_param = SSL_CTX_set1_param(ctx : SSLContext, param : X509VerifyParam) : Int
  {% end %}
end

{% if LibSSL::OPENSSL_VERSION_NUMBER < 0x1_01_00_00_0 %}
  LibSSL.ssl_library_init
  LibSSL.ssl_load_error_strings
  LibCrypto.openssl_add_all_algorithms
  LibCrypto.err_load_crypto_strings
{% end %}
