// 「设置 › 控制中心」页：第三方模块和原固定模块的名字、图标（只在「设置」进程，配合 CCModules.x 的加载器）
//
// 设置页代码在 /System/Library/PreferenceBundles/ControlCenterSettings.bundle，点进去才加载，所以等 NSBundle 加载完再装 hook。
// CCUISettingsListController -_descriptionForIdentifier: 给每个模块一份 CCUISettingsModuleDescription
// （-initWithIdentifier:displayName:iconImage:iconBackgroundColor:）。系统只认识自己的模块：
// - 第三方模块：系统自己能从包里读出名字和图标，不动
// - 原固定模块（网络、音乐……）：系统没准备设置页图标、名字是内部名 → 图标用 SF Symbols 画，名字跟系统语言（中 / 英），
//   名字在 -[NSBundle ccui_displayName] 里改（列表名字从这里来，不是从 description 来）
#import "XRKCommon.h"

@interface CCUISettingsModuleDescription : NSObject
- (instancetype)initWithIdentifier:(NSString *)identifier displayName:(NSString *)name iconImage:(UIImage *)icon iconBackgroundColor:(UIColor *)color;
@end

@interface CCUISettingsListController : UIViewController
@end

// 原固定模块和 xrkit 自己的模块：名字（中 / 英，跟系统语言）+ SF Symbol + 底色。屏幕镜像系统自己有名字和图标，不在这里
static NSDictionary<NSString *, NSArray *> *XRKFixedModuleInfo(void) {
    static NSDictionary *info;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        info = @{
            @"com.apple.control-center.ConnectivityModule":    @[@"网络",         @"Connectivity",     @"antenna.radiowaves.left.and.right", UIColor.systemBlueColor],
            @"com.apple.mediaremote.controlcenter.nowplaying": @[@"正在播放",     @"Now Playing",      @"play.fill",                         UIColor.systemPinkColor],
            @"com.apple.control-center.OrientationLockModule": @[@"屏幕方向锁定", @"Orientation Lock", @"lock.rotation",                     UIColor.systemRedColor],
            @"com.apple.control-center.DisplayModule":         @[@"亮度",         @"Brightness",       @"sun.max.fill",                      UIColor.systemOrangeColor],
            @"com.apple.mediaremote.controlcenter.audio":      @[@"音量",         @"Volume",           @"speaker.wave.2.fill",               UIColor.systemGrayColor],
            @"com.apple.FocusUIModule":                        @[@"专注模式",     @"Focus",            @"moon.fill",                         UIColor.systemIndigoColor],
            @"com.apple.control-center.DoNotDisturbModule":    @[@"勿扰模式",     @"Do Not Disturb",   @"moon.fill",                         UIColor.systemIndigoColor],
            // xrkit 自己的模块（Modules/）
            @"com.xyrith.xrkit.cc.power":          @[@"注销",      @"Respring",        @"slowmo",            UIColor.systemRedColor],
            @"com.xyrith.xrkit.cc.lock":           @[@"锁屏",      @"Lock Screen",     @"lock.fill",         UIColor.systemBlueColor],
            @"com.xyrith.xrkit.cc.screenshot":     @[@"截屏",      @"Screenshot",      @"camera.viewfinder", UIColor.systemGrayColor],
            @"com.xyrith.xrkit.cc.autobrightness": @[@"自动亮度",  @"Auto-Brightness", @"sun.max.fill",      UIColor.systemOrangeColor],
            @"com.xyrith.xrkit.cc.clearapps":      @[@"清除后台",  @"Clear Apps",      @"xmark.app.fill",    UIColor.systemRedColor],
            @"com.xyrith.xrkit.cc.settings":       @[@"xrkit 设置", @"xrkit Settings", @"gearshape.fill",    UIColor.systemGrayColor],
            @"com.xyrith.xrkit.cc.darkmode":       @[@"深色模式",  @"Dark Mode",       @"circle.lefthalf.filled", UIColor.systemIndigoColor],
            @"com.xyrith.xrkit.cc.nightshift":     @[@"夜览",      @"Night Shift",     @"sunset.fill",       UIColor.systemOrangeColor],
            @"com.xyrith.xrkit.cc.truetone":       @[@"原彩显示",  @"True Tone",       @"sun.max.circle.fill", UIColor.systemYellowColor],
            @"com.xyrith.xrkit.cc.keepawake":      @[@"屏幕常亮",  @"Keep Awake",      @"cup.and.saucer.fill", UIColor.systemBrownColor],
            @"com.xyrith.xrkit.cc.hotspot":        @[@"个人热点",  @"Personal Hotspot", @"personalhotspot",  UIColor.systemGreenColor],
            @"com.xyrith.xrkit.cc.location":       @[@"定位",      @"Location",        @"location.fill",     UIColor.systemBlueColor],
            @"com.xyrith.xrkit.cc.netspeed":       @[@"实时网速",  @"Network Speed",   @"arrow.up.arrow.down", UIColor.systemTealColor],
            @"com.xyrith.xrkit.cc.battery":        @[@"电池信息",  @"Battery Info",    @"battery.75",        UIColor.systemGreenColor],
            @"com.xyrith.xrkit.cc.vpn":            @[@"VPN",       @"VPN",             @"network",           UIColor.systemBlueColor],
        };
    });
    return info;
}

static NSString *XRKFixedModuleName(NSString *identifier) {
    NSArray *info = XRKFixedModuleInfo()[identifier];
    if (!info) return nil;
    BOOL zh = [NSLocale.preferredLanguages.firstObject hasPrefix:@"zh"];
    return zh ? info[0] : info[1];
}

