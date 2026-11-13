// 主屏幕页面：隐藏负一屏、隐藏 App 资源库、隐藏页面圆点（Dock 相关在 Dock.x）
#import "XRKCommon.h"

@interface SBRootFolderController : NSObject
- (void)setLeadingCustomViewPageHidden:(BOOL)hidden;
@end

@interface SBIconListPageControl : UIView
@end

#pragma mark - 隐藏负一屏（第一页左边的小组件页）
// iOS 17 上只把页面设成隐藏不够：第一页继续右拉时系统会改用"浮层"弹出负一屏，所以：
//   1. 页面隐藏、页数算 0；
//   2. 拦住浮层弹出和过度右拉的处理；
//   3. ignoresOverscrollOnFirstPageOrientations 的含义是"这些方向禁止滚动视图原生回弹"，
//      原值 30（全禁），设成 0 才有跟最后一页一样的原生回弹。设反了就是完全拉不动。

static NSHashTable *gRootFolderControllers, *gRootFolderViews;

%group XRKTodayPage
%hook SBRootFolderController

- (BOOL)isLeadingCustomViewPageHidden {
    XRKTrack(gRootFolderControllers, self);
    return XRKOn(kXRKHideTodayPage) || %orig;
}

- (BOOL)isTodayViewPageHidden {
    return XRKOn(kXRKHideTodayPage) || %orig;
}

- (void)setLeadingCustomViewPageHidden:(BOOL)hidden {
    XRKTrack(gRootFolderControllers, self);
    %orig(hidden || XRKOn(kXRKHideTodayPage));
}

%end

%hook SBRootFolderView

- (BOOL)isLeadingCustomViewPageHidden {
    XRKTrack(gRootFolderViews, self);
    return XRKOn(kXRKHideTodayPage) || %orig;
}

- (unsigned long long)ignoresOverscrollOnFirstPageOrientations {
    return XRKOn(kXRKHideTodayPage) ? 0 : %orig;
}

- (BOOL)_shouldIgnoreOverscrollOnFirstPageForOrientation:(long long)orientation {
    return XRKOn(kXRKHideTodayPage) ? NO : %orig;
}

- (unsigned long long)_leadingCustomPageCount {
    return XRKOn(kXRKHideTodayPage) ? 0 : %orig;
}

%end

%hook SBIconController

- (void)presentTodayOverlayForIconManager:(id)manager {
    if (!XRKOn(kXRKHideTodayPage)) %orig;
}

- (void)iconManager:(id)manager rootFolderController:(id)controller didOverscrollOnFirstPageByAmount:(double)amount {
    if (!XRKOn(kXRKHideTodayPage)) %orig;
}

- (void)iconManager:(id)manager rootFolderController:(id)controller didEndOverscrollOnFirstPageWithVelocity:(double)velocity translation:(double)translation {
    if (!XRKOn(kXRKHideTodayPage)) %orig;
}

%end
%end

#pragma mark - 隐藏 App 资源库（最后一页右边）
// SpringBoard 启动时读取，切换后需要注销生效（AppLibraryDisabler 做的是同一件事）

%group XRKAppLibrary
%hook SBIconController

- (BOOL)isAppLibrarySupported {
    return XRKOn(kXRKHideAppLibrary) ? NO : %orig;
}

- (BOOL)isAppLibraryAllowed {
    return XRKOn(kXRKHideAppLibrary) ? NO : %orig;
}

%end
%end

#pragma mark - 隐藏页面圆点（iOS 17 关掉搜索按钮后底部显示的就是它）

static NSHashTable *gPageControls;

%group XRKPageDots
%hook SBIconListPageControl

- (void)setHidden:(BOOL)hidden {
    %orig(XRKNoteSystemHidden(self, hidden) || XRKOn(kXRKHidePageDots));
}

- (void)didMoveToWindow {
    %orig;
    XRKTrack(gPageControls, self);
    if (XRKOn(kXRKHidePageDots)) XRKReapplyHidden(self);
}

%end
%end

#pragma mark - 初始化

void XRKInitHomeScreen(void) {
    BOOL todayOK = XRKResponds("SBRootFolderController", @[@"isLeadingCustomViewPageHidden", @"isTodayViewPageHidden",
                                                           @"setLeadingCustomViewPageHidden:"]) &&
                   XRKResponds("SBRootFolderView", @[@"isLeadingCustomViewPageHidden", @"ignoresOverscrollOnFirstPageOrientations",
                                                     @"_shouldIgnoreOverscrollOnFirstPageForOrientation:", @"_leadingCustomPageCount"]) &&
                   XRKResponds("SBIconController", @[@"presentTodayOverlayForIconManager:",
                                                     @"iconManager:rootFolderController:didOverscrollOnFirstPageByAmount:",
                                                     @"iconManager:rootFolderController:didEndOverscrollOnFirstPageWithVelocity:translation:"]);
    BOOL libraryOK = XRKResponds("SBIconController", @[@"isAppLibrarySupported", @"isAppLibraryAllowed"]);
    BOOL dotsOK = objc_getClass("SBIconListPageControl") != nil;
    XRKDebugLog(@"[HomeScreen] today=%d appLibrary=%d dots=%d", todayOK, libraryOK, dotsOK);

    if (todayOK) {
        gRootFolderControllers = [NSHashTable weakObjectsHashTable];
        gRootFolderViews = [NSHashTable weakObjectsHashTable];
        %init(XRKTodayPage);
        XRKAddRefresher(@[kXRKHideTodayPage], ^{
            BOOL hide = XRKOn(kXRKHideTodayPage);
            for (SBRootFolderController *c in gRootFolderControllers.allObjects) [c setLeadingCustomViewPageHidden:hide];
            for (UIView *v in gRootFolderViews.allObjects) {
                [v setNeedsLayout];
                [v layoutIfNeeded];
            }
        });
    }
    if (libraryOK) {
        %init(XRKAppLibrary);
    }
    if (dotsOK) {
        gPageControls = [NSHashTable weakObjectsHashTable];
        %init(XRKPageDots);
        // 关闭时还给系统决定（单页、显示搜索按钮时系统自己会藏）
        XRKAddRefresher(@[kXRKHidePageDots], ^{
            for (UIView *v in gPageControls.allObjects) XRKReapplyHidden(v);
        });
    }
}
