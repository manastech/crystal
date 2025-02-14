{% if flag?(:win32) %}
  require "c/ws2tcpip"
  require "c/afunix"
  require "c/netioapi"
{% elsif flag?(:wasi) %}
  require "c/arpa/inet"
  require "c/netinet/in"
  require "c/net/if"
{% else %}
  require "c/arpa/inet"
  require "c/sys/un"
  require "c/netinet/in"
  require "c/net/if"
{% end %}

class Socket < IO
  enum Protocol
    IP = LibC::IPPROTO_IP
    {% if flag?(:win32) %}
      TCP  = LibC::IPPROTO::IPPROTO_TCP
      UDP  = LibC::IPPROTO::IPPROTO_UDP
      RAW  = LibC::IPPROTO::IPPROTO_RAW
      ICMP = LibC::IPPROTO::IPPROTO_ICMP
    {% else %}
      TCP  = LibC::IPPROTO_TCP
      UDP  = LibC::IPPROTO_UDP
      RAW  = LibC::IPPROTO_RAW
      ICMP = LibC::IPPROTO_ICMP
    {% end %}
  end

  # :nodoc:
  {% if flag?(:win32) %}
    alias FamilyT = UInt8
  {% else %}
    alias FamilyT = LibC::SaFamilyT
  {% end %}

  enum Family : FamilyT
    UNSPEC = LibC::AF_UNSPEC
    UNIX   = LibC::AF_UNIX
    INET   = LibC::AF_INET
    INET6  = LibC::AF_INET6
  end

  enum Type
    STREAM = LibC::SOCK_STREAM
    DGRAM  = LibC::SOCK_DGRAM
    {% unless flag?(:wasi) %}
      RAW       = LibC::SOCK_RAW
      SEQPACKET = LibC::SOCK_SEQPACKET
    {% end %}
  end

  class Error < IO::Error
    private def self.new_from_os_error(message, os_error, **opts)
      case os_error
      when Errno::ECONNREFUSED
        Socket::ConnectError.new(message, **opts)
      when Errno::EADDRINUSE
        Socket::BindError.new(message, **opts)
      else
        super message, os_error, **opts
      end
    end
  end

  class ConnectError < Error
  end

  class BindError < Error
  end
end
