require "./sys/types"
require "./stdint"

lib LibC
  F_OK       =    0
  R_OK       = 0x04
  W_OK       = 0x02
  X_OK       = 0x01
  SC_CLK_TCK =    3

  fun access(x0 : Char*, x1 : Int) : Int
  fun chdir(x0 : Char*) : Int
  fun chown(x0 : Char*, x1 : UidT, x2 : GidT) : Int
  fun close(x0 : Int) : Int
  fun dup2(x0 : Int, x1 : Int) : Int
  fun _exit(x0 : Int) : NoReturn
  fun execvp(x0 : Char*, x1 : Char**) : Int
  @[ReturnsTwice]
  fun fork : PidT
  fun ftruncate(x0 : Int, x1 : OffT) : Int
  fun getcwd(x0 : Char*, x1 : SizeT) : Char*
  fun gethostname(x0 : Char*, x1 : SizeT) : Int
  fun getpgid(pid : PidT) : Int
  fun getpid : PidT
  fun getppid : PidT
  fun isatty(x0 : Int) : Int
  fun lchown(x0 : Char*, x1 : UidT, x2 : GidT) : Int
  fun link(x0 : Char*, x1 : Char*) : Int
  fun lockf(x0 : Int, x1 : Int, x2 : OffT) : Int
  fun lseek(x0 : Int, x1 : OffT, x2 : Int) : OffT
  fun pipe(x0 : Int*) : Int
  fun read(x0 : Int, x1 : Void*, x2 : SizeT) : SSizeT
  fun pread(x0 : Int, x1 : Void*, x2 : SizeT, x3 : OffT) : SSizeT
  fun rmdir(x0 : Char*) : Int
  fun symlink(x0 : Char*, x1 : Char*) : Int
  fun sysconf(x0 : Int) : Long
  fun unlink(x0 : Char*) : Int
  fun write(x0 : Int, x1 : Void*, x2 : SizeT) : SSizeT
  fun getuid : UidT
  fun geteuid : UidT
  fun getresuid(ruid : UidT*, euid : UidT*, suid : UidT*) : Int
  fun setuid(uid : UidT) : Int
  fun getgid : GidT
  fun getegid : GidT
  fun getresgid(rgid : GidT*, egid : GidT*, sgid : GidT*) : Int
  fun setgid(gid : GidT) : Int
end
