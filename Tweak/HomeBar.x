// 底部白条（Home 指示条）：只隐藏白条本身，上滑手势照常可用
// 白条本体有两种类：
//   MTLumaDodgePillView    会随背景明暗变色的那种
//   MTStaticColorPillView  固定颜色的那种（iOS 17 锁屏上实际显示的是它）
// 容器有两种：
//   主屏幕 / App 里 / 控制中心 / 系统弹窗：SBHomeGrabberView
//   锁屏：CSHomeAffordanceView
#import "XRKCommon.h"

@interface MTLumaDodgePillView : UIView
@end

@interface MTStaticColorPillView : UIView
@end

static Class gGrabberClass, gLockAffordanceClass;
static NSHashTable *gPills;

// 白条类也可能被别处用到，只处理装在上面两种容器里的
static BOOL XRKIsHomeBarPill(UIView *pill) {
    for (UIView *v = pill.superview; v; v = v.superview) {
        if ([v isKindOfClass:gGrabberClass]) return YES;
        if (gLockAffordanceClass && [v isKindOfClass:gLockAffordanceClass]) return YES;
    }
    return NO;
}

static BOOL XRKShouldHidePill(UIView *pill) {
    return XRKOn(kXRKHideHomeBar) && XRKIsHomeBarPill(pill);
}

// setHidden: 的 hook：记下系统想要的值，再决定要不要藏
static BOOL XRKPillHidden(UIView *pill, BOOL hidden) {
    return XRKNoteSystemHidden(pill, hidden) || XRKShouldHidePill(pill);
}

static void XRKPillDidMoveToWindow(UIView *pill) {
    if (!pill.window || !XRKIsHomeBarPill(pill)) return;
    [gPills addObject:pill];
    if (XRKOn(kXRKHideHomeBar)) XRKReapplyHidden(pill);
}

%group XRKHomeBarLuma
%hook MTLumaDodgePillView

- (void)setHidden:(BOOL)hidden {
    %orig(XRKPillHidden(self, hidden));
}

- (void)didMoveToWindow {
    %orig;
    XRKPillDidMoveToWindow(self);
}

%end
%end

%group XRKHomeBarStatic
%hook MTStaticColorPillView

- (void)setHidden:(BOOL)hidden {
    %orig(XRKPillHidden(self, hidden));
}

- (void)didMoveToWindow {
    %orig;
    XRKPillDidMoveToWindow(self);
}

%end
%end

void XRKInitHomeBar(void) {
    gGrabberClass = objc_getClass("SBHomeGrabberView");
    gLockAffordanceClass = objc_getClass("CSHomeAffordanceView");
    BOOL luma = objc_getClass("MTLumaDodgePillView") != nil;
    BOOL statik = objc_getClass("MTStaticColorPillView") != nil;
    XRKDebugLog(@"[HomeBar] grabber=%d lockScreen=%d lumaPill=%d staticPill=%d",
                gGrabberClass != nil, gLockAffordanceClass != nil, luma, statik);
    if (!gGrabberClass || !(luma || statik)) return;

    gPills = [NSHashTable weakObjectsHashTable];
    if (luma) %init(XRKHomeBarLuma);
    if (statik) %init(XRKHomeBarStatic);
    XRKAddRefresher(@[kXRKHideHomeBar], ^{
        for (UIView *pill in gPills.allObjects) XRKReapplyHidden(pill);
    });
}
