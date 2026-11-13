// xrkit 个人热点：一点开关「允许其他人加入」，和系统控制中心网络模块里的热点按钮同一套：
// WiFiKit 的 WFPersonalHotspotStateMonitor -asyncMISDiscoveryState:(^(BOOL)) / -setMISDiscoveryState:immediateDisable:
//（ConnectivityModule 导入的就是它；回调参数是 BOOL，反汇编核对过）
#import "../XRKModule.h"
#import <dlfcn.h>

@interface XRKHotspotModule : CCUIToggleModule
@end

static id XRKHotspotMonitor(void) {
    static id monitor;
    if (!monitor) {
        dlopen("/System/Library/PrivateFrameworks/WiFiKit.framework/WiFiKit", RTLD_NOW);
        monitor = [objc_getClass("WFPersonalHotspotStateMonitor") new];
    }
    return monitor;
}

static BOOL gHotspotOn;

@implementation XRKHotspotModule

- (UIImage *)iconGlyph { return XRKGlyph(@"personalhotspot"); }
- (UIColor *)selectedColor { return UIColor.systemGreenColor; }

- (BOOL)isSelected {
    // 状态是异步拿的：先返回上次的值，拿到后再刷新
    id m = XRKHotspotMonitor();
    if ([m respondsToSelector:@selector(asyncMISDiscoveryState:)]) {
        __weak typeof(self) weakSelf = self;
        void (^handler)(BOOL) = ^(BOOL on) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (on == gHotspotOn) return;
                gHotspotOn = on;
                [weakSelf refreshState];
            });
        };
        ((void (*)(id, SEL, id))objc_msgSend)(m, @selector(asyncMISDiscoveryState:), handler);
    }
    return gHotspotOn;
}

- (void)setSelected:(BOOL)selected {
    id m = XRKHotspotMonitor();
    if ([m respondsToSelector:@selector(setMISDiscoveryState:immediateDisable:)]) {
        ((void (*)(id, SEL, BOOL, BOOL))objc_msgSend)(m, @selector(setMISDiscoveryState:immediateDisable:), selected, !selected);
        gHotspotOn = selected;
    }
    [super setSelected:selected];
}

@end
