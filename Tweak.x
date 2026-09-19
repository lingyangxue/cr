#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <notify.h>
#import <dlfcn.h>
#import <unistd.h>
#import <sys/stat.h>

#pragma mark - 常量

#define CRANE_PREFS_PATH @"/var/mobile/Library/Preferences/com.opa334.craneprefs.plist"
#define CRANE_PREFS_DOMAIN CFSTR("com.opa334.craneprefs")
#define MY_PREFS_PATH @"/var/mobile/Library/Preferences/com.developer.craneicon.plist"
#define CRANE_ICON_SCHEME @"crane-icon"
#define WEB_CLIPS_DIR @"/var/mobile/Library/WebClips"

#pragma mark - 日志

static void CILog(NSString *fmt, ...) {
    va_list args;
    va_start(args, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:args];
    va_end(args);

    NSString *dir = @"/var/mobile/Library/Logs";
    [[NSFileManager defaultManager] createDirectoryAtPath:dir
                              withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *path = [dir stringByAppendingPathComponent:@"CraneIcon.log"];
    NSString *line = [NSString stringWithFormat:@"%@ [pid=%d] %@\n", [NSDate date], getpid(), msg];

    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
    if (!fh) {
        [[NSFileManager defaultManager] createFileAtPath:path contents:nil attributes:nil];
        fh = [NSFileHandle fileHandleForWritingAtPath:path];
    }
    [fh seekToEndOfFile];
    [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
    [fh closeFile];

    NSLog(@"[CraneIcon] %@", msg);
}

#pragma mark - 读取 Crane 配置

static NSDictionary *LoadCranePrefs(void) {
    NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:CRANE_PREFS_PATH];
    if (d) return d;
    CFPreferencesAppSynchronize(CRANE_PREFS_DOMAIN);
    CFArrayRef keys = CFPreferencesCopyKeyList(CRANE_PREFS_DOMAIN,
                                               kCFPreferencesCurrentUser,
                                               kCFPreferencesAnyHost);
    if (!keys) return nil;
    NSMutableDictionary *m = [NSMutableDictionary dictionary];
    for (NSString *k in (__bridge NSArray *)keys) {
        CFPropertyListRef v = CFPreferencesCopyAppValue((__bridge CFStringRef)k, CRANE_PREFS_DOMAIN);
        if (v) m[k] = (__bridge_transfer id)v;
    }
    CFRelease(keys);
    return m;
}

static BOOL CraneSetActiveContainer(NSString *bundleID, NSString *containerID) {
    if (!bundleID || !containerID) return NO;

    NSMutableDictionary *prefs = [NSMutableDictionary dictionaryWithContentsOfFile:CRANE_PREFS_PATH];
    if (!prefs) prefs = [NSMutableDictionary dictionary];

    NSString *key = [NSString stringWithFormat:@"appSettings_%@", bundleID];
    NSMutableDictionary *appSettings = [prefs[key] mutableCopy];
    if (!appSettings) {
        CILog(@"找不到 appSettings for %@", bundleID);
        return NO;
    }

    appSettings[@"activeContainer"] = containerID;
    prefs[key] = appSettings;

    [prefs writeToFile:CRANE_PREFS_PATH atomically:YES];
    chmod([CRANE_PREFS_PATH UTF8String], 0666);

    CFPreferencesSetAppValue((__bridge CFStringRef)key,
                             (__bridge CFPropertyListRef)appSettings,
                             CRANE_PREFS_DOMAIN);
    CFPreferencesAppSynchronize(CRANE_PREFS_DOMAIN);

    notify_post("com.opa334.crane/ReloadPrefs");

    CILog(@"切换 %@ -> %@", bundleID, containerID);
    return YES;
}

#pragma mark - 我的记录（防止重复生成图标）

static NSMutableDictionary *LoadMyPrefs(void) {
    NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:MY_PREFS_PATH];
    return d ? [d mutableCopy] : [NSMutableDictionary dictionary];
}

static void SaveMyPrefs(NSDictionary *d) {
    [d writeToFile:MY_PREFS_PATH atomically:YES];
    chmod([MY_PREFS_PATH UTF8String], 0666);
}

#pragma mark - 进程管理

