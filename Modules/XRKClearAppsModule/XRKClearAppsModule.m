// xrkit 清除后台：关掉多任务里所有 App（跳过 xrkit 里锁定的）。和多任务「往下拉清除全部」同一套：
// SBMainSwitcherControllerCoordinator -recentAppLayouts → 每个 displayItem -deleteAppLayoutForDisplayItem:
#import "../XRKModule.h"
#import "../../Shared/XRKKeys.h"
#import "../../Shared/XRKPrefs.h"

@interface XRKClearAppsModule : CCUIToggleModule
@end

@implementation XRKClearAppsModule

- (UIImage *)iconGlyph { return XRKGlyph(@"xmark.app"); }
- (UIColor *)selectedColor { return UIColor.systemRedColor; }
- (BOOL)isSelected { return NO; }

- (void)setSelected:(BOOL)selected {
    XRKHaptic();
    id coord = XRKShared("SBMainSwitcherControllerCoordinator");
    if (![coord respondsToSelector:@selector(recentAppLayouts)] || ![coord respondsToSelector:@selector(deleteAppLayoutForDisplayItem:)]) return;

    NSArray *locked = @[];
    CFPropertyListRef v = CFPreferencesCopyAppValue((__bridge CFStringRef)kXRKSwLockedApps, (__bridge CFStringRef)XRK_PREFS_DOMAIN);
    if (v) {
        if (CFGetTypeID(v) == CFArrayGetTypeID()) locked = (__bridge NSArray *)v;
        locked = [locked copy];
        CFRelease(v);
    }
    CFPropertyListRef lockOn = CFPreferencesCopyAppValue((__bridge CFStringRef)kXRKSwLockApps, (__bridge CFStringRef)XRK_PREFS_DOMAIN);
    BOOL lockEnabled = lockOn && CFGetTypeID(lockOn) == CFBooleanGetTypeID() && CFBooleanGetValue(lockOn);
    if (lockOn) CFRelease(lockOn);

    NSArray *layouts = [[coord valueForKey:@"recentAppLayouts"] copy];
    for (id layout in layouts) {
        NSArray *items = [layout respondsToSelector:@selector(allItems)] ? [layout valueForKey:@"allItems"] : @[];
        id first = items.firstObject;
        NSString *bid = [first respondsToSelector:@selector(bundleIdentifier)] ? [first valueForKey:@"bundleIdentifier"] : nil;
        if (lockEnabled && bid && [locked containsObject:bid]) continue;
        for (id item in [items copy]) ((void (*)(id, SEL, id))objc_msgSend)(coord, @selector(deleteAppLayoutForDisplayItem:), item);
    }
}

@end
