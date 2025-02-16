require "./sys/types"
require "./stdint"

lib LibC
  F_OK                =  0
  R_OK                =  4
  W_OK                =  2
  X_OK                =  1
  SC_CLK_TCK          =  2
  SC_NPROCESSORS_ONLN = 84
  SC_PAGESIZE         = 30

  fun chroot(path : Char*) : Int
  fun access(name : Char*, type : Int) : Int
  fun chdir(path : Char*) : Int
  fun chown(file : Char*, owner : UidT, group : GidT) : Int
  fun fchown(fd : Int, owner : UidT, group : GidT) : Int
  fun close(fd : Int) : Int
  fun dup2(fd : Int, fd2 : Int) : Int
  fun dup3(fd : Int, fd2 : Int, flags : Int) : Int
  fun _exit(status : Int) : NoReturn
  fun execvp(file : Char*, argv : Char**) : Int
  fun fdatasync(fd : Int) : Int
  @[ReturnsTwice]
  fun fork : PidT
  fun fsync(fd : Int) : Int
  fun ftruncate = ftruncate64(fd : Int, length : OffT) : Int
  fun getcwd(buf : Char*, size : SizeT) : Char*
  fun gethostname(name : Char*, len : SizeT) : Int
  fun getpgid(pid : PidT) : PidT
  fun getpid : PidT
  fun getppid : PidT
  fun getuid : UidT
  fun setuid(uid : UidT) : Int
  fun isatty(fd : Int) : Int
  fun ttyname_r(fd : Int, buf : Char*, buffersize : SizeT) : Int
  fun lchown(file : Char*, owner : UidT, group : GidT) : Int
  fun link(from : Char*, to : Char*) : Int
  fun lockf = lockf64(fd : Int, cmd : Int, len : OffT) : Int
  fun lseek = lseek64(fd : Int, offset : OffT, whence : Int) : OffT
  fun pipe(pipedes : StaticArray(Int, 2)) : Int
  fun pipe2(pipedes : StaticArray(Int, 2), flags : Int) : Int
  fun read(fd : Int, buf : Void*, nbytes : SizeT) : SSizeT
  fun pread = pread64(x0 : Int, x1 : Void*, x2 : SizeT, x3 : OffT) : SSizeT
  fun rmdir(path : Char*) : Int
  fun symlink(from : Char*, to : Char*) : Int
  fun readlink(path : Char*, buf : Char*, size : SizeT) : SSizeT
  fun syscall(sysno : Long, ...) : Long
  fun sysconf(name : Int) : Long
  fun unlink(name : Char*) : Int
  fun write(fd : Int, buf : Void*, n : SizeT) : SSizeT
  fun copy_file_range(fd_in : Int, offset_in : OffT*, fd_out : Int, offset_out : OffT*, len : SizeT, flags : UInt) : Int
end
