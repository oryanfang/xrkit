// 控制中心：背景透明度、模块背景透明度、隐藏控制中心里的状态栏、亮度/音量显示百分比、模块圆角
//
// - 背景：CCUIModularControlCenterOverlayViewController -overlayBackgroundView（整屏模糊背景）。
//   呼出动画改的是模糊"权重"不是 alpha，所以 alpha 留给我们用，在排版时设一次即可。
// - 模块背景：每个模块的底板是 CCUIContentModuleContentContainerView 的 _moduleMaterialView。
//   有些模块自己画底板（_moduleProvidesOwnPlatter），不受影响。
// - 状态栏：顶部区域 CCUIHeaderPocketView 用 -setStatusBarAlpha: 控制状态栏淡入淡出，拦住改成 0。
// - 亮度 / 音量百分比、模块圆角：见下面。
// 控制中心每次打开都会重新走一遍，所以改完设置最晚下次打开生效。
// 类、方法、成员名已用 iOS 17.3.1 的系统符号核对过（ControlCenterUI）。
#import "XRKCommon.h"

@interface CCUIModularControlCenterOverlayViewController : UIViewController
- (UIView *)overlayBackgroundView;
@end

@interface CCUIContentModuleContentContainerView : UIView
@end

@interface CCUIHeaderPocketView : UIView
- (double)statusBarAlpha;
- (void)setStatusBarAlpha:(double)alpha;
@end

static NSHashTable *gModuleContainers, *gHeaderPockets;

static CGFloat XRKCCBackgroundAlpha(void) {
    return XRKDouble(kXRKCCBackgroundAlpha, 1.0, 0.0, 1.0);
}

static CGFloat XRKCCModuleAlpha(void) {
    return XRKDouble(kXRKCCModuleAlpha, 1.0, 0.0, 1.0);
}

// 模块圆角：系统设圆角时乘上系数（100% = 系统）。在设圆角的那一刻改，所以下次打开控制中心生效
static CGFloat XRKCCCornerFactor(void) {
    return XRKDouble(kXRKCCCornerScale, 1.0, 0.0, 1.5);
}

static void XRKApplyModuleAlpha(UIView *container) {
    UIView *material = XRKViewIvar(container, @"_moduleMaterialView");
    if (material) material.alpha = XRKCCModuleAlpha();
}

%group XRKCCBackground
%hook CCUIModularControlCenterOverlayViewController

- (void)viewDidLayoutSubviews {
    %orig;
    UIView *bg = [self overlayBackgroundView];
    CGFloat a = XRKCCBackgroundAlpha();
    if (bg && bg.alpha != a) bg.alpha = a;
}

%end
%end

%group XRKCCModules
%hook CCUIContentModuleContentContainerView

- (void)_setContinuousCornerRadius:(double)radius ignoreSubviewClipping:(BOOL)ignore {
    %orig(radius * XRKCCCornerFactor(), ignore);
}

- (void)_configureModuleMaterialViewIfNecessary {
    %orig;
    XRKTrack(gModuleContainers, self);
    XRKApplyModuleAlpha(self);
}

- (void)layoutSubviews {
    %orig;
    XRKTrack(gModuleContainers, self);
    XRKApplyModuleAlpha(self);
}

%end
%end

%group XRKCCStatusBar
%hook CCUIHeaderPocketView

- (void)setStatusBarAlpha:(double)alpha {
    XRKTrack(gHeaderPockets, self);
    %orig(XRKOn(kXRKCCHideStatusBar) ? 0 : alpha);
}

%end
%end

#pragma mark - 亮度 / 音量显示百分比、滑块圆角
// 亮度、音量都是 CCUIBaseSliderView（ControlCenterUIKit）。在滑块顶部正中放一个百分比，
// 值改变（-setValue: / -setValue:animated:）、拖动中（-_handleFluidSliderInteractionUpdate:，读 presentationValue）和排版时更新；
// 顶部被白色填充盖住时字变深色。只给亮度 / 音量模块（手电筒不要）。

@interface CCUIBaseSliderView : UIControl
- (float)value;
- (float)presentationValue;
@end

static const void *kXRKSliderLabelKey = &kXRKSliderLabelKey;
static NSHashTable *gSliders;

// 只给亮度、音量显示（手电筒展开后也是 CCUIBaseSliderView，那里显示百分比没意义）：顺着父视图找所在模块的 moduleIdentifier
static const void *kXRKSliderModuleKey = &kXRKSliderModuleKey;

