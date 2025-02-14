require "spec"
require "uri"
require "uri/json"
require "uri/yaml"
require "spec/helpers/string"

private def assert_uri(string, file = __FILE__, line = __LINE__, **args)
  it "`#{string}`", file, line do
    URI.parse(string).should eq URI.new(**args)
    URI.parse(string).to_s.should eq string
  end
end

# rearrange parameters for `assert_prints`
{% for method in %w(encode encode_www_form decode decode_www_form) %}
  private def uri_{{ method.id }}(string, **options)
    URI.{{ method.id }}(string, **options)
  end

  private def uri_{{ method.id }}(io : IO, string, **options)
    URI.{{ method.id }}(string, io, **options)
  end

  private def it_{{ method.gsub(/code/, "codes").id }}(string, expected_result, file = __FILE__, line = __LINE__, **options)
    it "{{ method[0...6].id }}s #{string.inspect}", file: file, line: line do
      assert_prints uri_{{ method.id }}(string, **options), expected_result, file: file, line: line
    end
  end
{% end %}

# This helper method is used in the specs for #relativize and also ensures the
# reversibility of #relativize and #resolve.
private def assert_relativize(base, uri, relative)
  base = URI.parse(base)
  relative = URI.parse(relative)
  base.relativize(uri).should eq relative

  # Reversibility is only guaranteed on normalized URIs
  uri = URI.parse(uri).normalize
  base.normalize!
  relative.normalize!
  base.relativize(base.resolve(relative)).should eq relative
  base.resolve(base.relativize(uri)).should eq uri
end

