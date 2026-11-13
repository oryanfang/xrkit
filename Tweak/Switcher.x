// 多任务（App 切换器）：隐藏卡片上的名称和图标、锁定 App、任意卡片往下拉清除全部、
// 卡片大小 / 圆角 / 间距 / 上下位置、排列样式（系统 / 网格 / iPad）
//
// 都用 iOS 17.3.1 的 SpringBoard 符号 + 反汇编核对过：
// - 排列样式：「网格」只改 SBAppSwitcherSettings -effectiveSwitcherStyle → 2（选布局），界面和手势仍是 iPhone 那套；
//   「iPad」还要换界面类和手势总控，见 GridFull.x。改了要注销。
// - 堆叠：SBDeckSwitcherModifier。卡片大小 = SBAppSwitcherSettings -deckSwitcherPageScale（各处都从这里取）；
//   圆角 -_cardCornerRadiusInSwitcher；位置 -leadingOffsetForIndex:displayItemsCount:scrollProgress:（乘系数调间距）。
// - 网格：SBMixedGridSwitcherModifier -_fullScreenCardScale / -_cardCornerRadiusInSwitcher / -_horizontalSpacing / -_verticalSpacing。
// - 名称和图标：各布局修饰器的 -titleAndIconOpacityForIndex: / -titleOpacityForIndex: 返回 0。
// - 锁定：SBFluidSwitcherViewController -_supportsKillingForAppLayout: 返回 NO，卡片就划不掉。
//   长按卡片切换锁定（长按不会打开 App），卡片上方名称左边显示小锁；锁定列表存在偏好 swLockedApps（Bundle ID 数组）。
// - 清除全部：SBMainSwitcherControllerCoordinator -recentAppLayouts 里每个 App 调 -deleteAppLayoutForDisplayItem:
//   （系统按 Bundle ID 删卡片走的就是它），跳过锁住的；全清空了就收起切换器。
#import "XRKCommon.h"

@interface SBDisplayItem : NSObject
@property (nonatomic, readonly) NSString *bundleIdentifier;
@end

@interface SBAppLayout : NSObject
- (NSArray<SBDisplayItem *> *)allItems;
@end

@interface SBMainSwitcherControllerCoordinator : NSObject
+ (instancetype)sharedInstance;
- (NSArray<SBAppLayout *> *)recentAppLayouts;
- (void)deleteAppLayoutForDisplayItem:(SBDisplayItem *)item;
- (void)dismissMainSwitcherNoninteractivelyAnimated:(BOOL)animated;
@end

@interface SBMixedGridSwitcherModifier : NSObject
- (double)_horizontalSpacing;
@end

@interface SBFluidSwitcherItemContainerHeaderView : UIView
@end

@interface SBFluidSwitcherItemContainer : UIView
- (SBAppLayout *)appLayout;
@end

#if XRK_DEBUG
static double gXRKLastHSpacing, gXRKLastVSpacing;   // 调试截屏时写进日志
#define XRK_NOTE_SPACING(var, v) (var = (v))
#else
#define XRK_NOTE_SPACING(var, v) ((void)0)
#endif
static double gXRKHeaderHeight = 44.33;             // 多任务卡片上方名称栏的高度，名称栏排版时更新

#pragma mark - 系数

// 「iPad」样式下这几个值只在 SpringBoard 启动时读一次：iPad 的网格会缓存卡片尺寸
// （SBMixedGridSwitcherModifier -_cachedFullScreenCardScale、根修饰器 -_setCardSizesWithEvent:），
// 运行中改了值就和缓存对不上，上滑进多任务的过渡停在半路（2026-11-11 改卡片大小后遇到过）。其他样式照常即时生效。
static BOOL gXRKFrozen;
static CGFloat gXRKFrozenScale, gXRKFrozenSpacing, gXRKFrozenYOffset;

// 排列样式改了要注销，所以运行中当它不变
static BOOL XRKPadStyle(void) {
    return XRKSwitcherStyleSetting() == XRKSwitcherStyleiPad;
}

