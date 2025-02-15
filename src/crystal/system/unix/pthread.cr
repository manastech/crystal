require "c/pthread"
require "c/sched"
require "../panic"
{% if flag?(:openbsd) || flag?(:android) %}
  require "../thread_local"
{% end %}

module Crystal::System::Thread
  alias Handle = LibC::PthreadT

  def to_unsafe
    @system_handle
  end

  protected setter system_handle

  private def init_handle
    # NOTE: `@system_handle` needs to be set here too, not just in
    # `.thread_proc`, since the current thread might progress first; the value
    # of `LibC.pthread_self` inside the new thread must be equal to this
    # `@system_handle` after `pthread_create` returns
    ret = GC.pthread_create(
      thread: pointerof(@system_handle),
      attr: Pointer(LibC::PthreadAttrT).null,
      start: ->Thread.thread_proc(Void*),
      arg: self.as(Void*),
    )

    raise RuntimeError.from_os_error("pthread_create", Errno.new(ret)) unless ret == 0
  end

  def self.init : Nil
    {% if flag?(:musl) %}
      @@main_handle = current_handle
    {% elsif flag?(:openbsd) || flag?(:android) %}
      @@current_thread = ThreadLocal(::Thread).new
    {% end %}
  end

  def self.thread_proc(data : Void*) : Void*
    th = data.as(::Thread)

    # `#start` calls `#stack_address`, which might read `@system_handle` before
    # `GC.pthread_create` updates it in the original thread that spawned the
    # current one, so we also assign to it here
    th.system_handle = current_handle

    th.start
    Pointer(Void).null
  end

  def self.current_handle : Handle
    LibC.pthread_self
  end

  def self.yield_current : Nil
    ret = LibC.sched_yield
    raise RuntimeError.from_errno("sched_yield") unless ret == 0
  end

  # No support for @[::ThreadLocal] for OpenBSD, we use pthread's specific storage (TSS)
  # instead
  #
  # Android appears to support @[::ThreadLocal] to some degree, but executables fail with
  # an underaligned TLS segment, see https://github.com/crystal-lang/crystal/issues/13951
  {% if flag?(:openbsd) || flag?(:android) %}
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
    req = uninitialized LibC::Timespec
    req.tv_sec = typeof(req.tv_sec).new(time.seconds)
    req.tv_nsec = typeof(req.tv_nsec).new(time.nanoseconds)

    loop do
      return if LibC.nanosleep(pointerof(req), out rem) == 0
      raise RuntimeError.from_errno("nanosleep() failed") unless Errno.value == Errno::EINTR
      req = rem
    end
  end

  private def system_join : Exception?
    ret = GC.pthread_join(@system_handle)
    RuntimeError.from_os_error("pthread_join", Errno.new(ret)) unless ret == 0
  end

  private def system_close
    GC.pthread_detach(@system_handle)
  end

  private def stack_address : Void*
    address = Pointer(Void).null

    {% if flag?(:darwin) %}
      # FIXME: pthread_get_stacksize_np returns bogus value on macOS X 10.9.0:
      address = LibC.pthread_get_stackaddr_np(@system_handle) - LibC.pthread_get_stacksize_np(@system_handle)
    {% elsif (flag?(:bsd) && !flag?(:openbsd)) || flag?(:solaris) %}
      ret = LibC.pthread_attr_init(out attr)
      unless ret == 0
        LibC.pthread_attr_destroy(pointerof(attr))
        raise RuntimeError.from_os_error("pthread_attr_init", Errno.new(ret))
      end

      if LibC.pthread_attr_get_np(@system_handle, pointerof(attr)) == 0
        LibC.pthread_attr_getstack(pointerof(attr), pointerof(address), out _)
      end
      ret = LibC.pthread_attr_destroy(pointerof(attr))
      raise RuntimeError.from_os_error("pthread_attr_destroy", Errno.new(ret)) unless ret == 0
    {% elsif flag?(:linux) %}
      ret = LibC.pthread_getattr_np(@system_handle, out attr)
      raise RuntimeError.from_os_error("pthread_getattr_np", Errno.new(ret)) unless ret == 0

      LibC.pthread_attr_getstack(pointerof(attr), pointerof(address), out stack_size)

      ret = LibC.pthread_attr_destroy(pointerof(attr))
      raise RuntimeError.from_os_error("pthread_attr_destroy", Errno.new(ret)) unless ret == 0

      # with musl-libc, the main thread does not respect `rlimit -Ss` and
      # instead returns the same default stack size as non-default threads, so
      # we obtain the rlimit to correct the stack address manually
      {% if flag?(:musl) %}
        if Thread.current_is_main?
          if LibC.getrlimit(LibC::RLIMIT_STACK, out rlim) == 0
            address = address + stack_size - rlim.rlim_cur
          else
            raise RuntimeError.from_errno("getrlimit")
          end
        end
      {% end %}
    {% elsif flag?(:openbsd) %}
      ret = LibC.pthread_stackseg_np(@system_handle, out stack)
      raise RuntimeError.from_os_error("pthread_stackseg_np", Errno.new(ret)) unless ret == 0

      address =
        if LibC.pthread_main_np == 1
          stack.ss_sp - stack.ss_size + LibC.sysconf(LibC::SC_PAGESIZE)
        else
          stack.ss_sp - stack.ss_size
        end
    {% else %}
      {% raise "No `Crystal::System::Thread#stack_address` implementation available" %}
    {% end %}

    address
  end

  {% if flag?(:musl) %}
    @@main_handle = uninitialized Handle

    def self.current_is_main?
      current_handle == @@main_handle
    end
  {% end %}

  # Warning: must be called from the current thread itself, because Darwin
  # doesn't allow to set the name of any thread but the current one!
  private def system_name=(name : String) : String
    {% if flag?(:darwin) %}
      LibC.pthread_setname_np(name)
    {% elsif flag?(:netbsd) %}
      LibC.pthread_setname_np(@system_handle, name, nil)
    {% elsif LibC.has_method?(:pthread_setname_np) %}
      LibC.pthread_setname_np(@system_handle, name)
    {% elsif LibC.has_method?(:pthread_set_name_np) %}
      LibC.pthread_set_name_np(@system_handle, name)
    {% else %}
      {% raise "No `Crystal::System::Thread#system_name` implementation available" %}
    {% end %}
    name
  end

  @suspended = Atomic(Bool).new(false)

  def self.init_suspend_resume : Nil
    install_sig_suspend_signal_handler
    install_sig_resume_signal_handler
  end

  private def self.install_sig_suspend_signal_handler
    action = LibC::Sigaction.new
    action.sa_flags = LibC::SA_SIGINFO
    action.sa_sigaction = LibC::SigactionHandlerT.new do |_, _, _|
      # notify that the thread has been interrupted
      Thread.current_thread.@suspended.set(true)

      # block all signals but SIG_RESUME
      mask = uninitialized LibC::SigsetT
      LibC.sigfillset(pointerof(mask))
      LibC.sigdelset(pointerof(mask), SIG_RESUME)

      # suspend the thread until it receives the SIG_RESUME signal
      LibC.sigsuspend(pointerof(mask))
    end
    LibC.sigemptyset(pointerof(action.@sa_mask))
    LibC.sigaction(SIG_SUSPEND, pointerof(action), nil)
  end

  private def self.install_sig_resume_signal_handler
    action = LibC::Sigaction.new
    action.sa_flags = 0
    action.sa_sigaction = LibC::SigactionHandlerT.new do |_, _, _|
      # do nothing (a handler is still required to receive the signal)
    end
    LibC.sigemptyset(pointerof(action.@sa_mask))
    LibC.sigaction(SIG_RESUME, pointerof(action), nil)
  end

  private def system_suspend : Nil
    @suspended.set(false)

    if LibC.pthread_kill(@system_handle, SIG_SUSPEND) == -1
      System.panic("pthread_kill()", Errno.value)
    end
  end

  private def system_wait_suspended : Nil
    until @suspended.get
      Thread.yield_current
    end
  end

  private def system_resume : Nil
    if LibC.pthread_kill(@system_handle, SIG_RESUME) == -1
      System.panic("pthread_kill()", Errno.value)
    end
  end

  # the suspend/resume signals try to follow BDWGC but aren't exact (e.g. it may
  # use SIGUSR1 and SIGUSR2 on FreeBSD instead of SIGRT).

  private SIG_SUSPEND =
    {% if flag?(:linux) %}
      LibC::SIGPWR
    {% elsif LibC.has_constant?(:SIGRTMIN) %}
      LibC::SIGRTMIN + 6
    {% else %}
      LibC::SIGXFSZ
    {% end %}

  private SIG_RESUME =
    {% if LibC.has_constant?(:SIGRTMIN) %}
      LibC::SIGRTMIN + 5
    {% else %}
      LibC::SIGXCPU
    {% end %}

  def self.sig_suspend : ::Signal
    if (gc = GC).responds_to?(:sig_suspend)
      gc.sig_suspend
    else
      ::Signal.new(SIG_SUSPEND)
    end
  end

  def self.sig_resume : ::Signal
    if (gc = GC).responds_to?(:sig_resume)
      gc.sig_resume
    else
      ::Signal.new(SIG_RESUME)
    end
  end
end

# In musl (alpine) the calls to unwind API segfaults
# when the binary is statically linked. This is because
# some symbols like `pthread_once` are defined as "weak"
# and, for some reason, not linked into the final binary.
# Adding an explicit reference to the symbol ensures it's
# included in the statically linked binary.
{% if flag?(:musl) && flag?(:static) %}
  lib LibC
    fun pthread_once(Void*, Void*)
  end

  fun __crystal_static_musl_workaround
    LibC.pthread_once(nil, nil)
  end
{% end %}
