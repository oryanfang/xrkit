// xrkit VPN：点按开关「设置 › VPN」里当前选中的 VPN；长按展开菜单，列出所有 VPN，点一个就切过去并连接，点正在连的就断开。
//
// 照抄系统设置的做法（VPNPreferences.bundle，iOS 17.3.1 符号 + 反汇编 + 真机探测核对过，2026-11-13）：
//   store = +[VPNConnectionStore sharedInstance]
//   列表：-vpnServicesForCurrentSetWithGrade:(NSUInteger) → NSUUID 数组；名字：[store connectionWithServiceID:grade:].displayName
//   选中：-activeVPNIDWithGrade: / -isActiveVPNID:withGrade:；切换：-setActiveVPNID:withGrade:（-[VPNController changeActiveVPN:] 就是这么切的）
//   开关：VPNConnection -connect / -disconnect；状态 -status（NEVPNStatus：1 断开、2 正在连接、3 已连接、4 重连、5 正在断开）
//   开着 = (aggregateStatus & ~1) == 2，即 2 / 3（-[VPNBundleController vpnActiveForSpecifier:] 反汇编）
//   真机上常见的 VPN App 都在 grade 0（currentOnlyConnectionGrade = 0）
// 界面：ControlCenterUIKit 的 CCUIMenuModuleViewController（父类 CCUIButtonModuleViewController），
//   收起时是普通按钮（-buttonTapped:forEvent:），长按展开成菜单（-setMenuItems:，CCUIMenuModuleItem）。
// VPNPreferences 是设置的插件包，用到时才 dlopen 进 SpringBoard。
#import "../XRKModule.h"
#import <dlfcn.h>

@interface UIImage (XRKAppIcon)
+ (UIImage *)_applicationIconImageForBundleIdentifier:(NSString *)bundleID format:(int)format scale:(CGFloat)scale;
@end

@interface CCUIMenuModuleItem : NSObject
- (NSString *)identifier;
- (instancetype)initWithTitle:(NSString *)title identifier:(NSString *)identifier handler:(BOOL (^)(void))handler;
- (void)setSelected:(BOOL)selected;
- (void)setSubtitle:(NSString *)subtitle;
@end

@interface CCUIMenuModuleViewController : UIViewController
- (void)setContentModuleContext:(CCUIContentModuleContext *)context;
- (CCUIContentModuleContext *)contentModuleContext;
- (void)setGlyphImage:(UIImage *)image;
- (void)setSelectedGlyphColor:(UIColor *)color;
- (void)setSelected:(BOOL)selected;
- (void)setTitle:(NSString *)title;
- (void)setSubtitle:(NSString *)subtitle;
- (void)setMenuItems:(NSArray *)items;
- (void)setUseTrailingCheckmarkLayout:(BOOL)use;
- (void)setHideGlyphInHeader:(BOOL)hide;
- (void)setUseTrailingInset:(BOOL)use;
- (void)buttonTapped:(id)sender forEvent:(UIEvent *)event;
- (void)willTransitionToExpandedContentMode:(BOOL)expanded;
@end

@interface XRKVPNMenuViewController : CCUIMenuModuleViewController
@property (nonatomic, strong) NSMutableDictionary<NSString *, UIImage *> *xrkIcons;   // 菜单项 identifier → App 图标
- (void)xrk_refresh;
@end

@interface XRKVPNModule : NSObject
@property (nonatomic, strong) CCUIContentModuleContext *contentModuleContext;
@end

#pragma mark - VPN 数据

static id XRKVPNStore(void) {
    static BOOL loaded;
    if (!loaded) {
        loaded = YES;
        dlopen("/System/Library/PreferenceBundles/VPNPreferences.bundle/VPNPreferences", RTLD_NOW);
    }
    return XRKShared("VPNConnectionStore");
}

static NSUInteger XRKVPNGrade(id store) {
    if (![store respondsToSelector:@selector(currentOnlyConnectionGrade)]) return 0;
    return ((NSUInteger (*)(id, SEL))objc_msgSend)(store, @selector(currentOnlyConnectionGrade));
}

static NSArray *XRKVPNServiceIDs(id store, NSUInteger grade) {
    SEL sel = NSSelectorFromString(@"vpnServicesForCurrentSetWithGrade:");
    if (![store respondsToSelector:sel]) return @[];
    id ids = ((id (*)(id, SEL, NSUInteger))objc_msgSend)(store, sel, grade);
    return [ids isKindOfClass:[NSArray class]] ? ids : @[];
}

