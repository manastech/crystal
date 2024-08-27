require "uri"

# A `URISanitizer` is used to validate and transform a URI based on specified
# rules.
class Sanitize::URISanitizer
  # Specifies a whitelist of URI schemes this sanitizer accepts.
  #
  # If empty, no schemes are accepted (i.e. only relative URIs are valid).
  # If `nil`, all schemes are accepted (this setting is potentially dangerous).
  #
  # Relative URIs are not affected by this setting.
  property accepted_schemes : Set(String)?

  # Specifies a whitelist of hosts this sanitizer accepts.
  #
  # If empty, no hosts are accepted (i.e. only relative URIs are valid).
  # If `nil`, all hosts are accepted (default).
  #
  # The blacklist `rejected_hosts` has precedence over this whitelist.
  property accepted_hosts : Set(String)?

  # Specifies a blacklist of hosts this sanitizer rejects.
  #
  # If empty, no hosts are rejected.
  #
  # This blacklist has precedence over the whitelist `accepted_hosts`.
  property rejected_hosts : Set(String) = Set(String).new

  # Specifies a base URL all relative URLs are resolved against.
  #
  # If `nil`, relative URLs are not resolved.
  property base_url : URI?

  # Configures whether fragment-only URIs are resolved on `base_url`.
  #
  # ```
  # sanitizer = Sanitize::URISanitizer.new
  # sanitizer.base_url = URI.parse("https://example.com/base/")
  # sanitizer.sanitize(URI.parse("#foo")) # => "#foo"
  #
  # sanitizer.resolve_fragment_urls = true
  # sanitizer.sanitize(URI.parse("#foo")) # => "https://example.com/base/#foo"
  # ```
  property resolve_fragment_urls = false

  def initialize(@accepted_schemes : Set(String)? = Set{"http", "https", "mailto", "tel"})
  end

  # Adds *scheme* to `accepted_schemes`.
  def accept_scheme(scheme : String)
    schemes = self.accepted_schemes ||= Set(String).new
    schemes << scheme
  end

  def sanitize(uri : URI) : URI?
    unless accepts_scheme?(uri.scheme)
      return nil
    end

    unless accepts_host?(uri.host)
      return nil
    end

    uri = resolve_base_url(uri)

    uri
  end

  def accepts_scheme?(scheme)
    if scheme.nil?
      return true
    end

    if accepted_schemes = self.accepted_schemes
      return accepted_schemes.includes?(scheme)
    end

    true
  end

  def accepts_host?(host)
    if host.nil?
      return true
    end

    return false if rejected_hosts.includes?(host)

    if accepted_hosts = self.accepted_hosts
      return false unless accepted_hosts.includes?(host)
    end

    true
  end

  def resolve_base_url(uri)
    if base_url = self.base_url
      unless uri.absolute? || (!resolve_fragment_urls && fragment_url?(uri))
        uri = base_url.resolve(uri)
      end
    end
    uri
  end

  private def fragment_url?(uri)
    uri.path.empty? && uri.host.nil? && uri.query.nil? && !uri.fragment.nil?
  end
end
