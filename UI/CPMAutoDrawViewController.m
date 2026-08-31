/**
 * CPMAutoDrawViewController.m
 * Implementation of the automation control panel.
 */
#import "CPMAutoDrawViewController.h"
#import "CPMExecutionController.h"
#import "CPMVinylShape.h"
#import "OverlayCommon.h"
#import "OverlayManager.h"

@interface CPMAutoDrawViewController () <UIGestureRecognizerDelegate>
@property (nonatomic, strong) UIView *controlsContainer;
@property (nonatomic, strong) UIButton *loadImageBtn;
@property (nonatomic, strong) UIButton *selectRegionBtn;
@property (nonatomic, strong) UIButton *startBtn;
@property (nonatomic, strong) UIButton *pauseBtn;
@property (nonatomic, strong) UIButton *stopBtn;
@property (nonatomic, strong) UISlider *layerLimitSlider;
@property (nonatomic, strong) UILabel *layerLimitLabel;
@property (nonatomic, strong) UISlider *touchDelaySlider;
@property (nonatomic, strong) UILabel *touchDelayLabel;
@property (nonatomic, strong) UIProgressView *progressView;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UILabel *layerCountLabel;
@property (nonatomic, strong) UIView *roiOverlay;
@property (nonatomic, strong) UITapGestureRecognizer *tapGesture;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, assign) BOOL isVisible;
@end

@implementation CPMAutoDrawViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setupControls];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (self.isVisible) [self showControlsAnimated:NO];
}

