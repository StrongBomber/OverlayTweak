/**
 * OverlayManager.h — overlay lifecycle, gestures, persistence.
 * Extended for CPM Image-to-Vinyl Automation (v2.0).
 */

#import <UIKit/UIKit.h>

@class CPMExecutionController;
@class CPMAutoDrawViewController;

NS_ASSUME_NONNULL_BEGIN

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

- (void)nudgeBy:(CGPoint)delta;
- (void)snapToAlignment:(NSInteger)alignment; /* 0 center, 1 left, 2 right, 3 top, 4 bottom */
- (void)rotateByDegrees:(CGFloat)degrees;

- (void)setShowsBorder:(BOOL)show;
- (BOOL)showsBorder;
- (void)setShowsGrid:(BOOL)show;
- (BOOL)showsGrid;

- (void)setPitch:(CGFloat)pitch;
- (CGFloat)pitch;
- (void)setYaw:(CGFloat)yaw;
- (CGFloat)yaw;
- (void)resetPerspective;

- (void)setCropInsets:(UIEdgeInsets)insets;
- (UIEdgeInsets)cropInsets;
- (void)resetCrop;
- (void)beginCropMode;
- (void)endCropMode;
- (BOOL)isCropModeEnabled;

- (void)beginWarpMode;
- (void)endWarpMode;
- (void)resetWarp;

- (void)beginPerspectiveMode;
- (void)endPerspectiveMode;

- (void)beginColorPickMode;
- (void)endColorPickMode;

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

// CPM Image-to-Vinyl Automation (v2.0)
- (void)showAutoDrawPanel;
- (void)hideAutoDrawPanel;
- (void)startAutoDrawWithImage:(UIImage *)image roiRect:(CGRect)roiRect;
- (void)pauseAutoDraw;
- (void)resumeAutoDraw;
- (void)stopAutoDraw;
- (void)emergencyStopAutoDraw;
- (void)clearAutoDrawSession;

@property (nonatomic, strong, readonly, nullable) id executionController;
@property (nonatomic, strong, readonly, nullable) id autoDrawViewController;
@property (nonatomic, assign, readonly) BOOL isAutoDrawRunning;
@property (nonatomic, assign, readonly) CGFloat autoDrawProgress;

@end

NS_ASSUME_NONNULL_END
