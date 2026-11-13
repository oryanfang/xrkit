// 图标透明度：静止时半透明，手指碰到主屏幕任何位置恢复 100%，抬手后静止一段时间再淡回
//
// 做法：hook 图标列表 SBIconListView（主屏幕每一页 + Dock 都是它的子类）的 alpha。
// 系统设的 alpha 原样记下来，实际显示的是"系统值 × 我们的系数"，getter 返回系统值，
// 所以 SpringBoard 自己的动画逻辑不受影响。
#import "XRKCommon.h"

@interface SBIconListView : UIView
@end

@interface SBHomeScreenWindow : UIWindow
@end

static const void *kXRKSystemAlphaKey = &kXRKSystemAlphaKey;
static NSHashTable *gIconLists;
static BOOL gTouching = NO;        // 有手指在屏幕上
static BOOL gAwake = NO;           // "唤醒"状态：触摸中，或抬手后还没到延迟时间
static NSUInteger gFadeToken = 0;  // 每次触摸变化 +1，用来作废还没执行的淡出

static CGFloat XRKIdleFactor(void) {
    if (gAwake || !XRKOn(kXRKIdleFade)) return 1;
    return XRKDouble(kXRKIdleFadeAlpha, 0.4, 0.05, 1.0);
}

// setAlpha: 被 hook 了，用系统值重设一次就会按当前系数生效
static void XRKApplyIdleFadeAll(NSTimeInterval duration) {
    void (^apply)(void) = ^{
        for (UIView *v in gIconLists.allObjects) [v setAlpha:v.alpha];
    };
    if (duration <= 0) {
        apply();
        return;
    }
    [UIView animateWithDuration:duration delay:0
                        options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                     animations:apply completion:nil];
}

// 打开的文件夹里的图标列表也是 SBIconListView，打开的文件夹要看清楚，所以排除：
// 往上找有没有 SBFloatyFolderView（打开的文件夹）。列表不会在文件夹和主屏幕之间挪，进了窗口后算一次缓存起来
static const void *kXRKInFolderKey = &kXRKInFolderKey;

static BOOL XRKListInFolder(UIView *list) {
    NSNumber *cached = objc_getAssociatedObject(list, kXRKInFolderKey);
    if (cached) return cached.boolValue;
    if (!list.window) return NO;
    BOOL inFolder = NO;
    static Class folderClass;
    if (!folderClass) folderClass = objc_getClass("SBFloatyFolderView");
    for (UIView *v = list.superview; v && folderClass; v = v.superview) {
        if ([v isKindOfClass:folderClass]) {
            inFolder = YES;
            break;
        }
    }
    objc_setAssociatedObject(list, kXRKInFolderKey, @(inFolder), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return inFolder;
}

%group XRKIdleFade
%hook SBIconListView

- (void)setAlpha:(CGFloat)alpha {
    if (XRKListInFolder(self)) {
        // 文件夹里的不处理；之前（还没进窗口时）被我们改过的话，清掉记录、恢复系统值
        if (objc_getAssociatedObject(self, kXRKSystemAlphaKey)) {
            objc_setAssociatedObject(self, kXRKSystemAlphaKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        %orig;
        return;
    }
    CGFloat factor = XRKIdleFactor();
    // 功能没用过（没存过系统值、系数为 1）就原样放行，不额外存值
    if (factor == 1 && !objc_getAssociatedObject(self, kXRKSystemAlphaKey)) {
        %orig;
        return;
    }
    objc_setAssociatedObject(self, kXRKSystemAlphaKey, @(alpha), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    %orig(alpha * factor);
}

- (CGFloat)alpha {
    NSNumber *system = objc_getAssociatedObject(self, kXRKSystemAlphaKey);
    return system ? system.doubleValue : %orig;
}

- (void)didMoveToWindow {
    %orig;
    XRKTrack(gIconLists, self);
    [self setAlpha:self.alpha];
}

%end

%hook SBHomeScreenWindow

- (void)sendEvent:(UIEvent *)event {
    %orig;
    if (event.type != UIEventTypeTouches || !XRKOn(kXRKIdleFade)) return;

    BOOL touching = NO;
    for (UITouch *t in event.allTouches) {
        if (t.phase != UITouchPhaseEnded && t.phase != UITouchPhaseCancelled) {
            touching = YES;
            break;
        }
    }
    if (touching == gTouching) return;
    gTouching = touching;

    NSUInteger token = ++gFadeToken;
    if (touching) {
        if (!gAwake) {
            gAwake = YES;
            XRKApplyIdleFadeAll(0.15);
        }
        return;
    }
    // 抬手后静止一段时间再慢慢淡回去；期间再碰屏幕就作废
    double delay = XRKDouble(kXRKIdleFadeDelay, 3.0, 0.5, 30.0);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (token != gFadeToken || gTouching) return;
        gAwake = NO;
        XRKApplyIdleFadeAll(0.6);
    });
}

%end
%end

void XRKInitIdleFade(void) {
    BOOL ok = objc_getClass("SBIconListView") && objc_getClass("SBHomeScreenWindow");
    XRKDebugLog(@"[IdleFade] ok=%d", ok);
    if (!ok) return;

    gIconLists = [NSHashTable weakObjectsHashTable];
    %init(XRKIdleFade);
    XRKAddRefresher(@[kXRKIdleFade, kXRKIdleFadeAlpha], ^{
        gFadeToken++;
        gAwake = NO;
        XRKApplyIdleFadeAll(0.25);
    });
}