// 「iPad」样式的卡片默认放大到 110.5%（在 iPhone 上用 iPad 网格调出来比较合适的大小），滑块在它上面乘
#define XRK_PAD_CARD_SCALE_BASE 1.105
static CGFloat XRKCardScale(void) {
    if (gXRKFrozen) return gXRKFrozenScale;
    CGFloat base = XRKPadStyle() ? XRK_PAD_CARD_SCALE_BASE : 1.0;
    return base * XRKDouble(kXRKSwCardScale, 1.0, 0.6, 1.3);
}
static CGFloat XRKCardCorner(void)  { return XRKDouble(kXRKSwCardCorner, 1.0, 0.0, 2.0); }
static CGFloat XRKCardSpacing(void) { return gXRKFrozen ? gXRKFrozenSpacing : XRKDouble(kXRKSwCardSpacing, 1.0, 0.5, 2.0); }
// 卡片上下位置：占屏幕高度的比例，负数往上。基准 ≈ 系统原位 -0.1%（调过几轮定下来的默认位置），滑块在它上面加减
#define XRK_CARD_Y_BASE (-0.001)
static CGFloat XRKCardYOffset(void) { return gXRKFrozen ? gXRKFrozenYOffset : XRK_CARD_Y_BASE + XRKDouble(kXRKSwCardYOffset, 0, -0.15, 0.15); }

#pragma mark - 锁定列表

static NSString *XRKLayoutBundleID(SBAppLayout *layout) {
    SBDisplayItem *item = [layout allItems].firstObject;
    return [item respondsToSelector:@selector(bundleIdentifier)] ? item.bundleIdentifier : nil;
}

static NSArray<NSString *> *XRKLockedApps(void) {
    id v = [[XRKPrefs shared] objectForKey:kXRKSwLockedApps];
    return [v isKindOfClass:[NSArray class]] ? v : @[];
}

static BOOL XRKIsLocked(SBAppLayout *layout) {
    NSString *bid = XRKLayoutBundleID(layout);
    return bid && [XRKLockedApps() containsObject:bid];
}

static void XRKSetLocked(NSString *bid, BOOL locked) {
    NSMutableArray *list = [XRKLockedApps() mutableCopy];
    [list removeObject:bid];
    if (locked) [list addObject:bid];
    XRKWritePref(kXRKSwLockedApps, list);
    [[XRKPrefs shared] reload];
}

#pragma mark - 排列样式、大小、圆角、间距

%group XRKSwitcherLayout
%hook SBAppSwitcherSettings

// 「网格」和「iPad」都用网格布局（2）
- (long long)effectiveSwitcherStyle {
    return XRKSwitcherStyleSetting() == XRKSwitcherStyleSystem ? %orig : XRKSwitcherStyleGrid;
}

- (double)deckSwitcherPageScale {
    return %orig * XRKCardScale();
}

// 堆叠样式所有卡片的竖直位置（SBDeckSwitcherModifier -frameForIndex: 用它），上滑手势的过渡
// （SBHomeGestureSwitcherModifier -_inSwitcherCenterYOffsetWhenPresented）也用它，所以动画能对上
- (double)switcherCenterYOffsetPercentOfScreenHeight {
    return %orig + XRKCardYOffset();
}

%end

%hook SBDeckSwitcherModifier

- (double)_cardCornerRadiusInSwitcher {
    return %orig * XRKCardCorner();
}

- (double)leadingOffsetForIndex:(unsigned long long)index displayItemsCount:(unsigned long long)count scrollProgress:(double)progress {
    return %orig * XRKCardSpacing();
}

%end

%hook SBMixedGridSwitcherModifier

- (double)_fullScreenCardScale {
    return %orig * XRKCardScale();
}

- (double)_cardCornerRadiusInSwitcher {
    return %orig * XRKCardCorner();
}

- (double)_horizontalSpacing {
    double v = %orig * XRKCardSpacing();
    XRK_NOTE_SPACING(gXRKLastHSpacing, v);
    return v;
}

- (CGRect)frameForIndex:(unsigned long long)index {
    CGRect f = %orig;
    f.origin.y += XRKCardYOffset() * UIScreen.mainScreen.bounds.size.height;
    return f;
}

- (double)_verticalSpacing {
    double v;
    if (XRKPadStyle()) {
        // iPad 样式：上下对称——上一排卡片底边到下一排名称栏顶部的空白 = 左右两列之间的空白。
        // 卡片到卡片的间距 = 左右间距 + 名称栏高度（实测 44.3pt，随系统字号变化，取名称栏实际高度）
        v = [self _horizontalSpacing] + gXRKHeaderHeight;
    } else {
        v = %orig * XRKCardSpacing();
    }
    XRK_NOTE_SPACING(gXRKLastVSpacing, v);
    return v;
}

