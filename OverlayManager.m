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
@property (nonatomic, strong) UIView *cropBar;
@property (nonatomic, assign) BOOL menuHidden;

@property (nonatomic, strong) NSUserDefaults *defaults;
@property (nonatomic, assign) BOOL setupCompleted;
@property (nonatomic, assign) NSInteger setupAttempts;
@property (nonatomic, weak) UIWindow *previousKeyWindow;
@property (nonatomic, strong) UIView *toastView;

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
        [self showToast:@"Overlay hazır — ⚙️ menü"];
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
    [self clampOverlayToScreen];
}

#pragma mark - Menu

- (void)createMenuButton {
    CGFloat size = 48.0;
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

    [btn addTarget:self action:@selector(menuTapped) forControlEvents:UIControlEventTouchUpInside];
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(menuDragged:)];
    [btn addGestureRecognizer:pan];

    [self.overlayWindow.rootViewController.view addSubview:btn];
    self.menuButton = btn;

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
    tab.frame = CGRectMake(0, 0, 22, 44);
    tab.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.45];
    tab.layer.cornerRadius = 8;
    tab.layer.maskedCorners = kCALayerMaxXMinYCorner | kCALayerMaxXMaxYCorner;
    [tab setTitle:@"⚙" forState:UIControlStateNormal];
    tab.titleLabel.font = [UIFont systemFontOfSize:12];
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

- (void)menuTapped {
    if (_cropModeEnabled) [self endCropMode];
    if (self.isSettingsVisible) [self hideSettingsPanel];
    else [self showSettingsPanel];
}

- (void)edgeTabTapped {
    [self setMenuHidden:NO];
    [self showSettingsPanel];
}

- (void)menuDragged:(UIPanGestureRecognizer *)g {
    CGPoint t = [g translationInView:self.overlayWindow];
    CGPoint c = CGPointMake(g.view.center.x + t.x, g.view.center.y + t.y);
    g.view.center = c;
    [g setTranslation:CGPointZero inView:self.overlayWindow];
    [self clampMenuToScreen];
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
    if (hidden) [self showToast:@"Menü gizlendi — kenar ⚙"];
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

    UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
    lp.minimumPressDuration = 0.45;
    [self.overlayContainer addGestureRecognizer:lp];

    self.panGesture.delegate = self;
    self.pinchGesture.delegate = self;
    self.rotationGesture.delegate = self;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)a shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)b {
    return YES;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldReceiveTouch:(UITouch *)t {
    if (g.view == self.settingsContainerView) {
        return t.view == self.settingsContainerView;
    }
    if (_cropModeEnabled && (g == self.panGesture || g == self.pinchGesture || g == self.rotationGesture)) {
        return NO;
    }
    if (_cropModeEnabled && [self.overlayView isCropHandleView:t.view]) {
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
    self.overlayContainer.layer.shouldRasterize = !perspectiveOn && !_cropModeEnabled;
    self.overlayContainer.layer.rasterizationScale = [UIScreen mainScreen].scale;
}

- (void)handlePan:(UIPanGestureRecognizer *)g {
    if (self.isLocked || _cropModeEnabled) return;
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
    if (self.isLocked || _cropModeEnabled) return;
    if (g.state == UIGestureRecognizerStateChanged) {
        _currentScaleValue = MAX(0.15, MIN(6.0, _currentScaleValue * g.scale));
        [self applyContainerTransform];
        g.scale = 1.0;
    }
    if (g.state == UIGestureRecognizerStateEnded) [self scheduleSave];
}

- (void)handleRotation:(UIRotationGestureRecognizer *)g {
    if (self.isLocked || _cropModeEnabled) return;
    if (g.state == UIGestureRecognizerStateChanged) {
        _currentRotationValue += g.rotation;
        [self applyContainerTransform];
        g.rotation = 0;
    }
    if (g.state == UIGestureRecognizerStateEnded) [self scheduleSave];
}

- (void)handleDoubleTap:(UITapGestureRecognizer *)g {
    if (self.isLocked || _cropModeEnabled) return;
    [self resetTransform];
    [self showToast:@"Konum sıfırlandı"];
}

- (void)handleLongPress:(UILongPressGestureRecognizer *)g {
    if (_cropModeEnabled) return;
    if (g.state != UIGestureRecognizerStateBegan) return;
    [self toggleLock];
    [self showToast:self.isLocked ? @"Kilitlendi — dokunmalar oyuna geçer" : @"Kilit açıldı"];
}

- (void)clampOverlayToScreen {
    if (!self.overlayContainer) return;
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

    if (self.overlayContainer && self.isOverlayVisible && !self.isLocked && !self.overlayContainer.hidden) {
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
    UIEdgeInsets old = _cropInsetsValue;
    self.overlayView.cropInsets = insets;
    insets = self.overlayView.cropInsets;
    CGSize newSize = [self.overlayView croppedSize];

    UIView *view = self.overlayContainer;
    CATransform3D t = view.layer.transform;
    view.layer.transform = CATransform3DIdentity;

    CGPoint keepSuper = CGPointZero;
    if (keep && view.superview) {
        CGPoint local = CGPointMake((insets.left - old.left) * base.width,
                                    (insets.top - old.top) * base.height);
        keepSuper = [view convertPoint:local toView:view.superview];
    }

    view.bounds = CGRectMake(0, 0, newSize.width, newSize.height);

    if (keep && view.superview) {
        CGPoint newTL = [view convertPoint:CGPointZero toView:view.superview];
        CGPoint c = view.center;
        c.x += keepSuper.x - newTL.x;
        c.y += keepSuper.y - newTL.y;
        view.center = c;
        _currentPosition = c;
    }

    view.layer.transform = t;
    _cropInsetsValue = insets;
    [self scheduleSave];
}

- (UIEdgeInsets)cropInsets { return _cropInsetsValue; }

- (void)resetCrop {
    [self applyCropInsets:UIEdgeInsetsZero keepPosition:YES];
}

- (void)overlayView:(OverlayView *)view didChangeCropInsets:(UIEdgeInsets)insets {
    (void)view;
    [self applyCropInsets:insets keepPosition:YES];
}

- (void)beginCropMode {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self beginCropMode]; });
        return;
    }
    if (self.isLocked) {
        [self showToast:@"Önce kilidi açın"];
        return;
    }
    if (self.isSettingsVisible) [self hideSettingsPanel];
    if (!self.isOverlayVisible) [self showOverlay];
    _cropModeEnabled = YES;
    self.overlayView.cropModeEnabled = YES;
    [self applyContainerTransform];
    [self showCropBar];
    [self showToast:@"Tutamaçları sürükleyerek kırpın"];
}

