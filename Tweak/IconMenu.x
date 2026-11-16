// 主屏幕图标：长按菜单加「复制 Bundle ID / 强制退出 / 重新打开」、点按图标时震动
//
// 长按菜单（iOS 17，符号确认）：SBIconView -applicationShortcutItems 返回 App 自己的快捷项（SBSApplicationShortcutItem），
// 系统再在后面加「编辑主屏幕」「分享 App」「移除 App」；点按某项走 +[SBIconView activateShortcut:withBundleIdentifier:forIconView:]。
// 我们往 applicationShortcutItems 后面追加自己的项（type 以 com.xyrith.xrkit. 开头），在 activateShortcut 里认出来自己处理。
//
// 结束 App：FBSSystemService -terminateApplication:forReason:andReport:withDescription:，再把多任务里的卡片删掉（跟手动划掉一样）。
// 重新打开：结束后等进程真正退出（最多 2 秒），再用 SBMainWorkspace 打开（见 DockRunning.x 的说明，别用 LSApplicationWorkspace）。
#import "XRKCommon.h"

@interface SBSApplicationShortcutItem : NSObject
- (NSString *)type;
- (void)setType:(NSString *)type;
- (void)setLocalizedTitle:(NSString *)title;
- (void)setIcon:(id)icon;
- (void)setBundleIdentifierToLaunch:(NSString *)bid;
@end

@interface SBSApplicationShortcutSystemPrivateIcon : NSObject
- (instancetype)initWithSystemImageName:(NSString *)name;
@end

@interface SBIconView : UIView
- (id)icon;
- (BOOL)isEditing;
@end

@interface NSObject (XRKIconMenu)
+ (instancetype)sharedInstance;
+ (instancetype)sharedService;
- (NSString *)applicationBundleID;
- (id)applicationWithBundleIdentifier:(NSString *)bid;
- (id)processState;
- (int)pid;
- (NSArray *)recentAppLayouts;
- (NSArray *)allItems;
- (NSString *)bundleIdentifier;
- (void)deleteAppLayoutForDisplayItem:(id)item;
- (void)terminateApplication:(NSString *)bid forReason:(int)reason andReport:(BOOL)report withDescription:(NSString *)desc;
- (id)initWithApplicationForMainDisplay:(id)application;
- (id)createRequestForApplicationActivation:(id)entity options:(unsigned long long)options;
- (BOOL)executeTransitionRequest:(id)request;
@end

static NSString *const kTypeCopy = @"com.xyrith.xrkit.copy-bundle-id";
static NSString *const kTypeQuit = @"com.xyrith.xrkit.force-quit";
static NSString *const kTypeRelaunch = @"com.xyrith.xrkit.relaunch";

#pragma mark - 动作

static int XRKAppPid(NSString *bid) {
    id app = [[objc_getClass("SBApplicationController") sharedInstance] applicationWithBundleIdentifier:bid];
    id state = [app respondsToSelector:@selector(processState)] ? [app processState] : nil;
    return [state respondsToSelector:@selector(pid)] ? [state pid] : 0;
}

static void XRKQuitApp(NSString *bid) {
    @try {
        id service = [objc_getClass("FBSSystemService") sharedService];
        [service terminateApplication:bid forReason:1 andReport:NO withDescription:@"xrkit force quit"];
        id coord = [objc_getClass("SBMainSwitcherControllerCoordinator") sharedInstance];
        for (id layout in [[coord recentAppLayouts] copy]) {
            for (id item in [[layout allItems] copy]) {
                if ([item respondsToSelector:@selector(bundleIdentifier)] && [[item bundleIdentifier] isEqualToString:bid]) [coord deleteAppLayoutForDisplayItem:item];
            }
        }
    } @catch (NSException *e) {
        XRKDebugLog(@"[IconMenu] quit %@ failed: %@", bid, e.reason);
    }
}

static void XRKOpenApp(NSString *bid) {
    @try {
        id app = [[objc_getClass("SBApplicationController") sharedInstance] applicationWithBundleIdentifier:bid];
        id entity = app ? [[objc_getClass("SBDeviceApplicationSceneEntity") alloc] initWithApplicationForMainDisplay:app] : nil;
        id workspace = [objc_getClass("SBMainWorkspace") sharedInstance];
        id request = entity ? [workspace createRequestForApplicationActivation:entity options:0] : nil;
        BOOL ok = request ? [workspace executeTransitionRequest:request] : NO;
        XRKDebugLog(@"[IconMenu] relaunch %@ ok=%d", bid, ok);
    } @catch (NSException *e) {
        XRKDebugLog(@"[IconMenu] relaunch %@ failed: %@", bid, e.reason);
    }
}

// 等进程退出再打开；每 0.1 秒看一次，最多 2 秒
static void XRKOpenWhenQuit(NSString *bid, int tries) {
    if (XRKAppPid(bid) <= 0 || tries >= 20) {
        XRKOpenApp(bid);
        return;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ XRKOpenWhenQuit(bid, tries + 1); });
}

static SBSApplicationShortcutItem *XRKMenuItem(NSString *type, NSString *title, NSString *symbol, NSString *bid) {
    SBSApplicationShortcutItem *item = [objc_getClass("SBSApplicationShortcutItem") new];
    [item setType:type];
    [item setLocalizedTitle:title];
    [item setIcon:[[objc_getClass("SBSApplicationShortcutSystemPrivateIcon") alloc] initWithSystemImageName:symbol]];
    [item setBundleIdentifierToLaunch:bid];
    return item;
}

