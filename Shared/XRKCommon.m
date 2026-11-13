#import "XRKCommon.h"

#pragma mark - 刷新登记

// 每项：@[keys 或 NSNull, 上次的值（可变数组）, block]
static NSMutableArray<NSArray *> *gRefreshers;

static NSArray *XRKSnapshot(NSArray<NSString *> *keys) {
    NSMutableArray *values = [NSMutableArray arrayWithCapacity:keys.count];
    for (NSString *key in keys) [values addObject:[[XRKPrefs shared] objectForKey:key] ?: NSNull.null];
    return values;
}

void XRKAddRefresher(NSArray<NSString *> *keys, void (^refresher)(void)) {
    if (!refresher) return;
    if (!gRefreshers) gRefreshers = [NSMutableArray array];
    NSMutableArray *last = keys ? [XRKSnapshot(keys) mutableCopy] : [NSMutableArray array];
    [gRefreshers addObject:@[keys ?: (id)NSNull.null, last, [refresher copy]]];
}

void XRKRunRefreshers(void) {
    for (NSArray *entry in gRefreshers) {
        NSArray *keys = entry[0] == NSNull.null ? nil : entry[0];
        if (keys) {
            NSArray *now = XRKSnapshot(keys);
            NSMutableArray *last = entry[1];
            if ([now isEqualToArray:last]) continue;
            [last setArray:now];
        }
        ((void (^)(void))entry[2])();
    }
}

#pragma mark - 显示 / 隐藏

static const void *kXRKSystemHiddenKey = &kXRKSystemHiddenKey;
static const void *kXRKHiddenByUsKey = &kXRKHiddenByUsKey;

BOOL XRKNoteSystemHidden(UIView *view, BOOL hidden) {
    NSNumber *old = objc_getAssociatedObject(view, kXRKSystemHiddenKey);
    if (!old || old.boolValue != hidden) objc_setAssociatedObject(view, kXRKSystemHiddenKey, @(hidden), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return hidden;
}

BOOL XRKSystemHidden(UIView *view) {
    NSNumber *v = objc_getAssociatedObject(view, kXRKSystemHiddenKey);
    return v ? v.boolValue : view.hidden;   // 没记过 = 我们还没碰过，当前值就是系统的
}

void XRKReapplyHidden(UIView *view) {
    if (view) [view setHidden:XRKSystemHidden(view)];
}

void XRKSetHiddenByUs(UIView *view, BOOL hide) {
    if (!view) return;
    BOOL ours = [objc_getAssociatedObject(view, kXRKHiddenByUsKey) boolValue];
    if (hide) {
        if (!view.hidden) {
            view.hidden = YES;
            objc_setAssociatedObject(view, kXRKHiddenByUsKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    } else if (ours) {
        view.hidden = NO;
        objc_setAssociatedObject(view, kXRKHiddenByUsKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

#pragma mark - 取私有成员视图

// 类 + 成员名 → Ivar（找不到存 NSNull，避免反复查）。只在主线程用。
static NSMutableDictionary *gIvarCache;

static Ivar XRKLookupIvar(Class cls, NSString *name) {
    if (!gIvarCache) gIvarCache = [NSMutableDictionary dictionary];
    NSString *key = [NSString stringWithFormat:@"%p.%@", (__bridge void *)cls, name];
    id cached = gIvarCache[key];
    if (cached) return cached == NSNull.null ? NULL : (Ivar)[cached pointerValue];
    Ivar ivar = class_getInstanceVariable(cls, name.UTF8String);
    // 只认对象类型的成员，避免把数值当对象读
    if (ivar && ivar_getTypeEncoding(ivar)[0] != '@') ivar = NULL;
    gIvarCache[key] = ivar ? [NSValue valueWithPointer:ivar] : NSNull.null;
    return ivar;
}

UIView *XRKViewIvar(id object, NSString *name) {
    if (!object) return nil;
    id value = nil;
    if ([name hasPrefix:@"_"] && NSThread.isMainThread) {
        Ivar ivar = XRKLookupIvar(object_getClass(object), name);
        if (ivar) value = object_getIvar(object, ivar);
        else return nil;
    } else {
        @try {
            value = [object valueForKey:name];
        } @catch (__unused NSException *e) {
            return nil;
        }
    }
    return [value isKindOfClass:UIView.class] ? value : nil;
}
