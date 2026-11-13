// 截图不显示左下角预览（设置在主屏幕页）
//
// -[SpringBoard _takeScreenshotWithOptionsCollection:presentationOptions:]（按键截屏、xrkit 截屏模块都走这里）先问
// +[SSScreenCapturer shouldUseScreenCapturerForScreenshots]（ScreenshotServices）：
//   是 → 交给截屏服务（左下角缩略图预览、点开编辑）；否 → 老流程 -[SBScreenshotManager saveScreenshots]
//   （闪白 + 直接存进相册，没有预览）。iOS 17.3.1 符号 + 反汇编核对过。
// 打开时让它回答"否"。
#import "XRKCommon.h"
#import <dlfcn.h>

%group XRKNoScreenshotPreview
%hook SSScreenCapturer

+ (BOOL)shouldUseScreenCapturerForScreenshots {
    return XRKOn(kXRKNoScreenshotPreview) ? NO : %orig;
}

%end
%end

void XRKInitScreenshot(void) {
    dlopen("/System/Library/PrivateFrameworks/ScreenshotServices.framework/ScreenshotServices", RTLD_NOW);
    BOOL ok = XRKClassResponds("SSScreenCapturer", @[@"shouldUseScreenCapturerForScreenshots"]) &&
              XRKResponds("SBScreenshotManager", @[@"saveScreenshots"]);
    XRKDebugLog(@"[Screenshot] ok=%d", ok);
    if (ok) %init(XRKNoScreenshotPreview);
}
