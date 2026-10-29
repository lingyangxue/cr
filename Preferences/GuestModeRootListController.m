#import "GuestModeRootListController.h"
#import "../GuestModeState.h"
#import <objc/runtime.h>

@interface LSApplicationProxy : NSObject
@property (nonatomic, readonly) NSString *bundleIdentifier;
@property (nonatomic, readonly) NSString *localizedName;
@property (nonatomic, readonly) NSString *applicationType;
@end

@interface LSApplicationWorkspace : NSObject
+ (instancetype)defaultWorkspace;
- (NSArray<LSApplicationProxy *> *)allInstalledApplications;
@end

@implementation GuestModeRootListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        NSMutableArray *specs = [NSMutableArray array];

        PSSpecifier *group1 = [PSSpecifier groupSpecifierWithName:@"访客模式"];
        [specs addObject:group1];

        PSSpecifier *enterBtn = [PSSpecifier preferenceSpecifierNamed:@"进入访客模式并注销"
                                                               target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
        // 修复 ARC 强转报错：使用 NSStringFromSelector 作为字符串传递
        [enterBtn setProperty:NSStringFromSelector(@selector(enterGuestMode)) forKey:@"action"];
        [specs addObject:enterBtn];

        PSSpecifier *exitPass = [PSSpecifier preferenceSpecifierNamed:@"退出密码"
                                                               target:self set:@selector(setExitPasscode:specifier:) get:@selector(getExitPasscode:) detail:nil cell:PSEditTextCell edit:nil];
        [specs addObject:exitPass];

        PSSpecifier *group2 = [PSSpecifier groupSpecifierWithName:@"允许访客使用的原生 App"];
        [specs addObject:group2];

        for (NSDictionary *app in [self fetchNativeApps]) {
            PSSpecifier *spec = [PSSpecifier preferenceSpecifierNamed:app[@"name"]
                                                               target:self set:@selector(setAppAllowed:specifier:) get:@selector(getAppAllowed:) detail:nil cell:PSSwitchCell edit:nil];
            [spec setProperty:app[@"bundleID"] forKey:@"bundleID"];
            [specs addObject:spec];
        }

        _specifiers = specs;
    }
    return _specifiers;
}

- (NSArray<NSDictionary *> *)fetchNativeApps {
    NSArray *all = [[LSApplicationWorkspace defaultWorkspace] allInstalledApplications];
    NSMutableArray *result = [NSMutableArray array];
    for (LSApplicationProxy *app in all) {
        if ([app.applicationType isEqualToString:@"System"]) {
            [result addObject:@{
                @"bundleID": app.bundleIdentifier ?: @"",
                @"name": app.localizedName ?: app.bundleIdentifier ?: @"未知"
            }];
        }
    }
    return [result sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [a[@"name"] compare:b[@"name"]];
    }];
}

// 修复 expected a type 报错：改为 id
- (void)setAppAllowed:(id)cell specifier:(PSSpecifier *)spec {
    BOOL on = [[self readPreferenceValue:spec] boolValue];
    NSString *bundleID = [spec propertyForKey:@"bundleID"];

    NSMutableDictionary *state = [GuestModeLoadState() mutableCopy];
    NSMutableArray *allowed = [state[kGuestAllowedAppsKey] mutableCopy] ?: [NSMutableArray array];

    if (on && ![allowed containsObject:bundleID]) [allowed addObject:bundleID];
    if (!on) [allowed removeObject:bundleID];

    state[kGuestAllowedAppsKey] = allowed;
    GuestModeSaveState(state);
    [self setPreferenceValue:@(on) specifier:spec];
}

- (id)getAppAllowed:(PSSpecifier *)spec {
    NSString *bundleID = [spec propertyForKey:@"bundleID"];
    return @([GuestModeAllowedApps() containsObject:bundleID]);
}

- (void)setExitPasscode:(NSString *)value specifier:(PSSpecifier *)spec {
    NSMutableDictionary *state = [GuestModeLoadState() mutableCopy];
    state[kGuestExitPasscodeKey] = value ?: @"";
    GuestModeSaveState(state);
    [self setPreferenceValue:value specifier:spec];
}

- (NSString *)getExitPasscode:(PSSpecifier *)spec {
    return GuestModeExitPasscode();
}

- (void)enterGuestMode {
    if (GuestModeAllowedApps().count == 0) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"提示" message:@"请至少选择一个允许访客使用的 App" preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    if (GuestModeExitPasscode().length == 0) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"提示" message:@"请先设置退出密码" preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }

    NSMutableDictionary *state = [GuestModeLoadState() mutableCopy];
    state[kGuestActiveKey] = @YES;
    GuestModeSaveState(state);

    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("com.yourname.guestmode.respring"), NULL, NULL, YES);
}

@end
