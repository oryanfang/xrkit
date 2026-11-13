// xrkit 桌面快捷入口：点开直接跳到「设置 → xrkit」
// 普通 App 打不开 prefs: 链接，这里用 LSApplicationWorkspace -openSensitiveURL:withOptions:，
// 需要 com.apple.springboard.opensensitiveurl 权限（见 entitlements.plist，越狱环境下用 ldid 签上）。
#import <UIKit/UIKit.h>

@interface LSApplicationWorkspace : NSObject
+ (instancetype)defaultWorkspace;
- (BOOL)openSensitiveURL:(NSURL *)url withOptions:(NSDictionary *)options;
@end

@interface XRKLauncherDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation XRKLauncherDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = [UIViewController new];
    self.window.rootViewController.view.backgroundColor = UIColor.systemBackgroundColor;
    [self.window makeKeyAndVisible];
    return YES;
}

// 每次被点开（包括从后台切回来）都跳一次
- (void)applicationDidBecomeActive:(UIApplication *)application {
    NSURL *url = [NSURL URLWithString:@"prefs:root=xrkit"];
    Class workspace = NSClassFromString(@"LSApplicationWorkspace");
    if (![[workspace defaultWorkspace] openSensitiveURL:url withOptions:nil]) {
        [application openURL:url options:@{} completionHandler:nil];
    }
}

@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(XRKLauncherDelegate.class));
    }
}
