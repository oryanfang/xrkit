#!/usr/bin/env python3
# 生成 Prefs/Resources 下的设置页 plist（Root / SpringBoard / LockScreen / ControlCenter / Switcher / Beta）。
# 改设置页就改这里，然后运行：python3 Prefs/make_plists.py
#
# 写法约定（紧凑排版）：
# - 多选项用单行列表（PSLinkListCell，点进去选，右边显示当前值），长说明放进列表页底部（message）
# - 滑块用单行 XRKSliderCell，同一组 name_chars 写成一样，滑块左端才对齐
# - 需要注销才生效的项：respring=True → 名字后面显示橙色小标签「需注销」，说明文字里不再重复
# - 即时生效不写；「下次打开控制中心 / 多任务生效」这类才在组底部说明
import plistlib, os

DOMAIN = "com.xyrith.xrkit"
NOTIFY = "com.xyrith.xrkit/prefschanged"
# 版本号从 control 读（升版本只改 control）
VERSION = next(l.split(":", 1)[1].strip() for l in open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "control"))
               if l.startswith("Version:"))
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "Resources")


def group(label=None, footer=None):
    d = {"cell": "PSGroupCell"}
    if label: d["label"] = label
    if footer: d["footerText"] = footer
    return d


def _pref(d, key, default, respring, requires):
    d.update({"key": key, "default": default, "defaults": DOMAIN, "PostNotification": NOTIFY})
    if respring: d["xrkRespring"] = True
    if requires: d["xrkRequires"] = requires
    return d


def switch(label, key, default=False, respring=False, requires=None):
    return _pref({"cell": "PSSwitchCell", "label": label}, key, default, respring, requires)


def choice(label, key, values, titles, default, short=None, message=None, respring=False, requires=None):
    d = {"cell": "PSLinkListCell", "detail": "PSListItemsController", "label": label,
         "validValues": values, "validTitles": titles}
    if short: d["shortTitles"] = short
    if message: d["staticTextMessage"] = message
    return _pref(d, key, default, respring, requires)


def slider(label, key, default, lo, hi, fmt, name_chars, requires=None):
    d = {"cell": "PSStaticTextCell", "cellClass": "XRKSliderCell", "label": label,
         "min": lo, "max": hi, "xrkFormat": fmt, "xrkNameChars": name_chars}
    return _pref(d, key, default, False, requires)


def value(label, text):
    # 只读的一行：名字在左、值在右（XRKSubListController -xrkStaticValue: 返回 xrkValue）
    return {"cell": "PSTitleValueCell", "label": label, "get": "xrkStaticValue:", "xrkValue": text}


def button(label, action):
    return {"cell": "PSButtonCell", "label": label, "action": action}


def link(label, plist, icon=None):
    d = {"cell": "PSLinkCell", "label": label, "detail": "XRKSubListController", "plistName": plist}
    if icon and os.path.exists(os.path.join(OUT, icon)): d["icon"] = icon   # 图标还没画好时先不写
    return d


PAGES = {}

PAGES["Root"] = ("xrkit", [
    group(),
    switch("启用 xrkit", "enabled", True, respring=True),
    group(),
    link("主屏幕", "SpringBoard", "SpringBoard.png"),
    link("锁屏", "LockScreen", "LockScreen.png"),
    link("控制中心", "ControlCenter", "ControlCenter.png"),
    link("多任务", "Switcher", "Switcher.png"),
    group("实验", "还在测试、可能不稳定的功能。"),
    link("Beta", "Beta", "Beta.png"),
    group(),
    # 关于的图标用 xrkit 自己的图标（About.png 由 make_logo.swift 导出）
    link("关于", "About", "About.png"),
    # 注销在导航栏右上角（XRKRootListController -viewDidLoad）
])

