lib LibC
  alias LSTATUS = DWORD
  alias REGSAM = ACCESS_MASK

  enum RegistryRoutineFlags
    NONE                       = 0
    SZ                         = 1
    EXPAND_SZ                  = 2
    BINARY                     = 3
    DWORD                      = 4
    DWORD_LITTLE_ENDIAN        = DWORD
    DWORD_BIG_ENDIAN           =  5
    LINK                       =  6
    MULTI_SZ                   =  7
    RESOURCE_LIST              =  8
    FULL_RESOURCE_DESCRIPTOR   =  9
    RESOURCE_REQUIREMENTS_LIST = 10
    QWORD                      = 11
    QWORD_LITTLE_ENDIAN        = QWORD
  end

  HKEY_CLASSES_ROOT     = Pointer(Void).new(0x80000000).as(HKEY)
  HKEY_CURRENT_USER     = Pointer(Void).new(0x80000001).as(HKEY)
  HKEY_LOCAL_MACHINE    = Pointer(Void).new(0x80000002).as(HKEY)
  HKEY_USERS            = Pointer(Void).new(0x80000003).as(HKEY)
  HKEY_PERFORMANCE_DATA = Pointer(Void).new(0x80000004).as(HKEY)
  HKEY_CURRENT_CONFIG   = Pointer(Void).new(0x80000005).as(HKEY)
  HKEY_DYN_DATA         = Pointer(Void).new(0x8000006).as(HKEY)

  fun RegOpenKeyExW(hKey : HKEY, lpSubKey : LPWSTR, ulOptions : DWORD, samDesired : REGSAM, phkResult : HKEY*) : LSTATUS
  fun RegCloseKey(hKey : HKEY) : LSTATUS
  fun RegEnumKeyExW(hKey : HKEY, dwIndex : DWORD,
                    lpName : LPWSTR, lpcchName : DWORD*,
                    lpReserved : DWORD*,
                    lpClass : LPWSTR, lpcchClass : DWORD*,
                    lpftLastWriteTime : FILETIME*) : LSTATUS
  fun RegQueryInfoKeyW(hKey : HKEY, lpClass : LPSTR, lpcchClass : DWORD*, lpReserved : DWORD*,
                       lpcSubKeys : DWORD*, lpcbMaxSubKeyLen : DWORD*,
                       lpcbMaxClassLen : DWORD*,
                       lpcValues : DWORD*, lpcbMaxValueNameLen : DWORD*, lpcbMaxValueLen : DWORD*,
                       lpcbSecurityDescriptor : DWORD*, lpftLastWriteTime : FILETIME*) : DWORD
  fun RegQueryValueExW(hKey : HKEY, lpValueName : LPWSTR, lpReserved : DWORD*, lpType : RegistryRoutineFlags*, lpData : BYTE*, lpcbData : DWORD*) : LSTATUS
end