%end
%end

#pragma mark - 隐藏卡片上的名称和图标

%group XRKSwitcherTitles
%hook SBDeckSwitcherModifier
- (double)titleAndIconOpacityForIndex:(unsigned long long)index {
    return XRKOn(kXRKSwHideTitles) ? 0 : %orig;
}
- (double)titleOpacityForIndex:(unsigned long long)index {
    return XRKOn(kXRKSwHideTitles) ? 0 : %orig;
}
%end
%hook SBMixedGridSwitcherModifier
- (double)titleAndIconOpacityForIndex:(unsigned long long)index {
    return XRKOn(kXRKSwHideTitles) ? 0 : %orig;
}
%end
%hook SBHomeToDeckSwitcherModifier
- (double)titleAndIconOpacityForIndex:(unsigned long long)index {
    return XRKOn(kXRKSwHideTitles) ? 0 : %orig;
}
%end
%hook SBHomeToGridSwitcherModifier
- (double)titleAndIconOpacityForIndex:(unsigned long long)index {
    return XRKOn(kXRKSwHideTitles) ? 0 : %orig;
}
%end
%end

#pragma mark - 锁定（划不掉）

%group XRKSwitcherLock
%hook SBFluidSwitcherViewController

- (BOOL)_supportsKillingForAppLayout:(SBAppLayout *)layout {
    if (XRKOn(kXRKSwLockApps) && XRKIsLocked(layout)) return NO;
    return %orig;
}

%end
%end

#pragma mark - 卡片手势：长按锁定、往下拉清除全部

static void XRKClearAllApps(void) {
    SBMainSwitcherControllerCoordinator *coord = [XRKClass("SBMainSwitcherControllerCoordinator") sharedInstance];
    BOOL lockOn = XRKOn(kXRKSwLockApps);
    BOOL anyLeft = NO;
    for (SBAppLayout *layout in [[coord recentAppLayouts] copy]) {
        if (lockOn && XRKIsLocked(layout)) {
            anyLeft = YES;
            continue;
        }
        for (SBDisplayItem *item in [[layout allItems] copy]) [coord deleteAppLayoutForDisplayItem:item];
    }
    XRKDebugLog(@"[Switcher] clear all, locked left=%d", anyLeft);
    if (!anyLeft) [coord dismissMainSwitcherNoninteractivelyAnimated:YES];
}

@interface XRKSwitcherGestures : NSObject <UIGestureRecognizerDelegate>
@end

static const void *kXRKGesturesKey = &kXRKGesturesKey;
#if XRK_DEBUG
static NSHashTable *gItemContainers;   // 只给调试截屏写卡片位置用
#endif

// 锁的标记放在卡片上方名称栏里、App 图标的左边（不盖在卡片内容上）。
// 名称栏 SBFluidSwitcherItemContainerHeaderView：-titleItems 是 SBFluidSwitcherSpaceTitleItem（有 -displayItem），
// _itemsToTitleLabels / _itemsToIconImageViews 以 displayItem 为 key。系统排完版后，把锁放在图标左边（不挪系统的东西）。
static NSHashTable *gHeaderViews;
static const void *kXRKHeaderLocksKey = &kXRKHeaderLocksKey;

// 「iPad」样式：名称栏按 iPad 大卡片排（图标离左边 36pt、名字只给 33pt 宽），在 iPhone 的小卡片上名字被截断、
// 图标挤在中间。改成图标贴左、名字紧跟图标并用满剩余宽度（截图 + 位置日志确认过，2026-11-11）
static void XRKCompactHeader(UIView *header) {
    if (!XRKPadStyle()) return;
    UIView *icon = nil;
    NSMutableArray<UIView *> *labels = [NSMutableArray array];
    for (UIView *sub in header.subviews) {
        if (sub.hidden) continue;
        if ([NSStringFromClass(sub.class) containsString:@"IconImageContainer"]) icon = sub;
        else if ([sub isKindOfClass:[UILabel class]]) [labels addObject:sub];
    }
    if (!icon || labels.count != 1) return;   // 分屏的两个 App 等复杂情况交给系统
    UILabel *label = (UILabel *)labels.firstObject;
    CGFloat w = header.bounds.size.width;
    BOOL rtl = header.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
    CGRect fi = icon.frame, fl = label.frame;
    CGFloat gap = 8;
    CGFloat maxLabel = MAX(0, w - fi.size.width - gap);
    fl.size.width = MIN([label sizeThatFits:CGSizeMake(CGFLOAT_MAX, fl.size.height)].width, maxLabel);
    if (rtl) {
        fi.origin.x = w - fi.size.width;
        fl.origin.x = fi.origin.x - gap - fl.size.width;
    } else {
        fi.origin.x = 0;
        fl.origin.x = fi.size.width + gap;
    }
    icon.frame = fi;
    label.frame = fl;
}

