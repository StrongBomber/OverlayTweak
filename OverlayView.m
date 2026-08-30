/**
 * OverlayView.m
 *
 * Crop is a window into the uncropped image: the view shrinks from the
 * dragged edge and the image is offset so remaining pixels stay put.
 */

#import "OverlayView.h"
#import <QuartzCore/QuartzCore.h>

enum {
    kOLHandleL = 1,
    kOLHandleR,
    kOLHandleT,
    kOLHandleB,
    kOLHandleTL,
    kOLHandleTR,
    kOLHandleBL,
    kOLHandleBR
};

@interface OverlayView ()
@property (nonatomic, strong) UIView *clipView;
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) UILabel *placeholderLabel;
@property (nonatomic, strong) CAShapeLayer *gridLayer;
@property (nonatomic, strong) CAShapeLayer *cropFrameLayer;
@property (nonatomic, strong) CAShapeLayer *cropGuideLayer;
@property (nonatomic, strong) NSArray<UIView *> *cropHandles;
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
    _uncroppedSize = CGSizeZero;
    _cropModeEnabled = NO;

    self.backgroundColor = [UIColor clearColor];
    self.clipsToBounds = NO;
    self.opaque = NO;
    self.layer.allowsEdgeAntialiasing = YES;
    self.layer.shouldRasterize = YES;
    self.layer.rasterizationScale = [UIScreen mainScreen].scale;
    self.layer.drawsAsynchronously = YES;

    _clipView = [[UIView alloc] initWithFrame:self.bounds];
    _clipView.clipsToBounds = YES;
    _clipView.opaque = NO;
    _clipView.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.28];
    _clipView.userInteractionEnabled = NO;
    [self addSubview:_clipView];

    _imageView = [[UIImageView alloc] initWithFrame:_clipView.bounds];
    _imageView.contentMode = _imageContentMode;
    _imageView.backgroundColor = [UIColor clearColor];
    _imageView.opaque = NO;
    _imageView.clipsToBounds = YES;
    [_clipView addSubview:_imageView];

    _placeholderLabel = [[UILabel alloc] initWithFrame:_clipView.bounds];
    _placeholderLabel.text = @"Görsel seçin\nmenüden ⚙️";
    _placeholderLabel.textAlignment = NSTextAlignmentCenter;
    _placeholderLabel.numberOfLines = 2;
    _placeholderLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    _placeholderLabel.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.72];
    _placeholderLabel.userInteractionEnabled = NO;
    [_clipView addSubview:_placeholderLabel];

    _gridLayer = [CAShapeLayer layer];
    _gridLayer.strokeColor = [UIColor colorWithWhite:1.0 alpha:0.35].CGColor;
    _gridLayer.fillColor = [UIColor clearColor].CGColor;
    _gridLayer.lineWidth = 1.0 / [UIScreen mainScreen].scale;
    _gridLayer.hidden = YES;
    [_clipView.layer addSublayer:_gridLayer];

    _cropFrameLayer = [CAShapeLayer layer];
    _cropFrameLayer.fillColor = [UIColor clearColor].CGColor;
    _cropFrameLayer.strokeColor = [UIColor colorWithWhite:1.0 alpha:0.95].CGColor;
    _cropFrameLayer.lineWidth = 2.0;
    _cropFrameLayer.hidden = YES;
    [self.layer addSublayer:_cropFrameLayer];

    _cropGuideLayer = [CAShapeLayer layer];
    _cropGuideLayer.fillColor = [UIColor clearColor].CGColor;
    _cropGuideLayer.strokeColor = [UIColor colorWithWhite:1.0 alpha:0.55].CGColor;
    _cropGuideLayer.lineWidth = 1.0 / [UIScreen mainScreen].scale;
    _cropGuideLayer.lineDashPattern = @[ @4, @3 ];
    _cropGuideLayer.hidden = YES;
    [self.layer addSublayer:_cropGuideLayer];

    NSMutableArray *handles = [NSMutableArray array];
    for (NSInteger tag = kOLHandleL; tag <= kOLHandleBR; tag++) {
        [handles addObject:[self makeHandle:tag]];
    }
    _cropHandles = handles;

    [self updateAppearance];
}

- (UIView *)makeHandle:(NSInteger)tag {
    UIView *hit = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 28, 28)];
    hit.tag = tag;
    hit.hidden = YES;
    hit.userInteractionEnabled = YES;

    UIView *knob = [[UIView alloc] initWithFrame:CGRectMake(7, 7, 18, 18)];
    knob.backgroundColor = [UIColor whiteColor];
    knob.userInteractionEnabled = NO;
    knob.layer.cornerRadius = 9;
    knob.layer.borderWidth = 2.0;
    knob.layer.borderColor = [UIColor colorWithRed:0.25 green:0.55 blue:1.0 alpha:1].CGColor;
    knob.layer.shadowColor = [UIColor blackColor].CGColor;
    knob.layer.shadowOpacity = 0.5;
    knob.layer.shadowRadius = 2.5;
    knob.layer.shadowOffset = CGSizeMake(0, 1);
    [hit addSubview:knob];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleCropPan:)];
    pan.maximumNumberOfTouches = 1;
    [hit addGestureRecognizer:pan];
    [self addSubview:hit];
    return hit;
}

