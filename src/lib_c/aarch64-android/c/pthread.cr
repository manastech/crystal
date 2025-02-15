require "./sys/types"

lib LibC
  PTHREAD_MUTEX_ERRORCHECK = 2

  fun pthread_attr_destroy(__attr : PthreadAttrT*) : Int
  fun pthread_attr_getstack(__attr : PthreadAttrT*, __addr : Void**, __size : SizeT*) : Int

  fun pthread_condattr_destroy(__attr : PthreadCondattrT*) : Int
  fun pthread_condattr_init(__attr : PthreadCondattrT*) : Int
  {% if ANDROID_API >= 21 %}
    fun pthread_condattr_setclock(__attr : PthreadCondattrT*, __clock : ClockidT) : Int
  {% end %}

  fun pthread_cond_broadcast(__cond : PthreadCondT*) : Int
  fun pthread_cond_destroy(__cond : PthreadCondT*) : Int
  fun pthread_cond_init(__cond : PthreadCondT*, __attr : PthreadCondattrT*) : Int
  fun pthread_cond_signal(__cond : PthreadCondT*) : Int
  fun pthread_cond_timedwait(__cond : PthreadCondT*, __mutex : PthreadMutexT*, __timeout : Timespec*) : Int
  fun pthread_cond_wait(__cond : PthreadCondT*, __mutex : PthreadMutexT*) : Int

  fun pthread_create(__pthread_ptr : PthreadT*, __attr : PthreadAttrT*, __start_routine : Void* -> Void*, Void*) : Int
  fun pthread_detach(__pthread : PthreadT) : Int
  fun pthread_getattr_np(__pthread : PthreadT, __attr : PthreadAttrT*) : Int
  fun pthread_equal(__lhs : PthreadT, __rhs : PthreadT) : Int
  fun pthread_getspecific(__key : PthreadKeyT) : Void*
  fun pthread_join(__pthread : PthreadT, __return_value_ptr : Void**) : Int
  fun pthread_key_create(__key_ptr : PthreadKeyT*, __key_destructor : Void* ->) : Int
  fun pthread_key_delete(__key_ptr : PthreadKeyT) : Int

  fun pthread_mutexattr_destroy(__attr : PthreadMutexattrT*) : Int
  fun pthread_mutexattr_init(__attr : PthreadMutexattrT*) : Int
  fun pthread_mutexattr_settype(__attr : PthreadMutexattrT*, __type : Int) : Int

  fun pthread_mutex_destroy(__mutex : PthreadMutexT*) : Int
  fun pthread_mutex_init(__mutex : PthreadMutexT*, __attr : PthreadMutexattrT*) : Int
  fun pthread_mutex_lock(__mutex : PthreadMutexT*) : Int
  fun pthread_mutex_trylock(__mutex : PthreadMutexT*) : Int
  fun pthread_mutex_unlock(__mutex : PthreadMutexT*) : Int

  fun pthread_self : PthreadT
  fun pthread_setname_np(__key : PthreadT, __name : Char*) : Int

  fun pthread_setspecific(__key : PthreadKeyT, __value : Void*) : Int
end
