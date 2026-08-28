/**
 * ==============================================================================
 * OverlayManager.m
 * ==============================================================================
 * Kritik düzeltme: hitTest:withEvent: artık ayarlar panelini de kontrol ediyor.
 * ==============================================================================
 */

#import "OverlayManager.h"
#import "SettingsViewController.h"

#define OLLog(fmt, ...) NSLog(@"[Overlay] " fmt, ##__VA_ARGS__)

NSString *const kDefaultsOpacity = @"overlay_opacity";
NSString *const kDefaultsPositionX = @"overlay_position_x";
NSString *const kDefaultsPositionY = @"overlay_position_y";
NSString *const kDefaultsScale = @"overlay_scale";
NSString *const kDefaultsRotation = @"overlay_rotation";
NSString *const kDefaultsImageBookmark = @"overlay_image_data";
NSString *const kDefaultsIsLocked = @"overlay_is_locked";
NSString *const kDefaultsOverlayVisible = @"overlay_visible";

// ============================================================================
// Kritik: Doğru hitTest implementasyonu
// ============================================================================
// Sorun: Eski kod sadece overlayContainer ve menü butonunu kontrol ediyordu.
//        Ayarlar paneli (settingsContainerView) hiç kontrol edilmiyordu,
//        bu yüzden paneldeki hiçbir buton çalışmıyordu.
//
// Çözüm: hitTest'te 3 durumu kontrol et:
//   1. Ayarlar paneli açıksa -> panel'e dokunmaları geçir
//   2. Menü butonuna dokunulduysa -> butona geçir
//   3. Overlay container'a dokunulduysa (kilitli değilse) -> container'a geçir
//   4. Diğer -> nil (oyuna geçir)
// ============================================================================

@interface OverlayPassthroughWindow : UIWindow
@end

@implementation OverlayPassthroughWindow

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    OverlayManager *mgr = [OverlayManager sharedManager];

    // Overlay hiç görünür değilse, tüm dokunmaları geçir
    if (!mgr.isOverlayVisible && !mgr.isSettingsVisible) {
        return nil;
    }

    // KRİTİK: Ayarlar paneli açıksa, panel'e dokunmaları geçir
    if (mgr.isSettingsVisible && mgr.settingsContainerView) {
        CGPoint p = [self convertPoint:point toView:mgr.settingsContainerView];
        if ([mgr.settingsContainerView pointInside:p withEvent:event]) {
            return [mgr.settingsContainerView hitTest:p withEvent:event];
        }
    }

    // Menü butonu (her zaman dokunulabilir)
    if (mgr.menuButton) {
        CGPoint p = [self convertPoint:point toView:mgr.menuButton];
        if ([mgr.menuButton pointInside:p withEvent:event]) {
            return [mgr.menuButton hitTest:p withEvent:event];
        }
    }

    // Overlay container (kilitli değilse)
    if (mgr.overlayContainer && !mgr.isLocked) {
        CGPoint p = [self convertPoint:point toView:mgr.overlayContainer];
        if ([mgr.overlayContainer pointInside:p withEvent:event]) {
            return [mgr.overlayContainer hitTest:p withEvent:event];
        }
    }

    // Hiçbir overlay elemanına dokunulmuyor -> oyuna geçir
    return nil;
}

@end

// ============================================================================
// OverlayManager
// ============================================================================

@interface OverlayManager ()

@property (nonatomic, strong, readwrite) UIWindow *overlayWindow;
@property (nonatomic, strong, readwrite) UIView *overlayContainer;
@property (nonatomic, assign, readwrite) BOOL isOverlayVisible;
@property (nonatomic, assign, readwrite) BOOL isLocked;
@property (nonatomic, assign, readwrite) BOOL isSettingsVisible;

@property (nonatomic, strong) UIImageView *overlayImageView;
@property (nonatomic, strong) UIButton *menuButton;
@property (nonatomic, strong) UIView *settingsContainerView;
@property (nonatomic, strong) SettingsViewController *settingsVC;

@property (nonatomic, strong) UIPanGestureRecognizer *panGesture;
@property (nonatomic, strong) UIPinchGestureRecognizer *pinchGesture;
@property (nonatomic, strong) UIRotationGestureRecognizer *rotationGesture;

