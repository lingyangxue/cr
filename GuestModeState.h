#import <Foundation/Foundation.h>

#define kGuestStatePath @"/var/jb/var/mobile/Library/Preferences/com.yourname.guestmode.plist"

#define kGuestActiveKey       @"active"
#define kGuestAllowedAppsKey  @"allowedApps"
#define kGuestExitPasscodeKey @"exitPasscode"

// 加上 extern "C" 防止 C++ 编译器对函数名进行修饰导致链接失败
#ifdef __cplusplus
extern "C" {
#endif

NSDictionary *GuestModeLoadState(void);
void GuestModeSaveState(NSDictionary *state);
BOOL GuestModeIsActive(void);
NSArray<NSString *> *GuestModeAllowedApps(void);
BOOL GuestModeIsAppAllowed(NSString *bundleID);
NSString *GuestModeExitPasscode(void);

#ifdef __cplusplus
}
#endif
