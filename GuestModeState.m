#import "GuestModeState.h"

NSDictionary *GuestModeLoadState(void) {
    return [NSDictionary dictionaryWithContentsOfFile:kGuestStatePath] ?: @{};
}

void GuestModeSaveState(NSDictionary *state) {
    [state writeToFile:kGuestStatePath atomically:YES];
}

BOOL GuestModeIsActive(void) {
    return [GuestModeLoadState()[kGuestActiveKey] boolValue];
}

NSArray<NSString *> *GuestModeAllowedApps(void) {
    return GuestModeLoadState()[kGuestAllowedAppsKey] ?: @[];
}

BOOL GuestModeIsAppAllowed(NSString *bundleID) {
    if (!bundleID) return NO;
    return [GuestModeAllowedApps() containsObject:bundleID];
}

NSString *GuestModeExitPasscode(void) {
    return GuestModeLoadState()[kGuestExitPasscodeKey] ?: @"";
}
