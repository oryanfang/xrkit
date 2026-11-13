// 多任务「iPad」样式：让系统直接用 iPad 的网格界面 SBGridSwitcherViewController（原始 switcherStyle = 2），
// 外加 iPad 的手势/动画总控 SBiPadOSPlatformSwitcherModifier（建界面时伪装 idiom），配一个卡死保护。
//
// 2026-11-11 曾经卡死过三次（主线程空转在 _dispatch_main_queue_drain，看门狗 60 秒重启），每次都刚好碰上
// 「面容识别后直接进主屏幕」→ 已在 LockScreen.x 把这种情况下的自动解锁改成 RunLoop 定时器延后执行，之后没再卡。
// 卡死保护留着兜底：
//   1. 心跳：主线程 RunLoop 上挂一个 0.5 秒的定时器记时间（卡在主队列里时 RunLoop 转不起来，定时器就不走）；
//   2. 后台线程每秒检查，心跳停了超过 5 秒（看门狗是 60 秒） → 认定卡死：
//      - 马上把偏好 swStyle 改回 0（系统），这样重启后不会再卡；
//      - 暂停主线程、读它的调用栈（只记地址，暂停期间不分配内存，防死锁），恢复后用 dladdr 换成"库名+偏移"，
//        连续采 40 次，写到 /var/mobile/Library/Caches/com.xyrith.xrkit.hang（不随 SpringBoard 重启清空），
//        之后在电脑上用 DeviceSupport 的符号 atos 解析。
// 只有选了「iPad」样式才装 hook、开心跳。
#import "XRKCommon.h"
#import <mach/mach.h>
#import <dlfcn.h>
#import <ptrauth.h>
#import <pthread.h>
#import <mach/mach_time.h>
#import <signal.h>

#define XRK_HANG_FILE @"/var/mobile/Library/Caches/com.xyrith.xrkit.hang"

static BOOL XRKFullPadOn(void) {
    return XRKSwitcherStyleSetting() == XRKSwitcherStyleiPad;
}

static BOOL gXRKFakePadIdiom = NO;

%group XRKGridFull
%hook SBAppSwitcherSettings

// 原始值：SBMainSwitcherControllerCoordinator -_loadContentViewControllerIfNecessaryForWindowScene: 按它选界面类
//   1 = SBDeckSwitcherViewController，2 = SBGridSwitcherViewController，3 = 调试表格，0 = 按设备
- (long long)switcherStyle {
    return XRKFullPadOn() ? 2 : %orig;
}

%end

// 手势和动画的总控（根修饰器）：同一个 _loadContentViewControllerIfNecessaryForWindowScene: 里按
// UIDevice.userInterfaceIdiom 选——iPad → SBiPadOSPlatformSwitcherModifier，否则 SBFullScreenFluidSwitcherRootSwitcherModifier。
// 只换界面不换总控，手感还是 iPhone 那套（实测动画僵硬）。所以只在这个方法执行期间让 idiom 返回 iPad。
%hook SBMainSwitcherControllerCoordinator

- (void)_loadContentViewControllerIfNecessaryForWindowScene:(id)scene {
    BOOL fake = [NSThread isMainThread];
    if (fake) gXRKFakePadIdiom = YES;
    %orig;
    if (fake) gXRKFakePadIdiom = NO;
}

%end

%hook UIDevice

- (UIUserInterfaceIdiom)userInterfaceIdiom {
    if (gXRKFakePadIdiom && [NSThread isMainThread]) return UIUserInterfaceIdiomPad;
    return %orig;
}

%end
%end

#pragma mark - 卡死保护

static mach_port_t gMainThread;
static volatile double gMainBeat;    // 主线程 RunLoop 最近一次"转起来"的时间（秒，XRKUptime）

// 用 mach_absolute_time：手机熄屏 / CPU 休眠时它会停，休眠的时间不算"卡住"。
// （2026-11-11 用 CFAbsoluteTimeGetCurrent 时误判过：熄屏几秒后轻点唤醒，被当成主线程卡了 7.7 秒）
static double XRKUptime(void) {
    static mach_timebase_info_data_t tb;
    if (tb.denom == 0) mach_timebase_info(&tb);
    return (double)mach_absolute_time() * tb.numer / tb.denom / 1e9;
}

static void XRKAppendHang(NSString *text) {
    NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:XRK_HANG_FILE];
    if (!h) {
        [@"" writeToFile:XRK_HANG_FILE atomically:YES encoding:NSUTF8StringEncoding error:nil];
        h = [NSFileHandle fileHandleForWritingAtPath:XRK_HANG_FILE];
    }
    [h seekToEndOfFile];
    [h writeData:[text dataUsingEncoding:NSUTF8StringEncoding]];
    [h closeFile];
}

#define XRK_MAX_FRAMES 48

