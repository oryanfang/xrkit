#import <Foundation/Foundation.h>

// 偏好域与通知名：设置面板写入这里，插件从这里读取
#define XRK_PREFS_DOMAIN   @"com.xyrith.xrkit"
#define XRK_PREFS_CHANGED  "com.xyrith.xrkit/prefschanged"

@interface XRKPrefs : NSObject

+ (instancetype)shared;

// 从 cfprefsd 重新读取全部偏好
- (void)reload;

- (BOOL)boolForKey:(NSString *)key fallback:(BOOL)fallback;
- (double)doubleForKey:(NSString *)key fallback:(double)fallback;
- (id)objectForKey:(NSString *)key;

// 总开关（默认开启）
@property (nonatomic, readonly) BOOL enabled;

@end
