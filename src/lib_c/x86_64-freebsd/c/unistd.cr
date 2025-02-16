require "./sys/types"
require "./stdint"

lib LibC
  F_OK        =    0
  R_OK        = 0x04
  W_OK        = 0x02
  X_OK        = 0x01
  SC_CLK_TCK  =    3
  SC_PAGESIZE =   47

  fun chroot(dirname : Char*) : Int
  fun access(x0 : Char*, x1 : Int) : Int
  fun chdir(x0 : Char*) : Int
  fun chown(x0 : Char*, x1 : UidT, x2 : GidT) : Int
  fun fchown(x0 : Int, x1 : UidT, x2 : GidT) : Int
  fun close(x0 : Int) : Int
  fun dup2(x0 : Int, x1 : Int) : Int
  fun dup3(x0 : Int, x1 : Int, x2 : Int) : Int
  fun _exit(x0 : Int) : NoReturn
  fun execvp(x0 : Char*, x1 : Char**) : Int
  fun fdatasync(fd : Int) : Int
  @[ReturnsTwice]
  fun fork : PidT
  fun fsync(fd : Int) : Int
  fun ftruncate(x0 : Int, x1 : OffT) : Int
  fun getcwd(x0 : Char*, x1 : SizeT) : Char*
  fun gethostname(x0 : Char*, x1 : SizeT) : Int
  fun getpgid(pid : PidT) : Int
  fun getpid : PidT
  fun getppid : PidT
  fun getuid : UidT
  fun setuid(uid : UidT) : Int
  fun isatty(x0 : Int) : Int
  fun ttyname_r(fd : Int, buf : Char*, buffersize : SizeT) : Int
  fun lchown(x0 : Char*, x1 : UidT, x2 : GidT) : Int
  fun link(x0 : Char*, x1 : Char*) : Int
  fun lockf(x0 : Int, x1 : Int, x2 : OffT) : Int
  fun lseek(x0 : Int, x1 : OffT, x2 : Int) : OffT
  fun pipe(x0 : Int*) : Int
  fun pipe2(x0 : Int*, x1 : Int) : Int
  fun read(x0 : Int, x1 : Void*, x2 : SizeT) : SSizeT
  fun pread(x0 : Int, x1 : Void*, x2 : SizeT, x3 : OffT) : SSizeT
  fun rmdir(x0 : Char*) : Int
  fun symlink(x0 : Char*, x1 : Char*) : Int
  fun readlink(path : Char*, buf : Char*, size : SizeT) : SSizeT
  fun sysconf(x0 : Int) : Long
  fun unlink(x0 : Char*) : Int
  fun write(x0 : Int, x1 : Void*, x2 : SizeT) : SSizeT
  fun copy_file_range(fd_in : Int, offset_in : OffT*, fd_out : Int, offset_out : OffT*, len : SizeT, flags : UInt) : SSizeT
end
