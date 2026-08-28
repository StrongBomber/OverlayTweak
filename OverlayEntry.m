/**
 * ==============================================================================
 * OverlayEntry.m - Dylib Giriş Noktası
 * ==============================================================================
 */

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#define OLLog(fmt, ...) NSLog(@"[Overlay] " fmt, ##__VA_ARGS__)

// ============================================================================
// Hedef Bundle ID (nil = tüm uygulamalar)
// ============================================================================
static NSString *const kTargetBundleID = nil;

// ============================================================================
// OverlayManager Forward Declaration
// ============================================================================
@interface OverlayManager : NSObject
+ (instancetype)sharedManager;
- (void)setup;
@end

// ============================================================================
// Swizzling
// ============================================================================
static BOOL swizzleMethod(Class cls, SEL originalSel, SEL swizzledSel) {
    if (!cls) return NO;
    Method orig = class_getInstanceMethod(cls, originalSel);
    Method swiz = class_getInstanceMethod(cls, swizzledSel);
    if (!orig || !swiz) return NO;
    method_exchangeImplementations(orig, swiz);
    OLLog(@"Swizzle: %@.%@", NSStringFromClass(cls), NSStringFromSelector(originalSel));
    return YES;
}

// ============================================================================
// Swizzled Metotlar (UIApplication kategorisinde tanımlı)
// ============================================================================

@interface UIApplication (OverlaySwizzle)
- (BOOL)overlay_app:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)opts;
- (void)overlay_becomeActive:(UIApplication *)app;
@end

@implementation UIApplication (OverlaySwizzle)

- (BOOL)overlay_app:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)opts {
    // Orijinal metodu çağır
    BOOL result = [self overlay_app:app didFinishLaunchingWithOptions:opts];
    OLLog(@"didFinishLaunchingWithOptions yakalandı!");

    // Overlay'i gecikmeli başlat
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        OLLog(@"Overlay başlatılıyor...");
        [[OverlayManager sharedManager] setup];
    });
    return result;
}

- (void)overlay_becomeActive:(UIApplication *)app {
    [self overlay_becomeActive:app];
    static BOOL once = NO;
    if (once) return;
    once = YES;
    OLLog(@"applicationDidBecomeActive fallback!");

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [[OverlayManager sharedManager] setup];
    });
}

@end

// ============================================================================
// NSNotification Fallback
// ============================================================================
static void notifFallback(CFNotificationCenterRef center, void *observer,
                          CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    OLLog(@"NSNotification fallback!");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [[OverlayManager sharedManager] setup];
    });
}

// ============================================================================
// Constructor
// ============================================================================
__attribute__((constructor))
static void overlay_entry(void) {
    OLLog(@"===========================================");
    OLLog(@"Dylib Loaded!");
    OLLog(@"Bundle: %@", [[NSBundle mainBundle] bundleIdentifier]);
    OLLog(@"iOS: %@", [[UIDevice currentDevice] systemVersion]);
    OLLog(@"===========================================");

    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    if (kTargetBundleID && ![bundleID isEqualToString:kTargetBundleID]) {
        OLLog(@"Hedef değil: %@", bundleID);
        return;
    }

    // AppDelegate'i bul
    UIApplication *app = [UIApplication sharedApplication];
    id appDelegate = app.delegate;

    if (appDelegate) {
        Class appDelegateClass = [appDelegate class];
        OLLog(@"AppDelegate: %@", NSStringFromClass(appDelegateClass));

        // didFinishLaunchingWithOptions: swizzle
        SEL origSel = @selector(application:didFinishLaunchingWithOptions:);
        SEL swizSel = @selector(overlay_app:didFinishLaunchingWithOptions:);

        Method swizMethod = class_getInstanceMethod([UIApplication class], swizSel);
        if (swizMethod) {
            IMP swizIMP = method_getImplementation(swizMethod);
            const char *encoding = method_getTypeEncoding(swizMethod);
            class_addMethod(appDelegateClass, swizSel, swizIMP, encoding);
            swizzleMethod(appDelegateClass, origSel, swizSel);
        }

        // applicationDidBecomeActive: fallback
        SEL origSel2 = @selector(applicationDidBecomeActive:);
        SEL swizSel2 = @selector(overlay_becomeActive:);
        Method swizMethod2 = class_getInstanceMethod([UIApplication class], swizSel2);
        if (swizMethod2) {
            IMP swizIMP2 = method_getImplementation(swizMethod2);
            const char *encoding2 = method_getTypeEncoding(swizMethod2);
            class_addMethod(appDelegateClass, swizSel2, swizIMP2, encoding2);
            swizzleMethod(appDelegateClass, origSel2, swizSel2);
        }
    } else {
        OLLog(@"AppDelegate bulunamadı!");
    }

    // NSNotification fallback
    CFNotificationCenterAddObserver(
        CFNotificationCenterGetLocalCenter(), NULL, notifFallback,
        CFSTR("UIApplicationDidFinishLaunchingNotification"),
        NULL, CFNotificationSuspensionBehaviorDeliverImmediately
    );

    OLLog(@"Tüm stratejiler hazır.");
}
