// Mac 风格 Dock：
//   1. 运行中的 App 图标下面显示白点（Dock 里的，以及竖线右边的）
//   2. 竖线右边显示"在 App 切换器里、但不在 Dock 里"的 App，按最近使用排序，点按打开，长按不响应
//
// "运行中" = App 切换器里的 App（SBMainSwitcherControllerCoordinator -recentAppLayouts，已按最近使用排序）。
// 切换器变化时系统会调 -_notifySwitcherControllersAppLayoutsDidChange，借这个时机刷新。
//
// ⚠️ 不能在布局过程中直接调 +[SBMainSwitcherControllerCoordinator sharedInstance]：
// SpringBoard 启动时，正是在创建这个单例的过程中初始化主屏幕、触发 Dock 布局的，
// 这时再要单例会让 dispatch_once 递归加锁，SpringBoard 直接崩溃 → 安全模式（0.1.0-43 踩过）。
// 所以取数据一律用 XRKScheduleRunningRefresh() 推迟到当前这一轮跑完。
//
// 右边的位置（自适应）：平时 Dock 完全是原生的；右侧有 App 时由我们重新摆 Dock 图标和右侧 App，
// 放不下就整体缩小（见 XRKUpdateRecentApps 上面的说明）。
// 这些图标是我们自己的视图，不进系统的图标模型，不会改动主屏幕布局。
#import "XRKCommon.h"

@interface SBIconListView : UIView
- (void)layoutIconsNow;
@end

@interface SBDockIconListView : SBIconListView
@end

@interface SBIconView : UIView
- (id)icon;
- (BOOL)isEditing;
@end

@interface NSObject (XRKDockRunning)
+ (instancetype)sharedInstance;
- (NSArray *)recentAppLayouts;
- (NSArray *)allItems;
- (NSString *)bundleIdentifier;
- (NSString *)applicationBundleID;
- (id)iconManager;
- (id)iconModel;
- (id)applicationIconForBundleIdentifier:(NSString *)bundleID;
@end

@interface NSObject (XRKDockRunningLaunch)
- (id)applicationWithBundleIdentifier:(NSString *)bundleID;
- (id)initWithApplicationForMainDisplay:(id)application;
- (id)createRequestForApplicationActivation:(id)entity options:(unsigned long long)options;
- (BOOL)executeTransitionRequest:(id)request;
@end

@interface NSObject (XRKDockRunningIcon)
- (UIImage *)iconImageWithInfo:(XRKIconImageInfo)info;
@end

static NSHashTable *gDockLists;
static CGAffineTransform gListTransform;          // 图标列表要套的平移+缩放（Dock.x 在系统布局后重新套）
static NSArray<NSString *> *gRunningBundleIDs;   // 切换器里的 App，按最近使用
static __weak id gIconModel;                       // 在推迟的刷新里取好，布局时直接用（不在布局里要单例）
static const void *kXRKRunningDotKey = &kXRKRunningDotKey;
static const void *kXRKRecentContainerKey = &kXRKRecentContainerKey;

#pragma mark - 数据

static NSArray<NSString *> *XRKFetchRunningBundleIDs(void) {
    NSMutableArray *ids = [NSMutableArray array];
    @try {
        id coordinator = [objc_getClass("SBMainSwitcherControllerCoordinator") sharedInstance];
        if (![coordinator respondsToSelector:@selector(recentAppLayouts)]) return ids;
        for (id layout in [coordinator recentAppLayouts]) {
            if (![layout respondsToSelector:@selector(allItems)]) continue;
            for (id item in [layout allItems]) {
                NSString *bundleID = [item respondsToSelector:@selector(bundleIdentifier)] ? [item bundleIdentifier] : nil;
                if (bundleID.length && ![ids containsObject:bundleID]) [ids addObject:bundleID];
            }
        }
    } @catch (__unused NSException *e) {
    }
    return ids;
}

static NSString *XRKBundleIDForIconView(UIView *iconView) {
    @try {
        id icon = [(SBIconView *)iconView icon];
        return [icon respondsToSelector:@selector(applicationBundleID)] ? [icon applicationBundleID] : nil;
    } @catch (__unused NSException *e) {
        return nil;
    }
}

static UIImage *XRKAppIconImage(NSString *bundleID, CGSize size) {
    @try {
        id icon = [gIconModel applicationIconForBundleIdentifier:bundleID];
        if (![icon respondsToSelector:@selector(iconImageWithInfo:)]) return nil;
        XRKIconImageInfo info = { size, UIScreen.mainScreen.scale, size.width * 0.225 };
        return [icon iconImageWithInfo:info];
    } @catch (__unused NSException *e) {
        return nil;
    }
}