static void KillProcessForBundle(NSString *bundleID) {
    if (!bundleID) return;
    Class pmCls = objc_getClass("FBProcessManager");
    if (!pmCls) return;
    id pm = ((id (*)(id, SEL))objc_msgSend)(pmCls, sel_registerName("sharedInstance"));
    NSArray *procs = ((id (*)(id, SEL, id))objc_msgSend)(pm,
                                                         sel_registerName("processesForBundleIdentifier:"),
                                                         bundleID);
    for (id p in procs) {
        SEL s = sel_registerName("killForReason:andReport:withDescription:completion:");
        if ([p respondsToSelector:s]) {
            ((void (*)(id, SEL, NSInteger, BOOL, id, id))objc_msgSend)(p, s, 1, NO,
                                                                       @"CraneIcon Switch", nil);
        }
    }
}

static void LaunchAppByBundleID(NSString *bundleID) {
    if (!bundleID) return;
    Class ctrlCls = objc_getClass("SBApplicationController");
    if (!ctrlCls) return;
    id ctrl = ((id (*)(id, SEL))objc_msgSend)(ctrlCls, sel_registerName("sharedInstance"));
    id app = ((id (*)(id, SEL, id))objc_msgSend)(ctrl,
                                                 sel_registerName("applicationWithBundleIdentifier:"),
                                                 bundleID);
    if (!app) return;
    Class uiCls = objc_getClass("SBUIController");
    if (!uiCls) return;
    id ui = ((id (*)(id, SEL))objc_msgSend)(uiCls, sel_registerName("sharedInstance"));
    ((void (*)(id, SEL, id))objc_msgSend)(ui, sel_registerName("activateApplication:"), app);
}

#pragma mark - App 信息

static UIImage *ExtractAppIcon(NSString *bundleID) {
    Class cls = objc_getClass("LSApplicationProxy");
    if (!cls) return nil;
    id proxy = ((id (*)(id, SEL, id))objc_msgSend)(cls,
                                                   sel_registerName("applicationProxyForIdentifier:"),
                                                   bundleID);
    if (!proxy) return nil;
    SEL sel = sel_registerName("iconDataForVariant:");
    if ([proxy respondsToSelector:sel]) {
        NSData *data = ((id (*)(id, SEL, int))objc_msgSend)(proxy, sel, 2);
        if (data) return [UIImage imageWithData:data scale:[UIScreen mainScreen].scale];
    }
    return nil;
}

static NSString *AppLocalizedName(NSString *bundleID) {
    Class cls = objc_getClass("LSApplicationProxy");
    if (!cls) return bundleID;
    id proxy = ((id (*)(id, SEL, id))objc_msgSend)(cls,
                                                   sel_registerName("applicationProxyForIdentifier:"),
                                                   bundleID);
    if (!proxy) return bundleID;
    SEL sel = sel_registerName("localizedName");
    if ([proxy respondsToSelector:sel]) {
        NSString *n = ((id (*)(id, SEL))objc_msgSend)(proxy, sel);
        if (n) return n;
    }
    return bundleID;
}

#pragma mark - 生成桌面图标

static void CreateDesktopIcon(NSString *bundleID, NSString *containerID, NSString *containerName) {
    if (!bundleID || !containerID) return;

    dlopen("/System/Library/PrivateFrameworks/WebClip.framework/WebClip", RTLD_NOW);

    NSString *uuid = [[NSUUID UUID] UUIDString];
    NSString *launchURL = [NSString stringWithFormat:@"%@://launch?bundle=%@&container=%@",
                           CRANE_ICON_SCHEME, bundleID, containerID];

    NSString *appName = AppLocalizedName(bundleID);
    NSString *displayName;
    if (containerName && containerName.length > 0) {
        displayName = [NSString stringWithFormat:@"%@ (%@)", appName, containerName];
    } else {
        NSString *shortID = containerID.length > 6 ? [containerID substringToIndex:6] : containerID;
        displayName = [NSString stringWithFormat:@"%@ (%@)", appName, shortID];
    }

    UIImage *icon = ExtractAppIcon(bundleID);

    NSString *dir = [NSString stringWithFormat:@"%@/%@.webclip", WEB_CLIPS_DIR, uuid];
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];

    NSDictionary *meta = @{
        @"Identifier": uuid,
        @"ApplicationBundleID": @"",
        @"ClassicMode": @NO,
        @"FullScreen": @YES,
        @"IconIsPrecomposed": @YES,
        @"IconIsScreenShotBased": @NO,
        @"IsWebClip": @YES,
        @"Title": displayName,
        @"URL": launchURL,
        @"UIStatusBarStyle": @"UIStatusBarStyleDefault"
    };
    NSString *plistPath = [dir stringByAppendingPathComponent:@"Info.plist"];
    [meta writeToFile:plistPath atomically:YES];
    chmod([plistPath UTF8String], 0666);

    if (icon) {
        NSData *png = UIImagePNGRepresentation(icon);
        if (png) {
            NSString *iconPath = [dir stringByAppendingPathComponent:@"icon.png"];
            [png writeToFile:iconPath atomically:YES];
            chmod([iconPath UTF8String], 0666);
        }
    }
    chmod([dir UTF8String], 0777);

    CILog(@"生成图标: %@ -> %@", bundleID, displayName);
}

