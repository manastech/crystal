class IPSocket < Socket
  # Returns the `IPAddress` for the local end of the IP socket.
  def local_address
    sockaddr6 = uninitialized LibC::SockaddrIn6
    sockaddr = pointerof(sockaddr6).as(LibC::Sockaddr*)
    addrlen = LibC::SocklenT.new(sizeof(LibC::SockaddrIn6))

    if LibC.getsockname(fd, sockaddr, pointerof(addrlen)) != 0
      raise OSError.create("getsockname")
    end

    IPAddress.from(sockaddr, addrlen)
  end

  # Returns the `IPAddress` for the remote end of the IP socket.
  def remote_address
    sockaddr6 = uninitialized LibC::SockaddrIn6
    sockaddr = pointerof(sockaddr6).as(LibC::Sockaddr*)
    addrlen = LibC::SocklenT.new(sizeof(LibC::SockaddrIn6))

    if LibC.getpeername(fd, sockaddr, pointerof(addrlen)) != 0
      raise OSError.create("getpeername")
    end

    IPAddress.from(sockaddr, addrlen)
  end
end
