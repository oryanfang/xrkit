// xrkit 设置：点一下打开 设置 › xrkit（模块自带的 -[CCUIContentModuleContext openURL:completionHandler:]，会自动收起控制中心）
#import "../XRKModule.h"

@interface XRKSettingsModule : CCUIToggleModule
@end

@implementation XRKSettingsModule

- (UIImage *)iconGlyph { return XRKGlyph(@"gearshape.fill"); }
- (UIColor *)selectedColor { return UIColor.systemGrayColor; }
- (BOOL)isSelected { return NO; }

- (void)setSelected:(BOOL)selected {
    [self.contentModuleContext openURL:[NSURL URLWithString:@"prefs:root=xrkit"] completionHandler:nil];
}

@end
