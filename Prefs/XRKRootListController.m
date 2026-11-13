#import "XRKRootListController.h"
#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <sys/utsname.h>

// 公开仓库：反馈（Issues）和检查更新（Releases）都用它
static NSString *const kXRKRepo = @"oryanfang/xrkit";
// 软件源（GitHub Pages）
static NSString *const kXRKSourceURL = @"https://oryanfang.github.io/repo/";

// 私有 API：通过 FrontBoardServices 让 SpringBoard 重启（注销）
@interface SBSRelaunchAction : NSObject
+ (instancetype)actionWithReason:(NSString *)reason options:(NSUInteger)options targetURL:(NSURL *)url;
@end

@interface FBSSystemService : NSObject
+ (instancetype)sharedService;
- (void)sendActions:(NSSet *)actions withResult:(id)result;
@end

@interface PSListController (XRKPrivate)
- (id)readPreferenceValue:(PSSpecifier *)specifier;
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier;
- (PSSpecifier *)specifierAtIndexPath:(NSIndexPath *)indexPath;
@end

#pragma mark - 「需注销」小标签
// plist 里写 xrkRespring = true 的项，名字后面跟一个橙色小标签「需注销」（改完要注销才生效）

static UIImage *XRKRespringTagImage(UIFont *font) {
    static UIImage *image;
    static CGFloat cachedSize;
    if (image && cachedSize == font.pointSize) return image;
    cachedSize = font.pointSize;
    UIFont *tagFont = [UIFont systemFontOfSize:round(font.pointSize * 0.68) weight:UIFontWeightMedium];
    NSDictionary *attrs = @{NSFontAttributeName: tagFont, NSForegroundColorAttributeName: UIColor.systemOrangeColor};
    NSString *text = @"需注销";
    CGSize t = [text sizeWithAttributes:attrs];
    CGSize size = CGSizeMake(ceil(t.width) + 10, ceil(t.height) + 3);
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:size];
    image = [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [[UIColor.systemOrangeColor colorWithAlphaComponent:0.15] setFill];
        [[UIBezierPath bezierPathWithRoundedRect:(CGRect){CGPointZero, size} cornerRadius:size.height / 2] fill];
        [text drawAtPoint:CGPointMake((size.width - t.width) / 2, (size.height - t.height) / 2) withAttributes:attrs];
    }];
    return image;
}

static void XRKDecorateCell(UITableViewCell *cell, PSSpecifier *spec) {
    if (![[spec propertyForKey:@"xrkRespring"] boolValue] || !spec.name.length || !cell.textLabel) return;
    UIFont *font = cell.textLabel.font ?: [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    UIImage *tag = XRKRespringTagImage(font);
    NSTextAttachment *att = [NSTextAttachment new];
    att.image = tag;
    // 标签和文字垂直居中
    att.bounds = CGRectMake(0, round((font.capHeight - tag.size.height) / 2), tag.size.width, tag.size.height);
    NSMutableAttributedString *text = [[NSMutableAttributedString alloc] initWithString:[spec.name stringByAppendingString:@"  "]
                                                                             attributes:@{NSFontAttributeName: font}];
    [text appendAttributedString:[NSAttributedString attributedStringWithAttachment:att]];
    cell.textLabel.attributedText = text;
}

#pragma mark - 注销

static void XRKRespringNow(void) {
    dlopen("/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices", RTLD_LAZY);
    dlopen("/System/Library/PrivateFrameworks/FrontBoardServices.framework/FrontBoardServices", RTLD_LAZY);
    Class actionClass = NSClassFromString(@"SBSRelaunchAction");
    Class serviceClass = NSClassFromString(@"FBSSystemService");
    if (!actionClass || !serviceClass) return;
    // options 4 = FadeToBlackTransition
    SBSRelaunchAction *relaunch = [actionClass actionWithReason:@"RestartRenderServer" options:4 targetURL:nil];
    [[serviceClass sharedService] sendActions:[NSSet setWithObject:relaunch] withResult:nil];
}

// 弹窗问要不要注销（主页的注销按钮、重置设置之后共用）
static void XRKConfirmRespring(UIViewController *vc, NSString *title, NSString *message, NSString *cancelTitle) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:cancelTitle style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"注销" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) { XRKRespringNow(); }]];
    [vc presentViewController:alert animated:YES completion:nil];
}

