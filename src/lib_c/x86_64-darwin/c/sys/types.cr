require "../stddef"
require "../stdint"

lib LibC
  alias BlkcntT = LongLong
  alias BlksizeT = Int
  alias ClockT = ULong
  alias DevT = Int
  alias GidT = UInt
  alias IdT = UInt
  alias InoT = UInt64
  alias ModeT = UShort
  alias NlinkT = UShort
  alias OffT = LongLong
  alias PidT = Int

  struct PthreadAttrT
    __sig : Long
    __opaque : StaticArray(Char, 56)
  end

  struct PthreadCondT
    __sig : Long
    __opaque : StaticArray(Char, 40)
  end

  struct PthreadCondattrT
    __sig : Long
    __opaque : StaticArray(Char, 8)
  end

  struct PthreadMutexT
    __sig : Long
    __opaque : StaticArray(Char, 56)
  end

  struct PthreadMutexattrT
    __sig : Long
    __opaque : StaticArray(Char, 8)
  end

  type PthreadT = Void*
  alias PthreadKeyT = UInt
  alias SSizeT = Long
  alias SusecondsT = Int
  alias TimeT = Long
  alias UidT = UInt
end
