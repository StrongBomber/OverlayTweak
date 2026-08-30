/**
 * OverlayView.m
 */

#import "OverlayView.h"
#import <QuartzCore/QuartzCore.h>

@interface OverlayView ()
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) UILabel *placeholderLabel;
@property (nonatomic, strong) CAShapeLayer *gridLayer;
@end

@implementation OverlayView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) { [self commonInit]; }
    return self;
}

- (instancetype)initWithFrame:(CGRect)frame image:(UIImage *)image {
    self = [super initWithFrame:frame];
    if (self) { [self commonInit]; [self setImage:image]; }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) { [self commonInit]; }
    return self;
}

- (void)commonInit {
    _cornerRadius = 8.0;
    _showsBorder = YES;
    _imageContentMode = UIViewContentModeScaleAspectFit;
    _flipHorizontal = NO;
    _flipVertical = NO;
    _showsGrid = NO;
    _cropInsets = UIEdgeInsetsZero;

    self.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.28];
    self.clipsToBounds = YES;
    self.opaque = NO;
    self.layer.allowsEdgeAntialiasing = YES;
    self.layer.shouldRasterize = YES;
    self.layer.rasterizationScale = [UIScreen mainScreen].scale;
    self.layer.drawsAsynchronously = YES;

    _imageView = [[UIImageView alloc] initWithFrame:self.bounds];
    _imageView.contentMode = _imageContentMode;
    _imageView.backgroundColor = [UIColor clearColor];
    _imageView.opaque = NO;
    _imageView.clipsToBounds = YES;
    _imageView.layer.masksToBounds = YES;
    _imageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self addSubview:_imageView];

    _placeholderLabel = [[UILabel alloc] initWithFrame:self.bounds];
    _placeholderLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _placeholderLabel.text = @"Görsel seçin\n⚙️ menü";
    _placeholderLabel.textAlignment = NSTextAlignmentCenter;
    _placeholderLabel.numberOfLines = 2;
    _placeholderLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    _placeholderLabel.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.7];
    _placeholderLabel.userInteractionEnabled = NO;
    [self addSubview:_placeholderLabel];

    _gridLayer = [CAShapeLayer layer];
    _gridLayer.strokeColor = [UIColor colorWithWhite:1.0 alpha:0.35].CGColor;
    _gridLayer.fillColor = [UIColor clearColor].CGColor;
    _gridLayer.lineWidth = 1.0 / [UIScreen mainScreen].scale;
    _gridLayer.hidden = YES;
    [self.layer addSublayer:_gridLayer];

    [self updateAppearance];
}

- (void)updateAppearance {
    self.layer.cornerRadius = _cornerRadius;
    self.layer.borderWidth = _showsBorder ? 2.0 : 0.0;
    self.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.45].CGColor;
}

- (void)setLockedAppearance:(BOOL)locked {
    if (locked) {
        self.layer.borderColor = [UIColor systemRedColor].CGColor;
        self.layer.borderWidth = 3.0;
    } else {
        [self updateAppearance];
    }
}

- (void)applyFlip {
    CGFloat sx = _flipHorizontal ? -1.0 : 1.0;
    CGFloat sy = _flipVertical ? -1.0 : 1.0;
    _imageView.transform = CGAffineTransformMakeScale(sx, sy);
}

- (void)setImage:(UIImage *)image {
    _image = image;
    _imageView.image = image;
    _placeholderLabel.hidden = (image != nil);
    self.backgroundColor = image
        ? [UIColor clearColor]
        : [[UIColor blackColor] colorWithAlphaComponent:0.28];
    [self applyCrop];
    if (image) {
        _imageView.alpha = 0;
        [UIView animateWithDuration:0.18 animations:^{ self->_imageView.alpha = 1; }];
    }
}

- (void)clearImage {
    _image = nil;
    _imageView.image = nil;
    _placeholderLabel.hidden = NO;
    self.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.28];
    _imageView.layer.contentsRect = CGRectMake(0, 0, 1, 1);
}

- (void)setCornerRadius:(CGFloat)c {
    _cornerRadius = c;
    self.layer.cornerRadius = c;
}

- (void)setShowsBorder:(BOOL)b {
    _showsBorder = b;
    [self updateAppearance];
}

- (void)setImageContentMode:(UIViewContentMode)mode {
    _imageContentMode = mode;
    _imageView.contentMode = mode;
}

- (void)setFlipHorizontal:(BOOL)flip {
    _flipHorizontal = flip;
    [self applyFlip];
}

- (void)setFlipVertical:(BOOL)flip {
    _flipVertical = flip;
    [self applyFlip];
}

- (void)setShowsGrid:(BOOL)show {
    _showsGrid = show;
    _gridLayer.hidden = !show;
    if (show) [self updateGrid];
}

- (void)setCropInsets:(UIEdgeInsets)insets {
    insets.left   = MAX(0, MIN(0.45, insets.left));
    insets.right  = MAX(0, MIN(0.45, insets.right));
    insets.top    = MAX(0, MIN(0.45, insets.top));
    insets.bottom = MAX(0, MIN(0.45, insets.bottom));
    _cropInsets = insets;
    [self applyCrop];
}

- (void)applyCrop {
    CGFloat l = _cropInsets.left;
    CGFloat t = _cropInsets.top;
    CGFloat w = MAX(0.10, 1.0 - l - _cropInsets.right);
    CGFloat h = MAX(0.10, 1.0 - t - _cropInsets.bottom);
    _imageView.layer.contentsRect = CGRectMake(l, t, w, h);
}

- (void)updateGrid {
    if (!_showsGrid) return;
    CGRect b = self.bounds;
    UIBezierPath *path = [UIBezierPath bezierPath];
    for (NSInteger i = 1; i <= 2; i++) {
        CGFloat x = b.size.width * i / 3.0;
        [path moveToPoint:CGPointMake(x, 0)];
        [path addLineToPoint:CGPointMake(x, b.size.height)];
        CGFloat y = b.size.height * i / 3.0;
        [path moveToPoint:CGPointMake(0, y)];
        [path addLineToPoint:CGPointMake(b.size.width, y)];
    }
    /* Center crosshair */
    [path moveToPoint:CGPointMake(b.size.width * 0.5, 0)];
    [path addLineToPoint:CGPointMake(b.size.width * 0.5, b.size.height)];
    [path moveToPoint:CGPointMake(0, b.size.height * 0.5)];
    [path addLineToPoint:CGPointMake(b.size.width, b.size.height * 0.5)];
    _gridLayer.path = path.CGPath;
    _gridLayer.frame = b;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    _imageView.frame = self.bounds;
    _placeholderLabel.frame = self.bounds;
    [self applyCrop];
    [self updateGrid];
}

@end
