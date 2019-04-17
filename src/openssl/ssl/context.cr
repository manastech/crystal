require "uri/punycode"

abstract class OpenSSL::SSL::Context
  # :nodoc:
  def self.default_method
    {% if LibSSL::OPENSSL_VERSION_NUMBER >= 0x1_01_00_00_0 %}
      LibSSL.tls_method
    {% else %}
      LibSSL.sslv23_method
    {% end %}
  end

  # The list of secure ciphers (intermediate security) as of May 2016 as per
  # https://wiki.mozilla.org/Security/Server_Side_TLS
  CIPHERS = %w(
    ECDHE-ECDSA-CHACHA20-POLY1305
    ECDHE-RSA-CHACHA20-POLY1305
    ECDHE-ECDSA-AES128-GCM-SHA256
    ECDHE-RSA-AES128-GCM-SHA256
    ECDHE-ECDSA-AES256-GCM-SHA384
    ECDHE-RSA-AES256-GCM-SHA384
    DHE-RSA-AES128-GCM-SHA256
    DHE-RSA-AES256-GCM-SHA384
    ECDHE-ECDSA-AES128-SHA256
    ECDHE-RSA-AES128-SHA256
    ECDHE-ECDSA-AES128-SHA
    ECDHE-RSA-AES256-SHA384
    ECDHE-RSA-AES128-SHA
    ECDHE-ECDSA-AES256-SHA384
    ECDHE-ECDSA-AES256-SHA
    ECDHE-RSA-AES256-SHA
    DHE-RSA-AES128-SHA256
    DHE-RSA-AES128-SHA
    DHE-RSA-AES256-SHA256
    DHE-RSA-AES256-SHA
    ECDHE-ECDSA-DES-CBC3-SHA
    ECDHE-RSA-DES-CBC3-SHA
    EDH-RSA-DES-CBC3-SHA
    AES128-GCM-SHA256
    AES256-GCM-SHA384
    AES128-SHA256
    AES256-SHA256
    AES128-SHA
    AES256-SHA
    DES-CBC3-SHA
    !RC4
    !aNULL
    !eNULL
    !LOW
    !3DES
    !MD5
    !EXP
    !PSK
    !SRP
    !DSS
  ).join(' ')

  class Client < Context
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

    @hostname : String?

    def initialize(method : LibSSL::SSLMethod = Context.default_method)
      super(method)

      self.verify_mode = OpenSSL::SSL::VerifyMode::PEER
      {% if LibSSL::OPENSSL_VERSION_NUMBER >= 0x1_00_02_00_0 %}
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

    {% if LibSSL::OPENSSL_VERSION_NUMBER <= 0x1_00_01_00_0 %}
      # Wraps the original certificate verification to also validate the
      # hostname against the certificate configured Subject Alternate
      # Names or Common Name.
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
    {% end %}
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

      add_options(OpenSSL::SSL::Options::CIPHER_SERVER_PREFERENCE)
      {% if LibSSL::OPENSSL_VERSION_NUMBER >= 0x1_00_02_00_0 %}
      self.default_verify_param = "ssl_client"
      {% end %}

      set_tmp_ecdh_key(curve: LibCrypto::NID_X9_62_prime256v1)
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
  end

  protected def initialize(method : LibSSL::SSLMethod)
    @handle = LibSSL.ssl_ctx_new(method)
    raise OpenSSL::Error.new("SSL_CTX_new") if @handle.null?

    set_default_verify_paths

    add_options(OpenSSL::SSL::Options.flags(
      ALL,
      NO_SSL_V2,
      NO_SSL_V3,
      NO_SESSION_RESUMPTION_ON_RENEGOTIATION,
      SINGLE_ECDH_USE,
      SINGLE_DH_USE
    ))

    add_modes(OpenSSL::SSL::Modes.flags(AUTO_RETRY, RELEASE_BUFFERS))

    self.ciphers = CIPHERS
  end

  # Overriding initialize or new in the child classes as public methods,
  # makes it either impossible to access the parent versions or makes the parent
  # versions public too. So to provide insecure in the child classes, we need
  # a second constructor that we call from there without getting the
  # overridden ones of the childs.
  protected def _initialize_insecure(method : LibSSL::SSLMethod)
    @handle = LibSSL.ssl_ctx_new(method)
    raise OpenSSL::Error.new("SSL_CTX_new") if @handle.null?
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

  # Sets the default paths for `ca_certiifcates=` and `ca_certificates_path=`.
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

  # Specify the path to the private key to use. The key must in PEM format.
  # The key must correspond to the entity certificate set by `certificate_chain=`.
  def private_key=(file_path : String)
    ret = LibSSL.ssl_ctx_use_privatekey_file(@handle, file_path, LibSSL::SSLFileType::PEM)
    raise OpenSSL::Error.new("SSL_CTX_use_PrivateKey_file") unless ret == 1
  end

  # Specify a list of TLS ciphers to use or discard.
  def ciphers=(ciphers : String)
    ret = LibSSL.ssl_ctx_set_cipher_list(@handle, ciphers)
    raise OpenSSL::Error.new("SSL_CTX_set_cipher_list") if ret == 0
    ciphers
  end

  # Adds a temporary ECDH key curve to the TLS context. This is required to
  # enable the EECDH cipher suites. By default the prime256 curve will be used.
  def set_tmp_ecdh_key(curve = LibCrypto::NID_X9_62_prime256v1)
    key = LibCrypto.ec_key_new_by_curve_name(curve)
    raise OpenSSL::Error.new("ec_key_new_by_curve_name") if key.null?
    LibSSL.ssl_ctx_ctrl(@handle, LibSSL::SSL_CTRL_SET_TMP_ECDH, 0, key)
    LibCrypto.ec_key_free(key)
  end

  # Returns the current modes set on the TLS context.
  def modes
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
  def options
    opts = {% if LibSSL::OPENSSL_VERSION_NUMBER >= 0x1_01_00_00_0 %}
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
    opts = {% if LibSSL::OPENSSL_VERSION_NUMBER >= 0x1_01_00_00_0 %}
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
    opts = {% if LibSSL::OPENSSL_VERSION_NUMBER >= 0x1_01_00_00_0 %}
      LibSSL.ssl_ctx_clear_options(@handle, options)
    {% else %}
      LibSSL.ssl_ctx_ctrl(@handle, LibSSL::SSL_CTRL_CLEAR_OPTIONS, options, nil)
    {% end %}
    OpenSSL::SSL::Options.new(opts)
  end

  # Returns the current verify mode. See the `SSL_CTX_set_verify(3)` manpage for more details.
  def verify_mode
    LibSSL.ssl_ctx_get_verify_mode(@handle)
  end

  # Sets the verify mode. See the `SSL_CTX_set_verify(3)` manpage for more details.
  def verify_mode=(mode : OpenSSL::SSL::VerifyMode)
    LibSSL.ssl_ctx_set_verify(@handle, mode, nil)
  end

  {% if LibSSL::OPENSSL_VERSION_NUMBER >= 0x1_00_02_00_0 || LibSSL::LIBRESSL_VERSION_NUMBER >= 0x2_05_00_00_0 %}

  @alpn_protocol : Pointer(Void)?

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

  private def alpn_protocol=(protocol : Bytes)
    alpn_cb = ->(ssl : LibSSL::SSL, o : LibC::Char**, olen : LibC::Char*, i : LibC::Char*, ilen : LibC::Int, data : Void*) {
      proto = Box(Bytes).unbox(data)
      ret = LibSSL.ssl_select_next_proto(o, olen, proto, 2, i, ilen)
      if ret != LibSSL::OPENSSL_NPN_NEGOTIATED
        LibSSL::SSL_TLSEXT_ERR_NOACK
      else
        LibSSL::SSL_TLSEXT_ERR_OK
      end
    }
    @alpn_protocol = alpn_protocol = Box.box(protocol)
    LibSSL.ssl_ctx_set_alpn_select_cb(@handle, alpn_cb, alpn_protocol)
  end

  {% end %}

  {% if LibSSL::OPENSSL_VERSION_NUMBER >= 0x1_00_02_00_0 %}

  # Sets this context verify param to the default one of the given name.
  #
  # Depending on the OpenSSL version, the available defaults are
  # `default`, `pkcs7`, `smime_sign`, `ssl_client` and `ssl_server`.
  def default_verify_param=(name : String)
    param = LibCrypto.x509_verify_param_lookup(name)
    raise ArgumentError.new("#{name} is an unsupported default verify param") unless param
    ret = LibSSL.ssl_ctx_set1_param(@handle, param)
    raise OpenSSL::Error.new("SSL_CTX_set1_param") unless ret == 1
  end

  # Sets the given `OpenSSL::X509VerifyFlags` in this context, additionally to
  # the already set ones.
  def add_x509_verify_flags(flags : OpenSSL::X509VerifyFlags)
    param = LibSSL.ssl_ctx_get0_param(@handle)
    ret = LibCrypto.x509_verify_param_set_flags(param, flags)
    raise OpenSSL::Error.new("X509_VERIFY_PARAM_set_flags)") unless ret == 1
  end

  {% end %}

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
      context.verify_mode = OpenSSL::SSL::VerifyMode::FAIL_IF_NO_PEER_CERT
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