@implementation XRKRootListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    }
    return _specifiers;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [super tableView:tableView cellForRowAtIndexPath:indexPath];
    XRKDecorateCell(cell, [self specifierAtIndexPath:indexPath]);
    return cell;
}

// 注销放在导航栏右上角（蓝字），不占列表位置
- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"注销" style:UIBarButtonItemStylePlain
                                                                             target:self action:@selector(respring)];
}

- (void)respring {
    XRKConfirmRespring(self, @"注销", @"确定要注销（重启 SpringBoard）吗？", @"取消");
}

@end

// 系统「在主屏幕上显示搜索」开关背后的接口（SpringBoardServices）
@interface SBSHomeScreenService : NSObject
- (BOOL)showsHomeScreenSearchAffordance;
- (void)setShowsHomeScreenSearchAffordance:(BOOL)shows;
@end

static SBSHomeScreenService *XRKHomeScreenService(void) {
    static SBSHomeScreenService *service;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        dlopen("/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices", RTLD_LAZY);
        Class cls = NSClassFromString(@"SBSHomeScreenService");
        if ([cls instancesRespondToSelector:@selector(setShowsHomeScreenSearchAffordance:)]) service = [cls new];
    });
    return service;
}

#pragma mark - 关于页：检查更新

// 比较版本号 "0.2.0" / "v0.3.1"（忽略开头的 v 和 "-构建号" "+debug" 这类后缀）：a 比 b 新返回 YES
static BOOL XRKVersionNewer(NSString *a, NSString *b) {
    NSArray *(^parts)(NSString *) = ^NSArray *(NSString *v) {
        if ([v hasPrefix:@"v"] || [v hasPrefix:@"V"]) v = [v substringFromIndex:1];
        v = [[v componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"-+ "]] firstObject];
        return [v componentsSeparatedByString:@"."];
    };
    NSArray *pa = parts(a), *pb = parts(b);
    for (NSUInteger i = 0; i < MAX(pa.count, pb.count); i++) {
        NSInteger x = i < pa.count ? [pa[i] integerValue] : 0, y = i < pb.count ? [pb[i] integerValue] : 0;
        if (x != y) return x > y;
    }
    return NO;
}

@implementation XRKSubListController {
    NSArray *_xrkAllSpecifiers;   // plist 里的全部项（含暂时隐藏的）
    NSString *_xrkNewVersion;     // 关于页：GitHub 上更新的版本号（没有更新时为 nil）
    NSURL *_xrkUpdateURL;         // 关于页：新版本的 Release 页面
}

- (void)viewDidLoad {
    [super viewDidLoad];
    if ([self xrk_versionSpecifier]) [self xrk_checkUpdate];
}

- (PSSpecifier *)xrk_versionSpecifier {
    for (PSSpecifier *spec in _xrkAllSpecifiers ?: [self specifiers]) {
        if ([[spec propertyForKey:@"xrkVersion"] boolValue]) return spec;
    }
    return nil;
}

// 查公开仓库最新的 Release（没发过 Release / 没网 / 被限流都当作没有更新，不提示）
- (void)xrk_checkUpdate {
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"https://api.github.com/repos/%@/releases/latest", kXRKRepo]];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:10];
    [req setValue:@"application/vnd.github+json" forHTTPHeaderField:@"Accept"];
    __weak typeof(self) weakSelf = self;
    [[NSURLSession.sharedSession dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *resp, NSError *error) {
        if (error || !data || ![resp isKindOfClass:[NSHTTPURLResponse class]] || ((NSHTTPURLResponse *)resp).statusCode != 200) return;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if (![json isKindOfClass:[NSDictionary class]]) return;
        NSString *tag = json[@"tag_name"], *page = json[@"html_url"];
        if (![tag isKindOfClass:[NSString class]] || ![page isKindOfClass:[NSString class]]) return;
        dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf xrk_gotLatestVersion:tag page:[NSURL URLWithString:page]]; });
    }] resume];
}