PAGES["About"] = ("关于", [
    # 只写验证过的，避免夸大：iOS 15、16 能装但没测过，不写"支持"
    group(None, "只在 iOS 17.3.1 上测试过。需要 roothide 越狱环境，只装了巨魔的手机用不了。打开本页时会到 GitHub 查一次有没有新版本。"),
    # 版本行：打开关于页时查 GitHub 最新 Release，有新版就显示「有新版 x.x.x」，点开是 Release 页（XRKSubListController）
    dict(value("版本", VERSION), get="xrkVersionValue:", xrkVersion=True),
    value("作者", "xyrith"),
    value("适用系统", "iOS 17"),
    value("越狱环境", "roothide"),
    # 设置页语言（只影响设置页，XRKLocalize.h）：0 跟随系统 / 1 中文 / 2 English；改了马上重新加载，不用注销
    group(),
    choice("语言", "prefsLanguage", [0, 1, 2], ["跟随系统", "中文", "English"], 0, short=["跟随系统", "中文", "English"]),
    group("软件源与反馈", "软件源地址：https://oryanfang.github.io/repo/\n「复制问题信息」会复制 xrkit 版本、iOS 版本、机型和改过的设置（锁定的 App 只写数量），可以贴进反馈里。"),
    button("软件源", "xrkOpenRepo"),
    button("反馈问题", "xrkOpenIssues"),
    button("复制问题信息", "xrkCopyInfo"),
    group(None, "把 xrkit 的所有开关和滑块恢复成默认值，多任务里锁定的 App 也会清空。完成后需要注销。"),
    button("重置所有设置", "xrkResetAll"),
])

PAGES["SpringBoard"] = ("主屏幕", [
    group("隐藏", "「底部搜索按钮」和系统设置里的同一个开关同步。"),
    switch("底部横条", "hideHomeBar"),
    switch("负一屏", "sbHideTodayPage"),
    switch("App 资源库", "sbHideAppLibrary", respring=True),
    switch("页面圆点", "sbHidePageDots"),
    # 不存 xrkit 偏好，直接读写系统设置（XRKRootListController.m 里的 xrkHideSearch）
    {"cell": "PSSwitchCell", "label": "底部搜索按钮", "id": "xrkHideSearch",
     "get": "xrkHideSearch:", "set": "setXrkHideSearch:specifier:"},
    switch("图标名称", "sbHideIconLabels"),
    switch("通知角标", "sbHideBadges"),

    group("文件夹", "显示第一个 App 的图标时，文件夹的角标照常显示，点按仍是打开文件夹。"),
    switch("隐藏文件夹背景", "sbHideFolderBackground"),
    switch("显示第一个 App 的图标", "sbFolderFirstIcon"),

    group("Dock", "减少图标数量前，先把多出来的图标拖出 Dock，否则会被系统挪到主屏幕其他位置。"),
    switch("隐藏整个 Dock", "dockHide"),
    choice("背景", "dockBackgroundStyle", [0, 1, 2, 3], ["系统", "透明", "深色", "浅色"], 0),
    choice("图标数量", "dockIconCount", [3, 4, 5, 6], ["3 个", "4 个（系统）", "5 个", "6 个"], 4,
           short=["3", "4", "5", "6"], message="6 个时图标会自动缩小一点才放得下。", respring=True),

    group("图标", "静止时半透明：碰到屏幕马上恢复，抬手后过一会儿再淡回去。"),
    switch("角标使用图标主色调", "sbBadgeIconColor"),
    switch("下载时显示百分比", "sbDownloadPercent"),
    switch("静止时半透明", "sbIdleFade"),
    slider("透明度", "sbIdleFadeAlpha", 0.4, 0.1, 1.0, "percent", 3, requires="sbIdleFade"),
    slider("延迟", "sbIdleFadeDelay", 3.0, 0.5, 10.0, "seconds", 3, requires="sbIdleFade"),

    group("截图", "截图后直接存进相册，不弹出左下角的缩略图。控制中心里的截屏模块也一样。"),
    switch("不显示左下角预览", "noScreenshotPreview"),
])

