require "./sys/types"

# Starting with glibc 2.34, `pthread` is integrated into `libc` and may not even
# be available as a separate shared library.
# There's always a static library for compiled mode, but `Crystal::Loader` does not support
# static libraries. So we just skip `pthread` entirely in interpreted mode.
# The symbols are still available in the interpreter because they are loaded in the compiler.
{% unless flag?(:interpreted) %}
  @[Link("pthread")]
{% end %}
lib LibC
  PTHREAD_MUTEX_ERRORCHECK = 2

  fun pthread_attr_destroy(attr : PthreadAttrT*) : Int
  fun pthread_attr_getstack(addr : PthreadAttrT*, stackaddr : Void**, stacksize : SizeT*) : Int
  fun pthread_condattr_destroy(attr : PthreadCondattrT*) : Int
  fun pthread_condattr_init(attr : PthreadCondattrT*) : Int
  fun pthread_condattr_setclock(attr : PthreadCondattrT*, type : ClockidT) : Int
  fun pthread_cond_broadcast(cond : PthreadCondT*) : Int
  fun pthread_cond_destroy(cond : PthreadCondT*) : Int
  fun pthread_cond_init(cond : PthreadCondT*, cond_attr : PthreadCondattrT*) : Int
  fun pthread_cond_signal(cond : PthreadCondT*) : Int
  fun pthread_cond_timedwait(cond : PthreadCondT*, mutex : PthreadMutexT*, abstime : Timespec*) : Int
  fun pthread_cond_wait(cond : PthreadCondT*, mutex : PthreadMutexT*) : Int
  fun pthread_create(newthread : PthreadT*, attr : PthreadAttrT*, start_routine : Void* -> Void*, arg : Void*) : Int
  fun pthread_detach(th : PthreadT) : Int
  fun pthread_getattr_np(thread : PthreadT, attr : PthreadAttrT*) : Int
  fun pthread_getspecific(PthreadKeyT) : Void*
  fun pthread_join(th : PthreadT, thread_return : Void**) : Int
  alias PthreadKeyDestructor = (Void*) ->
  fun pthread_key_create(PthreadKeyT*, PthreadKeyDestructor) : Int
  fun pthread_key_delete(PthreadKeyT) : Int
  fun pthread_mutexattr_destroy(attr : PthreadMutexattrT*) : Int
  fun pthread_mutexattr_init(attr : PthreadMutexattrT*) : Int
  fun pthread_mutexattr_settype(attr : PthreadMutexattrT*, type : Int) : Int
  fun pthread_mutex_destroy(mutex : PthreadMutexT*) : Int
  fun pthread_mutex_init(mutex : PthreadMutexT*, mutexattr : PthreadMutexattrT*) : Int
  fun pthread_mutex_lock(mutex : PthreadMutexT*) : Int
  fun pthread_mutex_trylock(mutex : PthreadMutexT*) : Int
  fun pthread_mutex_unlock(mutex : PthreadMutexT*) : Int
  fun pthread_self : PthreadT
  fun pthread_setname_np(PthreadT, Char*) : Int
  fun pthread_setspecific(PthreadKeyT, Void*) : Int
end
