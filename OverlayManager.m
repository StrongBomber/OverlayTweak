/**
 * OverlayManager.m
 *
 * Fixes vs original:
 *  - Window is attached to the active UIWindowScene (required on iOS 13+).
 *  - Does not steal the game's key window (no makeKeyAndVisible on setup).
 *  - hitTest lets presented modals (PHPicker / alerts) receive touches.
 *  - Settings is a child of a real root view controller.
 *  - Images stored as JPEG on disk, not PNG in NSUserDefaults (lag).
 *  - Slider/gesture persistence is debounced.
 *  - OverlayView is actually used; rasterized to cut overdraw.
 */

#import "OverlayManager.h"
#import "OverlayCommon.h"
#import "OverlayView.h"
#import "SettingsViewController.h"
#import <math.h>
#import <QuartzCore/QuartzCore.h>

#pragma mark - Private interface (must be first so the window can call us)

@interface OverlayManager () <UIGestureRecognizerDelegate, OverlayViewCropDelegate>

@property (nonatomic, strong, readwrite) UIWindow *overlayWindow;
@property (nonatomic, strong, readwrite) UIView *overlayContainer;
@property (nonatomic, assign, readwrite) BOOL isOverlayVisible;
@property (nonatomic, assign, readwrite) BOOL isLocked;

// CPM Automation properties
@property (nonatomic, strong, readwrite, nullable) id executionController;
@property (nonatomic, strong, readwrite, nullable) id autoDrawViewController;
@property (nonatomic, assign, readwrite) BOOL isAutoDrawRunning;
@property (nonatomic, assign, readwrite) CGFloat autoDrawProgress;
@property (nonatomic, assign, readwrite) BOOL isSettingsVisible;

@property (nonatomic, strong) OverlayView *overlayView;
@property (nonatomic, strong) UIButton *menuButton;
@property (nonatomic, strong) UIButton *edgeTab;
@property (nonatomic, strong) UIView *settingsContainerView;
@property (nonatomic, strong) SettingsViewController *settingsVC;

@property (nonatomic, strong) UIPanGestureRecognizer *panGesture;
@property (nonatomic, strong) UIPinchGestureRecognizer *pinchGesture;
@property (nonatomic, strong) UIRotationGestureRecognizer *rotationGesture;

@property (nonatomic, assign) CGFloat currentOpacityValue;
@property (nonatomic, assign) CGFloat currentScaleValue;
@property (nonatomic, assign) CGFloat currentRotationValue;
@property (nonatomic, assign) CGPoint currentPosition;
@property (nonatomic, assign) BOOL flipH;
@property (nonatomic, assign) BOOL flipV;
@property (nonatomic, assign) NSInteger contentModeIndexValue;
@property (nonatomic, assign) NSInteger sizeModeValue; /* 0 follow image, 1 custom */
@property (nonatomic, assign) CGFloat customWidthValue;
@property (nonatomic, assign) CGFloat customHeightValue;
@property (nonatomic, assign) BOOL showsBorderValue;
@property (nonatomic, assign) BOOL showsGridValue;
@property (nonatomic, assign) CGFloat pitchValue;
@property (nonatomic, assign) CGFloat yawValue;
@property (nonatomic, assign) UIEdgeInsets cropInsetsValue;
@property (nonatomic, assign) BOOL cropModeEnabled;
@property (nonatomic, assign) BOOL warpModeEnabled;
@property (nonatomic, assign) BOOL perspectiveModeEnabled;
@property (nonatomic, strong) UIView *cropBar;
@property (nonatomic, assign) BOOL menuHidden;
@property (nonatomic, strong) NSArray<UIButton *> *quickButtons;
@property (nonatomic, assign) BOOL quickMenuOpen;

@property (nonatomic, strong) NSUserDefaults *defaults;
@property (nonatomic, assign) BOOL setupCompleted;
@property (nonatomic, assign) NSInteger setupAttempts;
@property (nonatomic, weak) UIWindow *previousKeyWindow;
@property (nonatomic, strong) UIView *toastView;
@property (nonatomic, assign) BOOL colorPickModeEnabled;
@property (nonatomic, assign) CGFloat pickerSavedOpacity;
@property (nonatomic, assign) BOOL cropSessionValid;
@property (nonatomic, assign) CGPoint cropSessionOrigin;
@property (nonatomic, assign) CGSize cropSessionBase;
@property (nonatomic, strong) UIView *pickerLoupe;
@property (nonatomic, strong) UIView *pickerCatcher;
@property (nonatomic, copy) NSString *pickedColorHex;

- (UIView *)hitTestOverlayPoint:(CGPoint)point event:(UIEvent *)event;

@end

#pragma mark - Passthrough window

@interface OverlayPassthroughWindow : UIWindow
@end

@implementation OverlayPassthroughWindow

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    /* Presented picker/alert must receive touches via default delivery. */
    if (self.rootViewController.presentedViewController) {
        return [super hitTest:point withEvent:event];
    }
    return [[OverlayManager sharedManager] hitTestOverlayPoint:point event:event];
}

@end

#pragma mark - Root VC (needed so we can present modals)

@interface OverlayRootViewController : UIViewController
@end

@implementation OverlayRootViewController

- (void)loadView {
    UIView *v = [[UIView alloc] initWithFrame:[UIScreen mainScreen].bounds];
    v.backgroundColor = [UIColor clearColor];
    v.opaque = NO;
    v.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.view = v;
}

- (BOOL)prefersStatusBarHidden { return NO; }
- (BOOL)shouldAutorotate { return YES; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskAll;
}

@end

#pragma mark - OverlayManager

@implementation OverlayManager

+ (instancetype)sharedManager {
    static OverlayManager *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[OverlayManager alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _defaults = [NSUserDefaults standardUserDefaults];
        _currentOpacityValue = 0.5;
        _currentScaleValue = 1.0;
        _currentRotationValue = 0.0;
        _currentPosition = CGPointZero;
        _contentModeIndexValue = 0;
        _sizeModeValue = 0;
        _customWidthValue = 240.0;
        _customHeightValue = 240.0;
        _showsBorderValue = YES;
        _showsGridValue = NO;
        _pitchValue = 0;
        _yawValue = 0;
        _cropInsetsValue = UIEdgeInsetsZero;
        _isOverlayVisible = NO;
        _isLocked = NO;
        _isSettingsVisible = NO;
        _setupCompleted = NO;
        _setupAttempts = 0;
    }
    return self;
}

#pragma mark - Setup

- (void)setup {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self setup]; });
        return;
    }
    if (_setupCompleted) return;

    if (![self activeWindowScene] && ![self findHostWindow]) {
        if (_setupAttempts++ < 20) {
            NSTimeInterval delay = MIN(0.3 * _setupAttempts, 2.0);
            OLLog(@"No window/scene yet, retry %ld in %.1fs", (long)_setupAttempts, delay);
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{ [self setup]; });
        } else {
            OLLog(@"Gave up finding a window for now; will retry on become-active.");
            _setupAttempts = 0;
        }
        return;
    }

    OLLog(@"Setup starting…");
    [self loadSavedState];
    [self createOverlayWindow];
    if (!self.overlayWindow) {
        OLLog(@"Failed to create overlay window.");
        return;
    }
    [self createOverlayContainer];
    [self createMenuButton];
    [self createEdgeTab];
    [self setupGestures];
    [self loadSavedImage];
    [self syncOverlaySizeAnimated:NO];
    [self installObservers];

    _setupCompleted = YES;
    OLLog(@"Overlay created.");

    BOOL visible = YES;
    if ([_defaults objectForKey:kDefaultsOverlayVisible]) {
        visible = [_defaults boolForKey:kDefaultsOverlayVisible];
    }
    if (visible) {
        [self showOverlay];
    } else {
        self.overlayContainer.hidden = YES;
        self.isOverlayVisible = NO;
    }

    if (self.menuHidden) {
        self.menuButton.hidden = YES;
        self.edgeTab.hidden = NO;
    }

    if (![_defaults boolForKey:kDefaultsWelcomeShown]) {
        [self showToast:[NSString stringWithFormat:@"Overlay v%@  ·  ⚙️ menü", kOLVersion]];
        [_defaults setBool:YES forKey:kDefaultsWelcomeShown];
    }
}

- (void)installObservers {
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(appBackgrounded)
               name:UIApplicationDidEnterBackgroundNotification object:nil];
    [nc addObserver:self selector:@selector(handleGeometryChange)
               name:UIApplicationDidChangeStatusBarOrientationNotification object:nil];
    if (@available(iOS 13.0, *)) {
        [nc addObserver:self selector:@selector(handleGeometryChange)
                   name:UISceneDidActivateNotification object:nil];
    }
}

- (void)appBackgrounded {
    [self saveCurrentState];
}

- (void)handleGeometryChange {
    if (!self.overlayWindow) return;
    if (@available(iOS 13.0, *)) {
        UIWindowScene *scene = [self activeWindowScene];
        if (scene) {
            if (self.overlayWindow.windowScene != scene) {
                self.overlayWindow.windowScene = scene;
            }
            self.overlayWindow.frame = scene.coordinateSpace.bounds;
        }
    } else {
        self.overlayWindow.frame = [UIScreen mainScreen].bounds;
    }
    [self clampOverlayToScreen];
    [self clampMenuToScreen];
}

#pragma mark - Windows / scenes

- (UIWindowScene *)activeWindowScene {
    if (@available(iOS 13.0, *)) {
        UIWindowScene *fallback = nil;
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) continue;
            UIWindowScene *ws = (UIWindowScene *)scene;
            if (ws.activationState == UISceneActivationStateForegroundActive) return ws;
            if (!fallback) fallback = ws;
        }
        return fallback;
    }
    return nil;
}

- (UIWindow *)findHostWindow {
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) continue;
            for (UIWindow *w in ((UIWindowScene *)scene).windows) {
                if (w == self.overlayWindow || w.hidden || w.alpha <= 0) continue;
                if (w.isKeyWindow) return w;
            }
        }
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) continue;
            for (UIWindow *w in ((UIWindowScene *)scene).windows) {
                if (w == self.overlayWindow || w.hidden) continue;
                return w;
            }
        }
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    UIWindow *key = [UIApplication sharedApplication].keyWindow;
#pragma clang diagnostic pop
    if (key && key != self.overlayWindow) return key;

    id delegate = [UIApplication sharedApplication].delegate;
    if ([delegate respondsToSelector:@selector(window)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        UIWindow *w = [delegate performSelector:@selector(window)];
#pragma clang diagnostic pop
        if (w && w != self.overlayWindow) return w;
    }
    return nil;
}

