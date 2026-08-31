/**
 * OverlayView.m
 *
 * Crop is a window into the uncropped image.
 * Warp is a Photoshop-style 3×3 mesh (corners = distort).
 * Perspective mode exposes crop-like edge handles that drive pitch/yaw.
 */

#import "OverlayView.h"
#import <QuartzCore/QuartzCore.h>
#import <CoreImage/CoreImage.h>

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
@property (nonatomic, strong) CAShapeLayer *cropDimLayer;
@property (nonatomic, strong) CAShapeLayer *cropFrameLayer;
@property (nonatomic, strong) CAShapeLayer *cropGuideLayer;
@property (nonatomic, strong) CAShapeLayer *warpGridLayer;
@property (nonatomic, strong) CAShapeLayer *perspFrameLayer;
@property (nonatomic, strong) NSArray<UIView *> *cropHandles;
@property (nonatomic, strong) NSArray<UIView *> *warpHandles;
@property (nonatomic, strong) NSArray<UIView *> *perspHandles;
@property (nonatomic, assign) unsigned char *colorBuf;
@property (nonatomic, assign) NSInteger colorBufW;
@property (nonatomic, assign) NSInteger colorBufH;
@property (nonatomic, assign) CGFloat colorBufScale;
@end

@implementation OverlayView

+ (NSArray<NSValue *> *)identityWarpPoints {
    NSMutableArray *a = [NSMutableArray arrayWithCapacity:9];
    for (NSInteger r = 0; r < 3; r++) {
        for (NSInteger c = 0; c < 3; c++) {
            [a addObject:[NSValue valueWithCGPoint:CGPointMake(c / 2.0, r / 2.0)]];
        }
    }
    return a;
}

+ (BOOL)warpPointsAreIdentity:(NSArray<NSValue *> *)points {
    if (points.count != 9) return YES;
    NSArray *idPts = [self identityWarpPoints];
    for (NSInteger i = 0; i < 9; i++) {
        CGPoint a = [points[i] CGPointValue];
        CGPoint b = [idPts[i] CGPointValue];
        if (fabs(a.x - b.x) > 0.001 || fabs(a.y - b.y) > 0.001) return NO;
    }
    return YES;
}

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
    _warpModeEnabled = NO;
    _perspectiveModeEnabled = NO;
    _warpPoints = [[self class] identityWarpPoints];

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

    _cropFrameLayer = [self makeShapeStroke:[UIColor colorWithWhite:1 alpha:0.95] width:2.0 dashed:NO];
    _cropGuideLayer = [self makeShapeStroke:[UIColor colorWithWhite:1 alpha:0.55] width:1.0 / [UIScreen mainScreen].scale dashed:YES];
    _warpGridLayer = [self makeShapeStroke:[UIColor colorWithRed:1 green:0.55 blue:0.2 alpha:0.95] width:1.5 dashed:NO];
    _perspFrameLayer = [self makeShapeStroke:[UIColor colorWithRed:1 green:0.84 blue:0.2 alpha:0.95] width:2.0 dashed:NO];

    UIColor *cropBlue = [UIColor colorWithRed:0.25 green:0.55 blue:1.0 alpha:1];
    UIColor *warpOrange = [UIColor colorWithRed:1.0 green:0.48 blue:0.16 alpha:1];
    UIColor *perspYellow = [UIColor colorWithRed:1.0 green:0.84 blue:0.18 alpha:1];

    NSMutableArray *crop = [NSMutableArray array];
    for (NSInteger tag = kOLHandleL; tag <= kOLHandleBR; tag++) {
        [crop addObject:[self makeHandle:tag color:cropBlue action:@selector(handleCropPan:)]];
    }
    _cropHandles = crop;

    NSMutableArray *warp = [NSMutableArray array];
    for (NSInteger i = 0; i < 9; i++) {
        [warp addObject:[self makeHandle:i color:warpOrange action:@selector(handleWarpPan:)]];
    }
    _warpHandles = warp;

    NSMutableArray *persp = [NSMutableArray array];
    for (NSInteger tag = kOLHandleL; tag <= kOLHandleBR; tag++) {
        [persp addObject:[self makeHandle:tag color:perspYellow action:@selector(handlePerspPan:)]];
    }
    _perspHandles = persp;

    [self updateAppearance];
}

