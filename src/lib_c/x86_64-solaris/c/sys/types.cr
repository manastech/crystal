require "../stddef"
require "../stdint"

lib LibC
  alias BlkcntT = Long
  alias BlksizeT = Int
  alias ClockT = Long
  alias ClockidT = Int
  alias DevT = ULong
  alias GidT = UInt
  alias IdT = Int
  alias InoT = ULong
  alias ModeT = UInt
  alias NlinkT = UInt
  alias OffT = Long
  alias PidT = Int

  struct PthreadAttrT
    __pthread_attrp : Void*
  end

  struct PthreadCondT
    __pthread_cond_flag : UInt8[4]
    __pthread_cond_type : UInt16
    __pthread_cond_magic : UInt16
    __pthread_cond_data : UInt64
  end

  struct PthreadCondattrT
    __pthread_condattrp : Void*
  end

  struct PthreadMutexT
    __pthread_mutex_flag1 : UInt16
    __pthread_mutex_flag2 : UInt8
    __pthread_mutex_ceiling : UInt8
    __pthread_mutex_type : UInt16
    __pthread_mutex_magic : UInt16
    __pthread_mutex_lock : UInt64 # actually a union with {UInt8[8]} and {UInt32, UInt32}
    __pthread_mutex_data : UInt64
  end

  struct PthreadMutexattrT
    __pthread_mutexattrp : Void*
  end

  alias PthreadT = UInt
  alias PthreadKeyT = Int

  alias SSizeT = Long
  alias SusecondsT = Long
  alias TimeT = Long
  alias UidT = UInt
end
