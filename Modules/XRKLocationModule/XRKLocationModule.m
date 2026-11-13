// xrkit 定位：一点开关定位服务。CoreLocation 的类方法 +[CLLocationManager locationServicesEnabled] /
// +setLocationServicesEnabled:（私有，SpringBoard 里能调；选择器在 iOS 17.3.1 的 CoreLocation 里核对过）
#import "../XRKModule.h"
#import <dlfcn.h>

@interface XRKLocationModule : CCUIToggleModule
@end

static Class XRKLocationManagerClass(void) {
    static Class cls;
    if (!cls) {
        dlopen("/System/Library/Frameworks/CoreLocation.framework/CoreLocation", RTLD_NOW);
        cls = objc_getClass("CLLocationManager");
    }
    return cls;
}

@implementation XRKLocationModule

- (UIImage *)iconGlyph { return XRKGlyph(@"location"); }
- (UIImage *)selectedIconGlyph { return XRKGlyph(@"location.fill"); }
- (UIColor *)selectedColor { return UIColor.systemBlueColor; }

- (BOOL)isSelected {
    Class cls = XRKLocationManagerClass();
    if (![cls respondsToSelector:@selector(locationServicesEnabled)]) return NO;
    return ((BOOL (*)(id, SEL))objc_msgSend)(cls, @selector(locationServicesEnabled));
}

// 连续快速开关时，开着的「设置 › 隐私 › 定位服务」页会在重新排版时断言崩溃（系统 PrivacySettingsUI
// -[PUILocationServicesClipsListController specifiers] 的 __assert_rtn，连点五六次后「设置」会闪退）。
// 切换一次后 1.5 秒内再点不处理，等系统处理完。
static CFAbsoluteTime gLastLocationToggle;

- (void)setSelected:(BOOL)selected {
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (now - gLastLocationToggle < 1.5) {
        [self refreshState];   // 按真实状态把按钮恢复回去
        return;
    }
    gLastLocationToggle = now;
    Class cls = XRKLocationManagerClass();
    SEL sel = NSSelectorFromString(@"setLocationServicesEnabled:");
    if ([cls respondsToSelector:sel]) ((void (*)(id, SEL, BOOL))objc_msgSend)(cls, sel, selected);
    [super setSelected:selected];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [self refreshState]; });
}

@end
