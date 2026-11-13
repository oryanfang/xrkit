// xrkit 截屏：收起控制中心后截屏（-[SpringBoard takeScreenshot]，和按键截屏同一套）
#import "../XRKModule.h"

@interface XRKScreenshotModule : CCUIToggleModule
@end

@implementation XRKScreenshotModule

- (UIImage *)iconGlyph { return XRKGlyph(@"camera.viewfinder"); }
- (UIColor *)selectedColor { return UIColor.systemGrayColor; }
- (BOOL)isSelected { return NO; }

- (void)setSelected:(BOOL)selected {
    [self.contentModuleContext dismissControlCenter];
    // 控制中心收起动画结束后再截，否则会截到半透明的控制中心
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        id app = UIApplication.sharedApplication;
        if ([app respondsToSelector:@selector(takeScreenshot)]) ((void (*)(id, SEL))objc_msgSend)(app, @selector(takeScreenshot));
    });
}

@end