- (CAShapeLayer *)makeShapeStroke:(UIColor *)color width:(CGFloat)w dashed:(BOOL)dashed {
    CAShapeLayer *l = [CAShapeLayer layer];
    l.fillColor = [UIColor clearColor].CGColor;
    l.strokeColor = color.CGColor;
    l.lineWidth = w;
    l.hidden = YES;
    if (dashed) l.lineDashPattern = @[ @4, @3 ];
    [self.layer addSublayer:l];
    return l;
}

- (UIView *)makeHandle:(NSInteger)tag color:(UIColor *)color action:(SEL)action {
    UIView *hit = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 28, 28)];
    hit.tag = tag;
    hit.hidden = YES;
    hit.userInteractionEnabled = YES;

    UIView *knob = [[UIView alloc] initWithFrame:CGRectMake(7, 7, 18, 18)];
    knob.backgroundColor = [UIColor whiteColor];
    knob.userInteractionEnabled = NO;
    knob.layer.cornerRadius = 9;
    knob.layer.borderWidth = 2.0;
    knob.layer.borderColor = color.CGColor;
    knob.layer.shadowColor = [UIColor blackColor].CGColor;
    knob.layer.shadowOpacity = 0.5;
    knob.layer.shadowRadius = 2.5;
    knob.layer.shadowOffset = CGSizeMake(0, 1);
    [hit addSubview:knob];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:action];
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
    _placeholderLabel.hidden = (image != nil);
    _clipView.backgroundColor = image
        ? [UIColor clearColor]
        : [[UIColor blackColor] colorWithAlphaComponent:0.28];
    [self refreshDisplayedImage];
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
    [self refreshDisplayedImage];
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
    [self refreshDisplayedImage];
}

- (void)setCropInsets:(UIEdgeInsets)insets {
    _cropInsets = [self clampedInsets:insets];
    [self applyCropLayout];
    [self refreshDisplayedImage];
    if (_cropModeEnabled) [self layoutCropChrome];
}

- (void)setWarpPoints:(NSArray<NSValue *> *)warpPoints {
    if (warpPoints.count != 9) warpPoints = [[self class] identityWarpPoints];
    _warpPoints = [warpPoints copy];
    [self refreshDisplayedImage];
    if (_warpModeEnabled) [self layoutWarpChrome];
}

- (void)resetWarp {
    self.warpPoints = [[self class] identityWarpPoints];
}

