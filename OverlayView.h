/**
 * OverlayView.h — rasterized image overlay with border, flip, and crop chrome.
 */

#import <UIKit/UIKit.h>

@class OverlayView;

@protocol OverlayViewCropDelegate <NSObject>
- (void)overlayView:(OverlayView *)view didChangeCropInsets:(UIEdgeInsets)insets;
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
@property (nonatomic, weak) id<OverlayViewCropDelegate> cropDelegate;

- (instancetype)initWithFrame:(CGRect)frame image:(UIImage *)image;
- (void)clearImage;
- (void)setLockedAppearance:(BOOL)locked;
- (BOOL)isCropHandleView:(UIView *)view;
- (CGSize)croppedSize;

@end