- (void)setupControls {
    self.view.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.7];
    self.view.opaque = NO;
    
    self.scrollView = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    self.scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.scrollView];
    
    self.controlsContainer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 500)];
    self.controlsContainer.center = CGPointMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds));
    self.controlsContainer.backgroundColor = [[UIColor colorWithWhite:0.1 alpha:0.95]];
    self.controlsContainer.layer.cornerRadius = 16;
    self.controlsContainer.layer.shadowColor = [UIColor blackColor].CGColor;
    self.controlsContainer.layer.shadowOpacity = 0.5;
    self.controlsContainer.layer.shadowRadius = 20;
    self.controlsContainer.layer.shadowOffset = CGSizeMake(0, 10);
    [self.scrollView addSubview:self.controlsContainer];
    
    CGFloat y = 16;
    CGFloat padding = 12;
    CGFloat btnWidth = 280;
    CGFloat btnHeight = 44;
    CGFloat sliderWidth = 240;
    
    self.loadImageBtn = [self makeButtonWithTitle:@"Load Reference Image"
                                          action:@selector(loadImageTapped)
                                          y:&y width:btnWidth height:btnHeight];
    self.loadImageBtn.backgroundColor = [UIColor systemBlueColor];
    
    self.selectRegionBtn = [self makeButtonWithTitle:@"Select ROI Region"
                                              action:@selector(selectRegionTapped)
                                              y:&y width:btnWidth height:btnHeight];
    self.selectRegionBtn.backgroundColor = [UIColor systemOrangeColor];
    
    y += 8;
    
    UILabel *layerLimitTitle = [self makeLabelWithText:@"Layer Limit:"
                                                  font:[UIFont systemFontOfSize:13 weight:UIFontWeightMedium]
                                                  color:[UIColor whiteColor]
                                                  y:&y alignment:NSTextAlignmentLeft];
    self.layerLimitSlider = [[UISlider alloc] initWithFrame:CGRectMake(padding, y, sliderWidth, 20)];
    self.layerLimitSlider.minimumValue = 50;
    self.layerLimitSlider.maximumValue = 300;
    self.layerLimitSlider.value = 200;
    self.layerLimitSlider.tintColor = [UIColor systemBlueColor];
    [self.layerLimitSlider addTarget:self action:@selector(layerLimitChanged:) forControlEvents:UIControlEventValueChanged];
    [self.controlsContainer addSubview:self.layerLimitSlider];
    y += 28;
    
    self.layerLimitLabel = [self makeLabelWithText:@"200 layers"
                                              font:[UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightRegular]
                                              color:[[UIColor whiteColor] colorWithAlphaComponent:0.7]
                                              y:&y alignment:NSTextAlignmentLeft];
    y += 12;
    
    UILabel *touchDelayTitle = [self makeLabelWithText:@"Touch Delay (ms):"
                                                  font:[UIFont systemFontOfSize:13 weight:UIFontWeightMedium]
                                                  color:[UIColor whiteColor]
                                                  y:&y alignment:NSTextAlignmentLeft];
    self.touchDelaySlider = [[UISlider alloc] initWithFrame:CGRectMake(padding, y, sliderWidth, 20)];
    self.touchDelaySlider.minimumValue = 5;
    self.touchDelaySlider.maximumValue = 100;
    self.touchDelaySlider.value = 15;
    self.touchDelaySlider.tintColor = [UIColor systemGreenColor];
    [self.touchDelaySlider addTarget:self action:@selector(touchDelayChanged:) forControlEvents:UIControlEventValueChanged];
    [self.controlsContainer addSubview:self.touchDelaySlider];
    y += 28;
    
    self.touchDelayLabel = [self makeLabelWithText:@"15 ms"
                                            font:[UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightRegular]
                                            color:[[UIColor whiteColor] colorWithAlphaComponent:0.7]
                                            y:&y alignment:NSTextAlignmentLeft];
    y += 12;
    
    self.progressView = [[UIProgressView alloc] initWithFrame:CGRectMake(padding, y, sliderWidth, 8)];
    self.progressView.progressTintColor = [UIColor systemBlueColor];
    self.progressView.trackTintColor = [[UIColor whiteColor] colorWithAlphaComponent:0.2];
    self.progressView.layer.cornerRadius = 4;
    self.progressView.clipsToBounds = YES;
    [self.controlsContainer addSubview:self.progressView];
    y += 20;
    
    self.statusLabel = [self makeLabelWithText:@"Ready"
                                        font:[UIFont systemFontOfSize:14 weight:UIFontWeightSemibold]
                                        color:[UIColor whiteColor]
                                        y:&y alignment:NSTextAlignmentLeft];
    y += 28;
    
    self.layerCountLabel = [self makeLabelWithText:@"Layers: 0/0"
                                           font:[UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightRegular]
                                           color:[[UIColor whiteColor] colorWithAlphaComponent:0.6]
                                           y:&y alignment:NSTextAlignmentLeft];
    
    y += 40;
    
    CGFloat btnY = self.view.bounds.size.height - 80 - btnHeight;
    self.startBtn = [self makeButtonWithTitle:@"▶ Start Auto-Draw"
                                        action:@selector(startTapped)
                                        y:&btnY width:btnWidth height:btnHeight];
    self.startBtn.backgroundColor = [UIColor systemGreenColor];
    self.startBtn.layer.cornerRadius = 8;
    
    self.pauseBtn = [self makeButtonWithTitle:@"⏸ Pause"
                                        action:@selector(pauseTapped)
                                        y:&btnY width:btnWidth height:btnHeight];
    self.pauseBtn.backgroundColor = [UIColor systemYellowColor];
    self.pauseBtn.layer.cornerRadius = 8;
    self.pauseBtn.alpha = 0.6;
    
    self.stopBtn = [self makeButtonWithTitle:@"⏹ Stop / Emergency Stop"
                                       action:@selector(stopTapped)
                                       y:&btnY width:btnWidth height:btnHeight];
    self.stopBtn.backgroundColor = [UIColor systemRedColor];
    self.stopBtn.layer.cornerRadius = 8;
    self.stopBtn.alpha = 0.6;
    
    // ROI overlay for region selection
    self.roiOverlay = [[UIView alloc] initWithFrame:self.view.bounds];
    self.roiOverlay.backgroundColor = [UIColor clearColor];
    self.roiOverlay.layer.borderColor = [UIColor systemYellowColor].CGColor;
    self.roiOverlay.layer.borderWidth = 2;
    self.roiOverlay.layer.cornerRadius = 4;
    self.roiOverlay.hidden = YES;
    [self.view addSubview:self.roiOverlay];
    
    // Tap to exit ROI selection mode
    self.tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(roiSelectionTapped:)];
    self.tapGesture.numberOfTapsRequired = 2;
    self.tapGesture.delegate = self;
    [self.roiOverlay addGestureRecognizer:self.tapGesture];
    
    // Long press on overlay for emergency stop
    UILongPressGestureRecognizer *emergencyGesture = [[UILongPressGestureRecognizer alloc] initWithTarget:self
                                                                                                 action:@selector(emergencyStopPressed:)];
    emergencyGesture.minimumPressDuration = 0.5;
    [self.roiOverlay addGestureRecognizer:emergencyGesture];
}

