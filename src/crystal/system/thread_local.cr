# Stores and retrieves a `Pointer` or `Reference` in the system Thread Local
# Storage (TLS), also named Thread Specific Storage (TSS).
#
# WARNING: Thread local storage is unknown to the GC. When storing a `Reference`
# or a `Pointer` to the GC HEAP memory, you must make sure that there are other
# live references to that memory, otherwise the GC might decide to collect it!
struct Crystal::System::ThreadLocal(T)
  # Initializes a global thread local index/key.
  def initialize
    raise NotImplementedError.new
  end

  # Initializes a global thread local index/key. The destructor must be called
  # in each thread that terminates if the thread local value has been set.
  def initialize(&destructor : T ->)
    raise NotImplementedError.new
  end

  # Returns the thread local value if previously set, otherwise runs the
  # initializer to create the value, sets the thread local and returns it.
  def get(&initializer : -> T) : T
    get? || set(yield)
  end

  # Returns the thread local value if previously set, otherwise returns `nil`.
  def get? : T?
    raise NotImplementedError.new
  end

  # Sets the thread local to *value*. Doesn't call the destructor when replacing
  # a thread local value; you are responsible for retrieving the previous value
  # and doing any cleanup. Returns *value*.
  def set(value : T) : T
    raise NotImplementedError.new
  end

  # Releases the thread local index/key. Assumes every thread will no longer
  # need to access this thread local.
  def release : Nil
    raise NotImplementedError.new
  end
end

{% if flag?(:wasm32) %}
  require "./wasi/thread_local"
{% elsif flag?(:unix) %}
  require "./unix/thread_local"
{% elsif flag?(:win32) %}
  require "./win32/thread_local"
{% else %}
  {% raise "unsupported target" %}
{% end %}
