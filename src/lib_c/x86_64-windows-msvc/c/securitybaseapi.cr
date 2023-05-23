require "c/winnt"

@[Link("advapi32")]
lib LibC
  fun CreateWellKnownSid(wellKnownSidType : WELL_KNOWN_SID_TYPE, domainSid : SID*, pSid : SID*, cbSid : DWORD*) : BOOL

  fun GetTokenInformation(tokenHandle : HANDLE, tokenInformationClass : TOKEN_INFORMATION_CLASS, tokenInformation : Void*, tokenInformationLength : DWORD, returnLength : DWORD*) : BOOL
end
