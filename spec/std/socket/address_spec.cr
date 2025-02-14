require "spec"
require "socket"
require "../../support/win32"
require "spec/helpers/string"

describe Socket::Address do
  describe ".parse" do
    it "accepts URI" do
      address = Socket::Address.parse URI.parse("tcp://192.168.0.1:8081")
      address.should eq Socket::IPAddress.new("192.168.0.1", 8081)
    end

    it "parses TCP" do
      address = Socket::Address.parse "tcp://192.168.0.1:8081"
      address.should eq Socket::IPAddress.new("192.168.0.1", 8081)
    end

    it "parses UDP" do
      address = Socket::Address.parse "udp://192.168.0.1:8081"
      address.should eq Socket::IPAddress.new("192.168.0.1", 8081)
    end

    it "parses UNIX" do
      address = Socket::Address.parse "unix://socket.sock"
      address.should eq Socket::UNIXAddress.new("socket.sock")
    end

    it "fails with unknown scheme" do
      expect_raises(Socket::Error, "Unsupported address type: ssl") do
        Socket::Address.parse "ssl://192.168.0.1:8081"
      end
    end
  end
end

describe Socket::IPAddress do
  c_port = {% if IO::ByteFormat::NetworkEndian != IO::ByteFormat::SystemEndian %}
             36895 # 0x901F
           {% else %}
             8080 # 0x1F90
           {% end %}

  it "transforms an IPv4 address into a C struct and back" do
    addr1 = Socket::IPAddress.new("127.0.0.1", 8080)

    addr1_c = addr1.to_unsafe
    addr1_c.as(LibC::SockaddrIn*).value.sin_port.should eq(c_port)

    addr2 = Socket::IPAddress.from(addr1_c, addr1.size)
    addr2.family.should eq(addr1.family)
    addr2.port.should eq(addr1.port)
    typeof(addr2.address).should eq(String)
    addr2.address.should eq(addr1.address)
    addr2.should eq(Socket::IPAddress.from(addr1_c))
  end

  it "transforms an IPv6 address into a C struct and back" do
    addr1 = Socket::IPAddress.new("2001:db8:8714:3a90::12", 8080)

    addr1_c = addr1.to_unsafe
    addr1_c.as(LibC::SockaddrIn6*).value.sin6_port.should eq(c_port)

    addr2 = Socket::IPAddress.from(addr1_c, addr1.size)
    addr2.family.should eq(addr1.family)
    addr2.port.should eq(addr1.port)
    typeof(addr2.address).should eq(String)
    addr2.address.should eq(addr1.address)
    addr2.should eq(Socket::IPAddress.from(addr1_c))
  end

  it "won't resolve domains" do
    expect_raises(Socket::Error, /Invalid IP address/) do
      Socket::IPAddress.new("localhost", 1234)
    end
  end

  it "errors on out of range port numbers" do
    expect_raises(Socket::Error, /Invalid port number/) do
      Socket::IPAddress.new("localhost", -1)
    end

    expect_raises(Socket::Error, /Invalid port number/) do
      Socket::IPAddress.new("localhost", 65536)
    end
  end

  it "#to_s" do
    assert_prints Socket::IPAddress.v4(UInt8.static_array(127, 0, 0, 1), 80).to_s, "127.0.0.1:80"

    assert_prints Socket::IPAddress.v6(UInt16.static_array(0x2001, 0xdb8, 0x8714, 0x3a90, 0, 0, 0, 0x12), 443).to_s, "[2001:db8:8714:3a90::12]:443"
    assert_prints Socket::IPAddress.v6(UInt16.static_array(0xffff, 0xffff, 0xffff, 0xffff, 0xffff, 0xffff, 0xffff, 0xffff), 0xffff).to_s, "[ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff]:65535"
    assert_prints Socket::IPAddress.v6(UInt16.static_array(0x2001, 0xdb8, 0, 1, 1, 1, 1, 1), 443).to_s, "[2001:db8:0:1:1:1:1:1]:443"
    assert_prints Socket::IPAddress.v6(UInt16.static_array(0x2001, 0, 0, 1, 0, 0, 0, 1), 443).to_s, "[2001:0:0:1::1]:443"
    assert_prints Socket::IPAddress.v6(UInt16.static_array(0x2001, 0, 0, 0, 1, 0, 0, 1), 443).to_s, "[2001::1:0:0:1]:443"
    assert_prints Socket::IPAddress.v6(UInt16.static_array(0x2001, 0xdb8, 0, 0, 1, 0, 0, 1), 443).to_s, "[2001:db8::1:0:0:1]:443"
    assert_prints Socket::IPAddress.v6(UInt16.static_array(0, 0, 0, 0, 0, 0, 0, 1), 443).to_s, "[::1]:443"
    assert_prints Socket::IPAddress.v6(UInt16.static_array(1, 0, 0, 0, 0, 0, 0, 0), 443).to_s, "[1::]:443"
    assert_prints Socket::IPAddress.v6(UInt16.static_array(0, 0, 0, 0, 0, 0, 0, 0), 443).to_s, "[::]:443"

    assert_prints Socket::IPAddress.v4_mapped_v6(UInt8.static_array(0, 0, 0, 0), 443).to_s, "[::ffff:0.0.0.0]:443"
    assert_prints Socket::IPAddress.v4_mapped_v6(UInt8.static_array(192, 168, 1, 15), 443).to_s, "[::ffff:192.168.1.15]:443"

    assert_prints Socket::IPAddress.new("0:0:0:0:0:0:0:1", 443).to_s, "[::1]:443"
    assert_prints Socket::IPAddress.new("0:0:0:0:0:ffff:c0a8:010f", 443).to_s, "[::ffff:192.168.1.15]:443"
    assert_prints Socket::IPAddress.new("::ffff:0:0", 443).to_s, "[::ffff:0.0.0.0]:443"
  end

  it "#address" do
    Socket::IPAddress.v4(UInt8.static_array(127, 0, 0, 1), 80).address.should eq "127.0.0.1"

    Socket::IPAddress.v6(UInt16.static_array(0x2001, 0xdb8, 0x8714, 0x3a90, 0, 0, 0, 0x12), 443).address.should eq "2001:db8:8714:3a90::12"
    Socket::IPAddress.v6(UInt16.static_array(0xffff, 0xffff, 0xffff, 0xffff, 0xffff, 0xffff, 0xffff, 0xffff), 0xffff).address.should eq "ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff"
    Socket::IPAddress.v6(UInt16.static_array(0x2001, 0xdb8, 0, 1, 1, 1, 1, 1), 443).address.should eq "2001:db8:0:1:1:1:1:1"
    Socket::IPAddress.v6(UInt16.static_array(0x2001, 0, 0, 1, 0, 0, 0, 1), 443).address.should eq "2001:0:0:1::1"
    Socket::IPAddress.v6(UInt16.static_array(0x2001, 0, 0, 0, 1, 0, 0, 1), 443).address.should eq "2001::1:0:0:1"
    Socket::IPAddress.v6(UInt16.static_array(0x2001, 0xdb8, 0, 0, 1, 0, 0, 1), 443).address.should eq "2001:db8::1:0:0:1"
    Socket::IPAddress.v6(UInt16.static_array(0, 0, 0, 0, 0, 0, 0, 1), 443).address.should eq "::1"
    Socket::IPAddress.v6(UInt16.static_array(1, 0, 0, 0, 0, 0, 0, 0), 443).address.should eq "1::"
    Socket::IPAddress.v6(UInt16.static_array(0, 0, 0, 0, 0, 0, 0, 0), 443).address.should eq "::"

    Socket::IPAddress.v4_mapped_v6(UInt8.static_array(0, 0, 0, 0), 443).address.should eq "::ffff:0.0.0.0"
    Socket::IPAddress.v4_mapped_v6(UInt8.static_array(192, 168, 1, 15), 443).address.should eq "::ffff:192.168.1.15"

    Socket::IPAddress.new("0:0:0:0:0:0:0:1", 443).address.should eq "::1"
    Socket::IPAddress.new("0:0:0:0:0:ffff:c0a8:010f", 443).address.should eq "::ffff:192.168.1.15"
    Socket::IPAddress.new("::ffff:0:0", 443).address.should eq "::ffff:0.0.0.0"
  end

  describe "#scope_id" do
    it "parses link-local IPv6 with interface scope" do
      address = Socket::IPAddress.new("fe80::3333:4444%3", 8081)
      address.address.should eq "fe80::3333:4444"
      address.scope_id.should eq 3
    end

    it "ignores link-local scope identifier on non-LL addrs" do
      address = Socket::IPAddress.new("fd00::abcd%5", 443)
      address.address.should eq "fd00::abcd"
      address.scope_id.should eq 0
    end

    it "looks up loopback interface index by name" do
      # loopback interface "lo" is supposed to *always* be the first interface and
      # enumerated with index 1
      loopback_iface = {% if flag?(:windows) %}
                         "loopback_0"
                       {% elsif flag?(:darwin) || flag?(:bsd) || flag?(:solaris) %}
                         "lo0"
                       {% else %}
                         "lo"
                       {% end %}
      address = Socket::IPAddress.new("fe80::1111%#{loopback_iface}", 0)
      address.address.should eq "fe80::1111"
      address.scope_id.should eq 1
    end

    it "looks up loopback interface name by index" do
      # loopback interface "lo" is supposed to *always* be the first interface and
      # enumerated with index 1
      buf = uninitialized StaticArray(UInt8, LibC::IF_NAMESIZE)
      LibC.if_indextoname(1, buf)
      ifname = String.new(buf.to_unsafe)
      {% if flag?(:windows) %}
        ifname.should eq "loopback_0"
      {% elsif flag?(:darwin) || flag?(:bsd) || flag?(:solaris) %}
        ifname.should eq "lo0"
      {% else %}
        ifname.should eq "lo"
      {% end %}
    end

    it "fails on invalid link-local scope identifier" do
      expect_raises(ArgumentError, "Invalid IPv6 link-local scope index '0' in address 'fe80::c0ff:ee%0'") do
        Socket::IPAddress.new("fe80::c0ff:ee%0", port: 0)
      end
    end

    it "fails on non-existent link-local scope interface" do
      # looking up an interface index obviously requires for said interface device to exist
      expect_raises(ArgumentError, "IPv6 link-local scope interface 'zzzzzzzzzzzzzzz' not found (in address 'fe80::0f0f:abcd%zzzzzzzzzzzzzzz'") do
        Socket::IPAddress.new("fe80::0f0f:abcd%zzzzzzzzzzzzzzz", port: 0)
      end
    end
  end

  describe ".parse" do
    it "parses IPv4" do
      address = Socket::IPAddress.parse "ip://192.168.0.1:8081"
      address.should eq Socket::IPAddress.new("192.168.0.1", 8081)
    end

    it "parses IPv6" do
      address = Socket::IPAddress.parse "ip://[::1]:8081"
      address.should eq Socket::IPAddress.new("::1", 8081)
    end

    it "fails host name" do
      expect_raises(Socket::Error, "Invalid IP address: example.com") do
        Socket::IPAddress.parse "ip://example.com:8081"
      end
    end

    it "ignores path and params" do
      address = Socket::IPAddress.parse "ip://192.168.0.1:8081/foo?bar=baz"
      address.should eq Socket::IPAddress.new("192.168.0.1", 8081)
    end

    it "fails with missing host" do
      expect_raises(Socket::Error, "Invalid IP address: missing host") do
        Socket::IPAddress.parse "ip:///path"
      end
    end

    it "fails with missing port" do
      expect_raises(Socket::Error, "Invalid IP address: missing port") do
        Socket::IPAddress.parse "ip://127.0.0.1"
      end
    end
  end

  # Tests from libc-test:
  # https://repo.or.cz/libc-test.git/blob/2113a3ed8217775797dd9a82aa420c10ef1712d5:/src/functional/inet_pton.c
  describe ".parse_v4_fields?" do
    # dotted-decimal notation
    it { Socket::IPAddress.parse_v4_fields?("0.0.0.0").should eq UInt8.static_array(0, 0, 0, 0) }
    it { Socket::IPAddress.parse_v4_fields?("127.0.0.1").should eq UInt8.static_array(127, 0, 0, 1) }
    it { Socket::IPAddress.parse_v4_fields?("10.0.128.31").should eq UInt8.static_array(10, 0, 128, 31) }
    it { Socket::IPAddress.parse_v4_fields?("255.255.255.255").should eq UInt8.static_array(255, 255, 255, 255) }

    # numbers-and-dots notation, but not dotted-decimal
    it { Socket::IPAddress.parse_v4_fields?("1.2.03.4").should be_nil }
    it { Socket::IPAddress.parse_v4_fields?("1.2.0x33.4").should be_nil }
    it { Socket::IPAddress.parse_v4_fields?("1.2.0XAB.4").should be_nil }
    it { Socket::IPAddress.parse_v4_fields?("1.2.0xabcd").should be_nil }
    it { Socket::IPAddress.parse_v4_fields?("1.0xabcdef").should be_nil }
    it { Socket::IPAddress.parse_v4_fields?("00377.0x0ff.65534").should be_nil }

    # invalid
    it { Socket::IPAddress.parse_v4_fields?(".1.2.3").should be_nil }
    it { Socket::IPAddress.parse_v4_fields?("1..2.3").should be_nil }
    it { Socket::IPAddress.parse_v4_fields?("1.2.3.").should be_nil }
    it { Socket::IPAddress.parse_v4_fields?("1.2.3.4.5").should be_nil }
    it { Socket::IPAddress.parse_v4_fields?("1.2.3.a").should be_nil }
    it { Socket::IPAddress.parse_v4_fields?("1.256.2.3").should be_nil }
    it { Socket::IPAddress.parse_v4_fields?("1.2.4294967296.3").should be_nil }
    it { Socket::IPAddress.parse_v4_fields?("1.2.-4294967295.3").should be_nil }
    it { Socket::IPAddress.parse_v4_fields?("1.2. 3.4").should be_nil }
  end

  describe ".parse_v6_fields?" do
    it { Socket::IPAddress.parse_v6_fields?(":").should be_nil }
    it { Socket::IPAddress.parse_v6_fields?("::").should eq UInt16.static_array(0, 0, 0, 0, 0, 0, 0, 0) }
    it { Socket::IPAddress.parse_v6_fields?("::1").should eq UInt16.static_array(0, 0, 0, 0, 0, 0, 0, 1) }
    it { Socket::IPAddress.parse_v6_fields?(":::").should be_nil }
    it { Socket::IPAddress.parse_v6_fields?("192.168.1.1").should be_nil }
    it { Socket::IPAddress.parse_v6_fields?(":192.168.1.1").should be_nil }
    it { Socket::IPAddress.parse_v6_fields?("::192.168.1.1").should eq UInt16.static_array(0, 0, 0, 0, 0, 0, 0xc0a8, 0x0101) }
    it { Socket::IPAddress.parse_v6_fields?("0:0:0:0:0:0:192.168.1.1").should eq UInt16.static_array(0, 0, 0, 0, 0, 0, 0xc0a8, 0x0101) }
    it { Socket::IPAddress.parse_v6_fields?("0:0::0:0:0:192.168.1.1").should eq UInt16.static_array(0, 0, 0, 0, 0, 0, 0xc0a8, 0x0101) }
    it { Socket::IPAddress.parse_v6_fields?("::012.34.56.78").should be_nil }
    it { Socket::IPAddress.parse_v6_fields?(":ffff:192.168.1.1").should be_nil }
    it { Socket::IPAddress.parse_v6_fields?("::ffff:192.168.1.1").should eq UInt16.static_array(0, 0, 0, 0, 0, 0xffff, 0xc0a8, 0x0101) }
    it { Socket::IPAddress.parse_v6_fields?(".192.168.1.1").should be_nil }
    it { Socket::IPAddress.parse_v6_fields?(":.192.168.1.1").should be_nil }
    it { Socket::IPAddress.parse_v6_fields?("a:0b:00c:000d:E:F::").should eq UInt16.static_array(0xa, 0x0b, 0x00c, 0x000d, 0xE, 0xF, 0, 0) }
    it { Socket::IPAddress.parse_v6_fields?("a:0b:00c:000d:0000e:f::").should be_nil }
    it { Socket::IPAddress.parse_v6_fields?("1:2:3:4:5:6::").should eq UInt16.static_array(1, 2, 3, 4, 5, 6, 0, 0) }
    it { Socket::IPAddress.parse_v6_fields?("1:2:3:4:5:6:7::").should eq UInt16.static_array(1, 2, 3, 4, 5, 6, 7, 0) }
    it { Socket::IPAddress.parse_v6_fields?("1:2:3:4:5:6:7:8::").should be_nil }
    it { Socket::IPAddress.parse_v6_fields?("1:2:3:4:5:6:7::9").should be_nil }
    it { Socket::IPAddress.parse_v6_fields?("::1:2:3:4:5:6").should eq UInt16.static_array(0, 0, 1, 2, 3, 4, 5, 6) }
    it { Socket::IPAddress.parse_v6_fields?("::1:2:3:4:5:6:7").should eq UInt16.static_array(0, 1, 2, 3, 4, 5, 6, 7) }
    it { Socket::IPAddress.parse_v6_fields?("::1:2:3:4:5:6:7:8").should be_nil }
    it { Socket::IPAddress.parse_v6_fields?("a:b::c:d:e:f").should eq UInt16.static_array(0xa, 0xb, 0, 0, 0xc, 0xd, 0xe, 0xf) }
    it { Socket::IPAddress.parse_v6_fields?("ffff:c0a8:5e4").should be_nil }
    it { Socket::IPAddress.parse_v6_fields?(":ffff:c0a8:5e4").should be_nil }
    it { Socket::IPAddress.parse_v6_fields?("0:0:0:0:0:ffff:c0a8:5e4").should eq UInt16.static_array(0, 0, 0, 0, 0, 0xffff, 0xc0a8, 0x5e4) }
    it { Socket::IPAddress.parse_v6_fields?("0:0:0:0:ffff:c0a8:5e4").should be_nil }
    it { Socket::IPAddress.parse_v6_fields?("0::ffff:c0a8:5e4").should eq UInt16.static_array(0, 0, 0, 0, 0, 0xffff, 0xc0a8, 0x5e4) }
    it { Socket::IPAddress.parse_v6_fields?("::0::ffff:c0a8:5e4").should be_nil }
    it { Socket::IPAddress.parse_v6_fields?("c0a8").should be_nil }
  end

  describe ".v4" do
    it "constructs an IPv4 address" do
      Socket::IPAddress.v4(0, 0, 0, 0, port: 0).should eq Socket::IPAddress.new("0.0.0.0", 0)
      Socket::IPAddress.v4(127, 0, 0, 1, port: 1234).should eq Socket::IPAddress.new("127.0.0.1", 1234)
      Socket::IPAddress.v4(192, 168, 0, 1, port: 8081).should eq Socket::IPAddress.new("192.168.0.1", 8081)
      Socket::IPAddress.v4(255, 255, 255, 254, port: 65535).should eq Socket::IPAddress.new("255.255.255.254", 65535)
    end

    it "raises on out of bound field" do
      expect_raises(Socket::Error, "Invalid IPv4 field: 256") { Socket::IPAddress.v4(256, 0, 0, 0, port: 0) }
      expect_raises(Socket::Error, "Invalid IPv4 field: 256") { Socket::IPAddress.v4(0, 256, 0, 0, port: 0) }
      expect_raises(Socket::Error, "Invalid IPv4 field: 256") { Socket::IPAddress.v4(0, 0, 256, 0, port: 0) }
      expect_raises(Socket::Error, "Invalid IPv4 field: 256") { Socket::IPAddress.v4(0, 0, 0, 256, port: 0) }
      expect_raises(Socket::Error, "Invalid IPv4 field: -1") { Socket::IPAddress.v4(-1, 0, 0, 0, port: 0) }
      expect_raises(Socket::Error, "Invalid IPv4 field: -1") { Socket::IPAddress.v4(0, -1, 0, 0, port: 0) }
      expect_raises(Socket::Error, "Invalid IPv4 field: -1") { Socket::IPAddress.v4(0, 0, -1, 0, port: 0) }
      expect_raises(Socket::Error, "Invalid IPv4 field: -1") { Socket::IPAddress.v4(0, 0, 0, -1, port: 0) }
    end

    it "raises on out of bound port number" do
      expect_raises(Socket::Error, "Invalid port number: 65536") { Socket::IPAddress.v4(0, 0, 0, 0, port: 65536) }
      expect_raises(Socket::Error, "Invalid port number: -1") { Socket::IPAddress.v4(0, 0, 0, 0, port: -1) }
    end

    it "constructs from StaticArray" do
      Socket::IPAddress.v4(UInt8.static_array(0, 0, 0, 0), 0).should eq Socket::IPAddress.new("0.0.0.0", 0)
      Socket::IPAddress.v4(UInt8.static_array(127, 0, 0, 1), 1234).should eq Socket::IPAddress.new("127.0.0.1", 1234)
      Socket::IPAddress.v4(UInt8.static_array(192, 168, 0, 1), 8081).should eq Socket::IPAddress.new("192.168.0.1", 8081)
      Socket::IPAddress.v4(UInt8.static_array(255, 255, 255, 254), 65535).should eq Socket::IPAddress.new("255.255.255.254", 65535)
    end
  end

  describe ".v6" do
    it "constructs an IPv6 address" do
      Socket::IPAddress.v6(0, 0, 0, 0, 0, 0, 0, 0, port: 0).should eq Socket::IPAddress.new("::", 0)
      Socket::IPAddress.v6(1, 2, 3, 4, 5, 6, 7, 8, port: 8080).should eq Socket::IPAddress.new("1:2:3:4:5:6:7:8", 8080)
      Socket::IPAddress.v6(0xfe80, 0, 0, 0, 0x4860, 0x4860, 0x4860, 0x1234, port: 55001).should eq Socket::IPAddress.new("fe80::4860:4860:4860:1234", 55001)
      Socket::IPAddress.v6(0xffff, 0xffff, 0xffff, 0xffff, 0xffff, 0xffff, 0xffff, 0xfffe, port: 65535).should eq Socket::IPAddress.new("ffff:ffff:ffff:ffff:ffff:ffff:ffff:fffe", 65535)
      Socket::IPAddress.v6(0, 0, 0, 0, 0, 0xffff, 0xc0a8, 0x0001, port: 0).should eq Socket::IPAddress.new("::ffff:192.168.0.1", 0)
      Socket::IPAddress.v6(0xfe80, 0, 0, 0, 0x5971, 0x5971, 0x5971, 0xabcd, port: 44444, scope_id: 3).should eq Socket::IPAddress.new("fe80::5971:5971:5971:abcd%3", 44444)
    end

    it "raises on out of bound field" do
      expect_raises(Socket::Error, "Invalid IPv6 field: 65536") { Socket::IPAddress.v6(65536, 0, 0, 0, 0, 0, 0, 0, port: 0) }
      expect_raises(Socket::Error, "Invalid IPv6 field: 65536") { Socket::IPAddress.v6(0, 65536, 0, 0, 0, 0, 0, 0, port: 0) }
      expect_raises(Socket::Error, "Invalid IPv6 field: 65536") { Socket::IPAddress.v6(0, 0, 65536, 0, 0, 0, 0, 0, port: 0) }
      expect_raises(Socket::Error, "Invalid IPv6 field: 65536") { Socket::IPAddress.v6(0, 0, 0, 65536, 0, 0, 0, 0, port: 0) }
      expect_raises(Socket::Error, "Invalid IPv6 field: 65536") { Socket::IPAddress.v6(0, 0, 0, 0, 65536, 0, 0, 0, port: 0) }
      expect_raises(Socket::Error, "Invalid IPv6 field: 65536") { Socket::IPAddress.v6(0, 0, 0, 0, 0, 65536, 0, 0, port: 0) }
      expect_raises(Socket::Error, "Invalid IPv6 field: 65536") { Socket::IPAddress.v6(0, 0, 0, 0, 0, 0, 65536, 0, port: 0) }
      expect_raises(Socket::Error, "Invalid IPv6 field: 65536") { Socket::IPAddress.v6(0, 0, 0, 0, 0, 0, 0, 65536, port: 0) }
      expect_raises(Socket::Error, "Invalid IPv6 field: -1") { Socket::IPAddress.v6(-1, 0, 0, 0, 0, 0, 0, 0, port: 0) }
      expect_raises(Socket::Error, "Invalid IPv6 field: -1") { Socket::IPAddress.v6(0, -1, 0, 0, 0, 0, 0, 0, port: 0) }
      expect_raises(Socket::Error, "Invalid IPv6 field: -1") { Socket::IPAddress.v6(0, 0, -1, 0, 0, 0, 0, 0, port: 0) }
      expect_raises(Socket::Error, "Invalid IPv6 field: -1") { Socket::IPAddress.v6(0, 0, 0, -1, 0, 0, 0, 0, port: 0) }
      expect_raises(Socket::Error, "Invalid IPv6 field: -1") { Socket::IPAddress.v6(0, 0, 0, 0, -1, 0, 0, 0, port: 0) }
      expect_raises(Socket::Error, "Invalid IPv6 field: -1") { Socket::IPAddress.v6(0, 0, 0, 0, 0, -1, 0, 0, port: 0) }
      expect_raises(Socket::Error, "Invalid IPv6 field: -1") { Socket::IPAddress.v6(0, 0, 0, 0, 0, 0, -1, 0, port: 0) }
      expect_raises(Socket::Error, "Invalid IPv6 field: -1") { Socket::IPAddress.v6(0, 0, 0, 0, 0, 0, 0, -1, port: 0) }
    end

    it "raises on out of bound port number" do
      expect_raises(Socket::Error, "Invalid port number: 65536") { Socket::IPAddress.v6(0, 0, 0, 0, 0, 0, 0, 0, port: 65536) }
      expect_raises(Socket::Error, "Invalid port number: -1") { Socket::IPAddress.v6(0, 0, 0, 0, 0, 0, 0, 0, port: -1) }
    end

    it "constructs from StaticArray" do
      Socket::IPAddress.v6(UInt16.static_array(0, 0, 0, 0, 0, 0, 0, 0), 0).should eq Socket::IPAddress.new("::", 0)
      Socket::IPAddress.v6(UInt16.static_array(1, 2, 3, 4, 5, 6, 7, 8), 8080).should eq Socket::IPAddress.new("1:2:3:4:5:6:7:8", 8080)
      Socket::IPAddress.v6(UInt16.static_array(0xfe80, 0, 0, 0, 0x4860, 0x4860, 0x4860, 0x1234), 55001).should eq Socket::IPAddress.new("fe80::4860:4860:4860:1234", 55001)
      Socket::IPAddress.v6(UInt16.static_array(0xffff, 0xffff, 0xffff, 0xffff, 0xffff, 0xffff, 0xffff, 0xfffe), 65535).should eq Socket::IPAddress.new("ffff:ffff:ffff:ffff:ffff:ffff:ffff:fffe", 65535)
      Socket::IPAddress.v6(UInt16.static_array(0, 0, 0, 0, 0, 0xffff, 0xc0a8, 0x0001), 0).should eq Socket::IPAddress.new("::ffff:192.168.0.1", 0)
    end
  end

  describe ".v4_mapped_v6" do
    it "constructs an IPv4-mapped IPv6 address" do
      Socket::IPAddress.v4_mapped_v6(0, 0, 0, 0, port: 0).should eq Socket::IPAddress.new("::ffff:0.0.0.0", 0)
      Socket::IPAddress.v4_mapped_v6(127, 0, 0, 1, port: 1234).should eq Socket::IPAddress.new("::ffff:127.0.0.1", 1234)
      Socket::IPAddress.v4_mapped_v6(192, 168, 0, 1, port: 8081).should eq Socket::IPAddress.new("::ffff:192.168.0.1", 8081)
      Socket::IPAddress.v4_mapped_v6(255, 255, 255, 254, port: 65535).should eq Socket::IPAddress.new("::ffff:255.255.255.254", 65535)
    end

    it "raises on out of bound field" do
      expect_raises(Socket::Error, "Invalid IPv4 field: 256") { Socket::IPAddress.v4_mapped_v6(256, 0, 0, 0, port: 0) }
      expect_raises(Socket::Error, "Invalid IPv4 field: 256") { Socket::IPAddress.v4_mapped_v6(0, 256, 0, 0, port: 0) }
      expect_raises(Socket::Error, "Invalid IPv4 field: 256") { Socket::IPAddress.v4_mapped_v6(0, 0, 256, 0, port: 0) }
      expect_raises(Socket::Error, "Invalid IPv4 field: 256") { Socket::IPAddress.v4_mapped_v6(0, 0, 0, 256, port: 0) }
      expect_raises(Socket::Error, "Invalid IPv4 field: -1") { Socket::IPAddress.v4_mapped_v6(-1, 0, 0, 0, port: 0) }
      expect_raises(Socket::Error, "Invalid IPv4 field: -1") { Socket::IPAddress.v4_mapped_v6(0, -1, 0, 0, port: 0) }
      expect_raises(Socket::Error, "Invalid IPv4 field: -1") { Socket::IPAddress.v4_mapped_v6(0, 0, -1, 0, port: 0) }
      expect_raises(Socket::Error, "Invalid IPv4 field: -1") { Socket::IPAddress.v4_mapped_v6(0, 0, 0, -1, port: 0) }
    end

    it "raises on out of bound port number" do
      expect_raises(Socket::Error, "Invalid port number: 65536") { Socket::IPAddress.v4_mapped_v6(0, 0, 0, 0, port: 65536) }
      expect_raises(Socket::Error, "Invalid port number: -1") { Socket::IPAddress.v4_mapped_v6(0, 0, 0, 0, port: -1) }
    end

    it "constructs from StaticArray" do
      Socket::IPAddress.v4_mapped_v6(UInt8.static_array(0, 0, 0, 0), 0).should eq Socket::IPAddress.new("::ffff:0.0.0.0", 0)
      Socket::IPAddress.v4_mapped_v6(UInt8.static_array(127, 0, 0, 1), 1234).should eq Socket::IPAddress.new("::ffff:127.0.0.1", 1234)
      Socket::IPAddress.v4_mapped_v6(UInt8.static_array(192, 168, 0, 1), 8081).should eq Socket::IPAddress.new("::ffff:192.168.0.1", 8081)
      Socket::IPAddress.v4_mapped_v6(UInt8.static_array(255, 255, 255, 254), 65535).should eq Socket::IPAddress.new("::ffff:255.255.255.254", 65535)
    end
  end

  it ".valid_v6?" do
    Socket::IPAddress.valid_v6?("::1").should be_true
    Socket::IPAddress.valid_v6?("x").should be_false
    Socket::IPAddress.valid_v6?("127.0.0.1").should be_false
  end

  it ".valid_v4?" do
    Socket::IPAddress.valid_v4?("127.0.0.1").should be_true
    Socket::IPAddress.valid_v4?("::1").should be_false
    Socket::IPAddress.valid_v4?("x").should be_false
  end

  it ".valid?" do
    Socket::IPAddress.valid?("127.0.0.1").should be_true
    Socket::IPAddress.valid?("::1").should be_true
    Socket::IPAddress.valid?("x").should be_false
  end

  it "#loopback?" do
    Socket::IPAddress.new("127.0.0.1", 0).loopback?.should be_true
    Socket::IPAddress.new("127.255.255.254", 0).loopback?.should be_true
    Socket::IPAddress.new("128.0.0.1", 0).loopback?.should be_false
    Socket::IPAddress.new("0.0.0.0", 0).loopback?.should be_false
    Socket::IPAddress.new("::1", 0).loopback?.should be_true
    Socket::IPAddress.new("0000:0000:0000:0000:0000:0000:0000:0001", 0).loopback?.should be_true
    Socket::IPAddress.new("::2", 0).loopback?.should be_false
    Socket::IPAddress.new(Socket::IPAddress::LOOPBACK, 0).loopback?.should be_true
    Socket::IPAddress.new(Socket::IPAddress::LOOPBACK6, 0).loopback?.should be_true
    Socket::IPAddress.new("::ffff:127.0.0.1", 0).loopback?.should be_true
    Socket::IPAddress.new("::ffff:127.0.1.1", 0).loopback?.should be_true
    Socket::IPAddress.new("::ffff:1.0.0.1", 0).loopback?.should be_false
  end

  it "#unspecified?" do
    Socket::IPAddress.new("0.0.0.0", 0).unspecified?.should be_true
    Socket::IPAddress.new("127.0.0.1", 0).unspecified?.should be_false
    Socket::IPAddress.new("::", 0).unspecified?.should be_true
    Socket::IPAddress.new("0000:0000:0000:0000:0000:0000:0000:0000", 0).unspecified?.should be_true
    Socket::IPAddress.new(Socket::IPAddress::UNSPECIFIED, 0).unspecified?.should be_true
    Socket::IPAddress.new(Socket::IPAddress::UNSPECIFIED6, 0).unspecified?.should be_true
  end

  it ".valid_port?" do
    Socket::IPAddress.valid_port?(0).should be_true
    Socket::IPAddress.valid_port?(80).should be_true
    Socket::IPAddress.valid_port?(65_535).should be_true

    Socket::IPAddress.valid_port?(-1).should be_false
    Socket::IPAddress.valid_port?(65_536).should be_false
  end

  it "#private?" do
    Socket::IPAddress.new("192.168.0.1", 0).private?.should be_true
    Socket::IPAddress.new("192.100.0.1", 0).private?.should be_false
    Socket::IPAddress.new("172.16.0.1", 0).private?.should be_true
    Socket::IPAddress.new("172.10.0.1", 0).private?.should be_false
    Socket::IPAddress.new("10.0.0.1", 0).private?.should be_true
    Socket::IPAddress.new("1.1.1.1", 0).private?.should be_false
    Socket::IPAddress.new("fd00::1", 0).private?.should be_true
    Socket::IPAddress.new("fb00::1", 0).private?.should be_false
    Socket::IPAddress.new("2001:4860:4860::8888", 0).private?.should be_false
  end

  it "#link_local?" do
    Socket::IPAddress.new("0.0.0.0", 0).link_local?.should be_false
    Socket::IPAddress.new("127.0.0.1", 0).link_local?.should be_false
    Socket::IPAddress.new("10.0.0.0", 0).link_local?.should be_false
    Socket::IPAddress.new("172.16.0.0", 0).link_local?.should be_false
    Socket::IPAddress.new("192.168.0.0", 0).link_local?.should be_false

    Socket::IPAddress.new("169.254.1.1", 0).link_local?.should be_true
    Socket::IPAddress.new("169.254.254.255", 0).link_local?.should be_true

    Socket::IPAddress.new("::1", 0).link_local?.should be_false
    Socket::IPAddress.new("::", 0).link_local?.should be_false
    Socket::IPAddress.new("fb84:8bf7:e905::1", 0).link_local?.should be_false

    Socket::IPAddress.new("fe80::4860:4860:4860:1234", 0).link_local?.should be_true
  end

  it "#==" do
    Socket::IPAddress.new("127.0.0.1", 8080).should eq Socket::IPAddress.new("127.0.0.1", 8080)
    Socket::IPAddress.new("127.0.0.1", 8080).hash.should eq Socket::IPAddress.new("127.0.0.1", 8080).hash

    Socket::IPAddress.new("127.0.0.1", 8080).should_not eq Socket::IPAddress.new("127.0.0.1", 8081)
    Socket::IPAddress.new("127.0.0.1", 8080).hash.should_not eq Socket::IPAddress.new("127.0.0.1", 8081).hash

    Socket::IPAddress.new("127.0.0.1", 8080).should_not eq Socket::IPAddress.new("127.0.0.2", 8080)
    Socket::IPAddress.new("127.0.0.1", 8080).hash.should_not eq Socket::IPAddress.new("127.0.0.2", 8080).hash
  end
