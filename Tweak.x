#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

#import "Common.h"
#import <UIKit/UIKit.h>
#import <notify.h>
#import <dlfcn.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <unistd.h>

#pragma mark - 私有类声明

@interface SBSApplicationShortcutItem : NSObject
@property (nonatomic, copy) NSString *type;
@property (nonatomic, copy) NSString *localizedTitle;
@property (nonatomic, copy) NSString *localizedSubtitle;
@end

@interface SBApplicationShortcutStore : NSObject
- (NSString *)bundleIdentifier;
- (NSArray<SBSApplicationShortcutItem *> *)shortcutItems;
@end

@interface FBProcess : NSObject
- (void)killForReason:(NSInteger)reason andReport:(BOOL)report withDescription:(NSString *)desc completion:(id)completion;
@end

@interface FBProcessManager : NSObject
+ (instancetype)sharedInstance;
- (NSArray<FBProcess *> *)processesForBundleIdentifier:(NSString *)bundleID;
@end

@interface LSApplicationProxy : NSObject
+ (instancetype)applicationProxyForIdentifier:(NSString *)bundleID;
- (NSString *)localizedName;
- (NSData *)iconDataForVariant:(int)variant;
@end

@interface SBApplication : NSObject
- (NSString *)bundleIdentifier;
@end

@interface SBApplicationController : NSObject
+ (instancetype)sharedInstance;
- (SBApplication *)applicationWithBundleIdentifier:(NSString *)bundleIdentifier;
@end

@interface SBUIController : NSObject
+ (instancetype)sharedInstance;
- (void)activateApplication:(SBApplication *)app;
@end

#pragma mark - 工具函数

static BOOL gIsBypassingPrompt = NO;