- (UIEdgeInsets)clampedCropInsets:(UIEdgeInsets)insets {
    return [self clampedInsets:insets];
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

- (CGRect)cropRectInBounds {
    CGRect b = self.bounds;
    CGFloat l = _cropInsets.left * b.size.width;
    CGFloat r = _cropInsets.right * b.size.width;
    CGFloat t = _cropInsets.top * b.size.height;
    CGFloat bot = _cropInsets.bottom * b.size.height;
    CGFloat w = MAX(40.0, b.size.width - l - r);
    CGFloat h = MAX(40.0, b.size.height - t - bot);
    return CGRectMake(l, t, w, h);
}

- (void)applyCropLayout {
    CGSize base = [self effectiveUncroppedSize];
    CGFloat l = _cropInsets.left * base.width;
    CGFloat t = _cropInsets.top * base.height;
    _clipView.frame = self.bounds;
    BOOL warped = ![[self class] warpPointsAreIdentity:_warpPoints];
    if (_cropModeEnabled) {
        /* Full uncropped image stays put; only the crop rectangle moves. */
        _clipView.clipsToBounds = YES;
        _imageView.frame = self.bounds;
        _placeholderLabel.frame = self.bounds;
    } else if (warped) {
        _clipView.clipsToBounds = NO;
        _imageView.frame = _clipView.bounds;
        _placeholderLabel.frame = _clipView.bounds;
    } else {
        _clipView.clipsToBounds = YES;
        _imageView.frame = CGRectMake(-l, -t, base.width, base.height);
        _placeholderLabel.frame = _imageView.frame;
    }
}

#pragma mark - Display / warp render

- (void)refreshDisplayedImage {
    [self applyCropLayout];
    if (!_image) {
        _imageView.image = nil;
        return;
    }
    if ([[self class] warpPointsAreIdentity:_warpPoints]) {
        _imageView.image = _image;
        return;
    }
    UIImage *warped = [self renderWarpedImage:_image];
    _imageView.image = warped ?: _image;
    _imageView.frame = _clipView.bounds;
}

- (UIImage *)renderWarpedImage:(UIImage *)srcImg {
    CIImage *input = [[CIImage alloc] initWithImage:srcImg];
    if (!input) return srcImg;
    CGRect e = input.extent;
    if (e.size.width < 2 || e.size.height < 2) return srcImg;

    CIImage *acc = nil;
    for (NSInteger r = 0; r < 2; r++) {
        for (NSInteger c = 0; c < 2; c++) {
            CGFloat u0 = c / 2.0, u1 = (c + 1) / 2.0;
            CGFloat v0 = r / 2.0, v1 = (r + 1) / 2.0;
            CGFloat pad = 1.0;
            CGFloat x = e.origin.x + u0 * e.size.width - (c == 0 ? 0 : pad);
            CGFloat w = (u1 - u0) * e.size.width + pad;
            CGFloat ciBottom = e.origin.y + (1.0 - v1) * e.size.height - (r == 1 ? 0 : pad);
            CGFloat h = (v1 - v0) * e.size.height + pad;
            CGRect src = CGRectMake(x, ciBottom, w, h);
            CIImage *cell = [input imageByCroppingToRect:src];

            CGPoint pTL = [_warpPoints[r * 3 + c] CGPointValue];
            CGPoint pTR = [_warpPoints[r * 3 + c + 1] CGPointValue];
            CGPoint pBL = [_warpPoints[(r + 1) * 3 + c] CGPointValue];
            CGPoint pBR = [_warpPoints[(r + 1) * 3 + c + 1] CGPointValue];

            CIVector *tl = [self ciDest:pTL extent:e];
            CIVector *tr = [self ciDest:pTR extent:e];
            CIVector *bl = [self ciDest:pBL extent:e];
            CIVector *br = [self ciDest:pBR extent:e];

            CIFilter *f = [CIFilter filterWithName:@"CIPerspectiveTransform"];
            if (!f) continue;
            [f setValue:cell forKey:kCIInputImageKey];
            [f setValue:tl forKey:@"inputTopLeft"];
            [f setValue:tr forKey:@"inputTopRight"];
            [f setValue:bl forKey:@"inputBottomLeft"];
            [f setValue:br forKey:@"inputBottomRight"];
            CIImage *piece = f.outputImage;
            if (!piece) continue;
            acc = acc ? [piece imageByCompositingOverImage:acc] : piece;
        }
    }
    if (!acc) return srcImg;

    static CIContext *ctx;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        ctx = [CIContext contextWithOptions:@{kCIContextUseSoftwareRenderer: @NO}];
    });
    CGImageRef cg = [ctx createCGImage:acc fromRect:e];
    if (!cg) return srcImg;
    UIImage *out = [UIImage imageWithCGImage:cg scale:srcImg.scale orientation:UIImageOrientationUp];
    CGImageRelease(cg);
    return out;
}

- (CIVector *)ciDest:(CGPoint)u extent:(CGRect)e {
    return [CIVector vectorWithX:e.origin.x + u.x * e.size.width
                               Y:e.origin.y + (1.0 - u.y) * e.size.height];
}

#pragma mark - Modes

- (void)setCropModeEnabled:(BOOL)on {
    _cropModeEnabled = on;
    if (on) {
        _warpModeEnabled = NO;
        _perspectiveModeEnabled = NO;
    }
    [self applyCropLayout];
    [self updateEditChrome];
}

- (void)setWarpModeEnabled:(BOOL)on {
    _warpModeEnabled = on;
    if (on) {
        _cropModeEnabled = NO;
        _perspectiveModeEnabled = NO;
    }
    [self updateEditChrome];
}

- (void)setPerspectiveModeEnabled:(BOOL)on {
    _perspectiveModeEnabled = on;
    if (on) {
        _cropModeEnabled = NO;
        _warpModeEnabled = NO;
    }
    [self updateEditChrome];
}