end

{% if flag?(:unix) %}
  describe Socket::UNIXAddress do
    it "transforms into a C struct and back" do
      path = "unix_address.sock"

      addr1 = Socket::UNIXAddress.new(path)
      addr2 = Socket::UNIXAddress.from(addr1.to_unsafe, addr1.size)

      addr2.family.should eq(addr1.family)
      addr2.path.should eq(addr1.path)
      addr2.to_s.should eq(path)
      addr2 = Socket::UNIXAddress.from(addr1.to_unsafe)
    end

    it "raises when path is too long" do
      path = "unix_address-too-long-#{("a" * 2048)}.sock"

      expect_raises(ArgumentError, "Path size exceeds the maximum size") do
        Socket::UNIXAddress.new(path)
      end
    end

    it "to_s" do
      Socket::UNIXAddress.new("some_path").to_s.should eq("some_path")
    end

    it "#==" do
      Socket::UNIXAddress.new("some_path").should eq Socket::UNIXAddress.new("some_path")
      Socket::UNIXAddress.new("some_path").hash.should eq Socket::UNIXAddress.new("some_path").hash

      Socket::UNIXAddress.new("some_path").should_not eq Socket::UNIXAddress.new("other_path")
      Socket::UNIXAddress.new("some_path").hash.should_not eq Socket::UNIXAddress.new("other_path").hash
    end

    it "accepts `Path` input" do
      Socket::UNIXAddress.new(Path.new("some_path")).should eq Socket::UNIXAddress.new("some_path")
    end

    describe ".parse" do
      it "parses relative" do
        address = Socket::UNIXAddress.parse "unix://foo.sock"
        address.should eq Socket::UNIXAddress.new("foo.sock")
      end

      it "parses relative subpath" do
        address = Socket::UNIXAddress.parse "unix://foo/bar.sock"
        address.should eq Socket::UNIXAddress.new("foo/bar.sock")
      end

      it "parses relative dot" do
        address = Socket::UNIXAddress.parse "unix://./bar.sock"
        address.should eq Socket::UNIXAddress.new("./bar.sock")
      end

      it "relative with" do
        address = Socket::UNIXAddress.parse "unix://foo:21/bar.sock"
        address.should eq Socket::UNIXAddress.new("foo:21/bar.sock")
      end

      it "parses absolute" do
        address = Socket::UNIXAddress.parse "unix:///foo.sock"
        address.should eq Socket::UNIXAddress.new("/foo.sock")
      end

      it "ignores params" do
        address = Socket::UNIXAddress.parse "unix:///foo.sock?bar=baz"
        address.should eq Socket::UNIXAddress.new("/foo.sock")
      end

      it "fails with missing path" do
        expect_raises(Socket::Error, "Invalid UNIX address: missing path") do
          Socket::UNIXAddress.parse "unix://?foo=bar"
        end
      end
    end
  end
{% end %}

describe Socket do
  # Most of the specs are moved to `.parse_v4_fields?` and `.parse_v6_fields?`,
  # which are implemented in pure Crystal; the remaining ones here are test
  # cases that were once known to break on certain platforms when `Socket.ip?`
  # was still using the system `inet_pton`
  it ".ip?" do
    Socket.ip?("1.2.03.4").should be_false
    Socket.ip?("::012.34.56.78").should be_false
    Socket.ip?("a:0b:00c:000d:0000e:f::").should be_false
    Socket.ip?("::1:2:3:4:5:6:7").should be_true
  end

  it "==" do
    a = Socket::IPAddress.new("127.0.0.1", 8080)
    b = Socket::UNIXAddress.new("some_path")
    c = "some_path"
    (a == a).should be_true
    (b == b).should be_true
    (a == b).should be_false
    (a == c).should be_false
    (b == c).should be_false
  end
end
