// xrkit 夜览：一点开关夜览。CoreBrightness 的 CBBlueLightClient：
// -getBlueLightStatus:(状态结构体指针，第 0 字节 active、第 1 字节 enabled) / -setEnabled:（iOS 17.3.1 符号核对过）
#import "../XRKModule.h"
#import <dlfcn.h>

@interface XRKNightShiftModule : CCUIToggleModule
@end

static id XRKBlueLight(void) {
    static id client;
    if (!client) {
        dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_NOW);
        client = [objc_getClass("CBBlueLightClient") new];
    }
    return client;
}

@implementation XRKNightShiftModule

- (UIImage *)iconGlyph { return XRKGlyph(@"sunset"); }
- (UIImage *)selectedIconGlyph { return XRKGlyph(@"sunset.fill"); }
- (UIColor *)selectedColor { return UIColor.systemOrangeColor; }

- (BOOL)isSelected {
    id c = XRKBlueLight();
    if (![c respondsToSelector:@selector(getBlueLightStatus:)]) return NO;
    // 结构体大小随系统变，给足空间
    unsigned char status[128] = {0};
    BOOL ok = ((BOOL (*)(id, SEL, void *))objc_msgSend)(c, @selector(getBlueLightStatus:), status);
    return ok && status[1];
}

- (void)setSelected:(BOOL)selected {
    id c = XRKBlueLight();
    if ([c respondsToSelector:@selector(setEnabled:)]) ((BOOL (*)(id, SEL, BOOL))objc_msgSend)(c, @selector(setEnabled:), selected);
    [super setSelected:selected];
}

@end
