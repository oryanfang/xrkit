// 主屏幕：图标行列数（需注销）、编辑模式隐藏「+」和「完成」按钮
//
// iOS 17 结构（探测确认，2026-11-16）：
//   - 每页格子大小 SBHIconGridSize = {列, 行}（两个 16 位整数），系统是 4×6；
//     来源 SBHIconManager -listGridSizeForFolderClass: / -iconModel:listGridSizeForFolderClass:，根文件夹 SBRootFolder -listGridSize
//   - 排版 SBHDefaultIconListLayoutProvider -makeLayoutForIconLocation:，位置 "SBIconLocationRoot…"，
//     layoutConfiguration 里 numberOfPortraitColumns / Rows、iconImageInfo、portraitLayoutInsets {94, 35, 244, 35}、
//     listSizeForIconSpacingCalculation {430, 932}
//   - 编辑模式左上「+」和右上「完成」：SBRootFolderView -setShowsAddWidgetButton:animated: / -setShowsDoneButton:animated:
#import "XRKCommon.h"

typedef struct {
    uint16_t columns;
    uint16_t rows;
} XRKIconGridSize;

@interface SBIconListGridLayoutConfiguration : NSObject
- (unsigned long long)numberOfPortraitColumns;
- (unsigned long long)numberOfPortraitRows;
- (void)setNumberOfPortraitColumns:(unsigned long long)columns;
- (void)setNumberOfPortraitRows:(unsigned long long)rows;
- (XRKIconImageInfo)iconImageInfo;
- (void)setIconImageInfo:(XRKIconImageInfo)info;
- (UIEdgeInsets)portraitLayoutInsets;
- (CGSize)listSizeForIconSpacingCalculation;
@end

@interface SBRootFolderView : UIView
- (void)setShowsAddWidgetButton:(BOOL)shows animated:(BOOL)animated;
- (void)setShowsDoneButton:(BOOL)shows animated:(BOOL)animated;
@end

#pragma mark - 行列数（SpringBoard 启动时读一次，改了要注销）
// 只允许比系统多（列 4～6、行 6～8）：比系统少的话，已有的大小组件放不下会被系统挤到别的页，甚至丢掉。
// 改回系统大小时多出来的图标系统会挪到后面的页。

static uint16_t gColumns = 4, gRows = 6;

static BOOL XRKGridCustom(void) { return gColumns != 4 || gRows != 6; }

static BOOL XRKIsRootFolderClass(Class cls) {
    Class root = objc_getClass("SBRootFolder");
    return root && cls && (cls == root || [cls isSubclassOfClass:root]);
}

// 图标原尺寸放不下时按比例缩小（圆角等比缩）。每列至少留 kMinColGap，每行给名字和间距留 kRowExtra
static const CGFloat kMinColGap = 10;
static const CGFloat kRowExtra = 28;

static void XRKFitHomeIconSize(SBIconListGridLayoutConfiguration *config) {
    XRKIconImageInfo info = [config iconImageInfo];
    if (info.size.width <= 0) return;
    CGSize list = [config respondsToSelector:@selector(listSizeForIconSpacingCalculation)] ? [config listSizeForIconSpacingCalculation] : CGSizeZero;
    if (list.width <= 0) list = UIScreen.mainScreen.bounds.size;
    UIEdgeInsets insets = [config respondsToSelector:@selector(portraitLayoutInsets)] ? [config portraitLayoutInsets] : UIEdgeInsetsZero;
    CGFloat w = list.width - insets.left - insets.right, h = list.height - insets.top - insets.bottom;
    CGFloat fitW = floor(w / gColumns - kMinColGap), fitH = floor(h / gRows - kRowExtra);
    CGFloat fitting = MIN(fitW, fitH);
    if (fitting >= info.size.width || fitting < 30) return;
    CGFloat ratio = fitting / info.size.width;
    XRKIconImageInfo smaller = info;
    smaller.size = CGSizeMake(fitting, round(info.size.height * ratio));
    smaller.continuousCornerRadius = info.continuousCornerRadius * ratio;
    [config setIconImageInfo:smaller];
}

%group XRKHomeGrid
%hook SBHIconManager

- (XRKIconGridSize)listGridSizeForFolderClass:(Class)cls {
    if (!XRKIsRootFolderClass(cls)) return %orig;
    return (XRKIconGridSize){gColumns, gRows};
}