static void XRKLayoutHeaderLocks(UIView *header) {
    NSMutableDictionary *locks = objc_getAssociatedObject(header, kXRKHeaderLocksKey);
    for (UIView *v in locks.allValues) v.hidden = YES;
    if (!XRKOn(kXRKSwLockApps)) return;
    NSArray *items = [header respondsToSelector:@selector(titleItems)] ? [header valueForKey:@"titleItems"] : nil;
    NSDictionary *labels = nil;
    @try { labels = [header valueForKey:@"_itemsToTitleLabels"]; } @catch (NSException *e) { return; }
    if (![labels isKindOfClass:[NSDictionary class]]) return;
    for (id titleItem in items) {
        id displayItem = [titleItem respondsToSelector:@selector(displayItem)] ? [titleItem valueForKey:@"displayItem"] : nil;
        NSString *bid = [displayItem respondsToSelector:@selector(bundleIdentifier)] ? [displayItem valueForKey:@"bundleIdentifier"] : nil;
        UIView *label = displayItem ? labels[displayItem] : nil;
        if (!bid || ![label isKindOfClass:[UIView class]] || label.hidden || ![XRKLockedApps() containsObject:bid]) continue;
        if (!locks) {
            locks = [NSMutableDictionary dictionary];
            objc_setAssociatedObject(header, kXRKHeaderLocksKey, locks, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        UIImageView *lock = locks[bid];
        if (!lock) {
            UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:16 weight:UIImageSymbolWeightSemibold];
            lock = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"lock.fill" withConfiguration:cfg]];
            lock.userInteractionEnabled = NO;
            [header addSubview:lock];
            locks[bid] = lock;
        }
        UIColor *color = [label respondsToSelector:@selector(textColor)] ? [label valueForKey:@"textColor"] : nil;
        lock.tintColor = color ?: UIColor.whiteColor;
        lock.alpha = label.alpha;
        lock.hidden = NO;
        // 放在 App 图标左边；没有图标视图时退回到名称左边
        NSDictionary *icons = nil;
        @try { icons = [header valueForKey:@"_itemsToIconImageViews"]; } @catch (NSException *e) {}
        UIView *icon = [icons isKindOfClass:[NSDictionary class]] ? icons[displayItem] : nil;
        UIView *anchor = ([icon isKindOfClass:[UIView class]] && !icon.hidden) ? icon : label;
        CGRect f = anchor.frame;
        CGSize ls = lock.bounds.size;
        CGFloat gap = 5;
        BOOL rtl = header.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
        CGFloat x = rtl ? CGRectGetMaxX(f) + gap + ls.width / 2 : CGRectGetMinX(f) - gap - ls.width / 2;
        lock.center = CGPointMake(x, CGRectGetMidY(f));
    }
}

static void XRKRefreshAllHeaders(void) {
    for (UIView *h in gHeaderViews.allObjects) {
        [h setNeedsLayout];
        [h layoutIfNeeded];
    }
}

// 长按后这张卡片短时间内不响应"点按打开"
static const void *kXRKSuppressTapKey = &kXRKSuppressTapKey;

static BOOL XRKTapSuppressed(UIView *container) {
    NSDate *until = objc_getAssociatedObject(container, kXRKSuppressTapKey);
    return until && [until timeIntervalSinceNow] > 0;
}

