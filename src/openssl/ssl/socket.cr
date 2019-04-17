abstract class OpenSSL::SSL::Socket < IO
  class Client < Socket
    def initialize(io, context : Context::Client = Context::Client.new, sync_close : Bool = false, hostname : String? = nil)
      super(io, context, sync_close)

      if hostname
        # Macro from OpenSSL: SSL_ctrl(s,SSL_CTRL_SET_TLSEXT_HOSTNAME,TLSEXT_NAMETYPE_host_name,(char *)name)
        LibSSL.ssl_ctrl(
          @ssl,
          LibSSL::SSLCtrl::SET_TLSEXT_HOSTNAME,
          LibSSL::TLSExt::NAMETYPE_host_name,
          hostname.to_unsafe.as(Pointer(Void))
        )

        {% if LibSSL::OPENSSL_VERSION_NUMBER >= 0x1_00_02_00_0 %}
          param = LibSSL.ssl_get0_param(@ssl)

          if ::Socket.ip?(hostname)
            unless LibCrypto.x509_verify_param_set1_ip_asc(param, hostname) == 1
              raise OpenSSL::Error.new("X509_VERIFY_PARAM_set1_ip_asc")
            end
          else
            unless LibCrypto.x509_verify_param_set1_host(param, hostname, 0) == 1
              raise OpenSSL::Error.new("X509_VERIFY_PARAM_set1_host")
            end
          end
        {% else %}
          context.set_cert_verify_callback(hostname)
        {% end %}
      end

      ret = LibSSL.ssl_connect(@ssl)
      unless ret == 1
        raise OpenSSL::SSL::Error.new(@ssl, ret, "SSL_connect")
      end
    end

    def self.open(io, context : Context::Client = Context::Client.new, sync_close : Bool = false, hostname : String? = nil)
      socket = new(io, context, sync_close, hostname)

      begin
        yield socket
      ensure
        socket.close
      end
    end
  end

  class Server < Socket
    def initialize(io, context : Context::Server = Context::Server.new, sync_close : Bool = false)
      super(io, context, sync_close)

      ret = LibSSL.ssl_accept(@ssl)
      unless ret == 1
        io.close if sync_close
        raise OpenSSL::SSL::Error.new(@ssl, ret, "SSL_accept")
      end
    end

    def self.open(io, context : Context::Server = Context::Server.new, sync_close : Bool = false)
      socket = new(io, context, sync_close)

      begin
        yield socket
      ensure
        socket.close
      end
    end
  end

  include IO::Buffered

  # If `#sync_close?` is `true`, closing this socket will
  # close the underlying IO.
  property? sync_close : Bool

  getter? closed : Bool

  protected def initialize(io, context : Context, @sync_close : Bool = false)
    @closed = false

    @ssl = LibSSL.ssl_new(context)
    unless @ssl
      raise OpenSSL::Error.new("SSL_new")
    end

    # Since OpenSSL::SSL::Socket is buffered it makes no
    # sense to wrap a IO::Buffered with buffering activated.
    if io.is_a?(IO::Buffered)
      io.sync = true
      io.read_buffering = false
    end

    @bio = BIO.new(io)
    LibSSL.ssl_set_bio(@ssl, @bio, @bio)
  end

  def finalize
    LibSSL.ssl_free(@ssl)
  end

  def unbuffered_read(slice : Bytes)
    check_open

    count = slice.size
    return 0 if count == 0

    LibSSL.ssl_read(@ssl, slice.pointer(count), count).tap do |bytes|
      if bytes <= 0 && !LibSSL.ssl_get_error(@ssl, bytes).zero_return?
        raise OpenSSL::SSL::Error.new(@ssl, bytes, "SSL_read")
      end
    end
  end

  def unbuffered_write(slice : Bytes)
    check_open

    return if slice.empty?

    count = slice.size
    bytes = LibSSL.ssl_write(@ssl, slice.pointer(count), count)
    unless bytes > 0
      raise OpenSSL::SSL::Error.new(@ssl, bytes, "SSL_write")
    end
    nil
  end

  def unbuffered_flush
    @bio.io.flush
  end

  {% if LibSSL::OPENSSL_VERSION_NUMBER >= 0x1_00_02_00_0 || LibSSL::LIBRESSL_VERSION_NUMBER >= 0x2_05_00_00_0 %}
  # Returns the negotiated ALPN protocol (eg: `"h2"`) of `nil` if no protocol was
  # negotiated.
  def alpn_protocol
    LibSSL.ssl_get0_alpn_selected(@ssl, out protocol, out len)
    String.new(protocol, len) unless protocol.null?
  end
  {% end %}

  def unbuffered_close
    return if @closed
    @closed = true

    begin
      loop do
        begin
          ret = LibSSL.ssl_shutdown(@ssl)
          break if ret == 1
          raise OpenSSL::SSL::Error.new(@ssl, ret, "SSL_shutdown") if ret < 0
        rescue e : OpenSSL::SSL::Error
          case e.error
          when .want_read?, .want_write?
            # Ignore, shutdown did not complete yet
          when .syscall?
            # OpenSSL claimed an underlying syscall failed, but that didn't set any error state,
            # assume we're done
            break
          else
            raise e
          end
        end

        # ret == 0, retry, shutdown is not complete yet
      end
    rescue IO::Error
    ensure
      @bio.io.close if @sync_close
    end
  end

  def unbuffered_rewind
    raise IO::Error.new("Can't rewind OpenSSL::SSL::Socket::Client")
  end

  # Returns the hostname provided through Server Name Indication (SNI)
  def hostname : String?
    if host_name = LibSSL.ssl_get_servername(@ssl, LibSSL::TLSExt::NAMETYPE_host_name)
      String.new(host_name)
    end
  end

  def local_address
    io = @bio.io
    io.responds_to?(:local_address) ? io.local_address : nil
  end

  def remote_address
    io = @bio.io
    io.responds_to?(:remote_address) ? io.remote_address : nil
  end
end