- (void)updateAppearance {
    self.layer.cornerRadius = _cornerRadius;
    self.layer.borderWidth = _showsBorder ? 2.0 : 0.0;
    self.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.45].CGColor;
    _clipView.layer.cornerRadius = _cornerRadius;
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
    _clipView.backgroundColor = image
        ? [UIColor clearColor]
        : [[UIColor blackColor] colorWithAlphaComponent:0.28];
    [self applyCropLayout];
    if (image) {
        _imageView.alpha = 0;
        [UIView animateWithDuration:0.18 animations:^{ self->_imageView.alpha = 1; }];
    }
}

- (void)clearImage {
    _image = nil;
    _imageView.image = nil;
    _placeholderLabel.hidden = NO;
    _clipView.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.28];
}

- (void)setCornerRadius:(CGFloat)c {
    _cornerRadius = c;
    self.layer.cornerRadius = c;
    _clipView.layer.cornerRadius = c;
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

- (void)setUncroppedSize:(CGSize)size {
    _uncroppedSize = size;
    [self applyCropLayout];
}

- (void)setCropInsets:(UIEdgeInsets)insets {
    _cropInsets = [self clampedInsets:insets];
    [self applyCropLayout];
}

- (UIEdgeInsets)clampedInsets:(UIEdgeInsets)insets {
    insets.left   = MAX(0, insets.left);
    insets.right  = MAX(0, insets.right);
    insets.top    = MAX(0, insets.top);
    insets.bottom = MAX(0, insets.bottom);
    CGFloat maxEdge = 0.80;
    insets.left   = MIN(maxEdge, insets.left);
    insets.right  = MIN(maxEdge, insets.right);
    insets.top    = MIN(maxEdge, insets.top);
    insets.bottom = MIN(maxEdge, insets.bottom);
    if (insets.left + insets.right > 0.85) {
        CGFloat s = 0.85 / (insets.left + insets.right);
        insets.left *= s;
        insets.right *= s;
    }
    if (insets.top + insets.bottom > 0.85) {
        CGFloat s = 0.85 / (insets.top + insets.bottom);
        insets.top *= s;
        insets.bottom *= s;
    }
    return insets;
}

- (CGSize)effectiveUncroppedSize {
    if (_uncroppedSize.width >= 40 && _uncroppedSize.height >= 40) return _uncroppedSize;
    if (self.bounds.size.width >= 1 && self.bounds.size.height >= 1) return self.bounds.size;
    return CGSizeMake(220, 220);
}

- (CGSize)croppedSize {
    CGSize base = [self effectiveUncroppedSize];
    UIEdgeInsets in = _cropInsets;
    CGFloat w = MAX(40.0, base.width * (1.0 - in.left - in.right));
    CGFloat h = MAX(40.0, base.height * (1.0 - in.top - in.bottom));
    return CGSizeMake(w, h);
}

- (void)applyCropLayout {
    CGSize base = [self effectiveUncroppedSize];
    CGFloat l = _cropInsets.left * base.width;
    CGFloat t = _cropInsets.top * base.height;
    _clipView.frame = self.bounds;
    _imageView.frame = CGRectMake(-l, -t, base.width, base.height);
    _placeholderLabel.frame = _imageView.frame;
}

- (void)setCropModeEnabled:(BOOL)on {
    _cropModeEnabled = on;
    _cropFrameLayer.hidden = !on;
    _cropGuideLayer.hidden = !on;
    for (UIView *h in _cropHandles) h.hidden = !on;
    self.layer.shouldRasterize = !on;
    if (on) {
        self.layer.borderWidth = 0;
        [self layoutCropChrome];
    } else {
        [self updateAppearance];
    }
}

- (BOOL)isCropHandleView:(UIView *)view {
    while (view && view != self) {
        if ([_cropHandles containsObject:view]) return YES;
        view = view.superview;
    }
    return NO;
}

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    if ([super pointInside:point withEvent:event]) return YES;
    if (!_cropModeEnabled) return NO;
    for (UIView *h in _cropHandles) {
        if (!h.hidden && CGRectContainsPoint(h.frame, point)) return YES;
    }
    return NO;
}

