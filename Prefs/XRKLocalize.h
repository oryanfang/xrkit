// 设置页的中 / 英文：原文是中文，en.lproj/Localizable.strings 是英文（由 make_plists.py 生成）。
// 关于页「语言」（偏好 prefsLanguage）：0 跟随系统——系统是中文时 NSBundle 选 zh-Hans.lproj（空表），查不到就用原文，
// 其他语言选 en.lproj；1 一律中文；2 一律英文。
#pragma once
#import <Foundation/Foundation.h>
#import <Preferences/PSSpecifier.h>

static inline NSBundle *XRKPrefsBundle(void) {
    static NSBundle *bundle;
    if (!bundle) bundle = [NSBundle bundleForClass:NSClassFromString(@"XRKRootListController")];
    return bundle;
}

typedef NS_ENUM(NSInteger, XRKPrefsLanguage) { XRKPrefsLanguageSystem = 0, XRKPrefsLanguageChinese = 1, XRKPrefsLanguageEnglish = 2 };
extern NSInteger gXRKPrefsLanguage;   // -1 = 还没读偏好（定义在 XRKRootListController.m，各文件共用一份）

static inline XRKPrefsLanguage XRKCurrentPrefsLanguage(void) {
    if (gXRKPrefsLanguage < 0) {
        CFPropertyListRef v = CFPreferencesCopyAppValue(CFSTR("prefsLanguage"), CFSTR("com.xyrith.xrkit"));
        gXRKPrefsLanguage = (v && CFGetTypeID(v) == CFNumberGetTypeID()) ? [(__bridge NSNumber *)v integerValue] : 0;
        if (v) CFRelease(v);
    }
    return (XRKPrefsLanguage)gXRKPrefsLanguage;
}

// 设置页里选了新语言（XRKSubListController -setPreferenceValue:specifier:）
static inline void XRKSetPrefsLanguage(NSInteger lang) { gXRKPrefsLanguage = lang; }

static inline NSString *XRKL(NSString *text) {
    if (!text.length) return text;
    switch (XRKCurrentPrefsLanguage()) {
        case XRKPrefsLanguageChinese: return text;
        case XRKPrefsLanguageEnglish: {
            static NSDictionary *english;
            if (!english) {
                NSString *path = [XRKPrefsBundle() pathForResource:@"Localizable" ofType:@"strings" inDirectory:nil forLocalization:@"en"];
                english = [NSDictionary dictionaryWithContentsOfFile:path] ?: @{};
            }
            return english[text] ?: text;
        }
        default: return [XRKPrefsBundle() localizedStringForKey:text value:text table:@"Localizable"];
    }
}

// 设置页 plist 读进来以后，把名字、组说明、多选项的选项和说明都换成当前语言
static inline void XRKLocalizeSpecifiers(NSArray<PSSpecifier *> *specifiers) {
    for (PSSpecifier *spec in specifiers) {
        if (spec.name.length) spec.name = XRKL(spec.name);
        for (NSString *key in @[@"footerText", @"staticTextMessage", @"label"]) {
            id v = [spec propertyForKey:key];
            if ([v isKindOfClass:[NSString class]]) [spec setProperty:XRKL(v) forKey:key];
        }
        NSMutableDictionary *(^map)(NSDictionary *) = ^NSMutableDictionary *(NSDictionary *d) {
            NSMutableDictionary *m = [NSMutableDictionary dictionaryWithCapacity:d.count];
            [d enumerateKeysAndObjectsUsingBlock:^(id k, id v, BOOL *stop) { m[k] = [v isKindOfClass:[NSString class]] ? XRKL(v) : v; }];
            return m;
        };
        if (spec.titleDictionary.count) spec.titleDictionary = map(spec.titleDictionary);
        if (spec.shortTitleDictionary.count) spec.shortTitleDictionary = map(spec.shortTitleDictionary);
    }
}
