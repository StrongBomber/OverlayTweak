/**
 * OverlayManager.h — overlay lifecycle, gestures, persistence.
 */

#import <UIKit/UIKit.h>

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
- (void)clearOverlayImage;
- (UIImage *)currentImage;

- (void)setOpacity:(CGFloat)opacity;
- (CGFloat)currentOpacity;

- (void)setScale:(CGFloat)scale;
- (CGFloat)currentScale;

- (void)setRotation:(CGFloat)rotation;
- (CGFloat)currentRotation;

- (void)setLocked:(BOOL)locked;
- (void)toggleLock;

- (void)setFlipHorizontal:(BOOL)flip;
- (BOOL)flipHorizontal;
- (void)setFlipVertical:(BOOL)flip;
- (BOOL)flipVertical;

- (void)setContentModeIndex:(NSInteger)index;
- (NSInteger)contentModeIndex;

/// 0 = match photo aspect/size, 1 = custom width × height (points).
- (void)setSizeMode:(NSInteger)mode;
- (NSInteger)sizeMode;
- (CGSize)customSize;
- (void)setCustomSize:(CGSize)size;
- (CGSize)currentOverlaySize;
- (CGSize)imageNativeSize;
- (void)syncOverlaySizeAnimated:(BOOL)animated;

- (void)resetTransform;
- (void)resetAllSettings;

- (void)saveCurrentState;

- (void)showSettingsPanel;
- (void)hideSettingsPanel;

- (void)presentModal:(UIViewController *)viewController;
- (void)makeOverlayWindowKey;
- (void)restoreKeyWindow;

- (void)setMenuHidden:(BOOL)hidden;
- (BOOL)isMenuHidden;

- (void)showToast:(NSString *)text;

@end