static void KillProcessForBundle(NSString *bundleID) {
    if (!bundleID) return;
    Class pmCls = objc_getClass("FBProcessManager");
    if (!pmCls) return;
    id pm = ((id (*)(id, SEL))objc_msgSend)(pmCls, sel_registerName("sharedInstance"));
    NSArray *procs = ((id (*)(id, SEL, id))objc_msgSend)(pm,
                                                         sel_registerName("processesForBundleIdentifier:"),
                                                         bundleID);
    for (id proc in procs) {
        SEL sel = sel_registerName("killForReason:andReport:withDescription:completion:");
        if ([proc respondsToSelector:sel]) {
            ((void (*)(id, SEL, NSInteger, BOOL, id, id))objc_msgSend)(proc, sel, 1, NO,
                                                                       @"Crane Switch Container", nil);
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

static UIImage *CraneExtractHDAppIcon(NSString *bundleID) {
    CGFloat scale = [UIScreen mainScreen].scale;
    Class proxyCls = objc_getClass("LSApplicationProxy");
    if (!proxyCls) return nil;
    id proxy = ((id (*)(id, SEL, id))objc_msgSend)(proxyCls,
                                                   sel_registerName("applicationProxyForIdentifier:"),
                                                   bundleID);
    if (proxy) {
        SEL sel = sel_registerName("iconDataForVariant:");
        if ([proxy respondsToSelector:sel]) {
            NSData *iconData = ((id (*)(id, SEL, int))objc_msgSend)(proxy, sel, 2);
            if (iconData) return [UIImage imageWithData:iconData scale:scale];
        }
    }
    return nil;
}

static void CreateDesktopIconForContainer(NSString *bundleID, NSString *containerID) {
    if (!bundleID || !containerID) return;
    dlopen("/System/Library/PrivateFrameworks/WebClip.framework/WebClip", RTLD_NOW);

    NSString *clipUUID = [[NSUUID UUID] UUIDString];
    NSString *launchURL = [NSString stringWithFormat:@"%@://open?bundleID=%@&container=%@",
                           CRANE_SCHEME, bundleID, containerID];

    Class proxyCls = objc_getClass("LSApplicationProxy");
    id appProxy = ((id (*)(id, SEL, id))objc_msgSend)(proxyCls,
                                                      sel_registerName("applicationProxyForIdentifier:"),
                                                      bundleID);
    NSString *appName = nil;
    if (appProxy) {
        SEL sel = sel_registerName("localizedName");
        if ([appProxy respondsToSelector:sel]) {
            appName = ((id (*)(id, SEL))objc_msgSend)(appProxy, sel);
        }
    }
    if (!appName) appName = bundleID.lastPathComponent;

    NSString *displayTitle = [containerID isEqualToString:@"default"]
                             ? appName
                             : [NSString stringWithFormat:@"%@ (%@)", appName, containerID];
    UIImage *appIcon = CraneExtractHDAppIcon(bundleID);

    NSString *clipDir = [NSString stringWithFormat:@"/var/mobile/Library/WebClips/%@.webclip", clipUUID];
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm createDirectoryAtPath:clipDir withIntermediateDirectories:YES attributes:nil error:nil];

    NSDictionary *clipMeta = @{
        @"Identifier": clipUUID,
        @"ApplicationBundleID": @"",
        @"ClassicMode": @NO,
        @"FullScreen": @YES,
        @"IconIsPrecomposed": @YES,
        @"IconIsScreenShotBased": @NO,
        @"IsWebClip": @YES,
        @"Title": displayTitle,
        @"URL": launchURL,
        @"UIStatusBarStyle": @"UIStatusBarStyleDefault"
    };
    NSString *plistPath = [clipDir stringByAppendingPathComponent:@"Info.plist"];
    [clipMeta writeToFile:plistPath atomically:YES];
    chmod([plistPath UTF8String], 0666);

    if (appIcon) {
        NSData *pngData = UIImagePNGRepresentation(appIcon);
        if (pngData) {
            NSString *iconPath = [clipDir stringByAppendingPathComponent:@"icon.png"];
            [pngData writeToFile:iconPath atomically:YES];
            chmod([iconPath UTF8String], 0666);
        }
    }
    chmod([clipDir UTF8String], 0777);

    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         CFSTR("com.apple.webclips.changed"),
                                         NULL, NULL, YES);
}

static void HandleClipCreationRequest(void) {
    NSDictionary *prefs = CraneLoadAllPrefs();
    NSString *bundleID = prefs[@"PendingClipBundleID"];
    NSString *containerID = prefs[@"PendingClipContainerID"];

    if (bundleID && containerID) {
        CreateDesktopIconForContainer(bundleID, containerID);
        NSMutableDictionary *mut = [prefs mutableCopy];
        [mut removeObjectForKey:@"PendingClipBundleID"];
        [mut removeObjectForKey:@"PendingClipContainerID"];
        CraneSaveAllPrefs(mut);
    }
}

#pragma mark - 快捷菜单项构造

static NSArray *CraneBuildShortcutItemsForBundle(NSString *bundleID, NSArray *origItems) {
    if (!CraneIsEnabled() || !bundleID) return origItems;
    if ([bundleID hasPrefix:@"com.apple."]) return origItems;

    NSMutableArray *items = [origItems mutableCopy] ?: [NSMutableArray array];
    NSString *activeContainer = CraneActiveContainerForBundle(bundleID);
    NSArray *containers = CraneGetContainersForBundle(bundleID);

    Class itemCls = objc_getClass("SBSApplicationShortcutItem");
    if (!itemCls) itemCls = objc_getClass("UIApplicationShortcutItem");
    if (!itemCls) {
        NSLog(@"[CraneAdv] 找不到 shortcut item 类");
        return items;
    }

    for (NSString *cID in containers) {
        id item = ((id (*)(id, SEL))objc_msgSend)(
            ((id (*)(id, SEL))objc_msgSend)(itemCls, sel_registerName("alloc")),
            sel_registerName("init"));

        NSString *typeStr = [NSString stringWithFormat:@"com.crane.switch.%@", cID];
        NSString *titleStr = [NSString stringWithFormat:@"切换至: %@", cID];
        NSString *subStr = [cID isEqualToString:activeContainer] ? @"[当前激活]" : @"点击切换激活容器";

        ((void (*)(id, SEL, id))objc_msgSend)(item, sel_registerName("setType:"), typeStr);
        ((void (*)(id, SEL, id))objc_msgSend)(item, sel_registerName("setLocalizedTitle:"), titleStr);
        ((void (*)(id, SEL, id))objc_msgSend)(item, sel_registerName("setLocalizedSubtitle:"), subStr);
        [items addObject:item];
    }

    NSLog(@"[CraneAdv] 为 %@ 加入 %lu 个容器菜单", bundleID, (unsigned long)containers.count);
    return items;
}

#pragma mark - iOS 17 快捷菜单（主入口）

%hook SBHIconManager

- (id)iconView:(id)iconView applicationShortcutItemsForMenu:(id)menu withOptions:(id)opts {
    id orig = %orig;
    NSString *bundleID = nil;
    @try {
        id icon = ((id (*)(id, SEL))objc_msgSend)(iconView, sel_registerName("icon"));
        if (icon) {
            bundleID = ((id (*)(id, SEL))objc_msgSend)(icon, sel_registerName("applicationBundleID"));
            if (!bundleID) {
                bundleID = ((id (*)(id, SEL))objc_msgSend)(icon, sel_registerName("applicationBundleIdentifier"));
            }
        }
    } @catch (NSException *e) {
        NSLog(@"[CraneAdv] 取 bundleID 异常: %@", e);
    }

    NSArray *origItems = nil;
    if ([orig isKindOfClass:[NSArray class]]) origItems = orig;
    else if ([orig isKindOfClass:[NSDictionary class]]) {
        origItems = orig[@"items"];
    }

    if (!origItems) return orig;
    NSArray *newItems = CraneBuildShortcutItemsForBundle(bundleID, origItems);

    if ([orig isKindOfClass:[NSArray class]]) return newItems;
    if ([orig isKindOfClass:[NSDictionary class]]) {
        NSMutableDictionary *d = [orig mutableCopy];
        d[@"items"] = newItems;
        return d;
    }
    return orig;
}

- (void)iconView:(id)iconView activateApplicationShortcutItem:(id)item {
    NSString *type = nil;
    @try {
        type = ((id (*)(id, SEL))objc_msgSend)(item, sel_registerName("type"));
    } @catch (NSException *e) {}

    if (type && [type hasPrefix:@"com.crane.switch."]) {
        NSString *cID = [type stringByReplacingOccurrencesOfString:@"com.crane.switch." withString:@""];
        NSString *bundleID = nil;
        @try {
            id icon = ((id (*)(id, SEL))objc_msgSend)(iconView, sel_registerName("icon"));
            if (icon) {
                bundleID = ((id (*)(id, SEL))objc_msgSend)(icon, sel_registerName("applicationBundleID"));
            }
        } @catch (NSException *e) {}

        NSLog(@"[CraneAdv] 点击容器菜单: %@ -> %@", bundleID, cID);
        if (bundleID) {
            CraneSetActiveContainerForBundle(bundleID, cID);
            KillProcessForBundle(bundleID);
        }
        return;
    }
    %orig;
}

%end

#pragma mark - iOS 13-16 老路径（保留兜底）

%hook SBApplicationShortcutStore

- (NSArray *)shortcutItems {
    NSArray *orig = %orig;
    NSString *bundleID = [self bundleIdentifier];
    NSLog(@"[CraneAdv] 老路径 shortcutItems 被调用: %@", bundleID);
    return CraneBuildShortcutItemsForBundle(bundleID, orig);
}

%end

#pragma mark - SBUIController（启动时询问容器）

%hook SBUIController

- (void)activateApplication:(SBApplication *)app {
    if (!CraneIsEnabled() || gIsBypassingPrompt) {
        %orig;
        return;
    }

    NSString *bundleID = nil;
    if ([app respondsToSelector:@selector(bundleIdentifier)]) {
        bundleID = [app bundleIdentifier];
    }

    if (bundleID && ![bundleID hasPrefix:@"com.apple."]) {
        BOOL alwaysAsk = CraneGetAppBool(bundleID, @"PromptOnLaunch", NO);
        if (alwaysAsk) {
            NSArray *containers = CraneGetContainersForBundle(bundleID);
            if (containers.count > 1) {
                UIAlertController *alert = [UIAlertController
                    alertControllerWithTitle:@"选择启动容器"
                    message:[NSString stringWithFormat:@"目标应用: %@", bundleID.lastPathComponent]
                    preferredStyle:UIAlertControllerStyleActionSheet];

                for (NSString *cID in containers) {
                    [alert addAction:[UIAlertAction
                        actionWithTitle:[cID isEqualToString:@"default"] ? @"默认" : cID
                        style:UIAlertActionStyleDefault
                        handler:^(UIAlertAction *action) {
                            CraneSetActiveContainerForBundle(bundleID, cID);
                            KillProcessForBundle(bundleID);
                            gIsBypassingPrompt = YES;
                            LaunchAppByBundleID(bundleID);
                            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)),
                                           dispatch_get_main_queue(), ^{
                                gIsBypassingPrompt = NO;
                            });
                        }]];
                }
                [alert addAction:[UIAlertAction actionWithTitle:@"取消"
                                                          style:UIAlertActionStyleCancel
                                                        handler:nil]];

                UIViewController *vc = [UIApplication sharedApplication].keyWindow.rootViewController;
                [vc presentViewController:alert animated:YES completion:nil];
                return;
            }
        }
    }

    %orig;
}