- (void)handleCropPan:(UIPanGestureRecognizer *)g {
    if (!_cropModeEnabled) return;
    CGSize base = [self effectiveUncroppedSize];
    if (base.width < 1 || base.height < 1) return;
    CGPoint t = [g translationInView:self];
    [g setTranslation:CGPointZero inView:self];
    UIEdgeInsets insets = _cropInsets;
    NSInteger tag = g.view.tag;
    CGFloat dx = t.x / base.width;
    CGFloat dy = t.y / base.height;
    if (tag == kOLHandleL || tag == kOLHandleTL || tag == kOLHandleBL) insets.left += dx;
    if (tag == kOLHandleR || tag == kOLHandleTR || tag == kOLHandleBR) insets.right -= dx;
    if (tag == kOLHandleT || tag == kOLHandleTL || tag == kOLHandleTR) insets.top += dy;
    if (tag == kOLHandleB || tag == kOLHandleBL || tag == kOLHandleBR) insets.bottom -= dy;
    insets = [self clampedInsets:insets];
    if ([self.cropDelegate respondsToSelector:@selector(overlayView:didChangeCropInsets:)]) {
        [self.cropDelegate overlayView:self didChangeCropInsets:insets];
    } else {
        [self setCropInsets:insets];
    }
}

- (void)layoutCropChrome {
    CGRect b = self.bounds;
    _cropFrameLayer.frame = b;
    UIBezierPath *frame = [UIBezierPath bezierPathWithRect:CGRectInset(b, 1, 1)];
    CGFloat tick = 18.0;
    [frame moveToPoint:CGPointMake(1, tick)];
    [frame addLineToPoint:CGPointMake(1, 1)];
    [frame addLineToPoint:CGPointMake(tick, 1)];
    [frame moveToPoint:CGPointMake(b.size.width - tick, 1)];
    [frame addLineToPoint:CGPointMake(b.size.width - 1, 1)];
    [frame addLineToPoint:CGPointMake(b.size.width - 1, tick)];
    [frame moveToPoint:CGPointMake(1, b.size.height - tick)];
    [frame addLineToPoint:CGPointMake(1, b.size.height - 1)];
    [frame addLineToPoint:CGPointMake(tick, b.size.height - 1)];
    [frame moveToPoint:CGPointMake(b.size.width - tick, b.size.height - 1)];
    [frame addLineToPoint:CGPointMake(b.size.width - 1, b.size.height - 1)];
    [frame addLineToPoint:CGPointMake(b.size.width - 1, b.size.height - tick)];
    _cropFrameLayer.path = frame.CGPath;

    UIBezierPath *guides = [UIBezierPath bezierPath];
    for (NSInteger i = 1; i <= 2; i++) {
        CGFloat x = b.size.width * i / 3.0;
        [guides moveToPoint:CGPointMake(x, 0)];
        [guides addLineToPoint:CGPointMake(x, b.size.height)];
        CGFloat y = b.size.height * i / 3.0;
        [guides moveToPoint:CGPointMake(0, y)];
        [guides addLineToPoint:CGPointMake(b.size.width, y)];
    }
    _cropGuideLayer.frame = b;
    _cropGuideLayer.path = guides.CGPath;

    CGFloat s = 28.0;
    CGFloat midX = b.size.width * 0.5 - s * 0.5;
    CGFloat midY = b.size.height * 0.5 - s * 0.5;
    CGFloat maxX = b.size.width - s * 0.5;
    CGFloat maxY = b.size.height - s * 0.5;
    for (UIView *h in _cropHandles) {
        CGRect f = CGRectMake(0, 0, s, s);
        switch (h.tag) {
            case kOLHandleL:  f.origin = CGPointMake(-s * 0.5, midY); break;
            case kOLHandleR:  f.origin = CGPointMake(maxX, midY); break;
            case kOLHandleT:  f.origin = CGPointMake(midX, -s * 0.5); break;
            case kOLHandleB:  f.origin = CGPointMake(midX, maxY); break;
            case kOLHandleTL: f.origin = CGPointMake(-s * 0.5, -s * 0.5); break;
            case kOLHandleTR: f.origin = CGPointMake(maxX, -s * 0.5); break;
            case kOLHandleBL: f.origin = CGPointMake(-s * 0.5, maxY); break;
            case kOLHandleBR: f.origin = CGPointMake(maxX, maxY); break;
            default: break;
        }
        h.frame = f;
    }
}

- (void)updateGrid {
    if (!_showsGrid) return;
    CGRect b = _clipView.bounds;
    UIBezierPath *path = [UIBezierPath bezierPath];
    for (NSInteger i = 1; i <= 2; i++) {
        CGFloat x = b.size.width * i / 3.0;
        [path moveToPoint:CGPointMake(x, 0)];
        [path addLineToPoint:CGPointMake(x, b.size.height)];
        CGFloat y = b.size.height * i / 3.0;
        [path moveToPoint:CGPointMake(0, y)];
        [path addLineToPoint:CGPointMake(b.size.width, y)];
    }
    [path moveToPoint:CGPointMake(b.size.width * 0.5, 0)];
    [path addLineToPoint:CGPointMake(b.size.width * 0.5, b.size.height)];
    [path moveToPoint:CGPointMake(0, b.size.height * 0.5)];
    [path addLineToPoint:CGPointMake(b.size.width, b.size.height * 0.5)];
    _gridLayer.path = path.CGPath;
    _gridLayer.frame = b;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self applyCropLayout];
    [self updateGrid];
    if (_cropModeEnabled) [self layoutCropChrome];
}

@end