static UIImage *XRKSymbolIcon(NSString *symbol) {
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:15 weight:UIImageSymbolWeightSemibold];
    return [[UIImage systemImageNamed:symbol withConfiguration:cfg] imageWithTintColor:UIColor.whiteColor renderingMode:UIImageRenderingModeAlwaysOriginal];
}

// 只给原固定模块做（第三方模块系统自己能读出名字和图标，替换了反而变形，2026-11-12 截图确认）
static id XRKMakeDescription(NSString *identifier) {
    Class cls = objc_getClass("CCUISettingsModuleDescription");
    NSArray *fixed = XRKFixedModuleInfo()[identifier];
    if (!fixed || ![cls instancesRespondToSelector:@selector(initWithIdentifier:displayName:iconImage:iconBackgroundColor:)]) return nil;
    return [[cls alloc] initWithIdentifier:identifier displayName:XRKFixedModuleName(identifier) iconImage:XRKSymbolIcon(fixed[2]) iconBackgroundColor:fixed[3]];
}

// 「更多控件」（_disabledIdentifiers，系统按名字排）：系统模块在前，xrkit 自己的模块统一排在后面（不和系统模块混在一起，好找）。
// 两组内部保持系统原来的顺序。生成列表前（-_specifiersForIdentifiers: 传进来的就是这个数组）就地重排；
// 从上面移除一个模块时系统按名字算插入位置（-_indexForInsertingItemWithIdentifier:intoArray:），再把它限制在自己那一组里。
static BOOL XRKIsOwnModule(NSString *identifier) {
    return [identifier isKindOfClass:[NSString class]] && [identifier hasPrefix:@"com.xyrith.xrkit."];
}

static void XRKPartitionOwnModulesLast(NSMutableArray *ids) {
    if (![ids isKindOfClass:[NSMutableArray class]]) return;
    NSMutableArray *system = [NSMutableArray array], *own = [NSMutableArray array];
    for (id i in ids) [(XRKIsOwnModule(i) ? own : system) addObject:i];
    if (!own.count) return;
    [ids setArray:[system arrayByAddingObjectsFromArray:own]];
}

%group XRKCCSettingsPage
%hook CCUISettingsListController

- (id)_descriptionForIdentifier:(NSString *)identifier {
    id mine = XRKMakeDescription(identifier);
    if (mine) XRKDebugLog(@"[CCSettings] %@ → xrkit 的图标", identifier);
    return mine ?: %orig;
}

- (id)_specifiersForIdentifiers:(NSArray *)identifiers {
    NSMutableArray *disabled = nil;
    @try { disabled = [self valueForKey:@"_disabledIdentifiers"]; } @catch (NSException *e) {}
    if (identifiers && identifiers == disabled) XRKPartitionOwnModulesLast(disabled);
    return %orig;
}

- (unsigned long long)_indexForInsertingItemWithIdentifier:(NSString *)identifier intoArray:(NSArray *)array {
    unsigned long long idx = %orig;
    NSMutableArray *disabled = nil;
    @try { disabled = [self valueForKey:@"_disabledIdentifiers"]; } @catch (NSException *e) {}
    if (array != disabled) return idx;
    NSUInteger firstOwn = array.count;
    for (NSUInteger i = 0; i < array.count; i++) if (XRKIsOwnModule(array[i])) { firstOwn = i; break; }
    if (XRKIsOwnModule(identifier)) return MAX(idx, (unsigned long long)firstOwn);
    return MIN(idx, (unsigned long long)firstOwn);
}

%end

// 列表里的名字取自模块包的 -[NSBundle ccui_displayName]（设置包里给 NSBundle 加的分类方法），模块包 ID = 模块 ID
%hook NSBundle

- (NSString *)ccui_displayName {
    return XRKFixedModuleName(self.bundleIdentifier) ?: %orig;
}

%end
%end

static BOOL gSettingsHooked = NO;

static void XRKTryHookSettingsPage(void) {
    if (gSettingsHooked) return;
    Class cls = objc_getClass("CCUISettingsListController");
    if (!cls || !XRKResponds("CCUISettingsListController", @[@"_descriptionForIdentifier:", @"_specifiersForIdentifiers:",
                                                             @"_indexForInsertingItemWithIdentifier:intoArray:"]) ||
        ![NSBundle instancesRespondToSelector:NSSelectorFromString(@"ccui_displayName")]) return;
    gSettingsHooked = YES;
    XRKDebugLog(@"[CCSettings] settings page loaded, hooking");
    %init(XRKCCSettingsPage);
}

// 设置包是「设置」用 NSBundle 加载的。之前用 _dyld_register_func_for_add_image 等它，回调时类还没注册好（2026-11-12 实测没装上），
// 改成 hook -[NSBundle load] / -loadAndReturnError:，加载完成后类一定可用。
%group XRKCCSettingsBundleWatch
%hook NSBundle

- (BOOL)load {
    BOOL r = %orig;
    if (r && !gSettingsHooked && [self.bundlePath containsString:@"ControlCenterSettings"]) XRKTryHookSettingsPage();
    return r;
}

- (BOOL)loadAndReturnError:(NSError **)error {
    BOOL r = %orig;
    if (r && !gSettingsHooked && [self.bundlePath containsString:@"ControlCenterSettings"]) XRKTryHookSettingsPage();
    return r;
}

%end
%end

void XRKInitCCModulesSettings(void) {
    XRKTryHookSettingsPage();
    if (!gSettingsHooked) %init(XRKCCSettingsBundleWatch);
}
