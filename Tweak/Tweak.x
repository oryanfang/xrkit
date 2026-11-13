// 入口：读偏好、监听设置变化、按总开关初始化各模块
// 每个功能区一个文件，对外暴露 XRKInitXxx()（声明在 XRKCommon.h），
// 模块内部用 XRKAddRefresher(关心的偏好键, block) 登记"改设置后要刷新什么"，只有那几个键变了才跑。
#import "XRKCommon.h"
#import <dlfcn.h>

static BOOL gModulesLoaded = NO;

static void XRKPrefsChanged(CFNotificationCenterRef center, void *observer,
                            CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    [[XRKPrefs shared] reload];
    if (!gModulesLoaded) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        XRKRunRefreshers();
    });
}

%ctor {
    @autoreleasepool {
        XRKPrefs *prefs = [XRKPrefs shared];
        [prefs reload];

        // 「设置」App 里只跑控制中心模块加载器（设置 › 控制中心 要和 SpringBoard 看到同一份模块和配置）
        if ([NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.Preferences"]) {
            if (!prefs.enabled) return;
            dlopen("/System/Library/PrivateFrameworks/ControlCenterServices.framework/ControlCenterServices", RTLD_NOW);
            if (XRKInitCCModules()) XRKInitCCModulesSettings();
            return;
        }

        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
                                        XRKPrefsChanged, CFSTR(XRK_PREFS_CHANGED), NULL,
                                        CFNotificationSuspensionBehaviorCoalesce);

        XRKDebugReset();
        XRKDebugLog(@"xrkit loaded into %@ (pid %d) at %@, enabled=%d",
                    NSProcessInfo.processInfo.processName, getpid(), [NSDate date], prefs.enabled);

        // 总开关关闭时不安装任何 hook（切换总开关需要注销生效）
        if (!prefs.enabled) return;

        XRKInitHomeBar();
        XRKInitHomeScreen();
        XRKInitDock();
        XRKInitDockRunning();
        XRKInitIcons();
        XRKInitFolders();
        XRKInitIdleFade();
        XRKInitControlCenter();
        XRKInitLockScreen();
        XRKInitSwitcher();
        XRKInitScreenshot();
        XRKInitGridFull();
        XRKInitCCModules();
        gModulesLoaded = YES;

        XRKDebugStartCPUSampling();
        XRKDebugStartScreenshotWatcher();
    }
}