PAGES["LockScreen"] = ("锁屏", [
    group("隐藏", "隐藏相机按钮后仍能左滑打开相机，要一起禁掉就打开下面的「禁止左滑打开相机」。"),
    switch("手电筒按钮", "lsHideFlashlight"),
    switch("相机按钮", "lsHideCamera"),
    switch("「上滑打开」", "lsHideCallToAction"),
    switch("右上角控制中心提示条", "lsHideCCGrabber"),

    group("手势"),
    switch("禁止左滑打开相机", "lsDisableCameraSwipe", respring=True),
    switch("禁止下滑搜索", "lsDisableSearch"),

    group("面容识别", "识别成功后直接进主屏幕，不用再上滑。屏幕没亮、在小组件页、待机显示时不会自动进入。"
                     "打开「有通知时停在锁屏」后，锁屏上有通知或音乐时会先停下来。"),
    switch("直接进主屏幕", "lsAutoUnlock"),
    switch("有通知时停在锁屏", "lsAutoUnlockStay", True, requires="lsAutoUnlock"),

    group("显示", "充电时电量显示在锁屏底部两个按钮中间。"),
    switch("充电时显示电量", "lsChargePercent"),
    choice("音乐播放器", "lsNowPlaying", [0, 1, 2], ["系统", "暂停后收起", "完全隐藏"], 0,
           message="「暂停后收起」：暂停后播放器马上从锁屏消失（系统会再留一段时间）。\n「完全隐藏」：播放时也不在锁屏显示。"),
])

PAGES["ControlCenter"] = ("控制中心", [
    group("外观", "100% 是系统原样，下次打开控制中心生效。音乐等模块自己画背景，不受「模块背景」影响。"),
    slider("整体背景", "ccBackgroundAlpha", 1.0, 0.0, 1.0, "percent", 4),
    slider("模块背景", "ccModuleAlpha", 1.0, 0.0, 1.0, "percent", 4),
    slider("模块圆角", "ccCornerScale", 1.0, 0.0, 1.5, "percent", 4),

    group("显示"),
    switch("亮度和音量显示百分比", "ccSliderPercent"),
    switch("隐藏状态栏", "ccHideStatusBar"),

    group("更多控件", "打开后，xrkit 自带的控件（注销、锁屏、截屏、VPN、网速、电池等）和其他插件的控件都能加进控制中心；"
                     "网络、音乐这些原本固定的控件也能在「设置 › 控制中心」里移动或删掉。现在的控件排列会保留。装了 CCSupport 时这个开关不起作用。"),
    switch("启用更多控件", "ccModuleLoader", respring=True),
])

PAGES["Switcher"] = ("多任务", [
    group(),
    choice("排列样式", "swStyle", [0, 2, 3], ["系统（堆叠）", "网格", "iPad"], 0, short=["系统", "网格", "iPad"],
           message="「网格」：卡片排成网格，上滑和打开、关闭的手感还是 iPhone 那套。\n"
                   "「iPad」：直接用 iPad 的多任务界面和手势。带卡死保护：万一卡住超过 5 秒，会自动改回「系统」并重启桌面。",
           respring=True),

    group("卡片", "长按卡片锁定 / 解锁：锁住的卡片在 App 图标左边显示小锁，划不掉，清除全部时也会跳过。"),
    switch("隐藏名称和图标", "swHideTitles"),
    switch("长按锁定 App", "swLockApps"),
    switch("往下拉清除全部", "swPullDownClear"),

    group("卡片格式", "100% / 0% 是默认样子，下次打开多任务生效；「iPad」样式下要注销才生效。"),
    slider("大小", "swCardScale", 1.0, 0.6, 1.3, "percent", 4),
    slider("圆角", "swCardCorner", 1.0, 0.0, 2.0, "percent", 4),
    slider("间距", "swCardSpacing", 1.0, 0.5, 2.0, "percent", 4),
    slider("上下位置", "swCardYOffset", 0.0, -0.15, 0.15, "signedPercent", 4),
])

PAGES["Beta"] = ("Beta", [
    group(None, "这里的功能还在测试，可能不稳定。遇到桌面卡住、Dock 错位，先关掉这里的开关；"
                "万一反复重启进了安全模式，xrkit 不会加载，回来关掉即可。"),
    group("Mac 风格 Dock", "竖线右边显示在多任务里、但不在 Dock 里的 App，按最近使用排序，点按打开。"
                           "右边有 App 时 Dock 图标会自动缩小排开。"),
    switch("运行中的 App 显示白点", "dockRunningDots"),
    choice("竖线右边的 App", "dockRecentApps", [0, 1, 2, 3], ["关", "1 个", "2 个", "3 个"], 0),
])

