require "../src/uri_sanitizer"
require "spec"
require "uri"

private def assert_sanitize(source : String, expected : String? = source, sanitizer = Sanitize::URISanitizer.new, *, file = __FILE__, line = __LINE__)
  if expected
    expected = URI.parse(expected)
  end
  sanitizer.sanitize(URI.parse(source)).should eq(expected), file: file, line: line
end

describe Sanitize::URISanitizer do
  describe "#accepted_schemes" do
    it "has default value" do
      Sanitize::URISanitizer.new.accepted_schemes.should eq Set{"http", "https", "mailto", "tel"}
    end

    it "accepts minimal schemes" do
      assert_sanitize("http://example.com")
      assert_sanitize("https://example.com")
      assert_sanitize("mailto:mail@example.com")
      assert_sanitize("tel:example.com")
    end

    it "refutes unsafe schemes" do
      assert_sanitize("javascript:alert();", nil)
      assert_sanitize("ssh:git@github.com", nil)
    end

    it "custom schemes" do
      sanitizer = Sanitize::URISanitizer.new
      sanitizer.accept_scheme "javascript"
      assert_sanitize("javascript:alert();", sanitizer: sanitizer)
    end

    it "can be disabled" do
      sanitizer = Sanitize::URISanitizer.new
      sanitizer.accepted_schemes = nil
      assert_sanitize("javascript:alert();", sanitizer: sanitizer)
      assert_sanitize("foo:bar", sanitizer: sanitizer)
    end
  end

  describe "#base_url" do
    it "disabled by default" do
      Sanitize::URISanitizer.new.base_url.should be_nil
      assert_sanitize("foo")
    end

    it "set to absolute URL" do
      sanitizer = Sanitize::URISanitizer.new
      sanitizer.base_url = URI.parse("https://example.com/base/")

      assert_sanitize("foo", "https://example.com/base/foo", sanitizer: sanitizer)
      assert_sanitize("/foo", "https://example.com/foo", sanitizer: sanitizer)
    end

    it "doesn't base fragment-only URLs" do
      sanitizer = Sanitize::URISanitizer.new
      sanitizer.base_url = URI.parse("https://example.com/base/")

      assert_sanitize("#foo", sanitizer: sanitizer)
      assert_sanitize("#", sanitizer: sanitizer)
      assert_sanitize("https:#", sanitizer: sanitizer)
      assert_sanitize("?#foo", "https://example.com/base/?#foo", sanitizer: sanitizer)
      assert_sanitize("/#", "https://example.com/#", sanitizer: sanitizer)
      assert_sanitize("https://#", "https://#", sanitizer: sanitizer)

      sanitizer.resolve_fragment_urls = true
      assert_sanitize("#foo", "https://example.com/base/#foo", sanitizer: sanitizer)
      assert_sanitize("#", "https://example.com/base/#", sanitizer: sanitizer)
      assert_sanitize("https:#", "https:#", sanitizer: sanitizer)
    end
  end

  describe "#accepted_hosts" do
    it "disabled by default" do
      Sanitize::URISanitizer.new.accepted_hosts.should be_nil
    end

    it "restricts hosts" do
      sanitizer = Sanitize::URISanitizer.new
      sanitizer.accepted_hosts = Set{"foo.example.com"}
      assert_sanitize("http://foo.example.com", sanitizer: sanitizer)
      assert_sanitize("http://bar.example.com", nil, sanitizer: sanitizer)
      assert_sanitize("http://example.com", nil, sanitizer: sanitizer)
      assert_sanitize("http://foo.foo.example.com", nil, sanitizer: sanitizer)
      assert_sanitize("foo", sanitizer: sanitizer)
    end

    it "works with base_url" do
      sanitizer = Sanitize::URISanitizer.new
      sanitizer.accepted_hosts = Set{"foo.example.com"}
      sanitizer.base_url = URI.parse("http://bar.example.com/")
      assert_sanitize("foo", "http://bar.example.com/foo", sanitizer: sanitizer)
      assert_sanitize("http://bar.example.com/foo", nil, sanitizer: sanitizer)
    end
  end

  describe "#rejected_hosts" do
    it "disabled by default" do
      Sanitize::URISanitizer.new.rejected_hosts.should be_a(Set(String))
    end

    it "restricts hosts" do
      sanitizer = Sanitize::URISanitizer.new
      sanitizer.rejected_hosts = Set{"bar.example.com"}
      assert_sanitize("http://foo.example.com", sanitizer: sanitizer)
      assert_sanitize("http://bar.example.com", nil, sanitizer: sanitizer)
      assert_sanitize("http://example.com", sanitizer: sanitizer)
      assert_sanitize("http://bar.bar.example.com", sanitizer: sanitizer)
      assert_sanitize("foo", sanitizer: sanitizer)
    end

    it "works with base_url" do
      sanitizer = Sanitize::URISanitizer.new
      sanitizer.rejected_hosts = Set{"foo.example.com"}
      sanitizer.base_url = URI.parse("http://foo.example.com/")
      assert_sanitize("foo", "http://foo.example.com/foo", sanitizer: sanitizer)
      assert_sanitize("http://foo.example.com/foo", nil, sanitizer: sanitizer)
    end

    it "overrides accepted_hosts" do
      sanitizer = Sanitize::URISanitizer.new
      sanitizer.rejected_hosts = Set{"foo.example.com"}
      sanitizer.accepted_hosts = Set{"foo.example.com"}
      assert_sanitize("http://foo.example.com/foo", nil, sanitizer: sanitizer)
    end
  end
end
