require "../netinet/in"
require "../stdint"

lib LibC
  IF_NAMESIZE = 16u8

  fun if_nametoindex(ifname : Char*) : UInt
  fun if_indextoname(ifindex : UInt, ifname : LibC::Char*) : LibC::Char*
end
