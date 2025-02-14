require "./in6addr"
require "./inaddr"
require "./stdint"

@[Link("iphlpapi")]
lib LibC
  NDIS_IF_MAX_STRING_SIZE = 256u16
  IF_NAMESIZE             = LibC::NDIS_IF_MAX_STRING_SIZE + 1 # need one more byte for terminating '\0'

  fun if_nametoindex(ifname : Char*) : UInt
  fun if_indextoname(ifindex : UInt, ifname : LibC::Char*) : LibC::Char*
end