- (void)xrk_gotLatestVersion:(NSString *)latest page:(NSURL *)page {
    PSSpecifier *spec = [self xrk_versionSpecifier];
    NSString *installed = [spec propertyForKey:@"xrkValue"];
    if (!spec || !page || !installed || !XRKVersionNewer(latest, installed)) return;
    _xrkNewVersion = [latest hasPrefix:@"v"] || [latest hasPrefix:@"V"] ? [latest substringFromIndex:1] : latest;
    _xrkUpdateURL = page;
    [self reloadSpecifier:spec animated:YES];
}

// 版本行显示的值：有新版时换成「有新版 x.x.x」
- (id)xrkVersionValue:(PSSpecifier *)specifier {
    return _xrkNewVersion ? [NSString stringWithFormat:@"有新版 %@", _xrkNewVersion] : [specifier propertyForKey:@"xrkValue"];
}

#pragma mark - 关于页：软件源、反馈

// 软件源：在 Sileo 里添加，或复制地址（装了别的包管理器时自己粘贴）
- (void)xrkOpenRepo {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"软件源" message:kXRKSourceURL
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    NSURL *sileo = [NSURL URLWithString:[@"sileo://source/" stringByAppendingString:kXRKSourceURL]];
    // 「设置」没声明 sileo 这个 scheme，canOpenURL 总是 NO，所以不判断，直接给出（没装 Sileo 时点了没反应）
    [sheet addAction:[UIAlertAction actionWithTitle:@"在 Sileo 中添加" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [UIApplication.sharedApplication openURL:sileo options:@{} completionHandler:nil];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"复制地址" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        UIPasteboard.generalPasteboard.string = kXRKSourceURL;
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    // iPad 上 action sheet 要有锚点
    sheet.popoverPresentationController.sourceView = self.view;
    sheet.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 1, 1);
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)xrkOpenIssues {
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"https://github.com/%@/issues/new", kXRKRepo]];
    [UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil];
}