#pragma mark - 白点

static CGRect XRKDockIconImageFrame(UIView *iconView, UIView *list) {
    UIView *imageView = XRKViewIvar(iconView, @"_iconImageView");
    return imageView ? [imageView convertRect:imageView.bounds toView:list] : iconView.frame;
}

static UIView *XRKMakeDot(void) {
    UIView *dot = [UIView new];
    dot.backgroundColor = UIColor.whiteColor;
    dot.userInteractionEnabled = NO;
    dot.layer.shadowColor = UIColor.blackColor.CGColor;
    dot.layer.shadowOpacity = 0.35;
    dot.layer.shadowRadius = 1.5;
    dot.layer.shadowOffset = CGSizeZero;
    return dot;
}

// 白点放在图标正下方
static void XRKPlaceDot(UIView *dot, CGRect iconFrame) {
    CGFloat side = 4.5;
    dot.bounds = CGRectMake(0, 0, side, side);
    dot.layer.cornerRadius = side / 2;
    dot.center = CGPointMake(CGRectGetMidX(iconFrame), CGRectGetMaxY(iconFrame) + 6);
}

// Dock 里系统的图标视图（从左到右）和它们的 bundleID（白点、右侧共用，每次更新只取一遍）
static NSArray<UIView *> *XRKCollectDockIcons(UIView *list, NSMutableArray *bundleIDsOut) {
    NSMutableArray<UIView *> *views = [NSMutableArray array];
    for (UIView *v in list.subviews) {
        if ([v isKindOfClass:XRKClass("SBIconView")] && !v.hidden) [views addObject:v];
    }
    [views sortUsingComparator:^NSComparisonResult(UIView *a, UIView *b) {
        return a.center.x < b.center.x ? NSOrderedAscending : (a.center.x > b.center.x ? NSOrderedDescending : NSOrderedSame);
    }];
    for (UIView *v in views) [bundleIDsOut addObject:XRKBundleIDForIconView(v) ?: NSNull.null];
    return views;
}

static void XRKUpdateDockDots(SBIconListView *list, NSArray<UIView *> *iconViews, NSArray *bundleIDs) {
    BOOL on = XRKOn(kXRKDockRunningDots);
    for (NSUInteger i = 0; i < iconViews.count; i++) {
        UIView *iconView = iconViews[i];
        UIView *dot = objc_getAssociatedObject(iconView, kXRKRunningDotKey);
        id bundleID = bundleIDs[i];
        BOOL running = on && bundleID != NSNull.null && [gRunningBundleIDs containsObject:bundleID];
        if (!running) {
            dot.hidden = YES;
            continue;
        }
        if (!dot) {
            dot = XRKMakeDot();
            objc_setAssociatedObject(iconView, kXRKRunningDotKey, dot, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        if (dot.superview != list) [list addSubview:dot];
        XRKPlaceDot(dot, XRKDockIconImageFrame(iconView, list));
        dot.hidden = NO;
    }
}

#pragma mark - 竖线右边的运行中 App

// 右边图标的点击：用 bundleID 打开
@interface XRKDockRecentButton : UIControl
@property (nonatomic, copy) NSString *bundleID;
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) UIView *dot;
@end

@implementation XRKDockRecentButton

- (instancetype)init {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        _imageView = [UIImageView new];
        _imageView.userInteractionEnabled = NO;
        [self addSubview:_imageView];
        _dot = XRKMakeDot();
        [self addSubview:_dot];
        [self addTarget:self action:@selector(xrk_tapped) forControlEvents:UIControlEventTouchUpInside];
        [self addTarget:self action:@selector(xrk_highlight) forControlEvents:UIControlEventTouchDown | UIControlEventTouchDragEnter];
        [self addTarget:self action:@selector(xrk_unhighlight)
       forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel | UIControlEventTouchDragExit];
    }
    return self;
}

// 按下时跟系统图标一样稍微变暗
- (void)xrk_highlight { self.imageView.alpha = 0.6; }
- (void)xrk_unhighlight { self.imageView.alpha = 1; }

