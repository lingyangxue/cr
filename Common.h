#pragma once
#import <Foundation/Foundation.h>
#import <objc/message.h>        // ★ 修复 objc_msgSend 未声明
#import <objc/runtime.h>
#import <sys/stat.h>
#import <notify.h>
#import <string.h>

#define PREF_DOMAIN CFSTR("com.developer.craneadvanced")
#define PREF_PATH @"/var/mobile/Library/Preferences/com.developer.craneadvanced.plist"
#define CRANE_SCHEME @"crane-launch"
#define NOTIFY_CREATE_CLIP "com.developer.craneadvanced.createclip"

#pragma mark - 配置读写

static inline NSMutableDictionary *CraneLoadAllPrefs(void) {
    CFPreferencesAppSynchronize(PREF_DOMAIN);
    CFArrayRef keys = CFPreferencesCopyKeyList(PREF_DOMAIN,
                                               kCFPreferencesCurrentUser,
                                               kCFPreferencesAnyHost);
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    if (keys) {
        for (NSString *key in (__bridge NSArray *)keys) {
            CFPropertyListRef val = CFPreferencesCopyAppValue((__bridge CFStringRef)key, PREF_DOMAIN);
            if (val) {
                dict[key] = (__bridge_transfer id)val;
            }
        }
        CFRelease(keys);
    }
    if (dict.count == 0) {
        NSDictionary *fileDict = [NSDictionary dictionaryWithContentsOfFile:PREF_PATH];
        if (fileDict) [dict addEntriesFromDictionary:fileDict];
    }
    return dict;
}

static inline void CraneSaveAllPrefs(NSDictionary *dict) {
    if (!dict) return;
    for (NSString *key in dict) {
        CFPreferencesSetAppValue((__bridge CFStringRef)key,
                                 (__bridge CFPropertyListRef)dict[key],
                                 PREF_DOMAIN);
    }
    CFPreferencesAppSynchronize(PREF_DOMAIN);
    [dict writeToFile:PREF_PATH atomically:YES];
    chmod([PREF_PATH UTF8String], 0666);
}

static inline BOOL CraneIsEnabled(void) {
    NSDictionary *prefs = CraneLoadAllPrefs();
    if (prefs[@"Enabled"] == nil) return YES;
    return [prefs[@"Enabled"] boolValue];
}

static inline NSString *CraneActiveContainerForBundle(NSString *bundleID) {
    if (!bundleID) return @"default";
    NSDictionary *prefs = CraneLoadAllPrefs();
    NSString *val = prefs[bundleID];
    return (val && val.length > 0) ? val : @"default";
}

static inline void CraneSetActiveContainerForBundle(NSString *bundleID, NSString *containerID) {
    if (!bundleID || !containerID) return;
    NSMutableDictionary *prefs = CraneLoadAllPrefs();
    prefs[bundleID] = containerID;
    CraneSaveAllPrefs(prefs);
}

static inline NSArray *CraneGetContainersForBundle(NSString *bundleID) {
    if (!bundleID) return @[@"default"];
    NSDictionary *prefs = CraneLoadAllPrefs();
    NSString *key = [NSString stringWithFormat:@"Containers_%@", bundleID];
    NSArray *list = prefs[key];
    return (list && list.count > 0) ? list : @[@"default"];
}

static inline BOOL CraneGetAppBool(NSString *bundleID, NSString *key, BOOL defaultVal) {
    NSDictionary *prefs = CraneLoadAllPrefs();
    NSString *fullKey = [NSString stringWithFormat:@"%@_%@", bundleID, key];
    if (prefs[fullKey] == nil) return defaultVal;
    return [prefs[fullKey] boolValue];
}

static inline void CraneSetAppBool(NSString *bundleID, NSString *key, BOOL val) {
    NSMutableDictionary *prefs = CraneLoadAllPrefs();
    NSString *fullKey = [NSString stringWithFormat:@"%@_%@", bundleID, key];
    prefs[fullKey] = @(val);
    CraneSaveAllPrefs(prefs);
}

#pragma mark - 沙盒路径重定向

static inline NSString *CraneDataContainerPathForBundle(NSString *bundleID) {
    if (!bundleID) return nil;
    Class proxyCls = objc_getClass("LSApplicationProxy");
    if (proxyCls) {
        id proxy = ((id (*)(id, SEL, id))objc_msgSend)(proxyCls,
                                                       sel_registerName("applicationProxyForIdentifier:"),
                                                       bundleID);
        if (proxy) {
            SEL sel = sel_registerName("dataContainerURL");
            if ([proxy respondsToSelector:sel]) {
                NSURL *url = ((id (*)(id, SEL))objc_msgSend)(proxy, sel);
                if (url) return [url path];
            }
        }
    }
    return nil;
}

static inline NSString *CraneRedirectPath(NSString *originalPath, NSString *containerID, NSString *dataContainerPath) {
    if (!originalPath || !containerID || [containerID isEqualToString:@"default"]) {
        return originalPath;
    }
    if (!dataContainerPath) return originalPath;
    if ([originalPath containsString:@"/_CraneContainers/"]) return originalPath;

    NSRange range = [originalPath rangeOfString:dataContainerPath];
    if (range.location == NSNotFound) return originalPath;

    NSString *suffix = [originalPath substringFromIndex:range.location + range.length];
    NSString *containerRoot = [dataContainerPath stringByAppendingPathComponent:
                               [NSString stringWithFormat:@"_CraneContainers/%@", containerID]];
    return [containerRoot stringByAppendingString:suffix];
}
