// 控制中心模块加载器（替代 CCSupport，从头写）：在 SpringBoard 和「设置」两个进程里都运行
//
// 系统（ControlCenterServices，iOS 17.3.1 符号 + 反汇编核对过）：
// - +[CCSModuleRepository _defaultModuleDirectories]：扫描模块的目录，默认只有 /System/Library/ControlCenter/Bundles
// - +[CCSModuleRepository _defaultModuleIdentifierAllowedList]：白名单（框架里的一个 plist），不在名单上的模块被过滤
// - +[CCSModuleSettingsProvider _configurationFileURL]：模块顺序 / 启用配置
//   （/var/mobile/Library/ControlCenter/ModuleConfiguration.plist，键 module-identifiers / disabled-module-identifiers /
//    userenabled-fixed-module-identifiers / version）
// - +[CCSModuleSettingsProvider _defaultFixedModuleIdentifiers] 等：固定模块（网络、音乐、专注……），设置里不能动
//
// 我们：
// 1. 目录加上越狱根下的 /Library/ControlCenter/Bundles（roothide：jbroot()）
// 2. 白名单并上那个目录里扫到的模块 ID
// 3. 配置改用 jbroot 下的 ModuleConfiguration_xrkit.plist；第一次从 CCSupport 的那份（或系统那份）复制，布局原样保留
// 4. 固定模块清单清空，原来的固定模块并进普通模块列表 → 能移动、能删除
// 5. 检测到 CCSupport.dylib 已加载就什么都不做（两个加载器同时改同一份东西会冲突）
// 设置页的名字 / 图标在 CCModulesSettings.x。
#import "XRKCommon.h"
#import <mach-o/dyld.h>
#import <roothide.h>

#define XRK_CC_CONFIG_NAME     @"ModuleConfiguration_xrkit.plist"
#define XRK_CC_CCSUPPORT_NAME  @"ModuleConfiguration_CCSupport.plist"

@interface CCSModuleRepository : NSObject
@end

@interface CCSModuleSettingsProvider : NSObject
@end

#pragma mark - 工具

static BOOL XRKCCSupportLoaded(void) {
    static int cached = -1;
    if (cached >= 0) return cached;
    cached = 0;
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char *name = _dyld_get_image_name(i);
        if (name && strstr(name, "CCSupport.dylib")) { cached = 1; break; }
    }
    return cached;
}

static NSURL *XRKCCThirdPartyBundlesURL(void) {
    return [NSURL fileURLWithPath:jbroot(@"/Library/ControlCenter/Bundles") isDirectory:YES];
}

// 第三方模块目录里每个 .bundle 的 CFBundleIdentifier（启动时扫一次；装新模块需要注销，和 CCSupport 一样）
static NSDictionary<NSString *, NSURL *> *XRKCCThirdPartyModules(void) {
    static NSDictionary *modules;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableDictionary *found = [NSMutableDictionary dictionary];
        NSURL *dir = XRKCCThirdPartyBundlesURL();
        NSArray *items = [NSFileManager.defaultManager contentsOfDirectoryAtURL:dir includingPropertiesForKeys:nil options:0 error:nil];
        for (NSURL *url in items) {
            if (![url.pathExtension isEqualToString:@"bundle"]) continue;
            NSDictionary *info = [NSDictionary dictionaryWithContentsOfURL:[url URLByAppendingPathComponent:@"Info.plist"]];
            NSString *bid = info[@"CFBundleIdentifier"];
            if ([bid isKindOfClass:[NSString class]] && bid.length) found[bid] = url;
        }
        modules = [found copy];
    });
    return modules;
}

static NSURL *XRKCCConfigURL(void) {
    return [NSURL fileURLWithPath:jbroot([@"/var/mobile/Library/ControlCenter" stringByAppendingPathComponent:XRK_CC_CONFIG_NAME])];
}

// 原来的固定模块（启动时从系统取一次，用来并进普通列表）
static NSArray<NSString *> *gSystemFixedModules;

