#import "XRKDebug.h"
#import <sys/resource.h>

void XRKDebugReset(void) {
#if XRK_DEBUG
    [@"" writeToFile:XRK_DEBUG_FILE atomically:YES encoding:NSUTF8StringEncoding error:nil];
#endif
}

void XRKDebugLog(NSString *format, ...) {
#if XRK_DEBUG
    va_list args;
    va_start(args, format);
    NSString *line = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    // 插件也注入「设置」（控制中心模块加载器），那边的行加前缀区分
    static BOOL inSettings;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ inSettings = [NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.Preferences"]; });
    if (inSettings) line = [@"[设置] " stringByAppendingString:line];

    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:XRK_DEBUG_FILE];
    if (!handle) {
        [@"" writeToFile:XRK_DEBUG_FILE atomically:YES encoding:NSUTF8StringEncoding error:nil];
        handle = [NSFileHandle fileHandleForWritingAtPath:XRK_DEBUG_FILE];
    }
    [handle seekToEndOfFile];
    [handle writeData:[[line stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding]];
    [handle closeFile];
#endif
}

#if XRK_DEBUG
static double XRKCPUSeconds(void) {
    struct rusage u;
    getrusage(RUSAGE_SELF, &u);
    return u.ru_utime.tv_sec + u.ru_utime.tv_usec / 1e6 + u.ru_stime.tv_sec + u.ru_stime.tv_usec / 1e6;
}

static void XRKSampleCPU(int remaining, double lastCPU, CFAbsoluteTime lastTime) {
    if (remaining <= 0) return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC), dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        double cpu = XRKCPUSeconds();
        CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
        XRKDebugLog(@"[CPU] %.1f%%", (cpu - lastCPU) / (now - lastTime) * 100.0);
        XRKSampleCPU(remaining - 1, cpu, now);
    });
}
#endif

void XRKDebugStartCPUSampling(void) {
#if XRK_DEBUG
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC), dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        XRKSampleCPU(12, XRKCPUSeconds(), CFAbsoluteTimeGetCurrent());
    });
#endif
}

#if XRK_DEBUG
#import <UIKit/UIKit.h>
#import <dlfcn.h>
// 调试截屏：电脑上 `ssh … touch /rootfs/var/mobile/Library/Caches/com.xyrith.xrkit.shot-request`，
// SpringBoard 每秒看一次，有请求就截整屏，存成 com.xyrith.xrkit.shot.png，再删掉请求。
// 开发时用来远程看效果（比如调多任务卡片间距），只在调试版里有。
// 截法：UIKit 的 _UICreateScreenUIImage 截底图（它会跳过控制中心那层），再把可见的控制中心窗口叠画上去。
// （QuartzCore 的 CARenderServerRenderDisplay 在 iOS 17 上只返回全透明的图，用不了）
#define XRK_SHOT_REQUEST @"/var/mobile/Library/Caches/com.xyrith.xrkit.shot-request"
#define XRK_SHOT_FILE    @"/var/mobile/Library/Caches/com.xyrith.xrkit.shot.png"
static NSMutableArray *gShotDumpers;
#endif

void XRKDebugAddShotDumper(void (^dumper)(void)) {
#if XRK_DEBUG
    if (!gShotDumpers) gShotDumpers = [NSMutableArray array];
    [gShotDumpers addObject:[dumper copy]];
#endif
}

void XRKDebugStartScreenshotWatcher(void) {
#if XRK_DEBUG
    typedef UIImage *(*XRKScreenFn)(void);
    static XRKScreenFn screenFn;
    screenFn = (XRKScreenFn)dlsym(RTLD_DEFAULT, "_UICreateScreenUIImage");
    XRKDebugLog(@"[Debug] screenshot watcher fn=%d", screenFn != NULL);
    static dispatch_source_t timer;
    timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), NSEC_PER_SEC, 200 * NSEC_PER_MSEC);
    dispatch_source_set_event_handler(timer, ^{
        NSFileManager *fm = NSFileManager.defaultManager;
        if (![fm fileExistsAtPath:XRK_SHOT_REQUEST]) return;
        [fm removeItemAtPath:XRK_SHOT_REQUEST error:nil];
        UIImage *img = screenFn ? screenFn() : nil;
        NSString *how = @"UIKit";
        // UIKit 的截屏跳过控制中心：把所有场景里可见的控制中心窗口按层级画在上面
        NSMutableArray<UIWindow *> *cc = [NSMutableArray array];
        for (UIScene *sc in UIApplication.sharedApplication.connectedScenes) {
            if (![sc isKindOfClass:[UIWindowScene class]]) continue;
            for (UIWindow *w in ((UIWindowScene *)sc).windows) {
                if (!w.hidden && w.alpha > 0.01 && [NSStringFromClass(w.class) containsString:@"ControlCenter"]) [cc addObject:w];
            }
        }
        if (img && cc.count) {
            [cc sortUsingComparator:^NSComparisonResult(UIWindow *a, UIWindow *b) { return a.windowLevel < b.windowLevel ? NSOrderedAscending : NSOrderedDescending; }];
            UIImage *base = img;
            UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:base.size];
            img = [r imageWithActions:^(UIGraphicsImageRendererContext *c) {
                [base drawInRect:(CGRect){CGPointZero, base.size}];
                for (UIWindow *w in cc) [w drawViewHierarchyInRect:w.frame afterScreenUpdates:NO];
            }];
            how = @"UIKit+ccWindows";
        }
        if (!img) {
            how = @"windows";
            // 退路：把 SpringBoard 的窗口画出来
            UIWindowScene *scene = nil;
            for (UIScene *s in UIApplication.sharedApplication.connectedScenes)
                if ([s isKindOfClass:[UIWindowScene class]]) { scene = (UIWindowScene *)s; break; }
            CGRect b = UIScreen.mainScreen.bounds;
            UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:b.size];
            img = [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
                for (UIWindow *w in scene.windows) if (!w.hidden) [w drawViewHierarchyInRect:w.frame afterScreenUpdates:NO];
            }];
        }
        [UIImagePNGRepresentation(img) writeToFile:XRK_SHOT_FILE atomically:YES];
        XRKDebugLog(@"[Debug] screenshot saved %@ via %@", NSStringFromCGSize(img.size), how);
        for (void (^d)(void) in gShotDumpers) d();
    });
    dispatch_resume(timer);
#endif
}
