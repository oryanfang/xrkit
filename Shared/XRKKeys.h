// 所有偏好键集中在这里，与 Prefs/Resources/*.plist 里的 key 保持一致
#pragma once

// 总开关
#define kXRKEnabled            @"enabled"

// 主屏幕 · 隐藏
#define kXRKHideHomeBar        @"hideHomeBar"
#define kXRKHideTodayPage      @"sbHideTodayPage"
#define kXRKHideAppLibrary     @"sbHideAppLibrary"      // 需要注销生效
#define kXRKHidePageDots       @"sbHidePageDots"
#define kXRKHideIconLabels     @"sbHideIconLabels"
#define kXRKHideBadges         @"sbHideBadges"
#define kXRKHideFolderBg       @"sbHideFolderBackground"
#define kXRKFolderFirstIcon    @"sbFolderFirstIcon"
// 「隐藏底部搜索按钮」不存 xrkit 偏好，直接读写系统设置（见 Prefs/XRKRootListController.m）

#define kXRKDownloadPercent    @"sbDownloadPercent"     // 下载中的 App 图标中间显示百分比
#define kXRKBadgeIconColor     @"sbBadgeIconColor"      // 角标改成图标主色调，数字自动黑/白

// Dock
#define kXRKDockHide           @"dockHide"
#define kXRKDockBackground     @"dockBackgroundStyle"   // 0 系统 / 1 透明 / 2 深色 / 3 浅色
#define kXRKDockIconCount      @"dockIconCount"         // 3～6，4 = 系统默认；需要注销生效
#define kXRKDockRunningDots    @"dockRunningDots"       // 运行中的 App 图标下面显示白点
#define kXRKDockRecentApps     @"dockRecentApps"        // 竖线右边显示几个运行中的 App：0 关，1～3；即时生效

// 主屏幕 · 图标透明度
#define kXRKIdleFade           @"sbIdleFade"
#define kXRKIdleFadeAlpha      @"sbIdleFadeAlpha"       // 0.1～1，默认 0.4
#define kXRKIdleFadeDelay      @"sbIdleFadeDelay"       // 秒，0.5～10，默认 3

// 控制中心
#define kXRKCCBackgroundAlpha  @"ccBackgroundAlpha"     // 0～1，默认 1（系统）
#define kXRKCCModuleAlpha      @"ccModuleAlpha"         // 0～1，默认 1（系统）
#define kXRKCCHideStatusBar    @"ccHideStatusBar"
#define kXRKCCSliderPercent    @"ccSliderPercent"       // 亮度 / 音量滑块显示百分比
#define kXRKCCCornerScale      @"ccCornerScale"         // 模块圆角 0～1.5，默认 1（系统）
#define kXRKCCModuleLoader     @"ccModuleLoader"        // 「启用更多控件」：xrkit 加载控制中心模块（替代 CCSupport）；需注销，检测到 CCSupport 时不启用

// 锁屏
#define kXRKLSHideFlashlight      @"lsHideFlashlight"
#define kXRKLSHideCamera          @"lsHideCamera"
#define kXRKLSHideCallToAction    @"lsHideCallToAction"     // 「上滑打开」
#define kXRKLSHideCCGrabber       @"lsHideCCGrabber"        // 右上角控制中心提示条
#define kXRKLSDisableCameraSwipe  @"lsDisableCameraSwipe"   // 需要注销生效
#define kXRKLSChargePercent       @"lsChargePercent"        // 充电时锁屏底部显示电量
#define kXRKLSNowPlaying          @"lsNowPlaying"           // 音乐播放器：0 系统 / 1 暂停后收起 / 2 完全隐藏
#define kXRKLSDisableSearch       @"lsDisableSearch"        // 禁止下滑搜索
// 锁屏 · 面容识别
#define kXRKLSAutoUnlock          @"lsAutoUnlock"           // 面容识别后直接进主屏幕
#define kXRKLSAutoUnlockStay      @"lsAutoUnlockStay"       // 有通知时停在锁屏（默认开）

// 多任务
#define kXRKSwHideTitles          @"swHideTitles"           // 隐藏卡片上的名称和图标
#define kXRKSwLockApps            @"swLockApps"             // 长按卡片锁定，锁住的划不掉
#define kXRKSwLockedApps          @"swLockedApps"           // 锁定的 Bundle ID 数组（插件在 SpringBoard 里写）
#define kXRKSwPullDownClear       @"swPullDownClear"        // 任意卡片往下拉清除全部
#define kXRKSwStyle               @"swStyle"                // 排列样式：0 系统（堆叠）/ 2 网格 / 3 iPad（见 GridFull.x）；需注销
#define kXRKSwCardScale           @"swCardScale"            // 卡片大小 0.6～1.3，默认 1（iPad 样式下再乘 1.105）
#define kXRKSwCardCorner          @"swCardCorner"           // 卡片圆角 0～2，默认 1
#define kXRKSwCardSpacing         @"swCardSpacing"          // 卡片间距 0.5～2，默认 1
#define kXRKSwCardYOffset         @"swCardYOffset"          // 卡片上下位置 -0.15～0.15（屏幕高度比例，负数往上），默认 0；实际位置 = 基准（≈ 系统原位）+ 这个值

// 截图
#define kXRKNoScreenshotPreview   @"noScreenshotPreview"    // 截图不显示左下角预览，直接存相册
