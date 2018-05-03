require "./types"
require "../time"

lib LibC
  S_IFMT   = 0o170000
  S_IFBLK  = 0o060000
  S_IFCHR  = 0o020000
  S_IFIFO  = 0o010000
  S_IFREG  = 0o100000
  S_IFDIR  = 0o040000
  S_IFLNK  = 0o120000
  S_IFSOCK = 0o140000
  S_IRUSR  = 0o000400
  S_IWUSR  = 0o000200
  S_IXUSR  = 0o000100
  S_IRWXU  = 0o000700
  S_IRGRP  = 0o000040
  S_IWGRP  = 0o000020
  S_IXGRP  = 0o000010
  S_IRWXG  = 0o000070
  S_IROTH  = 0o000004
  S_IWOTH  = 0o000002
  S_IXOTH  = 0o000001
  S_IRWXO  = 0o000007
  S_ISUID  = 0o004000
  S_ISGID  = 0o002000
  S_ISVTX  = 0o001000

  struct Stat
    st_dev : DevT
    st_ino : InoT
    st_mode : ModeT
    st_nlink : NlinkT
    st_uid : UidT
    st_gid : GidT
    st_rdev : DevT
    st_atimespec : Timespec
    st_mtimespec : Timespec
    st_ctimespec : Timespec
    st_size : OffT
    st_blocks : BlkcntT
    st_blksize : BlksizeT
    st_flags : UInt
    st_gen : UInt
    st_lspare : Int
    st_qspare : StaticArray(LongLong, 2)
  end

  struct Statfs
    bsize : UInt32
    iosize : Int32
    nlocks : UInt64
    bfree : UInt64
    bavail : UInt64
    files : UInt64
    ffree : UInt64
    fsid : FsidT
    owner : UInt32
    type : UInt32
    flags : UInt32
    fssubtype : UInt32
    fstypename : StaticArray(ShortShort, 16)
    mntonname : StaticArray(ShortShort, 1024)
    mntfromname : StaticArray(ShortShort, 1024)
    reserved : StaticArray(Long, 8)
  end

  fun chmod(x0 : Char*, x1 : ModeT) : Int
  fun fstat(x0 : Int, x1 : Stat*) : Int
  fun lstat(x0 : Char*, x1 : Stat*) : Int
  fun mkdir(x0 : Char*, x1 : ModeT) : Int
  fun mkfifo(x0 : Char*, x1 : ModeT) : Int
  fun mknod(x0 : Char*, x1 : ModeT, x2 : DevT) : Int
  fun stat(x0 : Char*, x1 : Stat*) : Int
  fun statfs(file : Char*, buf : Stat*) : Int
  fun umask(x0 : ModeT) : ModeT
end
