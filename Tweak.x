#import "Common.h"
#import <UIKit/UIKit.h>
#import <notify.h>
#import <dlfcn.h>
#import <objc/runtime.h>

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

#pragma mark - Hook SBUIController

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

#pragma mark - Hook URL scheme 处理

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
