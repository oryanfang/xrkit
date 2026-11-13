// 插件各模块共用的小工具（只给 Tweak 用，设置面板不引用）
#pragma once
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "XRKPrefs.h"
#import "XRKDebug.h"
#import "XRKKeys.h"

#pragma mark - 偏好

static inline BOOL XRKOn(NSString *key) {
    return [[XRKPrefs shared] boolForKey:key fallback:NO];
}

static inline double XRKDouble(NSString *key, double fallback, double min, double max) {
    double v = [[XRKPrefs shared] doubleForKey:key fallback:fallback];
    return MAX(min, MIN(max, v));
}

// 插件自己往偏好里写（SpringBoard 里：锁定的 App、卡死保护改回系统样式），写完立刻同步
static inline void XRKWritePref(NSString *key, id value) {
    CFStringRef domain = (__bridge CFStringRef)XRK_PREFS_DOMAIN;
    CFPreferencesSetValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
}

// 多任务排列样式（swStyle）：0 系统堆叠 / 2 网格 / 3 iPad（GridFull.x）
typedef NS_ENUM(long long, XRKSwitcherStyle) {
    XRKSwitcherStyleSystem = 0,
    XRKSwitcherStyleGrid = 2,
    XRKSwitcherStyleiPad = 3,
};

static inline XRKSwitcherStyle XRKSwitcherStyleSetting(void) {
    return (XRKSwitcherStyle)XRKDouble(kXRKSwStyle, 0, 0, 3);
}

#pragma mark - 运行时

// 取私有成员视图，取不到或不是视图返回 nil，不会崩溃。
// 以 "_" 开头的按成员变量直接读（按 类+名字 缓存查找结果，排版等高频路径里用），其余走 KVC（方法名，比如 backgroundView）
UIView *XRKViewIvar(id object, NSString *name);

// 按名字取类，结果缓存在调用处（高频路径里代替 objc_getClass）
#define XRKClass(name) ({ static Class _xrk_cls; if (!_xrk_cls) _xrk_cls = objc_getClass(name); _xrk_cls; })

// 类存在且所有实例方法都存在才返回 YES。只给检查通过的功能装 hook，类名/方法在新系统变了也不会让 SpringBoard 崩
static inline BOOL XRKResponds(const char *className, NSArray<NSString *> *selectors) {
    Class cls = objc_getClass(className);
    if (!cls) return NO;
    for (NSString *sel in selectors) {
        if (![cls instancesRespondToSelector:NSSelectorFromString(sel)]) return NO;
    }
    return YES;
}

// 同上，检查类方法
static inline BOOL XRKClassResponds(const char *className, NSArray<NSString *> *selectors) {
    Class cls = objc_getClass(className);
    if (!cls) return NO;
    for (NSString *sel in selectors) {
        if (![cls respondsToSelector:NSSelectorFromString(sel)]) return NO;
    }
    return YES;
}

// 对象没有这个方法时返回 nil / fallback，不崩溃（只用于无参数、返回对象 / BOOL 的方法）
static inline id XRKSafeCall(id obj, NSString *selName) {
    SEL sel = NSSelectorFromString(selName);
    if (!obj || ![obj respondsToSelector:sel]) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(obj, sel);
}

static inline BOOL XRKSafeBool(id obj, NSString *selName, BOOL fallback) {
    SEL sel = NSSelectorFromString(selName);
    if (!obj || ![obj respondsToSelector:sel]) return fallback;
    return ((BOOL (*)(id, SEL))objc_msgSend)(obj, sel);
}

// SpringBoard 图标图片参数（SBIcon -iconImageWithInfo:、SBIconListGridLayoutConfiguration -iconImageInfo 等）
typedef struct {
    CGSize size;
    double scale;
    double continuousCornerRadius;
} XRKIconImageInfo;

#pragma mark - 改设置后立即刷新

// 记录出现过的对象（弱引用），改设置后能立即刷新，不用等系统下次布局
static inline void XRKTrack(NSHashTable *table, id object) {
    if (table && object) [table addObject:object];
}

// 模块登记"改设置后要做的刷新"，收到通知时在主线程按登记顺序执行。
// keys：这个刷新关心的偏好键，只有其中某个值变了才执行（改别的设置不会牵连它）；传 nil 表示每次都执行
void XRKAddRefresher(NSArray<NSString *> *keys, void (^refresher)(void));
void XRKRunRefreshers(void);

#pragma mark - 显示 / 隐藏：关掉功能时还给系统

// hook 了 setHidden: 的视图：记下系统自己想要的值（hook 里 %orig(XRKNoteSystemHidden(self, hidden) || 我们要藏)），
// 我们要藏 / 要恢复时都调 XRKReapplyHidden（用系统值再走一遍 hook），关掉功能时就回到系统原本的状态，不会把系统藏着的东西强行显示出来
BOOL XRKNoteSystemHidden(UIView *view, BOOL hidden);
BOOL XRKSystemHidden(UIView *view);
void XRKReapplyHidden(UIView *view);

// 没 hook setHidden: 的视图：只撤销我们自己设的 hidden，系统自己藏的不去动
void XRKSetHiddenByUs(UIView *view, BOOL hide);

#pragma mark - 各模块入口（各在自己的 .x 文件里，Tweak.x 按顺序调用）

void XRKInitHomeBar(void);
void XRKInitHomeScreen(void);
void XRKInitDock(void);
void XRKInitDockRunning(void);
void XRKInitIcons(void);
void XRKInitFolders(void);
void XRKInitIdleFade(void);
void XRKInitControlCenter(void);
void XRKInitLockScreen(void);
void XRKInitSwitcher(void);
void XRKInitScreenshot(void);
void XRKInitGridFull(void);
BOOL XRKInitCCModules(void);          // 控制中心模块加载器，返回是否启用（SpringBoard + 设置）
void XRKInitCCModulesSettings(void);  // 设置页的模块名字 / 图标（只在设置进程）

#pragma mark - 模块之间共用

// Dock 布局（Dock.x ↔ DockRunning.x）
unsigned long long XRKDockRecentSlots(void);                // 竖线右边显示几个运行中的 App
void XRKDockApplyListTransform(UIView *list, BOOL reset);   // 复位 / 套上 DockRunning.x 算好的图标列表缩放
