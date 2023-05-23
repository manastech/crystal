require "c/winnt"
require "c/win_def"
require "c/int_safe"
require "c/minwinbase"

lib LibC
  fun LocalFree(hMem : Void*) : Void*

  FORMAT_MESSAGE_ALLOCATE_BUFFER = 0x00000100_u32
  FORMAT_MESSAGE_IGNORE_INSERTS  = 0x00000200_u32
  FORMAT_MESSAGE_FROM_STRING     = 0x00000400_u32
  FORMAT_MESSAGE_FROM_HMODULE    = 0x00000800_u32
  FORMAT_MESSAGE_FROM_SYSTEM     = 0x00001000_u32
  FORMAT_MESSAGE_ARGUMENT_ARRAY  = 0x00002000_u32
  FORMAT_MESSAGE_MAX_WIDTH_MASK  = 0x000000FF_u32

  STD_ERROR_HANDLE = DWORD.new!(-12)

  fun FormatMessageA(dwFlags : DWORD, lpSource : Void*, dwMessageId : DWORD, dwLanguageId : DWORD,
                     lpBuffer : LPSTR, nSize : DWORD, arguments : Void*) : DWORD
  fun FormatMessageW(dwFlags : DWORD, lpSource : Void*, dwMessageId : DWORD, dwLanguageId : DWORD,
                     lpBuffer : LPWSTR, nSize : DWORD, arguments : Void*) : DWORD

  SYMBOLIC_LINK_FLAG_DIRECTORY                 = 0x1
  SYMBOLIC_LINK_FLAG_ALLOW_UNPRIVILEGED_CREATE = 0x2

  PIPE_ACCESS_OUTBOUND = 0x00000002

  fun CreateHardLinkW(lpFileName : LPWSTR, lpExistingFileName : LPWSTR, lpSecurityAttributes : SECURITY_ATTRIBUTES*) : BOOL
  fun CreateSymbolicLinkW(lpSymlinkFileName : LPWSTR, lpTargetFileName : LPWSTR, dwFlags : DWORD) : BOOLEAN
  fun CreateNamedPipeA(lpName : LPSTR, dwOpenMode : DWORD, dwPipeMode : DWORD, nMaxInstances : DWORD,
                       nOutBufferSize : DWORD, nInBufferSize : DWORD, nDefaultTimeOut : DWORD, lpSecurityAttributes : SECURITY_ATTRIBUTES*) : HANDLE

  FILE_SKIP_COMPLETION_PORT_ON_SUCCESS = 1_u8

  fun SetFileCompletionNotificationModes(fileHandle : HANDLE, flags : UChar) : BOOL

  fun GetEnvironmentVariableW(lpName : LPWSTR, lpBuffer : LPWSTR, nSize : DWORD) : DWORD
  fun GetEnvironmentStringsW : LPWCH
  fun FreeEnvironmentStringsW(lpszEnvironmentBlock : LPWCH) : BOOL
  fun SetEnvironmentVariableW(lpName : LPWSTR, lpValue : LPWSTR) : BOOL

  INFINITE = 0xFFFFFFFF

  WAIT_OBJECT_0      = 0x00000000_u32
  WAIT_IO_COMPLETION = 0x000000C0_u32
  WAIT_TIMEOUT       = 0x00000102_u32
  WAIT_FAILED        = 0xFFFFFFFF_u32

  STARTF_USESTDHANDLES = 0x00000100

  MOVEFILE_REPLACE_EXISTING      =  0x1_u32
  MOVEFILE_COPY_ALLOWED          =  0x2_u32
  MOVEFILE_DELAY_UNTIL_REBOOT    =  0x4_u32
  MOVEFILE_WRITE_THROUGH         =  0x8_u32
  MOVEFILE_CREATE_HARDLINK       = 0x10_u32
  MOVEFILE_FAIL_IF_NOT_TRACKABLE = 0x20_u32

  fun MoveFileExW(lpExistingFileName : LPWSTR, lpNewFileName : LPWSTR, dwFlags : DWORD) : BOOL

  fun GetBinaryTypeW(lpApplicationName : LPWSTR, lpBinaryType : DWORD*) : BOOL
end
