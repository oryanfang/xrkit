#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>

@interface XRKRootListController : PSListController
@end

// 通用子页面：根据 specifier 上的 plistName 加载对应的 Resources/<plistName>.plist
@interface XRKSubListController : PSListController
@end
