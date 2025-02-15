require "c/processthreadsapi"
require "c/synchapi"
require "../panic"
{% if flag?(:gnu) %}
  require "../thread_local"
{% end %}

module Crystal::System::Thread
  alias Handle = LibC::HANDLE

  def to_unsafe
    @system_handle
  end

  private def init_handle
    @system_handle = GC.beginthreadex(
      security: Pointer(Void).null,
      stack_size: LibC::UInt.zero,
      start_address: ->Thread.thread_proc(Void*),
      arglist: self.as(Void*),
      initflag: LibC::UInt.zero,
      thrdaddr: Pointer(LibC::UInt).null,
    )
  end

  def self.init : Nil
    {% if flag?(:gnu) %}
      @@current_thread = ThreadLocal(::Thread).new
    {% end %}
  end

  def self.thread_proc(data : Void*) : LibC::UInt
    # ensure that even in the case of stack overflow there is enough reserved
    # stack space for recovery (for the main thread this is done in
    # `Exception::CallStack.setup_crash_handler`)
    stack_size = Crystal::System::Fiber::RESERVED_STACK_SIZE
    LibC.SetThreadStackGuarantee(pointerof(stack_size))

    data.as(::Thread).start
    LibC::UInt.zero
  end

  def self.current_handle : Handle
    # `GetCurrentThread` returns a _constant_ and is only meaningful as an
    # argument to Win32 APIs; to uniquely identify it we must duplicate the handle
    cur_proc = LibC.GetCurrentProcess
    if LibC.DuplicateHandle(cur_proc, LibC.GetCurrentThread, cur_proc, out handle, 0, true, LibC::DUPLICATE_SAME_ACCESS) == 0
      raise RuntimeError.from_winerror("DuplicateHandle")
    end
    handle
  end

  def self.yield_current : Nil
    LibC.SwitchToThread
  end

  # MinGW does not support @[::ThreadLocal] correctly
  {% if flag?(:gnu) %}
    @@current_thread = uninitialized ThreadLocal(::Thread)

    def self.current_thread : ::Thread
      # Thread#start sets Thread.current as soon as it starts. Thus we know
      # that if `Thread.current` is not set then we are in the main thread
      @@current_thread.get { ::Thread.new }
    end

    def self.current_thread? : ::Thread?
      @@current_thread.get?
    end

    def self.current_thread=(thread : ::Thread)
      @@current_thread.set(thread)
    end
  {% else %}
    @[::ThreadLocal]
    @@current_thread : ::Thread?

    def self.current_thread : ::Thread
      @@current_thread ||= ::Thread.new
    end

    def self.current_thread? : ::Thread?
      @@current_thread
    end

    def self.current_thread=(@@current_thread : ::Thread)
    end
  {% end %}

  def self.sleep(time : ::Time::Span) : Nil
    LibC.Sleep(time.total_milliseconds.to_i.clamp(1..))
  end

  private def system_join : Exception?
    if LibC.WaitForSingleObject(@system_handle, LibC::INFINITE) != LibC::WAIT_OBJECT_0
      return RuntimeError.from_winerror("WaitForSingleObject")
    end
    if LibC.CloseHandle(@system_handle) == 0
      return RuntimeError.from_winerror("CloseHandle")
    end
  end

  private def system_close
    LibC.CloseHandle(@system_handle)
  end

  private def stack_address : Void*
    {% if LibC.has_method?("GetCurrentThreadStackLimits") %}
      LibC.GetCurrentThreadStackLimits(out low_limit, out high_limit)
      Pointer(Void).new(low_limit)
    {% else %}
      tib = LibC.NtCurrentTeb
      high_limit = tib.value.stackBase
      if LibC.VirtualQuery(tib.value.stackLimit, out mbi, sizeof(LibC::MEMORY_BASIC_INFORMATION)) == 0
        raise RuntimeError.from_winerror("VirtualQuery")
      end
      low_limit = mbi.allocationBase
      low_limit
    {% end %}
  end

  private def system_name=(name : String) : String
    {% if LibC.has_method?(:SetThreadDescription) %}
      LibC.SetThreadDescription(@system_handle, System.to_wstr(name))
    {% end %}
    name
  end

  def self.init_suspend_resume : Nil
  end

  private def system_suspend : Nil
    if LibC.SuspendThread(@system_handle) == -1
      Crystal::System.panic("SuspendThread()", WinError.value)
    end
  end

  private def system_wait_suspended : Nil
    # context must be aligned on 16 bytes but we lack a mean to force the
    # alignment on the struct, so we overallocate then realign the pointer:
    local = uninitialized UInt8[sizeof(Tuple(LibC::CONTEXT, UInt8[15]))]
    thread_context = Pointer(LibC::CONTEXT).new(local.to_unsafe.address &+ 15_u64 & ~15_u64)
    thread_context.value.contextFlags = LibC::CONTEXT_FULL

    if LibC.GetThreadContext(@system_handle, thread_context) == -1
      Crystal::System.panic("GetThreadContext()", WinError.value)
    end
  end

  private def system_resume : Nil
    if LibC.ResumeThread(@system_handle) == -1
      Crystal::System.panic("ResumeThread()", WinError.value)
    end
  end
end
