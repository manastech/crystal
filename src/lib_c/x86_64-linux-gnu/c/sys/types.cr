require "../stddef"
require "../stdint"

lib LibC
  alias BlkcntT = Long
  alias BlksizeT = Long
  alias ClockT = Long
  alias ClockidT = Int
  alias DevT = ULong
  alias GidT = UInt
  alias IdT = UInt
  alias InoT = ULong
  alias ModeT = UInt
  alias NlinkT = ULong
  alias OffT = Long
  alias PidT = Int

  union PthreadAttrT
    __size : StaticArray(Char, 56)
    __align : Long
  end

  union PthreadCondT
    __size : StaticArray(Char, 48)
    __align : LongLong
  end

  union PthreadCondattrT
    __size : StaticArray(Char, 4)
    __align : Int
  end

  union PthreadMutexT
    __size : StaticArray(Char, 40)
    __align : Long
  end

  union PthreadMutexattrT
    __size : StaticArray(Char, 4)
    __align : Int
  end

  alias PthreadKeyT = UInt
  alias PthreadT = ULong
  alias SSizeT = Long
  alias SusecondsT = Long
  alias TimeT = Long
  alias UidT = UInt
end