- (void)updateEditChrome {
    BOOL crop = _cropModeEnabled;
    BOOL warp = _warpModeEnabled;
    BOOL persp = _perspectiveModeEnabled;
    _cropDimLayer.hidden = !crop;
    _cropFrameLayer.hidden = !crop;
    _cropGuideLayer.hidden = !crop;
    _warpGridLayer.hidden = !warp;
    _perspFrameLayer.hidden = !persp;
    for (UIView *h in _cropHandles) h.hidden = !crop;
    for (UIView *h in _warpHandles) h.hidden = !warp;
    for (UIView *h in _perspHandles) h.hidden = !persp;
    self.layer.shouldRasterize = !(crop || warp || persp);
    if (crop || warp || persp) {
        self.layer.borderWidth = 0;
        if (crop) [self layoutCropChrome];
        if (warp) [self layoutWarpChrome];
        if (persp) [self layoutPerspChrome];
    } else {
        [self updateAppearance];
    }
}

- (BOOL)isCropHandleView:(UIView *)view {
    while (view && view != self) {
        if ([_cropHandles containsObject:view]) return YES;
        if ([_warpHandles containsObject:view]) return YES;
        if ([_perspHandles containsObject:view]) return YES;
        view = view.superview;
    }
    return NO;
}

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    if ([super pointInside:point withEvent:event]) return YES;
    NSArray *sets = @[ _cropHandles, _warpHandles, _perspHandles ];
    for (NSArray *hs in sets) {
        for (UIView *h in hs) {
            if (!h.hidden && CGRectContainsPoint(h.frame, point)) return YES;
        }
    }
    return NO;
}

#pragma mark - Handle drags

- (void)handleCropPan:(UIPanGestureRecognizer *)g {
    if (!_cropModeEnabled) return;
    CGSize sz = self.bounds.size;
    if (sz.width < 1 || sz.height < 1) return;
    if (g.state == UIGestureRecognizerStateBegan) return;

    /* View stays still. Insets are finger vs the uncropped bounds. */
    CGPoint p = [g locationInView:self];
    CGFloat u = p.x / sz.width;
    CGFloat v = p.y / sz.height;
    UIEdgeInsets insets = _cropInsets;
    NSInteger tag = g.view.tag;
    if (tag == kOLHandleL || tag == kOLHandleTL || tag == kOLHandleBL) insets.left = u;
    if (tag == kOLHandleR || tag == kOLHandleTR || tag == kOLHandleBR) insets.right = 1.0 - u;
    if (tag == kOLHandleT || tag == kOLHandleTL || tag == kOLHandleTR) insets.top = v;
    if (tag == kOLHandleB || tag == kOLHandleBL || tag == kOLHandleBR) insets.bottom = 1.0 - v;
    insets = [self clampedInsets:insets];
    if ([self.cropDelegate respondsToSelector:@selector(overlayView:didChangeCropInsets:)]) {
        [self.cropDelegate overlayView:self didChangeCropInsets:insets];
    } else {
        [self setCropInsets:insets];
    }
}

- (void)handleWarpPan:(UIPanGestureRecognizer *)g {
    if (!_warpModeEnabled) return;
    CGSize sz = self.bounds.size;
    if (sz.width < 1 || sz.height < 1) return;
    CGPoint t = [g translationInView:self];
    [g setTranslation:CGPointZero inView:self];
    NSInteger i = g.view.tag;
    if (i < 0 || i >= 9) return;
    NSMutableArray *pts = [_warpPoints mutableCopy];
    CGPoint p = [pts[i] CGPointValue];
    p.x += t.x / sz.width;
    p.y += t.y / sz.height;
    p.x = MAX(-0.25, MIN(1.25, p.x));
    p.y = MAX(-0.25, MIN(1.25, p.y));
    pts[i] = [NSValue valueWithCGPoint:p];
    _warpPoints = pts;
    [self refreshDisplayedImage];
    [self layoutWarpChrome];
    if ([self.cropDelegate respondsToSelector:@selector(overlayView:didChangeWarpPoints:)]) {
        [self.cropDelegate overlayView:self didChangeWarpPoints:_warpPoints];
    }
}