// 复制问题信息：版本、系统、机型、偏好域里存着的设置（锁定的 App 只写数量，不写是哪些 App）
- (void)xrkCopyInfo {
    struct utsname u;
    uname(&u);
    NSMutableString *text = [NSMutableString string];
    [text appendFormat:@"xrkit %@\n", [[self xrk_versionSpecifier] propertyForKey:@"xrkValue"] ?: @"?"];
    [text appendFormat:@"iOS %@ · %s\n", UIDevice.currentDevice.systemVersion, u.machine];
    [text appendString:@"越狱环境：roothide\n"];

    CFStringRef domain = CFSTR("com.xyrith.xrkit");
    CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    NSArray *keys = CFBridgingRelease(CFPreferencesCopyKeyList(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost));
    NSDictionary *prefs = keys.count ? CFBridgingRelease(CFPreferencesCopyMultiple((__bridge CFArrayRef)keys, domain,
                                                                                   kCFPreferencesCurrentUser, kCFPreferencesAnyHost)) : @{};
    if (!prefs.count) {
        [text appendString:@"设置：全部默认\n"];
    } else {
        [text appendString:@"改过的设置：\n"];
        for (NSString *key in [prefs.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
            id v = prefs[key];
            if ([v isKindOfClass:[NSArray class]] || [v isKindOfClass:[NSDictionary class]]) {
                [text appendFormat:@"  %@ = %lu 项\n", key, (unsigned long)[v count]];
            } else {
                [text appendFormat:@"  %@ = %@\n", key, v];
            }
        }
    }
    UIPasteboard.generalPasteboard.string = text;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"已复制" message:text preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

// 「隐藏底部搜索按钮」：不存自己的偏好，直接读写系统设置，跟系统开关保持同步
- (id)xrkHideSearch:(PSSpecifier *)specifier {
    SBSHomeScreenService *service = XRKHomeScreenService();
    return @(service ? ![service showsHomeScreenSearchAffordance] : NO);
}

- (void)setXrkHideSearch:(id)value specifier:(PSSpecifier *)specifier {
    [XRKHomeScreenService() setShowsHomeScreenSearchAffordance:![value boolValue]];
}

// 关于页的只读行（PSTitleValueCell）：值写在 plist 的 xrkValue 里
- (id)xrkStaticValue:(PSSpecifier *)specifier {
    return [specifier propertyForKey:@"xrkValue"];
}

// 重置所有设置：删掉 xrkit 偏好域里的全部键（开关、滑块、锁定的 App），通知插件重读，再问要不要注销。
// 「底部搜索按钮」存在系统设置里，不受影响
- (void)xrkResetAll {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"重置所有设置"
        message:@"xrkit 的所有开关和滑块都会恢复默认，多任务里锁定的 App 也会清空。确定吗？"
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"重置" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
        CFStringRef domain = CFSTR("com.xyrith.xrkit");
        CFArrayRef keys = CFPreferencesCopyKeyList(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        if (keys) {
            CFPreferencesSetMultiple(NULL, keys, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
            CFRelease(keys);
        }
        CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("com.xyrith.xrkit/prefschanged"), NULL, NULL, YES);
        XRKConfirmRespring(weakSelf, @"已重置", @"有些设置要注销后才会完全恢复，现在注销吗？", @"稍后");
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

// 依赖显示：plist 里写了 xrkRequires = 某个开关的 key 的项，只有那个开关打开时才显示。
// 例如图标透明度的两个滑块，开关关着时整组只占一行。
- (NSArray *)specifiers {
    if (!_specifiers) {
        NSString *plistName = [self.specifier propertyForKey:@"plistName"];
        _xrkAllSpecifiers = plistName ? [self loadSpecifiersFromPlistName:plistName target:self] : @[];
        NSMutableArray *visible = [NSMutableArray array];
        for (PSSpecifier *spec in _xrkAllSpecifiers) {
            NSString *requires = [spec propertyForKey:@"xrkRequires"];
            if (requires && ![self xrk_boolForKey:requires]) continue;
            [visible addObject:spec];
        }
        _specifiers = visible;
    }
    return _specifiers;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [super tableView:tableView cellForRowAtIndexPath:indexPath];
    PSSpecifier *spec = [self specifierAtIndexPath:indexPath];
    XRKDecorateCell(cell, spec);
    // 关于页版本行：有新版时蓝字 + 箭头，可以点
    if ([[spec propertyForKey:@"xrkVersion"] boolValue]) {
        BOOL update = _xrkUpdateURL != nil;
        cell.detailTextLabel.textColor = update ? UIColor.systemBlueColor : UIColor.secondaryLabelColor;
        cell.accessoryType = update ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;
        cell.selectionStyle = update ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    PSSpecifier *spec = [self specifierAtIndexPath:indexPath];
    if ([[spec propertyForKey:@"xrkVersion"] boolValue]) {
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
        if (_xrkUpdateURL) [UIApplication.sharedApplication openURL:_xrkUpdateURL options:@{} completionHandler:nil];
        return;
    }
    [super tableView:tableView didSelectRowAtIndexPath:indexPath];
}

- (BOOL)xrk_boolForKey:(NSString *)key {
    for (PSSpecifier *spec in _xrkAllSpecifiers) {
        if ([[spec propertyForKey:@"key"] isEqualToString:key]) return [[self readPreferenceValue:spec] boolValue];
    }
    return NO;
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    [super setPreferenceValue:value specifier:specifier];

    NSString *key = [specifier propertyForKey:@"key"];
    if (!key) return;
    NSMutableArray *dependents = [NSMutableArray array];
    for (PSSpecifier *spec in _xrkAllSpecifiers) {
        if ([[spec propertyForKey:@"xrkRequires"] isEqualToString:key]) [dependents addObject:spec];
    }
    if (!dependents.count) return;

    if ([value boolValue]) {
        NSMutableArray *missing = [NSMutableArray array];
        for (PSSpecifier *spec in dependents) {
            if (![_specifiers containsObject:spec]) [missing addObject:spec];
        }
        if (missing.count) [self insertContiguousSpecifiers:missing afterSpecifier:specifier animated:YES];
    } else {
        NSMutableArray *present = [NSMutableArray array];
        for (PSSpecifier *spec in dependents) {
            if ([_specifiers containsObject:spec]) [present addObject:spec];
        }
        if (present.count) [self removeContiguousSpecifiers:present animated:YES];
    }
}

@end
