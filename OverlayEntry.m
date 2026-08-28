/**
 * OverlayEntry.m — dylib constructor. No fragile AppDelegate swizzling.
 *
 * Injection (insert_dylib) runs this before or around UIApplicationMain.
 * We wait for a real window/scene instead of touching UIKit too early.
 */

#import "OverlayCommon.h"
#import "OverlayManager.h"
#import <UIKit/UIKit.h>

#ifndef OVERLAY_TARGET_BUNDLE_ID
#define OVERLAY_TARGET_BUNDLE_ID nil
#endif

static NSString *const kTargetBundleID = OVERLAY_TARGET_BUNDLE_ID;

static BOOL OLBundleAllowed(void) {
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    if (!kTargetBundleID) return YES;
    return [bundleID isEqualToString:kTargetBundleID];
}

static void OLStart(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        OLLog(@"Starting OverlayManager (v%@) bundle=%@",
              kOLVersion, [[NSBundle mainBundle] bundleIdentifier]);
    });
    [[OverlayManager sharedManager] setup];
}

static void OLScheduleStart(NSTimeInterval delay) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        OLStart();
    });
}

__attribute__((constructor))
static void overlay_entry(void) {
    @autoreleasepool {
        OLLog(@"===========================================");
        OLLog(@"Dylib loaded  v%@", kOLVersion);
        OLLog(@"Bundle: %@", [[NSBundle mainBundle] bundleIdentifier] ?: @"(nil)");
        OLLog(@"===========================================");

        if (!OLBundleAllowed()) {
            OLLog(@"Skipping — not the target bundle.");
            return;
        }

        NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];

        [nc addObserverForName:UIApplicationDidFinishLaunchingNotification
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(__unused NSNotification *n) {
            OLLog(@"DidFinishLaunching");
            OLScheduleStart(0.35);
        }];

        [nc addObserverForName:UIApplicationDidBecomeActiveNotification
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(__unused NSNotification *n) {
            OLScheduleStart(0.15);
        }];

        if (@available(iOS 13.0, *)) {
            [nc addObserverForName:UISceneDidActivateNotification
                            object:nil
                             queue:[NSOperationQueue mainQueue]
                        usingBlock:^(__unused NSNotification *n) {
                OLScheduleStart(0.15);
            }];
        }

        /* Already past launch (late inject) or constructor after main(). */
        dispatch_async(dispatch_get_main_queue(), ^{
            UIApplication *app = [UIApplication sharedApplication];
            if (!app) {
                OLScheduleStart(0.8);
                return;
            }
            if (app.applicationState == UIApplicationStateBackground) return;
            OLScheduleStart(0.45);
        });
    }
}