- (void)handlePerspPan:(UIPanGestureRecognizer *)g {
    if (!_perspectiveModeEnabled) return;
    CGSize sz = self.bounds.size;
    if (sz.width < 1 || sz.height < 1) return;
    CGPoint t = [g translationInView:self];
    [g setTranslation:CGPointZero inView:self];
    NSInteger tag = g.view.tag;
    CGFloat dPitch = 0, dYaw = 0;
    CGFloat ky = 1.35 / MAX(sz.height, 1);
    CGFloat kx = 1.35 / MAX(sz.width, 1);
    if (tag == kOLHandleT || tag == kOLHandleTL || tag == kOLHandleTR) dPitch += t.y * ky;
    if (tag == kOLHandleB || tag == kOLHandleBL || tag == kOLHandleBR) dPitch -= t.y * ky;
    if (tag == kOLHandleL || tag == kOLHandleTL || tag == kOLHandleBL) dYaw += t.x * kx;
    if (tag == kOLHandleR || tag == kOLHandleTR || tag == kOLHandleBR) dYaw -= t.x * kx;
    if (fabs(dPitch) < 0.0001 && fabs(dYaw) < 0.0001) return;
    if ([self.cropDelegate respondsToSelector:@selector(overlayView:didChangePitchDelta:yawDelta:)]) {
        [self.cropDelegate overlayView:self didChangePitchDelta:dPitch yawDelta:dYaw];
    }
}

#pragma mark - Chrome layout

- (void)layoutEdgeHandles:(NSArray<UIView *> *)handles {
    [self layoutEdgeHandles:handles inRect:self.bounds];
}

- (void)layoutEdgeHandles:(NSArray<UIView *> *)handles inRect:(CGRect)b {
    CGFloat s = 28.0;
    CGFloat midX = b.origin.x + b.size.width * 0.5 - s * 0.5;
    CGFloat midY = b.origin.y + b.size.height * 0.5 - s * 0.5;
    CGFloat minX = b.origin.x - s * 0.5;
    CGFloat minY = b.origin.y - s * 0.5;
    CGFloat maxX = CGRectGetMaxX(b) - s * 0.5;
    CGFloat maxY = CGRectGetMaxY(b) - s * 0.5;
    for (UIView *h in handles) {
        CGRect f = CGRectMake(0, 0, s, s);
        switch (h.tag) {
            case kOLHandleL:  f.origin = CGPointMake(minX, midY); break;
            case kOLHandleR:  f.origin = CGPointMake(maxX, midY); break;
            case kOLHandleT:  f.origin = CGPointMake(midX, minY); break;
            case kOLHandleB:  f.origin = CGPointMake(midX, maxY); break;
            case kOLHandleTL: f.origin = CGPointMake(minX, minY); break;
            case kOLHandleTR: f.origin = CGPointMake(maxX, minY); break;
            case kOLHandleBL: f.origin = CGPointMake(minX, maxY); break;
            case kOLHandleBR: f.origin = CGPointMake(maxX, maxY); break;
            default: break;
        }
        h.frame = f;
    }
}

- (void)addCornerTicks:(UIBezierPath *)frame rect:(CGRect)b tick:(CGFloat)tick {
    CGFloat x0 = b.origin.x + 1, y0 = b.origin.y + 1;
    CGFloat x1 = CGRectGetMaxX(b) - 1, y1 = CGRectGetMaxY(b) - 1;
    [frame moveToPoint:CGPointMake(x0, y0 + tick)];
    [frame addLineToPoint:CGPointMake(x0, y0)];
    [frame addLineToPoint:CGPointMake(x0 + tick, y0)];
    [frame moveToPoint:CGPointMake(x1 - tick, y0)];
    [frame addLineToPoint:CGPointMake(x1, y0)];
    [frame addLineToPoint:CGPointMake(x1, y0 + tick)];
    [frame moveToPoint:CGPointMake(x0, y1 - tick)];
    [frame addLineToPoint:CGPointMake(x0, y1)];
    [frame addLineToPoint:CGPointMake(x0 + tick, y1)];
    [frame moveToPoint:CGPointMake(x1 - tick, y1)];
    [frame addLineToPoint:CGPointMake(x1, y1)];
    [frame addLineToPoint:CGPointMake(x1, y1 - tick)];
}

