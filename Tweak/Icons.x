// 图标：隐藏图标名称、隐藏通知角标、角标改成图标主色调、下载中显示百分比
#import "XRKCommon.h"

@interface SBIconView : UIView
- (void)setLabelHidden:(BOOL)hidden;
- (void)_updateAccessoryViewAnimated:(BOOL)animated;
@end

@interface SBIconBadgeView : UIView
@end

@interface SBIconProgressView : UIView
- (double)displayedFraction;
- (long long)displayedState;
@end

@interface NSObject (XRKIconsPrivate)
- (id)_folderIcon;
- (id)folder;
- (id)firstIcon;
- (XRKIconImageInfo)iconImageInfo;
- (UIImage *)iconImageWithInfo:(XRKIconImageInfo)info;
- (UIImage *)displayedImage;
- (UIImage *)contentsImage;
@end

static NSHashTable *gIconViews;

#pragma mark - 隐藏图标名称
// 记下系统自己要不要显示名称（Dock 等地方本来就不显示），关掉功能时还给系统，不一律显示

static const void *kXRKSystemLabelHiddenKey = &kXRKSystemLabelHiddenKey;
static BOOL gLabelsHookOK;

static BOOL XRKSystemLabelHidden(UIView *iconView) {
    NSNumber *v = objc_getAssociatedObject(iconView, kXRKSystemLabelHiddenKey);
    return v ? v.boolValue : XRKSafeBool(iconView, @"isLabelHidden", NO);   // 没记过 = 还没碰过，当前值就是系统的
}

static void XRKReapplyLabel(SBIconView *iconView) {
    if (gLabelsHookOK) [iconView setLabelHidden:XRKSystemLabelHidden(iconView)];
}

// 所有图标视图都记下来，几个功能共用
%group XRKIconTracking
%hook SBIconView

- (void)didMoveToWindow {
    %orig;
    XRKTrack(gIconViews, self);
    if (XRKOn(kXRKHideIconLabels)) XRKReapplyLabel(self);
}

%end
%end

%group XRKIconLabels
%hook SBIconView