- (void)createOverlayWindow {
    CGRect bounds = [UIScreen mainScreen].bounds;
    OverlayPassthroughWindow *win = nil;

    if (@available(iOS 13.0, *)) {
        UIWindowScene *scene = [self activeWindowScene];
        if (scene) {
            win = [[OverlayPassthroughWindow alloc] initWithWindowScene:scene];
            bounds = scene.coordinateSpace.bounds;
            win.frame = bounds;
            OLLog(@"Attached to scene %@", scene);
        }
    }
    if (!win) {
        win = [[OverlayPassthroughWindow alloc] initWithFrame:bounds];
    }

    win.windowLevel = UIWindowLevelStatusBar + 100;
    win.backgroundColor = [UIColor clearColor];
    win.opaque = NO;
    win.userInteractionEnabled = YES;
    OverlayRootViewController *root = [OverlayRootViewController new];
    win.rootViewController = root;
    win.hidden = NO; /* do NOT makeKeyAndVisible — that pauses games */

    self.overlayWindow = win;
    OLLog(@"Overlay window ready (level %.0f)", win.windowLevel);
}

#pragma mark - Overlay container

- (void)createOverlayContainer {
    CGRect bounds = self.overlayWindow.bounds;
    CGSize start = [self resolvedOverlaySize];
    CGFloat w = start.width;
    CGFloat h = start.height;

    OverlayView *view = [[OverlayView alloc] initWithFrame:CGRectMake(0, 0, w, h)];
    view.imageContentMode = [self contentModeFromIndex:_contentModeIndexValue];
    view.flipHorizontal = _flipH;
    view.flipVertical = _flipV;
    view.showsBorder = _showsBorderValue;
    view.showsGrid = _showsGridValue;
    view.uncroppedSize = start;
    view.cropInsets = _cropInsetsValue;
    view.cropDelegate = self;
    view.layer.allowsEdgeAntialiasing = YES;
    CGSize cropped = [view croppedSize];
    view.bounds = CGRectMake(0, 0, cropped.width, cropped.height);

    if (_currentPosition.x != 0 || _currentPosition.y != 0) {
        view.center = _currentPosition;
    } else {
        view.center = CGPointMake(CGRectGetMidX(bounds), CGRectGetMidY(bounds));
        _currentPosition = view.center;
    }

    view.alpha = _currentOpacityValue;
    view.hidden = YES;
    [view setLockedAppearance:_isLocked];

    [self.overlayWindow.rootViewController.view addSubview:view];
    self.overlayView = view;
    self.overlayContainer = view;
    [self applyContainerTransform];
    [self applySavedWarp];
    [self clampOverlayToScreen];
}

#pragma mark - Menu

- (void)createMenuButton {
    CGFloat size = 52.0;
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    btn.frame = CGRectMake(0, 0, size, size);
    btn.accessibilityLabel = @"Overlay menü";

    UIBlurEffect *blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark];
    UIVisualEffectView *blurView = [[UIVisualEffectView alloc] initWithEffect:blur];
    blurView.frame = btn.bounds;
    blurView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    blurView.userInteractionEnabled = NO;
    blurView.layer.cornerRadius = size / 2.0;
    blurView.clipsToBounds = YES;
    [btn insertSubview:blurView atIndex:0];

    [btn setTitle:@"⚙️" forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont systemFontOfSize:22];
    btn.layer.cornerRadius = size / 2.0;
    btn.layer.borderWidth = 1.0 / [UIScreen mainScreen].scale;
    btn.layer.borderColor = [[UIColor whiteColor] colorWithAlphaComponent:0.28].CGColor;
    btn.layer.shadowColor = [UIColor blackColor].CGColor;
    btn.layer.shadowOpacity = 0.45;
    btn.layer.shadowRadius = 10;
    btn.layer.shadowOffset = CGSizeMake(0, 4);

    [btn addTarget:self action:@selector(menuTapped) forControlEvents:UIControlEventTouchUpInside];
    [btn addTarget:self action:@selector(menuHighlight) forControlEvents:UIControlEventTouchDown];
    [btn addTarget:self action:@selector(menuUnhighlight)
  forControlEvents:(UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel)];
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(menuDragged:)];
    [btn addGestureRecognizer:pan];
    UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(menuLongPressed:)];
    lp.minimumPressDuration = 0.32;
    lp.allowableMovement = 14;
    [btn addGestureRecognizer:lp];

    [self.overlayWindow.rootViewController.view addSubview:btn];
    self.menuButton = btn;
    [self createQuickButtons];

    CGRect b = self.overlayWindow.bounds;
    UIEdgeInsets inset = self.overlayWindow.safeAreaInsets;
    CGFloat x = [_defaults doubleForKey:kDefaultsMenuX];
    CGFloat y = [_defaults doubleForKey:kDefaultsMenuY];
    if (x <= 0 || y <= 0) {
        x = b.size.width - size / 2.0 - 14.0 - inset.right;
        y = inset.top + 36.0 + size / 2.0;
    }
    btn.center = CGPointMake(x, y);
    [self clampMenuToScreen];
}

- (void)createEdgeTab {
    UIButton *tab = [UIButton buttonWithType:UIButtonTypeCustom];
    tab.frame = CGRectMake(0, 0, 26, 52);
    tab.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.62];
    tab.layer.cornerRadius = 10;
    tab.layer.maskedCorners = kCALayerMaxXMinYCorner | kCALayerMaxXMaxYCorner;
    tab.layer.borderWidth = 1.0 / [UIScreen mainScreen].scale;
    tab.layer.borderColor = [[UIColor whiteColor] colorWithAlphaComponent:0.18].CGColor;
    [tab setTitle:@"⚙" forState:UIControlStateNormal];
    tab.titleLabel.font = [UIFont systemFontOfSize:14];
    tab.hidden = YES;
    [tab addTarget:self action:@selector(edgeTabTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.overlayWindow.rootViewController.view addSubview:tab];
    self.edgeTab = tab;
    [self positionEdgeTab];
}

- (void)positionEdgeTab {
    if (!self.edgeTab) return;
    CGRect b = self.overlayWindow.bounds;
    UIEdgeInsets inset = self.overlayWindow.safeAreaInsets;
    self.edgeTab.center = CGPointMake(11 + inset.left, inset.top + 80);
    if (self.edgeTab.center.y > b.size.height) {
        self.edgeTab.center = CGPointMake(11 + inset.left, b.size.height * 0.3);
    }
}

- (void)menuHighlight {
    [UIView animateWithDuration:0.12 animations:^{
        self.menuButton.transform = CGAffineTransformMakeScale(0.90, 0.90);
    }];
}

- (void)menuUnhighlight {
    [UIView animateWithDuration:0.18 delay:0 usingSpringWithDamping:0.7 initialSpringVelocity:0.4 options:0 animations:^{
        self.menuButton.transform = CGAffineTransformIdentity;
    } completion:nil];
}

- (void)menuTapped {
    if (_quickMenuOpen) {
        [self hideQuickMenu];
        return;
    }
    [self endAllEditModes];
    if (self.isSettingsVisible) [self hideSettingsPanel];
    else [self showSettingsPanel];
}

- (void)menuLongPressed:(UILongPressGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateBegan) return;
    if (!self.menuButton || self.menuButton.hidden) return;
    [self menuUnhighlight];
    if (self.isSettingsVisible) [self hideSettingsPanel];
    if (_quickMenuOpen) [self hideQuickMenu];
    else [self showQuickMenu];
}

- (void)edgeTabTapped {
    [self setMenuHidden:NO];
    [self showSettingsPanel];
}

- (void)menuDragged:(UIPanGestureRecognizer *)g {
    if (_quickMenuOpen && g.state == UIGestureRecognizerStateBegan) {
        /* Keep fan attached while dragging the hub. */
    }
    CGPoint t = [g translationInView:self.overlayWindow];
    CGPoint c = CGPointMake(g.view.center.x + t.x, g.view.center.y + t.y);
    g.view.center = c;
    [g setTranslation:CGPointZero inView:self.overlayWindow];
    [self clampMenuToScreen];
    if (_quickMenuOpen) [self layoutQuickButtonsFromHub:NO];
    if (g.state == UIGestureRecognizerStateEnded) {
        [_defaults setDouble:self.menuButton.center.x forKey:kDefaultsMenuX];
        [_defaults setDouble:self.menuButton.center.y forKey:kDefaultsMenuY];
    }
}

- (void)setMenuHidden:(BOOL)hidden {
    _menuHidden = hidden;
    self.menuButton.hidden = hidden;
    self.edgeTab.hidden = !hidden;
    [_defaults setBool:hidden forKey:kDefaultsMenuHidden];
    if (hidden) {
        [self hideQuickMenu];
        [self showToast:@"Menü gizlendi — kenar ⚙"];
    }
}

#pragma mark - Quick actions (long-press hub)

- (UIButton *)makeRoundToolButton:(NSString *)title {
    CGFloat size = 50.0;
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    btn.frame = CGRectMake(0, 0, size, size);
    UIBlurEffect *blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark];
    UIVisualEffectView *blurView = [[UIVisualEffectView alloc] initWithEffect:blur];
    blurView.frame = btn.bounds;
    blurView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    blurView.userInteractionEnabled = NO;
    blurView.layer.cornerRadius = size / 2.0;
    blurView.clipsToBounds = YES;
    [btn insertSubview:blurView atIndex:0];
    [btn setTitle:title forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont systemFontOfSize:20];
    btn.layer.cornerRadius = size / 2.0;
    btn.layer.borderWidth = 1.0 / [UIScreen mainScreen].scale;
    btn.layer.borderColor = [[UIColor whiteColor] colorWithAlphaComponent:0.28].CGColor;
    btn.layer.shadowColor = [UIColor blackColor].CGColor;
    btn.layer.shadowOpacity = 0.45;
    btn.layer.shadowRadius = 10;
    btn.layer.shadowOffset = CGSizeMake(0, 4);
    btn.hidden = YES;
    btn.alpha = 0;
    btn.exclusiveTouch = YES;
    return btn;
}

- (void)createQuickButtons {
    for (UIButton *b in self.quickButtons) [b removeFromSuperview];
    UIView *root = self.overlayWindow.rootViewController.view;
    NSArray *titles = @[ @"✂️", @"🔒", @"👁", @"✨", @"📐", @"🎨" ];
    NSArray *labels = @[ @"Kırp", @"Kilit", @"Göster", @"Warp", @"Perspektif", @"Renk" ];
    NSMutableArray *btns = [NSMutableArray array];
    for (NSInteger i = 0; i < 6; i++) {
        UIButton *b = [self makeRoundToolButton:titles[i]];
        b.tag = 900 + i;
        b.accessibilityLabel = labels[i];
        [b addTarget:self action:@selector(quickTapped:) forControlEvents:UIControlEventTouchUpInside];
        [root insertSubview:b belowSubview:self.menuButton];
        [btns addObject:b];
    }
    self.quickButtons = btns;
    [self refreshQuickButtonFaces];
}

