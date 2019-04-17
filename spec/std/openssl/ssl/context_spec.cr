require "../../spec_helper"
require "openssl"
require "../../../support/finalize"

class OpenSSL::SSL::Context
  property key : Symbol?

  def finalize
    if key = self.key
      State.inc(key)
    end

    previous_def
  end
end

describe OpenSSL::SSL::Context do
  it "new for client" do
    context = OpenSSL::SSL::Context::Client.new

    (context.options & OpenSSL::SSL::Options::ALL).should eq(OpenSSL::SSL::Options::ALL)
    (context.options & OpenSSL::SSL::Options::NO_SSL_V2).should eq(OpenSSL::SSL::Options::NO_SSL_V2)
    (context.options & OpenSSL::SSL::Options::NO_SSL_V3).should eq(OpenSSL::SSL::Options::NO_SSL_V3)
    (context.options & OpenSSL::SSL::Options::NO_SESSION_RESUMPTION_ON_RENEGOTIATION).should eq(OpenSSL::SSL::Options::NO_SESSION_RESUMPTION_ON_RENEGOTIATION)
    (context.options & OpenSSL::SSL::Options::SINGLE_ECDH_USE).should eq(OpenSSL::SSL::Options::SINGLE_ECDH_USE)
    (context.options & OpenSSL::SSL::Options::SINGLE_DH_USE).should eq(OpenSSL::SSL::Options::SINGLE_DH_USE)

    context.modes.should eq(OpenSSL::SSL::Modes.flags(AUTO_RETRY, RELEASE_BUFFERS))
    context.verify_mode.should eq(OpenSSL::SSL::VerifyMode::PEER)

    OpenSSL::SSL::Context::Client.new(LibSSL.tlsv1_method)
  end

  it "new for server" do
    context = OpenSSL::SSL::Context::Server.new

    (context.options & OpenSSL::SSL::Options::ALL).should eq(OpenSSL::SSL::Options::ALL)
    (context.options & OpenSSL::SSL::Options::NO_SSL_V2).should eq(OpenSSL::SSL::Options::NO_SSL_V2)
    (context.options & OpenSSL::SSL::Options::NO_SSL_V3).should eq(OpenSSL::SSL::Options::NO_SSL_V3)
    (context.options & OpenSSL::SSL::Options::NO_SESSION_RESUMPTION_ON_RENEGOTIATION).should eq(OpenSSL::SSL::Options::NO_SESSION_RESUMPTION_ON_RENEGOTIATION)
    (context.options & OpenSSL::SSL::Options::SINGLE_ECDH_USE).should eq(OpenSSL::SSL::Options::SINGLE_ECDH_USE)
    (context.options & OpenSSL::SSL::Options::SINGLE_DH_USE).should eq(OpenSSL::SSL::Options::SINGLE_DH_USE)
    (context.options & OpenSSL::SSL::Options::CIPHER_SERVER_PREFERENCE).should eq(OpenSSL::SSL::Options::CIPHER_SERVER_PREFERENCE)

    context.modes.should eq(OpenSSL::SSL::Modes.flags(AUTO_RETRY, RELEASE_BUFFERS))
    context.verify_mode.should eq(OpenSSL::SSL::VerifyMode::NONE)

    OpenSSL::SSL::Context::Server.new(LibSSL.tlsv1_method)
  end

  it "insecure for client" do
    context = OpenSSL::SSL::Context::Client.insecure
    context.should be_a(OpenSSL::SSL::Context::Client)
    context.verify_mode.should eq(OpenSSL::SSL::VerifyMode::NONE)
    context.options.no_ssl_v3?.should_not be_true
    {% if LibSSL::OPENSSL_VERSION_NUMBER >= 0x1_01_01_00_0 %}
    context.modes.should eq(OpenSSL::SSL::Modes::AUTO_RETRY)
    {% else %}
    context.modes.should eq(OpenSSL::SSL::Modes::None)
    {% end %}

    OpenSSL::SSL::Context::Client.insecure(LibSSL.tlsv1_method)
  end

  it "insecure for server" do
    context = OpenSSL::SSL::Context::Server.insecure
    context.should be_a(OpenSSL::SSL::Context::Server)
    context.verify_mode.should eq(OpenSSL::SSL::VerifyMode::NONE)
    context.options.no_ssl_v3?.should_not be_true
    {% if LibSSL::OPENSSL_VERSION_NUMBER >= 0x1_01_01_00_0 %}
    context.modes.should eq(OpenSSL::SSL::Modes::AUTO_RETRY)
    {% else %}
    context.modes.should eq(OpenSSL::SSL::Modes::None)
    {% end %}

    OpenSSL::SSL::Context::Server.insecure(LibSSL.tlsv1_method)
  end

  it "sets certificate chain" do
    context = OpenSSL::SSL::Context::Client.new
    context.certificate_chain = datapath("openssl", "openssl.crt")
  end

  it "fails to set certificate chain" do
    context = OpenSSL::SSL::Context::Client.new
    expect_raises(OpenSSL::Error) { context.certificate_chain = datapath("nonexistent.crt") }
    expect_raises(OpenSSL::Error) { context.certificate_chain = datapath("test_file.txt") }
  end

  it "sets private key" do
    context = OpenSSL::SSL::Context::Client.new
    context.private_key = datapath("openssl", "openssl.key")
  end

  it "fails to set private key" do
    context = OpenSSL::SSL::Context::Client.new
    expect_raises(OpenSSL::Error) { context.private_key = datapath("nonexistent.key") }
    expect_raises(OpenSSL::Error) { context.private_key = datapath("test_file.txt") }
  end

  it "sets ciphers" do
    ciphers = "EDH+aRSA DES-CBC3-SHA !RC4"
    context = OpenSSL::SSL::Context::Client.new
    (context.ciphers = ciphers).should eq(ciphers)
  end

  it "adds temporary ecdh curve (P-256)" do
    context = OpenSSL::SSL::Context::Client.new
    context.set_tmp_ecdh_key
  end

  it "adds options" do
    context = OpenSSL::SSL::Context::Client.new
    context.remove_options(context.options) # reset
    default_options = context.options       # options we can't unset

    context.add_options(OpenSSL::SSL::Options::ALL)
      .should eq(default_options | OpenSSL::SSL::Options::ALL)

    context.add_options(OpenSSL::SSL::Options.flags(NO_SSL_V2, NO_SSL_V3))
      .should eq(OpenSSL::SSL::Options.flags(ALL, NO_SSL_V2, NO_SSL_V3))
  end

  it "removes options" do
    context = OpenSSL::SSL::Context::Client.insecure
    default_options = context.options
    context.add_options(OpenSSL::SSL::Options.flags(NO_TLS_V1, NO_SSL_V2))
    context.remove_options(OpenSSL::SSL::Options::NO_TLS_V1).should eq(default_options | OpenSSL::SSL::Options::NO_SSL_V2)
  end

  it "returns options" do
    context = OpenSSL::SSL::Context::Client.insecure
    default_options = context.options
    context.add_options(OpenSSL::SSL::Options.flags(ALL, NO_SSL_V2))
    context.options.should eq(default_options | OpenSSL::SSL::Options.flags(ALL, NO_SSL_V2))
  end

  it "adds modes" do
    context = OpenSSL::SSL::Context::Client.insecure
    context.add_modes(OpenSSL::SSL::Modes::AUTO_RETRY).should eq(OpenSSL::SSL::Modes::AUTO_RETRY)
    context.add_modes(OpenSSL::SSL::Modes::RELEASE_BUFFERS)
      .should eq(OpenSSL::SSL::Modes.flags(AUTO_RETRY, RELEASE_BUFFERS))
  end

  it "removes modes" do
    context = OpenSSL::SSL::Context::Client.insecure
    context.add_modes(OpenSSL::SSL::Modes.flags(AUTO_RETRY, RELEASE_BUFFERS))
    context.remove_modes(OpenSSL::SSL::Modes::AUTO_RETRY).should eq(OpenSSL::SSL::Modes::RELEASE_BUFFERS)
  end

  it "returns modes" do
    context = OpenSSL::SSL::Context::Client.insecure
    context.add_modes(OpenSSL::SSL::Modes.flags(AUTO_RETRY, RELEASE_BUFFERS))
    context.modes.should eq(OpenSSL::SSL::Modes.flags(AUTO_RETRY, RELEASE_BUFFERS))
  end

  it "sets the verify mode" do
    context = OpenSSL::SSL::Context::Client.new
    context.verify_mode = OpenSSL::SSL::VerifyMode::NONE
    context.verify_mode.should eq(OpenSSL::SSL::VerifyMode::NONE)
    context.verify_mode = OpenSSL::SSL::VerifyMode::PEER
    context.verify_mode.should eq(OpenSSL::SSL::VerifyMode::PEER)
  end

  {% if LibSSL::OPENSSL_VERSION_NUMBER >= 0x1_00_02_00_0 || LibSSL::LIBRESSL_VERSION_NUMBER >= 0x2_05_00_00__0 %}
  it "alpn_protocol=" do
    context = OpenSSL::SSL::Context::Client.insecure
    context.alpn_protocol = "h2"
  end
  {% end %}

  it "calls #finalize on insecure client context" do
    assert_finalizes(:insecure_client_ctx) { OpenSSL::SSL::Context::Client.insecure }
  end

  it "calls #finalize on insecure server context" do
    assert_finalizes(:insecure_server_ctx) { OpenSSL::SSL::Context::Server.insecure }
  end

  describe ".from_hash" do
    it "builds" do
      private_key = datapath("openssl", "openssl.key")
      certificate = datapath("openssl", "openssl.crt")

      context = OpenSSL::SSL::Context::Client.from_hash({"key" => private_key, "cert" => certificate, "verify_mode" => "none"})
      context.verify_mode.should eq OpenSSL::SSL::VerifyMode::NONE

      context = OpenSSL::SSL::Context::Server.from_hash({"key" => private_key, "cert" => certificate})
      context.verify_mode.should eq OpenSSL::SSL::VerifyMode::NONE

      context = OpenSSL::SSL::Context::Client.from_hash({"key" => private_key, "cert" => certificate, "ca" => certificate})
      context.verify_mode.should eq OpenSSL::SSL::VerifyMode::PEER

      context = OpenSSL::SSL::Context::Client.from_hash({"key" => private_key, "cert" => certificate, "ca" => File.dirname(certificate)})
      context.verify_mode.should eq OpenSSL::SSL::VerifyMode::PEER
    end

    it "errors" do
      private_key = datapath("openssl", "openssl.key")
      certificate = datapath("openssl", "openssl.crt")
      nonexistent = datapath("openssl", "nonexistent")

      expect_raises(ArgumentError, "missing private key") do
        OpenSSL::SSL::Context::Client.from_hash({} of String => String)
      end
      expect_raises(OpenSSL::Error, /SSL_CTX_use_PrivateKey_file: .+No such file or directory/) do
        OpenSSL::SSL::Context::Client.from_hash({"key" => nonexistent})
      end
      expect_raises(ArgumentError, "missing certificate") do
        OpenSSL::SSL::Context::Client.from_hash({"key" => private_key})
      end
      expect_raises(OpenSSL::Error, /SSL_CTX_use_certificate_chain_file: .+No such file or directory/) do
        OpenSSL::SSL::Context::Client.from_hash({"key" => private_key, "cert" => nonexistent})
      end
      expect_raises(ArgumentError, "Invalid SSL context: missing CA certificate") do
        OpenSSL::SSL::Context::Client.from_hash({"key" => private_key, "cert" => certificate})
      end
      expect_raises(ArgumentError, %(Invalid SSL context: unknown verify mode "foo")) do
        OpenSSL::SSL::Context::Client.from_hash({"key" => private_key, "cert" => certificate, "verify_mode" => "foo"})
      end
      expect_raises(ArgumentError, "Invalid SSL context: missing CA certificate") do
        OpenSSL::SSL::Context::Client.from_hash({"key" => private_key, "cert" => certificate, "verify_mode" => "peer"})
      end
      expect_raises(OpenSSL::Error, /SSL_CTX_load_verify_locations: .+No such file or directory/) do
        OpenSSL::SSL::Context::Client.from_hash({"key" => private_key, "cert" => certificate, "ca" => nonexistent})
      end
    end
  end
end
