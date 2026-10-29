#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface PSListController : UIViewController {
    NSMutableArray *_specifiers;
}
- (NSArray *)specifiers;
- (id)readPreferenceValue:(id)specifier;
- (void)setPreferenceValue:(id)value specifier:(id)specifier;
@end

@interface PSSpecifier : NSObject
+ (instancetype)groupSpecifierWithName:(NSString *)name;
+ (instancetype)preferenceSpecifierNamed:(NSString *)name target:(id)target set:(SEL)set get:(SEL)get detail:(Class)detail cell:(int)cell edit:(Class)edit;
- (void)setProperty:(id)property forKey:(NSString *)key;
- (id)propertyForKey:(NSString *)key;
@end

// 定义 Cell 枚举常量防报错
#define PSGroupCell 0
#define PSButtonCell 13
#define PSEditTextCell 8
#define PSSwitchCell 6

@interface GuestModeRootListController : PSListController
@end