- (void)refreshQuickButtonFaces {
    if (self.quickButtons.count < 6) return;
    [self.quickButtons[1] setTitle:self.isLocked ? @"🔒" : @"🔓" forState:UIControlStateNormal];
    self.quickButtons[1].accessibilityLabel = self.isLocked ? @"Kilidi aç" : @"Kilitle";
    [self.quickButtons[2] setTitle:self.isOverlayVisible ? @"👁" : @"🙈" forState:UIControlStateNormal];
    self.quickButtons[2].accessibilityLabel = self.isOverlayVisible ? @"Overlay gizle" : @"Overlay göster";
}

- (void)layoutQuickButtonsFromHub:(BOOL)collapsed {
    if (!self.menuButton || self.quickButtons.count == 0) return;
    CGPoint hub = self.menuButton.center;
    CGRect b = self.overlayWindow.bounds;
    CGFloat R = collapsed ? 0 : 94.0;
    CGFloat toward = atan2(CGRectGetMidY(b) - hub.y, CGRectGetMidX(b) - hub.x);
    CGFloat span = 190.0 * (CGFloat)M_PI / 180.0;
    CGFloat a0 = toward - span * 0.5;
    NSInteger n = (NSInteger)self.quickButtons.count;
    for (NSInteger i = 0; i < n; i++) {
        CGFloat a = (n <= 1) ? toward : (a0 + span * i / (CGFloat)(n - 1));
        CGPoint p = CGPointMake(hub.x + cos(a) * R, hub.y + sin(a) * R);
        self.quickButtons[i].center = p;
    }
}

- (void)showQuickMenu {
    if (_quickMenuOpen || !self.menuButton || self.menuButton.hidden) return;
    if (self.quickButtons.count == 0) [self createQuickButtons];
    [self refreshQuickButtonFaces];
    _quickMenuOpen = YES;
    CGPoint hub = self.menuButton.center;
    for (UIButton *b in self.quickButtons) {
        b.hidden = NO;
        b.alpha = 0;
        b.center = hub;
        b.transform = CGAffineTransformMakeScale(0.35, 0.35);
        [b.superview bringSubviewToFront:b];
    }
    [self.menuButton.superview bringSubviewToFront:self.menuButton];
    [self layoutQuickButtonsFromHub:NO];
    NSArray *targets = [self.quickButtons copy];
    for (NSInteger i = 0; i < (NSInteger)targets.count; i++) {
        UIButton *b = targets[i];
        CGPoint dest = b.center;
        b.center = hub;
        [UIView animateWithDuration:0.42
                              delay:0.03 * i
             usingSpringWithDamping:0.70
              initialSpringVelocity:0.55
                            options:UIViewAnimationOptionAllowUserInteraction
                         animations:^{
            b.center = dest;
            b.alpha = 1;
            b.transform = CGAffineTransformIdentity;
        } completion:nil];
    }
}

- (void)hideQuickMenu {
    if (!_quickMenuOpen && self.quickButtons.count == 0) return;
    _quickMenuOpen = NO;
    CGPoint hub = self.menuButton.center;
    NSArray *btns = [self.quickButtons copy];
    [UIView animateWithDuration:0.22 delay:0 options:UIViewAnimationOptionCurveEaseIn animations:^{
        for (UIButton *b in btns) {
            b.center = hub;
            b.alpha = 0;
            b.transform = CGAffineTransformMakeScale(0.35, 0.35);
        }
    } completion:^(__unused BOOL f) {
        if (!self->_quickMenuOpen) {
            for (UIButton *b in btns) {
                b.hidden = YES;
                b.transform = CGAffineTransformIdentity;
            }
        }
    }];
}

- (void)quickTapped:(UIButton *)btn {
    NSInteger i = btn.tag - 900;
    switch (i) {
        case 0:
            [self hideQuickMenu];
            [self beginCropMode];
            break;
        case 1:
            [self toggleLock];
            [self refreshQuickButtonFaces];
            [self showToast:self.isLocked ? @"Kilitlendi" : @"Kilit açıldı"];
            if (self.isLocked) [self endAllEditModes];
            break;
        case 2:
            [self toggleOverlay];
            [self refreshQuickButtonFaces];
            [self showToast:self.isOverlayVisible ? @"Overlay görünür" : @"Overlay gizli"];
            break;
        case 3:
            [self hideQuickMenu];
            [self beginWarpMode];
            break;
        case 4:
            [self hideQuickMenu];
            [self beginPerspectiveMode];
            break;
        case 5:
            [self hideQuickMenu];
            [self beginColorPickMode];
            break;
        default:
            break;
    }
}

- (BOOL)isMenuHidden { return _menuHidden; }

#pragma mark - Gestures

- (void)setupGestures {
    self.panGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    self.panGesture.maximumNumberOfTouches = 1;
    [self.overlayContainer addGestureRecognizer:self.panGesture];

    self.pinchGesture = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(handlePinch:)];
    [self.overlayContainer addGestureRecognizer:self.pinchGesture];

    self.rotationGesture = [[UIRotationGestureRecognizer alloc] initWithTarget:self action:@selector(handleRotation:)];
    [self.overlayContainer addGestureRecognizer:self.rotationGesture];

    UITapGestureRecognizer *dbl = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleDoubleTap:)];
    dbl.numberOfTapsRequired = 2;
    [self.overlayContainer addGestureRecognizer:dbl];

    UITapGestureRecognizer *colorTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleColorTap:)];
    colorTap.numberOfTapsRequired = 1;
    colorTap.delegate = self;
    [self.overlayContainer addGestureRecognizer:colorTap];

    UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
    lp.minimumPressDuration = 0.45;
    [self.overlayContainer addGestureRecognizer:lp];

    self.panGesture.delegate = self;
    self.pinchGesture.delegate = self;
    self.rotationGesture.delegate = self;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)a shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)b {
    if (_cropModeEnabled || _warpModeEnabled || _perspectiveModeEnabled || _colorPickModeEnabled) {
        return NO;
    }
    return YES;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldReceiveTouch:(UITouch *)t {
    if (g.view == self.settingsContainerView) {
        return t.view == self.settingsContainerView;
    }
    BOOL editing = _cropModeEnabled || _warpModeEnabled || _perspectiveModeEnabled;
    if ([g isKindOfClass:[UITapGestureRecognizer class]] &&
        ((UITapGestureRecognizer *)g).numberOfTapsRequired == 1 &&
        g.view == self.overlayContainer) {
        return _colorPickModeEnabled;
    }
    if (_colorPickModeEnabled) {
        if (g == self.panGesture || g == self.pinchGesture || g == self.rotationGesture) return NO;
        if ([g isKindOfClass:[UITapGestureRecognizer class]] &&
            ((UITapGestureRecognizer *)g).numberOfTapsRequired == 2) {
            return NO;
        }
    }
    if (editing && (g == self.panGesture || g == self.pinchGesture || g == self.rotationGesture)) {
        return NO;
    }
    if ([self.overlayView isCropHandleView:t.view]) {
        return NO;
    }
    return YES;
}

- (void)applyContainerTransform {
    if (!self.overlayContainer) return;
    /* 2D affine and 3D layer transforms fight — keep UIView.transform identity. */
    self.overlayContainer.transform = CGAffineTransformIdentity;
    CATransform3D t = CATransform3DIdentity;
    t.m34 = -1.0 / 700.0;
    t = CATransform3DRotate(t, _pitchValue, 1, 0, 0);
    t = CATransform3DRotate(t, _yawValue, 0, 1, 0);
    t = CATransform3DRotate(t, _currentRotationValue, 0, 0, 1);
    t = CATransform3DScale(t, _currentScaleValue, _currentScaleValue, 1);
    self.overlayContainer.layer.transform = t;
    BOOL perspectiveOn = (fabs(_pitchValue) > 0.001 || fabs(_yawValue) > 0.001);
    self.overlayContainer.layer.shouldRasterize = !perspectiveOn && !_cropModeEnabled && !_warpModeEnabled && !_perspectiveModeEnabled;
    self.overlayContainer.layer.rasterizationScale = [UIScreen mainScreen].scale;
}

- (void)handlePan:(UIPanGestureRecognizer *)g {
    if (_colorPickModeEnabled) {
        [self sampleColorFromGesture:g];
        return;
    }
    if (self.isLocked || _cropModeEnabled || _warpModeEnabled || _perspectiveModeEnabled) return;
    UIView *v = g.view;
    CGPoint t = [g translationInView:v.superview];
    v.center = CGPointMake(v.center.x + t.x, v.center.y + t.y);
    [g setTranslation:CGPointZero inView:v.superview];
    _currentPosition = v.center;
    if (g.state == UIGestureRecognizerStateEnded || g.state == UIGestureRecognizerStateCancelled) {
        [self clampOverlayToScreen];
        [self scheduleSave];
    }
}

- (void)handlePinch:(UIPinchGestureRecognizer *)g {
    if (self.isLocked || _cropModeEnabled || _warpModeEnabled || _perspectiveModeEnabled || _colorPickModeEnabled) return;
    if (g.state == UIGestureRecognizerStateChanged) {
        _currentScaleValue = MAX(0.15, MIN(6.0, _currentScaleValue * g.scale));
        [self applyContainerTransform];
        g.scale = 1.0;
    }
    if (g.state == UIGestureRecognizerStateEnded) [self scheduleSave];
}

- (void)handleRotation:(UIRotationGestureRecognizer *)g {
    if (self.isLocked || _cropModeEnabled || _warpModeEnabled || _perspectiveModeEnabled || _colorPickModeEnabled) return;
    if (g.state == UIGestureRecognizerStateChanged) {
        _currentRotationValue += g.rotation;
        [self applyContainerTransform];
        g.rotation = 0;
    }
    if (g.state == UIGestureRecognizerStateEnded) [self scheduleSave];
}

- (void)handleDoubleTap:(UITapGestureRecognizer *)g {
    if (self.isLocked || _cropModeEnabled || _colorPickModeEnabled) return;
    [self resetTransform];
    [self showToast:@"Konum sıfırlandı"];
}

- (void)handleLongPress:(UILongPressGestureRecognizer *)g {
    if (_cropModeEnabled || _warpModeEnabled || _perspectiveModeEnabled || _colorPickModeEnabled) return;
    if (g.state != UIGestureRecognizerStateBegan) return;
    [self toggleLock];
    [self showToast:self.isLocked ? @"Kilitlendi — dokunmalar oyuna geçer" : @"Kilit açıldı"];
}

- (void)clampOverlayToScreen {
    if (!self.overlayContainer || _cropModeEnabled) return;
    CGSize s = self.overlayWindow.bounds.size;
    CGPoint c = self.overlayContainer.center;
    c.x = MAX(24, MIN(s.width - 24, c.x));
    c.y = MAX(24, MIN(s.height - 24, c.y));
    self.overlayContainer.center = c;
    _currentPosition = c;
}

- (void)clampMenuToScreen {
    if (!self.menuButton) return;
    CGSize s = self.overlayWindow.bounds.size;
    CGPoint c = self.menuButton.center;
    UIEdgeInsets inset = self.overlayWindow.safeAreaInsets;
    c.x = MAX(24 + inset.left, MIN(s.width - 24 - inset.right, c.x));
    c.y = MAX(24 + inset.top, MIN(s.height - 24 - inset.bottom, c.y));
    self.menuButton.center = c;
}

#pragma mark - Hit testing

- (UIView *)hitTestOverlayPoint:(CGPoint)point event:(UIEvent *)event {
    UIWindow *win = self.overlayWindow;
    if (!win) return nil;

    if (!self.isOverlayVisible && !self.isSettingsVisible && self.menuButton.hidden && self.edgeTab.hidden && !self.cropBar) {
        return nil;
    }

    if (self.cropBar && !self.cropBar.hidden) {
        CGPoint p = [win convertPoint:point toView:self.cropBar];
        if ([self.cropBar pointInside:p withEvent:event]) {
            return [self.cropBar hitTest:p withEvent:event];
        }
    }

    if (_colorPickModeEnabled && self.pickerCatcher) {
        /* Bar already handled. Let the catcher own the rest so overlay cannot pan. */
        if (self.menuButton && !self.menuButton.hidden) {
            CGPoint p = [win convertPoint:point toView:self.menuButton];
            if ([self.menuButton pointInside:p withEvent:event]) {
                return [self.menuButton hitTest:p withEvent:event];
            }
        }
        CGPoint p = [win convertPoint:point toView:self.pickerCatcher];
        return [self.pickerCatcher hitTest:p withEvent:event] ?: self.pickerCatcher;
    }

    if (_quickMenuOpen) {
        for (UIButton *b in self.quickButtons) {
            if (b.hidden) continue;
            CGPoint p = [win convertPoint:point toView:b];
            if ([b pointInside:p withEvent:event]) {
                return [b hitTest:p withEvent:event];
            }
        }
    }

    if (self.menuButton && !self.menuButton.hidden) {
        CGPoint p = [win convertPoint:point toView:self.menuButton];
        if ([self.menuButton pointInside:p withEvent:event]) {
            return [self.menuButton hitTest:p withEvent:event];
        }
    }

    if (self.edgeTab && !self.edgeTab.hidden) {
        CGPoint p = [win convertPoint:point toView:self.edgeTab];
        if ([self.edgeTab pointInside:p withEvent:event]) {
            return [self.edgeTab hitTest:p withEvent:event];
        }
    }

    if (self.isSettingsVisible && self.settingsContainerView) {
        CGPoint p = [win convertPoint:point toView:self.settingsContainerView];
        if ([self.settingsContainerView pointInside:p withEvent:event]) {
            return [self.settingsContainerView hitTest:p withEvent:event];
        }
    }

    BOOL editing = _cropModeEnabled || _warpModeEnabled || _perspectiveModeEnabled || _colorPickModeEnabled;
    if (self.overlayContainer && self.isOverlayVisible && !self.overlayContainer.hidden &&
        (!self.isLocked || editing)) {
        CGPoint p = [win convertPoint:point toView:self.overlayContainer];
        if ([self.overlayContainer pointInside:p withEvent:event]) {
            return [self.overlayContainer hitTest:p withEvent:event];
        }
    }

    return nil;
}

#pragma mark - Visibility

- (void)showOverlay {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self showOverlay]; });
        return;
    }
    self.overlayContainer.hidden = NO;
    self.overlayContainer.alpha = 0;
    [UIView animateWithDuration:0.2 animations:^{
        self.overlayContainer.alpha = self.currentOpacityValue;
    }];
    self.isOverlayVisible = YES;
    [_defaults setBool:YES forKey:kDefaultsOverlayVisible];
}

