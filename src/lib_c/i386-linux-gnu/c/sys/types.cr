require "../stddef"
require "../stdint"

lib LibC
  alias BlkcntT = LongLong
  alias BlksizeT = Long
  alias ClockT = Long
  alias ClockidT = Int
  alias DevT = ULongLong
  alias GidT = UInt
  alias IdT = UInt
  alias InoT = ULongLong
  alias ModeT = UInt
  alias NlinkT = UInt
  alias OffT = LongLong
  alias PidT = Int

  union PthreadAttrT
    __size : StaticArray(Char, 36)
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
    __size : StaticArray(Char, 24)
    __align : Long
  end

  union PthreadMutexattrT
    __size : StaticArray(Char, 4)
    __align : Int
  end

  alias PthreadT = ULong
  alias PthreadKeyT = UInt
  alias SSizeT = Int
  alias SusecondsT = Long
  alias TimeT = Long
  alias UidT = UInt
end
