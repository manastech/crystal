require "c/winnt"
require "c/basetsd"
require "c/wtypesbase"
require "c/minwinbase"

lib LibC
  fun GetFullPathNameW(lpFileName : LPWSTR, nBufferLength : DWORD, lpBuffer : LPWSTR, lpFilePart : LPWSTR*) : DWORD
  fun GetTempPathW(nBufferLength : DWORD, lpBuffer : LPWSTR) : DWORD

  FILE_TYPE_CHAR    = DWORD.new(0x2)
  FILE_TYPE_DISK    = DWORD.new(0x1)
  FILE_TYPE_PIPE    = DWORD.new(0x3)
  FILE_TYPE_UNKNOWN = DWORD.new(0x0)

  fun GetFileType(hFile : HANDLE) : DWORD

  struct WIN32_FILE_ATTRIBUTE_DATA
    dwFileAttributes : DWORD
    ftCreationTime : FILETIME
    ftLastAccessTime : FILETIME
    ftLastWriteTime : FILETIME
    nFileSizeHigh : DWORD
    nFileSizeLow : DWORD
  end

  struct BY_HANDLE_FILE_INFORMATION
    dwFileAttributes : DWORD
    ftCreationTime : FILETIME
    ftLastAccessTime : FILETIME
    ftLastWriteTime : FILETIME
    dwVolumeSerialNumber : DWORD
    nFileSizeHigh : DWORD
    nFileSizeLow : DWORD
    nNumberOfLinks : DWORD
    nFileIndexHigh : DWORD
    nFileIndexLow : DWORD
  end

  fun GetFileInformationByHandle(hFile : HANDLE, lpFileInformation : BY_HANDLE_FILE_INFORMATION*) : BOOL
  fun GetFileAttributesW(lpFileName : LPWSTR) : DWORD
  fun SetFileAttributesW(lpFileName : LPWSTR, dwFileAttributes : DWORD) : BOOL
  fun GetFileAttributesExW(lpFileName : LPWSTR, fInfoLevelId : GET_FILEEX_INFO_LEVELS, lpFileInformation : Void*) : BOOL

  CREATE_NEW        = 1
  CREATE_ALWAYS     = 2
  OPEN_EXISTING     = 3
  OPEN_ALWAYS       = 4
  TRUNCATE_EXISTING = 5

  FILE_ATTRIBUTE_NORMAL    =  0x80
  FILE_ATTRIBUTE_TEMPORARY = 0x100

  FILE_FLAG_BACKUP_SEMANTICS    = 0x02000000
  FILE_FLAG_DELETE_ON_CLOSE     = 0x04000000
  FILE_FLAG_FIRST_PIPE_INSTANCE = 0x00080000
  FILE_FLAG_NO_BUFFERING        = 0x20000000
  FILE_FLAG_OPEN_REPARSE_POINT  = 0x00200000
  FILE_FLAG_OVERLAPPED          = 0x40000000
  FILE_FLAG_RANDOM_ACCESS       = 0x10000000
  FILE_FLAG_SEQUENTIAL_SCAN     = 0x08000000

  FILE_SHARE_READ   = 0x1
  FILE_SHARE_WRITE  = 0x2
  FILE_SHARE_DELETE = 0x4

  DEFAULT_SHARE_MODE = FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE

  fun CreateFileW(lpFileName : LPWSTR, dwDesiredAccess : DWORD, dwShareMode : DWORD,
                  lpSecurityAttributes : SECURITY_ATTRIBUTES*, dwCreationDisposition : DWORD,
                  dwFlagsAndAttributes : DWORD, hTemplateFile : HANDLE) : HANDLE

  fun ReadFile(hFile : HANDLE, lpBuffer : Void*, nNumberOfBytesToRead : DWORD, lpNumberOfBytesRead : DWORD*, lpOverlapped : OVERLAPPED*) : BOOL
  fun WriteFile(hFile : HANDLE, lpBuffer : Void*, nNumberOfBytesToWrite : DWORD, lpNumberOfBytesWritten : DWORD*, lpOverlapped : OVERLAPPED*) : BOOL

  MAX_PATH = 260

  struct WIN32_FIND_DATAW
    dwFileAttributes : DWORD
    ftCreationTime : FILETIME
    ftLastAccessTime : FILETIME
    ftLastWriteTime : FILETIME
    nFileSizeHigh : DWORD
    nFileSizeLow : DWORD
    dwReserved0 : DWORD
    dwReserved1 : DWORD
    cFileName : WCHAR[MAX_PATH]
    cAlternateFileName : WCHAR[14]
  end

  fun FindFirstFileW(lpFileName : LPWSTR, lpFindFileData : WIN32_FIND_DATAW*) : HANDLE
  fun FindNextFileW(hFindFile : HANDLE, lpFindFileData : WIN32_FIND_DATAW*) : BOOL
  fun FindClose(hFindFile : HANDLE) : BOOL

  fun LockFileEx(
    hFile : HANDLE,
    dwFlags : DWORD,
    dwReserved : DWORD,
    nNumberOfBytesToLockLow : DWORD,
    nNumberOfBytesToLockHigh : DWORD,
    lpOverlapped : OVERLAPPED*
  ) : BOOL
  fun UnlockFileEx(
    hFile : HANDLE,
    dwReserved : DWORD,
    nNumberOfBytesToUnlockLow : DWORD,
    nNumberOfBytesToUnlockHigh : DWORD,
    lpOverlapped : OVERLAPPED*
  ) : BOOL
  fun SetFileTime(hFile : HANDLE, lpCreationTime : FILETIME*,
                  lpLastAccessTime : FILETIME*, lpLastWriteTime : FILETIME*) : BOOL
end