- (UIButton *)makeButtonWithTitle:(NSString *)title action:(SEL)action y:(CGFloat *)y width:(CGFloat)w height:(CGFloat)h {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    btn.frame = CGRectMake(20, *y, w, h);
    [btn setTitle:title forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
    [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    btn.backgroundColor = [[UIColor systemGrayColor] colorWithAlphaComponent:0.3];
    btn.layer.cornerRadius = 8;
    btn.layer.borderWidth = 1;
    btn.layer.borderColor = [[UIColor whiteColor] colorWithAlphaComponent:0.1].CGColor;
    [btn addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [self.controlsContainer addSubview:btn];
    *y += h + 8;
    return btn;
}

- (UILabel *)makeLabelWithText:(NSString *)text font:(UIFont *)font color:(UIColor *)color y:(CGFloat *)y alignment:(NSTextAlignment)alignment {
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(20, *y, 280, 24)];
    label.text = text;
    label.font = font;
    label.textColor = color;
    label.textAlignment = alignment;
    label.numberOfLines = 1;
    [self.controlsContainer addSubview:label];
    *y += 28;
    return label;
}

#pragma mark - Actions

- (void)loadImageTapped {
    if ([self.delegate respondsToSelector:@selector(autoDrawControllerDidRequestImage:)]) {
        [self.delegate autoDrawControllerDidRequestImage:self];
    }
}

- (void)selectRegionTapped {
    self.roiSelectionEnabled = YES;
    self.roiOverlay.hidden = NO;
    self.roiOverlay.alpha = 0;
    [UIView animateWithDuration:0.3 animations:^{
        self.roiOverlay.alpha = 1;
    }];
    if ([self.delegate respondsToSelector:@selector(autoDrawController:didRequestROISelection:)]) {
        [self.delegate autoDrawController:self didRequestROISelection:YES];
    }
}

- (void)roiSelectionTapped:(UITapGestureRecognizer *)gesture {
    // Double tap to confirm ROI
    CGRect roi = self.roiOverlay.frame;
    if (CGRectGetWidth(roi) > 50 && CGRectGetHeight(roi) > 50) {
        self.roiSelectionEnabled = NO;
        [self updateROI:roi];
        [self.roiOverlay removeFromSuperview];
        self.roiOverlay = nil;
        self.roiOverlay = [[UIView alloc] initWithFrame:self.view.bounds];
        self.roiOverlay.backgroundColor = [UIColor clearColor];
        self.roiOverlay.layer.borderColor = [UIColor systemYellowColor].CGColor;
        self.roiOverlay.layer.borderWidth = 2;
        self.roiOverlay.layer.cornerRadius = 4;
        self.roiOverlay.hidden = YES;
        [self.view addSubview:self.roiOverlay];
        [self.tapGesture removeFromRecognizer];
        self.tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(roiSelectionTapped:)];
        self.tapGesture.numberOfTapsRequired = 2;
        [self.roiOverlay addGestureRecognizer:self.tapGesture];
    }
}

- (void)startTapped {
    if (self.executionController && self.referenceImage) {
        [self.executionController startAutomationWithImage:self.referenceImage roiRect:self.roiRect];
    }
    if ([self.delegate respondsToSelector:@selector(autoDrawControllerDidRequestStart:)]) {
        [self.delegate autoDrawControllerDidRequestStart:self];
    }
}

- (void)pauseTapped {
    if ([self.delegate respondsToSelector:@selector(autoDrawControllerDidRequestPause:)]) {
        [self.delegate autoDrawControllerDidRequestPause:self];
    }
}

- (void)stopTapped {
    if ([self.delegate respondsToSelector:@selector(autoDrawControllerDidRequestStop:)]) {
        [self.delegate autoDrawControllerDidRequestStop:self];
    }
}

- (void)layerLimitChanged:(UISlider *)slider {
    NSInteger limit = (NSInteger)slider.value;
    self.layerLimitLabel.text = [NSString stringWithFormat:@"%ld layers", (long)limit];
    if (self.executionController) {
        [self.executionController setMaxLayers:limit];
    }
}

- (void)touchDelayChanged:(UISlider *)slider {
    CGFloat ms = slider.value;
    self.touchDelayLabel.text = [NSString stringWithFormat:@"%.0f ms", ms];
    if (self.executionController) {
        [self.executionController setTouchDelay:ms];
    }
}

- (void)emergencyStopPressed:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) {
        [self stopTapped];
        [self showToast:@"Emergency Stop Activated"];
    }
}