static BOOL XRKZh(void) {
    return [NSLocale.preferredLanguages.firstObject hasPrefix:@"zh"];
}

#pragma mark - 长按菜单

%group XRKIconMenu
%hook SBIconView

- (NSArray *)applicationShortcutItems {
    NSArray *items = %orig;
    BOOL copy = XRKOn(kXRKIconMenuCopyID), quit = XRKOn(kXRKIconMenuQuit), relaunch = XRKOn(kXRKIconMenuRelaunch);
    if (!copy && !quit && !relaunch) return items;
    id icon = [self icon];
    NSString *bid = [icon respondsToSelector:@selector(applicationBundleID)] ? [icon applicationBundleID] : nil;
    if (!bid.length || [self isEditing]) return items;
    BOOL zh = XRKZh();
    NSMutableArray *out = [items ?: @[] mutableCopy];
    BOOL running = XRKAppPid(bid) > 0;
    if (relaunch && running) [out addObject:XRKMenuItem(kTypeRelaunch, zh ? @"重新打开" : @"Relaunch", @"arrow.clockwise", bid)];
    if (quit && running) [out addObject:XRKMenuItem(kTypeQuit, zh ? @"强制退出" : @"Force Quit", @"xmark.circle", bid)];
    if (copy) [out addObject:XRKMenuItem(kTypeCopy, zh ? @"复制 Bundle ID" : @"Copy Bundle ID", @"doc.on.doc", bid)];
    return out;
}

+ (void)activateShortcut:(SBSApplicationShortcutItem *)item withBundleIdentifier:(NSString *)bid forIconView:(id)iconView {
    NSString *type = [item respondsToSelector:@selector(type)] ? [item type] : nil;
    if (![type hasPrefix:@"com.xyrith.xrkit."] || !bid.length) {
        %orig;
        return;
    }
    XRKDebugLog(@"[IconMenu] %@ %@", type, bid);
    if ([type isEqualToString:kTypeCopy]) {
        UIPasteboard.generalPasteboard.string = bid;
    } else if ([type isEqualToString:kTypeQuit]) {
        XRKQuitApp(bid);
    } else if ([type isEqualToString:kTypeRelaunch]) {
        XRKQuitApp(bid);
        XRKOpenWhenQuit(bid, 0);
    }
}

%end
%end

#pragma mark - 点按图标震动

static UIImpactFeedbackGenerator *gXRKTapHaptic;
static NSInteger gXRKTapHapticStyle = -1;
static CFAbsoluteTime gXRKLastTapHaptic;

static void XRKTapHaptic(SBIconView *iconView) {
    NSInteger level = lround(XRKDouble(kXRKIconTapHaptic, 0, 0, 3));
    if (level == 0) return;
    if ([iconView respondsToSelector:@selector(isEditing)] && [iconView isEditing]) return;
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (now - gXRKLastTapHaptic < 0.15) return;   // iconTapped: 和 iconTapped:modifierFlags: 可能一前一后都走到
    gXRKLastTapHaptic = now;
    UIImpactFeedbackStyle style = level == 1 ? UIImpactFeedbackStyleLight : level == 2 ? UIImpactFeedbackStyleMedium : UIImpactFeedbackStyleRigid;
    if (!gXRKTapHaptic || gXRKTapHapticStyle != style) {
        gXRKTapHaptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:style];
        gXRKTapHapticStyle = style;
    }
    [gXRKTapHaptic impactOccurred];
}

%group XRKTapHaptic
%hook SBHIconManager

- (void)iconTapped:(id)iconView {
    XRKTapHaptic(iconView);
    %orig;
}

- (void)iconTapped:(id)iconView modifierFlags:(long long)flags {
    XRKTapHaptic(iconView);
    %orig;
}

%end
%end

#pragma mark - 初始化

void XRKInitIconMenu(void) {
    BOOL menuOK = XRKResponds("SBIconView", @[@"applicationShortcutItems", @"icon", @"isEditing"]) &&
                  XRKClassResponds("SBIconView", @[@"activateShortcut:withBundleIdentifier:forIconView:"]) &&
                  XRKResponds("SBSApplicationShortcutItem", @[@"setType:", @"setLocalizedTitle:", @"setIcon:", @"setBundleIdentifierToLaunch:"]) &&
                  XRKResponds("SBSApplicationShortcutSystemPrivateIcon", @[@"initWithSystemImageName:"]) &&
                  XRKResponds("FBSSystemService", @[@"terminateApplication:forReason:andReport:withDescription:"]) &&
                  XRKClassResponds("FBSSystemService", @[@"sharedService"]) &&
                  XRKResponds("SBMainWorkspace", @[@"createRequestForApplicationActivation:options:", @"executeTransitionRequest:"]);
    BOOL hapticOK = XRKResponds("SBHIconManager", @[@"iconTapped:", @"iconTapped:modifierFlags:"]);
    XRKDebugLog(@"[IconMenu] menu=%d haptic=%d", menuOK, hapticOK);
    if (menuOK) %init(XRKIconMenu);
    if (hapticOK) %init(XRKTapHaptic);
}
