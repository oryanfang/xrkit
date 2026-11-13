// 锁屏：隐藏手电筒 / 相机按钮、隐藏「上滑打开」、隐藏右上角控制中心提示条、禁止左滑打开相机（需注销）、
// 充电时显示电量、音乐播放器、禁止下滑搜索、面容识别后直接进主屏幕
//
// 类、方法、成员名都用 iOS 17.3.1 的系统符号核对过（CoverSheet / SpringBoard），关键调用关系看过反汇编：
// - 底部两个按钮：CSQuickActionsView -_addOrRemoveCameraButtonIfNecessary / -_addOrRemoveFlashlightButtonIfNecessary
//   只问 delegate（CSQuickActionsViewController）的 -hasCamera / -hasFlashlight，整个 CoverSheet 里没别处用这两个方法。
//   -refreshSupportedButtons 会把这两个都重跑一遍，所以开关即时生效。
// - 左滑相机：CSCoverSheetViewController -_eligiblePageViewControllers 按每个页面类的
//   +isAvailableForConfiguration 决定要不要这一页；相机页是 SBDashBoardCameraPageViewController。
#import "XRKCommon.h"

static void XRKInitLockScreenExtras(void);

@interface CSQuickActionsView : UIView
- (void)refreshSupportedButtons;
@end

@interface CSQuickActionsViewController : UIViewController
- (CSQuickActionsView *)quickActionsViewIfLoaded;
@end

@interface CSTeachableMomentsContainerView : UIView
@end

@interface CSFixedFooterView : UIView
@end

static NSHashTable *gQuickActionControllers, *gLockViews;

#pragma mark - 底部手电筒 / 相机按钮

%group XRKQuickActions
%hook CSQuickActionsViewController

- (BOOL)hasFlashlight {
    XRKTrack(gQuickActionControllers, self);
    return XRKOn(kXRKLSHideFlashlight) ? NO : %orig;
}

- (BOOL)hasCamera {
    XRKTrack(gQuickActionControllers, self);
    return XRKOn(kXRKLSHideCamera) ? NO : %orig;
}

%end
%end

#pragma mark - 「上滑打开」文字、右上角控制中心提示条

static void XRKApplyTeachable(UIView *container) {
    XRKSetHiddenByUs(XRKViewIvar(container, @"_callToActionLabelContainerView"), XRKOn(kXRKLSHideCallToAction));
    BOOL hideGrabber = XRKOn(kXRKLSHideCCGrabber);
    XRKSetHiddenByUs(XRKViewIvar(container, @"_controlCenterGrabberContainerView"), hideGrabber);
    XRKSetHiddenByUs(XRKViewIvar(container, @"_controlCenterGlyphContainerView"), hideGrabber);
}

static void XRKApplyFooter(UIView *footer) {
    BOOL hide = XRKOn(kXRKLSHideCallToAction);
    XRKSetHiddenByUs(XRKViewIvar(footer, @"_callToActionLabel"), hide);
    XRKSetHiddenByUs(XRKViewIvar(footer, @"_alternateCallToActionLabel"), hide);
}

%group XRKLockTexts
%hook CSTeachableMomentsContainerView

- (void)layoutSubviews {
    %orig;
    XRKTrack(gLockViews, self);
    XRKApplyTeachable(self);
}

%end

%hook CSFixedFooterView

- (void)layoutSubviews {
    %orig;
    XRKTrack(gLockViews, self);
    XRKApplyFooter(self);
}

%end
%end

#pragma mark - 禁止左滑打开相机（需注销）

%group XRKCameraPage
%hook SBDashBoardCameraPageViewController

+ (BOOL)isAvailableForConfiguration {
    return XRKOn(kXRKLSDisableCameraSwipe) ? NO : %orig;
}

%end
%end

#pragma mark - 初始化

