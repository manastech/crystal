require "../stddef"
require "../stdint"

lib LibC
  alias BlkcntT = Long
  alias BlksizeT = Int
  alias ClockT = Int
  alias ClockidT = Int
  alias DevT = ULong
  alias GidT = UInt
  alias IdT = Long
  alias InoT = ULong
  alias ModeT = UShort
  alias NlinkT = ULong
  alias OffT = Long
  alias PidT = Int
  type PthreadAttrT = Void*
  type PthreadCondT = Void*
  type PthreadCondattrT = Void*
  alias PthreadKeyT = Int
  type PthreadMutexT = Void*
  type PthreadMutexattrT = Void*
  type PthreadT = Void*
  alias SSizeT = Long
  alias SusecondsT = Long
  alias TimeT = Long
  alias UidT = UInt
end
