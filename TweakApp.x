#import "Common.h"
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <dlfcn.h>

static NSString *gCurrentBundleID = nil;
static NSString *gCurrentContainerID = nil;
static NSString *gDataContainerPath = nil;
static BOOL gHooksInstalled = NO;

static NSString *CurrentBundleID(void) {
    if (gCurrentBundleID) return gCurrentBundleID;
    gCurrentBundleID = [[NSBundle mainBundle] bundleIdentifier];
    return gCurrentBundleID;
}

static void SetupRedirectContext(void) {
    if (gHooksInstalled) return;
    NSString *bid = CurrentBundleID();
    if (!bid || [bid hasPrefix:@"com.apple."]) return;

    gDataContainerPath = CraneDataContainerPathForBundle(bid);
    gCurrentContainerID = CraneActiveContainerForBundle(bid);

    NSLog(@"[CraneAdvApp] bundle=%@ container=%@ path=%@",
          bid, gCurrentContainerID, gDataContainerPath);
    gHooksInstalled = YES;
}

static NSString *Redirect(NSString *path) {
    if (!path || !gCurrentContainerID || !gHooksInstalled) return path;
    if ([gCurrentContainerID isEqualToString:@"default"]) return path;
    return CraneRedirectPath(path, gCurrentContainerID, gDataContainerPath);
}

%group AppSandbox

%hook NSFileManager

- (BOOL)fileExistsAtPath:(NSString *)path {
    return %orig(Redirect(path));
}

- (BOOL)createDirectoryAtPath:(NSString *)path
  withIntermediateDirectories:(BOOL)createIntermediates
                   attributes:(NSDictionary *)attributes
                        error:(NSError **)error {
    return %orig(Redirect(path), createIntermediates, attributes, error);
}

- (NSArray *)contentsOfDirectoryAtPath:(NSString *)path error:(NSError **)error {
    return %orig(Redirect(path), error);
}

- (BOOL)removeItemAtPath:(NSString *)path error:(NSError **)error {
    return %orig(Redirect(path), error);
}

- (BOOL)moveItemAtPath:(NSString *)srcPath toPath:(NSString *)dstPath error:(NSError **)error {
    return %orig(Redirect(srcPath), Redirect(dstPath), error);
}

- (BOOL)copyItemAtPath:(NSString *)srcPath toPath:(NSString *)dstPath error:(NSError **)error {
    return %orig(Redirect(srcPath), Redirect(dstPath), error);
}

- (NSDictionary *)attributesOfItemAtPath:(NSString *)path error:(NSError **)error {
    return %orig(Redirect(path), error);
}

- (BOOL)createFileAtPath:(NSString *)path contents:(NSData *)contents attributes:(NSDictionary *)attributes {
    return %orig(Redirect(path), contents, attributes);
}

%end

%hook NSUserDefaults

- (instancetype)initWithSuiteName:(NSString *)suitename {
    return %orig(Redirect(suitename));
}

%end

%end // group

%ctor {
    @autoreleasepool {
        %init(AppSandbox);
        SetupRedirectContext();
        NSLog(@"[CraneAdvApp] hooks installed for %@ container=%@",
              gCurrentBundleID, gCurrentContainerID);
    }
}
