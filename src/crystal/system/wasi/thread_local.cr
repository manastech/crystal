# TODO: we don't support threads in WASI yet; the thread local is just a faking
# it for the time being.

struct Crystal::System::ThreadLocal(T)
  @value : T?

  def initialize
    {% raise "Can only create Crystal::System::ThreadLocal with pointer types or reference types, not #{T}" unless T < Pointer || T < Reference %}
  end

  def initialize(&destructor : T ->)
    {% raise "Can only create Crystal::System::ThreadLocal with pointer types or reference types, not #{T}" unless T < Pointer || T < Reference %}
  end

  def get? : T?
    @value
  end

  def set(value : T) : T
    @value = value
  end

  def release : Nil
    @value = nil
  end
end
