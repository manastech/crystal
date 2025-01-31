require "c/pthread"

struct Crystal::System::ThreadLocal(T)
  @key : LibC::PthreadKeyT

  def initialize
    {% raise "Can only create Crystal::System::ThreadLocal with pointer types or reference types, not #{T}" unless T < Pointer || T < Reference %}
    ret = LibC.pthread_key_create(out @key, nil)
    raise RuntimeError.from_os_error("pthread_key_create", Errno.new(ret)) unless ret == 0
  end

  def initialize(&destructor : T ->)
    {% raise "Can only create Crystal::System::ThreadLocal with pointer types or reference types, not #{T}" unless T < Pointer || T < Reference %}
    ret = LibC.pthread_key_create(out @key, destructor.unsafe_as(Proc(Void*, Nil)))
    raise RuntimeError.from_os_error("pthread_key_create", Errno.new(ret)) unless ret == 0
  end

  def get? : T?
    ptr = LibC.pthread_getspecific(@key)
    ptr.as(T) if ptr
  end

  def set(value : T) : T
    ret = LibC.pthread_setspecific(@key, value.as(Void*))
    raise RuntimeError.from_os_error("pthread_setspecific", Errno.new(ret)) unless ret == 0
    value
  end

  def release : Nil
    ret = LibC.pthread_key_delete(@key)
    raise RuntimeError.from_os_error("pthread_key_delete", Errno.new(ret)) unless ret == 0
  end
end
