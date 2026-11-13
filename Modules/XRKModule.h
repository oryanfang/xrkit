// xrkit 控制中心模块共用：系统类声明 + 小工具（每个模块是独立的 bundle，装到 /Library/ControlCenter/Bundles，
// 由 xrkit 的模块加载器 Tweak/CCModules.x 加载，跑在 SpringBoard 里）。
// 注意：每个 bundle 都会编进这个头文件，所以这里只放 static inline 函数，类名各模块自己起（同名类会冲突）。
#pragma once
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

// ControlCenterUIKit（iOS 17.3.1 符号核对过）
@interface CCUIContentModuleContext : NSObject
- (void)openURL:(NSURL *)url completionHandler:(void (^)(BOOL))completion;
- (void)dismissControlCenter;
@end

@interface CCUIToggleModule : NSObject
@property (nonatomic, retain) CCUIContentModuleContext *contentModuleContext;
- (UIImage *)iconGlyph;
- (UIImage *)selectedIconGlyph;
- (UIColor *)selectedColor;
- (BOOL)isSelected;
- (void)setSelected:(BOOL)selected;
- (void)refreshState;
@end

static inline UIImage *XRKGlyph(NSString *symbol) {
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:22 weight:UIImageSymbolWeightMedium];
    return [[UIImage systemImageNamed:symbol withConfiguration:cfg] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

static inline id XRKShared(const char *className) {
    Class cls = objc_getClass(className);
    if (!cls || ![cls respondsToSelector:@selector(sharedInstance)]) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(cls, @selector(sharedInstance));
}

static inline void XRKHaptic(void) {
    [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium] impactOccurred];
}

#pragma mark - 信息类模块（自己画内容，不是开关）
// 控制中心问内容控制器 -moduleLayoutSizeForOrientation: 要几格（ControlCenterUI -_sizesForModuleIdentifiers:... 反汇编确认）
typedef struct { unsigned long long width; unsigned long long height; } XRKLayoutSize;

// 两行文字的内容视图（实时网速、电池信息共用）：左边一个图标，上面大字、下面小字。每秒刷新一次，只在控制中心显示时跑。
// 每个 bundle 用 XRK_INFO_VC_DECL / XRK_INFO_VC_IMPL 生成自己名字的基类（各 bundle 类名不能重复），子类重写 -refresh
#define XRK_INFO_VC_DECL(VC) \
@interface VC : UIViewController \
@property (nonatomic, strong) UIImageView *iconView; \
@property (nonatomic, strong) UILabel *titleLabel; \
@property (nonatomic, strong) UILabel *detailLabel; \
@property (nonatomic, strong) NSTimer *timer; \
- (void)refresh; \
@end

#define XRK_INFO_VC_IMPL(VC) \
@implementation VC \
- (void)viewDidLoad { \
    [super viewDidLoad]; \
    self.iconView = [UIImageView new]; \
    self.iconView.tintColor = UIColor.whiteColor; \
    self.iconView.contentMode = UIViewContentModeScaleAspectFit; \
    self.titleLabel = [UILabel new]; \
    self.titleLabel.font = [UIFont monospacedDigitSystemFontOfSize:17 weight:UIFontWeightSemibold]; \
    self.titleLabel.textColor = UIColor.whiteColor; \
    self.titleLabel.adjustsFontSizeToFitWidth = YES; \
    self.titleLabel.minimumScaleFactor = 0.6; \
    self.detailLabel = [UILabel new]; \
    self.detailLabel.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightMedium]; \
    self.detailLabel.textColor = [UIColor colorWithWhite:1 alpha:0.7]; \
    self.detailLabel.adjustsFontSizeToFitWidth = YES; \
    self.detailLabel.minimumScaleFactor = 0.6; \
    for (UIView *v in @[self.iconView, self.titleLabel, self.detailLabel]) [self.view addSubview:v]; \
} \
- (void)viewDidLayoutSubviews { \
    [super viewDidLayoutSubviews]; \
    CGRect b = self.view.bounds; \
    CGFloat pad = 14, icon = 26; \
    self.iconView.frame = CGRectMake(pad, (b.size.height - icon) / 2, icon, icon); \
    CGFloat x = pad + icon + 10, w = b.size.width - x - pad; \
    self.titleLabel.frame = CGRectMake(x, b.size.height / 2 - 21, w, 22); \
    self.detailLabel.frame = CGRectMake(x, b.size.height / 2 + 2, w, 16); \
} \
- (void)viewWillAppear:(BOOL)animated { \
    [super viewWillAppear:animated]; \
    [self refresh]; \
    [self.timer invalidate]; \
    __weak typeof(self) weakSelf = self; \
    self.timer = [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer *t) { [weakSelf refresh]; }]; \
} \
- (void)viewDidDisappear:(BOOL)animated { \
    [super viewDidDisappear:animated]; \
    [self.timer invalidate]; \
    self.timer = nil; \
} \
- (XRKLayoutSize)moduleLayoutSizeForOrientation:(long long)orientation { return (XRKLayoutSize){2, 1}; } \
- (BOOL)shouldBeginTransitionToExpandedContentModule { return NO; } \
- (void)refresh {} \
@end

// 控制中心实例化模块时会检查 conformsToProtocol:CCUIContentModule
// （-[CCUIModuleInstanceManager _instantiateModuleWithMetadata:]，反汇编确认）。不继承 CCUIToggleModule 的模块
// 要自己补上协议，否则直接被跳过、控制中心里不出现（2026-11-12 网速 / 电池模块就是这样）。在 +load 里调用。
static inline void XRKAdoptProtocol(Class cls, const char *protocolName) {
    Protocol *p = objc_getProtocol(protocolName);
    if (p && !class_conformsToProtocol(cls, p)) class_addProtocol(cls, p);
}
