require "./sys/types"

lib LibC
  PTHREAD_MUTEX_ERRORCHECK = 1

  fun pthread_condattr_destroy(x0 : PthreadCondattrT*) : Int
  fun pthread_condattr_init(x0 : PthreadCondattrT*) : Int
  fun pthread_cond_broadcast(x0 : PthreadCondT*) : Int
  fun pthread_cond_destroy(x0 : PthreadCondT*) : Int
  fun pthread_cond_init(x0 : PthreadCondT*, x1 : PthreadCondattrT*) : Int
  fun pthread_cond_signal(x0 : PthreadCondT*) : Int
  fun pthread_cond_timedwait_relative_np(x0 : PthreadCondT*, x1 : PthreadMutexT*, x2 : Timespec*) : Int
  fun pthread_cond_wait(x0 : PthreadCondT*, x1 : PthreadMutexT*) : Int
  fun pthread_create(x0 : PthreadT*, x1 : PthreadAttrT*, x2 : Void* -> Void*, x3 : Void*) : Int
  fun pthread_detach(x0 : PthreadT) : Int
  fun pthread_get_stackaddr_np(x0 : PthreadT) : Void*
  fun pthread_get_stacksize_np(x0 : PthreadT) : SizeT
  fun pthread_getspecific(PthreadKeyT) : Void*
  fun pthread_join(x0 : PthreadT, x1 : Void**) : Int
  alias PthreadKeyDestructor = (Void*) ->
  fun pthread_key_create(PthreadKeyT*, PthreadKeyDestructor) : Int
  fun pthread_key_delete(PthreadKeyT) : Int
  fun pthread_mutexattr_destroy(x0 : PthreadMutexattrT*) : Int
  fun pthread_mutexattr_init(x0 : PthreadMutexattrT*) : Int
  fun pthread_mutexattr_settype(x0 : PthreadMutexattrT*, x1 : Int) : Int
  fun pthread_mutex_destroy(x0 : PthreadMutexT*) : Int
  fun pthread_mutex_init(x0 : PthreadMutexT*, x1 : PthreadMutexattrT*) : Int
  fun pthread_mutex_lock(x0 : PthreadMutexT*) : Int
  fun pthread_mutex_trylock(x0 : PthreadMutexT*) : Int
  fun pthread_mutex_unlock(x0 : PthreadMutexT*) : Int
  fun pthread_self : PthreadT
  fun pthread_setname_np(Char*) : Int
  fun pthread_setspecific(PthreadKeyT, Void*) : Int
end
