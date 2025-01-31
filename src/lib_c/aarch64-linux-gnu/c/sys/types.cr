require "../stddef"
require "../stdint"

lib LibC
  alias BlkcntT = Long
  alias BlksizeT = Int
  alias ClockT = Long
  alias ClockidT = Int
  alias DevT = ULong
  alias GidT = UInt
  alias IdT = UInt
  alias InoT = ULong
  alias ModeT = UInt
  alias NlinkT = UInt
  alias OffT = Long
  alias PidT = Int

  union PthreadAttrT
    __size : StaticArray(Char, 64)
    __align : Long
  end

  union PthreadCondT
    __size : StaticArray(Char, 48)
    __align : LongLong
  end

  union PthreadCondattrT
    __size : StaticArray(Char, 8)
    __align : Int
  end

  union PthreadMutexT
    __size : StaticArray(Char, 48)
    __align : Long
  end

  union PthreadMutexattrT
    __size : StaticArray(Char, 8)
    __align : Int
  end

  alias PthreadT = ULong
  alias PthreadKeyT = UInt
  alias SSizeT = Long
  alias SusecondsT = Long
  alias TimeT = Long
  alias UidT = UInt
end