%end

#pragma mark - URL scheme（桌面分身图标点击）

%hook SpringBoard

- (BOOL)application:(UIApplication *)application
            openURL:(NSURL *)url
            options:(NSDictionary *)options {
    if ([[url scheme] isEqualToString:CRANE_SCHEME]) {
        NSURLComponents *comp = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
        NSString *targetBundle = nil;
        NSString *targetContainer = nil;
        for (NSURLQueryItem *item in comp.queryItems) {
            if ([item.name isEqualToString:@"bundleID"]) targetBundle = item.value;
            if ([item.name isEqualToString:@"container"]) targetContainer = item.value;
        }
        if (targetBundle && targetContainer) {
            CraneSetActiveContainerForBundle(targetBundle, targetContainer);
            KillProcessForBundle(targetBundle);
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                LaunchAppByBundleID(targetBundle);
            });
            return YES;
        }
    }
    return %orig;
}

%end

#pragma mark - 构造器

%ctor {
    @autoreleasepool {
        %init;
        NSLog(@"[CraneAdv] Tweak loaded in pid=%d", getpid());

        dispatch_async(dispatch_get_global_queue(0, 0), ^{
            NSString *baseDir = @"/var/mobile/Library/WebClips";
            NSFileManager *fm = [NSFileManager defaultManager];
            NSArray *items = [fm contentsOfDirectoryAtPath:baseDir error:nil];
            for (NSString *item in items) {
                if ([item hasSuffix:@".webclip"]) {
                    NSString *folder = [baseDir stringByAppendingPathComponent:item];
                    NSString *infoFile = [folder stringByAppendingPathComponent:@"Info.plist"];
                    if (![fm fileExistsAtPath:infoFile]) {
                        [fm removeItemAtPath:folder error:nil];
                    }
                }
            }
        });

        int token;
        notify_register_dispatch(NOTIFY_CREATE_CLIP, &token, dispatch_get_main_queue(), ^(int t) {
            HandleClipCreationRequest();
        });
    }
}

#pragma clang diagnostic pop
