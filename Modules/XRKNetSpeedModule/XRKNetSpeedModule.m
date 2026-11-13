// xrkit 实时网速：2×1 方块，显示当前下载 / 上传速度，每秒刷新（只在控制中心显示时计算）。
// getifaddrs 读网卡累计字节数（AF_LINK 的 if_data.ifi_ibytes / ifi_obytes），统计 Wi-Fi（en*）和蜂窝（pdp_ip*），
// 不算 VPN 隧道（utun*），否则开 VPN 时同一份流量会算两遍。计数器是 32 位会回绕，差值为负时丢掉这一秒。
#import "../XRKModule.h"
#import <ifaddrs.h>
#import <net/if.h>

XRK_INFO_VC_DECL(XRKNetSpeedBaseVC)
XRK_INFO_VC_IMPL(XRKNetSpeedBaseVC)

@interface XRKNetSpeedViewController : XRKNetSpeedBaseVC
@end

@interface XRKNetSpeedModule : NSObject
@property (nonatomic, strong) CCUIContentModuleContext *contentModuleContext;
@end

static void XRKReadBytes(uint64_t *inBytes, uint64_t *outBytes) {
    *inBytes = 0; *outBytes = 0;
    struct ifaddrs *list = NULL;
    if (getifaddrs(&list) != 0) return;
    for (struct ifaddrs *i = list; i; i = i->ifa_next) {
        if (!i->ifa_addr || i->ifa_addr->sa_family != AF_LINK || !i->ifa_data) continue;
        if (!(i->ifa_flags & IFF_UP)) continue;
        const char *n = i->ifa_name;
        if (strncmp(n, "en", 2) != 0 && strncmp(n, "pdp_ip", 6) != 0) continue;
        struct if_data *d = (struct if_data *)i->ifa_data;
        *inBytes += d->ifi_ibytes;
        *outBytes += d->ifi_obytes;
    }
    freeifaddrs(list);
}

static NSString *XRKFormatSpeed(double bytesPerSecond) {
    if (bytesPerSecond < 1024) return [NSString stringWithFormat:@"%.0f B/s", bytesPerSecond];
    if (bytesPerSecond < 1024 * 1024) return [NSString stringWithFormat:@"%.0f KB/s", bytesPerSecond / 1024];
    return [NSString stringWithFormat:@"%.1f MB/s", bytesPerSecond / 1024 / 1024];
}

static uint64_t gLastIn, gLastOut;
static CFAbsoluteTime gLastTime;

@implementation XRKNetSpeedViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.iconView.image = [UIImage systemImageNamed:@"arrow.up.arrow.down" withConfiguration:
                           [UIImageSymbolConfiguration configurationWithPointSize:20 weight:UIImageSymbolWeightSemibold]];
    self.titleLabel.text = @"↓ —";
    self.detailLabel.text = @"↑ —";
}

- (void)refresh {
    uint64_t in, out;
    XRKReadBytes(&in, &out);
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    double dt = now - gLastTime;
    if (gLastTime > 0 && dt > 0.2 && dt < 5 && in >= gLastIn && out >= gLastOut) {
        self.titleLabel.text = [@"↓ " stringByAppendingString:XRKFormatSpeed((in - gLastIn) / dt)];
        self.detailLabel.text = [@"↑ " stringByAppendingString:XRKFormatSpeed((out - gLastOut) / dt)];
    }
    gLastIn = in; gLastOut = out; gLastTime = now;
}

@end

@implementation XRKNetSpeedModule {
    XRKNetSpeedViewController *_vc;
}

+ (void)load {
    XRKAdoptProtocol(self, "CCUIContentModule");
    XRKAdoptProtocol(objc_getClass("XRKNetSpeedViewController"), "CCUIContentModuleContentViewController");
}

- (UIViewController *)contentViewController {
    if (!_vc) _vc = [XRKNetSpeedViewController new];
    return _vc;
}

- (UIViewController *)contentViewControllerForContext:(id)context { return [self contentViewController]; }

@end
