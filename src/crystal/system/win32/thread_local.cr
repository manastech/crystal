# NOTE: Uses FLS instead of TLS so we can register a destructor while creating
# the key. Since we don't use the Windows Fiber API, FLS acts exactly the same
# as TLS.
#
# See <https://learn.microsoft.com/en-us/windows/win32/procthread/fibers#fiber-local-storage>
require "c/fibersapi"

struct Crystal::System::ThreadLocal(T)
  @key : LibC::DWORD

  def initialize
    {% raise "Can only create Crystal::System::ThreadLocal with pointer types or reference types, not #{T}" unless T < Pointer || T < Reference %}
    @key = LibC.FlsAlloc(nil)
    raise RuntimeError.from_winerror("FlsAlloc") if @key == LibC::FLS_OUT_OF_INDEXES
  end

  def initialize(&destructor : T ->)
    {% raise "Can only create Crystal::System::ThreadLocal with pointer types or reference types, not #{T}" unless T < Pointer || T < Reference %}
    @key = LibC.FlsAlloc(destructor.unsafe_as(Proc(Void*, Nil)))
    raise RuntimeError.from_winerror("FlsAlloc") if @key == LibC::FLS_OUT_OF_INDEXES
  end

  def get? : T?
    ptr = LibC.FlsGetValue(@key)
    ptr.as(T) if ptr
  end

  def set(value : T) : T
    ret = LibC.FlsSetValue(@key, value.as(Void*))
    raise RuntimeError.from_winerror("FlsSetValue") unless ret
    value
  end

  def release : Nil
    ret = LibC.FlsFree(@key)
    raise RuntimeError.from_winerror("FlsFree") unless ret
  end
end
