/**
 * OverlayView.h — rasterized image overlay with crop, warp, and perspective chrome.
 */

#import <UIKit/UIKit.h>

@class OverlayView;

@protocol OverlayViewCropDelegate <NSObject>
@optional
- (void)overlayView:(OverlayView *)view didChangeCropInsets:(UIEdgeInsets)insets;
- (void)overlayView:(OverlayView *)view didChangeWarpPoints:(NSArray<NSValue *> *)points;
- (void)overlayView:(OverlayView *)view didChangePitchDelta:(CGFloat)dPitch yawDelta:(CGFloat)dYaw;
@end

@interface OverlayView : UIView

@property (nonatomic, strong) UIImage *image;
@property (nonatomic, assign) CGFloat cornerRadius;
@property (nonatomic, assign) BOOL showsBorder;
@property (nonatomic, assign) UIViewContentMode imageContentMode;
@property (nonatomic, assign) BOOL flipHorizontal;
@property (nonatomic, assign) BOOL flipVertical;
@property (nonatomic, assign) BOOL showsGrid;
/// Unit insets 0–0.8 on each edge, relative to uncroppedSize.
@property (nonatomic, assign) UIEdgeInsets cropInsets;
/// Full overlay size before crop. Cropped bounds are computed from this.
@property (nonatomic, assign) CGSize uncroppedSize;
@property (nonatomic, assign) BOOL cropModeEnabled;
@property (nonatomic, assign) BOOL warpModeEnabled;
@property (nonatomic, assign) BOOL perspectiveModeEnabled;
/// 9 unit-space points (3×3, y-down). Identity is a regular grid.
@property (nonatomic, copy) NSArray<NSValue *> *warpPoints;
@property (nonatomic, weak) id<OverlayViewCropDelegate> cropDelegate;

+ (NSArray<NSValue *> *)identityWarpPoints;
+ (BOOL)warpPointsAreIdentity:(NSArray<NSValue *> *)points;

- (instancetype)initWithFrame:(CGRect)frame image:(UIImage *)image;
- (void)clearImage;
- (void)setLockedAppearance:(BOOL)locked;
- (BOOL)isCropHandleView:(UIView *)view;
- (CGSize)croppedSize;
- (UIEdgeInsets)clampedCropInsets:(UIEdgeInsets)insets;
- (void)resetWarp;
- (CGRect)cropRectInBounds;
- (void)beginColorSampling;
- (void)endColorSampling;
- (UIColor *)colorAtPoint:(CGPoint)point;
- (UIImage *)loupeImageAtPoint:(CGPoint)point;

@end
