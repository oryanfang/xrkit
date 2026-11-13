// xrkit 屏幕常亮：打开后不自动锁屏，再点一下恢复。SpringBoard 的 SBBacklightController -preventIdleSleep / -allowIdleSleep。
// 状态只在这次 SpringBoard 运行期间有效（注销后恢复正常自动锁定，避免忘了关一直亮着）
#import "../XRKModule.h"

@interface XRKKeepAwakeModule : CCUIToggleModule
@end

static BOOL gKeepAwake;

@implementation XRKKeepAwakeModule

- (UIImage *)iconGlyph { return XRKGlyph(@"cup.and.saucer"); }
- (UIImage *)selectedIconGlyph { return XRKGlyph(@"cup.and.saucer.fill"); }
- (UIColor *)selectedColor { return UIColor.systemBrownColor; }
- (BOOL)isSelected { return gKeepAwake; }

- (void)setSelected:(BOOL)selected {
    id backlight = XRKShared("SBBacklightController");
    SEL sel = selected ? @selector(preventIdleSleep) : @selector(allowIdleSleep);
    if ([backlight respondsToSelector:sel]) {
        ((void (*)(id, SEL))objc_msgSend)(backlight, sel);
        gKeepAwake = selected;
    }
    [super setSelected:gKeepAwake];
}

@end
