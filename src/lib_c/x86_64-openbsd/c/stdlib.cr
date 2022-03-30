require "./stddef"
require "./sys/wait"

lib LibC
  fun arc4random : UInt32
  fun arc4random_buf(x0 : Void*, x1 : SizeT) : Void
  fun exit(x0 : Int) : NoReturn
  fun free(x0 : Void*) : Void
  fun getenv(x0 : Char*) : Char*
  fun malloc(x0 : SizeT) : Void*
  fun mkstemp(x0 : Char*) : Int
  fun mkstemps(x0 : Char*, x1 : Int) : Int
  fun realloc(x0 : Void*, x1 : SizeT) : Void*
  fun realpath(x0 : Char*, x1 : Char*) : Char*
  fun setenv(x0 : Char*, x1 : Char*, x2 : Int) : Int
  fun strtof(x0 : Char*, x1 : Char**) : Float
  fun strtod(x0 : Char*, x1 : Char**) : Double
  fun unsetenv(x0 : Char*) : Int
end
