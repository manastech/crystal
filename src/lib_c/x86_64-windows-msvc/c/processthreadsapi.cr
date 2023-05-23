require "./basetsd"
require "c/wtypesbase"
require "c/sdkddkver"

lib LibC
  CREATE_UNICODE_ENVIRONMENT = 0x00000400

  struct PROCESS_INFORMATION
    hProcess : HANDLE
    hThread : HANDLE
    dwProcessId : DWORD
    dwThreadId : DWORD
  end

  struct STARTUPINFOW
    cb : DWORD
    lpReserved : LPWSTR
    lpDesktop : LPWSTR
    lpTitle : LPWSTR
    dwX : DWORD
    dwY : DWORD
    dwXSize : DWORD
    dwYSize : DWORD
    dwXCountChars : DWORD
    dwYCountChars : DWORD
    dwFillAttribute : DWORD
    dwFlags : DWORD
    wShowWindow : WORD
    cbReserved2 : WORD
    lpReserved2 : BYTE*
    hStdInput : HANDLE
    hStdOutput : HANDLE
    hStdError : HANDLE
  end

  fun NtCurrentTeb : NT_TIB*
  fun GetCurrentThread : HANDLE
  fun GetCurrentThreadId : DWORD
  {% if LibC::WIN32_WINNT >= LibC::WIN32_WINNT_WIN8 %}
    fun GetCurrentThreadStackLimits(lowLimit : ULONG_PTR*, highLimit : ULONG_PTR*) : Void
  {% end %}
  fun GetCurrentProcess : HANDLE
  fun GetCurrentProcessId : DWORD
  fun OpenProcess(dwDesiredAccess : DWORD, bInheritHandle : BOOL, dwProcessId : DWORD) : HANDLE
  fun GetExitCodeProcess(hProcess : HANDLE, lpExitCode : DWORD*) : BOOL
  fun ExitProcess(uExitCode : UInt) : NoReturn
  fun TerminateProcess(hProcess : HANDLE, uExitCode : UInt) : BOOL
  fun CreateProcessW(lpApplicationName : LPWSTR, lpCommandLine : LPWSTR,
                     lpProcessAttributes : SECURITY_ATTRIBUTES*, lpThreadAttributes : SECURITY_ATTRIBUTES*,
                     bInheritHandles : BOOL, dwCreationFlags : DWORD,
                     lpEnvironment : Void*, lpCurrentDirectory : LPWSTR,
                     lpStartupInfo : STARTUPINFOW*, lpProcessInformation : PROCESS_INFORMATION*) : BOOL
  fun SetThreadStackGuarantee(stackSizeInBytes : DWORD*) : BOOL
  fun GetProcessTimes(hProcess : HANDLE, lpCreationTime : FILETIME*, lpExitTime : FILETIME*,
                      lpKernelTime : FILETIME*, lpUserTime : FILETIME*) : BOOL
  fun SwitchToThread : BOOL

  GetCurrentProcessToken = HANDLE.new(-4) # C static inline function

  PROCESS_QUERY_INFORMATION = 0x0400
end