- (void)layoutCropChrome {
    CGRect b = self.bounds;
    _cropFrameLayer.frame = b;
    UIBezierPath *frame = [UIBezierPath bezierPathWithRect:CGRectInset(b, 1, 1)];
    [self addCornerTicks:frame rect:b tick:18.0];
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
    [self layoutEdgeHandles:_cropHandles];
}

- (void)layoutWarpChrome {
    CGRect b = self.bounds;
    CGFloat s = 28.0;
    UIBezierPath *grid = [UIBezierPath bezierPath];
    CGPoint pos[9];
    for (NSInteger i = 0; i < 9; i++) {
        CGPoint u = [_warpPoints[i] CGPointValue];
        pos[i] = CGPointMake(u.x * b.size.width, u.y * b.size.height);
        _warpHandles[i].frame = CGRectMake(pos[i].x - s * 0.5, pos[i].y - s * 0.5, s, s);
    }
    for (NSInteger r = 0; r < 3; r++) {
        [grid moveToPoint:pos[r * 3]];
        [grid addLineToPoint:pos[r * 3 + 1]];
        [grid addLineToPoint:pos[r * 3 + 2]];
    }
    for (NSInteger c = 0; c < 3; c++) {
        [grid moveToPoint:pos[c]];
        [grid addLineToPoint:pos[3 + c]];
        [grid addLineToPoint:pos[6 + c]];
    }
    _warpGridLayer.frame = b;
    _warpGridLayer.path = grid.CGPath;
}

- (void)layoutPerspChrome {
    CGRect b = self.bounds;
    _perspFrameLayer.frame = b;
    UIBezierPath *frame = [UIBezierPath bezierPathWithRect:CGRectInset(b, 1, 1)];
    [self addCornerTicks:frame rect:b tick:18.0];
    CGFloat midX = b.size.width * 0.5;
    CGFloat midY = b.size.height * 0.5;
    [frame moveToPoint:CGPointMake(midX - 12, 4)];
    [frame addLineToPoint:CGPointMake(midX, 0)];
    [frame addLineToPoint:CGPointMake(midX + 12, 4)];
    [frame moveToPoint:CGPointMake(midX - 12, b.size.height - 4)];
    [frame addLineToPoint:CGPointMake(midX, b.size.height)];
    [frame addLineToPoint:CGPointMake(midX + 12, b.size.height - 4)];
    [frame moveToPoint:CGPointMake(4, midY - 12)];
    [frame addLineToPoint:CGPointMake(0, midY)];
    [frame addLineToPoint:CGPointMake(4, midY + 12)];
    [frame moveToPoint:CGPointMake(b.size.width - 4, midY - 12)];
    [frame addLineToPoint:CGPointMake(b.size.width, midY)];
    [frame addLineToPoint:CGPointMake(b.size.width - 4, midY + 12)];
    _perspFrameLayer.path = frame.CGPath;
    [self layoutEdgeHandles:_perspHandles];
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
    if (_warpModeEnabled) [self layoutWarpChrome];
    if (_perspectiveModeEnabled) [self layoutPerspChrome];
}


- (void)dealloc {
    [self endColorSampling];
}

- (void)endColorSampling {
    if (_colorBuf) {
        free(_colorBuf);
        _colorBuf = NULL;
    }
    _colorBufW = 0;
    _colorBufH = 0;
    _colorBufScale = 1;
}

