# An OAuth consumer.
#
# For a quick example of how to authenticate an `HTTP::Client` with OAuth if
# you already have an access token, check the `OAuth` module description.
#
# This class also provides methods to get request tokens, build authorize URIs
# and get access tokens, as specified by [RFC 5849](https://tools.ietf.org/html/rfc5849).
#
# ### Example
#
# ```
# require "oauth"
#
# consumer_key = "some_key"
# consumer_secret = "some_secret"
# oauth_callback = "http://some.callback"
#
# # Create consumer, optionally pass custom URIs if needed,
# # if the request, authorize or access_token URIs are not the standard ones
# # (they can also be absolute URLs)
# consumer = OAuth::Consumer.new("api.example.com", consumer_key, consumer_secret)
#
# # Get a request token.
# # We probably need to save this somewhere to get it back in the
# # callback URL (saving token and secret should be enough)
# request_token = consumer.get_request_token(oauth_callback)
#
# # Build an authorize URI
# authorize_uri = consumer.get_authorize_uri(request_token, oauth_callback)
#
# # Redirect the user to `authorize_uri`...
# #
# # ...
# #
# # When http://some.callback is hit, once the user authorized the access,
# # we resume our logic to finally get an access token. The callback URL
# # should receive an `oauth_verifier` parameter that we need to use.
# oauth_verifier = request.params["oauth_verifier"]
#
# # Get the access token
# access_token = consumer.get_access_token(request_token, oauth_verifier)
#
# # Probably save the access token for reuse... This can be done
# # with `to_json` and `from_json`.
#
# # Use the token to authenticate an HTTP::Client
# client = HTTP::Client.new("api.example.com", tls: true)
# access_token.authenticate(client, consumer_key, consumer_secret)
#
# # And do requests as usual
# client.get "/some_path"
# ```
class OAuth::Consumer
  @tls : Bool | OpenSSL::SSL::Context::Client

  # Creates an OAuth consumer.
  #
  # Any or all of the customizable URIs *request_token_uri*, *authorize_uri* and
  # *access_token_uri* can be relative or absolute.
  # If they are relative, the given *host*, *port* and *scheme* will be used.
  # If they are absolute, the absolute URL will be used.
  def initialize(@host : String, @consumer_key : String, @consumer_secret : String,
                 @port : Int32? = nil,
                 @scheme : String = "https",
                 @request_token_uri : String = "/oauth/request_token",
                 @authorize_uri : String = "/oauth/authorize",
                 @access_token_uri : String = "/oauth/access_token",
                 tls : Nil | Bool | OpenSSL::SSL::Context::Client = nil)
    @tls = tls.nil? ? @scheme == "https" : tls
  end

  # Obtains a request token, also known as "temporary credentials", as specified by
  # [RFC 5849, Section 2.1](https://tools.ietf.org/html/rfc5849#section-2.1).
  #
  # Raises `OAuth::Error` if there was an error getting the request token.
  def get_request_token(oauth_callback = "oob") # : RequestToken
    post(nil, nil, {"oauth_callback" => oauth_callback}, @request_token_uri) do |response|
      RequestToken.from_response(response.body)
    end
  end

  # Returns an authorize URI from a given request token to redirect the user
  # to obtain an access token, as specified by
  # [RFC 5849, Section 2.2](https://tools.ietf.org/html/rfc5849#section-2.2).
  def get_authorize_uri(request_token, oauth_callback = nil) : String
    get_authorize_uri(request_token, oauth_callback) { }
  end

  # Returns an authorize URI from a given request token to redirect the user
  # to obtain an access token, as specified by
  # [RFC 5849, Section 2.2](https://tools.ietf.org/html/rfc5849#section-2.2).
  #
  # Yields an `URI::Params::Builder` to add extra parameters other than those
  # defined by the standard.
  def get_authorize_uri(request_token, oauth_callback = nil, &block : URI::Params::Builder ->) : String
    uri = URI.parse(@authorize_uri)

    # Use the default URI if it's not an absolute one
    unless uri.host
      uri = URI.new(@scheme, @host, @port, @authorize_uri)
    end

    uri.query = URI::Params.build do |form|
      form.add "oauth_token", request_token.token
      form.add "oauth_callback", oauth_callback if oauth_callback
      uri.query_params.each do |key, value|
        form.add key, value
      end
      yield form
    end

    uri.to_s
  end

  # Gets an access token from a previously obtained request token and an *oauth_verifier*
  # obtained from an authorize URI, as specified by
  # [RFC 5849, Section 2.3](https://tools.ietf.org/html/rfc5849#section-2.3).
  #
  # Raises `OAuth::Error` if there was an error getting the access token.
  def get_access_token(request_token, oauth_verifier, extra_params = nil) : AccessToken
    extra_params ||= {} of String => String
    extra_params["oauth_verifier"] = oauth_verifier
    post(request_token.token, request_token.secret, extra_params, @access_token_uri) do |response|
      AccessToken.from_response(response.body)
    end
  end

  # Authenticated an `HTTP::Client` to add an OAuth authorization header, as specified by
  # [RFC 5849, Section 3](https://tools.ietf.org/html/rfc5849#section-3).
  def authenticate(client : HTTP::Client, token : AccessToken) : Nil
    authenticate client, token.token, token.secret, nil
  end

  private def post(oauth_token, token_shared_secret, extra_params, target_uri, &)
    uri = URI.parse(target_uri)

    # If the target uri is absolute, we use that instead of the default values
    if uri.host
      client = HTTP::Client.new(uri)
      target_uri = uri.request_target
    else
      client = HTTP::Client.new @host, @port, tls: @tls
    end

    authenticate client, oauth_token, token_shared_secret, extra_params

    begin
      response = client.post target_uri
      yield response
    ensure
      client.close
    end
  end

  private def authenticate(client, token, token_secret, extra_params)
    OAuth.authenticate(client, token, token_secret, @consumer_key, @consumer_secret, extra_params)
  end

  private def handle_response(response, &)
    case response.status_code
    when 200, 201
      yield
    else
      raise OAuth::Error.new(response)
    end
  end
end