describe "URI" do
  describe ".parse" do
    # scheme
    assert_uri("http:", scheme: "http")
    it { URI.parse("HttP:").should eq(URI.new(scheme: "http")) }

    # host
    assert_uri("http://www.example.com", scheme: "http", host: "www.example.com")
    assert_uri("http://www.foo-bar.example.com", scheme: "http", host: "www.foo-bar.example.com")
    assert_uri("http://www.example.com:81", scheme: "http", host: "www.example.com", port: 81)
    assert_uri("http://[::1]:81", scheme: "http", host: "[::1]", port: 81)
    assert_uri("http://192.0.2.16:81", scheme: "http", host: "192.0.2.16", port: 81)
    it { URI.parse("http://[fe80::1%en0]:8080/").should eq(URI.new(scheme: "http", host: "[fe80::1%en0]", port: 8080, path: "/")) }
    assert_uri("http://[fe80::1%25en0]:8080/", scheme: "http", host: "[fe80::1%en0]", port: 8080, path: "/")
    assert_uri("mysql://a,b,c/bar", scheme: "mysql", host: "a,b,c", path: "/bar")
    assert_uri("scheme://!$&'()*+,;=hello!:12/path", scheme: "scheme", host: "!$&'()*+,;=hello!", port: 12, path: "/path")
    it { URI.parse("http://hello.世界.com").should eq(URI.new(scheme: "http", host: "hello.世界.com")) }
    assert_uri("tcp://[2020::2020:20:2020:2020%25Windows%20Loves%20Spaces]:2020", scheme: "tcp", host: "[2020::2020:20:2020:2020%Windows Loves Spaces]", port: 2020)

    # host with trailing slash
    assert_uri("http://www.example.com/", scheme: "http", host: "www.example.com", path: "/")
    assert_uri("http://www.example.com:81/", scheme: "http", host: "www.example.com", port: 81, path: "/")
    assert_uri("http://[::1]:81/", scheme: "http", host: "[::1]", port: 81, path: "/")
    assert_uri("http://192.0.2.16:81/", scheme: "http", host: "192.0.2.16", port: 81, path: "/")

    # preserves fully-qualified host with trailing dot
    assert_uri("https://example.com./", scheme: "https", host: "example.com.", path: "/")
    assert_uri("https://example.com.:8443/", scheme: "https", host: "example.com.", port: 8443, path: "/")

    # port
    it { URI.parse("http://192.168.0.2:/foo").should eq URI.new(scheme: "http", host: "192.168.0.2", path: "/foo") }

    # path
    assert_uri("http://www.example.com/foo", scheme: "http", host: "www.example.com", path: "/foo")
    assert_uri("http:.", scheme: "http", path: ".")
    assert_uri("http:..", scheme: "http", path: "..")
    assert_uri("http://host/!$&'()*+,;=:@[hello]", scheme: "http", host: "host", path: "/!$&'()*+,;=:@[hello]")
    assert_uri("http://example.com//foo", scheme: "http", host: "example.com", path: "//foo")
    assert_uri("///foo", host: "", path: "/foo")

    # query
    assert_uri("http://www.example.com/foo?q=1", scheme: "http", host: "www.example.com", path: "/foo", query: "q=1")
    assert_uri("http://www.example.com/foo?", scheme: "http", host: "www.example.com", path: "/foo", query: "")
    assert_uri("?q=1", query: "q=1")
    assert_uri("?q=1?", query: "q=1?")
    assert_uri("?a+b=c%2Bd", query: "a+b=c%2Bd")
    assert_uri("?query=http://example.com", query: "query=http://example.com")

    # userinfo
    assert_uri("https://alice:pa55w0rd@www.example.com", scheme: "https", host: "www.example.com", user: "alice", password: "pa55w0rd")
    assert_uri("https://alice@www.example.com", scheme: "https", host: "www.example.com", user: "alice", password: nil)
    assert_uri("https://alice:@www.example.com", scheme: "https", host: "www.example.com", user: "alice", password: "")
    assert_uri("https://%3AD:%40_%40@www.example.com", scheme: "https", host: "www.example.com", user: ":D", password: "@_@")

    pending "unescaped @ in user/password should not confuse host" do
      assert_uri("http://j@ne:password@example.com", scheme: "http", host: "example.com", user: "j@ne", password: "password")
      assert_uri("http://jane:p@ssword@example.com", scheme: "http", host: "example.com", user: "jane", password: "p@ssword")
    end

    # fragment
    assert_uri("https://www.example.com/#top", scheme: "https", host: "www.example.com", path: "/", fragment: "top")

    # relative URL
    assert_uri("/foo", path: "/foo")
    assert_uri("/foo?q=1", path: "/foo", query: "q=1")
    assert_uri("//foo", host: "foo")
    assert_uri("//user@foo/path?q=b", host: "foo", user: "user", path: "/path", query: "q=b")

    # various schemes
    assert_uri("mailto:foo@example.org", scheme: "mailto", path: "foo@example.org")
    assert_uri("news:comp.infosystems.www.servers.unix", scheme: "news", path: "comp.infosystems.www.servers.unix")
    assert_uri("tel:+1-816-555-1212", scheme: "tel", path: "+1-816-555-1212")
    assert_uri("urn:oasis:names:specification:docbook:dtd:xml:4.1.2", scheme: "urn", path: "oasis:names:specification:docbook:dtd:xml:4.1.2")
    assert_uri("telnet://192.0.2.16:80/", scheme: "telnet", host: "192.0.2.16", port: 80, path: "/")
    assert_uri("ldap://[2001:db8::7]/c=GB?objectClass?one", scheme: "ldap", host: "[2001:db8::7]", path: "/c=GB", query: "objectClass?one")
    assert_uri("magnet:?xt=urn:btih:c12fe1c06bba254a9dc9f519b335aa7c1367a88a&dn", scheme: "magnet", query: "xt=urn:btih:c12fe1c06bba254a9dc9f519b335aa7c1367a88a&dn")

    # opaque
    assert_uri("http:example.com/?q=foo", scheme: "http", path: "example.com/", query: "q=foo")

    # no hierarchical part
    assert_uri("http:", scheme: "http")
    assert_uri("http:?", scheme: "http", query: "")
    assert_uri("http:?#", scheme: "http", query: "", fragment: "")
    assert_uri("http:#", scheme: "http", fragment: "")
    assert_uri("http://", scheme: "http", host: "")
    assert_uri("http://?", scheme: "http", host: "", query: "")
    assert_uri("http://?#", scheme: "http", host: "", query: "", fragment: "")
    assert_uri("http://#", scheme: "http", host: "", fragment: "")

    # empty host, but port
    assert_uri("http://:8000", scheme: "http", host: "", port: 8000)
    assert_uri("http://:8000/foo", scheme: "http", host: "", port: 8000, path: "/foo")

    # empty host, but user
    assert_uri("http://user@", scheme: "http", host: "", user: "user")
    assert_uri("http://user@/foo", scheme: "http", host: "", user: "user", path: "/foo")

    # path with illegal characters
    assert_uri("foo/another@url/[]and{}", path: "foo/another@url/[]and{}")

    # complex examples
    assert_uri("http://user:pass@bitfission.com:8080/path?a=b#frag",
      scheme: "http", user: "user", password: "pass", host: "bitfission.com", port: 8080, path: "/path", query: "a=b", fragment: "frag")
    assert_uri("//user:pass@bitfission.com:8080/path?a=b#frag",
      user: "user", password: "pass", host: "bitfission.com", port: 8080, path: "/path", query: "a=b", fragment: "frag")
    assert_uri("/path?a=b#frag", path: "/path", query: "a=b", fragment: "frag")
    assert_uri("file://localhost/etc/fstab", scheme: "file", host: "localhost", path: "/etc/fstab")
    assert_uri("file:///etc/fstab", scheme: "file", host: "", path: "/etc/fstab")
    assert_uri("file:///C:/FooBar/Baz.txt", scheme: "file", host: "", path: "/C:/FooBar/Baz.txt")
    assert_uri("test:/test", scheme: "test", path: "/test")

    context "bad urls" do
      it { expect_raises(URI::Error) { URI.parse("http://some.com:8f80/path") } }
    end
  end

  describe ".new" do
    it "with query params" do
      URI.new(query: URI::Params.parse("foo=bar&foo=baz")).should eq URI.parse("?foo=bar&foo=baz")
    end
  end

  describe "#hostname" do
    it { URI.new("http", "www.example.com", path: "/foo").hostname.should eq("www.example.com") }
    it { URI.new("http", "[::1]", path: "/foo").hostname.should eq("::1") }
    it { URI.new(path: "/foo").hostname.should be_nil }
  end

  describe "#authority" do
    it { URI.new.authority.should be_nil }
    it { URI.new(scheme: "scheme").authority.should be_nil }
    it { URI.new(scheme: "scheme", host: "example.com").authority.should eq "example.com" }
    it { URI.new(scheme: "scheme", host: "example.com", port: 123).authority.should eq "example.com:123" }
    it { URI.new(scheme: "scheme", user: "user", host: "example.com").authority.should eq "user@example.com" }
    it { URI.new(scheme: "scheme", user: "user").authority.should eq "user@" }
    it { URI.new(scheme: "scheme", port: 123).authority.should eq ":123" }
    it { URI.new(scheme: "scheme", user: "user", port: 123).authority.should eq "user@:123" }
    it { URI.new(scheme: "scheme", user: "user", password: "pass", host: "example.com").authority.should eq "user:pass@example.com" }
    it { URI.new(scheme: "scheme", user: "user", password: "pass", host: "example.com", port: 123).authority.should eq "user:pass@example.com:123" }
    it { URI.new(scheme: "scheme", password: "pass", host: "example.com").authority.should eq "example.com" }
    it { URI.new(scheme: "scheme", path: "opaque").authority.should be_nil }
    it { URI.new(scheme: "scheme", path: "/path").authority.should be_nil }
  end

  describe "#request_target" do
    it { URI.new(path: "/foo").request_target.should eq("/foo") }
    it { URI.new.request_target.should eq("/") }
    it { URI.new(scheme: "https", host: "example.com").request_target.should eq("/") }
    it { URI.new(scheme: "https", host: "example.com", path: "/%2F/%2F/").request_target.should eq("/%2F/%2F/") }
    it { URI.new(scheme: "scheme", path: "opaque").request_target.should eq "opaque" }
    it { URI.new(scheme: "scheme", query: "foo=bar&foo=baz").request_target.should eq "?foo=bar&foo=baz" }

    it { URI.new(path: "/.//foo").request_target.should eq("/.//foo") }
    it { URI.new(path: "/foo", query: "q=1").request_target.should eq("/foo?q=1") }
    it { URI.new(path: "/", query: "q=1").request_target.should eq("/?q=1") }
    it { URI.new(query: "q=1").request_target.should eq("/?q=1") }
    it { URI.new(path: "/a%3Ab").request_target.should eq("/a%3Ab") }
    it { URI.new("scheme").request_target.should eq "" }

    it "does not add '?' to the end if the query params are empty" do
      uri = URI.parse("http://www.example.com/foo")
      uri.query = ""
      uri.request_target.should eq("/foo")
    end
  end

  describe "#absolute?" do
    it { URI.parse("http://www.example.com/foo").absolute?.should be_true }
    it { URI.parse("http://www.example.com").absolute?.should be_true }
    it { URI.parse("http://127.0.0.1").absolute?.should be_true }
    it { URI.parse("http://[::1]/").absolute?.should be_true }
    it { URI.parse("/foo").absolute?.should be_false }
    it { URI.parse("foo").absolute?.should be_false }
  end

  describe "#relative?" do
    it { URI.parse("/foo").relative?.should be_true }
  end

  describe "#normalize" do
    it "doesn't modify instance" do
      uri = URI.parse("HTTP://example.COM:80/./foo/../bar/")
      uri.normalize.should eq URI.parse("http://example.com/bar/")
      uri.should eq URI.parse("HTTP://example.COM:80/./foo/../bar/")
    end

    it "normalizes scheme" do
      URI.parse("HtTp://").normalize.should eq URI.parse("http://")
    end

    it "normalizes host" do
      URI.parse("http://FoO.cOm/").normalize.should eq URI.parse("http://foo.com/")
    end

    it "removes default port" do
      URI.new("http", "www.example.com", 80).normalize.to_s.should eq("http://www.example.com")
      URI.new("https", "www.example.com", 443).normalize.to_s.should eq("https://www.example.com")
      URI.new("ftp", "www.example.com", 21).normalize.to_s.should eq("ftp://www.example.com")
      URI.new("sftp", "www.example.com", 22).normalize.to_s.should eq("sftp://www.example.com")
      URI.new("ldap", "www.example.com", 389).normalize.to_s.should eq("ldap://www.example.com")
      URI.new("ldaps", "www.example.com", 636).normalize.to_s.should eq("ldaps://www.example.com")
    end

    it "removes dot notation from path" do
      URI.new(path: "../bar").normalize.path.should eq "bar"
      URI.new(path: "./bar").normalize.path.should eq "bar"
      URI.new(path: ".././bar").normalize.path.should eq "bar"
      URI.new(path: "/foo/./bar").normalize.path.should eq "/foo/bar"
      URI.new(path: "/bar/./").normalize.path.should eq "/bar/"
      URI.new(path: "/.").normalize.path.should eq "/"
      URI.new(path: "/bar/.").normalize.path.should eq "/bar/"
      URI.new(path: "/foo/../bar").normalize.path.should eq "/bar"
      URI.new(path: "/bar/../").normalize.path.should eq "/"
      URI.new(path: "/..").normalize.path.should eq "/"
      URI.new(path: "/bar/..").normalize.path.should eq "/"
      URI.new(path: "/foo/bar/..").normalize.path.should eq "/foo/"
      URI.new(path: ".").normalize.path.should eq ""
      URI.new(path: "..").normalize.path.should eq ""
    end

    it "prefixes relative path with colon with `./`" do
      URI.parse("./a:b").normalize.should eq URI.parse("./a:b")
      URI.parse("http:a:b").normalize.should eq URI.parse("http:./a:b")
    end
  end

  describe "#normalize!" do
    it "modifies the instance" do
      uri = URI.parse("HTTP://example.COM:80/./foo/../bar/")
      uri.normalize!
      uri.should eq URI.parse("http://example.com/bar/")
    end
  end

  describe "#opaque?" do
    it { URI.new.opaque?.should be_false }
    it { URI.new("foo").opaque?.should be_true }
    it { URI.new("foo", "example.com").opaque?.should be_false }
    it { URI.new("foo", "").opaque?.should be_false }
    it { URI.new("foo", path: "foo").opaque?.should be_true }
    it { URI.new("foo", path: "/foo").opaque?.should be_false }
  end

  describe "#userinfo" do
    it { URI.parse("http://www.example.com").userinfo.should be_nil }
    it { URI.parse("http://foo@www.example.com").userinfo.should eq("foo") }
    it { URI.parse("http://foo:bar@www.example.com").userinfo.should eq("foo:bar") }
    it { URI.new(user: "ä /", password: "ö :").userinfo.should eq("%C3%A4+%2F:%C3%B6+%3A") }
  end

  describe "#to_s" do
    it { assert_prints URI.new("http", "www.example.com").to_s, "http://www.example.com" }
    it { assert_prints URI.new("http", "www.example.com", 80).to_s, "http://www.example.com:80" }
    it { assert_prints URI.new("http", "www.example.com", user: "alice").to_s, "http://alice@www.example.com" }
    it { assert_prints URI.new("http", "www.example.com", user: "alice", password: "s3cr3t").to_s, "http://alice:s3cr3t@www.example.com" }
    it { assert_prints URI.new("http", "www.example.com", user: ":D").to_s, "http://%3AD@www.example.com" }
    it { assert_prints URI.new("http", "www.example.com", user: ":D", password: "@_@").to_s, "http://%3AD:%40_%40@www.example.com" }
    it { assert_prints URI.new("http", "www.example.com", user: "@al:ce", password: "s/cr3t").to_s, "http://%40al%3Ace:s%2Fcr3t@www.example.com" }
    it { assert_prints URI.new("http", "www.example.com", fragment: "top").to_s, "http://www.example.com#top" }
    it { assert_prints URI.new("http", "www.example.com", 80, "/hello").to_s, "http://www.example.com:80/hello" }
    it { assert_prints URI.new("http", "www.example.com", 80, "/hello", "a=1").to_s, "http://www.example.com:80/hello?a=1" }
    it { assert_prints URI.new("mailto", path: "foo@example.com").to_s, "mailto:foo@example.com" }
    it { assert_prints URI.new("file", path: "/foo.html").to_s, "file:/foo.html" }
    it { assert_prints URI.new("file", path: "foo.html").to_s, "file:foo.html" }
    it { assert_prints URI.new("file", host: "host", path: "/foo.html").to_s, "file://host/foo.html" }
    it { assert_prints URI.new(path: "/.//foo").to_s, "/.//foo" }
    it { assert_prints URI.new(host: "host", path: "//foo").to_s, "//host//foo" }

    it "preserves non-default port" do
      assert_prints URI.new("http", "www.example.com", 1234).to_s, "http://www.example.com:1234"
      assert_prints URI.new("https", "www.example.com", 1234).to_s, "https://www.example.com:1234"
      assert_prints URI.new("ftp", "www.example.com", 1234).to_s, "ftp://www.example.com:1234"
      assert_prints URI.new("sftp", "www.example.com", 1234).to_s, "sftp://www.example.com:1234"
      assert_prints URI.new("ldap", "www.example.com", 1234).to_s, "ldap://www.example.com:1234"
      assert_prints URI.new("ldaps", "www.example.com", 1234).to_s, "ldaps://www.example.com:1234"
    end

    it "preserves port for unknown scheme" do
      assert_prints URI.new("xyz", "www.example.com").to_s, "xyz://www.example.com"
      assert_prints URI.new("xyz", "www.example.com", 1234).to_s, "xyz://www.example.com:1234"
    end

    it "preserves port for nil scheme" do
      assert_prints URI.new(nil, "www.example.com", 1234).to_s, "//www.example.com:1234"
    end
  end

  describe "#query_params" do
    context "when there is no query parameters" do
      it "returns an empty instance of URI::Params" do
        uri = URI.parse("http://foo.com")
        uri.query_params.should be_a(URI::Params)
        uri.query_params.should eq(URI::Params.new)
      end
    end

    it "returns a URI::Params instance based on the query parameters" do
      expected_params = URI::Params{"id" => "30", "limit" => "5"}

      uri = URI.parse("http://foo.com?id=30&limit=5#time=1305298413")
      uri.query_params.should eq(expected_params)

      uri = URI.parse("?id=30&limit=5#time=1305298413")
      uri.query_params.should eq(expected_params)
    end
  end

  describe "#query_params=" do
    it "empty" do
      uri = URI.new
      params = URI::Params.new
      uri.query_params = params
      uri.query_params.should eq params
      uri.query.should eq ""
    end

    it "params with values" do
      uri = URI.new
      params = URI::Params.parse("foo=bar&foo=baz")
      uri.query_params = params
      uri.query_params.should eq params
      uri.query.should eq "foo=bar&foo=baz"
    end
  end

  describe "#update_query_params" do
    it "returns self" do
      expected_params = URI::Params{"id" => "30"}

      uri = URI.parse("http://foo.com?id=30&limit=5#time=1305298413")
      uri.update_query_params { |params| params.delete("limit") }.should be(uri)
      uri.query_params.should eq(expected_params)
    end

    it "commits changes to the URI::Object" do
      uri = URI.parse("http://foo.com?id=30&limit=5#time=1305298413")
      uri.update_query_params { |params| params.delete("limit") }

      uri.to_s.should eq("http://foo.com?id=30#time=1305298413")
    end
  end

  describe "#==" do
    it { URI.parse("http://example.com").should eq(URI.parse("http://example.com")) }
  end

  describe "#hash" do
    it { URI.parse("http://example.com").hash.should eq(URI.parse("http://example.com").hash) }
  end

  describe ".default_port" do
    it "returns default port for well known schemes" do
      URI.default_port("http").should eq(80)
      URI.default_port("https").should eq(443)
    end

    it "returns nil for unknown schemes" do
      URI.default_port("xyz").should eq(nil)
    end

    it "treats scheme case insensitively" do
      URI.default_port("Http").should eq(80)
      URI.default_port("HTTP").should eq(80)
    end
  end

  describe ".set_default_port" do
    it "registers port for scheme" do
      URI.set_default_port("ponzi", 9999)
      URI.default_port("ponzi").should eq(9999)
    ensure
      URI.set_default_port("ponzi", nil)
    end

    it "unregisters port for scheme" do
      old_port = URI.default_port("ftp")
      begin
        URI.set_default_port("ftp", nil)
        URI.default_port("ftp").should eq(nil)
      ensure
        URI.set_default_port("ftp", old_port)
      end
    end

    it "treats scheme case insensitively" do
      URI.set_default_port("UNKNOWN", 1234)
      URI.default_port("unknown").should eq(1234)
    ensure
      URI.set_default_port("UNKNOWN", nil)
    end
  end

  describe ".decode" do
    it_decodes("hello", "hello")
    it_decodes("hello%20world", "hello world")
    it_decodes("hello+world", "hello+world")
    it_decodes("hello%", "hello%")
    it_decodes("hello%2", "hello%2")
    it_decodes("hello%2B", "hello+")
    it_decodes("hello%2Bworld", "hello+world")
    it_decodes("hello%2%2Bworld", "hello%2+world")
    it_decodes("%E3%81%AA%E3%81%AA", "なな")
    it_decodes("%e3%81%aa%e3%81%aa", "なな")
    it_decodes("%27Stop%21%27+said+Fred", "'Stop!'+said+Fred")
    it_decodes("hello+world", "hello world", plus_to_space: true)
    it_decodes("+%2B %20", "++  ")

    it "does not decode string when block returns true" do
      String.build do |io|
        URI.decode("hello%26world", io) { |byte| URI.reserved? byte }
      end.should eq("hello%26world")
    end
  end

  it ".encode_path_segment" do
    assert_prints URI.encode_path_segment("hello"), "hello"
    assert_prints URI.encode_path_segment("hello world"), "hello%20world"
    assert_prints URI.encode_path_segment("hello%"), "hello%25"
    assert_prints URI.encode_path_segment("hello%2"), "hello%252"
    assert_prints URI.encode_path_segment("hello+"), "hello%2B"
    assert_prints URI.encode_path_segment("hello+world"), "hello%2Bworld"
    assert_prints URI.encode_path_segment("hello%2+world"), "hello%252%2Bworld"
    assert_prints URI.encode_path_segment("なな"), "%E3%81%AA%E3%81%AA"
    assert_prints URI.encode_path_segment(" !\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~qй"), "%20%21%22%23%24%25%26%27%28%29%2A%2B%2C-.%2F%3A%3B%3C%3D%3E%3F%40%5B%5C%5D%5E_%60%7B%7C%7D~q%D0%B9"
    assert_prints URI.encode_path_segment("'Stop!' said Fred"), "%27Stop%21%27%20said%20Fred"
    assert_prints URI.encode_path_segment("\n"), "%0A"
    assert_prints URI.encode_path_segment("https://en.wikipedia.org/wiki/Crystal (programming language)"), "https%3A%2F%2Fen.wikipedia.org%2Fwiki%2FCrystal%20%28programming%20language%29"
    assert_prints URI.encode_path_segment("\xFF"), "%FF" # escapes invalid UTF-8 character
    assert_prints URI.encode_path_segment("foo;bar;baz"), "foo%3Bbar%3Bbaz"
    assert_prints URI.encode_path_segment("foo/bar/baz"), "foo%2Fbar%2Fbaz"
    assert_prints URI.encode_path_segment("foo,bar,baz"), "foo%2Cbar%2Cbaz"
  end

  it ".encode_path" do
    assert_prints URI.encode_path("hello"), "hello"
    assert_prints URI.encode_path("hello world"), "hello%20world"
    assert_prints URI.encode_path("hello%"), "hello%25"
    assert_prints URI.encode_path("hello%2"), "hello%252"
    assert_prints URI.encode_path("hello+"), "hello%2B"
    assert_prints URI.encode_path("hello+world"), "hello%2Bworld"
    assert_prints URI.encode_path("hello%2+world"), "hello%252%2Bworld"
    assert_prints URI.encode_path("なな"), "%E3%81%AA%E3%81%AA"
    assert_prints URI.encode_path(" !\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~qй"), "%20%21%22%23%24%25%26%27%28%29%2A%2B%2C-./%3A%3B%3C%3D%3E%3F%40%5B%5C%5D%5E_%60%7B%7C%7D~q%D0%B9"
    assert_prints URI.encode_path("'Stop!' said Fred"), "%27Stop%21%27%20said%20Fred"
    assert_prints URI.encode_path("\n"), "%0A"
    assert_prints URI.encode_path("https://en.wikipedia.org/wiki/Crystal (programming language)"), "https%3A//en.wikipedia.org/wiki/Crystal%20%28programming%20language%29"
    assert_prints URI.encode_path("\xFF"), "%FF" # escapes invalid UTF-8 character
    assert_prints URI.encode_path("foo/bar/baz"), "foo/bar/baz"
  end

  describe ".encode" do
    it_encodes("hello", "hello")
    it_encodes("hello world", "hello%20world")
    it_encodes("hello%", "hello%25")
    it_encodes("hello%2", "hello%252")
    it_encodes("hello+", "hello+")
    it_encodes("hello+world", "hello+world")
    it_encodes("hello%2+world", "hello%252+world")
    it_encodes("なな", "%E3%81%AA%E3%81%AA")
    it_encodes("'Stop!' said Fred", "'Stop!'%20said%20Fred")
    it_encodes("\n", "%0A")
    it_encodes("https://en.wikipedia.org/wiki/Crystal (programming language)", "https://en.wikipedia.org/wiki/Crystal%20(programming%20language)")
    it_encodes("\xFF", "%FF") # encodes invalid UTF-8 character
    it_encodes("hello world", "hello+world", space_to_plus: true)
    it_encodes("'Stop!' said Fred", "'Stop!'+said+Fred", space_to_plus: true)

    it "does not encode character when block returns true" do
      String.build do |io|
        URI.decode("hello&world", io) { |byte| URI.reserved? byte }
      end.should eq("hello&world")
    end
  end

  describe ".encode_www_form" do
    it_encodes_www_form("", "")
    it_encodes_www_form("abc", "abc")
    it_encodes_www_form("1%41", "1%2541")
    it_encodes_www_form("a b+", "a+b%2B")
    it_encodes_www_form("a b+", "a%20b%2B", space_to_plus: false)
    it_encodes_www_form("10%", "10%25")
    it_encodes_www_form(" ?&=#+%!<>#\"{}|\\^[]`☺\t:/@$'()*,;", "+%3F%26%3D%23%2B%25%21%3C%3E%23%22%7B%7D%7C%5C%5E%5B%5D%60%E2%98%BA%09%3A%2F%40%24%27%28%29%2A%2C%3B")
    it_encodes_www_form("* foo=bar baz&hello/", "%2A+foo%3Dbar+baz%26hello%2F")
  end

  describe ".decode_www_form" do
    it_decodes_www_form("", "")
    it_decodes_www_form("abc", "abc")
    it_decodes_www_form("1%41", "1A")
    it_decodes_www_form("1%41%42%43", "1ABC")
    it_decodes_www_form("%4a", "J")
    it_encodes_www_form("hello+", "hello%2B")
    it_encodes_www_form("hello+world", "hello%2Bworld")
    it_encodes_www_form("hello%2+world", "hello%252%2Bworld")
    it_encodes_www_form("'Stop!' said Fred", "%27Stop%21%27+said+Fred")
    it_decodes_www_form("a+b", "a b")
    it_decodes_www_form("a%20b", "a b")
    it_decodes_www_form("%20%3F%26%3D%23%2B%25%21%3C%3E%23%22%7B%7D%7C%5C%5E%5B%5D%60%E2%98%BA%09%3A%2F%40%24%27%28%29%2A%2C%3B", " ?&=#+%!<>#\"{}|\\^[]`☺\t:/@$'()*,;")
    it_decodes_www_form("+%2B %20", " +  ")

    it_decodes_www_form("%", "%")
    it_decodes_www_form("%1", "%1")
    it_decodes_www_form("123%45%6", "123E%6")
    it_decodes_www_form("%zzzzz", "%zzzzz")
  end

  it ".reserved?" do
    reserved_chars = Set{':', '/', '?', '#', '[', ']', '@', '!', '$', '&', '\'', '(', ')', '*', '+', ',', ';', '='}

    ('\u{00}'..'\u{7F}').each do |char|
      URI.reserved?(char.ord.to_u8).should eq(reserved_chars.includes?(char))
    end
  end

  it ".unreserved?" do
    unreserved_chars = ('a'..'z').to_a + ('A'..'Z').to_a + ('0'..'9').to_a + ['_', '.', '-', '~']

    ('\u{00}'..'\u{7F}').each do |char|
      URI.unreserved?(char.ord.to_u8).should eq(unreserved_chars.includes?(char))
    end
  end

  describe "#resolve" do
    it "absolute URI references" do
      URI.parse("http://foo.com?a=b").resolve("https://bar.com/").should eq URI.parse("https://bar.com/")
      URI.parse("http://foo.com/").resolve("https://bar.com/?a=b").should eq URI.parse("https://bar.com/?a=b")
      URI.parse("http://foo.com/").resolve("https://bar.com/?").should eq URI.parse("https://bar.com/?")
      URI.parse("http://foo.com/bar").resolve("mailto:urbi@orbi.va").should eq URI.parse("mailto:urbi@orbi.va")
    end

    it "path-absolute URI references" do
      URI.parse("http://foo.com/bar").resolve("/baz").should eq URI.parse("http://foo.com/baz")
      URI.parse("http://foo.com/bar?a=b#f").resolve("/baz").should eq URI.parse("http://foo.com/baz")
      URI.parse("http://foo.com/bar?a=b").resolve("/baz?").should eq URI.parse("http://foo.com/baz?")
      URI.parse("http://foo.com/bar?a=b").resolve("/baz?c=d").should eq URI.parse("http://foo.com/baz?c=d")
    end

    it "multiple slashes" do
      URI.parse("http://foo.com/bar").resolve("http://foo.com//baz").should eq URI.parse("http://foo.com//baz")
      URI.parse("http://foo.com/bar").resolve("http://foo.com///baz/quux").should eq URI.parse("http://foo.com///baz/quux")
    end

    it "scheme-relative" do
      URI.parse("https://foo.com/bar?a=b").resolve("//bar.com/quux").should eq URI.parse("https://bar.com/quux")
    end

    it "path relative references" do
      # same depth
      URI.parse("http://foo.com").resolve(".").should eq URI.parse("http://foo.com/")
      URI.parse("http://foo.com/bar").resolve(".").should eq URI.parse("http://foo.com/")
      URI.parse("http://foo.com/bar/").resolve(".").should eq URI.parse("http://foo.com/bar/")

      # deeper
      URI.parse("http://foo.com").resolve("bar").should eq URI.parse("http://foo.com/bar")
      URI.parse("http://foo.com/").resolve("bar").should eq URI.parse("http://foo.com/bar")
      URI.parse("http://foo.com/bar/baz").resolve("quux").should eq URI.parse("http://foo.com/bar/quux")

      # higher
      URI.parse("http://foo.com/bar/baz").resolve("../quux").should eq URI.parse("http://foo.com/quux")
      URI.parse("http://foo.com/bar/baz").resolve("../../../../../quux").should eq URI.parse("http://foo.com/quux")
      URI.parse("http://foo.com/bar").resolve("..").should eq URI.parse("http://foo.com/")
      URI.parse("http://foo.com/bar/baz").resolve("./..").should eq URI.parse("http://foo.com/")

      # ".." in the middle
      URI.parse("http://foo.com/bar/baz").resolve("quux/dotdot/../tail").should eq URI.parse("http://foo.com/bar/quux/tail")
      URI.parse("http://foo.com/bar/baz").resolve("quux/./dotdot/../tail").should eq URI.parse("http://foo.com/bar/quux/tail")
      URI.parse("http://foo.com/bar/baz").resolve("quux/./dotdot/.././tail").should eq URI.parse("http://foo.com/bar/quux/tail")
      URI.parse("http://foo.com/bar/baz").resolve("quux/./dotdot/./../tail").should eq URI.parse("http://foo.com/bar/quux/tail")
      URI.parse("http://foo.com/bar/baz").resolve("quux/./dotdot/dotdot/././../../tail").should eq URI.parse("http://foo.com/bar/quux/tail")
      URI.parse("http://foo.com/bar/baz").resolve("quux/./dotdot/dotdot/./.././../tail").should eq URI.parse("http://foo.com/bar/quux/tail")
      URI.parse("http://foo.com/bar/baz").resolve("quux/./dotdot/dotdot/dotdot/./../../.././././tail").should eq URI.parse("http://foo.com/bar/quux/tail")
      URI.parse("http://foo.com/bar/baz").resolve("quux/./dotdot/../dotdot/../dot/./tail/..").should eq URI.parse("http://foo.com/bar/quux/dot/")
    end

    it "removes dot-segments" do
      # http://tools.ietf.org/html/rfc3986#section-5.2.4
      URI.parse("http://foo.com/dot/./dotdot/../foo/bar").resolve("../baz").should eq URI.parse("http://foo.com/dot/baz")
    end

    it "..." do
      URI.parse("http://foo.com/bar").resolve("...").should eq URI.parse("http://foo.com/...")
    end

    it "fragment" do
      URI.parse("http://foo.com/bar").resolve(".#frag").should eq URI.parse("http://foo.com/#frag")
      URI.parse("http://example.org/bar").resolve("#!$&%27()*+,;=").should eq URI.parse("http://example.org/bar#!$&%27()*+,;=")
    end

    it "encoded characters" do
      URI.parse("http://foo.com/foo%2fbar/").resolve("../baz").should eq URI.parse("http://foo.com/baz")
      URI.parse("http://foo.com/1/2%2f/3%2f4/5").resolve("../../a/b/c").should eq URI.parse("http://foo.com/1/a/b/c")
      URI.parse("http://foo.com/1/2/3").resolve("./a%2f../../b/..%2fc").should eq URI.parse("http://foo.com/1/2/b/..%2fc")
      URI.parse("http://foo.com/1/2%2f/3%2f4/5").resolve("./a%2f../b/../c").should eq URI.parse("http://foo.com/1/2%2f/3%2f4/a%2f../c")
      URI.parse("http://foo.com/foo%20bar/").resolve("../baz").should eq URI.parse("http://foo.com/baz")
      URI.parse("http://foo.com/foo").resolve("../bar%2fbaz").should eq URI.parse("http://foo.com/bar%2fbaz")
      URI.parse("http://foo.com/foo%2dbar/").resolve("./baz-quux").should eq URI.parse("http://foo.com/foo%2dbar/baz-quux")
    end

    it "RFC 3986: 5.4.1. Normal Examples" do
      # http://tools.ietf.org/html/rfc3986#section-5.4.1
      URI.parse("http://a/b/c/d;p?q").resolve("g:h").should eq URI.parse("g:h")
      URI.parse("http://a/b/c/d;p?q").resolve("g").should eq URI.parse("http://a/b/c/g")
      URI.parse("http://a/b/c/d;p?q").resolve("./g").should eq URI.parse("http://a/b/c/g")
      URI.parse("http://a/b/c/d;p?q").resolve("g/").should eq URI.parse("http://a/b/c/g/")
      URI.parse("http://a/b/c/d;p?q").resolve("/g").should eq URI.parse("http://a/g")
      URI.parse("http://a/b/c/d;p?q").resolve("//g").should eq URI.parse("http://g")
      URI.parse("http://a/b/c/d;p?q").resolve("?y").should eq URI.parse("http://a/b/c/d;p?y")
      URI.parse("http://a/b/c/d;p?q").resolve("g?y").should eq URI.parse("http://a/b/c/g?y")
      URI.parse("http://a/b/c/d;p?q").resolve("#s").should eq URI.parse("http://a/b/c/d;p?q#s")
      URI.parse("http://a/b/c/d;p?q").resolve("g#s").should eq URI.parse("http://a/b/c/g#s")
      URI.parse("http://a/b/c/d;p?q").resolve("g?y#s").should eq URI.parse("http://a/b/c/g?y#s")
      URI.parse("http://a/b/c/d;p?q").resolve(";x").should eq URI.parse("http://a/b/c/;x")
      URI.parse("http://a/b/c/d;p?q").resolve("g;x").should eq URI.parse("http://a/b/c/g;x")
      URI.parse("http://a/b/c/d;p?q").resolve("g;x?y#s").should eq URI.parse("http://a/b/c/g;x?y#s")
      URI.parse("http://a/b/c/d;p?q").resolve("").should eq URI.parse("http://a/b/c/d;p?q")
      URI.parse("http://a/b/c/d;p?q").resolve(".").should eq URI.parse("http://a/b/c/")
      URI.parse("http://a/b/c/d;p?q").resolve("./").should eq URI.parse("http://a/b/c/")
      URI.parse("http://a/b/c/d;p?q").resolve("..").should eq URI.parse("http://a/b/")
      URI.parse("http://a/b/c/d;p?q").resolve("../").should eq URI.parse("http://a/b/")
      URI.parse("http://a/b/c/d;p?q").resolve("../g").should eq URI.parse("http://a/b/g")
      URI.parse("http://a/b/c/d;p?q").resolve("../..").should eq URI.parse("http://a/")
      URI.parse("http://a/b/c/d;p?q").resolve("../../").should eq URI.parse("http://a/")
      URI.parse("http://a/b/c/d;p?q").resolve("../../g").should eq URI.parse("http://a/g")
    end

    it "RFC 3986: 5.4.2. Abnormal Examples" do
      # http://tools.ietf.org/html/rfc3986#section-5.4.2
      URI.parse("http://a/b/c/d;p?q").resolve("../../../g").should eq URI.parse("http://a/g")
      URI.parse("http://a/b/c/d;p?q").resolve("../../../../g").should eq URI.parse("http://a/g")
      URI.parse("http://a/b/c/d;p?q").resolve("/./g").should eq URI.parse("http://a/g")
      URI.parse("http://a/b/c/d;p?q").resolve("/../g").should eq URI.parse("http://a/g")
      URI.parse("http://a/b/c/d;p?q").resolve("g.").should eq URI.parse("http://a/b/c/g.")
      URI.parse("http://a/b/c/d;p?q").resolve(".g").should eq URI.parse("http://a/b/c/.g")
      URI.parse("http://a/b/c/d;p?q").resolve("g..").should eq URI.parse("http://a/b/c/g..")
      URI.parse("http://a/b/c/d;p?q").resolve("..g").should eq URI.parse("http://a/b/c/..g")
      URI.parse("http://a/b/c/d;p?q").resolve("./../g").should eq URI.parse("http://a/b/g")
      URI.parse("http://a/b/c/d;p?q").resolve("./g/.").should eq URI.parse("http://a/b/c/g/")
      URI.parse("http://a/b/c/d;p?q").resolve("g/./h").should eq URI.parse("http://a/b/c/g/h")
      URI.parse("http://a/b/c/d;p?q").resolve("g/../h").should eq URI.parse("http://a/b/c/h")
      URI.parse("http://a/b/c/d;p?q").resolve("g;x=1/./y").should eq URI.parse("http://a/b/c/g;x=1/y")
      URI.parse("http://a/b/c/d;p?q").resolve("g;x=1/../y").should eq URI.parse("http://a/b/c/y")
      URI.parse("http://a/b/c/d;p?q").resolve("g?y/./x").should eq URI.parse("http://a/b/c/g?y/./x")
      URI.parse("http://a/b/c/d;p?q").resolve("g?y/../x").should eq URI.parse("http://a/b/c/g?y/../x")
      URI.parse("http://a/b/c/d;p?q").resolve("g#s/./x").should eq URI.parse("http://a/b/c/g#s/./x")
      URI.parse("http://a/b/c/d;p?q").resolve("g#s/../x").should eq URI.parse("http://a/b/c/g#s/../x")
    end

    it "Extras" do
      URI.parse("https://a/b/c/d;p?q").resolve("//g?q").should eq URI.parse("https://g?q")
      URI.parse("https://a/b/c/d;p?q").resolve("//g#s").should eq URI.parse("https://g#s")
      URI.parse("https://a/b/c/d;p?q").resolve("//g/d/e/f?y#s").should eq URI.parse("https://g/d/e/f?y#s")
      URI.parse("https://a/b/c/d;p#s").resolve("?y").should eq URI.parse("https://a/b/c/d;p?y")
      URI.parse("https://a/b/c/d;p?q#s").resolve("?y").should eq URI.parse("https://a/b/c/d;p?y")
    end

    it "relative base" do
      URI.parse("a/b/c").resolve("bar/baz").should eq URI.parse("a/b/bar/baz")
    end

    it "opaque URIs" do
      URI.parse("mailto:urbi@orbi.va").resolve("bar/baz").should eq URI.parse("bar/baz")
      URI.parse("bar/baz").resolve("mailto:urbi@orbi.va").should eq URI.parse("mailto:urbi@orbi.va")
    end
  end

  describe "#relativize" do
    it "absolute URI references" do
      assert_relativize("http://foo.com?a=b", "https://bar.com/", "https://bar.com/")
      assert_relativize("http://foo.com/", "https://bar.com/?a=b", "https://bar.com/?a=b")
      assert_relativize("http://foo.com/", "https://bar.com/?", "https://bar.com/?")
      assert_relativize("http://foo.com/bar", "mailto:urbi@orbi.va", "mailto:urbi@orbi.va")
    end

    it "path relative references" do
      # same depth
      assert_relativize("http://foo.com", "http://foo.com/", "./")
      assert_relativize("http://foo.com/bar", "http://foo.com/", "./")
      assert_relativize("http://foo.com/bar", "http://foo.com/bar/", "bar/")
      assert_relativize("http://foo.com/bar", "http://foo.com/baz", "baz")
      assert_relativize("http://foo.com/bar?a=b#f", "http://foo.com/baz", "baz")
      assert_relativize("http://foo.com/bar?a=b", "http://foo.com/baz?", "baz?")
      assert_relativize("http://foo.com/bar?a=b", "http://foo.com/baz?c=d", "baz?c=d")

      # deeper
      assert_relativize("http://foo.com", "http://foo.com/bar", "bar")
      assert_relativize("http://foo.com/", "http://foo.com/bar", "bar")
      assert_relativize("http://foo.com/bar/baz", "http://foo.com/bar/quux", "quux")

      # higher
      assert_relativize("http://foo.com/bar/baz", "http://foo.com/quux", "../quux")
      assert_relativize("http://foo.com/bar/baz/", "http://foo.com/quux", "../../quux")
      assert_relativize("http://foo.com/bar", "http://foo.com/", "./")
      assert_relativize("http://foo.com/bar/baz", "http://foo.com/", "../")
      assert_relativize("http://foo.com/bar/", "http://foo.com/qux/", "../qux/")
      assert_relativize("http://a/b/c/d;p?q", "http://a/b/", "../")
      assert_relativize("http://a/b/c/d;p?q", "http://a/b/g", "../g")
      assert_relativize("http://a/b/c/d;p?q", "http://a/", "../../")
      assert_relativize("http://a/b/c/d;p?q", "http://a/g", "../../g")
    end

    it "identical" do
      assert_relativize("http://foo.com/a", "http://foo.com/a", "")
      assert_relativize("http://foo.com/a", "http://FOO.com/a", "")
    end

    it "ignore base path with dot-segments" do
      # These specs don't use assert_relativize because they explicitly not reversible as thy perform on non-normalized paths
      URI.parse("http://foo.com/dot/./dotdot/../foo/bar").relativize("http://foo.com/dot/baz").should eq URI.parse("/dot/baz")
      URI.parse("http://foo.com/dot/./dotdot/../foo/bar").relativize("dot/baz").should eq URI.parse("dot/baz")
    end

    it "..." do
      assert_relativize("http://foo.com/bar", "http://foo.com/.../", ".../")
    end

    it "fragment" do
      assert_relativize("http://foo.com/bar", "http://foo.com/#frag", "./#frag")
      assert_relativize("http://example.org/bar", "http://example.org/bar#!$&%27()*+,;=", "#!$&%27()*+,;=")
    end

    it "encoded characters" do
      assert_relativize("http://foo.com/foo%2fbar/", "http://foo.com/baz", "../baz")
      assert_relativize("http://foo.com/1/2%2f/3%2f4/5", "http://foo.com/1/a/b/c", "../../a/b/c")
      assert_relativize("http://foo.com/1/2/3", "http://foo.com/1/2/b/..%2fc", "b/..%2fc")
      assert_relativize("http://foo.com/1/2%2f/3%2f4/5", "http://foo.com/1/2%2f/3%2f4/a%2f../c", "a%2f../c")
      assert_relativize("http://foo.com/foo%20bar/", "http://foo.com/baz", "../baz")
      assert_relativize("http://foo.com/foo", "http://foo.com/bar%2fbaz", "bar%2fbaz")
      assert_relativize("http://foo.com/foo%2dbar/", "http://foo.com/foo%2dbar/baz-quux", "baz-quux")
    end

    it "RFC 3986: 5.4.1. Normal Examples" do
      # http://tools.ietf.org/html/rfc3986#section-5.4.1
      assert_relativize("http://a/b/c/d;p?q", "g:h", "g:h")
      assert_relativize("http://a/b/c/d;p?q", "http://a/b/c/g", "g")
      assert_relativize("http://a/b/c/d;p?q", "http://a/b/c/g/", "g/")
      assert_relativize("http://a/b/c/d;p?q", "http://a/b/c/d;p?y", "?y")
      assert_relativize("http://a/b/c/d;p?q", "http://a/b/c/g?y", "g?y")
      assert_relativize("http://a/b/c/d;p?q", "http://a/b/c/d;p?q#s", "#s")
      assert_relativize("http://a/b/c/d;p?q", "http://a/b/c/g#s", "g#s")
      assert_relativize("http://a/b/c/d;p?q", "http://a/b/c/g?y#s", "g?y#s")
      assert_relativize("http://a/b/c/d;p?q", "http://a/b/c/;x", ";x")
      assert_relativize("http://a/b/c/d;p?q", "http://a/b/c/g;x", "g;x")
      assert_relativize("http://a/b/c/d;p?q", "http://a/b/c/g;x?y#s", "g;x?y#s")
      assert_relativize("http://a/b/c/d;p?q", "http://a/b/c/d;p?q", "")
      assert_relativize("http://a/b/c/d;p?q", "http://a/b/c/", "./")
    end

    it "RFC 3986: 5.4.2. Abnormal Examples" do
      # http://tools.ietf.org/html/rfc3986#section-5.4.2
      assert_relativize("http://a/b/c/d;p?q", "http://a/b/c/g.", "g.")
      assert_relativize("http://a/b/c/d;p?q", "http://a/b/c/.g", ".g")
      assert_relativize("http://a/b/c/d;p?q", "http://a/b/c/g..", "g..")
      assert_relativize("http://a/b/c/d;p?q", "http://a/b/c/..g", "..g")
      assert_relativize("http://a/b/c/d;p?q", "http://a/b/c/g;x=1/y", "g;x=1/y")
      assert_relativize("http://a/b/c/d;p?q", "http://a/b/c/g?y/./x", "g?y/./x")
      assert_relativize("http://a/b/c/d;p?q", "http://a/b/c/g?y/../x", "g?y/../x")
      assert_relativize("http://a/b/c/d;p?q", "http://a/b/c/g#s/./x", "g#s/./x")
      assert_relativize("http://a/b/c/d;p?q", "http://a/b/c/g#s/../x", "g#s/../x")
      assert_relativize("https://a/b/c/d;p#s", "https://a/b/c/d;p?y", "?y")
      assert_relativize("https://a/b/c/d;p?q#s", "https://a/b/c/d;p?y", "?y")
    end

    it "relative base" do
      assert_relativize("a/b/c", "a/b/bar/baz", "bar/baz")
      assert_relativize("foo/", "foo/a:b", "./a:b")
    end

    it "opaque base" do
      assert_relativize("mailto:urbi@orbi.va", "bar/baz", "bar/baz")
      assert_relativize("mailto:urbi@orbi.va", "mailto:urbi@orbi.va#bar", "mailto:urbi@orbi.va#bar")
      assert_relativize("mailto:urbi@orbi.va#bar", "mailto:urbi@orbi.va", "mailto:urbi@orbi.va")
    end
  end

  it ".unwrap_ipv6" do
    URI.unwrap_ipv6("[::1]").should eq("::1")
    URI.unwrap_ipv6("127.0.0.1").should eq("127.0.0.1")
    URI.unwrap_ipv6("example.com").should eq("example.com")
    URI.unwrap_ipv6("[1234:5678::1]").should eq "1234:5678::1"
  end

  it ".from_json" do
    URI.from_json(%("https://example.com")).should eq URI.new(scheme: "https", host: "example.com")
  end

  it "#to_json" do
    URI.new(scheme: "https", host: "example.com").to_json.should eq %("https://example.com")
  end

  it ".from_yaml" do
    URI.from_yaml(%("https://example.com")).should eq URI.new(scheme: "https", host: "example.com")
  end

  it "#to_yaml" do
    URI.new(scheme: "https", host: "example.com").to_yaml.rchop("...\n").should eq %(--- https://example.com\n)
  end
end
