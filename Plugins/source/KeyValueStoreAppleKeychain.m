#import <Foundation/Foundation.h>
#import <Security/Security.h>

#import "IUnityInterface.h"
#import "IUnityLog.h"

static IUnityLog *logger;

/// Log a formatted debug message to Unity's console
static void debugLogFormat(NSString* fmt, ...) {
    va_list va;
    va_start(va, fmt);
    NSString* msg = [[NSString alloc] initWithFormat:fmt arguments:va];
    va_end(va);
    UNITY_LOG(logger, msg.UTF8String);
}

/// Log OSStatus error messages to Unity's console.
/// Ignores `errSecSuccess` and `errSecItemNotFound`.
static void logSecError(OSStatus result) {
    switch (result) {
        case errSecSuccess:
        case errSecItemNotFound:
            break;

        default: {
            NSString* error = CFBridgingRelease(SecCopyErrorMessageString(result, NULL));
            UNITY_LOG_ERROR(logger, error.UTF8String);
            break;
        }
    }
}

/// Log NSError message to Unity's console.
static void logNSError(NSError* error) {
    if (error) {
        UNITY_LOG_ERROR(logger, error.localizedDescription.UTF8String);
    }
}

static NSString* toNSString(const char *cStr) {
    return [NSString stringWithCString:cStr encoding:NSUTF8StringEncoding];
}

/// @warning Must match the C# AppleKeychainKeyValueStore class!!!
typedef struct AppleKeychainKeyValueStore {
    const char *account;
    const char *service;
    const char *label;
    const char *description;
    int isSynchronizable;
    int useDataProtectionKeychain;
    NSMutableDictionary* mutableDictionary;
} AppleKeychainKeyValueStore;

static NSMutableDictionary* createBaseQuery(const AppleKeychainKeyValueStore *kvs) {
    NSMutableDictionary* query = [NSMutableDictionary dictionaryWithObject:(id)kSecClassGenericPassword forKey:(id)kSecClass];
    if (kvs->account) {
        [query setObject:toNSString(kvs->account) forKey:(id)kSecAttrAccount];
    }
    if (kvs->service) {
        [query setObject:toNSString(kvs->service) forKey:(id)kSecAttrService];
    }
    if (@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, visionOS 1.0, *)) {
        [query setObject:@(kvs->useDataProtectionKeychain) forKey:(id)kSecUseDataProtectionKeychain];
    }
    return query;
}

static void fillAdditionalData(const AppleKeychainKeyValueStore *kvs, NSMutableDictionary* query, NSData* data) {
    if (kvs->label) {
        [query setObject:toNSString(kvs->label) forKey:(id)kSecAttrLabel];
    }
    if (kvs->description) {
        [query setObject:toNSString(kvs->description) forKey:(id)kSecAttrDescription];
    }
    if (@available(iOS 7.0, macOS 10.9, tvOS 9.0, watchOS 2.0, visionOS 1.0, *)) {
        [query setObject:@(kvs->isSynchronizable) forKey:(id)kSecAttrSynchronizable];
    }
    [query setObject:data forKey:(id)kSecValueData];
}

///////////////////////////////////////////////////////////
// Get/Set key-value pairs
///////////////////////////////////////////////////////////
static bool setData(const AppleKeychainKeyValueStore *kvs, id data) {
    NSError* error = nil;
    NSData* archivedData = [NSKeyedArchiver archivedDataWithRootObject:data requiringSecureCoding:YES error:&error];
    if (error) {
        logNSError(error);
        return false;
    }

    NSMutableDictionary* query = createBaseQuery(kvs);
    OSStatus result = SecItemCopyMatching((CFDictionaryRef) query, NULL);
    switch (result) {
        case errSecSuccess: {
            NSMutableDictionary* attributesToUpdate = [NSMutableDictionary dictionary];
            fillAdditionalData(kvs, attributesToUpdate, archivedData);
            OSStatus result = SecItemUpdate((CFDictionaryRef) query, (CFDictionaryRef) attributesToUpdate);
            logSecError(result);
            return result == errSecSuccess;
        }

        case errSecItemNotFound:
            fillAdditionalData(kvs, query, archivedData);
            result = SecItemAdd((CFDictionaryRef) query, NULL);
            logSecError(result);
            return result == errSecSuccess;

        default:
            logSecError(result);
            return false;
    }
}