- (void)hideOverlay {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self hideOverlay]; });
        return;
    }
    [UIView animateWithDuration:0.2 animations:^{
        self.overlayContainer.alpha = 0;
    } completion:^(BOOL f) {
        if (!self.isOverlayVisible) self.overlayContainer.hidden = YES;
    }];
    self.isOverlayVisible = NO;
    [_defaults setBool:NO forKey:kDefaultsOverlayVisible];
}

- (void)toggleOverlay {
    self.isOverlayVisible ? [self hideOverlay] : [self showOverlay];
    [self refreshQuickButtonFaces];
}

#pragma mark - Image

- (NSString *)imagePath {
    NSString *lib = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES).firstObject;
    NSString *dir = [lib stringByAppendingPathComponent:@"OverlayTweak"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return [dir stringByAppendingPathComponent:@"overlay.jpg"];
}

- (UIImage *)downscaledImage:(UIImage *)image maxDimension:(CGFloat)maxDim {
    if (!image) return nil;
    CGFloat w = image.size.width * image.scale;
    CGFloat h = image.size.height * image.scale;
    CGFloat m = MAX(w, h);
    if (m <= maxDim) return image;
    CGFloat f = maxDim / m;
    CGSize newSize = CGSizeMake(image.size.width * f, image.size.height * f);
    UIGraphicsImageRendererFormat *fmt = [UIGraphicsImageRendererFormat defaultFormat];
    fmt.scale = 1.0;
    fmt.opaque = NO;
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:newSize format:fmt];
    return [r imageWithActions:^(__unused UIGraphicsImageRendererContext *ctx) {
        [image drawInRect:CGRectMake(0, 0, newSize.width, newSize.height)];
    }];
}

- (void)setOverlayImage:(UIImage *)image {
    if (!image) return;
    UIImage *scaled = [self downscaledImage:image maxDimension:2048.0];
    self.overlayView.image = scaled;
    if (_sizeModeValue == 0) {
        /* New photo → overlay takes the photo's shape (and native size if it fits). */
        _currentScaleValue = 1.0;
        [self applyContainerTransform];
        [self syncOverlaySizeAnimated:YES];
    }
    if (self.overlayContainer.hidden && !self.isOverlayVisible) {
        [self showOverlay];
    }
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSData *data = UIImageJPEGRepresentation(scaled, 0.82);
        if (!data) return;
        [data writeToFile:[self imagePath] atomically:YES];
        /* Drop legacy UserDefaults blob so it stops inflating launches. */
        if ([self.defaults objectForKey:kDefaultsImageBookmark]) {
            [self.defaults removeObjectForKey:kDefaultsImageBookmark];
        }
        OLLog(@"Image saved (%lu bytes).", (unsigned long)data.length);
    });
}

- (void)clearOverlayImage {
    self.overlayView.image = nil;
    [self.overlayView clearImage];
    [[NSFileManager defaultManager] removeItemAtPath:[self imagePath] error:nil];
    [_defaults removeObjectForKey:kDefaultsImageBookmark];
    if (_sizeModeValue == 0) [self syncOverlaySizeAnimated:YES];
}

- (UIImage *)currentImage {
    return self.overlayView.image;
}

- (void)loadSavedImage {
    NSString *path = [self imagePath];
    if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
        UIImage *img = [UIImage imageWithContentsOfFile:path];
        if (img) {
            self.overlayView.image = img;
            OLLog(@"Image loaded from disk.");
            return;
        }
    }
    NSData *legacy = [_defaults objectForKey:kDefaultsImageBookmark];
    if ([legacy isKindOfClass:[NSData class]] && legacy.length > 0) {
        UIImage *img = [UIImage imageWithData:legacy];
        if (img) [self setOverlayImage:img];
    }
}

#pragma mark - Appearance properties

- (void)setOpacity:(CGFloat)opacity {
    opacity = MAX(0.02, MIN(1.0, opacity));
    _currentOpacityValue = opacity;
    if (self.isOverlayVisible) self.overlayContainer.alpha = opacity;
    [_defaults setBool:YES forKey:kDefaultsHasOpacity];
    [_defaults setDouble:opacity forKey:kDefaultsOpacity];
    [self scheduleSave];
}

- (CGFloat)currentOpacity { return _currentOpacityValue; }

- (void)setScale:(CGFloat)scale {
    _currentScaleValue = MAX(0.15, MIN(6.0, scale));
    [self applyContainerTransform];
    [self scheduleSave];
}

- (CGFloat)currentScale { return _currentScaleValue; }

- (void)setRotation:(CGFloat)rotation {
    _currentRotationValue = rotation;
    [self applyContainerTransform];
    [self scheduleSave];
}

- (CGFloat)currentRotation { return _currentRotationValue; }

- (void)setLocked:(BOOL)locked {
    _isLocked = locked;
    [self.overlayView setLockedAppearance:locked];
    [_defaults setBool:locked forKey:kDefaultsIsLocked];
    if (locked) [self endAllEditModes];
    [self refreshQuickButtonFaces];
}

- (void)toggleLock { [self setLocked:!self.isLocked]; }

- (void)setFlipHorizontal:(BOOL)flip {
    _flipH = flip;
    self.overlayView.flipHorizontal = flip;
    [_defaults setBool:flip forKey:kDefaultsFlipH];
}

- (BOOL)flipHorizontal { return _flipH; }

- (void)setFlipVertical:(BOOL)flip {
    _flipV = flip;
    self.overlayView.flipVertical = flip;
    [_defaults setBool:flip forKey:kDefaultsFlipV];
}

- (BOOL)flipVertical { return _flipV; }

- (UIViewContentMode)contentModeFromIndex:(NSInteger)index {
    switch (index) {
        case 1: return UIViewContentModeScaleAspectFill;
        case 2: return UIViewContentModeScaleToFill;
        default: return UIViewContentModeScaleAspectFit;
    }
}

- (void)setContentModeIndex:(NSInteger)index {
    _contentModeIndexValue = MAX(0, MIN(2, index));
    self.overlayView.imageContentMode = [self contentModeFromIndex:_contentModeIndexValue];
    [_defaults setInteger:_contentModeIndexValue forKey:kDefaultsContentMode];
}

- (NSInteger)contentModeIndex { return _contentModeIndexValue; }

#pragma mark - Size (follow image / custom)

- (NSInteger)sizeMode { return _sizeModeValue; }

- (void)setSizeMode:(NSInteger)mode {
    _sizeModeValue = (mode == 1) ? 1 : 0;
    [_defaults setInteger:_sizeModeValue forKey:kDefaultsSizeMode];
    if (_sizeModeValue == 0) _currentScaleValue = 1.0;
    [self applyContainerTransform];
    [self syncOverlaySizeAnimated:YES];
}

- (CGSize)customSize {
    return CGSizeMake(_customWidthValue, _customHeightValue);
}

- (void)setCustomSize:(CGSize)size {
    size = [self clampSize:size];
    _customWidthValue = size.width;
    _customHeightValue = size.height;
    _sizeModeValue = 1;
    _currentScaleValue = 1.0;
    [_defaults setInteger:1 forKey:kDefaultsSizeMode];
    [_defaults setDouble:_customWidthValue forKey:kDefaultsCustomWidth];
    [_defaults setDouble:_customHeightValue forKey:kDefaultsCustomHeight];
    [self applyContainerTransform];
    [self syncOverlaySizeAnimated:YES];
}