void XRKInitLockScreen(void) {
    BOOL quickOK = XRKResponds("CSQuickActionsViewController", @[@"hasCamera", @"hasFlashlight", @"quickActionsViewIfLoaded"]) &&
                   XRKResponds("CSQuickActionsView", @[@"refreshSupportedButtons"]);
    BOOL textsOK = objc_getClass("CSTeachableMomentsContainerView") && objc_getClass("CSFixedFooterView");
    BOOL cameraOK = XRKClassResponds("SBDashBoardCameraPageViewController", @[@"isAvailableForConfiguration"]);
    XRKDebugLog(@"[LockScreen] quickActions=%d texts=%d cameraPage=%d", quickOK, textsOK, cameraOK);

    if (quickOK) {
        gQuickActionControllers = [NSHashTable weakObjectsHashTable];
        %init(XRKQuickActions);
        XRKAddRefresher(@[kXRKLSHideFlashlight, kXRKLSHideCamera], ^{
            for (CSQuickActionsViewController *vc in gQuickActionControllers.allObjects) {
                CSQuickActionsView *v = [vc quickActionsViewIfLoaded];
                [v refreshSupportedButtons];
                [v setNeedsLayout];
            }
        });
    }
    if (textsOK) {
        gLockViews = [NSHashTable weakObjectsHashTable];
        %init(XRKLockTexts);
        XRKAddRefresher(@[kXRKLSHideCallToAction, kXRKLSHideCCGrabber], ^{
            for (UIView *v in gLockViews.allObjects) {
                if ([v isKindOfClass:XRKClass("CSFixedFooterView")]) XRKApplyFooter(v);
                else XRKApplyTeachable(v);
            }
        });
    }
    if (cameraOK) %init(XRKCameraPage);
    XRKInitLockScreenExtras();
}

// ======================================================================
// 第二批：面容识别后直接进主屏幕、充电时显示电量、音乐播放器、下滑搜索
// 同样用 iOS 17.3.1 的符号 + 反汇编核对过（SpringBoard / CoverSheet）
// ======================================================================

@interface SBLockScreenManager : NSObject
+ (instancetype)sharedInstance;
- (BOOL)isUILocked;
- (BOOL)isLockScreenVisible;
- (id)_userAuthController;
- (id)coverSheetViewController;
- (void)lockScreenViewControllerRequestsUnlock;
@end

@interface CSCoverSheetViewController : UIViewController
- (BOOL)isMainPageVisible;
- (BOOL)hasVisibleContentToReveal;
@end

@interface SBBacklightController : NSObject
+ (instancetype)sharedInstance;
- (BOOL)screenIsOn;
@end

@interface SBLockScreenNowPlayingController : NSObject
- (void)_updateNowPlayingPlugin;
@end

@interface CSMainPageView : UIView
@end

#pragma mark - 面容识别后直接进主屏幕
// SBLockScreenManager -_authenticationStateChanged: 是"认证状态变了"的通知回调（面容 ID 成功、输密码都会走），
// 认证成功后系统停在锁屏等你上滑；我们在这之后补一个"上滑"：-lockScreenViewControllerRequestsUnlock
// （就是上滑解锁调的那个，里面是 -unlockUIFromSource:withOptions:）。
// 不自动进入的情况：屏幕没亮、不在锁屏主页（左滑到了小组件页等）、待机显示（StandBy）、
// 以及打开「有通知时停在锁屏」并且锁屏上有通知 / 音乐（-hasVisibleContentToReveal）。

static BOOL XRKAmbientPresented(void) {
    id scene = XRKSafeCall(XRKSafeCall(UIApplication.sharedApplication, @"windowSceneManager"), @"activeDisplayWindowScene");
    return XRKSafeBool(XRKSafeCall(scene, @"ambientPresentationController"), @"isPresented", NO);
}

