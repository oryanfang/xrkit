// 文件夹：隐藏文件夹背景、文件夹显示为第一个 App 的图标
#import "XRKCommon.h"

@interface SBIcon : NSObject
- (UIImage *)iconImageWithInfo:(XRKIconImageInfo)info;
- (UIImage *)generateIconImageWithInfo:(XRKIconImageInfo)info;
@end

@interface SBFolder : NSObject
- (SBIcon *)firstIcon;
@end

@interface SBFolderIcon : SBIcon
- (SBFolder *)folder;
@end

@interface SBFolderIconImageView : UIView
- (UIView *)backgroundView;
- (SBFolderIcon *)_folderIcon;
- (XRKIconImageInfo)iconImageInfo;
- (void)setPageGridHidden:(BOOL)hidden;
- (BOOL)isPageGridHidden;
@end

@interface SBFolderBackgroundView : UIView
@end

@interface SBIconView : UIView
@end

#pragma mark - 隐藏文件夹背景
// 主屏幕上文件夹图标的底板：SBFolderIconImageView 的 backgroundView
// 打开文件夹后的圆角毛玻璃面板：SBFolderBackgroundView

static NSHashTable *gFolderIconImageViews, *gFolderBackgroundViews;

// 只撤销我们自己藏的底板（系统自己藏的不动）
static void XRKApplyFolderIconBackground(UIView *imageView) {
    XRKSetHiddenByUs(XRKViewIvar(imageView, @"backgroundView"), XRKOn(kXRKHideFolderBg));
}

%group XRKFolderBackground
%hook SBFolderIconImageView

- (void)layoutSubviews {
    %orig;
    XRKTrack(gFolderIconImageViews, self);
    XRKApplyFolderIconBackground(self);
}

%end

%hook SBFolderBackgroundView

- (void)setHidden:(BOOL)hidden {
    %orig(XRKNoteSystemHidden(self, hidden) || XRKOn(kXRKHideFolderBg));
}

- (void)didMoveToWindow {
    %orig;
    XRKTrack(gFolderBackgroundViews, self);
    if (XRKOn(kXRKHideFolderBg)) XRKReapplyHidden(self);
}

- (void)layoutSubviews {
    %orig;
    if (XRKOn(kXRKHideFolderBg) && !self.hidden) XRKReapplyHidden(self);
}

%end
%end

#pragma mark - 文件夹显示为第一个 App 的图标
// 做法（踩过坑才定下来的）：
// 1. 系统方法 setPageGridHidden: 隐藏九宫格、隐藏底板，开关文件夹的过渡里系统重建九宫格后也立刻再藏；
// 2. 第一个 App 的原图标作为 SBFolderIconImageView 自己 layer 的 sublayer（不是盖一个视图）；
// 3. iOS 17 的角标 SBIconBadgeView 就在 SBFolderIconImageView 里面，跟我们的图层是兄弟，
//    所以按 zPosition 排：系统子视图 0 < 第一个 App 图标 100 < 角标 200。
// 点它仍是打开文件夹；第一个 App 换了图标跟着换；文件夹的汇总角标照常显示。

#define XRK_FIRST_ICON_Z 100
#define XRK_BADGE_Z      200

static const void *kXRKFirstIconLayerKey = &kXRKFirstIconLayerKey;
static const void *kXRKFirstIconSourceKey = &kXRKFirstIconSourceKey;
static NSHashTable *gFirstIconImageViews;