- (XRKIconGridSize)iconModel:(id)model listGridSizeForFolderClass:(Class)cls {
    if (!XRKIsRootFolderClass(cls)) return %orig;
    return (XRKIconGridSize){gColumns, gRows};
}

%end

%hook SBRootFolder

- (XRKIconGridSize)listGridSize {
    return (XRKIconGridSize){gColumns, gRows};
}

%end

%hook SBHDefaultIconListLayoutProvider

- (id)makeLayoutForIconLocation:(NSString *)location {
    id layout = %orig;
    if (![location isKindOfClass:[NSString class]] || ![location hasPrefix:@"SBIconLocationRoot"]) return layout;
    @try {
        SBIconListGridLayoutConfiguration *config = [layout valueForKey:@"layoutConfiguration"];
        if (![config respondsToSelector:@selector(setNumberOfPortraitRows:)]) return layout;
        [config setNumberOfPortraitColumns:gColumns];
        [config setNumberOfPortraitRows:gRows];
        XRKFitHomeIconSize(config);
    } @catch (__unused NSException *e) {
    }
    return layout;
}

%end
%end

#pragma mark - 编辑模式按钮（即时生效）
// 记住系统想不想显示，设置一改就按"系统想要 && 没被隐藏"重设

static NSHashTable *gEditRootViews;
static const void *kXRKWantsAddKey = &kXRKWantsAddKey;
static const void *kXRKWantsDoneKey = &kXRKWantsDoneKey;

%group XRKEditButtons
%hook SBRootFolderView

- (void)setShowsAddWidgetButton:(BOOL)shows animated:(BOOL)animated {
    XRKTrack(gEditRootViews, self);
    objc_setAssociatedObject(self, kXRKWantsAddKey, @(shows), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    %orig(shows && !XRKOn(kXRKHsHideAddWidget), animated);
}

- (void)setShowsDoneButton:(BOOL)shows animated:(BOOL)animated {
    XRKTrack(gEditRootViews, self);
    objc_setAssociatedObject(self, kXRKWantsDoneKey, @(shows), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    %orig(shows && !XRKOn(kXRKHsHideEditDone), animated);
}

%end
%end

#pragma mark - 初始化

void XRKInitHomeGrid(void) {
    BOOL gridOK = XRKResponds("SBHIconManager", @[@"listGridSizeForFolderClass:", @"iconModel:listGridSizeForFolderClass:"]) &&
                  XRKResponds("SBRootFolder", @[@"listGridSize"]) &&
                  XRKResponds("SBHDefaultIconListLayoutProvider", @[@"makeLayoutForIconLocation:"]) &&
                  XRKResponds("SBIconListGridLayoutConfiguration", @[@"setNumberOfPortraitColumns:", @"setNumberOfPortraitRows:",
                                                                     @"iconImageInfo", @"setIconImageInfo:"]);
    BOOL editOK = XRKResponds("SBRootFolderView", @[@"setShowsAddWidgetButton:animated:", @"setShowsDoneButton:animated:"]);
    gColumns = (uint16_t)lround(XRKDouble(kXRKHsColumns, 4, 4, 6));
    gRows = (uint16_t)lround(XRKDouble(kXRKHsRows, 6, 6, 8));
    XRKDebugLog(@"[HomeGrid] grid=%d edit=%d size=%u×%u", gridOK, editOK, gColumns, gRows);

    if (gridOK && XRKGridCustom()) {
        %init(XRKHomeGrid);
    } else {
        gColumns = 4; gRows = 6;
    }

    if (editOK) {
        gEditRootViews = [NSHashTable weakObjectsHashTable];
        %init(XRKEditButtons);
        XRKAddRefresher(@[kXRKHsHideAddWidget, kXRKHsHideEditDone], ^{
            for (SBRootFolderView *v in gEditRootViews.allObjects) {
                NSNumber *add = objc_getAssociatedObject(v, kXRKWantsAddKey), *done = objc_getAssociatedObject(v, kXRKWantsDoneKey);
                if (add) [v setShowsAddWidgetButton:add.boolValue animated:YES];
                if (done) [v setShowsDoneButton:done.boolValue animated:YES];
            }
        });
    }
}