- (void)endCropMode {
    if (!_cropModeEnabled) return;
    _cropModeEnabled = NO;
    self.overlayView.cropModeEnabled = NO;
    [self applyContainerTransform];
    [self hideCropBar];
    [self saveCurrentState];
}

- (BOOL)isCropModeEnabled { return _cropModeEnabled; }

- (void)showCropBar {
    [self.cropBar removeFromSuperview];
    UIView *root = self.overlayWindow.rootViewController.view;
    CGFloat w = MIN(320.0, root.bounds.size.width - 24.0);
    CGFloat h = 48.0;
    UIEdgeInsets inset = self.overlayWindow.safeAreaInsets;
    UIView *bar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, h)];
    bar.center = CGPointMake(CGRectGetMidX(root.bounds), root.bounds.size.height - inset.bottom - 28 - h * 0.5);
    bar.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.82];
    bar.layer.cornerRadius = 14;
    bar.userInteractionEnabled = YES;

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(14, 0, w - 110, h)];
    title.text = @"Kırpma";
    title.textColor = [UIColor whiteColor];
    title.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    [bar addSubview:title];

    UIButton *done = [UIButton buttonWithType:UIButtonTypeSystem];
    done.frame = CGRectMake(w - 96, 8, 82, 32);
    [done setTitle:@"Tamam" forState:UIControlStateNormal];
    [done setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    done.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    done.backgroundColor = [UIColor systemBlueColor];
    done.layer.cornerRadius = 8;
    done.exclusiveTouch = YES;
    [done addTarget:self action:@selector(endCropMode) forControlEvents:UIControlEventTouchUpInside];
    [bar addSubview:done];

    [root addSubview:bar];
    [root bringSubviewToFront:bar];
    self.cropBar = bar;
}

- (void)hideCropBar {
    [self.cropBar removeFromSuperview];
    self.cropBar = nil;
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
    [self endCropMode];
    [self resetCrop];
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

    [self.overlayWindow layoutIfNeeded];
    UIViewController *root = self.overlayWindow.rootViewController;
    if (!root) return;

    self.settingsVC = [[SettingsViewController alloc] init];

    UIView *dim = [[UIView alloc] initWithFrame:root.view.bounds];
    dim.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    dim.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.45];
    dim.alpha = 0;
    dim.userInteractionEnabled = YES;

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(settingsBackgroundTapped:)];
    tap.delegate = self;
    tap.cancelsTouchesInView = NO;
    [dim addGestureRecognizer:tap];
    self.settingsContainerView = dim;

    CGFloat pw = MIN(340.0, CGRectGetWidth(root.view.bounds) - 28.0);
    CGFloat ph = MIN(540.0, CGRectGetHeight(root.view.bounds) - 56.0);
    self.settingsVC.view.frame = CGRectMake(0, 0, pw, ph);
    self.settingsVC.view.center = CGPointMake(CGRectGetMidX(dim.bounds), CGRectGetMidY(dim.bounds));
    self.settingsVC.view.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin |
                                            UIViewAutoresizingFlexibleRightMargin |
                                            UIViewAutoresizingFlexibleTopMargin |
                                            UIViewAutoresizingFlexibleBottomMargin;
    self.settingsVC.view.layer.cornerRadius = 16;
    self.settingsVC.view.clipsToBounds = YES;

    [root addChildViewController:self.settingsVC];
    [dim addSubview:self.settingsVC.view];
    [root.view addSubview:dim];
    [self.settingsVC didMoveToParentViewController:root];

    [root.view bringSubviewToFront:self.menuButton];

    [self.settingsVC.view layoutIfNeeded];

    [UIView animateWithDuration:0.22 animations:^{ dim.alpha = 1.0; }];
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
    box.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.78];
    box.layer.cornerRadius = 12;
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