@property (nonatomic, assign) CGFloat currentOpacity;
@property (nonatomic, assign) CGFloat currentScale;
@property (nonatomic, assign) CGFloat currentRotation;
@property (nonatomic, assign) CGPoint currentPosition;

@property (nonatomic, strong) NSUserDefaults *defaults;
@property (nonatomic, assign) BOOL setupCompleted;

@end

@implementation OverlayManager

#pragma mark - Singleton

+ (instancetype)sharedManager {
    static OverlayManager *instance = nil;
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
        _currentOpacity = 0.5;
        _currentScale = 1.0;
        _currentRotation = 0.0;
        _currentPosition = CGPointZero;
        _isOverlayVisible = NO;
        _isLocked = NO;
        _isSettingsVisible = NO;
        _setupCompleted = NO;
    }
    return self;
}

#pragma mark - Setup

- (void)setup {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self setup]; });
        return;
    }
    if (_setupCompleted) {
        OLLog(@"Setup zaten tamamlandı.");
        return;
    }

    OLLog(@"Setup başlıyor...");

    [self loadSavedState];

    UIWindow *keyWindow = [self findActiveWindow];
    if (!keyWindow) {
        OLLog(@"Pencere bulunamadı, 2sn sonra tekrar...");
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ [self setup]; });
        return;
    }
    OLLog(@"Window Found: %@", keyWindow);

    [self createOverlayWindow];
    [self createOverlayContainer];
    [self createMenuButton];
    [self setupGestures];
    [self loadSavedImage];

    _setupCompleted = YES;
    OLLog(@"Overlay Created!");

    [self showOverlay];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ [self showTestAlert]; });
}

#pragma mark - Pencere Bulma

- (UIWindow *)findActiveWindow {
    // Yöntem 1: UIWindowScene keyWindow (iOS 13+)
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]] &&
                scene.activationState == UISceneActivationStateForegroundActive) {
                for (UIWindow *w in ((UIWindowScene *)scene).windows) {
                    if (w.isKeyWindow) return w;
                }
            }
        }
    }

    // Yöntem 2: UIApplication keyWindow
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    UIWindow *w = [UIApplication sharedApplication].keyWindow;
    if (w) return w;
#pragma clang diagnostic pop

    // Yöntem 3: İlk visible window
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                for (UIWindow *w2 in ((UIWindowScene *)scene).windows) {
                    if (!w2.isHidden && w2.alpha > 0) return w2;
                }
            }
        }
    }

    // Yöntem 4: AppDelegate window
    id delegate = [UIApplication sharedApplication].delegate;
    if ([delegate respondsToSelector:@selector(window)]) {
        w = [delegate performSelector:@selector(window)];
        if (w) return w;
    }

    return nil;
}

#pragma mark - Overlay Penceresi

- (void)createOverlayWindow {
    CGRect bounds = [UIScreen mainScreen].bounds;

    self.overlayWindow = [[OverlayPassthroughWindow alloc] initWithFrame:bounds];
    self.overlayWindow.windowLevel = UIWindowLevelStatusBar + 1000;
    self.overlayWindow.backgroundColor = [UIColor clearColor];
    self.overlayWindow.userInteractionEnabled = YES;
    self.overlayWindow.hidden = NO;

    [self.overlayWindow makeKeyAndVisible];

    // Ana pencereyi tekrar key yap
    UIWindow *keyWindow = [self findActiveWindow];
    if (keyWindow && keyWindow != self.overlayWindow) {
        [keyWindow makeKeyWindow];
    }

    OLLog(@"Overlay penceresi oluşturuldu.");
}

#pragma mark - Overlay Container

