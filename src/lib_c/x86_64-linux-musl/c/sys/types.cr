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

  union PthreadAttrTU
    __i : StaticArray(Int, 14)
    __vi : StaticArray(Int, 14)
    __s : StaticArray(ULong, 7)
  end

  struct PthreadAttrT
    __u : PthreadAttrTU
  end

  union PthreadCondTU
    __i : StaticArray(Int, 12)
    __vi : StaticArray(Int, 12)
    __p : StaticArray(Void*, 6)
  end

  struct PthreadCondT
    __u : PthreadCondTU
  end

  struct PthreadCondattrT
    __attr : UInt
  end

  union PthreadMutexTU
    __i : StaticArray(Int, 10)
    __vi : StaticArray(Int, 10)
    __p : StaticArray(Void*, 5)
  end

  struct PthreadMutexT
    __u : PthreadMutexTU
  end

  struct PthreadMutexattrT
    __attr : UInt
  end

  type PthreadT = Void*
  alias PthreadKeyT = UInt
  alias SSizeT = Long
  alias SusecondsT = Long
  alias TimeT = Long
  alias UidT = UInt
end