static void XRKTryAutoUnlock(SBLockScreenManager *lsm) {
    if (!XRKOn(kXRKLSAutoUnlock)) return;
    if (![lsm isUILocked] || ![lsm isLockScreenVisible]) return;
    if (!XRKSafeBool([lsm _userAuthController], @"isAuthenticated", NO)) return;
    if (!XRKSafeBool([XRKClass("SBBacklightController") sharedInstance], @"screenIsOn", NO)) return;
    if (XRKAmbientPresented()) return;
    CSCoverSheetViewController *cs = [lsm coverSheetViewController];
    if (!XRKSafeBool(cs, @"isMainPageVisible", NO)) return;
    BOOL stay = [[XRKPrefs shared] boolForKey:kXRKLSAutoUnlockStay fallback:YES];
    if (stay && XRKSafeBool(cs, @"hasVisibleContentToReveal", NO)) return;
    XRKDebugLog(@"[LockScreen] auto unlock");
    [lsm lockScreenViewControllerRequestsUnlock];
}

%group XRKAutoUnlock
%hook SBLockScreenManager

- (void)_authenticationStateChanged:(id)notification {
    %orig;
    if (!XRKOn(kXRKLSAutoUnlock)) return;
    // 推迟到这一轮跑完：系统自己在这个回调里还要更新锁屏状态。
    // 多任务「iPad」样式时，iPad 网格界面也在处理认证变化，立刻插进去解锁会让主队列坏掉、主线程空转
    // （2026-11-11 三次卡死前都刚好触发了自动解锁）→ 这时改用 RunLoop 定时器、晚 0.35 秒（不走 GCD 主队列），之后没再卡过
    if (XRKSwitcherStyleSetting() == XRKSwitcherStyleiPad) {
        SBLockScreenManager *lsm = self;
        CFRunLoopTimerRef timer = CFRunLoopTimerCreateWithHandler(kCFAllocatorDefault, CFAbsoluteTimeGetCurrent() + 0.35, 0, 0, 0,
                                                                  ^(CFRunLoopTimerRef t) { XRKTryAutoUnlock(lsm); });
        CFRunLoopAddTimer(CFRunLoopGetMain(), timer, kCFRunLoopCommonModes);
        CFRelease(timer);
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{ XRKTryAutoUnlock(self); });
}

%end
%end

#pragma mark - 充电时显示电量
// 锁屏主页（CSMainPageView）底部正中、两个快捷按钮之间放一个"⚡ 85%"，只在充电 / 已充满且插着电时显示

static NSHashTable *gMainPages;
static const void *kXRKChargeLabelKey = &kXRKChargeLabelKey;