static id XRKVPNConnection(id store, id serviceID, NSUInteger grade) {
    SEL sel = NSSelectorFromString(@"connectionWithServiceID:withGrade:");
    if (!serviceID || ![store respondsToSelector:sel]) return nil;
    return ((id (*)(id, SEL, id, NSUInteger))objc_msgSend)(store, sel, serviceID, grade);
}

static id XRKVPNCurrentConnection(id store) {
    if (![store respondsToSelector:@selector(currentConnectionWithGrade:)]) return nil;
    return ((id (*)(id, SEL, NSUInteger))objc_msgSend)(store, @selector(currentConnectionWithGrade:), XRKVPNGrade(store));
}

static BOOL XRKVPNIsActiveID(id store, id serviceID, NSUInteger grade) {
    SEL sel = NSSelectorFromString(@"isActiveVPNID:withGrade:");
    if (![store respondsToSelector:sel]) return NO;
    return ((BOOL (*)(id, SEL, id, NSUInteger))objc_msgSend)(store, sel, serviceID, grade);
}

// NEVPNStatus：2 正在连接、3 已连接、4 重连（都算"连着"）
static NSUInteger XRKVPNStatus(id conn) {
    if (![conn respondsToSelector:@selector(status)]) return 0;
    return ((NSUInteger (*)(id, SEL))objc_msgSend)(conn, @selector(status));
}

static BOOL XRKVPNStatusIsOn(NSUInteger status) {
    return status == 2 || status == 3 || status == 4;
}

static BOOL XRKVPNAnyOn(id store) {
    if (![store respondsToSelector:@selector(aggregateStatus)]) return NO;
    NSUInteger status = ((NSUInteger (*)(id, SEL))objc_msgSend)(store, @selector(aggregateStatus));
    return (status & ~1UL) == 2;
}

static void XRKVPNSend(id conn, SEL action) {
    if ([conn respondsToSelector:action]) ((void (*)(id, SEL))objc_msgSend)(conn, action);
}

static NSString *XRKVPNName(id conn) {
    id name = [conn respondsToSelector:@selector(displayName)] ? [conn valueForKey:@"displayName"] : nil;
    return [name isKindOfClass:[NSString class]] && [name length] ? name : @"VPN";
}

// VPN 对应 App 的图标（24pt 圆角）。VPNConnection -bundleID 可能是 App 的扩展（xxx.PacketTunnel），
// 取不到就去掉最后一段再试；都没有就用一个通用的地球图标
static UIImage *XRKVPNAppIcon(id conn) {
    static NSCache *cache;
    if (!cache) cache = [NSCache new];
    id bid = [conn respondsToSelector:@selector(bundleID)] ? [conn valueForKey:@"bundleID"] : nil;
    NSString *key = [bid isKindOfClass:[NSString class]] ? bid : @"";
    UIImage *cached = [cache objectForKey:key];
    if (cached) return cached;

    UIImage *icon = nil;
    if ([UIImage respondsToSelector:@selector(_applicationIconImageForBundleIdentifier:format:scale:)]) {
        NSString *candidate = key;
        while (!icon && candidate.length) {
            icon = [UIImage _applicationIconImageForBundleIdentifier:candidate format:2 scale:UIScreen.mainScreen.scale];
            NSRange dot = [candidate rangeOfString:@"." options:NSBackwardsSearch];
            if (dot.location == NSNotFound || [candidate componentsSeparatedByString:@"."].count <= 2) break;
            candidate = [candidate substringToIndex:dot.location];
        }
    }
    // 系统把左侧图标放在文字左边那段空间（约 46pt）的正中，图标越小两边越宽：24pt → 两边各约 11pt。
    // ⚠️ 不要用 -setIndentation: 加宽（2026-11-13 试过：整行内容往左平移、被切掉），也不要在图里加透明留白（会被一起缩小）
    CGFloat side = 24;
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(side, side)];
    UIImage *result = [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        CGRect rect = CGRectMake(0, 0, side, side);
        if (icon) {
            [[UIBezierPath bezierPathWithRoundedRect:rect cornerRadius:side * 0.225] addClip];
            [icon drawInRect:rect];
        } else {
            [[UIColor colorWithWhite:1 alpha:0.18] setFill];
            [[UIBezierPath bezierPathWithRoundedRect:rect cornerRadius:side * 0.225] fill];
            UIImage *globe = [[UIImage systemImageNamed:@"network" withConfiguration:
                               [UIImageSymbolConfiguration configurationWithPointSize:15 weight:UIImageSymbolWeightSemibold]]
                              imageWithTintColor:UIColor.whiteColor renderingMode:UIImageRenderingModeAlwaysOriginal];
            [globe drawInRect:CGRectMake((side - globe.size.width) / 2, (side - globe.size.height) / 2, globe.size.width, globe.size.height)];
        }
    }];
    result = [result imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];   // 保持 App 原色，不被菜单染成白色
    [cache setObject:result forKey:key];
    return result;
}

