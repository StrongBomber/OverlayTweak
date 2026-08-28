/**
 * ==============================================================================
 * OverlayView.h
 * ==============================================================================
 */

#import <UIKit/UIKit.h>

@interface OverlayView : UIView

@property (nonatomic, strong) UIImage *image;
@property (nonatomic, assign) CGFloat cornerRadius;
@property (nonatomic, assign) BOOL showsBorder;
@property (nonatomic, assign) BOOL showsShadow;

- (instancetype)initWithFrame:(CGRect)frame image:(UIImage *)image;
- (void)setImage:(UIImage *)image;
- (void)clearImage;

@end
