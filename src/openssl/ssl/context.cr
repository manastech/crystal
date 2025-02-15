require "uri/punycode"
require "log"
{% if flag?(:win32) %}
  require "crystal/system/win32/crypto"
{% end %}

# An `SSL::Context` represents a generic secure socket protocol configuration.
#
# For both server and client applications exist more specialized subclassses
# `SSL::Context::Server` and `SSL::Context::Client` which need to be instantiated
# appropriately.
abstract class OpenSSL::SSL::Context
  # :nodoc:
  def self.default_method
    {% if LibSSL.has_method?(:tls_method) %}
      LibSSL.tls_method
    {% else %}
      LibSSL.sslv23_method
    {% end %}
  end

  class Client < Context
    @hostname : String?

    # Generates a new TLS client context with sane defaults for a client connection.
    #
    # Defaults to `TLS_method` or `SSLv23_method` (depending on OpenSSL version)
    # which tells OpenSSL to negotiate the TLS or SSL protocol with the remote
    # endpoint.
    #
    # Don't change the method unless you must restrict a specific protocol to be
    # used (eg: TLSv1.2) and nothing else. You should specify options to disable
    # specific protocols, yet allow to negotiate from various other ones. For
    # example the following snippet will enable the TLSv1, TLSv1.1 and TLSv1.2
    # protocols but disable the deprecated SSLv2 and SSLv3 protocols:
    #
    # ```
    # require "openssl"
    #
    # context = OpenSSL::SSL::Context::Client.new
    # context.add_options(OpenSSL::SSL::Options::NO_SSL_V2 | OpenSSL::SSL::Options::NO_SSL_V3)
    # ```
    def initialize(method : LibSSL::SSLMethod = Context.default_method)
      super(method)

      self.verify_mode = OpenSSL::SSL::VerifyMode::PEER
      {% if LibSSL.has_method?(:x509_verify_param_lookup) %}
        self.default_verify_param = "ssl_server"
      {% end %}
    end

    # Returns a new TLS client context with only the given method set.
    #
    # For everything else this uses the defaults of your OpenSSL.
    # Use this only if undoing the defaults that `new` sets is too much hassle.
    def self.insecure(method : LibSSL::SSLMethod = Context.default_method) : self
      super(method)
    end

    # Configures a client context from a hash-like interface.
    #
    # ```
    # require "openssl"
    #
    # context = OpenSSL::SSL::Context::Client.from_hash({"key" => "private.key", "cert" => "certificate.crt", "ca" => "ca.pem"})
    # ```
    #
    # Params:
    #
    # * `key` *(required)*: Path to private key file. See `#private_key=`.
    # * `cert` *(required)*: Path to the file containing the public certificate chain. See `#certificate_chain=`.
    # * `verify_mode`: Either `peer`, `force-peer`, `none` or empty (default: `peer`). See `verify_mode=`.
    # * `ca`: Path to a file containing the CA certificate chain or a directory containing all CA certificates.
    #    See `#ca_certificates=` and `#ca_certificates_path=`, respectively.
    #    Required if `verify_mode` is `peer`, `force-peer` or empty.
    def self.from_hash(params) : self
      super(params)
    end

    # Wraps the original certificate verification to also validate the
    # hostname against the certificate configured Subject Alternate
    # Names or Common Name.
    #
    # Required for OpenSSL <= 1.0.1 only.
    protected def set_cert_verify_callback(hostname : String)
      # Sanitize the hostname with PunyCode
      hostname = URI::Punycode.to_ascii hostname

      # Keep a reference so the GC doesn't collect it after sending it to C land
      @hostname = hostname
      LibSSL.ssl_ctx_set_cert_verify_callback(@handle, ->(x509_ctx, arg) {
        if LibCrypto.x509_verify_cert(x509_ctx) != 0
          cert = LibCrypto.x509_store_ctx_get_current_cert(x509_ctx)
          HostnameValidation.validate_hostname(arg.as(String), cert) == HostnameValidation::Result::MatchFound ? 1 : 0
        else
          0
        end
      }, hostname.as(Void*))
    end

    private def alpn_protocol=(protocol : Bytes)
      {% if LibSSL.has_method?(:ssl_ctx_set_alpn_protos) %}
        LibSSL.ssl_ctx_set_alpn_protos(@handle, protocol, protocol.size)
      {% else %}
        raise NotImplementedError.new("LibSSL.ssl_ctx_set_alpn_protos")
      {% end %}
    end
  end

  class Server < Context
    # Generates a new TLS server context with sane defaults for a server connection.
    #
    # Defaults to `TLS_method` or `SSLv23_method` (depending on OpenSSL version)
    # which tells OpenSSL to negotiate the TLS or SSL protocol with the remote
    # endpoint.
    #
    # Don't change the method unless you must restrict a specific protocol to be
    # used (eg: TLSv1.2) and nothing else. You should specify options to disable
    # specific protocols, yet allow to negotiate from various other ones. For
    # example the following snippet will enable the TLSv1, TLSv1.1 and TLSv1.2
    # protocols but disable the deprecated SSLv2 and SSLv3 protocols:
    #
    # ```
    # context = OpenSSL::SSL::Context::Server.new
    # context.add_options(OpenSSL::SSL::Options::NO_SSL_V2 | OpenSSL::SSL::Options::NO_SSL_V3)
    # ```
    def initialize(method : LibSSL::SSLMethod = Context.default_method)
      super(method)

      {% if LibSSL.has_method?(:x509_verify_param_lookup) %}
        self.default_verify_param = "ssl_client"
      {% end %}
    end

    # Returns a new TLS server context with only the given method set.
    #
    # For everything else this uses the defaults of your OpenSSL.
    # Use this only if undoing the defaults that `new` sets is too much hassle.
    def self.insecure(method : LibSSL::SSLMethod = Context.default_method) : self
      super(method)
    end

    # Configures a server from a hash-like interface.
    #
    # ```
    # require "openssl"
    #
    # context = OpenSSL::SSL::Context::Client.from_hash({"key" => "private.key", "cert" => "certificate.crt", "ca" => "ca.pem"})
    # ```
    #
    # Params:
    #
    # * `key` *(required)*: Path to private key file. See `#private_key=`.
    # * `cert` *(required)*: Path to the file containing the public certificate chain. See `#certificate_chain=`.
    # * `verify_mode`: Either `peer`, `force-peer`, `none` or empty (default: `none`). See `verify_mode=`.
    # * `ca`: Path to a file containing the CA certificate chain or a directory containing all CA certificates.
    #    See `#ca_certificates=` and `#ca_certificates_path=`, respectively.
    #    Required if `verify_mode` is `peer` or `force-peer`.
    def self.from_hash(params) : self
      super(params)
    end

    # Disables all session ticket generation for this context.
    # Tickets are used to resume earlier sessions more quickly,
    # but in TLS 1.3 if the client connects, sends data, and closes the connection
    # unidirectionally, the server connects, then sends a ticket
    # after the connect handshake, the ticket send can fail with Broken Pipe.
    # So if you have that kind of behavior (clients that never read) call this method.
    def disable_session_resume_tickets : Nil
      add_options(OpenSSL::SSL::Options::NO_TICKET) # TLS v1.2 and below
      {% if LibSSL.has_method?(:ssl_ctx_set_num_tickets) %}
        ret = LibSSL.ssl_ctx_set_num_tickets(self, 0) # TLS v1.3
        raise OpenSSL::Error.new("SSL_CTX_set_num_tickets") if ret != 1
      {% end %}
    end

    private def alpn_protocol=(protocol : Bytes)
      {% if LibSSL.has_method?(:ssl_ctx_set_alpn_select_cb) %}
        alpn_cb = ->(ssl : LibSSL::SSL, o : LibC::Char**, olen : LibC::Char*, i : LibC::Char*, ilen : LibC::Int, data : Void*) {
          proto = Box(Bytes).unbox(data)
          ret = LibSSL.ssl_select_next_proto(o, olen, proto, proto.size, i, ilen)
          if ret != LibSSL::OPENSSL_NPN_NEGOTIATED
            LibSSL::SSL_TLSEXT_ERR_NOACK
          else
            LibSSL::SSL_TLSEXT_ERR_OK
          end
        }
        @alpn_protocol = alpn_protocol = Box.box(protocol)
        LibSSL.ssl_ctx_set_alpn_select_cb(@handle, alpn_cb, alpn_protocol)
      {% else %}
        raise NotImplementedError.new("LibSSL.ssl_ctx_set_alpn_select_cb")
      {% end %}
    end
  end

  protected def initialize(method : LibSSL::SSLMethod)
    @handle = LibSSL.ssl_ctx_new(method)
    raise OpenSSL::Error.new("SSL_CTX_new") if @handle.null?

    set_default_verify_paths

    add_options(OpenSSL::SSL::Options.flags(
      ALL,
      NO_SSL_V2,
      NO_SSL_V3,
      NO_TLS_V1,
      NO_TLS_V1_1,
      NO_SESSION_RESUMPTION_ON_RENEGOTIATION,
      SINGLE_ECDH_USE,
      SINGLE_DH_USE
    ))

    {% if compare_versions(LibSSL::OPENSSL_VERSION, "1.1.0") >= 0 %}
      add_options(OpenSSL::SSL::Options::NO_RENEGOTIATION)
    {% end %}

    add_modes(OpenSSL::SSL::Modes.flags(AUTO_RETRY, RELEASE_BUFFERS))

    # OpenSSL does not support reading from the system root certificate store on
    # Windows, so we have to import them ourselves
    {% if flag?(:win32) %}
      Crystal::System::Crypto.populate_system_root_certificates(self)
    {% end %}
  end

  # Overriding initialize or new in the child classes as public methods,
  # makes it either impossible to access the parent versions or makes the parent
  # versions public too. So to provide insecure in the child classes, we need
  # a second constructor that we call from there without getting the
  # overridden ones of the childs.
  protected def _initialize_insecure(method : LibSSL::SSLMethod)
    @handle = LibSSL.ssl_ctx_new(method)
    raise OpenSSL::Error.new("SSL_CTX_new") if @handle.null?

    # since an insecure context on non-Windows systems still has access to the
    # system certificates, we do the same for Windows
    {% if flag?(:win32) %}
      Crystal::System::Crypto.populate_system_root_certificates(self)
    {% end %}
  end

  protected def self.insecure(method : LibSSL::SSLMethod)
    obj = allocate
    obj._initialize_insecure(method)
    GC.add_finalizer(obj)
    obj
  end

  def finalize
    LibSSL.ssl_ctx_free(@handle)
  end

  # Sets the default paths for `ca_certificates=` and `ca_certificates_path=`.
  def set_default_verify_paths
    LibSSL.ssl_ctx_set_default_verify_paths(@handle)
  end

  # Sets the path to a file containing all CA certificates, in PEM format, used to
  # validate the peers certificate.
  def ca_certificates=(file_path : String)
    ret = LibSSL.ssl_ctx_load_verify_locations(@handle, file_path, nil)
    raise OpenSSL::Error.new("SSL_CTX_load_verify_locations") unless ret == 1
  end

  # Sets the path to a directory containing all CA certificates used to
  # validate the peers certificate. The certificates should be in PEM format
  # and the `c_rehash(1)` utility must have been run in the directory.
  def ca_certificates_path=(dir_path : String)
    ret = LibSSL.ssl_ctx_load_verify_locations(@handle, nil, dir_path)
    raise OpenSSL::Error.new("SSL_CTX_load_verify_locations") unless ret == 1
  end

  # Specify the path to the certificate chain file to use. In server mode this
  # is presented to the client, in client mode this used as client certificate.
  def certificate_chain=(file_path : String)
    ret = LibSSL.ssl_ctx_use_certificate_chain_file(@handle, file_path)
    raise OpenSSL::Error.new("SSL_CTX_use_certificate_chain_file") unless ret == 1
  end

  # Specify the certificate to be used as chain. In server mode this
  # is presented to the client, in client mode this used as client certificate.
  def certificate_chain=(cert : OpenSSL::X509::Certificate)
    ret = LibSSL.ssl_ctx_use_certificate(@handle, cert)
    raise OpenSSL::Error.new("SSL_CTX_use_certificate") unless ret == 1
  end

  # Specify the path to the private key to use. The key must in PEM format.
  # The key must correspond to the entity certificate set by `certificate_chain=`.
  def private_key=(file_path : String)
    ret = LibSSL.ssl_ctx_use_privatekey_file(@handle, file_path, LibSSL::SSLFileType::PEM)
    raise OpenSSL::Error.new("SSL_CTX_use_PrivateKey_file") unless ret == 1
  end

  # Specify a list of TLS ciphers to use or discard for TLSv1.2 and below.
  #
  # See `#security_level=` for some sensible system configuration.
  #
  # This method does not impact TLSv1.3 ciphersuites. Use `#cipher_suites=`
  # to configure those.
  #
  # NOTE: The ciphers available to an application are determined by the
  #       linked version of the system SSL library. A comprehensive list
  #       of ciphers can be found in the
  #       [OpenSSL Cipher documentation](https://www.openssl.org/docs/man3.0/man1/openssl-ciphers.html#CIPHER-STRINGS).
  def ciphers=(ciphers : String)
    ret = LibSSL.ssl_ctx_set_cipher_list(@handle, ciphers)
    raise OpenSSL::Error.new("SSL_CTX_set_cipher_list") if ret == 0
    ciphers
  end

  # Specify a list of TLS ciphersuites to use or discard for TLSv1.3.
  #
  # See `#security_level=` for some sensible system configuration.
  #
  # NOTE: The ciphersuites available to an application are determined by the
  #       linked version of the system SSL library. A comprehensive list
  #       of ciphersuites can be found in the
  #       [OpenSSL Cipher documentation](https://www.openssl.org/docs/man3.0/man1/openssl-ciphers.html#TLS-v1.3-cipher-suites).
  def cipher_suites=(cipher_suites : String)
    {% if LibSSL.has_method?(:ssl_ctx_set_ciphersuites) %}
      ret = LibSSL.ssl_ctx_set_ciphersuites(@handle, cipher_suites)
      raise OpenSSL::Error.new("SSL_CTX_set_ciphersuites") if ret == 0
    {% else %}
      Log.warn { "SSL_CTX_set_ciphersuites not supported" }
    {% end %}
    cipher_suites
  end

  # Sets the current ciphers and ciphers suites to **modern** compatibility level as per Mozilla
  # recommendations. See `#security_level=` for some sensible system configuration.
  #
  # WARNING: Does nothing as of Crystal 1.13.
  # WARNING: Didn't work as expected as of OpenSSL 1.1 (didn't configure TLSv1.2 and below).
  @[Deprecated("Deprecated with no replacement. Prefer #security_level, global system configuration or build your own from https://wiki.mozilla.org/Security/Server_Side_TLS")]
  def set_modern_ciphers
  end

  # Sets the current ciphers and ciphers suites to **intermediate** compatibility level as per Mozilla
  # recommendations. See `#security_level=` for some sensible system configuration.
  #
  # WARNING: Does nothing as of Crystal 1.13.
  # WARNING: Didn't work as expected as of OpenSSL 1.1 (didn't configure TLSv1.2 and below).
  @[Deprecated("Deprecated with no replacement. Prefer #security_level, global system configuration or build your own from https://wiki.mozilla.org/Security/Server_Side_TLS")]
  def set_intermediate_ciphers
  end

  # Sets the current ciphers and ciphers suites to **old** compatibility level as per Mozilla
  # recommendations. See `#security_level=` for some sensible system configuration.
  #
  # WARNING: Does nothing as of Crystal 1.13.
  # WARNING: Didn't work as expected as of OpenSSL 1.1 (didn't configure TLSv1.2 and below).
  @[Deprecated("Deprecated with no replacement. Prefer #security_level, global system configuration or build your own from https://wiki.mozilla.org/Security/Server_Side_TLS")]
  def set_old_ciphers
  end

  # Returns the security level used by this TLS context.
  def security_level : Int32
    {% if LibSSL.has_method?(:ssl_ctx_get_security_level) %}
      LibSSL.ssl_ctx_get_security_level(@handle)
    {% else %}
      Log.warn { "SSL_CTX_get_security_level not supported" }
      0
    {% end %}
  end

  # Sets the security level used by this TLS context. The default system
  # security level might disable some ciphers.
  #
  # * https://www.openssl.org/docs/man1.1.1/man3/SSL_CTX_set_security_level.html
  # * https://wiki.debian.org/ContinuousIntegration/TriagingTips/openssl-1.1.1
  def security_level=(value : Int32)
    {% if LibSSL.has_method?(:ssl_ctx_set_security_level) %}
      LibSSL.ssl_ctx_set_security_level(@handle, value)
    {% else %}
      Log.warn { "SSL_CTX_set_security_level not supported" }
    {% end %}
    value
  end

  # Adds a temporary ECDH key curve to the TLS context. This is required to
  # enable the EECDH cipher suites. By default the prime256 curve will be used.
  def set_tmp_ecdh_key(curve = LibCrypto::NID_X9_62_prime256v1) : Nil
    key = LibCrypto.ec_key_new_by_curve_name(curve)
    raise OpenSSL::Error.new("ec_key_new_by_curve_name") if key.null?
    LibSSL.ssl_ctx_ctrl(@handle, LibSSL::SSL_CTRL_SET_TMP_ECDH, 0, key)
    LibCrypto.ec_key_free(key)
  end

  # Returns the current modes set on the TLS context.
  def modes : LibSSL::Modes
    OpenSSL::SSL::Modes.new LibSSL.ssl_ctx_ctrl(@handle, LibSSL::SSL_CTRL_MODE, 0, nil)
  end

  # Adds modes to the TLS context.
  def add_modes(mode : OpenSSL::SSL::Modes)
    OpenSSL::SSL::Modes.new LibSSL.ssl_ctx_ctrl(@handle, LibSSL::SSL_CTRL_MODE, mode, nil)
  end

  # Removes modes from the TLS context.
  def remove_modes(mode : OpenSSL::SSL::Modes)
    OpenSSL::SSL::Modes.new LibSSL.ssl_ctx_ctrl(@handle, LibSSL::SSL_CTRL_CLEAR_MODE, mode, nil)
  end

  # Returns the current options set on the TLS context.
  def options : LibSSL::Options
    opts = {% if LibSSL.has_method?(:ssl_ctx_get_options) %}
             LibSSL.ssl_ctx_get_options(@handle)
           {% else %}
             LibSSL.ssl_ctx_ctrl(@handle, LibSSL::SSL_CTRL_OPTIONS, 0, nil)
           {% end %}
    OpenSSL::SSL::Options.new(opts)
  end

  # Adds options to the TLS context.
  #
  # Example:
  # ```
  # context.add_options(
  #   OpenSSL::SSL::Options::ALL |       # various workarounds
  #   OpenSSL::SSL::Options::NO_SSL_V2 | # disable overly deprecated SSLv2
  #   OpenSSL::SSL::Options::NO_SSL_V3   # disable deprecated SSLv3
  # )
  # ```
  def add_options(options : OpenSSL::SSL::Options)
    opts = {% if LibSSL.has_method?(:ssl_ctx_set_options) %}
             LibSSL.ssl_ctx_set_options(@handle, options)
           {% else %}
             LibSSL.ssl_ctx_ctrl(@handle, LibSSL::SSL_CTRL_OPTIONS, options, nil)
           {% end %}
    OpenSSL::SSL::Options.new(opts)
  end

  # Removes options from the TLS context.
  #
  # Example:
  # ```
  # context.remove_options(OpenSSL::SSL::Options::NO_SSL_V3)
  # ```
  def remove_options(options : OpenSSL::SSL::Options)
    opts = {% if LibSSL.has_method?(:ssl_ctx_clear_options) %}
             LibSSL.ssl_ctx_clear_options(@handle, options)
           {% else %}
             LibSSL.ssl_ctx_ctrl(@handle, LibSSL::SSL_CTRL_CLEAR_OPTIONS, options, nil)
           {% end %}
    OpenSSL::SSL::Options.new(opts)
  end

  # Returns the current verify mode. See the `SSL_CTX_set_verify(3)` manpage for more details.
  def verify_mode : LibSSL::VerifyMode
    LibSSL.ssl_ctx_get_verify_mode(@handle)
  end

  # Sets the verify mode. See the `SSL_CTX_set_verify(3)` manpage for more details.
  def verify_mode=(mode : OpenSSL::SSL::VerifyMode)
    LibSSL.ssl_ctx_set_verify(@handle, mode, nil)
  end

  @alpn_protocol = Pointer(Void).null

  # Specifies an ALPN protocol to negotiate with the remote endpoint. This is
  # required to negotiate HTTP/2 with browsers, since browser vendors decided
  # not to implement HTTP/2 over insecure connections.
  #
  # Example:
  # ```
  # context.alpn_protocol = "h2"
  # ```
  def alpn_protocol=(protocol : String)
    proto = Bytes.new(protocol.bytesize + 1)
    proto[0] = protocol.bytesize.to_u8
    protocol.to_slice.copy_to(proto.to_unsafe + 1, protocol.bytesize)
    self.alpn_protocol = proto
  end

  # Sets this context verify param to the default one of the given name.
  #
  # Depending on the OpenSSL version, the available defaults are
  # `default`, `pkcs7`, `smime_sign`, `ssl_client` and `ssl_server`.
  def default_verify_param=(name : String)
    {% if LibSSL.has_method?(:x509_verify_param_lookup) %}
      param = LibCrypto.x509_verify_param_lookup(name)
      raise ArgumentError.new("#{name} is an unsupported default verify param") unless param
      ret = LibSSL.ssl_ctx_set1_param(@handle, param)
      raise OpenSSL::Error.new("SSL_CTX_set1_param") unless ret == 1
    {% else %}
      raise NotImplementedError.new("LibSSL.x509_verify_param_lookup")
    {% end %}
  end

  # Sets the given `OpenSSL::SSL::X509VerifyFlags` in this context, additionally to
  # the already set ones.
  def add_x509_verify_flags(flags : OpenSSL::SSL::X509VerifyFlags)
    {% if LibSSL.has_method?(:x509_verify_param_set_flags) %}
      param = LibSSL.ssl_ctx_get0_param(@handle)
      ret = LibCrypto.x509_verify_param_set_flags(param, flags)
      raise OpenSSL::Error.new("X509_VERIFY_PARAM_set_flags)") unless ret == 1
    {% else %}
      raise NotImplementedError.new("LibSSL.x509_verify_param_set_flags")
    {% end %}
  end

  def to_unsafe
    @handle
  end

  private def self.from_hash(params)
    context = new
    if key = params["key"]?
      context.private_key = key
    else
      raise ArgumentError.new("Invalid SSL context: missing private key ('key=')")
    end

    if cert = params["cert"]?
      context.certificate_chain = cert
    else
      raise ArgumentError.new("Invalid SSL context: missing certificate ('cert=')")
    end

    case verify_mode = params["verify_mode"]?
    when "peer"
      context.verify_mode = OpenSSL::SSL::VerifyMode::PEER
    when "force-peer"
      context.verify_mode = OpenSSL::SSL::VerifyMode::PEER | OpenSSL::SSL::VerifyMode::FAIL_IF_NO_PEER_CERT
    when "none"
      context.verify_mode = OpenSSL::SSL::VerifyMode::NONE
    when nil
      # use default
    else
      raise ArgumentError.new("Invalid SSL context: unknown verify mode #{verify_mode.inspect}")
    end

    if ca = params["ca"]?
      if File.directory?(ca)
        context.ca_certificates_path = ca
      else
        context.ca_certificates = ca
      end
    elsif context.verify_mode.peer? || context.verify_mode.fail_if_no_peer_cert?
      raise ArgumentError.new("Invalid SSL context: missing CA certificate ('ca=')")
    end

    context
  end
end
