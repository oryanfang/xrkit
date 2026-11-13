// xrkit 电源：点一下注销（重启 SpringBoard）。
// 走 SpringBoard 自己的 SBRestartManager -restartWithTransitionRequest:（系统正常注销的同一条路）
#import "../XRKModule.h"

@interface SBRestartTransitionRequest : NSObject
- (instancetype)initWithRequester:(NSString *)requester reason:(NSString *)reason;
@end

@interface XRKPowerModule : CCUIToggleModule
@end

@implementation XRKPowerModule

- (UIImage *)iconGlyph { return XRKGlyph(@"slowmo"); }   // 转圈（像"加载中"），用 power 看着像关机
- (UIColor *)selectedColor { return UIColor.systemRedColor; }
- (BOOL)isSelected { return NO; }

- (void)setSelected:(BOOL)selected {
    XRKHaptic();
    id app = UIApplication.sharedApplication;
    id manager = [app respondsToSelector:@selector(restartManager)] ? [app valueForKey:@"restartManager"] : nil;
    Class reqClass = objc_getClass("SBRestartTransitionRequest");
    if (manager && reqClass && [manager respondsToSelector:@selector(restartWithTransitionRequest:)]) {
        id req = [[reqClass alloc] initWithRequester:@"xrkit" reason:@"xrkit power module"];
        ((void (*)(id, SEL, id))objc_msgSend)(manager, @selector(restartWithTransitionRequest:), req);
    }
}

@end