static CALayer *XRKFirstIconLayer(UIView *view, BOOL create) {
    CALayer *layer = objc_getAssociatedObject(view, kXRKFirstIconLayerKey);
    if (!layer && create) {
        layer = [CALayer layer];
        layer.contentsGravity = kCAGravityResizeAspect;
        layer.zPosition = XRK_FIRST_ICON_Z;
        objc_setAssociatedObject(view, kXRKFirstIconLayerKey, layer, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return layer;
}

// 这个文件夹图标当前是否由我们接管（开关打开且图层已装上）
static BOOL XRKFirstIconActive(UIView *imageView) {
    return XRKOn(kXRKFolderFirstIcon) && XRKFirstIconLayer(imageView, NO).superlayer == imageView.layer;
}

static UIView *XRKBadgeForImageView(UIView *imageView) {
    for (UIView *v = imageView.superview; v; v = v.superview) {
        if ([v isKindOfClass:XRKClass("SBIconView")]) return XRKViewIvar(v, @"_accessoryView");
    }
    return nil;
}

static void XRKRestoreFolderIcon(SBFolderIconImageView *imageView) {
    CALayer *layer = XRKFirstIconLayer(imageView, NO);
    if (!layer.superlayer) return;
    XRKBadgeForImageView(imageView).layer.zPosition = 0;
    [layer removeFromSuperlayer];   // 先移除，XRKFirstIconActive 变 NO，下面才放得开九宫格
    objc_setAssociatedObject(imageView, kXRKFirstIconSourceKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [imageView setPageGridHidden:NO];
    XRKApplyFolderIconBackground(imageView);   // 底板交回"隐藏文件夹背景"开关决定
}

static UIImage *XRKFirstAppImage(SBFolderIconImageView *imageView) {
    @try {
        SBIcon *first = [[[imageView _folderIcon] folder] firstIcon];
        if (!first) return nil;
        XRKIconImageInfo info = [imageView iconImageInfo];
        if (info.size.width <= 0) info.size = imageView.bounds.size;
        if (info.scale <= 0) info.scale = UIScreen.mainScreen.scale;
        UIImage *image = [first respondsToSelector:@selector(iconImageWithInfo:)] ? [first iconImageWithInfo:info] : nil;
        if (!image && [first respondsToSelector:@selector(generateIconImageWithInfo:)]) image = [first generateIconImageWithInfo:info];
        return image;
    } @catch (__unused NSException *e) {
        return nil;
    }
}

// 接管时：藏九宫格和底板，角标抬到第一个 App 图标之上
static void XRKHideFolderGrid(SBFolderIconImageView *imageView) {
    if (![imageView isPageGridHidden]) [imageView setPageGridHidden:YES];
    XRKSetHiddenByUs(XRKViewIvar(imageView, @"backgroundView"), YES);
    XRKBadgeForImageView(imageView).layer.zPosition = XRK_BADGE_Z;
}

// reloadImage=NO：只调整位置和层级（排版时用，不重新取图）；YES：重新取第一个 App 的图标
// 取图要经过 SnowBoard 的 hook，比较贵，只在文件夹内容变化、开关切换、开关文件夹之后取
static void XRKApplyFolderFirstIconReloading(SBFolderIconImageView *imageView, BOOL reloadImage) {
    if (!reloadImage && XRKOn(kXRKFolderFirstIcon) && XRKFirstIconActive(imageView)) {
        CALayer *layer = XRKFirstIconLayer(imageView, NO);
        if (!CGRectEqualToRect(layer.frame, imageView.bounds)) {
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            layer.frame = imageView.bounds;
            [CATransaction commit];
        }
        XRKHideFolderGrid(imageView);
        return;
    }
    UIImage *icon = XRKOn(kXRKFolderFirstIcon) ? XRKFirstAppImage(imageView) : nil;
    if (!icon) {
        // 开关关闭、空文件夹、图片还没加载好：保持系统原样
        XRKRestoreFolderIcon(imageView);
        return;
    }

    CALayer *layer = XRKFirstIconLayer(imageView, YES);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    // 同一张源图不重复设置（layoutSubviews 调得很频繁）
    if (objc_getAssociatedObject(imageView, kXRKFirstIconSourceKey) != icon) {
        layer.contents = (__bridge id)icon.CGImage;
        layer.contentsScale = icon.scale;
        objc_setAssociatedObject(imageView, kXRKFirstIconSourceKey, icon, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    layer.frame = imageView.bounds;
    if (layer.superlayer != imageView.layer) [imageView.layer addSublayer:layer];
    [CATransaction commit];
    XRKHideFolderGrid(imageView);
}

static void XRKApplyFolderFirstIcon(SBFolderIconImageView *imageView) {
    XRKApplyFolderFirstIconReloading(imageView, YES);
}

%group XRKFolderFirstIcon
%hook SBFolderIconImageView

- (void)setPageGridHidden:(BOOL)hidden {
    %orig(hidden || XRKFirstIconActive(self));
}

// 开关文件夹的过渡开始时，系统会重建九宫格，立刻再藏一次
- (void)prepareToCrossfadeWithFloatyFolderView:(id)folderView allowFolderInteraction:(BOOL)allow {
    %orig;
    if (XRKFirstIconActive(self)) [self setPageGridHidden:YES];
}

- (void)_setupGridViewsInDefaultConfiguration {
    %orig;
    if (XRKFirstIconActive(self)) [self setPageGridHidden:YES];
}

- (void)layoutSubviews {
    %orig;
    XRKTrack(gFirstIconImageViews, self);
    XRKApplyFolderFirstIconReloading(self, NO);
}

// 文件夹内容变化（比如换了第一个 App）系统会调这个更新图标
- (void)updateImageAnimated:(BOOL)animated {
    %orig;
    XRKApplyFolderFirstIcon(self);
}

// 打开文件夹时系统把图标渐变成展开的面板，我们这层跟着淡出；关上时恢复
- (void)setFloatyFolderCrossfadeFraction:(double)fraction {
    %orig;
    if (!XRKFirstIconActive(self)) return;
    XRKFirstIconLayer(self, NO).opacity = 1.0 - fraction;
    if (![self isPageGridHidden]) [self setPageGridHidden:YES];
}

- (void)cleanupAfterFloatyFolderCrossfade {
    %orig;
    XRKFirstIconLayer(self, NO).opacity = 1.0;
    XRKApplyFolderFirstIcon(self);
}

%end

// 角标新建时 zPosition 是 0，要重新抬到第一个 App 图标之上
%hook SBIconView

- (void)_updateAccessoryViewAnimated:(BOOL)animated {
    %orig;
    UIView *badge = XRKViewIvar(self, @"_accessoryView");
    if (badge && XRKFirstIconActive(badge.superview)) badge.layer.zPosition = XRK_BADGE_Z;
}

%end
%end

#pragma mark - 初始化

void XRKInitFolders(void) {
    BOOL backgroundOK = XRKResponds("SBFolderIconImageView", @[@"backgroundView"]) && objc_getClass("SBFolderBackgroundView");
    BOOL firstIconOK = XRKResponds("SBFolderIconImageView", @[@"backgroundView", @"_folderIcon", @"iconImageInfo", @"updateImageAnimated:",
                                                             @"setPageGridHidden:", @"isPageGridHidden",
                                                             @"setFloatyFolderCrossfadeFraction:", @"cleanupAfterFloatyFolderCrossfade",
                                                             @"prepareToCrossfadeWithFloatyFolderView:allowFolderInteraction:",
                                                             @"_setupGridViewsInDefaultConfiguration"]) &&
                       XRKResponds("SBIconView", @[@"_updateAccessoryViewAnimated:"]) &&
                       XRKResponds("SBFolder", @[@"firstIcon"]) &&
                       XRKResponds("SBIcon", @[@"iconImageWithInfo:"]);
    XRKDebugLog(@"[Folders] background=%d firstIcon=%d", backgroundOK, firstIconOK);

    if (backgroundOK) {
        gFolderIconImageViews = [NSHashTable weakObjectsHashTable];
        gFolderBackgroundViews = [NSHashTable weakObjectsHashTable];
        %init(XRKFolderBackground);
        XRKAddRefresher(@[kXRKHideFolderBg], ^{
            for (UIView *v in gFolderIconImageViews.allObjects) XRKApplyFolderIconBackground(v);
            for (UIView *v in gFolderBackgroundViews.allObjects) XRKReapplyHidden(v);
        });
    }
    // 第一个 App 图标的刷新登记在背景之后：两者都改底板时，以它为准
    if (firstIconOK) {
        gFirstIconImageViews = [NSHashTable weakObjectsHashTable];
        %init(XRKFolderFirstIcon);
        XRKAddRefresher(@[kXRKFolderFirstIcon, kXRKHideFolderBg], ^{
            for (SBFolderIconImageView *v in gFirstIconImageViews.allObjects) XRKApplyFolderFirstIcon(v);
        });
    }
}
