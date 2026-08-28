/**
 * ==============================================================================
 * OverlayManager.h
 * ==============================================================================
 */

#import <UIKit/UIKit.h>

extern NSString *const kDefaultsOpacity;
extern NSString *const kDefaultsPositionX;
extern NSString *const kDefaultsPositionY;
extern NSString *const kDefaultsScale;
extern NSString *const kDefaultsRotation;
extern NSString *const kDefaultsImageBookmark;
extern NSString *const kDefaultsIsLocked;
extern NSString *const kDefaultsOverlayVisible;

@interface OverlayManager : NSObject

+ (instancetype)sharedManager;

@property (nonatomic, strong, readonly) UIWindow *overlayWindow;
@property (nonatomic, strong, readonly) UIView *overlayContainer;
@property (nonatomic, assign, readonly) BOOL isOverlayVisible;
@property (nonatomic, assign, readonly) BOOL isLocked;
@property (nonatomic, assign, readonly) BOOL isSettingsVisible;

- (void)setup;
- (void)showOverlay;
- (void)hideOverlay;
- (void)toggleOverlay;
- (void)setOverlayImage:(UIImage *)image;
- (void)setOpacity:(CGFloat)opacity;
- (CGFloat)currentOpacity;
- (void)setLocked:(BOOL)locked;
- (void)toggleLock;
- (void)saveCurrentState;
- (void)showSettingsPanel;
- (void)hideSettingsPanel;
- (void)showTestAlert;

@end