// 第一次用 xrkit 的配置：从 CCSupport（越狱根）→ 系统（真实根）里找一份现成的复制过来，并保证原固定模块都在列表里
static void XRKCCPrepareConfig(void) {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSURL *dst = XRKCCConfigURL();
    if ([fm fileExistsAtPath:dst.path]) return;
    [fm createDirectoryAtURL:dst.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];

    NSArray *sources = @[
        jbroot([@"/var/mobile/Library/ControlCenter" stringByAppendingPathComponent:XRK_CC_CCSUPPORT_NAME]),
        @"/var/mobile/Library/ControlCenter/ModuleConfiguration.plist",
    ];
    NSMutableDictionary *config = nil;
    NSString *from = nil;
    for (NSString *path in sources) {
        NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:path];
        if ([d[@"module-identifiers"] isKindOfClass:[NSArray class]]) {
            config = [d mutableCopy];
            from = path;
            break;
        }
    }
    if (!config) return;   // 一份都没有：交给系统按默认生成

    NSMutableArray *enabled = [config[@"module-identifiers"] mutableCopy];
    NSArray *disabled = [config[@"disabled-module-identifiers"] isKindOfClass:[NSArray class]] ? config[@"disabled-module-identifiers"] : @[];
    // 从系统那份迁过来时，固定模块不在列表里 → 按原顺序放到最前面
    NSUInteger insert = 0;
    for (NSString *fixed in gSystemFixedModules) {
        if ([enabled containsObject:fixed] || [disabled containsObject:fixed]) continue;
        [enabled insertObject:fixed atIndex:insert++];
    }
    config[@"module-identifiers"] = enabled;
    config[@"userenabled-fixed-module-identifiers"] = @[];
    [config writeToURL:dst atomically:YES];
    XRKDebugLog(@"[CCModules] config created from %@ (%lu modules)", from, (unsigned long)enabled.count);
}

#pragma mark - hooks

%group XRKCCLoader
%hook CCSModuleRepository

+ (NSArray<NSURL *> *)_defaultModuleDirectories {
    NSArray *dirs = %orig ?: @[];
    NSURL *extra = XRKCCThirdPartyBundlesURL();
    if ([dirs containsObject:extra]) return dirs;
    return [dirs arrayByAddingObject:extra];
}

+ (NSSet<NSString *> *)_defaultModuleIdentifierAllowedList {
    NSSet *allowed = %orig;
    if (!allowed) return nil;   // 没有白名单 = 不过滤
    return [allowed setByAddingObjectsFromArray:XRKCCThirdPartyModules().allKeys];
}

%end

%hook CCSModuleSettingsProvider

+ (NSURL *)_configurationFileURL {
    return XRKCCConfigURL();
}

+ (NSArray<NSString *> *)_defaultFixedModuleIdentifiers {
    return @[];
}

+ (NSArray<NSString *> *)_defaultUserEnabledFixedModuleIdentifiers {
    return @[];
}

// 全新配置（没有任何旧文件）时，原固定模块排在最前面
+ (NSArray<NSString *> *)_defaultEnabledModuleOrder {
    NSArray *order = %orig ?: @[];
    NSMutableArray *result = [NSMutableArray arrayWithArray:gSystemFixedModules ?: @[]];
    for (NSString *m in order) if (![result containsObject:m]) [result addObject:m];
    return result;
}

%end
%end

#pragma mark - 初始化

BOOL XRKInitCCModules(void) {
    BOOL ok = XRKClassResponds("CCSModuleRepository", @[@"_defaultModuleDirectories", @"_defaultModuleIdentifierAllowedList"]) &&
              XRKClassResponds("CCSModuleSettingsProvider", @[@"_configurationFileURL", @"_defaultFixedModuleIdentifiers",
                                                              @"_defaultUserEnabledFixedModuleIdentifiers", @"_defaultEnabledModuleOrder"]);
    BOOL ccsupport = XRKCCSupportLoaded();
    BOOL on = XRKOn(kXRKCCModuleLoader);
    XRKDebugLog(@"[CCModules] ok=%d on=%d ccsupport=%d thirdParty=%lu (%@)", ok, on, ccsupport,
                (unsigned long)XRKCCThirdPartyModules().count, NSProcessInfo.processInfo.processName);
    if (!ok || !on || ccsupport) return NO;

    // 先取系统原来的固定模块（hook 之前）
    id fixed = ((id (*)(id, SEL))objc_msgSend)(objc_getClass("CCSModuleSettingsProvider"), @selector(_defaultFixedModuleIdentifiers));
    gSystemFixedModules = [fixed isKindOfClass:[NSArray class]] ? [fixed copy] : @[];
    XRKCCPrepareConfig();
    %init(XRKCCLoader);
    return YES;
}