- (void)beginColorSampling {
    [self endColorSampling];
    self.layer.shouldRasterize = NO;
    [self layoutIfNeeded];
    CGSize sz = self.bounds.size;
    if (sz.width < 2 || sz.height < 2) return;
    CGFloat scale = [UIScreen mainScreen].scale;
    UIGraphicsImageRendererFormat *fmt = [UIGraphicsImageRendererFormat defaultFormat];
    fmt.scale = scale;
    fmt.opaque = NO;
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:sz format:fmt];
    /* Overlay window is never key — drawViewHierarchy is unreliable. */
    UIImage *snap = [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [self.layer renderInContext:ctx.CGContext];
    }];
    CGImageRef cg = snap.CGImage;
    if (!cg) return;
    NSInteger w = (NSInteger)CGImageGetWidth(cg);
    NSInteger h = (NSInteger)CGImageGetHeight(cg);
    if (w < 1 || h < 1) return;
    size_t bytes = (size_t)w * (size_t)h * 4;
    unsigned char *buf = (unsigned char *)calloc(1, bytes);
    if (!buf) return;
    CGColorSpaceRef cs = NULL;
    if (@available(iOS 9.0, *)) {
        cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    }
    if (!cs) cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef bctx = CGBitmapContextCreate(buf, (size_t)w, (size_t)h, 8, (size_t)w * 4, cs,
        kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(cs);
    if (!bctx) {
        free(buf);
        return;
    }
    /* Snapshot is UIKit y-down; CGContextDrawImage is y-up — flip so y matches. */
    CGContextTranslateCTM(bctx, 0, (CGFloat)h);
    CGContextScaleCTM(bctx, 1, -1);
    CGContextSetBlendMode(bctx, kCGBlendModeCopy);
    CGContextDrawImage(bctx, CGRectMake(0, 0, (CGFloat)w, (CGFloat)h), cg);
    CGContextRelease(bctx);
    _colorBuf = buf;
    _colorBufW = w;
    _colorBufH = h;
    _colorBufScale = scale;
}

- (BOOL)colorBufferPixelAtX:(NSInteger)x y:(NSInteger)y r:(int *)r g:(int *)g b:(int *)b {
    if (!_colorBuf || x < 0 || y < 0 || x >= _colorBufW || y >= _colorBufH) return NO;
    unsigned char *px = _colorBuf + ((size_t)y * (size_t)_colorBufW + (size_t)x) * 4;
    int A = px[3];
    if (A < 1) {
        *r = 0; *g = 0; *b = 0;
        return YES;
    }
    if (A >= 255) {
        *r = px[0]; *g = px[1]; *b = px[2];
        return YES;
    }
    *r = MIN(255, (px[0] * 255) / A);
    *g = MIN(255, (px[1] * 255) / A);
    *b = MIN(255, (px[2] * 255) / A);
    return YES;
}

- (UIColor *)colorAtPoint:(CGPoint)point {
    if (!_colorBuf) [self beginColorSampling];
    if (!_colorBuf) return nil;
    NSInteger x = (NSInteger)floor(point.x * _colorBufScale);
    NSInteger y = (NSInteger)floor(point.y * _colorBufScale);
    x = MAX(0, MIN(_colorBufW - 1, x));
    y = MAX(0, MIN(_colorBufH - 1, y));
    int R = 0, G = 0, B = 0;
    if (![self colorBufferPixelAtX:x y:y r:&R g:&G b:&B]) return nil;
    return [UIColor colorWithRed:R / 255.0 green:G / 255.0 blue:B / 255.0 alpha:1];
}

- (UIImage *)loupeImageAtPoint:(CGPoint)point {
    if (!_colorBuf) [self beginColorSampling];
    if (!_colorBuf) return nil;
    const NSInteger radius = 6; /* 13×13 source pixels */
    NSInteger cx = (NSInteger)floor(point.x * _colorBufScale);
    NSInteger cy = (NSInteger)floor(point.y * _colorBufScale);
    NSInteger dim = radius * 2 + 1;
    const NSInteger cell = 10;
    CGSize out = CGSizeMake(dim * cell, dim * cell);
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:out];
    return [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        CGContextRef c = ctx.CGContext;
        for (NSInteger dy = -radius; dy <= radius; dy++) {
            for (NSInteger dx = -radius; dx <= radius; dx++) {
                int R = 0, G = 0, B = 0;
                NSInteger px = cx + dx, py = cy + dy;
                if (![self colorBufferPixelAtX:px y:py r:&R g:&G b:&B]) {
                    R = G = B = 20;
                }
                CGContextSetRGBFillColor(c, R / 255.0, G / 255.0, B / 255.0, 1);
                CGContextFillRect(c, CGRectMake((dx + radius) * cell, (dy + radius) * cell, cell, cell));
            }
        }
        CGFloat mid = radius * cell;
        CGContextSetRGBStrokeColor(c, 1, 1, 1, 0.95);
        CGContextSetLineWidth(c, 1.5);
        CGContextStrokeRect(c, CGRectMake(mid, mid, cell, cell));
    }];
}

@end