- (CGSize)currentOverlaySize {
    if (!self.overlayContainer) return [self resolvedOverlaySize];
    return self.overlayContainer.bounds.size;
}

- (CGSize)imageNativeSize {
    UIImage *img = self.overlayView.image;
    if (!img) return CGSizeZero;
    return CGSizeMake(img.size.width * img.scale, img.size.height * img.scale);
}

- (CGSize)clampSize:(CGSize)size {
    CGSize screen = self.overlayWindow ? self.overlayWindow.bounds.size : [UIScreen mainScreen].bounds.size;
    CGFloat maxW = MAX(80.0, screen.width * 1.5);
    CGFloat maxH = MAX(80.0, screen.height * 1.5);
    size.width  = MAX(40.0, MIN(maxW, size.width));
    size.height = MAX(40.0, MIN(maxH, size.height));
    return size;
}

- (CGSize)sizeFittingScreen:(CGSize)raw {
    CGSize screen = self.overlayWindow ? self.overlayWindow.bounds.size : [UIScreen mainScreen].bounds.size;
    if (raw.width < 1 || raw.height < 1) {
        return CGSizeMake(220, 220);
    }
    /* Keep the photo's exact aspect. Use native pixel size as points when it
       fits; otherwise scale down uniformly so a 9:16 stays 9:16. Never upscale. */
    CGFloat maxW = screen.width * 0.92;
    CGFloat maxH = screen.height * 0.82;
    CGFloat f = MIN(1.0, MIN(maxW / raw.width, maxH / raw.height));
    return [self clampSize:CGSizeMake(raw.width * f, raw.height * f)];
}

- (CGSize)resolvedOverlaySize {
    if (_sizeModeValue == 1) {
        return [self clampSize:CGSizeMake(_customWidthValue, _customHeightValue)];
    }
    UIImage *img = self.overlayView.image;
    if (!img) {
        return CGSizeMake(220, 220);
    }
    CGSize pixels = CGSizeMake(img.size.width * img.scale, img.size.height * img.scale);
    return [self sizeFittingScreen:pixels];
}

- (void)syncOverlaySizeAnimated:(BOOL)animated {
    if (!self.overlayContainer) return;
    CGSize base = [self resolvedOverlaySize];
    self.overlayView.uncroppedSize = base;
    self.overlayView.cropInsets = _cropInsetsValue;
    CGSize size = [self.overlayView croppedSize];
    CGPoint center = self.overlayContainer.center;
    if (center.x == 0 && center.y == 0) {
        CGRect b = self.overlayWindow.bounds;
        center = CGPointMake(CGRectGetMidX(b), CGRectGetMidY(b));
    }
    CATransform3D t = self.overlayContainer.layer.transform;
    void (^apply)(void) = ^{
        self.overlayContainer.layer.transform = CATransform3DIdentity;
        self.overlayContainer.bounds = CGRectMake(0, 0, size.width, size.height);
        self.overlayContainer.center = center;
        self.overlayContainer.layer.transform = t;
        [self clampOverlayToScreen];
    };
    if (animated) {
        [UIView animateWithDuration:0.22 animations:apply];
    } else {
        apply();
    }
    [self scheduleSave];
}

- (void)nudgeBy:(CGPoint)delta {
    if (!self.overlayContainer || self.isLocked) return;
    CGPoint c = self.overlayContainer.center;
    c.x += delta.x;
    c.y += delta.y;
    self.overlayContainer.center = c;
    _currentPosition = c;
    [self clampOverlayToScreen];
    [self scheduleSave];
}

- (void)snapToAlignment:(NSInteger)alignment {
    if (!self.overlayContainer) return;
    CGRect b = self.overlayWindow.bounds;
    CGPoint c = self.overlayContainer.center;
    switch (alignment) {
        case 1: c.x = 24.0 + self.overlayContainer.bounds.size.width * _currentScaleValue * 0.5; break;
        case 2: c.x = b.size.width - 24.0 - self.overlayContainer.bounds.size.width * _currentScaleValue * 0.5; break;
        case 3: c.y = 24.0 + self.overlayContainer.bounds.size.height * _currentScaleValue * 0.5; break;
        case 4: c.y = b.size.height - 24.0 - self.overlayContainer.bounds.size.height * _currentScaleValue * 0.5; break;
        default:
            c = CGPointMake(CGRectGetMidX(b), CGRectGetMidY(b));
            break;
    }
    self.overlayContainer.center = c;
    _currentPosition = c;
    [self clampOverlayToScreen];
    [self scheduleSave];
}

- (void)rotateByDegrees:(CGFloat)degrees {
    _currentRotationValue += degrees * (CGFloat)M_PI / 180.0;
    [self applyContainerTransform];
    [self scheduleSave];
}

- (void)setShowsBorder:(BOOL)show {
    _showsBorderValue = show;
    self.overlayView.showsBorder = show;
    if (!show && self.isLocked) {
        /* Keep the red lock cue even if the decorative border is off. */
        [self.overlayView setLockedAppearance:YES];
    }
    [_defaults setBool:show forKey:kDefaultsShowsBorder];
}

- (BOOL)showsBorder { return _showsBorderValue; }

- (void)setShowsGrid:(BOOL)show {
    _showsGridValue = show;
    self.overlayView.showsGrid = show;
    [_defaults setBool:show forKey:kDefaultsShowsGrid];
}

- (BOOL)showsGrid { return _showsGridValue; }

- (void)setPitch:(CGFloat)pitch {
    _pitchValue = MAX(-1.2, MIN(1.2, pitch));
    [self applyContainerTransform];
    [self scheduleSave];
}

- (CGFloat)pitch { return _pitchValue; }

- (void)setYaw:(CGFloat)yaw {
    _yawValue = MAX(-1.2, MIN(1.2, yaw));
    [self applyContainerTransform];
    [self scheduleSave];
}

- (CGFloat)yaw { return _yawValue; }

- (void)resetPerspective {
    _pitchValue = 0;
    _yawValue = 0;
    [self applyContainerTransform];
    [self scheduleSave];
}

- (void)setCropInsets:(UIEdgeInsets)insets {
    [self applyCropInsets:insets keepPosition:YES];
}

- (void)applyCropInsets:(UIEdgeInsets)insets keepPosition:(BOOL)keep {
    if (!self.overlayView) {
        _cropInsetsValue = insets;
        return;
    }
    CGSize base = self.overlayView.uncroppedSize;
    if (base.width < 40 || base.height < 40) {
        base = [self resolvedOverlaySize];
        self.overlayView.uncroppedSize = base;
    }
    insets = [self.overlayView clampedCropInsets:insets];
    UIEdgeInsets old = _cropInsetsValue;
    CGFloat w = MAX(40.0, base.width * (1.0 - insets.left - insets.right));
    CGFloat h = MAX(40.0, base.height * (1.0 - insets.top - insets.bottom));

    UIView *view = self.overlayContainer;
    CATransform3D t = view.layer.transform;
    view.layer.transform = CATransform3DIdentity;

    CGPoint origin;
    if (_cropSessionValid) {
        origin = CGPointMake(_cropSessionOrigin.x + insets.left * _cropSessionBase.width,
                             _cropSessionOrigin.y + insets.top * _cropSessionBase.height);
    } else {
        origin = CGPointMake(view.center.x - view.bounds.size.width * 0.5,
                             view.center.y - view.bounds.size.height * 0.5);
        if (keep) {
            origin.x += (insets.left - old.left) * base.width;
            origin.y += (insets.top - old.top) * base.height;
        }
    }
    view.bounds = CGRectMake(0, 0, w, h);
    view.center = CGPointMake(origin.x + w * 0.5, origin.y + h * 0.5);
    view.layer.transform = t;

    _cropInsetsValue = insets;
    self.overlayView.cropInsets = insets;
    _currentPosition = view.center;
    [self scheduleSave];
}

- (UIEdgeInsets)cropInsets { return _cropInsetsValue; }

- (void)resetCrop {
    if (_cropModeEnabled) {
        _cropInsetsValue = UIEdgeInsetsZero;
        self.overlayView.cropInsets = UIEdgeInsetsZero;
        return;
    }
    [self applyCropInsets:UIEdgeInsetsZero keepPosition:YES];
}

- (void)overlayView:(OverlayView *)view didChangeCropInsets:(UIEdgeInsets)insets {
    insets = [view clampedCropInsets:insets];
    if (_cropModeEnabled) {
        /* Do not move or resize the overlay — only the crop rectangle changes. */
        _cropInsetsValue = insets;
        view.cropInsets = insets;
        return;
    }
    [self applyCropInsets:insets keepPosition:YES];
}

- (void)overlayView:(OverlayView *)view didChangeWarpPoints:(NSArray<NSValue *> *)points {
    (void)view;
    (void)points;
    [self scheduleSave];
}

- (void)overlayView:(OverlayView *)view didChangePitchDelta:(CGFloat)dPitch yawDelta:(CGFloat)dYaw {
    (void)view;
    [self setPitch:_pitchValue + dPitch];
    [self setYaw:_yawValue + dYaw];
}

- (void)endAllEditModes {
    [self endCropMode];
    [self endWarpMode];
    [self endPerspectiveMode];
    [self endColorPickMode];
}

- (BOOL)prepareEditMode {
    if (![NSThread isMainThread]) return NO;
    if (self.isLocked) {
        [self showToast:@"Önce kilidi açın"];
        return NO;
    }
    if (self.isSettingsVisible) [self hideSettingsPanel];
    if (!self.isOverlayVisible) [self showOverlay];
    return YES;
}

- (void)beginCropMode {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self beginCropMode]; });
        return;
    }
    if (![self prepareEditMode]) return;
    [self endWarpMode];
    [self endPerspectiveMode];
    [self endColorPickMode];
    UIView *view = self.overlayContainer;
    CGSize base = self.overlayView.uncroppedSize;
    if (base.width < 40 || base.height < 40) {
        base = [self resolvedOverlaySize];
        self.overlayView.uncroppedSize = base;
    }
    CATransform3D t = view.layer.transform;
    view.layer.transform = CATransform3DIdentity;
    UIEdgeInsets cur = _cropInsetsValue;
    CGPoint origin = CGPointMake(view.center.x - view.bounds.size.width * 0.5,
                                 view.center.y - view.bounds.size.height * 0.5);
    origin.x -= cur.left * base.width;
    origin.y -= cur.top * base.height;
    _cropSessionOrigin = origin;
    _cropSessionBase = base;
    _cropSessionValid = YES;
    view.bounds = CGRectMake(0, 0, base.width, base.height);
    view.center = CGPointMake(origin.x + base.width * 0.5, origin.y + base.height * 0.5);
    view.layer.transform = t;
    _currentPosition = view.center;
    _cropModeEnabled = YES;
    self.overlayView.uncroppedSize = base;
    self.overlayView.cropModeEnabled = YES;
    [self applyContainerTransform];
    [self showEditBarTitle:@"Kırpma" resetTitle:@"Sıfırla" reset:@selector(resetCrop) done:@selector(endCropMode)];
    [self showToast:@"Görsel sabit — çerçeveyi sürükleyin"];
}

