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

  union PthreadAttrTU
    __i : StaticArray(Int, 9)
    __vi : StaticArray(Int, 9)
    __s : StaticArray(UInt, 9)
  end

  struct PthreadAttrT
    __u : PthreadAttrTU
  end

  union PthreadCondTU
    __i : StaticArray(Int, 12)
    __vi : StaticArray(Int, 12)
    __p : StaticArray(Void*, 12)
  end

  struct PthreadCondT
    __u : PthreadCondTU
  end

  struct PthreadCondattrT
    __attr : UInt
  end

  union PthreadMutexTU
    __i : StaticArray(Int, 6)
    __vi : StaticArray(Int, 6)
    __p : StaticArray(Void*, 6)
  end

  struct PthreadMutexT
    __u : PthreadMutexTU
  end

  struct PthreadMutexattrT
    __attr : UInt
  end

  type PthreadT = Void*
  alias PthreadKeyT = UInt
  alias SSizeT = Int
  alias SusecondsT = Long
  alias TimeT = Long
  alias UidT = UInt
end
