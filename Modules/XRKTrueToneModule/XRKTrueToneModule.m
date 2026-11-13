// xrkit 原彩显示：一点开关原彩（True Tone）。CoreBrightness 的 CBAdaptationClient：-getEnabled / -setEnabled:
#import "../XRKModule.h"
#import <dlfcn.h>

@interface XRKTrueToneModule : CCUIToggleModule
@end

static id XRKAdaptation(void) {
    static id client;
    if (!client) {
        dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_NOW);
        client = [objc_getClass("CBAdaptationClient") new];
    }
    return client;
}

@implementation XRKTrueToneModule

- (UIImage *)iconGlyph { return XRKGlyph(@"sun.max.circle"); }
- (UIImage *)selectedIconGlyph { return XRKGlyph(@"sun.max.circle.fill"); }
- (UIColor *)selectedColor { return UIColor.systemYellowColor; }

- (BOOL)isSelected {
    id c = XRKAdaptation();
    if (![c respondsToSelector:@selector(getEnabled)]) return NO;
    return ((BOOL (*)(id, SEL))objc_msgSend)(c, @selector(getEnabled));
}

- (void)setSelected:(BOOL)selected {
    id c = XRKAdaptation();
    if ([c respondsToSelector:@selector(setEnabled:)]) ((BOOL (*)(id, SEL, BOOL))objc_msgSend)(c, @selector(setEnabled:), selected);
    [super setSelected:selected];
}

@end