- (void)createOverlayContainer {
    CGRect bounds = [UIScreen mainScreen].bounds;
    CGFloat w = bounds.size.width * 0.6;
    CGFloat h = bounds.size.height * 0.4;

    self.overlayContainer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, h)];
    self.overlayContainer.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.3];
    self.overlayContainer.clipsToBounds = YES;
    self.overlayContainer.layer.cornerRadius = 8.0;
    self.overlayContainer.layer.borderWidth = 2.0;
    self.overlayContainer.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.5].CGColor;

    self.overlayImageView = [[UIImageView alloc] initWithFrame:self.overlayContainer.bounds];
    self.overlayImageView.contentMode = UIViewContentModeScaleAspectFit;
    self.overlayImageView.backgroundColor = [UIColor clearColor];
    self.overlayImageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.overlayContainer addSubview:self.overlayImageView];

    if (_currentPosition.x != 0 || _currentPosition.y != 0) {
        self.overlayContainer.center = _currentPosition;
    } else {
        self.overlayContainer.center = CGPointMake(bounds.size.width / 2, bounds.size.height / 2);
    }

    self.overlayContainer.transform = CGAffineTransformConcat(
        CGAffineTransformMakeScale(_currentScale, _currentScale),
        CGAffineTransformMakeRotation(_currentRotation)
    );
    self.overlayContainer.alpha = _currentOpacity;
    self.overlayContainer.hidden = YES;

    [self.overlayWindow addSubview:self.overlayContainer];
    OLLog(@"Overlay container oluşturuldu.");
}

#pragma mark - Mini Menü

- (void)createMenuButton {
    CGFloat size = 50;
    CGFloat margin = 12;

    self.menuButton = [[UIButton alloc] initWithFrame:CGRectMake(
        [UIScreen mainScreen].bounds.size.width - size - margin, 60, size, size)];
    self.menuButton.tag = 9999;

    UIBlurEffect *blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark];
    UIVisualEffectView *blurView = [[UIVisualEffectView alloc] initWithEffect:blur];
    blurView.frame = self.menuButton.bounds;
    blurView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    blurView.layer.cornerRadius = size / 2;
    blurView.clipsToBounds = YES;
    [self.menuButton insertSubview:blurView atIndex:0];

    [self.menuButton setTitle:@"⚙️" forState:UIControlStateNormal];
    self.menuButton.titleLabel.font = [UIFont systemFontOfSize:24];

    self.menuButton.layer.shadowColor = [UIColor blackColor].CGColor;
    self.menuButton.layer.shadowOffset = CGSizeMake(0, 2);
    self.menuButton.layer.shadowRadius = 6;
    self.menuButton.layer.shadowOpacity = 0.6;

    [self.menuButton addTarget:self action:@selector(menuTapped) forControlEvents:UIControlEventTouchUpInside];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(menuDragged:)];
    [self.menuButton addGestureRecognizer:pan];

    [self.overlayWindow addSubview:self.menuButton];
    OLLog(@"Menü butonu oluşturuldu.");
}

#pragma mark - Gesture'lar

- (void)setupGestures {
    self.panGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    self.panGesture.maximumNumberOfTouches = 1;
    [self.overlayContainer addGestureRecognizer:self.panGesture];

    self.pinchGesture = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(handlePinch:)];
    [self.overlayContainer addGestureRecognizer:self.pinchGesture];

    self.rotationGesture = [[UIRotationGestureRecognizer alloc] initWithTarget:self action:@selector(handleRotation:)];
    [self.overlayContainer addGestureRecognizer:self.rotationGesture];

    self.panGesture.delegate = (id<UIGestureRecognizerDelegate>)self;
    self.pinchGesture.delegate = (id<UIGestureRecognizerDelegate>)self;
    self.rotationGesture.delegate = (id<UIGestureRecognizerDelegate>)self;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)a shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)b {
    return YES;
}

#pragma mark - Gesture İşleyicileri

- (void)handlePan:(UIPanGestureRecognizer *)g {
    if (self.isLocked) return;
    UIView *v = g.view;
    CGPoint t = [g translationInView:v.superview];
    CGPoint c = CGPointMake(v.center.x + t.x, v.center.y + t.y);
    CGSize s = [UIScreen mainScreen].bounds.size;
    CGFloat hw = v.bounds.size.width * _currentScale / 2;
    CGFloat hh = v.bounds.size.height * _currentScale / 2;
    c.x = MAX(hw, MIN(s.width - hw, c.x));
    c.y = MAX(hh, MIN(s.height - hh, c.y));
    v.center = c;
    [g setTranslation:CGPointZero inView:v.superview];
    _currentPosition = c;
}

- (void)handlePinch:(UIPinchGestureRecognizer *)g {
    if (self.isLocked) return;
    if (g.state == UIGestureRecognizerStateChanged) {
        _currentScale = MAX(0.2, MIN(5.0, _currentScale * g.scale));
        self.overlayContainer.transform = CGAffineTransformConcat(
            CGAffineTransformMakeScale(_currentScale, _currentScale),
            CGAffineTransformMakeRotation(_currentRotation));
        g.scale = 1.0;
    }
    if (g.state == UIGestureRecognizerStateEnded) [self saveCurrentState];
}

