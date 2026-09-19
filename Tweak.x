#import "Common.h"
#import <UIKit/UIKit.h>
#import <notify.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <unistd.h>

#pragma mark - 写日志到文件

static void CraneLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *msg = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    NSString *dir = @"/var/mobile/Library/Logs";
    [[NSFileManager defaultManager] createDirectoryAtPath:dir
                              withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *path = [dir stringByAppendingPathComponent:@"CraneAdv.log"];
    NSString *line = [NSString stringWithFormat:@"%@ [pid=%d] %@\n",
                      [NSDate date], getpid(), msg];

    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
    if (!fh) {
        [[NSFileManager defaultManager] createFileAtPath:path contents:nil attributes:nil];
        fh = [NSFileHandle fileHandleForWritingAtPath:path];
    }
    [fh seekToEndOfFile];
    [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
    [fh closeFile];

    NSLog(@"[CraneAdv] %@", msg);
}

#pragma mark - 工具函数

static void KillProc(NSString *bid) {
    if (!bid) return;
    Class cls = objc_getClass("FBProcessManager");
    if (!cls) return;
    id pm = ((id (*)(id, SEL))objc_msgSend)(cls, sel_registerName("sharedInstance"));
    NSArray *ps = ((id (*)(id, SEL, id))objc_msgSend)(pm,
                                                      sel_registerName("processesForBundleIdentifier:"),
                                                      bid);
    for (id p in ps) {
        SEL s = sel_registerName("killForReason:andReport:withDescription:completion:");
        if ([p respondsToSelector:s]) {
            ((void (*)(id, SEL, NSInteger, BOOL, id, id))objc_msgSend)(p, s, 1, NO, @"Crane", nil);
        }
    }
}

static NSString *GetStr(id obj, NSString *selName) {
    if (!obj) return nil;
    SEL sel = NSSelectorFromString(selName);
    if (![obj respondsToSelector:sel]) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(obj, sel);
}

static BOOL AlreadyHasCraneItem(NSArray *items) {
    if (!items) return NO;
    for (id item in items) {
        NSString *type = GetStr(item, @"type");
        if (type && [type hasPrefix:@"com.crane.switch."]) return YES;
    }
    return NO;
}

static NSArray *BuildItems(NSString *bid, NSArray *orig) {
    if (!CraneIsEnabled() || !bid || [bid hasPrefix:@"com.apple."]) return orig;
    if (AlreadyHasCraneItem(orig)) return orig;

    NSMutableArray *items = [orig mutableCopy] ?: [NSMutableArray array];
    NSString *active = CraneActiveContainerForBundle(bid);
    NSArray *cs = CraneGetContainersForBundle(bid);

    Class itemCls = objc_getClass("SBSApplicationShortcutItem");
    if (!itemCls) itemCls = objc_getClass("UIApplicationShortcutItem");
    if (!itemCls) {
        CraneLog(@"[BuildItems] 找不到 shortcut item 类");
        return items;
    }

    for (NSString *c in cs) {
        id item = ((id (*)(id, SEL))objc_msgSend)(
            ((id (*)(id, SEL))objc_msgSend)(itemCls, sel_registerName("alloc")),
            sel_registerName("init"));
        ((void (*)(id, SEL, id))objc_msgSend)(item, sel_registerName("setType:"),
            [NSString stringWithFormat:@"com.crane.switch.%@", c]);
        ((void (*)(id, SEL, id))objc_msgSend)(item, sel_registerName("setLocalizedTitle:"),
            [NSString stringWithFormat:@"切换至: %@", c]);
        ((void (*)(id, SEL, id))objc_msgSend)(item, sel_registerName("setLocalizedSubtitle:"),
            [c isEqualToString:active] ? @"[当前激活]" : @"点击切换");
        [items addObject:item];
    }
    CraneLog(@"[BuildItems] 为 %@ 加入 %lu 项", bid, (unsigned long)cs.count);
    return items;
}

#pragma mark - Hook 1: SBHIconManager（主要入口）

%hook SBHIconManager

- (id)iconView:(id)iconView applicationShortcutItemsForMenu:(id)menu withOptions:(id)opts {
    id orig = %orig;
    CraneLog(@"[Hook1] SBHIconManager 被调用");

    NSString *bid = nil;
    id icon = ((id (*)(id, SEL))objc_msgSend)(iconView, sel_registerName("icon"));
    if (icon) {
        bid = GetStr(icon, @"applicationBundleID");
        if (!bid) bid = GetStr(icon, @"applicationBundleIdentifier");
    }

    NSArray *origItems = nil;
    if ([orig isKindOfClass:[NSArray class]]) {
        origItems = orig;
    } else if ([orig isKindOfClass:[NSDictionary class]]) {
        origItems = orig[@"items"];
    }
    if (!origItems) return orig;

    NSArray *newItems = BuildItems(bid, origItems);

    if ([orig isKindOfClass:[NSArray class]]) return newItems;
    if ([orig isKindOfClass:[NSDictionary class]]) {
        NSMutableDictionary *d = [orig mutableCopy];
        d[@"items"] = newItems;
        return d;
    }
    return orig;
}

- (void)iconView:(id)iconView activateApplicationShortcutItem:(id)item {
    NSString *type = GetStr(item, @"type");
    if (type && [type hasPrefix:@"com.crane.switch."]) {
        NSString *cid = [type stringByReplacingOccurrencesOfString:@"com.crane.switch." withString:@""];
        id icon = ((id (*)(id, SEL))objc_msgSend)(iconView, sel_registerName("icon"));
        NSString *bid = GetStr(icon, @"applicationBundleID");
        CraneLog(@"[Hook1] 点击: %@ -> %@", bid, cid);
        if (bid) {
            CraneSetActiveContainerForBundle(bid, cid);
            KillProc(bid);
        }
        return;
    }
    %orig;
}

%end

#pragma mark - Hook 2: SBIconView（备用入口）

%hook SBIconView

- (NSArray *)applicationShortcutItems {
    NSArray *orig = %orig;
    CraneLog(@"[Hook2] SBIconView.applicationShortcutItems count=%lu", (unsigned long)orig.count);
    return orig;
}

- (NSArray *)_applicationShortcutItems {
    NSArray *orig = %orig;
    CraneLog(@"[Hook2b] SBIconView._applicationShortcutItems count=%lu", (unsigned long)orig.count);
    return orig;
}

- (id)_applicationShortcutItemsForMenu:(id)menu withOptions:(id)opts {
    id orig = %orig;
    CraneLog(@"[Hook2c] SBIconView._applicationShortcutItemsForMenu");
    return orig;
}

%end

#pragma mark - 启动

%ctor {
    @autoreleasepool {
        %init;
        CraneLog(@"=== Tweak loaded in pid=%d ===", getpid());
    }
}
