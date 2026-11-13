// Dock：隐藏整个 Dock、背景样式、图标数量
//
// iOS 17 结构（探测确认）：SBDockView
//   ├── MTMaterialView（_backgroundView，毛玻璃背景）
//   └── SBDockIconListView（图标）
#import "XRKCommon.h"

@interface SBDockView : UIView
- (void)setBackgroundAlpha:(CGFloat)alpha;
@end

@interface SBIconListGridLayoutConfiguration : NSObject
- (void)setNumberOfPortraitColumns:(unsigned long long)columns;
- (XRKIconImageInfo)iconImageInfo;
- (void)setIconImageInfo:(XRKIconImageInfo)info;
@end

@interface SBRootFolderController : NSObject
+ (NSString *)dockIconLocation;
@end

static NSHashTable *gDockViews;
static const void *kXRKDockEffectKey = &kXRKDockEffectKey;
static const void *kXRKDockHidMaterialKey = &kXRKDockHidMaterialKey;
static const void *kXRKDockBaseFrameKey = &kXRKDockBaseFrameKey;
static const void *kXRKDockAppliedFrameKey = &kXRKDockAppliedFrameKey;
static const void *kXRKDockBaseRadiusKey = &kXRKDockBaseRadiusKey;
static const void *kXRKDockSystemAlphaKey = &kXRKDockSystemAlphaKey;   // 系统自己设的背景透明度（换回「系统」样式时还给它）

// Dock 图标被缩小的比例（1 = 没缩）；图标数量放不下时由 XRKFitDockIconSize 设置
static CGFloat gDockIconRatio = 1;

typedef NS_ENUM(NSInteger, XRKDockBackgroundStyle) {
    XRKDockBackgroundSystem = 0,
    XRKDockBackgroundClear = 1,
    XRKDockBackgroundDark = 2,
    XRKDockBackgroundLight = 3,
};

static XRKDockBackgroundStyle XRKDockStyle(void) {
    return (XRKDockBackgroundStyle)lround(XRKDouble(kXRKDockBackground, 0, 0, 3));
}

// 图标数量决定 Dock 的容量和列数，SpringBoard 启动时读一次就固定下来（改了要注销）
static unsigned long long gFixedCount = 4;

// 竖线右边的个数不影响系统布局，随时读偏好，改了马上生效
unsigned long long XRKDockRecentSlots(void) { return (unsigned long long)lround(XRKDouble(kXRKDockRecentApps, 0, 0, 3)); }

#pragma mark - 背景样式