static void XRKUpdateChargeLabel(UIView *page) {
    UILabel *label = objc_getAssociatedObject(page, kXRKChargeLabelKey);
    BOOL want = XRKOn(kXRKLSChargePercent);
    if (!want) {
        label.hidden = YES;
        return;
    }
    UIDevice *device = UIDevice.currentDevice;
    if (!device.batteryMonitoringEnabled) device.batteryMonitoringEnabled = YES;
    UIDeviceBatteryState state = device.batteryState;
    BOOL plugged = state == UIDeviceBatteryStateCharging || state == UIDeviceBatteryStateFull;
    if (!label) {
        label = [UILabel new];
        label.font = [UIFont monospacedDigitSystemFontOfSize:15 weight:UIFontWeightSemibold];
        label.textColor = UIColor.whiteColor;
        label.textAlignment = NSTextAlignmentCenter;
        label.layer.shadowColor = UIColor.blackColor.CGColor;
        label.layer.shadowOpacity = 0.35;
        label.layer.shadowRadius = 3;
        label.layer.shadowOffset = CGSizeZero;
        label.userInteractionEnabled = NO;
        [page addSubview:label];
        objc_setAssociatedObject(page, kXRKChargeLabelKey, label, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    label.hidden = !plugged;
    if (!plugged) return;
    int percent = (int)lroundf(MAX(0, device.batteryLevel) * 100);
    label.text = [NSString stringWithFormat:@"⚡︎ %d%%", percent];
    [label sizeToFit];
    CGRect b = page.bounds;
    label.center = CGPointMake(CGRectGetMidX(b), CGRectGetMaxY(b) - page.safeAreaInsets.bottom - 60);
    [page bringSubviewToFront:label];
}

%group XRKChargePercent
%hook CSMainPageView

- (void)layoutSubviews {
    %orig;
    XRKTrack(gMainPages, self);
    XRKUpdateChargeLabel(self);
}

%end
%end

#pragma mark - 音乐播放器
// SBLockScreenNowPlayingController -_updateNowPlayingPlugin 算出状态再调 -_updateToState:
//   2 = 正在播放（显示）；1 = 暂停但最近在用（显示，并开一个计时器到时收起）；其余（0）= 不显示
// 「暂停后收起」把 1 改成 0；「完全隐藏」一律 0

static NSHashTable *gNowPlayingControllers;

%group XRKNowPlaying
%hook SBLockScreenNowPlayingController

- (void)_updateToState:(long long)state {
    XRKTrack(gNowPlayingControllers, self);
    long long mode = (long long)XRKDouble(kXRKLSNowPlaying, 0, 0, 2);
    if (mode == 2 || (mode == 1 && state == 1)) state = 0;
    %orig(state);
}

%end
%end

#pragma mark - 下滑搜索
// 锁屏（以及下拉出来的通知中心）中间往下拉出的 Spotlight 搜索：手势本身 + 通知列表里"往下拉到头就搜索"

%group XRKLockSearch
%hook CSCoverSheetViewController

- (BOOL)searchGestureShouldRecognize:(id)gesture {
    return XRKOn(kXRKLSDisableSearch) ? NO : %orig;
}

- (BOOL)spotlightPresenterAllowsPullToSearch:(id)presenter {
    return XRKOn(kXRKLSDisableSearch) ? NO : %orig;
}

%end
%end

static void XRKInitLockScreenExtras(void) {
    BOOL autoOK = XRKResponds("SBLockScreenManager", @[@"_authenticationStateChanged:", @"isUILocked", @"isLockScreenVisible",
                                                      @"_userAuthController", @"coverSheetViewController",
                                                      @"lockScreenViewControllerRequestsUnlock"]);
    BOOL chargeOK = objc_getClass("CSMainPageView") != nil;
    BOOL nowPlayingOK = XRKResponds("SBLockScreenNowPlayingController", @[@"_updateToState:", @"_updateNowPlayingPlugin"]);
    BOOL searchOK = XRKResponds("CSCoverSheetViewController", @[@"searchGestureShouldRecognize:", @"spotlightPresenterAllowsPullToSearch:"]);
    XRKDebugLog(@"[LockScreen] autoUnlock=%d charge=%d nowPlaying=%d search=%d", autoOK, chargeOK, nowPlayingOK, searchOK);

    if (autoOK) %init(XRKAutoUnlock);
    if (chargeOK) {
        gMainPages = [NSHashTable weakObjectsHashTable];
        %init(XRKChargePercent);
        void (^refresh)(void) = ^{
            for (UIView *v in gMainPages.allObjects) XRKUpdateChargeLabel(v);
        };
        XRKAddRefresher(@[kXRKLSChargePercent], refresh);
        for (NSNotificationName name in @[UIDeviceBatteryStateDidChangeNotification, UIDeviceBatteryLevelDidChangeNotification]) {
            [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:NSOperationQueue.mainQueue
                                                        usingBlock:^(NSNotification *n) { refresh(); }];
        }
    }
    if (nowPlayingOK) {
        gNowPlayingControllers = [NSHashTable weakObjectsHashTable];
        %init(XRKNowPlaying);
        XRKAddRefresher(@[kXRKLSNowPlaying], ^{
            for (SBLockScreenNowPlayingController *c in gNowPlayingControllers.allObjects) [c _updateNowPlayingPlugin];
        });
    }
    if (searchOK) %init(XRKLockSearch);
}