- (void)endCropMode {
    if (!_cropModeEnabled) return;
    UIEdgeInsets insets = _cropInsetsValue;
    _cropModeEnabled = NO;
    self.overlayView.cropModeEnabled = NO;
    [self applyCropInsets:insets keepPosition:YES];
    _cropSessionValid = NO;
    [self applyContainerTransform];
    [self hideCropBar];
    [self saveCurrentState];
}

- (BOOL)isCropModeEnabled { return _cropModeEnabled; }

- (void)beginWarpMode {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self beginWarpMode]; });
        return;
    }
    if (![self prepareEditMode]) return;
    [self endCropMode];
    [self endPerspectiveMode];
    [self endColorPickMode];
    _warpModeEnabled = YES;
    self.overlayView.warpModeEnabled = YES;
    [self applyContainerTransform];
    [self showEditBarTitle:@"Warp / Distort" resetTitle:@"Sıfırla" reset:@selector(resetWarp) done:@selector(endWarpMode)];
    [self showToast:@"3×3 ızgara — köşeler distort, iç noktalar warp"];
}

- (void)endWarpMode {
    if (!_warpModeEnabled) return;
    _warpModeEnabled = NO;
    self.overlayView.warpModeEnabled = NO;
    [self applyContainerTransform];
    [self hideCropBar];
    [self saveCurrentState];
}

- (void)resetWarp {
    [self.overlayView resetWarp];
    [self scheduleSave];
}

- (void)beginPerspectiveMode {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self beginPerspectiveMode]; });
        return;
    }
    if (![self prepareEditMode]) return;
    [self endCropMode];
    [self endWarpMode];
    [self endColorPickMode];
    _perspectiveModeEnabled = YES;
    self.overlayView.perspectiveModeEnabled = YES;
    [self applyContainerTransform];
    [self showEditBarTitle:@"Perspektif" resetTitle:@"Sıfırla" reset:@selector(resetPerspective) done:@selector(endPerspectiveMode)];
    [self showToast:@"Kenar tutamaçları: pitch / yaw"];
}

- (void)endPerspectiveMode {
    if (!_perspectiveModeEnabled) return;
    _perspectiveModeEnabled = NO;
    self.overlayView.perspectiveModeEnabled = NO;
    [self applyContainerTransform];
    [self hideCropBar];
    [self saveCurrentState];
}

- (void)showEditBarTitle:(NSString *)titleText resetTitle:(NSString *)resetTitle reset:(SEL)reset done:(SEL)done {
    [self.cropBar removeFromSuperview];
    UIView *root = self.overlayWindow.rootViewController.view;
    CGFloat w = MIN(340.0, root.bounds.size.width - 24.0);
    CGFloat h = 56.0;
    UIEdgeInsets inset = self.overlayWindow.safeAreaInsets;
    UIView *bar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, h)];
    bar.center = CGPointMake(CGRectGetMidX(root.bounds), root.bounds.size.height - inset.bottom - 22 - h * 0.5);
    bar.backgroundColor = [[UIColor colorWithWhite:0.08 alpha:0.92] colorWithAlphaComponent:0.92];
    bar.layer.cornerRadius = 16;
    bar.layer.borderWidth = 1.0 / [UIScreen mainScreen].scale;
    bar.layer.borderColor = [[UIColor whiteColor] colorWithAlphaComponent:0.16].CGColor;
    bar.layer.shadowColor = [UIColor blackColor].CGColor;
    bar.layer.shadowOpacity = 0.4;
    bar.layer.shadowRadius = 16;
    bar.layer.shadowOffset = CGSizeMake(0, 6);
    bar.userInteractionEnabled = YES;

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(16, 0, w - 188, h)];
    title.text = titleText;
    title.textColor = [UIColor whiteColor];
    title.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    title.tag = 701;
    [bar addSubview:title];

    UIButton *resetBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    resetBtn.frame = CGRectMake(w - 176, 12, 78, 32);
    [resetBtn setTitle:(resetTitle.length ? resetTitle : @"Sıfırla") forState:UIControlStateNormal];
    [resetBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    resetBtn.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    resetBtn.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.12];
    resetBtn.layer.cornerRadius = 10;
    resetBtn.exclusiveTouch = YES;
    [resetBtn addTarget:self action:reset forControlEvents:UIControlEventTouchUpInside];
    [bar addSubview:resetBtn];

    UIButton *doneBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    doneBtn.frame = CGRectMake(w - 90, 12, 78, 32);
    [doneBtn setTitle:@"Tamam" forState:UIControlStateNormal];
    [doneBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    doneBtn.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    doneBtn.backgroundColor = [UIColor systemBlueColor];
    doneBtn.layer.cornerRadius = 10;
    doneBtn.exclusiveTouch = YES;
    [doneBtn addTarget:self action:done forControlEvents:UIControlEventTouchUpInside];
    [bar addSubview:doneBtn];

    bar.alpha = 0;
    bar.transform = CGAffineTransformMakeTranslation(0, 12);
    [root addSubview:bar];
    [root bringSubviewToFront:bar];
    self.cropBar = bar;
    [UIView animateWithDuration:0.28 delay:0 usingSpringWithDamping:0.85 initialSpringVelocity:0.4 options:0 animations:^{
        bar.alpha = 1;
        bar.transform = CGAffineTransformIdentity;
    } completion:nil];
}

- (void)hideCropBar {
    [self.cropBar removeFromSuperview];
    self.cropBar = nil;
}

- (void)handleColorTap:(UITapGestureRecognizer *)g {
    if (!_colorPickModeEnabled) return;
    [self sampleColorFromGesture:g];
}

- (void)beginColorPickMode {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self beginColorPickMode]; });
        return;
    }
    if (![self prepareEditMode]) return;
    if (!self.overlayView.image) {
        [self showToast:@"Önce bir görsel seçin"];
        return;
    }
    [self endCropMode];
    [self endWarpMode];
    [self endPerspectiveMode];
    _pickerSavedOpacity = _currentOpacityValue;
    _colorPickModeEnabled = YES;
    self.overlayContainer.hidden = NO;
    self.isOverlayVisible = YES;
    [_defaults setBool:YES forKey:kDefaultsOverlayVisible];
    self.overlayContainer.alpha = 1.0;
    self.overlayContainer.layer.shouldRasterize = NO;
    [self.overlayView beginColorSampling];
    [self showColorPickBar];
    [self installPickerCatcher];
    [self ensurePickerLoupe];
    [self showToast:@"Opaklık %100 — overlay’den renk al"];
}

- (void)showColorPickBar {
    [self showEditBarTitle:@"#------" resetTitle:@"Kopyala" reset:@selector(copyPickedColor) done:@selector(endColorPickMode)];
    UIView *bar = self.cropBar;
    if (!bar) return;
    CGFloat w = bar.bounds.size.width;
    UIView *swatch = [[UIView alloc] initWithFrame:CGRectMake(12, 12, 32, 32)];
    swatch.backgroundColor = [UIColor whiteColor];
    swatch.layer.cornerRadius = 8;
    swatch.layer.borderWidth = 1.0 / [UIScreen mainScreen].scale;
    swatch.layer.borderColor = [[UIColor whiteColor] colorWithAlphaComponent:0.4].CGColor;
    swatch.tag = 703;
    [bar addSubview:swatch];
    UILabel *title = [bar viewWithTag:701];
    title.frame = CGRectMake(52, 6, w - 228, 24);
    title.font = [UIFont monospacedDigitSystemFontOfSize:17 weight:UIFontWeightSemibold];
    title.text = @"#------";
    UILabel *rgb = [[UILabel alloc] initWithFrame:CGRectMake(52, 28, w - 228, 18)];
    rgb.font = [UIFont monospacedDigitSystemFontOfSize:11 weight:UIFontWeightMedium];
    rgb.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.7];
    rgb.tag = 704;
    rgb.text = @"RGB  —";
    [bar addSubview:rgb];
}

- (void)installPickerCatcher {
    [self.pickerCatcher removeFromSuperview];
    UIView *root = self.overlayWindow.rootViewController.view;
    UIView *catcher = [[UIView alloc] initWithFrame:root.bounds];
    catcher.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    catcher.backgroundColor = [UIColor clearColor];
    catcher.userInteractionEnabled = YES;
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(sampleColorFromGesture:)];
    pan.maximumNumberOfTouches = 1;
    [catcher addGestureRecognizer:pan];
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(sampleColorFromGesture:)];
    [catcher addGestureRecognizer:tap];
    [root addSubview:catcher];
    if (self.cropBar) [root bringSubviewToFront:self.cropBar];
    if (self.menuButton) [root bringSubviewToFront:self.menuButton];
    self.pickerCatcher = catcher;
}

- (void)endColorPickMode {
    if (!_colorPickModeEnabled) return;
    _colorPickModeEnabled = NO;
    if (self.isOverlayVisible) {
        self.overlayContainer.alpha = _pickerSavedOpacity;
    }
    [self.overlayView endColorSampling];
    [_pickerLoupe removeFromSuperview];
    _pickerLoupe = nil;
    [_pickerCatcher removeFromSuperview];
    _pickerCatcher = nil;
    [self hideCropBar];
}

- (void)ensurePickerLoupe {
    if (_pickerLoupe) return;
    UIView *root = self.overlayWindow.rootViewController.view;
    UIView *loupe = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 130, 154)];
    loupe.userInteractionEnabled = NO;
    loupe.hidden = YES;
    UIImageView *mag = [[UIImageView alloc] initWithFrame:CGRectMake(5, 5, 120, 120)];
    mag.layer.cornerRadius = 60;
    mag.clipsToBounds = YES;
    mag.contentMode = UIViewContentModeScaleToFill;
    mag.layer.borderWidth = 3;
    mag.layer.borderColor = [UIColor whiteColor].CGColor;
    mag.tag = 1;
    [loupe addSubview:mag];
    UIView *ring = [[UIView alloc] initWithFrame:mag.frame];
    ring.userInteractionEnabled = NO;
    ring.layer.cornerRadius = 60;
    ring.layer.borderWidth = 2;
    ring.layer.borderColor = [[UIColor blackColor] colorWithAlphaComponent:0.35].CGColor;
    [loupe addSubview:ring];
    UILabel *hex = [[UILabel alloc] initWithFrame:CGRectMake(0, 128, 130, 22)];
    hex.font = [UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightSemibold];
    hex.textAlignment = NSTextAlignmentCenter;
    hex.textColor = [UIColor whiteColor];
    hex.layer.shadowColor = [UIColor blackColor].CGColor;
    hex.layer.shadowOpacity = 0.85;
    hex.layer.shadowRadius = 2;
    hex.layer.shadowOffset = CGSizeZero;
    hex.tag = 2;
    [loupe addSubview:hex];
    [root addSubview:loupe];
    _pickerLoupe = loupe;
}

