// xrkit 锁屏：点一下熄屏锁定，等同按电源键（SBBacklightController -_startFadeOutAnimationFromLockSource:）
#import "../XRKModule.h"

@interface XRKLockModule : CCUIToggleModule
@end

@implementation XRKLockModule

- (UIImage *)iconGlyph { return XRKGlyph(@"lock.fill"); }
- (UIColor *)selectedColor { return UIColor.systemBlueColor; }
- (BOOL)isSelected { return NO; }

- (void)setSelected:(BOOL)selected {
    XRKHaptic();
    [self.contentModuleContext dismissControlCenter];
    // 等控制中心收起再熄屏，否则下次亮屏控制中心还停在半路
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        id backlight = XRKShared("SBBacklightController");
        SEL sel = NSSelectorFromString(@"_startFadeOutAnimationFromLockSource:");
        if ([backlight respondsToSelector:sel]) ((void (*)(id, SEL, int))objc_msgSend)(backlight, sel, 1);
    });
}

@end