static bool hasData(const AppleKeychainKeyValueStore *kvs) {
    NSMutableDictionary* query = createBaseQuery(kvs);
    OSStatus result = SecItemCopyMatching((CFDictionaryRef) query, NULL);
    logSecError(result);
    return result == errSecSuccess;
}

static NSData* getData(const AppleKeychainKeyValueStore *kvs) {
    NSMutableDictionary* query = createBaseQuery(kvs);
    [query setObject:@YES forKey:(id)kSecReturnData];
    CFTypeRef existingData;
    OSStatus result = SecItemCopyMatching((CFDictionaryRef) query, &existingData);
    switch (result) {
        case errSecSuccess:
            return CFBridgingRelease(existingData);

        default:
            logSecError(result);
            return nil;
    }
}

static id getTypedData(const AppleKeychainKeyValueStore *kvs, Class cls) {
    NSData* data = getData(kvs);
    if (data) {
        NSError* error = nil;
        id value = [NSKeyedUnarchiver unarchivedObjectOfClass:cls fromData:data error:&error];
        logNSError(error);
        return value;
    }
    else {
        return nil;
    }
}

static bool deleteData(const AppleKeychainKeyValueStore *kvs) {
    NSMutableDictionary* query = createBaseQuery(kvs);
    OSStatus result = SecItemDelete((CFDictionaryRef) query);
    logSecError(result);
    return result == errSecSuccess;
}

///////////////////////////////////////////////////////////
// Exported functions
///////////////////////////////////////////////////////////
void UNITY_INTERFACE_EXPORT UnityPluginLoad(IUnityInterfaces* unityInterfaces) {
    logger = UNITY_GET_INTERFACE(unityInterfaces, IUnityLog);
}

void KeyValueStoreAppleKeychain_AllocDictionary(NSMutableDictionary** dict) {
    *dict = [[NSMutableDictionary alloc] init];
}

void KeyValueStoreAppleKeychain_ReleaseDictionary(NSMutableDictionary** dict) {
    [*dict release];
    *dict = nil;
}

void KeyValueStoreAppleKeychain_ClearDictionary(NSMutableDictionary* dict) {
    [dict removeAllObjects];
}

void KeyValueStoreAppleKeychain_DeleteKey(NSMutableDictionary* dict, const char *key) {
    [dict removeObjectForKey:toNSString(key)];
}

bool KeyValueStoreAppleKeychain_HasKey(NSMutableDictionary* dict, const char *key) {
    return [dict valueForKey:toNSString(key)];
}

void KeyValueStoreAppleKeychain_SetBool(NSMutableDictionary* dict, const char *key, int value) {
    [dict setObject:@(value) forKey:toNSString(key)];
}

bool KeyValueStoreAppleKeychain_TryGetBool(NSMutableDictionary* dict, const char *key, int *outValue) {
    id value = [dict valueForKey:toNSString(key)];
    if ([value isKindOfClass:NSNumber.class]) {
        *outValue = [value boolValue];
        return true;
    }
    else {
        *outValue = 0;
        return false;
    }
}

bool KeyValueStoreAppleKeychain_Save(const AppleKeychainKeyValueStore *kvs) {
    return setData(kvs, kvs->mutableDictionary);
}

bool KeyValueStoreAppleKeychain_Load(const AppleKeychainKeyValueStore *kvs, NSMutableDictionary** dict) {
    [*dict release];
    *dict = getTypedData(kvs, NSMutableDictionary.class);
    return *dict;
}

bool KeyValueStoreAppleKeychain_DeleteKeychain(const AppleKeychainKeyValueStore *kvs) {
    return deleteData(kvs);
}