static void RegenerateAllIcons(void) {
    NSDictionary *crane = LoadCranePrefs();
    if (!crane) {
        CILog(@"读不到 Crane 配置");
        return;
    }

    NSMutableDictionary *mine = LoadMyPrefs();
    NSMutableDictionary *generated = [mine[@"Generated"] mutableCopy] ?: [NSMutableDictionary dictionary];

    int created = 0;
    for (NSString *key in crane) {
        if (![key hasPrefix:@"appSettings_"]) continue;
        NSString *bundleID = [key substringFromIndex:[@"appSettings_" length]];
        if ([bundleID hasPrefix:@"com.apple."]) continue;

        NSDictionary *appSettings = crane[key];
        NSArray *containers = appSettings[@"Containers"];
        if (![containers isKindOfClass:[NSArray class]]) continue;

        NSMutableArray *alreadyGenerated = [generated[bundleID] mutableCopy] ?: [NSMutableArray array];

        for (NSDictionary *c in containers) {
            if (![c isKindOfClass:[NSDictionary class]]) continue;
            NSString *cid = c[@"identifier"];
            NSString *cname = c[@"name"];
            if (!cid) continue;
            if ([cid isEqualToString:@"DEFAULT"]) continue;
            if ([alreadyGenerated containsObject:cid]) continue;

            CreateDesktopIcon(bundleID, cid, cname);
            [alreadyGenerated addObject:cid];
            created++;
        }

        generated[bundleID] = alreadyGenerated;
    }

    mine[@"Generated"] = generated;
    SaveMyPrefs(mine);

    if (created > 0) {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                             CFSTR("com.apple.webclips.changed"),
                                             NULL, NULL, YES);
        CILog(@"共生成 %d 个图标", created);
    } else {
        CILog(@"无需生成新图标");
    }
}

#pragma mark - 拦截 crane-icon:// URL

static BOOL HandleCraneIconURL(NSURL *url) {
    if (!url) return NO;
    if (![[url scheme] isEqualToString:CRANE_ICON_SCHEME]) return NO;

    NSURLComponents *comp = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    NSString *bundle = nil;
    NSString *container = nil;
    for (NSURLQueryItem *q in comp.queryItems) {
        if ([q.name isEqualToString:@"bundle"]) bundle = q.value;
        if ([q.name isEqualToString:@"container"]) container = q.value;
    }

    if (!bundle || !container) {
        CILog(@"URL 参数不全: %@", url);
        return YES;
    }

    CILog(@"收到 URL: %@ -> %@", bundle, container);

    CraneSetActiveContainer(bundle, container);
    KillProcessForBundle(bundle);

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        LaunchAppByBundleID(bundle);
    });

    return YES;
}

%hook LSApplicationWorkspace

- (BOOL)openSensitiveURL:(NSURL *)url withOptions:(NSDictionary *)options {
    if (HandleCraneIconURL(url)) return YES;
    return %orig;
}

- (BOOL)openURL:(NSURL *)url withOptions:(NSDictionary *)options {
    if (HandleCraneIconURL(url)) return YES;
    return %orig;
}

- (BOOL)openURL:(NSURL *)url {
    if (HandleCraneIconURL(url)) return YES;
    return %orig;
}

%end

%hook SpringBoard

- (BOOL)application:(UIApplication *)app openURL:(NSURL *)url options:(NSDictionary *)opts {
    if (HandleCraneIconURL(url)) return YES;
    return %orig;
}

%end

#pragma mark - 启动

%ctor {
    @autoreleasepool {
        %init;
        CILog(@"=== CraneIcon loaded pid=%d ===", getpid());

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            RegenerateAllIcons();
        });
    }
}