static BOOL XRKZh(void) {
    return [NSLocale.preferredLanguages.firstObject hasPrefix:@"zh"];
}

// 图标：圆角框里写「VPN」，和状态栏的 VPN 标志一个风格
static UIImage *XRKVPNGlyph(void) {
    static UIImage *img;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        CGSize size = CGSizeMake(36, 21);
        UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:size];
        img = [[r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
            UIBezierPath *box = [UIBezierPath bezierPathWithRoundedRect:CGRectInset((CGRect){CGPointZero, size}, 1.2, 1.2) cornerRadius:4.5];
            box.lineWidth = 2;
            [UIColor.blackColor setStroke];
            [box stroke];
            NSDictionary *attrs = @{NSFontAttributeName: [UIFont systemFontOfSize:12.5 weight:UIFontWeightBold],
                                    NSForegroundColorAttributeName: UIColor.blackColor};
            CGSize t = [@"VPN" sizeWithAttributes:attrs];
            [@"VPN" drawAtPoint:CGPointMake((size.width - t.width) / 2, (size.height - t.height) / 2) withAttributes:attrs];
        }] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    });
    return img;
}

#pragma mark - 界面

@implementation XRKVPNMenuViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setGlyphImage:XRKVPNGlyph()];
    [self setSelectedGlyphColor:UIColor.systemBlueColor];
    [self setTitle:@"VPN"];
    if ([self respondsToSelector:@selector(setUseTrailingCheckmarkLayout:)]) [self setUseTrailingCheckmarkLayout:YES];
    // 顶部只留「VPN」和状态文字（图标是横长条，放进系统的正方形底会变成菱形，所以不放）
    if ([self respondsToSelector:@selector(setHideGlyphInHeader:)]) [self setHideGlyphInHeader:YES];
    if ([self respondsToSelector:@selector(setUseTrailingInset:)]) [self setUseTrailingInset:YES];
    [self xrk_refresh];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self xrk_refresh];
}

// 连接是异步的：操作后过一会儿按真实状态再刷新
- (void)xrk_refreshSoon {
    __weak typeof(self) weakSelf = self;
    for (NSNumber *delay in @[@0.5, @1.5, @3.0]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [weakSelf xrk_refresh];
        });
    }
}

// 按钮亮不亮、菜单副标题和勾
- (void)xrk_refresh {
    id store = XRKVPNStore();
    BOOL on = XRKVPNAnyOn(store);
    [self setSelected:on];

    NSUInteger grade = XRKVPNGrade(store);
    NSArray *ids = XRKVPNServiceIDs(store, grade);
    BOOL zh = XRKZh();
    NSString *status = zh ? @"未连接" : @"Not Connected";
    NSMutableArray *items = [NSMutableArray array];
    if (!self.xrkIcons) self.xrkIcons = [NSMutableDictionary dictionary];
    __weak typeof(self) weakSelf = self;
    for (id sid in ids) {
        id conn = XRKVPNConnection(store, sid, grade);
        NSString *name = XRKVPNName(conn);
        BOOL active = XRKVPNIsActiveID(store, sid, grade);
        NSUInteger st = XRKVPNStatus(conn);
        if (active && XRKVPNStatusIsOn(st)) {
            NSString *state = st == 3 ? (zh ? @"已连接" : @"Connected") : (zh ? @"正在连接…" : @"Connecting…");
            status = [NSString stringWithFormat:@"%@ · %@", state, name];
        }
        NSString *identifier = [sid respondsToSelector:@selector(UUIDString)] ? [sid UUIDString] : [sid description];
        self.xrkIcons[identifier] = XRKVPNAppIcon(conn);
        CCUIMenuModuleItem *item = [[objc_getClass("CCUIMenuModuleItem") alloc] initWithTitle:name identifier:identifier handler:^BOOL {
            [weakSelf xrk_selectServiceID:sid];
            return YES;
        }];
        // 勾 = 正在连的那个（没连接时不打勾，免得以为已经连上）
        [item setSelected:active && XRKVPNStatusIsOn(st)];
        if (item) [items addObject:item];
    }
    [self setSubtitle:status];
    [self setMenuItems:items];
}