// 暂停主线程，只读寄存器和栈上的帧指针链，不调用任何会分配内存 / 加锁的函数
static int XRKSampleMain(uintptr_t *out) {
    if (thread_suspend(gMainThread) != KERN_SUCCESS) return 0;
    int n = 0;
    arm_thread_state64_t st;
    mach_msg_type_number_t count = ARM_THREAD_STATE64_COUNT;
    if (thread_get_state(gMainThread, ARM_THREAD_STATE64, (thread_state_t)&st, &count) == KERN_SUCCESS) {
        out[n++] = (uintptr_t)ptrauth_strip((void *)arm_thread_state64_get_pc(st), ptrauth_key_asia);
        out[n++] = (uintptr_t)ptrauth_strip((void *)arm_thread_state64_get_lr(st), ptrauth_key_asia);
        uintptr_t fp = (uintptr_t)arm_thread_state64_get_fp(st);
        while (fp && (fp & 0xf) == 0 && n < XRK_MAX_FRAMES) {
            uintptr_t *frame = (uintptr_t *)fp;
            uintptr_t next = frame[0];
            uintptr_t lr = (uintptr_t)ptrauth_strip((void *)frame[1], ptrauth_key_asia);
            if (!lr) break;
            out[n++] = lr;
            if (next <= fp) break;   // 栈往高地址走，倒退说明链断了
            fp = next;
        }
    }
    thread_resume(gMainThread);
    return n;
}

static NSString *XRKDescribe(uintptr_t pc) {
    Dl_info info;
    if (dladdr((void *)pc, &info) && info.dli_fname) {
        NSString *lib = [@(info.dli_fname) lastPathComponent];
        return [NSString stringWithFormat:@"%@+0x%lx%@%@", lib, (unsigned long)(pc - (uintptr_t)info.dli_fbase),
                info.dli_sname ? @" " : @"", info.dli_sname ? @(info.dli_sname) : @""];
    }
    return [NSString stringWithFormat:@"0x%lx", (unsigned long)pc];
}

static void XRKHandleHang(double stalled) {
    // 1. 先自救：改回系统样式（重启后就不会再卡）
    XRKWritePref(kXRKSwStyle, @(XRKSwitcherStyleSystem));

    // 2. 采样主线程，按调用栈去重计数
    NSMutableDictionary<NSString *, NSNumber *> *stacks = [NSMutableDictionary dictionary];
    uintptr_t frames[XRK_MAX_FRAMES];
    for (int i = 0; i < 40; i++) {
        int n = XRKSampleMain(frames);
        NSMutableArray *lines = [NSMutableArray arrayWithCapacity:n];
        for (int j = 0; j < n; j++) [lines addObject:XRKDescribe(frames[j])];
        NSString *key = [lines componentsJoinedByString:@"\n    "];
        stacks[key] = @(stacks[key].intValue + 1);
        usleep(25 * 1000);
    }
    NSMutableString *report = [NSMutableString stringWithFormat:@"=== hang at %@ (main stalled %.1fs), swStyle reset to 0 ===\n",
                               [NSDate date], stalled];
    NSArray *sorted = [stacks keysSortedByValueUsingComparator:^NSComparisonResult(NSNumber *a, NSNumber *b) { return [b compare:a]; }];
    for (NSString *key in sorted) [report appendFormat:@"[%d samples]\n    %@\n", stacks[key].intValue, key];
    XRKAppendHang(report);

    // 3. 主线程还卡着就直接结束 SpringBoard，让系统马上重启它（不用等看门狗 60 秒）；重启后已是系统样式
    usleep(300 * 1000);
    if (XRKUptime() - gMainBeat > 4.0) {
        XRKAppendHang(@"(still stalled, killing SpringBoard for fast restart)\n");
        kill(getpid(), SIGKILL);
    }
}

static void *XRKWatchdogThread(void *arg) {
    BOOL reported = NO;
    while (1) {
        sleep(1);
        if (!XRKFullPadOn()) {
            reported = NO;
            continue;
        }
        if (gMainBeat == 0) continue;   // RunLoop 还没转起来（SpringBoard 还在启动），不算
        double stalled = XRKUptime() - gMainBeat;
        if (stalled > 5.0 && !reported) {
            reported = YES;
            @autoreleasepool { XRKHandleHang(stalled); }
        } else if (stalled < 1.0) {
            reported = NO;
        }
    }
    return NULL;
}

static void XRKBeat(CFRunLoopTimerRef timer, void *info) {
    gMainBeat = XRKUptime();
}

void XRKInitGridFull(void) {
    BOOL ok = XRKResponds("SBAppSwitcherSettings", @[@"switcherStyle"]) &&
              XRKResponds("SBMainSwitcherControllerCoordinator", @[@"_loadContentViewControllerIfNecessaryForWindowScene:"]);
    XRKDebugLog(@"[GridFull] ok=%d on=%d", ok, XRKFullPadOn());
    if (!ok || !XRKFullPadOn()) return;   // 切换排列样式需要注销

    %init(XRKGridFull);

    gMainThread = mach_thread_self();   // %ctor 在主线程
    gMainBeat = 0;
    CFRunLoopTimerRef timer = CFRunLoopTimerCreate(kCFAllocatorDefault, CFAbsoluteTimeGetCurrent() + 0.5, 0.5, 0, 0, XRKBeat, NULL);
    CFRunLoopAddTimer(CFRunLoopGetMain(), timer, kCFRunLoopCommonModes);
    CFRelease(timer);

    pthread_t t;
    pthread_create(&t, NULL, XRKWatchdogThread, NULL);
    pthread_detach(t);
}