static BOOL XRKSliderWantsPercent(UIView *slider) {
    NSNumber *cached = objc_getAssociatedObject(slider, kXRKSliderModuleKey);
    if (cached) return cached.boolValue;
    NSString *moduleID = nil;
    for (UIView *v = slider.superview; v; v = v.superview) {
        if ([v respondsToSelector:@selector(moduleIdentifier)]) {
            id mid = [v valueForKey:@"moduleIdentifier"];
            if ([mid isKindOfClass:[NSString class]]) { moduleID = mid; break; }
        }
    }
    if (!moduleID) return NO;   // 还没放进模块容器，先不显示也不缓存
    BOOL want = [moduleID isEqualToString:@"com.apple.control-center.DisplayModule"] ||
                [moduleID isEqualToString:@"com.apple.mediaremote.controlcenter.audio"];
    objc_setAssociatedObject(slider, kXRKSliderModuleKey, @(want), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return want;
}

static void XRKUpdateSliderLabel(CCUIBaseSliderView *slider) {
    UILabel *label = objc_getAssociatedObject(slider, kXRKSliderLabelKey);
    if (!XRKOn(kXRKCCSliderPercent) || !XRKSliderWantsPercent(slider)) {
        label.hidden = YES;
        return;
    }
    CGRect b = slider.bounds;
    if (b.size.height < 40 || b.size.height < b.size.width) {   // 只处理竖着的滑块（控制中心里的亮度、音量）
        label.hidden = YES;
        return;
    }
    if (!label) {
        label = [UILabel new];
        label.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightSemibold];
        label.textAlignment = NSTextAlignmentCenter;
        label.userInteractionEnabled = NO;
        [slider addSubview:label];
        objc_setAssociatedObject(slider, kXRKSliderLabelKey, label, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    // 拖动中用 presentationValue（界面上正在显示的值），否则用 value
    float raw = [slider respondsToSelector:@selector(presentationValue)] ? [slider presentationValue] : [slider value];
    float value = MAX(0.f, MIN(1.f, raw));
    label.hidden = NO;
    label.text = [NSString stringWithFormat:@"%d%%", (int)lroundf(value * 100)];
    [label sizeToFit];
    CGFloat top = 14;
    label.center = CGPointMake(CGRectGetMidX(b), top + label.bounds.size.height / 2);
    // 白色填充从底部往上长：盖到文字位置就用深色字
    BOOL covered = value * b.size.height >= b.size.height - (top + label.bounds.size.height / 2);
    label.textColor = covered ? [UIColor colorWithWhite:0.15 alpha:0.9] : [UIColor colorWithWhite:1 alpha:0.9];
    [slider bringSubviewToFront:label];
}

%group XRKCCSliderPercent
%hook CCUIBaseSliderView

- (void)setValue:(float)value {
    %orig;
    XRKUpdateSliderLabel(self);
}

- (void)setValue:(float)value animated:(BOOL)animated {
    %orig;
    XRKUpdateSliderLabel(self);
}

- (void)layoutSubviews {
    %orig;
    XRKTrack(gSliders, self);
    XRKUpdateSliderLabel(self);
}

// 手指拖动过程中系统走这里（不调 -setValue:），在这里刷新数字才是实时的
- (void)_handleFluidSliderInteractionUpdate:(id)update {
    %orig;
    XRKUpdateSliderLabel(self);
}

%end
%end

%group XRKCCCorners
%hook CCUIBaseSliderView

- (void)setContinuousSliderCornerRadius:(double)radius {
    %orig(radius * XRKCCCornerFactor());
}

%end
%end

void XRKInitControlCenter(void) {
    BOOL bgOK = XRKResponds("CCUIModularControlCenterOverlayViewController", @[@"overlayBackgroundView", @"viewDidLayoutSubviews"]);
    BOOL modulesOK = XRKResponds("CCUIContentModuleContentContainerView", @[@"_configureModuleMaterialViewIfNecessary",
                                                                           @"_setContinuousCornerRadius:ignoreSubviewClipping:"]);
    BOOL statusOK = XRKResponds("CCUIHeaderPocketView", @[@"setStatusBarAlpha:", @"statusBarAlpha"]);
    BOOL sliderOK = XRKResponds("CCUIBaseSliderView", @[@"value", @"presentationValue", @"setValue:", @"setValue:animated:",
                                                       @"setContinuousSliderCornerRadius:", @"_handleFluidSliderInteractionUpdate:"]);
    XRKDebugLog(@"[ControlCenter] background=%d modules=%d statusBar=%d slider=%d", bgOK, modulesOK, statusOK, sliderOK);

    if (sliderOK) {
        gSliders = [NSHashTable weakObjectsHashTable];
        %init(XRKCCSliderPercent);
        %init(XRKCCCorners);
        XRKAddRefresher(@[kXRKCCSliderPercent], ^{
            for (CCUIBaseSliderView *v in gSliders.allObjects) XRKUpdateSliderLabel(v);
        });
    }
    if (bgOK) %init(XRKCCBackground);
    if (modulesOK) {
        gModuleContainers = [NSHashTable weakObjectsHashTable];
        %init(XRKCCModules);
        XRKAddRefresher(@[kXRKCCModuleAlpha], ^{
            for (UIView *v in gModuleContainers.allObjects) XRKApplyModuleAlpha(v);
        });
    }
    if (statusOK) {
        gHeaderPockets = [NSHashTable weakObjectsHashTable];
        %init(XRKCCStatusBar);
        // 打开隐藏时立刻藏；关闭时等控制中心下次呼出，系统自己会把 alpha 设回来
        XRKAddRefresher(@[kXRKCCHideStatusBar], ^{
            if (!XRKOn(kXRKCCHideStatusBar)) return;
            for (CCUIHeaderPocketView *v in gHeaderPockets.allObjects) [v setStatusBarAlpha:0];
        });
    }
}