// 菜单里点了一个 VPN：正在连的 → 断开；否则切过去并连接
- (void)xrk_selectServiceID:(id)sid {
    XRKHaptic();
    id store = XRKVPNStore();
    NSUInteger grade = XRKVPNGrade(store);
    id conn = XRKVPNConnection(store, sid, grade);
    BOOL active = XRKVPNIsActiveID(store, sid, grade);
    if (active && XRKVPNStatusIsOn(XRKVPNStatus(conn))) {
        XRKVPNSend(conn, @selector(disconnect));
        [self xrk_refreshSoon];
        return;
    }
    // 先断开正在连的另一个，再切换选中
    id current = XRKVPNCurrentConnection(store);
    BOOL wasOn = current && XRKVPNStatusIsOn(XRKVPNStatus(current));
    if (wasOn) XRKVPNSend(current, @selector(disconnect));
    SEL setActive = NSSelectorFromString(@"setActiveVPNID:withGrade:");
    if ([store respondsToSelector:setActive]) ((void (*)(id, SEL, id, NSUInteger))objc_msgSend)(store, setActive, sid, grade);
    // 等上一个断干净再连（立刻连有时会被正在断开的状态吞掉）
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((wasOn ? 0.6 : 0.1) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        XRKVPNSend(XRKVPNConnection(store, sid, grade), @selector(connect));
    });
    [self xrk_refreshSoon];
}

// 收起状态点按：开关当前选中的 VPN；一个都没配置时打开「设置 › VPN」
- (void)buttonTapped:(id)sender forEvent:(UIEvent *)event {
    id store = XRKVPNStore();
    id conn = XRKVPNCurrentConnection(store);
    if (!conn) {
        [self.contentModuleContext openURL:[NSURL URLWithString:@"prefs:root=General&path=VPN"] completionHandler:nil];
        return;
    }
    BOOL on = XRKVPNAnyOn(store);
    XRKVPNSend(conn, on ? @selector(disconnect) : @selector(connect));
    [self setSelected:!on];
    [self xrk_refreshSoon];
}

// 展开时按最新状态重建菜单
- (void)willTransitionToExpandedContentMode:(BOOL)expanded {
    if (expanded) [self xrk_refresh];
    [super willTransitionToExpandedContentMode:expanded];
}

// 每行左边放对应 App 的图标（有了左侧图标，名字统一靠左，不会一行靠左一行居中）
- (UIImage *)leadingImageForMenuItem:(CCUIMenuModuleItem *)item {
    NSString *identifier = [item respondsToSelector:@selector(identifier)] ? [item identifier] : nil;
    return identifier ? self.xrkIcons[identifier] : nil;
}

// 底部是给「设置…」按钮预留的空白，我们不放按钮，不要它。
// 图标 24pt、离左边约 11pt，菜单圆角（约 33pt）碰不到图标；改成留一截底边的话，留白和菜单项底色不同，像多了一条横线
- (BOOL)_shouldShowFooterChin {
    return NO;
}

// 没有任何 VPN 配置时不展开
- (BOOL)shouldBeginTransitionToExpandedContentModule {
    id store = XRKVPNStore();
    return XRKVPNServiceIDs(store, XRKVPNGrade(store)).count > 0;
}

@end

#pragma mark - 模块

@implementation XRKVPNModule {
    XRKVPNMenuViewController *_vc;
}

+ (void)load {
    // 不继承 CCUIToggleModule，要自己补上协议，否则控制中心直接跳过（见 XRKModule.h）
    XRKAdoptProtocol(self, "CCUIContentModule");
}

- (UIViewController *)contentViewController {
    if (!_vc) {
        _vc = [XRKVPNMenuViewController new];
        [_vc setContentModuleContext:self.contentModuleContext];
    }
    return _vc;
}

- (UIViewController *)contentViewControllerForContext:(id)context { return [self contentViewController]; }

- (void)setContentModuleContext:(CCUIContentModuleContext *)context {
    _contentModuleContext = context;
    [_vc setContentModuleContext:context];
}

@end