- (void)handleRotation:(UIRotationGestureRecognizer *)g {
    if (self.isLocked) return;
    if (g.state == UIGestureRecognizerStateChanged) {
        _currentRotation += g.rotation;
        self.overlayContainer.transform = CGAffineTransformConcat(
            CGAffineTransformMakeScale(_currentScale, _currentScale),
            CGAffineTransformMakeRotation(_currentRotation));
        g.rotation = 0;
    }
    if (g.state == UIGestureRecognizerStateEnded) [self saveCurrentState];
}

#pragma mark - Menü

- (void)menuTapped {
    if (self.isSettingsVisible) {
        [self hideSettingsPanel];
    } else {
        [self showSettingsPanel];
    }
}

- (void)menuDragged:(UIPanGestureRecognizer *)g {
    CGPoint t = [g translationInView:self.overlayWindow];
    CGPoint c = CGPointMake(g.view.center.x + t.x, g.view.center.y + t.y);
    CGSize s = [UIScreen mainScreen].bounds.size;
    c.x = MAX(25, MIN(s.width - 25, c.x));
    c.y = MAX(25, MIN(s.height - 25, c.y));
    g.view.center = c;
    [g setTranslation:CGPointZero inView:self.overlayWindow];
}

#pragma mark - Görünürlük

- (void)showOverlay {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self showOverlay]; });
        return;
    }
    self.overlayContainer.hidden = NO;
    self.overlayContainer.alpha = 0;
    [UIView animateWithDuration:0.3 animations:^{
        self.overlayContainer.alpha = self.currentOpacity;
    }];
    self.isOverlayVisible = YES;
    [_defaults setBool:YES forKey:kDefaultsOverlayVisible];
    OLLog(@"Overlay gösterildi.");
}

- (void)hideOverlay {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self hideOverlay]; });
        return;
    }
    [UIView animateWithDuration:0.3 animations:^{
        self.overlayContainer.alpha = 0;
    } completion:^(BOOL f) {
        self.overlayContainer.hidden = YES;
    }];
    self.isOverlayVisible = NO;
    [_defaults setBool:NO forKey:kDefaultsOverlayVisible];
    OLLog(@"Overlay gizlendi.");
}

- (void)toggleOverlay {
    self.isOverlayVisible ? [self hideOverlay] : [self showOverlay];
}

#pragma mark - Görsel

- (void)setOverlayImage:(UIImage *)image {
    if (!image) return;
    self.overlayImageView.image = image;
    NSData *data = UIImagePNGRepresentation(image);
    if (data) {
        [_defaults setObject:data forKey:kDefaultsImageBookmark];
        [_defaults synchronize];
        OLLog(@"Görsel kaydedildi (%lu bytes).", (unsigned long)data.length);
    }
}

- (void)loadSavedImage {
    NSData *data = [_defaults objectForKey:kDefaultsImageBookmark];
    if (data) {
        UIImage *img = [UIImage imageWithData:data];
        if (img) {
            self.overlayImageView.image = img;
            OLLog(@"Görsel yüklendi.");
        }
    }
}

#pragma mark - Opacity

- (void)setOpacity:(CGFloat)opacity {
    opacity = MAX(0, MIN(1, opacity));
    _currentOpacity = opacity;
    if (self.isOverlayVisible) self.overlayContainer.alpha = opacity;
    [_defaults setDouble:opacity forKey:kDefaultsOpacity];
    [_defaults synchronize];
}

- (CGFloat)currentOpacity { return _currentOpacity; }

#pragma mark - Kilit

- (void)setLocked:(BOOL)locked {
    _isLocked = locked;
    if (locked) {
        self.overlayContainer.layer.borderColor = [UIColor systemRedColor].CGColor;
        self.overlayContainer.layer.borderWidth = 3;
    } else {
        self.overlayContainer.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.5].CGColor;
        self.overlayContainer.layer.borderWidth = 2;
    }
    [_defaults setBool:locked forKey:kDefaultsIsLocked];
    [_defaults synchronize];
}

- (void)toggleLock { [self setLocked:!self.isLocked]; }

