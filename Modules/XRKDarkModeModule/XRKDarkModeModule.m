// xrkit 深色模式：一点切换深色 / 浅色。UIKitServices 的 UISUserInterfaceStyleMode（系统设置里外观切换用的）：
// -modeValue：1 浅色、2 深色；-setModeValue:（iOS 17.3.1 符号核对过）
#import "../XRKModule.h"
#import <dlfcn.h>

@interface XRKDarkModeModule : CCUIToggleModule
@end

static id XRKStyleMode(void) {
    static id mode;
    if (!mode) {
        dlopen("/System/Library/PrivateFrameworks/UIKitServices.framework/UIKitServices", RTLD_NOW);
        Class cls = objc_getClass("UISUserInterfaceStyleMode");
        if ([cls instancesRespondToSelector:@selector(initWithDelegate:)])
            mode = ((id (*)(id, SEL, id))objc_msgSend)([cls alloc], @selector(initWithDelegate:), nil);
    }
    return mode;
}

@implementation XRKDarkModeModule

- (UIImage *)iconGlyph { return XRKGlyph(@"circle.lefthalf.filled"); }
- (UIColor *)selectedColor { return UIColor.systemIndigoColor; }

- (BOOL)isSelected {
    id mode = XRKStyleMode();
    if (![mode respondsToSelector:@selector(modeValue)]) return NO;
    return ((long long (*)(id, SEL))objc_msgSend)(mode, @selector(modeValue)) == 2;
}

- (void)setSelected:(BOOL)selected {
    id mode = XRKStyleMode();
    if ([mode respondsToSelector:@selector(setModeValue:)])
        ((void (*)(id, SEL, long long))objc_msgSend)(mode, @selector(setModeValue:), selected ? 2 : 1);
    [super setSelected:selected];
}

@end
