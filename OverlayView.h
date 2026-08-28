/**
 * OverlayView.h — rasterized image overlay with border + flip.
 */

#import <UIKit/UIKit.h>

@interface OverlayView : UIView

@property (nonatomic, strong) UIImage *image;
@property (nonatomic, assign) CGFloat cornerRadius;
@property (nonatomic, assign) BOOL showsBorder;
@property (nonatomic, assign) UIViewContentMode imageContentMode;
@property (nonatomic, assign) BOOL flipHorizontal;
@property (nonatomic, assign) BOOL flipVertical;
@property (nonatomic, assign) BOOL showsGrid;

- (instancetype)initWithFrame:(CGRect)frame image:(UIImage *)image;
- (void)clearImage;
- (void)setLockedAppearance:(BOOL)locked;

@end
