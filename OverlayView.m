/**
 * OverlayView.m
 */

#import "OverlayView.h"

@interface OverlayView ()
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) UILabel *placeholderLabel;
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
    if (image) {
        _imageView.alpha = 0;
        [UIView animateWithDuration:0.18 animations:^{ self->_imageView.alpha = 1; }];
    }
}

- (void)clearImage {
    _image = nil;
    _imageView.image = nil;
    _placeholderLabel.hidden = NO;
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

- (void)layoutSubviews {
    [super layoutSubviews];
    _imageView.frame = self.bounds;
    _placeholderLabel.frame = self.bounds;
}

@end
