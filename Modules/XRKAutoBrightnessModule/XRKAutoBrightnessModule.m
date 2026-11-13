// xrkit 自动亮度：开关「自动亮度」（系统在 设置 › 辅助功能 › 显示与文字大小 里）。
// 读：libAccessibility _AXSAutoBrightnessEnabled()；写：BackBoardServices BKSDisplayBrightnessSetAutoBrightnessEnabled()，
// 再把偏好 com.apple.BackBoard / BKEnableALS 存一下，重启后保持（iOS 17.3.1 符号核对过）
#import "../XRKModule.h"
#import <dlfcn.h>

@interface XRKAutoBrightnessModule : CCUIToggleModule
@end

static Boolean (*pAXSAutoBrightnessEnabled)(void);
static void (*pBKSSetAutoBrightness)(Boolean);

static void XRKLoadBrightnessFns(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        pAXSAutoBrightnessEnabled = dlsym(RTLD_DEFAULT, "_AXSAutoBrightnessEnabled");
        if (!pAXSAutoBrightnessEnabled) {
            void *h = dlopen("/usr/lib/libAccessibility.dylib", RTLD_NOW);
            if (h) pAXSAutoBrightnessEnabled = dlsym(h, "_AXSAutoBrightnessEnabled");
        }
        pBKSSetAutoBrightness = dlsym(RTLD_DEFAULT, "BKSDisplayBrightnessSetAutoBrightnessEnabled");
    });
}

@implementation XRKAutoBrightnessModule

- (UIImage *)iconGlyph { return XRKGlyph(@"sun.max"); }
- (UIImage *)selectedIconGlyph { return XRKGlyph(@"sun.max.fill"); }
- (UIColor *)selectedColor { return UIColor.systemOrangeColor; }

- (BOOL)isSelected {
    XRKLoadBrightnessFns();
    if (pAXSAutoBrightnessEnabled) return pAXSAutoBrightnessEnabled();
    CFPropertyListRef v = CFPreferencesCopyAppValue(CFSTR("BKEnableALS"), CFSTR("com.apple.BackBoard"));
    BOOL on = v ? CFBooleanGetValue((CFBooleanRef)v) : YES;
    if (v) CFRelease(v);
    return on;
}

- (void)setSelected:(BOOL)selected {
    XRKLoadBrightnessFns();
    if (pBKSSetAutoBrightness) pBKSSetAutoBrightness(selected);
    CFPreferencesSetAppValue(CFSTR("BKEnableALS"), selected ? kCFBooleanTrue : kCFBooleanFalse, CFSTR("com.apple.BackBoard"));
    CFPreferencesAppSynchronize(CFSTR("com.apple.BackBoard"));
    [super setSelected:selected];
    [self refreshState];
}

@end
