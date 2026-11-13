// xrkit 电池信息：2×1 方块，和实时网速同一个样式：上面功率、下面温度。
// 只放最常看的两项，更丰富的电池功能留给以后单独的电池插件。
// 电量 / 充电状态：UIDevice；其它：IORegistry 里 AppleSmartBattery 的属性（IORegistryEntryCreateCFProperty，只读用到的几项），都是"有就显示"。
// iOS 17 真机实测有：NominalChargeCapacity / DesignCapacity / AppleRawMaxCapacity / AppleRawCurrentCapacity、
// Voltage(mV)、InstantAmperage / Amperage(mA，放电为负)、Temperature(0.01℃)、CycleCount、TimeRemaining / AvgTimeToEmpty(分钟)、AdapterDetails{Watts…}
// IOKit 函数用 dlsym 取，不链接 IOKit。以后的电池插件可以和这里共用数据。
#import "../XRKModule.h"
#import <dlfcn.h>
#import <mach/mach.h>

XRK_INFO_VC_DECL(XRKBatteryBaseVC)
XRK_INFO_VC_IMPL(XRKBatteryBaseVC)

@interface XRKBatteryViewController : XRKBatteryBaseVC
@end

@interface XRKBatteryModule : NSObject
@property (nonatomic, strong) CCUIContentModuleContext *contentModuleContext;
@end

typedef mach_port_t xrk_io_object_t;
static xrk_io_object_t (*pIOServiceGetMatchingService)(mach_port_t, CFDictionaryRef);
static CFMutableDictionaryRef (*pIOServiceMatching)(const char *);
static CFTypeRef (*pIORegistryEntryCreateCFProperty)(xrk_io_object_t, CFStringRef, CFAllocatorRef, uint32_t);

// AppleSmartBattery 服务只找一次（一直留着，不释放）；每秒只读用得到的几项，不取整份属性（里面有很大的 BatteryData）
static xrk_io_object_t XRKBatteryService(void) {
    static xrk_io_object_t svc;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *h = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW);
        if (!h) return;
        pIOServiceGetMatchingService = dlsym(h, "IOServiceGetMatchingService");
        pIOServiceMatching = dlsym(h, "IOServiceMatching");
        pIORegistryEntryCreateCFProperty = dlsym(h, "IORegistryEntryCreateCFProperty");
        if (pIOServiceGetMatchingService && pIOServiceMatching && pIORegistryEntryCreateCFProperty)
            svc = pIOServiceGetMatchingService(0, pIOServiceMatching("AppleSmartBattery"));
    });
    return svc;
}

// 按顺序找第一个有的键，返回数值；都没有返回 NAN
static double XRKNum(NSArray<NSString *> *keys) {
    xrk_io_object_t svc = XRKBatteryService();
    if (!svc) return NAN;
    for (NSString *k in keys) {
        id v = (__bridge_transfer id)pIORegistryEntryCreateCFProperty(svc, (__bridge CFStringRef)k, kCFAllocatorDefault, 0);
        if ([v respondsToSelector:@selector(doubleValue)]) return [v doubleValue];
    }
    return NAN;
}

// 样子和实时网速一样：左边图标，上面大字功率、下面小字温度。电量状态栏已有、健康不常看，所以不放。
// 充电时功率变绿、图标带闪电。（试过两行塞三项 / 三列 健康·功率·温度，字太挤）
@implementation XRKBatteryViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    UIDevice.currentDevice.batteryMonitoringEnabled = YES;
}

- (void)refresh {
    BOOL zh = [NSLocale.preferredLanguages.firstObject hasPrefix:@"zh"];
    double voltage = XRKNum(@[@"Voltage", @"AppleRawBatteryVoltage"]);      // mV
    double amperage = XRKNum(@[@"InstantAmperage", @"Amperage"]);            // mA，放电为负
    double temp = XRKNum(@[@"Temperature"]);                                 // 0.01 ℃
    double watts = (!isnan(voltage) && !isnan(amperage)) ? fabs(voltage * amperage) / 1e6 : NAN;
    BOOL charging = UIDevice.currentDevice.batteryState == UIDeviceBatteryStateCharging || (!isnan(amperage) && amperage > 0);

    self.titleLabel.text = [NSString stringWithFormat:@"%@ %@", zh ? @"功率" : @"Power", isnan(watts) ? @"—" : [NSString stringWithFormat:@"%.1fW", watts]];
    self.titleLabel.textColor = charging ? UIColor.systemGreenColor : UIColor.whiteColor;
    self.detailLabel.text = [NSString stringWithFormat:@"%@ %@", zh ? @"温度" : @"Temp", isnan(temp) ? @"—" : [NSString stringWithFormat:@"%.1f℃", temp / 100.0]];
    self.iconView.image = [UIImage systemImageNamed:charging ? @"battery.100.bolt" : @"bolt.fill" withConfiguration:
                           [UIImageSymbolConfiguration configurationWithPointSize:20 weight:UIImageSymbolWeightSemibold]];
}

@end

@implementation XRKBatteryModule {
    XRKBatteryViewController *_vc;
}

+ (void)load {
    XRKAdoptProtocol(self, "CCUIContentModule");
    XRKAdoptProtocol(objc_getClass("XRKBatteryViewController"), "CCUIContentModuleContentViewController");
}

- (UIViewController *)contentViewController {
    if (!_vc) _vc = [XRKBatteryViewController new];
    return _vc;
}

- (UIViewController *)contentViewControllerForContext:(id)context { return [self contentViewController]; }

@end
