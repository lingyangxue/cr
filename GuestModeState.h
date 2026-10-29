#import <Foundation/Foundation.h>

#define kGuestStatePath @"/var/jb/var/mobile/Library/Preferences/com.yourname.guestmode.plist"

#define kGuestActiveKey       @"active"
#define kGuestAllowedAppsKey  @"allowedApps"
#define kGuestExitPasscodeKey @"exitPasscode"

NSDictionary *GuestModeLoadState(void);
void GuestModeSaveState(NSDictionary *state);
BOOL GuestModeIsActive(void);
NSArray<NSString *> *GuestModeAllowedApps(void);
BOOL GuestModeIsAppAllowed(NSString *bundleID);
NSString *GuestModeExitPasscode(void);