- (NSString *)hexFromColor:(UIColor *)color {
    if (!color) return @"#000000";
    CGFloat r = 0, g = 0, b = 0, a = 1;
    if (![color getRed:&r green:&g blue:&b alpha:&a]) {
        CGFloat w = 0;
        if ([color getWhite:&w alpha:&a]) {
            r = g = b = w;
        }
    }
    int R = (int)lround(MAX(0.0, MIN(1.0, r)) * 255.0);
    int G = (int)lround(MAX(0.0, MIN(1.0, g)) * 255.0);
    int B = (int)lround(MAX(0.0, MIN(1.0, b)) * 255.0);
    return [NSString stringWithFormat:@"#%02X%02X%02X", R, G, B];
}

- (void)sampleColorFromGesture:(UIGestureRecognizer *)g {
    if (!_colorPickModeEnabled || !self.overlayView) return;
    CGPoint local = [g locationInView:self.overlayView];
    if (!CGRectContainsPoint(self.overlayView.bounds, local)) return;
    UIColor *c = [self.overlayView colorAtPoint:local];
    if (!c) return;
    NSString *hex = [self hexFromColor:c];
    _pickedColorHex = hex;
    [self ensurePickerLoupe];
    UIView *root = self.overlayWindow.rootViewController.view;
    CGPoint win = [g locationInView:root];
    CGPoint loupeC = CGPointMake(win.x, win.y - 78.0);
    CGRect rb = root.bounds;
    loupeC.x = MAX(70, MIN(rb.size.width - 70, loupeC.x));
    loupeC.y = MAX(80, MIN(rb.size.height - 90, loupeC.y));
    self.pickerLoupe.hidden = NO;
    self.pickerLoupe.center = loupeC;
    UIImageView *mag = (UIImageView *)[self.pickerLoupe viewWithTag:1];
    mag.image = [self.overlayView loupeImageAtPoint:local];
    UILabel *hexLbl = (UILabel *)[self.pickerLoupe viewWithTag:2];
    hexLbl.text = hex;
    UIView *swatch = [self.cropBar viewWithTag:703];
    swatch.backgroundColor = c;
    UILabel *title = [self.cropBar viewWithTag:701];
    title.text = hex;
    CGFloat rr = 0, gg = 0, bb = 0, aa = 1;
    [c getRed:&rr green:&gg blue:&bb alpha:&aa];
    UILabel *rgb = [self.cropBar viewWithTag:704];
    rgb.text = [NSString stringWithFormat:@"RGB  %d  %d  %d",
                (int)lround(rr * 255), (int)lround(gg * 255), (int)lround(bb * 255)];
    [self.cropBar.superview bringSubviewToFront:self.cropBar];
    [self.pickerLoupe.superview bringSubviewToFront:self.pickerLoupe];
}

- (void)copyPickedColor {
    if (_pickedColorHex.length == 0) {
        [self showToast:@"Önce bir renk seçin"];
        return;
    }
    [UIPasteboard generalPasteboard].string = _pickedColorHex;
    [self showToast:[NSString stringWithFormat:@"%@ kopyalandı", _pickedColorHex]];
}

- (void)resetTransform {
    _currentScaleValue = 1.0;
    _currentRotationValue = 0.0;
    _pitchValue = 0;
    _yawValue = 0;
    CGRect b = self.overlayWindow.bounds;
    _currentPosition = CGPointMake(CGRectGetMidX(b), CGRectGetMidY(b));
    [UIView animateWithDuration:0.2 animations:^{
        self.overlayContainer.center = self->_currentPosition;
        [self applyContainerTransform];
    }];
    [self scheduleSave];
}

- (void)resetAllSettings {
    [self setOpacity:0.5];
    [self setLocked:NO];
    [self setFlipHorizontal:NO];
    [self setFlipVertical:NO];
    [self setContentModeIndex:0];
    _sizeModeValue = 0;
    _customWidthValue = 240.0;
    _customHeightValue = 240.0;
    [_defaults setInteger:0 forKey:kDefaultsSizeMode];
    [_defaults setDouble:_customWidthValue forKey:kDefaultsCustomWidth];
    [_defaults setDouble:_customHeightValue forKey:kDefaultsCustomHeight];
    [self setShowsBorder:YES];
    [self setShowsGrid:NO];
    [self endAllEditModes];
    [self resetCrop];
    [self resetWarp];
    [self resetPerspective];
    [self resetTransform];
    [self clearOverlayImage];
    [self setMenuHidden:NO];
    [self showOverlay];
    [self saveCurrentState];
}

#pragma mark - Persistence

- (void)scheduleSave {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(saveCurrentState) object:nil];
    [self performSelector:@selector(saveCurrentState) withObject:nil afterDelay:0.35];
}

- (void)saveCurrentState {
    [_defaults setDouble:_currentOpacityValue forKey:kDefaultsOpacity];
    [_defaults setBool:YES forKey:kDefaultsHasOpacity];
    [_defaults setDouble:_currentPosition.x forKey:kDefaultsPositionX];
    [_defaults setDouble:_currentPosition.y forKey:kDefaultsPositionY];
    [_defaults setDouble:_currentScaleValue forKey:kDefaultsScale];
    [_defaults setDouble:_currentRotationValue forKey:kDefaultsRotation];
    [_defaults setDouble:_pitchValue forKey:kDefaultsPitch];
    [_defaults setDouble:_yawValue forKey:kDefaultsYaw];
    [_defaults setDouble:_cropInsetsValue.left forKey:kDefaultsCropL];
    [_defaults setDouble:_cropInsetsValue.right forKey:kDefaultsCropR];
    [_defaults setDouble:_cropInsetsValue.top forKey:kDefaultsCropT];
    [_defaults setDouble:_cropInsetsValue.bottom forKey:kDefaultsCropB];
    [_defaults setBool:_isLocked forKey:kDefaultsIsLocked];
    [_defaults setBool:_flipH forKey:kDefaultsFlipH];
    [_defaults setBool:_flipV forKey:kDefaultsFlipV];
    [_defaults setInteger:_contentModeIndexValue forKey:kDefaultsContentMode];
    [_defaults setBool:_menuHidden forKey:kDefaultsMenuHidden];
    [_defaults setBool:_isOverlayVisible forKey:kDefaultsOverlayVisible];
    if (self.menuButton) {
        [_defaults setDouble:self.menuButton.center.x forKey:kDefaultsMenuX];
        [_defaults setDouble:self.menuButton.center.y forKey:kDefaultsMenuY];
    }
    NSArray *wpts = self.overlayView.warpPoints;
    if (wpts.count == 9) {
        NSMutableArray *raw = [NSMutableArray arrayWithCapacity:18];
        for (NSValue *v in wpts) {
            CGPoint p = [v CGPointValue];
            [raw addObject:@(p.x)];
            [raw addObject:@(p.y)];
        }
        [_defaults setObject:raw forKey:kDefaultsWarpPts];
    }
}

- (void)applySavedWarp {
    if (!self.overlayView) return;
    NSArray *raw = [_defaults arrayForKey:kDefaultsWarpPts];
    if (![raw isKindOfClass:[NSArray class]] || raw.count != 18) {
        self.overlayView.warpPoints = [OverlayView identityWarpPoints];
        return;
    }
    NSMutableArray *pts = [NSMutableArray arrayWithCapacity:9];
    for (NSInteger i = 0; i < 9; i++) {
        CGFloat x = [raw[i * 2] doubleValue];
        CGFloat y = [raw[i * 2 + 1] doubleValue];
        x = MAX(-0.25, MIN(1.25, x));
        y = MAX(-0.25, MIN(1.25, y));
        [pts addObject:[NSValue valueWithCGPoint:CGPointMake(x, y)]];
    }
    self.overlayView.warpPoints = pts;
}

- (void)loadSavedState {
    if ([_defaults boolForKey:kDefaultsHasOpacity]) {
        _currentOpacityValue = [_defaults doubleForKey:kDefaultsOpacity];
        _currentOpacityValue = MAX(0.02, MIN(1.0, _currentOpacityValue));
    } else {
        CGFloat v = [_defaults doubleForKey:kDefaultsOpacity];
        _currentOpacityValue = (v == 0.0) ? 0.5 : v;
    }
    _currentPosition = CGPointMake([_defaults doubleForKey:kDefaultsPositionX],
                                   [_defaults doubleForKey:kDefaultsPositionY]);
    _currentScaleValue = [_defaults doubleForKey:kDefaultsScale];
    if (_currentScaleValue == 0.0) _currentScaleValue = 1.0;
    _currentRotationValue = [_defaults doubleForKey:kDefaultsRotation];
    _pitchValue = MAX(-1.2, MIN(1.2, [_defaults doubleForKey:kDefaultsPitch]));
    _yawValue = MAX(-1.2, MIN(1.2, [_defaults doubleForKey:kDefaultsYaw]));
    _cropInsetsValue = UIEdgeInsetsMake(
        MAX(0, MIN(0.80, [_defaults doubleForKey:kDefaultsCropT])),
        MAX(0, MIN(0.80, [_defaults doubleForKey:kDefaultsCropL])),
        MAX(0, MIN(0.80, [_defaults doubleForKey:kDefaultsCropB])),
        MAX(0, MIN(0.80, [_defaults doubleForKey:kDefaultsCropR])));
    _isLocked = [_defaults boolForKey:kDefaultsIsLocked];
    _flipH = [_defaults boolForKey:kDefaultsFlipH];
    _flipV = [_defaults boolForKey:kDefaultsFlipV];
    _contentModeIndexValue = [_defaults integerForKey:kDefaultsContentMode];
    _sizeModeValue = [_defaults integerForKey:kDefaultsSizeMode];
    if (_sizeModeValue != 1) _sizeModeValue = 0;
    CGFloat cw = [_defaults doubleForKey:kDefaultsCustomWidth];
    CGFloat ch = [_defaults doubleForKey:kDefaultsCustomHeight];
    _customWidthValue = (cw >= 40.0) ? cw : 240.0;
    _customHeightValue = (ch >= 40.0) ? ch : 240.0;
    if ([_defaults objectForKey:kDefaultsShowsBorder]) {
        _showsBorderValue = [_defaults boolForKey:kDefaultsShowsBorder];
    } else {
        _showsBorderValue = YES;
    }
    _showsGridValue = [_defaults boolForKey:kDefaultsShowsGrid];
    _menuHidden = [_defaults boolForKey:kDefaultsMenuHidden];
}