# ---- 英文：中文原文 → 英文。系统语言不是中文时显示英文（XRKLocalize.h 的 XRKL / XRKLocalizeSpecifiers）。
# 设置页的文字和 Prefs/*.m 里 XRKL(@"…") 的文字都放这里；下面会检查有没有漏翻的。
EN = {
    # 首页
    "启用 xrkit": "Enable xrkit", "主屏幕": "Home Screen", "锁屏": "Lock Screen", "控制中心": "Control Center",
    "多任务": "App Switcher", "实验": "Experimental", "还在测试、可能不稳定的功能。": "Features still in testing; may be unstable.",
    "关于": "About", "语言": "Language", "跟随系统": "System", "中文": "中文",
    # 关于
    "只在 iOS 17.3.1 上测试过。需要 roothide 越狱环境，只装了巨魔的手机用不了。打开本页时会到 GitHub 查一次有没有新版本。":
        "Only tested on iOS 17.3.1. Requires a roothide jailbreak; it won't work with TrollStore alone. Opening this page checks GitHub once for a new version.",
    "版本": "Version", "作者": "Author", "适用系统": "Supported iOS", "越狱环境": "Jailbreak",
    "软件源与反馈": "Source & Feedback",
    "软件源地址：https://oryanfang.github.io/repo/\n「复制问题信息」会复制 xrkit 版本、iOS 版本、机型和改过的设置（锁定的 App 只写数量），可以贴进反馈里。":
        "Source: https://oryanfang.github.io/repo/\n\"Copy Debug Info\" copies the xrkit and iOS versions, device model and changed settings (locked apps as a count only) for pasting into a report.",
    "软件源": "Source", "反馈问题": "Report an Issue", "复制问题信息": "Copy Debug Info",
    "把 xrkit 的所有开关和滑块恢复成默认值，多任务里锁定的 App 也会清空。完成后需要注销。":
        "Restores every xrkit switch and slider to its default and clears locked apps in the App Switcher. Respring afterwards.",
    "重置所有设置": "Reset All Settings",
    # 主屏幕
    "隐藏": "Hide", "「底部搜索按钮」和系统设置里的同一个开关同步。": "\"Search Button\" is the same switch as the one in system Settings.",
    "底部横条": "Home Bar", "负一屏": "Today View", "App 资源库": "App Library", "页面圆点": "Page Dots",
    "底部搜索按钮": "Search Button", "图标名称": "Icon Labels", "通知角标": "Notification Badges",
    "文件夹": "Folders", "显示第一个 App 的图标时，文件夹的角标照常显示，点按仍是打开文件夹。":
        "When showing the first app's icon, the folder's badge still shows and tapping still opens the folder.",
    "隐藏文件夹背景": "Hide Folder Background", "显示第一个 App 的图标": "Show First App's Icon",
    "Dock": "Dock", "减少图标数量前，先把多出来的图标拖出 Dock，否则会被系统挪到主屏幕其他位置。":
        "Before lowering the icon count, drag the extra icons out of the Dock, or the system will move them elsewhere on the Home Screen.",
    "隐藏整个 Dock": "Hide Dock", "背景": "Background", "系统": "System", "透明": "Clear", "深色": "Dark", "浅色": "Light",
    "图标数量": "Icon Count", "3 个": "3", "4 个（系统）": "4 (System)", "5 个": "5", "6 个": "6",
    "6 个时图标会自动缩小一点才放得下。": "With 6 icons, they shrink slightly to fit.",
    "图标": "Icons", "静止时半透明：碰到屏幕马上恢复，抬手后过一会儿再淡回去。":
        "Fade When Idle: icons come back as soon as you touch the screen and fade again a moment after you lift your finger.",
    "角标使用图标主色调": "Badges Use Icon Color", "下载时显示百分比": "Download Percentage", "静止时半透明": "Fade When Idle",
    "透明度": "Opacity", "延迟": "Delay",
    "截图": "Screenshots", "截图后直接存进相册，不弹出左下角的缩略图。控制中心里的截屏模块也一样。":
        "Screenshots go straight to Photos without the thumbnail in the corner. Also applies to the Screenshot module in Control Center.",
    "不显示左下角预览": "No Thumbnail Preview",
    # 锁屏
    "隐藏相机按钮后仍能左滑打开相机，要一起禁掉就打开下面的「禁止左滑打开相机」。":
        "With the camera button hidden you can still swipe left for the camera; turn on \"Disable Camera Swipe\" below to block that too.",
    "手电筒按钮": "Flashlight Button", "相机按钮": "Camera Button", "「上滑打开」": "\"Swipe up to open\"",
    "右上角控制中心提示条": "Control Center Hint", "手势": "Gestures",
    "禁止左滑打开相机": "Disable Camera Swipe", "禁止下滑搜索": "Disable Pull-Down Search",
    "面容识别": "Face ID",
    "识别成功后直接进主屏幕，不用再上滑。屏幕没亮、在小组件页、待机显示时不会自动进入。打开「有通知时停在锁屏」后，锁屏上有通知或音乐时会先停下来。":
        "Go straight to the Home Screen after Face ID, no swipe needed. Not when the screen is off, on the widgets page or in StandBy. With \"Stay When Notified\" on, it stops on the Lock Screen when there are notifications or music.",
    "直接进主屏幕": "Unlock to Home Screen", "有通知时停在锁屏": "Stay When Notified",
    "显示": "Display", "充电时电量显示在锁屏底部两个按钮中间。": "While charging, the battery level shows between the two buttons at the bottom.",
    "充电时显示电量": "Battery While Charging", "音乐播放器": "Now Playing", "暂停后收起": "Hide When Paused", "完全隐藏": "Always Hide",
    "「暂停后收起」：暂停后播放器马上从锁屏消失（系统会再留一段时间）。\n「完全隐藏」：播放时也不在锁屏显示。":
        "Hide When Paused: the player leaves the Lock Screen as soon as you pause (the system keeps it a while).\nAlways Hide: never shown on the Lock Screen, even while playing.",
    # 控制中心
    "外观": "Appearance", "100% 是系统原样，下次打开控制中心生效。音乐等模块自己画背景，不受「模块背景」影响。":
        "100% is the system default. Takes effect the next time Control Center opens. Modules like Music draw their own background and aren't affected by \"Module Background\".",
    "整体背景": "Background", "模块背景": "Module Background", "模块圆角": "Corner Radius",
    "亮度和音量显示百分比": "Slider Percentages", "隐藏状态栏": "Hide Status Bar",
    "更多控件": "More Controls",
    "打开后，xrkit 自带的控件（注销、锁屏、截屏、VPN、网速、电池等）和其他插件的控件都能加进控制中心；网络、音乐这些原本固定的控件也能在「设置 › 控制中心」里移动或删掉。现在的控件排列会保留。装了 CCSupport 时这个开关不起作用。":
        "Lets you add xrkit's own controls (respring, lock, screenshot, VPN, network speed, battery…) and other tweaks' controls to Control Center, and move or remove fixed ones like Connectivity and Music in Settings › Control Center. Your current layout is kept. Has no effect while CCSupport is installed.",
    "启用更多控件": "Enable More Controls",
    # 多任务
    "排列样式": "Layout", "系统（堆叠）": "System (Stack)", "网格": "Grid", "iPad": "iPad",
    "「网格」：卡片排成网格，上滑和打开、关闭的手感还是 iPhone 那套。\n「iPad」：直接用 iPad 的多任务界面和手势。带卡死保护：万一卡住超过 5 秒，会自动改回「系统」并重启桌面。":
        "Grid: cards in a grid, with iPhone gestures and animations.\niPad: the iPad App Switcher and gestures. Has a freeze guard: if it hangs for more than 5 seconds it switches back to System and restarts SpringBoard.",
    "卡片": "Cards", "长按卡片锁定 / 解锁：锁住的卡片在 App 图标左边显示小锁，划不掉，清除全部时也会跳过。":
        "Long-press a card to lock or unlock it. Locked cards show a lock next to the app icon, can't be swiped away and are skipped by Clear All.",
    "隐藏名称和图标": "Hide Titles and Icons", "长按锁定 App": "Long-Press to Lock", "往下拉清除全部": "Pull Down to Clear All",
    "卡片格式": "Card Style", "100% / 0% 是默认样子，下次打开多任务生效；「iPad」样式下要注销才生效。":
        "100% / 0% is the default. Takes effect the next time the App Switcher opens; in the iPad layout it needs a respring.",
    "大小": "Size", "圆角": "Corners", "间距": "Spacing", "上下位置": "Position",
    # Beta
    "这里的功能还在测试，可能不稳定。遇到桌面卡住、Dock 错位，先关掉这里的开关；万一反复重启进了安全模式，xrkit 不会加载，回来关掉即可。":
        "These features are still in testing and may be unstable. If SpringBoard hangs or the Dock looks wrong, turn them off here; if it ends up in Safe Mode, xrkit won't load, so just come back and turn them off.",
    "Mac 风格 Dock": "Mac-Style Dock",
    "竖线右边显示在多任务里、但不在 Dock 里的 App，按最近使用排序，点按打开。右边有 App 时 Dock 图标会自动缩小排开。":
        "Apps in the App Switcher but not in the Dock appear to the right of a divider, most recent first; tap to open. The Dock icons shrink to make room.",
    "运行中的 App 显示白点": "Dots Under Running Apps", "竖线右边的 App": "Recent Apps", "关": "Off", "1 个": "1", "2 个": "2",
    # Prefs/*.m 里的文字
    "需注销": "Respring", "注销": "Respring", "确定要注销（重启 SpringBoard）吗？": "Respring (restart SpringBoard) now?",
    "取消": "Cancel", "有新版 %@": "Update: %@", "在 Sileo 中添加": "Add to Sileo", "复制地址": "Copy URL",
    "已复制": "Copied", "好": "OK", "重置": "Reset",
    "xrkit 的所有开关和滑块都会恢复默认，多任务里锁定的 App 也会清空。确定吗？":
        "All xrkit switches and sliders will go back to their defaults and locked apps will be cleared. Continue?",
    "已重置": "Reset Done", "有些设置要注销后才会完全恢复，现在注销吗？": "Some settings only fully reset after a respring. Respring now?",
    "稍后": "Later", "%.1f 秒": "%.1f s",
}
CODE_STRINGS = ["需注销", "注销", "确定要注销（重启 SpringBoard）吗？", "取消", "有新版 %@", "在 Sileo 中添加", "复制地址",
                "已复制", "好", "重置", "xrkit 的所有开关和滑块都会恢复默认，多任务里锁定的 App 也会清空。确定吗？", "已重置",
                "有些设置要注销后才会完全恢复，现在注销吗？", "稍后", "%.1f 秒", "重置所有设置", "软件源"]

def page_strings(title, items):
    out = [title]
    for it in items:
        for k in ("label", "footerText", "staticTextMessage"):
            if it.get(k): out.append(it[k])
        for k in ("validTitles", "shortTitles"):
            out += it.get(k, [])
    return out

needed = set(CODE_STRINGS)
for title, items in PAGES.values():
    needed.update(t for t in page_strings(title, items) if any(ord(c) > 127 for c in t))   # 纯英文 / 数字不用翻
missing = sorted(t for t in needed if t not in EN)
assert not missing, "这些文字还没有英文：\n" + "\n".join(missing)
for lang, table in (("en", EN), ("zh-Hans", {})):   # 中文用原文（空表 = 查不到就用原文）
    d = os.path.join(OUT, lang + ".lproj")
    os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, "Localizable.strings"), "wb") as f:
        plistlib.dump({k: table[k] for k in sorted(needed)} if table else {}, f, sort_keys=True)

for name, (title, items) in PAGES.items():
    with open(os.path.join(OUT, name + ".plist"), "wb") as f:
        plistlib.dump({"title": title, "items": items}, f, sort_keys=True)
    print(f"{name}.plist  {len(items)} 项")