- (void)setLabelHidden:(BOOL)hidden {
    objc_setAssociatedObject(self, kXRKSystemLabelHiddenKey, @(hidden), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    %orig(hidden || XRKOn(kXRKHideIconLabels));
}

%end
%end

#pragma mark - 隐藏通知角标
// 角标是 SBIconView 的"附件视图"，让它认为不该显示即可。
// 注意：文件夹显示第一个 App 图标时，文件夹的汇总角标要照常显示（免得漏看消息），这里不做特殊处理。

%group XRKBadges
%hook SBIconView

- (BOOL)shouldShowAccessoryView {
    return XRKOn(kXRKHideBadges) ? NO : %orig;
}

%end
%end

#pragma mark - 角标改成图标主色调
// SnowBoard 已经 hook 了角标图片的生成（+badgeBackgroundColor、_createImageForText:…），
// 所以不跟它抢那几个方法：等图片生成好、放进视图之后，再把它染色。
//   _backgroundView：红色圆底图 → 模板图 + 主色
//   _textView / _incomingTextView：数字图 → 模板图 + 黑或白（看底色亮度）

static NSHashTable *gBadgeViews;
static NSCache *gDominantColors;   // 图标图片 → 主色
static NSCache *gFolderColors;     // 文件夹第一个 App 的图标对象 → 主色（文件夹每次取图都是新图片，按图片缓存命中不了）

// 主色调：缩到 20×20，按色相分 12 段，只统计"有颜色"的像素（饱和度和亮度都够），
// 取权重最大的一段求平均；整张图都是黑白灰时，退回整体平均色。
static UIColor *XRKDominantColor(UIImage *image) {
    if (!image.CGImage) return nil;
    UIColor *cached = [gDominantColors objectForKey:image];
    if (cached) return cached;

    enum { side = 20 };
    uint8_t pixels[side * side * 4];
    memset(pixels, 0, sizeof(pixels));
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(pixels, side, side, 8, side * 4, space,
                                             kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(space);
    if (!ctx) return nil;
    CGContextDrawImage(ctx, CGRectMake(0, 0, side, side), image.CGImage);
    CGContextRelease(ctx);

    double bucketWeight[12] = {0}, bucketR[12] = {0}, bucketG[12] = {0}, bucketB[12] = {0};
    double allR = 0, allG = 0, allB = 0, allCount = 0;
    for (int i = 0; i < side * side; i++) {
        double a = pixels[i * 4 + 3] / 255.0;
        if (a < 0.5) continue;
        double r = pixels[i * 4] / 255.0 / a, g = pixels[i * 4 + 1] / 255.0 / a, b = pixels[i * 4 + 2] / 255.0 / a;
        allR += r; allG += g; allB += b; allCount++;
        double mx = MAX(r, MAX(g, b)), mn = MIN(r, MIN(g, b)), delta = mx - mn;
        double bri = mx, sat = mx > 0 ? delta / mx : 0;
        if (sat < 0.25 || bri < 0.25) continue;
        double h = r == mx ? (g - b) / delta : (g == mx ? 2 + (b - r) / delta : 4 + (r - g) / delta);   // 0～6
        h = fmod(h + 6, 6) / 6;
        int bucket = MIN(11, (int)(h * 12));
        double w = sat * bri;
        bucketWeight[bucket] += w;
        bucketR[bucket] += r * w; bucketG[bucket] += g * w; bucketB[bucket] += b * w;
    }
    if (allCount == 0) return nil;

    int best = 0;
    for (int i = 1; i < 12; i++) if (bucketWeight[i] > bucketWeight[best]) best = i;
    UIColor *color;
    if (bucketWeight[best] > allCount * 0.05) {
        double w = bucketWeight[best];
        color = [UIColor colorWithRed:bucketR[best] / w green:bucketG[best] / w blue:bucketB[best] / w alpha:1];
    } else {
        color = [UIColor colorWithRed:allR / allCount green:allG / allCount blue:allB / allCount alpha:1];
    }
    [gDominantColors setObject:color forKey:image];
    return color;
}

// 角标所在图标的主色；文件夹取第一个 App 的图标。
// 文件夹要现取第一个 App 的图标图片（经过 SnowBoard 的 hook，比较贵），所以按"第一个 App 的图标对象"缓存颜色，
// 角标每次排版都来问也只算一次
static UIColor *XRKBadgeIconColorFor(UIView *badge) {
    UIView *iconView = badge.superview;
    while (iconView && ![iconView isKindOfClass:XRKClass("SBIconView")]) iconView = iconView.superview;
    UIView *imageView = XRKViewIvar(iconView, @"_iconImageView");
    if (!imageView) return nil;
    @try {
        if ([imageView respondsToSelector:@selector(_folderIcon)]) {
            id first = [[[imageView _folderIcon] folder] firstIcon];
            if (!first) return nil;
            UIColor *cached = [gFolderColors objectForKey:first];
            if (cached) return cached;
            XRKIconImageInfo info = [imageView iconImageInfo];
            if (info.size.width <= 0) info.size = CGSizeMake(60, 60);
            if (info.scale <= 0) info.scale = UIScreen.mainScreen.scale;
            UIImage *image = [first respondsToSelector:@selector(iconImageWithInfo:)] ? [first iconImageWithInfo:info] : nil;
            UIColor *color = XRKDominantColor(image);
            if (color) [gFolderColors setObject:color forKey:first];
            return color;
        }
        UIImage *image = [imageView respondsToSelector:@selector(displayedImage)] ? [imageView displayedImage] : nil;
        if (!image && [imageView respondsToSelector:@selector(contentsImage)]) image = [imageView contentsImage];
        return XRKDominantColor(image);
    } @catch (__unused NSException *e) {
        return nil;
    }
}

static void XRKSetTemplate(UIImageView *view, UIColor *tint) {
    if (![view isKindOfClass:UIImageView.class] || !view.image) return;
    if (tint) {
        if (view.image.renderingMode != UIImageRenderingModeAlwaysTemplate) {
            view.image = [view.image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        }
        view.tintColor = tint;
    } else if (view.image.renderingMode == UIImageRenderingModeAlwaysTemplate) {
        view.image = [view.image imageWithRenderingMode:UIImageRenderingModeAutomatic];
        view.tintColor = nil;
    }
}

static void XRKApplyBadgeColor(UIView *badge) {
    UIImageView *background = (UIImageView *)XRKViewIvar(badge, @"_backgroundView");
    NSArray *texts = @[XRKViewIvar(badge, @"_textView") ?: NSNull.null, XRKViewIvar(badge, @"_incomingTextView") ?: NSNull.null];

    UIColor *color = XRKOn(kXRKBadgeIconColor) ? XRKBadgeIconColorFor(badge) : nil;
    UIColor *textColor = nil;
    if (color) {
        CGFloat r = 0, g = 0, b = 0;
        [color getRed:&r green:&g blue:&b alpha:NULL];
        textColor = (0.299 * r + 0.587 * g + 0.114 * b) > 0.62 ? UIColor.blackColor : UIColor.whiteColor;
    }
    XRKSetTemplate(background, color);
    for (id text in texts) {
        if (text != NSNull.null) XRKSetTemplate(text, textColor);
    }
}

%group XRKBadgeColor
%hook SBIconBadgeView

- (void)layoutSubviews {
    %orig;
    XRKTrack(gBadgeViews, self);
    XRKApplyBadgeColor(self);
}

// 数字变化时系统会换一张新的数字图
- (void)_crossfadeToTextImage:(id)image animator:(id)animator {
    %orig;
    XRKApplyBadgeColor(self);
}

- (void)configureForIcon:(id)icon infoProvider:(id)provider {
    %orig;
    XRKApplyBadgeColor(self);
}

%end
%end

#pragma mark - 下载中显示百分比
// 系统用 SBIconProgressView 画下载进度的圆圈；在它正中间叠一个百分比数字

static const void *kXRKPercentLabelKey = &kXRKPercentLabelKey;
static NSHashTable *gProgressViews;

static void XRKUpdatePercentLabel(SBIconProgressView *progress) {
    UILabel *label = objc_getAssociatedObject(progress, kXRKPercentLabelKey);
    double fraction = progress.displayedFraction;
    BOOL show = XRKOn(kXRKDownloadPercent) && progress.displayedState != 0 && fraction > 0.001 && fraction < 0.999;
    if (!show) {
        label.hidden = YES;
        return;
    }
    if (!label) {
        label = [UILabel new];
        label.textAlignment = NSTextAlignmentCenter;
        label.textColor = UIColor.whiteColor;
        label.userInteractionEnabled = NO;
        label.layer.shadowColor = UIColor.blackColor.CGColor;
        label.layer.shadowOpacity = 0.6;
        label.layer.shadowRadius = 2;
        label.layer.shadowOffset = CGSizeZero;
        objc_setAssociatedObject(progress, kXRKPercentLabelKey, label, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    CGFloat side = MIN(progress.bounds.size.width, progress.bounds.size.height);
    label.font = [UIFont monospacedDigitSystemFontOfSize:MAX(10, side * 0.2) weight:UIFontWeightBold];
    label.text = [NSString stringWithFormat:@"%.0f%%", floor(fraction * 100)];
    label.frame = progress.bounds;
    label.hidden = NO;
    if (label.superview != progress) [progress addSubview:label];
}

%group XRKDownloadPercent
%hook SBIconProgressView

- (void)setDisplayedFraction:(double)fraction {
    %orig;
    XRKUpdatePercentLabel(self);
}

- (void)setDisplayedState:(long long)state {
    %orig;
    XRKTrack(gProgressViews, self);
    XRKUpdatePercentLabel(self);
}

- (void)layoutSubviews {
    %orig;
    XRKTrack(gProgressViews, self);
    XRKUpdatePercentLabel(self);
}

%end
%end

#pragma mark - 初始化

void XRKInitIcons(void) {
    if (!objc_getClass("SBIconView")) return;
    BOOL labelsOK = XRKResponds("SBIconView", @[@"setLabelHidden:"]);
    BOOL badgesOK = XRKResponds("SBIconView", @[@"shouldShowAccessoryView", @"_updateAccessoryViewAnimated:"]);
    BOOL badgeColorOK = XRKResponds("SBIconBadgeView", @[@"layoutSubviews", @"_crossfadeToTextImage:animator:",
                                                         @"configureForIcon:infoProvider:"]);
    BOOL percentOK = XRKResponds("SBIconProgressView", @[@"displayedFraction", @"displayedState",
                                                         @"setDisplayedFraction:", @"setDisplayedState:"]);
    XRKDebugLog(@"[Icons] labels=%d badges=%d badgeColor=%d downloadPercent=%d", labelsOK, badgesOK, badgeColorOK, percentOK);

    gIconViews = [NSHashTable weakObjectsHashTable];
    gLabelsHookOK = labelsOK;
    %init(XRKIconTracking);
    if (labelsOK) {
        %init(XRKIconLabels);
        XRKAddRefresher(@[kXRKHideIconLabels], ^{
            for (SBIconView *v in gIconViews.allObjects) XRKReapplyLabel(v);
        });
    }
    if (badgesOK) {
        %init(XRKBadges);
        XRKAddRefresher(@[kXRKHideBadges], ^{
            for (SBIconView *v in gIconViews.allObjects) [v _updateAccessoryViewAnimated:YES];
        });
    }
    if (badgeColorOK) {
        gBadgeViews = [NSHashTable weakObjectsHashTable];
        gDominantColors = [NSCache new];
        gDominantColors.countLimit = 300;
        gFolderColors = [NSCache new];
        gFolderColors.countLimit = 100;
        %init(XRKBadgeColor);
        // 重新打开时清掉缓存（换了图标主题，关一下再开就能重算）
        XRKAddRefresher(@[kXRKBadgeIconColor], ^{
            [gDominantColors removeAllObjects];
            [gFolderColors removeAllObjects];
            for (UIView *badge in gBadgeViews.allObjects) XRKApplyBadgeColor(badge);
        });
    }
    if (percentOK) {
        gProgressViews = [NSHashTable weakObjectsHashTable];
        %init(XRKDownloadPercent);
        XRKAddRefresher(@[kXRKDownloadPercent], ^{
            for (SBIconProgressView *p in gProgressViews.allObjects) XRKUpdatePercentLabel(p);
        });
    }
}