#pragma mark - Settings panel

- (void)showSettingsPanel {
    if (self.isSettingsVisible) return;
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self showSettingsPanel]; });
        return;
    }
    [self hideQuickMenu];

    [self.overlayWindow layoutIfNeeded];
    UIViewController *root = self.overlayWindow.rootViewController;
    if (!root) return;

    self.settingsVC = [[SettingsViewController alloc] init];

    UIView *dim = [[UIView alloc] initWithFrame:root.view.bounds];
    dim.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    dim.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.55];
    dim.alpha = 0;
    dim.userInteractionEnabled = YES;

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(settingsBackgroundTapped:)];
    tap.delegate = self;
    tap.cancelsTouchesInView = NO;
    [dim addGestureRecognizer:tap];
    self.settingsContainerView = dim;

    CGFloat pw = MIN(368.0, CGRectGetWidth(root.view.bounds) - 20.0);
    CGFloat ph = MIN(680.0, CGRectGetHeight(root.view.bounds) - 40.0);
    self.settingsVC.view.frame = CGRectMake(0, 0, pw, ph);
    self.settingsVC.view.center = CGPointMake(CGRectGetMidX(dim.bounds), CGRectGetMidY(dim.bounds));
    self.settingsVC.view.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin |
                                            UIViewAutoresizingFlexibleRightMargin |
                                            UIViewAutoresizingFlexibleTopMargin |
                                            UIViewAutoresizingFlexibleBottomMargin;
    self.settingsVC.view.layer.cornerRadius = 22;
    self.settingsVC.view.clipsToBounds = NO;
    self.settingsVC.view.layer.shadowColor = [UIColor blackColor].CGColor;
    self.settingsVC.view.layer.shadowOpacity = 0.45;
    self.settingsVC.view.layer.shadowRadius = 28;
    self.settingsVC.view.layer.shadowOffset = CGSizeMake(0, 12);
    self.settingsVC.view.transform = CGAffineTransformMakeScale(0.94, 0.94);

    [root addChildViewController:self.settingsVC];
    [dim addSubview:self.settingsVC.view];
    [root.view addSubview:dim];
    [self.settingsVC didMoveToParentViewController:root];

    [root.view bringSubviewToFront:self.menuButton];

    [self.settingsVC.view layoutIfNeeded];

    [UIView animateWithDuration:0.32 delay:0 usingSpringWithDamping:0.84 initialSpringVelocity:0.5 options:UIViewAnimationOptionCurveEaseOut animations:^{
        dim.alpha = 1.0;
        self.settingsVC.view.transform = CGAffineTransformIdentity;
    } completion:nil];
    self.isSettingsVisible = YES;
}

- (void)settingsBackgroundTapped:(UITapGestureRecognizer *)g {
    [self hideSettingsPanel];
}

- (void)hideSettingsPanel {
    if (!self.isSettingsVisible) return;
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self hideSettingsPanel]; });
        return;
    }

    SettingsViewController *vc = self.settingsVC;
    UIView *dim = self.settingsContainerView;
    self.isSettingsVisible = NO;
    [self saveCurrentState];

    [UIView animateWithDuration:0.2 animations:^{
        dim.alpha = 0;
        vc.view.transform = CGAffineTransformMakeScale(0.96, 0.96);
    } completion:^(__unused BOOL f) {
        [vc willMoveToParentViewController:nil];
        [vc.view removeFromSuperview];
        [vc removeFromParentViewController];
        [dim removeFromSuperview];
        if (self.settingsVC == vc) {
            self.settingsContainerView = nil;
            self.settingsVC = nil;
        }
    }];
}

#pragma mark - Modal presentation (image picker)

- (void)makeOverlayWindowKey {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self makeOverlayWindowKey]; });
        return;
    }
    UIWindow *host = [self findHostWindow];
    if (host && host != self.overlayWindow) self.previousKeyWindow = host;
    [self.overlayWindow makeKeyAndVisible];
}

- (void)presentModal:(UIViewController *)viewController {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self presentModal:viewController]; });
        return;
    }
    [self makeOverlayWindowKey];
    UIViewController *root = self.overlayWindow.rootViewController;
    while (root.presentedViewController) root = root.presentedViewController;
    [root presentViewController:viewController animated:YES completion:nil];
}

- (void)restoreKeyWindow {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self restoreKeyWindow]; });
        return;
    }
    UIWindow *prev = self.previousKeyWindow;
    self.previousKeyWindow = nil;
    if (prev) {
        [prev makeKeyWindow];
        return;
    }
    UIWindow *host = [self findHostWindow];
    if (host) [host makeKeyWindow];
}

#pragma mark - Toast

#pragma mark - CPM Image-to-Vinyl Automation

- (void)showAutoDrawPanel {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self showAutoDrawPanel]; });
        return;
    }
    
    if (self.isAutoDrawRunning && self.autoDrawViewController) {
        [self autoDrawViewController:self.autoDrawViewController];
        return;
    }
    
    [self hideSettingsPanel];
    
    CPMAutoDrawViewController *vc = [[CPMAutoDrawViewController alloc] init];
    vc.delegate = self;
    vc.executionController = self.executionController;
    
    UIWindow *window = self.overlayWindow;
    if (!window) return;
    
    UIView *dim = [[UIView alloc] initWithFrame:window.bounds];
    dim.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.6];
    dim.alpha = 0;
    dim.userInteractionEnabled = YES;
    
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(hideAutoDrawPanel)];
    [dim addGestureRecognizer:tap];
    
    CGFloat pw = MIN(340.0, window.bounds.size.width - 30.0);
    CGFloat ph = MIN(500.0, window.bounds.size.height - 60.0);
    vc.view.frame = CGRectMake(0, 0, pw, ph);
    vc.view.center = CGPointMake(CGRectGetMidX(dim.bounds), CGRectGetMidY(dim.bounds));
    vc.view.layer.cornerRadius = 16;
    vc.view.clipsToBounds = YES;
    vc.view.layer.shadowColor = [UIColor blackColor].CGColor;
    vc.view.layer.shadowOpacity = 0.4;
    vc.view.layer.shadowRadius = 20;
    vc.view.layer.shadowOffset = CGSizeMake(0, 10);
    
    [window.rootViewController.view addSubview:dim];
    [window.rootViewController.view addSubview:vc.view];
    
    [UIView animateWithDuration:0.3 animations:^{
        dim.alpha = 1;
        vc.view.transform = CGAffineTransformIdentity;
    }];
    
    self.autoDrawViewController = vc;
}

- (void)hideAutoDrawPanel {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self hideAutoDrawPanel]; });
        return;
    }
    
    UIView *dim = nil;
    UIView *vcView = nil;
    
    if (self.autoDrawViewController) {
        vcView = self.autoDrawViewController.view;
    }
    
    for (UIView *subview in [self.overlayWindow.rootViewController.view subviews]) {
        if ([subview isKindOfClass:[UIView class]] && subview.backgroundColor && subview.backgroundColor.alpha < 1.0) {
            if (subview.alpha < 1.0 && subview.bounds.size.width > 100) {
                dim = subview;
                break;
            }
        }
    }
    
    if (!dim && !vcView) return;
    
    [UIView animateWithDuration:0.2 animations:^{
        if (dim) dim.alpha = 0;
        if (vcView) vcView.alpha = 0;
    } completion:^(BOOL f) {
        [vcView removeFromSuperview];
        [dim removeFromSuperview];
        self.autoDrawViewController = nil;
        self.executionController = nil;
    }];
}

- (void)autoDrawViewController:(id)controller {
    [self hideAutoDrawPanel];
}

- (void)startAutoDrawWithImage:(UIImage *)image roiRect:(CGRect)roiRect {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self startAutoDrawWithImage:image roiRect:roiRect]; });
        return;
    }
    
    if (self.isAutoDrawRunning) {
        [self stopAutoDraw];
    }
    
    self.executionController = [[CPMExecutionController alloc] init];
    self.executionController.delegate = self;
    
    [self.executionController startAutomationWithImage:image roiRect:roiRect];
    
    if (!self.autoDrawViewController) {
        [self showAutoDrawPanel];
    }
    
    [self showToast:@"Auto-Draw started"];
}

- (void)pauseAutoDraw {
    if ([self.executionController isPaused]) {
        [self.executionController resumeAutomation];
    } else {
        [self.executionController pauseAutomation];
    }
    [self showToast:[self.executionController isPaused] ? @"Auto-Draw paused" : @"Auto-Draw resumed"];
}

- (void)resumeAutoDraw {
    [self pauseAutoDraw];
}

- (void)stopAutoDraw {
    [self.executionController stopAutomation];
    [self showToast:@"Auto-Draw stopped"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        self.executionController = nil;
    });
}

- (void)emergencyStopAutoDraw {
    [self.executionController emergencyStop];
    [self showToast:@"🚨 EMERGENCY STOP"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        self.executionController = nil;
    });
}

- (void)clearAutoDrawSession {
    self.executionController = nil;
    self.autoDrawViewController = nil;
    [self hideAutoDrawPanel];
    [self showToast:@"Session cleared"];
}

- (void)showToast:(NSString *)text {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self showToast:text]; });
        return;
    }
    if (!self.overlayWindow) return;
    [self.toastView removeFromSuperview];

    UILabel *label = [[UILabel alloc] init];
    label.text = text;
    label.textColor = [UIColor whiteColor];
    label.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    label.textAlignment = NSTextAlignmentCenter;
    label.numberOfLines = 2;
    [label sizeToFit];

    CGFloat pad = 14;
    CGRect lf = label.frame;
    UIView *box = [[UIView alloc] initWithFrame:CGRectInset(lf, -pad, -8)];
    box.backgroundColor = [[UIColor colorWithWhite:0.08 alpha:1] colorWithAlphaComponent:0.92];
    box.layer.cornerRadius = 14;
    box.layer.borderWidth = 1.0 / [UIScreen mainScreen].scale;
    box.layer.borderColor = [[UIColor whiteColor] colorWithAlphaComponent:0.14].CGColor;
    label.center = CGPointMake(CGRectGetMidX(box.bounds), CGRectGetMidY(box.bounds));
    label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [box addSubview:label];

    CGRect b = self.overlayWindow.bounds;
    box.center = CGPointMake(CGRectGetMidX(b), b.size.height - 80);
    box.alpha = 0;
    [self.overlayWindow.rootViewController.view addSubview:box];
    self.toastView = box;

    [UIView animateWithDuration:0.18 animations:^{ box.alpha = 1; }];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.2 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [UIView animateWithDuration:0.25 animations:^{ box.alpha = 0; } completion:^(__unused BOOL f) {
            [box removeFromSuperview];
            if (self.toastView == box) self.toastView = nil;
        }];
    });
}

@end
