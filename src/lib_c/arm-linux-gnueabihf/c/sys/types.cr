require "../stddef"
require "../stdint"

lib LibC
  alias BlkcntT = Long
  alias BlksizeT = Long
  alias ClockT = Long
  alias ClockidT = Int
  alias DevT = ULongLong
  alias GidT = UInt
  alias IdT = UInt
  alias InoT = ULong
  alias ModeT = UInt
  alias NlinkT = UInt
  alias OffT = Long
  alias PidT = Int

  union PthreadAttrT
    __size : StaticArray(Char, 36)
    __align : Long
  end

  struct PthreadCondTData
    __lock : Int
    __futex : UInt
    __total_seq : ULongLong
    __wakeup_seq : ULongLong
    __woken_seq : ULongLong
    __mutex : Void*
    __nwaiters : UInt
    __broadcast_seq : UInt
  end

  union PthreadCondT
    __data : PthreadCondTData
    __size : StaticArray(Char, 48)
    __align : LongLong
  end

  union PthreadCondattrT
    __size : StaticArray(Char, 4)
    __align : Long
  end

  union PthreadMutexT
    __data : Void*
    __size : StaticArray(Char, 24)
    __align : Long
  end

  union PthreadMutexattrT
    __size : StaticArray(Char, 4)
    __align : Long
  end

  alias PthreadT = ULong
  alias PthreadKeyT = UInt
  alias SSizeT = Int
  alias SusecondsT = Long
  alias TimeT = Long
  alias UidT = UInt
end
