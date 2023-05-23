@[Link("advapi32")]
lib LibC
  fun GetSecurityInfo(handle : HANDLE, objectType : SE_OBJECT_TYPE, securityInfo : DWORD, ppsidOwner : SID**,
                      ppsidGroup : SID**, ppDacl : ACL**, ppSacl : ACL**, ppSecurityDescriptor : SECURITY_DESCRIPTOR**) : DWORD
  fun BuildTrusteeWithSidW(pTrustee : TRUSTEE_W*, pSid : SID*)
  fun GetEffectiveRightsFromAclW(pacl : ACL*, pTrustee : TRUSTEE_W*, pAccessRights : ACCESS_MASK*) : DWORD
end