// 把卡片上（以及里面几层视图上）系统自己的手势取消掉：禁用再启用会让正在识别的手势进入 cancelled
static void XRKCancelSystemGestures(UIView *view, UIGestureRecognizer *keep, int depth) {
    for (UIGestureRecognizer *g in view.gestureRecognizers) {
        if (g == keep) continue;
        if (objc_getAssociatedObject(g, kXRKSuppressTapKey)) continue;   // 我们自己的
        if (g.enabled) {
            g.enabled = NO;
            g.enabled = YES;
        }
    }
    if (depth <= 0) return;
    for (UIView *sub in view.subviews) XRKCancelSystemGestures(sub, keep, depth - 1);
}

@implementation XRKSwitcherGestures

+ (instancetype)shared {
    static XRKSwitcherGestures *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [XRKSwitcherGestures new]; });
    return instance;
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gr {
    if ([gr isKindOfClass:[UILongPressGestureRecognizer class]]) return XRKOn(kXRKSwLockApps);
    if (![gr isKindOfClass:[UIPanGestureRecognizer class]] || !XRKOn(kXRKSwPullDownClear)) return NO;
    // 只认"明显往下"的拖动：上滑关单个、左右滑翻卡片都不受影响
    CGPoint v = [(UIPanGestureRecognizer *)gr velocityInView:gr.view];
    return v.y > 0 && fabs(v.y) > fabs(v.x) * 1.5;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gr shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    return YES;
}

- (void)longPress:(UILongPressGestureRecognizer *)gr {
    if (gr.state != UIGestureRecognizerStateBegan) return;
    SBFluidSwitcherItemContainer *container = (SBFluidSwitcherItemContainer *)gr.view;
    // 先挡住"松手即打开"：取消系统的点按 / 高亮手势，并在 1 秒内忽略这张卡片的点按
    objc_setAssociatedObject(container, kXRKSuppressTapKey, [NSDate dateWithTimeIntervalSinceNow:1.0], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    XRKCancelSystemGestures(container, gr, 3);
    NSString *bid = XRKLayoutBundleID([container appLayout]);
    if (!bid) return;
    BOOL locked = ![XRKLockedApps() containsObject:bid];
    XRKSetLocked(bid, locked);
    [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium] impactOccurred];
    XRKRefreshAllHeaders();
    XRKDebugLog(@"[Switcher] %@ %@", locked ? @"lock" : @"unlock", bid);
}

- (void)pan:(UIPanGestureRecognizer *)gr {
    if (gr.state != UIGestureRecognizerStateEnded) return;
    CGPoint t = [gr translationInView:gr.view];
    if (t.y < 90) return;
    [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleHeavy] impactOccurred];
    XRKClearAllApps();
}

@end

%group XRKSwitcherGestures
%hook SBFluidSwitcherItemContainer

