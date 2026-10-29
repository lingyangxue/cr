#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <signal.h>
#import "GuestModeState.h"

static BOOL gGuestActive = NO;

@interface SBIcon : NSObject
- (NSString *)applicationBundleID;
@end

@interface SBIconModel : NSObject
- (BOOL)isIconVisible:(SBIcon *)icon;
@end

@interface LSApplicationWorkspace : NSObject
+ (instancetype)defaultWorkspace;
- (BOOL)openApplicationWithBundleID:(NSString *)bundleID;
@end

@interface SBDeviceLockController : NSObject
+ (instancetype)sharedInstance;
- (BOOL)attemptDeviceUnlockWithPassword:(NSString *)passcode appRequested:(BOOL)appRequested;
@end

static void GuestModeRespringCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    kill(getpid(), SIGKILL);
}

static void GuestModeExit(void) {
    NSMutableDictionary *state = [GuestModeLoadState() mutableCopy];
    [state removeObjectForKey:kGuestActiveKey];
    GuestModeSaveState(state);
    kill(getpid(), SIGKILL);
}

%hook SpringBoard
- (void)applicationDidFinishLaunching:(id)application {
    %orig;
    gGuestActive = GuestModeIsActive();
    NSLog(@"[GuestMode] active=%d allowed=%@", gGuestActive, GuestModeAllowedApps());
}
%end

%hook SBIconModel
- (BOOL)isIconVisible:(SBIcon *)icon {
    BOOL orig = %orig;
    if (gGuestActive) {
        NSString *bundleID = [icon applicationBundleID];
        if (bundleID && !GuestModeIsAppAllowed(bundleID)) return NO;
    }
    return orig;
}
%end

%hook LSApplicationWorkspace
- (BOOL)openApplicationWithBundleID:(NSString *)bundleID {
    if (gGuestActive && !GuestModeIsAppAllowed(bundleID)) {
        NSLog(@"[GuestMode] 拦截启动: %@", bundleID);
        return NO;
    }
    return %orig;
}
%end

%hook SBDeviceLockController
- (BOOL)attemptDeviceUnlockWithPassword:(NSString *)passEntered appRequested:(BOOL)appRequested {
    if (gGuestActive) {
        NSString *exitPass = GuestModeExitPasscode();
        if (exitPass.length > 0 && [passEntered isEqualToString:exitPass]) {
            NSLog(@"[GuestMode] 退出密码匹配，退出访客模式");
            GuestModeExit();
            return NO;
        }
    }
    return %orig;
}
%end

static NSDate *gLastPowerPress = nil;
static NSInteger gPowerPressCount = 0;

%hook SBHardwareButtonController
- (void)powerButtonDown {
    %orig;
    if (!gGuestActive) return;
    NSDate *now = [NSDate date];
    NSTimeInterval interval = gLastPowerPress ? [now timeIntervalSinceDate:gLastPowerPress] : 999;
    gLastPowerPress = now;
    if (interval < 2.0) {
        gPowerPressCount++;
        if (gPowerPressCount >= 3) {
            gPowerPressCount = 0;
            gLastPowerPress = nil;
            NSLog(@"[GuestMode] 手势退出触发");
            GuestModeExit();
        }
    } else {
        gPowerPressCount = 1;
    }
}
%end

%ctor {
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, GuestModeRespringCallback, CFSTR("com.yourname.guestmode.respring"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
}