// 打开 App：直接向 SpringBoard 工作区发"切换到这个 App"的请求（系统所有打开 App 的操作最后都走到这一步），主线程调：
//   entity  = [[SBDeviceApplicationSceneEntity alloc] initWithApplicationForMainDisplay:app]
//   request = [[SBMainWorkspace sharedInstance] createRequestForApplicationActivation:entity options:0]
//   [[SBMainWorkspace sharedInstance] executeTransitionRequest:request]
// ⚠️ 踩过的坑：
//   - LSApplicationWorkspace openApplicationWithBundleID:（给普通 App 用的，SpringBoard 里调等于绕一圈请求自己）：
//     主线程调卡约 30 秒（0.1.0-44），后台线程调撞上 SpringBoard 的 App 启动流程，主线程卡死、看门狗 60 秒重启（0.1.0-55）
//   - SBUIController -activateApplication:… 参数传 nil（0.1.0-57）、SBIconController -iconManager:launchIcon:location:…（0.1.0-59）：
//     不卡，但都什么也不做
- (void)xrk_tapped {
    NSString *bundleID = self.bundleID;
    if (!bundleID.length) return;
    @try {
        id app = [[objc_getClass("SBApplicationController") sharedInstance] applicationWithBundleIdentifier:bundleID];
        id entity = app ? [[objc_getClass("SBDeviceApplicationSceneEntity") alloc] initWithApplicationForMainDisplay:app] : nil;
        id workspace = [objc_getClass("SBMainWorkspace") sharedInstance];
        id request = entity ? [workspace createRequestForApplicationActivation:entity options:0] : nil;
        BOOL ok = request ? [workspace executeTransitionRequest:request] : NO;
        if (!ok) XRKDebugLog(@"[DockRunning] launch %@ failed (app=%d entity=%d request=%d)", bundleID, app != nil, entity != nil, request != nil);
    } @catch (NSException *e) {
        XRKDebugLog(@"[DockRunning] launch failed: %@", e.reason);
    }
}

@end

// 容器：竖线 + 若干按钮，加在 Dock 图标列表里面（这样跟着系统的淡入淡出、缩放动画一起动）
@interface XRKDockRecentContainer : UIView
@property (nonatomic, strong) UIView *divider;
@property (nonatomic, strong) NSMutableArray<XRKDockRecentButton *> *buttons;
@end

@implementation XRKDockRecentContainer

- (instancetype)init {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        _divider = [UIView new];
        _divider.backgroundColor = [UIColor colorWithWhite:1 alpha:0.35];
        _divider.userInteractionEnabled = NO;
        [self addSubview:_divider];
        _buttons = [NSMutableArray array];
    }
    return self;
}

// 只有点在按钮上才接收触摸，其余位置透传给系统的 Dock
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    return hit == self || hit == self.divider ? nil : hit;
}

@end