static void XRKApplyDockBackground(UIView *dock) {
    UIView *material = XRKViewIvar(dock, @"_backgroundView");
    UIVisualEffectView *effect = objc_getAssociatedObject(dock, kXRKDockEffectKey);
    XRKDockBackgroundStyle style = XRKDockStyle();

    if (style == XRKDockBackgroundSystem) {
        [effect removeFromSuperview];
        // 只恢复被我们藏起来的
        if ([objc_getAssociatedObject(dock, kXRKDockHidMaterialKey) boolValue]) {
            material.hidden = NO;
            material.alpha = 1;
            objc_setAssociatedObject(dock, kXRKDockHidMaterialKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        return;
    }

    if (material) {
        material.hidden = YES;
        objc_setAssociatedObject(dock, kXRKDockHidMaterialKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (style == XRKDockBackgroundClear || !material) {
        [effect removeFromSuperview];
        return;
    }

    if (!effect) {
        effect = [[UIVisualEffectView alloc] initWithEffect:nil];
        effect.userInteractionEnabled = NO;
        effect.clipsToBounds = YES;
        effect.layer.cornerCurve = kCACornerCurveContinuous;
        objc_setAssociatedObject(dock, kXRKDockEffectKey, effect, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    UIBlurEffectStyle blur = style == XRKDockBackgroundDark ? UIBlurEffectStyleSystemMaterialDark : UIBlurEffectStyleSystemMaterialLight;
    effect.effect = [UIBlurEffect effectWithStyle:blur];
    // 跟系统背景同样的位置和圆角
    effect.frame = material.frame;
    CGFloat radius = material.layer.cornerRadius;
    if (radius <= 0) radius = MIN(material.bounds.size.height * 0.3, 34);
    effect.layer.cornerRadius = radius;
    if (effect.superview != dock) [dock insertSubview:effect aboveSubview:material];
}

#pragma mark - 背景跟着图标缩小
// 图标缩小时，背景（气泡）的高度和圆角按同样比例缩，跟图标保持居中；宽度不变（6 个图标本来就占满）。
// 系统每次布局可能会重设背景 frame，也可能不会：记下"系统给的"和"我们改过的"，避免在自己改过的基础上反复缩。

static void XRKFitDockBackground(UIView *dock) {
    if (gDockIconRatio >= 1) return;
    UIView *material = XRKViewIvar(dock, @"_backgroundView");
    if (!material) return;

    NSValue *applied = objc_getAssociatedObject(material, kXRKDockAppliedFrameKey);
    if (!applied || !CGRectEqualToRect(applied.CGRectValue, material.frame)) {
        objc_setAssociatedObject(material, kXRKDockBaseFrameKey, [NSValue valueWithCGRect:material.frame], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (!objc_getAssociatedObject(material, kXRKDockBaseRadiusKey)) {
        objc_setAssociatedObject(material, kXRKDockBaseRadiusKey, @(material.layer.cornerRadius), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    CGRect base = [objc_getAssociatedObject(material, kXRKDockBaseFrameKey) CGRectValue];
    CGFloat baseRadius = [objc_getAssociatedObject(material, kXRKDockBaseRadiusKey) doubleValue];

    CGFloat height = round(base.size.height * gDockIconRatio);
    CGRect frame = CGRectMake(base.origin.x, round(CGRectGetMidY(base) - height / 2), base.size.width, height);
    material.frame = frame;
    if (baseRadius > 0) material.layer.cornerRadius = baseRadius * gDockIconRatio;
    objc_setAssociatedObject(material, kXRKDockAppliedFrameKey, [NSValue valueWithCGRect:frame], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

#pragma mark - hook

%group XRKDock
%hook SBDockView

- (void)setBackgroundAlpha:(CGFloat)alpha {
    objc_setAssociatedObject(self, kXRKDockSystemAlphaKey, @(alpha), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    %orig(XRKDockStyle() == XRKDockBackgroundSystem ? alpha : 0);
}

- (void)setHidden:(BOOL)hidden {
    %orig(XRKNoteSystemHidden(self, hidden) || XRKOn(kXRKDockHide));
}

- (void)didMoveToWindow {
    %orig;
    XRKTrack(gDockViews, self);
    if (XRKOn(kXRKDockHide)) XRKReapplyHidden(self);
}

- (void)layoutSubviews {
    // 竖线右边的运行中 App 需要平移/缩放整个图标列表（见 DockRunning.x）；系统布局会重设列表位置，
    // 所以布局前复位成原样、布局后再套上，避免带着变换设 frame
    UIView *list = XRKViewIvar(self, @"_iconListView");
    XRKDockApplyListTransform(list, YES);
    %orig;
    XRKDockApplyListTransform(list, NO);
    XRKTrack(gDockViews, self);
    XRKFitDockBackground(self);     // 先定背景大小，深色/浅色背景再照着它的 frame 和圆角画
    XRKApplyDockBackground(self);
}

%end
%end

#pragma mark - 图标数量（SpringBoard 启动时读取，需要注销）
// 容量：SBHIconManager / SBRootFolder 的 maxIconCountForDock（原值 4）
// 布局：SBHDefaultIconListLayoutProvider 给 Dock 位置做的布局，每行列数（原值 4）；放不下时缩小图标尺寸

// 列数 = 图标数量（启动时定死；竖线右边运行中 App 的位置由 DockRunning.x 自己摆，不靠加列）。
// 图标原尺寸放不下时（间距不到 kMinGap），按比例缩小 Dock 图标，圆角等比缩。
// Dock 背景比屏幕窄 28pt（左右各 14，探测确认）；5 列原尺寸放得下，6 列会缩到约 54pt。
static const CGFloat kDockSideInset = 28;
static const CGFloat kMinGap = 11;

static void XRKFitDockIconSize(SBIconListGridLayoutConfiguration *config, unsigned long long count) {
    if (![config respondsToSelector:@selector(iconImageInfo)] || ![config respondsToSelector:@selector(setIconImageInfo:)]) return;
    XRKIconImageInfo info = [config iconImageInfo];
    CGFloat available = UIScreen.mainScreen.bounds.size.width - kDockSideInset;
    CGFloat fitting = floor((available - (count + 1) * kMinGap) / count);
    if (info.size.width <= 0 || fitting >= info.size.width) return;
    CGFloat ratio = fitting / info.size.width;
    gDockIconRatio = ratio;
    XRKIconImageInfo smaller = info;
    smaller.size = CGSizeMake(fitting, round(info.size.height * ratio));
    smaller.continuousCornerRadius = info.continuousCornerRadius * ratio;
    [config setIconImageInfo:smaller];
}

%group XRKDockIconCount
%hook SBHIconManager

- (unsigned long long)maxIconCountForDock {
    return gFixedCount != 4 ? gFixedCount : %orig;
}

- (unsigned long long)maxIconCountForDockForIconModel:(id)model {
    return gFixedCount != 4 ? gFixedCount : %orig;
}

- (unsigned long long)maxIconCountForDockForRootFolder:(id)folder {
    return gFixedCount != 4 ? gFixedCount : %orig;
}

%end

%hook SBRootFolder

- (unsigned long long)maxIconCountForDock {
    return gFixedCount != 4 ? gFixedCount : %orig;
}

%end

%hook SBHDefaultIconListLayoutProvider

- (id)makeLayoutForIconLocation:(NSString *)location {
    id layout = %orig;
    unsigned long long count = gFixedCount;
    if (count == 4 || ![location isEqualToString:[objc_getClass("SBRootFolderController") dockIconLocation]]) return layout;
    @try {
        SBIconListGridLayoutConfiguration *config = [layout valueForKey:@"layoutConfiguration"];
        if (![config respondsToSelector:@selector(setNumberOfPortraitColumns:)]) return layout;
        [config setNumberOfPortraitColumns:count];
        XRKFitDockIconSize(config, count);
    } @catch (__unused NSException *e) {
    }
    return layout;
}

%end
%end

#pragma mark - 初始化

void XRKInitDock(void) {
    BOOL dockOK = XRKResponds("SBDockView", @[@"setBackgroundAlpha:"]);
    BOOL countOK = XRKResponds("SBHIconManager", @[@"maxIconCountForDock", @"maxIconCountForDockForIconModel:",
                                                   @"maxIconCountForDockForRootFolder:"]) &&
                   XRKResponds("SBRootFolder", @[@"maxIconCountForDock"]) &&
                   XRKResponds("SBHDefaultIconListLayoutProvider", @[@"makeLayoutForIconLocation:"]) &&
                   XRKResponds("SBIconListGridLayoutConfiguration", @[@"setNumberOfPortraitColumns:", @"iconImageInfo", @"setIconImageInfo:"]) &&
                   XRKClassResponds("SBRootFolderController", @[@"dockIconLocation"]);
    gFixedCount = (unsigned long long)lround(XRKDouble(kXRKDockIconCount, 4, 3, 6));
    XRKDebugLog(@"[Dock] view=%d iconCount=%d (fixed=%llu recentSlots=%llu)", dockOK, countOK, gFixedCount, XRKDockRecentSlots());

    if (countOK && gFixedCount != 4) {
        %init(XRKDockIconCount);
    } else {
        gFixedCount = 4;      // 没装 hook 时按系统默认
    }
    if (!dockOK) return;

    gDockViews = [NSHashTable weakObjectsHashTable];
    %init(XRKDock);
    XRKAddRefresher(@[kXRKDockHide, kXRKDockBackground], ^{
        for (SBDockView *dock in gDockViews.allObjects) {
            XRKReapplyHidden(dock);
            NSNumber *alpha = objc_getAssociatedObject(dock, kXRKDockSystemAlphaKey);
            [dock setBackgroundAlpha:alpha ? alpha.doubleValue : 1];
            XRKApplyDockBackground(dock);
        }
    });
}
