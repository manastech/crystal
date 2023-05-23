lib LibC
  enum SE_OBJECT_TYPE
    UNKNOWN_OBJECT_TYPE
    FILE_OBJECT
    SERVICE
    PRINTER
    REGISTRY_KEY
    LMSHARE
    KERNEL_OBJECT
    WINDOW_OBJECT
    DS_OBJECT
    DS_OBJECT_ALL
    PROVIDER_DEFINED_OBJECT
    WMIGUID_OBJECT
    REGISTRY_WOW64_32KEY
    REGISTRY_WOW64_64KEY
  end

  enum MULTIPLE_TRUSTEE_OPERATION
    NO_MULTIPLE_TRUSTEE
    TRUSTEE_IS_IMPERSONATE
  end

  enum TRUSTEE_FORM
    SID
    NAME
    BAD_FORM
    OBJECTS_AND_SID
    OBJECTS_AND_NAME
  end

  enum TRUSTEE_TYPE
    UNKNOWN
    USER
    GROUP
    DOMAIN
    ALIAS
    WELL_KNOWN_GROUP
    DELETED
    INVALID
    COMPUTER
  end

  struct OBJECTS_AND_SID
    objectsPresent : DWORD
    objectTypeGuid : GUID
    inheritedObjectTypeGuid : GUID
    pSid : SID*
  end

  struct OBJECTS_AND_NAME_W
    objectsPresent : DWORD
    objectType : SE_OBJECT_TYPE
    objectTypeName : LPWSTR
    inheritedObjectTypeName : LPWSTR
    ptstrName : LPWSTR
  end

  union TRUSTEE_W_union
    ptstrName : LPWSTR
    pSid : SID*
    pObjectsAndSid : OBJECTS_AND_SID*
    pObjectsAndName : OBJECTS_AND_NAME_W*
  end

  struct TRUSTEE_W
    pMultipleTrustee : TRUSTEE_W*
    multipleTrusteeOperation : MULTIPLE_TRUSTEE_OPERATION
    trusteeForm : TRUSTEE_FORM
    trusteeType : TRUSTEE_TYPE
    union : TRUSTEE_W_union
  end
end