#pragma mark - Durum

- (void)saveCurrentState {
    [_defaults setDouble:_currentOpacity forKey:kDefaultsOpacity];
    [_defaults setDouble:_currentPosition.x forKey:kDefaultsPositionX];
    [_defaults setDouble:_currentPosition.y forKey:kDefaultsPositionY];
    [_defaults setDouble:_currentScale forKey:kDefaultsScale];
    [_defaults setDouble:_currentRotation forKey:kDefaultsRotation];
    [_defaults setBool:_isLocked forKey:kDefaultsIsLocked];
    [_defaults synchronize];
}

- (void)loadSavedState {
    _currentOpacity = [_defaults doubleForKey:kDefaultsOpacity];
    if (_currentOpacity == 0) _currentOpacity = 0.5;
    _currentPosition = CGPointMake([_defaults doubleForKey:kDefaultsPositionX],
                                   [_defaults doubleForKey:kDefaultsPositionY]);
    _currentScale = [_defaults doubleForKey:kDefaultsScale];
    if (_currentScale == 0) _currentScale = 1.0;
    _currentRotation = [_defaults doubleForKey:kDefaultsRotation];
    _isLocked = [_defaults boolForKey:kDefaultsIsLocked];
}

#pragma mark - Ayarlar Paneli

- (void)showSettingsPanel {
    if (self.isSettingsVisible) return;
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self showSettingsPanel]; });
        return;
    }

    self.settingsVC = [[SettingsViewController alloc] init];

    // Container view - TÜM EKRANI kaplar (arka plan dokunma yakalama için)
    self.settingsContainerView = [[UIView alloc] initWithFrame:self.overlayWindow.bounds];
    self.settingsContainerView.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.4];
    self.settingsContainerView.alpha = 0;
    self.settingsContainerView.userInteractionEnabled = YES;

    // Panel view - Ortalanmış ayarlar paneli
    CGFloat pw = MIN(320, self.overlayWindow.bounds.size.width - 40);
    CGFloat ph = 440;
    CGFloat px = (self.overlayWindow.bounds.size.width - pw) / 2;
    CGFloat py = (self.overlayWindow.bounds.size.height - ph) / 2;

    // SettingsViewController'ın view'ını ekle
    [self addChildViewController:self.settingsVC];
    self.settingsVC.view.frame = CGRectMake(px, py, pw, ph);
    [self.settingsContainerView addSubview:self.settingsVC.view];
    [self.settingsVC didMoveToParentViewController:nil];

    [self.overlayWindow addSubview:self.settingsContainerView];

    [UIView animateWithDuration:0.3 animations:^{
        self.settingsContainerView.alpha = 1.0;
    }];

    self.isSettingsVisible = YES;
    OLLog(@"Ayarlar paneli gösterildi.");
}

- (void)hideSettingsPanel {
    if (!self.isSettingsVisible) return;
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self hideSettingsPanel]; });
        return;
    }

    [UIView animateWithDuration:0.3 animations:^{
        self.settingsContainerView.alpha = 0;
    } completion:^(BOOL f) {
        [self.settingsVC willMoveToParentViewController:nil];
        [self.settingsVC.view removeFromSuperview];
        [self.settingsVC removeFromParentViewController];
        [self.settingsContainerView removeFromSuperview];
        self.settingsContainerView = nil;
        self.settingsVC = nil;
    }];

    self.isSettingsVisible = NO;
    [self saveCurrentState];
    OLLog(@"Ayarlar paneli gizlendi.");
}

#pragma mark - Test Alert

- (void)showTestAlert {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self showTestAlert]; });
        return;
    }

    UIWindow *w = [self findActiveWindow];
    if (!w) { OLLog(@"Test alert: pencere yok!"); return; }

    UIViewController *vc = w.rootViewController;
    if (!vc) { OLLog(@"Test alert: rootVC yok!"); return; }

    while (vc.presentedViewController) vc = vc.presentedViewController;

    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"✅ Overlay Aktif"
        message:@"Tweak yüklendi!\n\n⚙️ butonuna basın."
        preferredStyle:UIAlertControllerStyleAlert];

    [vc presentViewController:alert animated:YES completion:^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [alert dismissViewControllerAnimated:YES completion:nil];
        });
    }];

    OLLog(@"Test alert gösterildi.");
}

@end