#pragma mark - Public

- (void)loadReferenceImage:(UIImage *)image {
    self.referenceImage = image;
    self.loadImageBtn.setTitle:[NSString stringWithFormat:@"✓ Image Loaded (%lu×%lu)",
                                 (unsigned long)image.size.width, (unsigned long)image.size.height];
    self.loadImageBtn.backgroundColor = [UIColor systemGreenColor];
}

- (void)clearReferenceImage {
    self.referenceImage = nil;
    self.loadImageBtn.setTitle:@"Load Reference Image";
    self.loadImageBtn.backgroundColor = [UIColor systemBlueColor];
}

- (void)updateROI:(CGRect)rect {
    self.roiRect = rect;
    if (self.executionController) {
        self.executionController.referenceROIRect = rect;
    }
}

- (void)showControlsAnimated:(BOOL)animated {
    self.isVisible = YES;
    self.controlsContainer.transform = CGAffineTransformMakeScale(0.8, 0.8);
    self.controlsContainer.alpha = 0;
    if (animated) {
        [UIView animateWithDuration:0.3 animations:^{
            self.controlsContainer.transform = CGAffineTransformIdentity;
            self.controlsContainer.alpha = 1;
        }];
    } else {
        self.controlsContainer.transform = CGAffineTransformIdentity;
        self.controlsContainer.alpha = 1;
    }
}

- (void)hideControlsAnimated:(BOOL)animated {
    self.isVisible = NO;
    if (animated) {
        [UIView animateWithDuration:0.2 animations:^{
            self.controlsContainer.alpha = 0;
        }];
    } else {
        self.controlsContainer.alpha = 0;
    }
}

- (NSString *)statusText {
    return self.statusLabel.text ?: @"Ready";
}

#pragma mark - Update Methods

- (void)updateProgress:(CGFloat)progress {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.progressView.progress = progress;
        self.statusLabel.text = [NSString stringWithFormat:@"Progress: %.0f%%", progress*100];
    });
}

- (void)updateLayerCount:(NSUInteger)placed total:(NSUInteger)total {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.layerCountLabel.text = [NSString stringWithFormat:@"Layers: %lu/%lu", (unsigned long)placed, (unsigned long)total];
    });
}

- (void)updateStatus:(NSString *)status {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.statusLabel.text = status;
    });
}

- (void)showToast:(NSString *)message {
    UILabel *toast = [[UILabel alloc] init];
    toast.text = message;
    toast.textColor = [UIColor whiteColor];
    toast.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    toast.textAlignment = NSTextAlignmentCenter;
    toast.numberOfLines = 2;
    toast.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.8];
    toast.layer.cornerRadius = 8;
    toast.clipsToBounds = YES;
    [toast sizeToFit];
    toast.frame = CGRectMake(0, 0, toast.frame.size.width + 24, toast.frame.size.height + 16);
    toast.center = CGPointMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds));
    toast.alpha = 0;
    [self.view addSubview:toast];
    [UIView animateWithDuration:0.2 animations:^{ toast.alpha = 1; }];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [UIView animateWithDuration:0.2 animations:^{ toast.alpha = 0; } completion:^(BOOL f) {
            [toast removeFromSuperview];
        }];
    });
}

@end
