/**
 * ==============================================================================
 * OverlayView.m
 * ==============================================================================
 */

#import "OverlayView.h"

@interface OverlayView ()
@property (nonatomic, strong) UIImageView *imageView;
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
    _cornerRadius = 8;
    _showsBorder = YES;
    _showsShadow = YES;
    self.backgroundColor = [UIColor clearColor];
    self.clipsToBounds = YES;
    _imageView = [[UIImageView alloc] initWithFrame:self.bounds];
    _imageView.contentMode = UIViewContentModeScaleAspectFit;
    _imageView.backgroundColor = [UIColor clearColor];
    _imageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self addSubview:_imageView];
    self.layer.cornerRadius = _cornerRadius;
    [self updateAppearance];
}

- (void)updateAppearance {
    self.layer.borderWidth = _showsBorder ? 1.0 : 0;
    self.layer.borderColor = [[UIColor colorWithWhite:1 alpha:0.3] CGColor];
    if (_showsShadow) {
        self.layer.shadowColor = [UIColor blackColor].CGColor;
        self.layer.shadowOffset = CGSizeMake(0, 2);
        self.layer.shadowRadius = 8;
        self.layer.shadowOpacity = 0.3;
        self.layer.shouldRasterize = YES;
        self.layer.rasterizationScale = [UIScreen mainScreen].scale;
    } else {
        self.layer.shadowOpacity = 0;
    }
    self.layer.cornerRadius = _cornerRadius;
}

- (void)setImage:(UIImage *)image {
    _image = image;
    _imageView.image = image;
    if (image) {
        _imageView.alpha = 0;
        [UIView animateWithDuration:0.2 animations:^{ self->_imageView.alpha = 1; }];
    }
}

- (void)clearImage { _image = nil; _imageView.image = nil; }
- (void)setCornerRadius:(CGFloat)c { _cornerRadius = c; self.layer.cornerRadius = c; }
- (void)setShowsBorder:(BOOL)b { _showsBorder = b; [self updateAppearance]; }
- (void)setShowsShadow:(BOOL)s { _showsShadow = s; [self updateAppearance]; }
- (void)layoutSubviews { [super layoutSubviews]; _imageView.frame = self.bounds; }

@end