- (void)layoutSubviews {
    %orig;
#if XRK_DEBUG
    XRKTrack(gItemContainers, self);
#endif
    if (!objc_getAssociatedObject(self, kXRKGesturesKey)) {
        XRKSwitcherGestures *handler = [XRKSwitcherGestures shared];
        UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:handler action:@selector(longPress:)];
        lp.minimumPressDuration = 0.5;
        lp.cancelsTouchesInView = YES;   // 识别成功时给卡片发 touchesCancelled，松手不会当成点按
        objc_setAssociatedObject(lp, kXRKSuppressTapKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        lp.delegate = handler;
        [self addGestureRecognizer:lp];
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:handler action:@selector(pan:)];
        pan.cancelsTouchesInView = NO;
        pan.delegate = handler;
        objc_setAssociatedObject(pan, kXRKSuppressTapKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [self addGestureRecognizer:pan];
        objc_setAssociatedObject(self, kXRKGesturesKey, @[lp, pan], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

- (void)_handlePageViewTap:(id)gesture {
    if (XRKTapSuppressed(self)) return;
    %orig;
}

%end

%hook SBFluidSwitcherItemContainerHeaderView

- (void)layoutSubviews {
    %orig;
    XRKTrack(gHeaderViews, self);
    if (self.bounds.size.height > 10) gXRKHeaderHeight = self.bounds.size.height;
    XRKCompactHeader(self);
    XRKLayoutHeaderLocks(self);
}

%end
%end

#pragma mark - 初始化

void XRKInitSwitcher(void) {
    if (XRKPadStyle()) {
        gXRKFrozenScale = XRKCardScale();
        gXRKFrozenSpacing = XRKCardSpacing();
        gXRKFrozenYOffset = XRKCardYOffset();
        gXRKFrozen = YES;
    }
    BOOL layoutOK = XRKResponds("SBAppSwitcherSettings", @[@"effectiveSwitcherStyle", @"deckSwitcherPageScale", @"switcherCenterYOffsetPercentOfScreenHeight"]) &&
                    XRKResponds("SBDeckSwitcherModifier", @[@"_cardCornerRadiusInSwitcher", @"leadingOffsetForIndex:displayItemsCount:scrollProgress:"]) &&
                    XRKResponds("SBMixedGridSwitcherModifier", @[@"frameForIndex:", @"_fullScreenCardScale", @"_cardCornerRadiusInSwitcher",
                                                                 @"_horizontalSpacing", @"_verticalSpacing"]);
    BOOL titlesOK = XRKResponds("SBDeckSwitcherModifier", @[@"titleAndIconOpacityForIndex:", @"titleOpacityForIndex:"]) &&
                    XRKResponds("SBMixedGridSwitcherModifier", @[@"titleAndIconOpacityForIndex:"]) &&
                    XRKResponds("SBHomeToDeckSwitcherModifier", @[@"titleAndIconOpacityForIndex:"]) &&
                    XRKResponds("SBHomeToGridSwitcherModifier", @[@"titleAndIconOpacityForIndex:"]);
    BOOL lockOK = XRKResponds("SBFluidSwitcherViewController", @[@"_supportsKillingForAppLayout:"]);
    BOOL gesturesOK = XRKResponds("SBFluidSwitcherItemContainer", @[@"appLayout", @"_handlePageViewTap:"]) &&
                      XRKResponds("SBFluidSwitcherItemContainerHeaderView", @[@"titleItems"]) &&
                      XRKResponds("SBMainSwitcherControllerCoordinator", @[@"recentAppLayouts", @"deleteAppLayoutForDisplayItem:",
                                                                           @"dismissMainSwitcherNoninteractivelyAnimated:"]);
    XRKDebugLog(@"[Switcher] layout=%d titles=%d lock=%d gestures=%d", layoutOK, titlesOK, lockOK, gesturesOK);

    if (layoutOK) %init(XRKSwitcherLayout);
    if (titlesOK) %init(XRKSwitcherTitles);
    if (lockOK) %init(XRKSwitcherLock);
    if (gesturesOK) {
#if XRK_DEBUG
        gItemContainers = [NSHashTable weakObjectsHashTable];
#endif
        gHeaderViews = [NSHashTable weakObjectsHashTable];
        %init(XRKSwitcherGestures);
        XRKAddRefresher(@[kXRKSwLockApps], ^{ XRKRefreshAllHeaders(); });
#if XRK_DEBUG
        XRKDebugAddShotDumper(^{
            for (UIView *h in gHeaderViews.allObjects) {
                if (!h.window) continue;
                XRKDebugLog(@"[Shot] header %@ win=%@ super=%@ superWin=%@", NSStringFromClass(h.class),
                            NSStringFromCGRect([h convertRect:h.bounds toView:nil]), NSStringFromClass(h.superview.class),
                            NSStringFromCGRect([h.superview convertRect:h.superview.bounds toView:nil]));
                for (UIView *sub in h.subviews) {
                    NSString *text = [sub respondsToSelector:@selector(text)] ? [sub valueForKey:@"text"] : @"";
                    XRKDebugLog(@"[Shot]    %@ %@ hidden=%d %@", NSStringFromClass(sub.class), NSStringFromCGRect(sub.frame), sub.hidden, text ?: @"");
                }
            }
            SBMainSwitcherControllerCoordinator *coord = [XRKClass("SBMainSwitcherControllerCoordinator") sharedInstance];
            XRKDebugLog(@"[Shot] apps=%lu hSpacing=%.1f vSpacing=%.1f screen=%@", (unsigned long)[coord recentAppLayouts].count,
                        gXRKLastHSpacing, gXRKLastVSpacing, NSStringFromCGRect(UIScreen.mainScreen.bounds));
            for (UIView *c in gItemContainers.allObjects) {
                if (!c.window) continue;
                XRKDebugLog(@"[Shot] container win=%@ bundle=%@", NSStringFromCGRect([c convertRect:c.bounds toView:nil]),
                            XRKLayoutBundleID([(SBFluidSwitcherItemContainer *)c appLayout]));
            }
        });
#endif
    }
}