static XRKDockRecentContainer *XRKRecentContainer(UIView *list, BOOL create) {
    XRKDockRecentContainer *container = objc_getAssociatedObject(list, kXRKRecentContainerKey);
    if (!container && create) {
        container = [XRKDockRecentContainer new];
        objc_setAssociatedObject(list, kXRKRecentContainerKey, container, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return container;
}

// Dock 里实际图标的大小（Dock.x 可能缩过）
static CGSize XRKDockIconSize(SBIconListView *list) {
    for (UIView *iconView in list.subviews) {
        if (![iconView isKindOfClass:XRKClass("SBIconView")]) continue;
        UIView *imageView = XRKViewIvar(iconView, @"_iconImageView");
        if (imageView.bounds.size.width > 0) return imageView.bounds.size;
    }
    return CGSizeMake(60, 60);
}

// 位置怎么算（踩过三次坑才定下来）：
// - Dock 是"流式布局"（SBIconListFlowExtendedLayout），图标间距只在启动时按列数算一次并缓存，运行中改列数不会重排；
// - 所以右侧有 App 时，由我们自己摆：算出能放下"Dock 图标 + 竖线 + 右侧 App"的图标大小和间距，
//   直接改系统那几个图标视图的 center，我们的按钮也按同样间距放；图标大小通过整个列表的缩放实现（图标视图本身不加变换）；
// - 右侧没有 App、或 Dock 在编辑模式（图标抖动）时不接管，让系统重新排一次恢复原样。
static const CGFloat kDividerExtra = 0.5;   // 竖线两边比普通间距多留半个间距
static const CGFloat kMinIconGap = 14;      // 图标之间至少留 14pt
static const CGFloat kListSideInset = 35;   // 系统 Dock 左右各留 35pt（4 列间距 98.7、5 列 74 反推出来的）

static BOOL gRepositioned = NO;   // 当前是不是我们摆的位置（需要恢复时让系统重排）
static BOOL gRestoring = NO;
static const void *kXRKTargetCenterKey = &kXRKTargetCenterKey;   // 接管时每个 Dock 图标的目标位置

// 系统会从很多条路挪图标（layoutIconsNow、动画重排、单个图标的动画更新……），只补 layoutIconsNow 不够，
// 会出现"系统图标被挪回原位、右侧 App 还在我们的位置"→ 重叠（0.1.0-52 踩过）。
// 所以接管期间直接拦 SBIconView 的 setCenter:/setFrame:，统一改成目标位置。
static NSValue *XRKTargetCenter(UIView *iconView) {
    if (!gRepositioned || gRestoring) return nil;
    if (![iconView.superview isKindOfClass:XRKClass("SBDockIconListView")]) return nil;
    return objc_getAssociatedObject(iconView, kXRKTargetCenterKey);
}

static void XRKClearTargets(UIView *list) {
    for (UIView *v in list.subviews) objc_setAssociatedObject(v, kXRKTargetCenterKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// Dock.x 在系统布局 Dock 前后调用：reset=YES 复位，NO 套上算好的缩放
void XRKDockApplyListTransform(UIView *list, BOOL reset) {
    CGAffineTransform t = reset ? CGAffineTransformIdentity : gListTransform;
    if (list && !CGAffineTransformEqualToTransform(list.transform, t)) list.transform = t;
}

static void XRKSetListTransform(UIView *list, CGAffineTransform t) {
    gListTransform = t;
    if (!CGAffineTransformEqualToTransform(list.transform, t)) list.transform = t;
}

// 交还给系统：去掉缩放，让系统按原样重排图标
static void XRKRestoreSystemDock(SBIconListView *list) {
    XRKSetListTransform(list, CGAffineTransformIdentity);
    if (!gRepositioned) return;
    gRepositioned = NO;
    XRKClearTargets(list);
    gRestoring = YES;
    if ([list respondsToSelector:@selector(layoutIconsNow)]) [list layoutIconsNow];
    gRestoring = NO;
}

static BOOL XRKDockIsEditing(NSArray<UIView *> *iconViews) {
    for (UIView *iconView in iconViews) {
        if ([iconView respondsToSelector:@selector(isEditing)] && [(id)iconView isEditing]) return YES;
    }
    return NO;
}

static void XRKUpdateRecentApps(SBIconListView *list, NSArray<UIView *> *iconViews, NSArray *bundleIDs) {
    unsigned long long slots = XRKDockRecentSlots();
    XRKDockRecentContainer *container = XRKRecentContainer(list, slots > 0);
    if (!slots) {
        [container removeFromSuperview];
        XRKRestoreSystemDock(list);
        return;
    }

    // Dock 里已有的 App 不重复显示
    NSSet *inDock = [NSSet setWithArray:bundleIDs];
    NSMutableArray *show = [NSMutableArray array];
    for (NSString *bundleID in gRunningBundleIDs) {
        if ([inDock containsObject:bundleID]) continue;
        [show addObject:bundleID];
        if (show.count >= slots) break;
    }

    container.frame = list.bounds;
    if (container.superview != list) [list addSubview:container];
    [list bringSubviewToFront:container];

    if (!show.count || XRKDockIsEditing(iconViews)) {
        container.hidden = YES;
        XRKRestoreSystemDock(list);
        return;
    }
    container.hidden = NO;

    // 整排有 gaps 个"间距"：Dock 图标之间 n-1 个、竖线那一格 1+kDividerExtra、右侧 App 之间 k-1 个
    CGSize iconSize = XRKDockIconSize(list);            // 系统图标原本的大小（列表未缩放时）
    NSUInteger n = iconViews.count, k = show.count;
    CGFloat gaps = (n ? n - 1 + 1 + kDividerExtra : 0) + (k - 1);
    CGFloat available = list.bounds.size.width - 2 * kListSideInset;   // 第一个图标左边缘到最后一个右边缘的总宽
    // 原生间距（只用来设上限，图标少时别排得比原生还开）：接管中时图标是我们摆的，按原生 4 列的 98.7 估
    CGFloat nativeSpacing = (!gRepositioned && n >= 2) ? (iconViews.lastObject.center.x - iconViews.firstObject.center.x) / (n - 1)
                                                       : (available - iconSize.width) / 3;

    // 先按原尺寸试：间距 = 均分可用宽度（但不超过原生间距）；间距不够 kMinIconGap 就缩小图标
    CGFloat visualIcon = iconSize.width;
    CGFloat visualSpacing = gaps > 0 ? MIN(nativeSpacing, (available - visualIcon) / gaps) : 0;
    if (gaps > 0 && visualSpacing - visualIcon < kMinIconGap) {
        visualIcon = floor((available - kMinIconGap * gaps) / (gaps + 1));
        visualSpacing = visualIcon + kMinIconGap;
    }
    CGFloat scale = MIN(1, visualIcon / iconSize.width);
    XRKSetListTransform(list, CGAffineTransformMakeScale(scale, scale));

    // 列表坐标（缩放前）里的位置：以列表中心为原点对称展开
    CGFloat spacing = visualSpacing / scale;
    CGFloat centerY = n ? iconViews.firstObject.center.y : CGRectGetMidY(list.bounds);
    CGFloat left = CGRectGetMidX(list.bounds) - gaps * spacing / 2;
    gRepositioned = YES;
    for (NSUInteger i = 0; i < n; i++) {
        CGPoint target = CGPointMake(round(left + i * spacing), centerY);
        objc_setAssociatedObject(iconViews[i], kXRKTargetCenterKey, [NSValue valueWithCGPoint:target], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        iconViews[i].center = target;
    }
    CGFloat lastX = left + (n ? n - 1 : 0) * spacing;
    CGFloat firstExtraX = n ? lastX + spacing * (1 + kDividerExtra) : left;

    // 竖线：最后一个 Dock 图标和第一个右侧 App 正中间
    CGFloat dividerHeight = round(iconSize.height * 0.7);
    container.divider.hidden = n == 0;
    container.divider.frame = CGRectMake(round((lastX + firstExtraX) / 2 - 0.5 / scale), round(centerY - dividerHeight / 2),
                                         MAX(1, 1 / scale), dividerHeight);

    while (container.buttons.count < k) {
        XRKDockRecentButton *button = [XRKDockRecentButton new];
        [container addSubview:button];
        [container.buttons addObject:button];
    }
    for (NSUInteger i = 0; i < container.buttons.count; i++) {
        XRKDockRecentButton *button = container.buttons[i];
        if (i >= k) {
            button.hidden = YES;
            continue;
        }
        NSString *bundleID = show[i];
        CGFloat x = firstExtraX + spacing * i;
        button.frame = CGRectMake(round(x - iconSize.width / 2), round(centerY - iconSize.height / 2), iconSize.width, iconSize.height);
        if (![button.bundleID isEqualToString:bundleID] || !button.imageView.image) {
            button.bundleID = bundleID;
            button.imageView.image = XRKAppIconImage(bundleID, iconSize);
        }
        button.imageView.frame = button.bounds;
        // 右边的都在运行，白点开关打开时才画
        button.dot.hidden = !XRKOn(kXRKDockRunningDots);
        XRKPlaceDot(button.dot, button.bounds);
        button.hidden = NO;
    }
}

static BOOL XRKDockRunningEnabled(void) {
    return XRKOn(kXRKDockRunningDots) || XRKDockRecentSlots() > 0;
}

// 功能关着时只做一次收尾（交还系统、藏掉我们的视图），之后每次排版直接返回
static BOOL gCleanedUp = YES;

static void XRKUpdateDockRunning(SBIconListView *list) {
    if (!XRKDockRunningEnabled()) {
        if (gCleanedUp) return;
        gCleanedUp = YES;
        [XRKRecentContainer(list, NO) removeFromSuperview];
        XRKRestoreSystemDock(list);
        for (UIView *v in list.subviews) [objc_getAssociatedObject(v, kXRKRunningDotKey) setHidden:YES];
        return;
    }
    gCleanedUp = NO;
    NSMutableArray *bundleIDs = [NSMutableArray array];
    NSArray<UIView *> *iconViews = XRKCollectDockIcons(list, bundleIDs);
    XRKUpdateRecentApps(list, iconViews, bundleIDs);   // 先摆位置
    XRKUpdateDockDots(list, iconViews, bundleIDs);     // 白点跟着图标的新位置
}

static void XRKRefreshRunning(BOOL animated) {
    if (!gIconModel) {
        @try {
            gIconModel = [[[objc_getClass("SBIconController") sharedInstance] iconManager] iconModel];
        } @catch (__unused NSException *e) {
        }
    }
    NSArray *ids = XRKDockRunningEnabled() ? XRKFetchRunningBundleIDs() : @[];
    // 切换器列表没变就只在"开关刚变"时刷新（列表一样但开关可能改了）
    BOOL same = gRunningBundleIDs && [ids isEqualToArray:gRunningBundleIDs];
    gRunningBundleIDs = ids;
    if (same && animated) return;
    for (SBIconListView *list in gDockLists.allObjects) {
        // Dock 正显示在屏幕上时（比如在切换器里划掉 App）平滑过渡，不突然跳
        if (animated && list.window && !list.window.hidden) {
            [UIView animateWithDuration:0.25 delay:0 options:UIViewAnimationOptionBeginFromCurrentState
                             animations:^{ XRKUpdateDockRunning(list); } completion:nil];
        } else {
            XRKUpdateDockRunning(list);
        }
    }
}

// 推迟到主线程下一轮再取数据（见文件开头的说明），多次调用只排一次
static BOOL gRefreshScheduled = NO;
static BOOL gDelayedRefreshScheduled = NO;

// 切换器变化（打开 App 时）延后 0.6 秒再重排：等打开 App 的放大动画放完、App 盖住主屏幕后再改，
// 否则动画中途 Dock 突然变样，看起来像重叠（0.1.0-54 发现的）
static void XRKScheduleDelayedRunningRefresh(void) {
    if (gDelayedRefreshScheduled) return;
    gDelayedRefreshScheduled = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        gDelayedRefreshScheduled = NO;
        XRKRefreshRunning(YES);
    });
}

static void XRKScheduleRunningRefresh(void) {
    if (gRefreshScheduled) return;
    gRefreshScheduled = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        gRefreshScheduled = NO;
        XRKRefreshRunning(NO);
    });
}

#pragma mark - hook

%group XRKDockRunning
%hook SBDockIconListView

- (void)layoutIconsNow {
    %orig;
    if (gRestoring || !gRunningBundleIDs) return;
    gRepositioned = NO;   // 系统刚排过，当前是原生位置
    XRKUpdateDockRunning(self);
}

- (void)layoutSubviews {
    %orig;
    XRKTrack(gDockLists, self);
    if (!gRunningBundleIDs) {
        // 第一次还没有数据：别在这里取（可能正处于 SpringBoard 启动中途），推迟取完再刷新
        if (XRKDockRunningEnabled()) XRKScheduleRunningRefresh();
        return;
    }
    XRKUpdateDockRunning(self);
}

%end

%hook SBIconView

- (void)setCenter:(CGPoint)center {
    NSValue *target = XRKTargetCenter(self);
    %orig(target ? target.CGPointValue : center);
}

- (void)setFrame:(CGRect)frame {
    NSValue *target = XRKTargetCenter(self);
    if (target) {
        CGPoint c = target.CGPointValue;
        frame.origin = CGPointMake(c.x - frame.size.width / 2, c.y - frame.size.height / 2);
    }
    %orig(frame);
}

%end

%hook SBMainSwitcherControllerCoordinator

- (void)_notifySwitcherControllersAppLayoutsDidChange {
    %orig;
    if (XRKDockRunningEnabled()) XRKScheduleDelayedRunningRefresh();
}

%end
%end

#pragma mark - 初始化

void XRKInitDockRunning(void) {
    BOOL ok = XRKResponds("SBMainSwitcherControllerCoordinator", @[@"recentAppLayouts", @"_notifySwitcherControllersAppLayoutsDidChange"]) &&
              XRKClassResponds("SBMainSwitcherControllerCoordinator", @[@"sharedInstance"]) &&
              XRKResponds("SBIconModel", @[@"applicationIconForBundleIdentifier:"]) &&
              XRKResponds("SBDockIconListView", @[@"layoutIconsNow"]) &&
              XRKResponds("SBApplicationController", @[@"applicationWithBundleIdentifier:"]) &&
              XRKResponds("SBDeviceApplicationSceneEntity", @[@"initWithApplicationForMainDisplay:"]) &&
              XRKResponds("SBMainWorkspace", @[@"createRequestForApplicationActivation:options:", @"executeTransitionRequest:"]);
    XRKDebugLog(@"[DockRunning] ok=%d dots=%d recentSlots=%llu", ok, XRKOn(kXRKDockRunningDots), XRKDockRecentSlots());
    if (!ok) return;

    gDockLists = [NSHashTable weakObjectsHashTable];
    gListTransform = CGAffineTransformIdentity;
    %init(XRKDockRunning);
    XRKAddRefresher(@[kXRKDockRunningDots, kXRKDockRecentApps], ^{
        XRKScheduleRunningRefresh();
    });
}
