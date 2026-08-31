/**
 * CPMROIOverlayView.m
 * Implementation of the ROI selector overlay.
 */
#import "CPMROIOverlayView.h"
#import <QuartzCore/QuartzCore.h>

@interface CPMROIOverlayView ()
@property (nonatomic, assign, readwrite) CGRect selectedRect;
@property (nonatomic, assign, readwrite) BOOL isSelecting;
@property (nonatomic, strong) UIView *selectionRectView;
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, assign) CGPoint startPoint;
@end

@implementation CPMROIOverlayView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _isSelecting = NO;
        _selectedRect = CGRectZero;
        _showGuides = YES;
        _showCenterCrosshair = YES;
        [self setupView];
    }
    return self;
}

- (void)setupView {
    self.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.4];
    self.opaque = NO;
    self.layer.allowsEdgeAntialiasing = YES;
    
    // Selection rectangle
    self.selectionRectView = [[UIView alloc] initWithFrame:CGRectZero];
    self.selectionRectView.backgroundColor = [[UIColor systemYellowColor] colorWithAlphaComponent:0.2];
    self.selectionRectView.layer.borderColor = [UIColor systemYellowColor].CGColor;
    self.selectionRectView.layer.borderWidth = 2;
    self.selectionRectView.layer.cornerRadius = 4;
    self.selectionRectView.hidden = YES;
    [self addSubview:self.selectionRectView];
    
    // Center crosshair
    UIView *crosshair = [[UIView alloc] initWithFrame:self.bounds];
    crosshair.backgroundColor = [UIColor clearColor];
    crosshair.userInteractionEnabled = NO;
    crosshair.tag = 100;
    [self addSubview:crosshair];
    
    UIBezierPath *path = [UIBezierPath bezierPath];
    CGFloat cx = self.bounds.size.width/2;
    CGFloat cy = self.bounds.size.height/2;
    CGFloat len = 40;
    [path moveToPoint:CGPointMake(cx-len, cy)];
    [path addLineToPoint:CGPointMake(cx+len, cy)];
    [path moveToPoint:CGPointMake(cx, cy-len)];
    [path addLineToPoint:CGPointMake(cx, cy+len)];
    CAShapeLayer *shape = [CAShapeLayer layer];
    shape.path = path.CGPath;
    shape.strokeColor = [UIColor whiteColor].CGColor;
    shape.lineWidth = 1;
    shape.lineDashPattern = @[@4, @4];
    [crosshair.layer addSublayer:shape];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.selectionRectView.layer.borderColor = [UIColor systemYellowColor].CGColor;
}

- (void)beginSelection {
    self.isSelecting = YES;
    self.startPoint = CGPointZero;
}

- (void)cancelSelection {
    self.isSelecting = NO;
    self.selectedRect = CGRectZero;
    self.selectionRectView.hidden = YES;
    if ([self.delegate respondsToSelector:@selector(roiOverlayDidCancel:)]) {
        [self.delegate roiOverlayDidCancel:self];
    }
}

- (void)clearSelection {
    self.selectedRect = CGRectZero;
    self.selectionRectView.hidden = YES;
}

#pragma mark - Touch Handling

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    // Always consume touches during selection mode
    return self.isSelecting || CGRectContainsPoint(self.bounds, point);
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (!self.isSelecting) return;
    UITouch *touch = touches.anyObject;
    self.startPoint = [touch locationInView:self];
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (!self.isSelecting) return;
    UITouch *touch = touches.anyObject;
    CGPoint current = [touch locationInView:self];
    
    CGFloat x = MIN(self.startPoint.x, current.x);
    CGFloat y = MIN(self.startPoint.y, current.y);
    CGFloat w = fabs(current.x - self.startPoint.x);
    CGFloat h = fabs(current.y - self.startPoint.y);
    
    if (w > 10 && h > 10) {
        self.selectedRect = CGRectMake(x, y, w, h);
        self.selectionRectView.frame = self.selectedRect;
        self.selectionRectView.hidden = NO;
        
        // Add corner handles
        [self updateCornerHandles];
    }
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (!self.isSelecting) return;
    if (CGRectGetWidth(self.selectedRect) > 50 && CGRectGetHeight(self.selectedRect) > 50) {
        if ([self.delegate respondsToSelector:@selector(roiOverlay:didFinishWithRect:)]) {
            [self.delegate roiOverlay:self didFinishWithRect:self.selectedRect];
        }
    }
    self.isSelecting = NO;
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self cancelSelection];
}

- (void)updateCornerHandles {
    if (!self.showGuides) {
        self.selectionRectView.layer.borderWidth = 2;
        return;
    }
    
    // Draw guide lines
    for (NSInteger i = 0; i < 3; i++) {
        CGFloat x = CGRectGetMinX(self.selectedRect) + CGRectGetWidth(self.selectedRect) * (i+1) / 3.0;
        CGFloat y = CGRectGetMinY(self.selectedRect) + CGRectGetHeight(self.selectedRect) * (i+1) / 3.0;
        
        // Vertical guide
        UIBezierPath *vPath = [UIBezierPath bezierPath];
        [vPath moveToPoint:CGPointMake(x, CGRectGetMinY(self.selectedRect))];
        [vPath addLineToPoint:CGPointMake(x, CGRectGetMaxY(self.selectedRect))];
        
        // Horizontal guide
        UIBezierPath *hPath = [UIBezierPath bezierPath];
        [hPath moveToPoint:CGPointMake(CGRectGetMinX(self.selectedRect), y)];
        [hPath addLineToPoint:CGPointMake(CGRectGetMaxX(self.selectedRect), y)];
    }
}

@end
