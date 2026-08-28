/**
 * SettingsViewController.m
 *
 * Built in viewDidLayoutSubviews so the panel has a real width.
 * PHPicker (iOS 14+) — no photo-library permission string required.
 */

#import "SettingsViewController.h"
#import "OverlayManager.h"
#import "OverlayCommon.h"
#import <PhotosUI/PhotosUI.h>
#import <math.h>

@interface SettingsViewController () <PHPickerViewControllerDelegate, UIGestureRecognizerDelegate>
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIView *contentView;
@property (nonatomic, strong) UIVisualEffectView *blurView;
@property (nonatomic, strong) UIButton *imageSelectButton;
@property (nonatomic, strong) UIButton *pasteButton;
@property (nonatomic, strong) UIImageView *imagePreview;
@property (nonatomic, strong) UISlider *opacitySlider;
@property (nonatomic, strong) UILabel *opacityValueLabel;
@property (nonatomic, strong) UISlider *scaleSlider;
@property (nonatomic, strong) UILabel *scaleValueLabel;
@property (nonatomic, strong) UILabel *lockLabel;
@property (nonatomic, strong) UISwitch *lockSwitch;
@property (nonatomic, strong) UISegmentedControl *modeControl;
@property (nonatomic, strong) UISegmentedControl *sizeModeControl;
@property (nonatomic, strong) UILabel *sizeInfoLabel;
@property (nonatomic, strong) UIButton *customSizeButton;
@property (nonatomic, strong) UISlider *rotationSlider;
@property (nonatomic, strong) UILabel *rotationValueLabel;
@property (nonatomic, strong) UISwitch *borderSwitch;
@property (nonatomic, strong) UISwitch *gridSwitch;
@property (nonatomic, strong) UIButton *toggleOverlayButton;
@property (nonatomic, strong) UIButton *resetButton;
@property (nonatomic, assign) BOOL uiBuilt;
@end

@implementation SettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.userInteractionEnabled = YES;
    self.view.backgroundColor = [UIColor clearColor];

    UIBlurEffect *blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark];
    self.blurView = [[UIVisualEffectView alloc] initWithEffect:blur];
    self.blurView.frame = self.view.bounds;
    self.blurView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.blurView.layer.cornerRadius = 16;
    self.blurView.clipsToBounds = YES;
    self.blurView.userInteractionEnabled = YES;
    [self.view addSubview:self.blurView];

    self.scrollView = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    self.scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.scrollView.showsVerticalScrollIndicator = YES;
    self.scrollView.alwaysBounceVertical = YES;
    self.scrollView.userInteractionEnabled = YES;
    self.scrollView.delaysContentTouches = NO;
    [self.blurView.contentView addSubview:self.scrollView];

    self.contentView = [[UIView alloc] initWithFrame:self.view.bounds];
    self.contentView.userInteractionEnabled = YES;
    [self.scrollView addSubview:self.contentView];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    if (!self.uiBuilt && self.view.bounds.size.width >= 32) {
        self.uiBuilt = YES;
        [self buildUI];
        [self loadState];
    }
    CGFloat h = CGRectGetMaxY(self.resetButton.frame) + 24;
    if (h < 80) h = self.view.bounds.size.height;
    self.scrollView.frame = self.view.bounds;
    self.scrollView.contentSize = CGSizeMake(self.view.bounds.size.width, h);
    self.contentView.frame = CGRectMake(0, 0, self.view.bounds.size.width, h);
}

#pragma mark - UI

- (void)buildUI {
    CGFloat p = 16;
    CGFloat sw = self.view.bounds.size.width - p * 2;
    CGFloat y = 0;

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(p, 14, sw - 48, 28)];
    title.text = @"Overlay Ayarları";
    title.font = [UIFont systemFontOfSize:18 weight:UIFontWeightSemibold];
    title.textColor = [UIColor whiteColor];
    [self.contentView addSubview:title];

    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    closeBtn.frame = CGRectMake(self.view.bounds.size.width - 44 - p, 12, 44, 32);
    [closeBtn setTitle:@"✕" forState:UIControlStateNormal];
    closeBtn.titleLabel.font = [UIFont systemFontOfSize:20];
    [closeBtn setTitleColor:[UIColor lightGrayColor] forState:UIControlStateNormal];
    closeBtn.exclusiveTouch = YES;
    [closeBtn addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:closeBtn];

    y = 52;
    [self addSeparatorAtY:y];
    y += 10;

    [self.contentView addSubview:[self sectionLabel:@"GÖRSEL" y:y]];
    y += 24;

    CGFloat ps = 64;
    self.imagePreview = [[UIImageView alloc] initWithFrame:CGRectMake(p, y, ps, ps)];
    self.imagePreview.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.1];
    self.imagePreview.layer.cornerRadius = 8;
    self.imagePreview.clipsToBounds = YES;
    self.imagePreview.contentMode = UIViewContentModeScaleAspectFit;
    [self.contentView addSubview:self.imagePreview];

    self.imageSelectButton = [self actionButton:@"📷  Galeriden Seç"
                                          frame:CGRectMake(p + ps + 10, y, sw - ps - 10, 30)
                                          color:[[UIColor whiteColor] colorWithAlphaComponent:0.15]
                                     titleColor:[UIColor whiteColor]];
    [self.imageSelectButton addTarget:self action:@selector(selectImageTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:self.imageSelectButton];

    self.pasteButton = [self actionButton:@"📋  Panodan Yapıştır"
                                    frame:CGRectMake(p + ps + 10, y + 34, sw - ps - 10, 30)
                                    color:[[UIColor whiteColor] colorWithAlphaComponent:0.10]
                               titleColor:[UIColor whiteColor]];
    [self.pasteButton addTarget:self action:@selector(pasteTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:self.pasteButton];

    y += 80;
    [self addSeparatorAtY:y];
    y += 10;

    [self.contentView addSubview:[self sectionLabel:@"BOYUT" y:y]];
    y += 26;

    self.sizeModeControl = [[UISegmentedControl alloc] initWithItems:@[@"Fotoğrafa göre", @"Özel"]];
    self.sizeModeControl.frame = CGRectMake(p, y, sw, 32);
    self.sizeModeControl.selectedSegmentIndex = 0;
    if (@available(iOS 13.0, *)) {
        self.sizeModeControl.selectedSegmentTintColor = [UIColor systemBlueColor];
        [self.sizeModeControl setTitleTextAttributes:@{NSForegroundColorAttributeName: [UIColor whiteColor]}
                                            forState:UIControlStateNormal];
    }
    [self.sizeModeControl addTarget:self action:@selector(sizeModeChanged:) forControlEvents:UIControlEventValueChanged];
    [self.contentView addSubview:self.sizeModeControl];

    y += 40;
    self.sizeInfoLabel = [[UILabel alloc] initWithFrame:CGRectMake(p, y, sw, 36)];
    self.sizeInfoLabel.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightRegular];
    self.sizeInfoLabel.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.7];
    self.sizeInfoLabel.numberOfLines = 2;
    self.sizeInfoLabel.text = @"Görsel seçilmedi";
    [self.contentView addSubview:self.sizeInfoLabel];

    y += 40;
    self.customSizeButton = [self actionButton:@"📐  Genişlik × Yükseklik gir"
                                         frame:CGRectMake(p, y, sw, 40)
                                         color:[[UIColor whiteColor] colorWithAlphaComponent:0.12]
                                    titleColor:[UIColor whiteColor]];
    [self.customSizeButton addTarget:self action:@selector(customSizeTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:self.customSizeButton];

    y += 48;
    CGFloat pw = (sw - 16) / 5.0;
    NSArray *presets = @[@"1:1", @"9:16", @"16:9", @"4:3", @"3:4"];
    for (NSInteger i = 0; i < 5; i++) {
        UIButton *b = [self actionButton:presets[i]
                                  frame:CGRectMake(p + i * (pw + 4), y, pw, 32)
                                  color:[[UIColor whiteColor] colorWithAlphaComponent:0.10]
                             titleColor:[UIColor whiteColor]];
        b.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
        b.tag = 500 + i;
        [b addTarget:self action:@selector(presetTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self.contentView addSubview:b];
    }

    y += 44;
    [self addSeparatorAtY:y];
    y += 10;

    [self.contentView addSubview:[self sectionLabel:@"ŞEFFAFLIK" y:y]];
    y += 26;

    self.opacitySlider = [[UISlider alloc] initWithFrame:CGRectMake(p, y, sw - 55, 30)];
    self.opacitySlider.minimumValue = 0.05f;
    self.opacitySlider.maximumValue = 1.0f;
    self.opacitySlider.value = 0.5f;
    self.opacitySlider.minimumTrackTintColor = [UIColor systemBlueColor];
    self.opacitySlider.maximumTrackTintColor = [[UIColor whiteColor] colorWithAlphaComponent:0.2];
    [self.opacitySlider addTarget:self action:@selector(opacityChanged:) forControlEvents:UIControlEventValueChanged];
    [self.contentView addSubview:self.opacitySlider];

    self.opacityValueLabel = [[UILabel alloc] initWithFrame:CGRectMake(self.view.bounds.size.width - p - 50, y, 50, 30)];
    self.opacityValueLabel.text = @"50%";
    self.opacityValueLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    self.opacityValueLabel.textColor = [UIColor whiteColor];
    self.opacityValueLabel.textAlignment = NSTextAlignmentRight;
    [self.contentView addSubview:self.opacityValueLabel];

    y += 40;
    [self.contentView addSubview:[self sectionLabel:@"ÖLÇEK" y:y]];
    y += 26;

    self.scaleSlider = [[UISlider alloc] initWithFrame:CGRectMake(p, y, sw - 55, 30)];
    self.scaleSlider.minimumValue = 0.2f;
    self.scaleSlider.maximumValue = 4.0f;
    self.scaleSlider.value = 1.0f;
    self.scaleSlider.minimumTrackTintColor = [UIColor systemTealColor];
    self.scaleSlider.maximumTrackTintColor = [[UIColor whiteColor] colorWithAlphaComponent:0.2];
    [self.scaleSlider addTarget:self action:@selector(scaleChanged:) forControlEvents:UIControlEventValueChanged];
    [self.contentView addSubview:self.scaleSlider];

    self.scaleValueLabel = [[UILabel alloc] initWithFrame:CGRectMake(self.view.bounds.size.width - p - 50, y, 50, 30)];
    self.scaleValueLabel.text = @"1.0×";
    self.scaleValueLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    self.scaleValueLabel.textColor = [UIColor whiteColor];
    self.scaleValueLabel.textAlignment = NSTextAlignmentRight;
    [self.contentView addSubview:self.scaleValueLabel];

    y += 40;
    [self.contentView addSubview:[self sectionLabel:@"DÖNDÜRME" y:y]];
    y += 26;

    self.rotationSlider = [[UISlider alloc] initWithFrame:CGRectMake(p, y, sw - 55, 30)];
    self.rotationSlider.minimumValue = -180.0f;
    self.rotationSlider.maximumValue = 180.0f;
    self.rotationSlider.value = 0;
    self.rotationSlider.minimumTrackTintColor = [UIColor systemOrangeColor];
    self.rotationSlider.maximumTrackTintColor = [[UIColor whiteColor] colorWithAlphaComponent:0.2];
    [self.rotationSlider addTarget:self action:@selector(rotationChanged:) forControlEvents:UIControlEventValueChanged];
    [self.contentView addSubview:self.rotationSlider];

    self.rotationValueLabel = [[UILabel alloc] initWithFrame:CGRectMake(self.view.bounds.size.width - p - 50, y, 50, 30)];
    self.rotationValueLabel.text = @"0°";
    self.rotationValueLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    self.rotationValueLabel.textColor = [UIColor whiteColor];
    self.rotationValueLabel.textAlignment = NSTextAlignmentRight;
    [self.contentView addSubview:self.rotationValueLabel];

    y += 36;
    UIButton *rotL = [self actionButton:@"↺  -90°"
                                  frame:CGRectMake(p, y, (sw - 8) / 2, 36)
                                  color:[[UIColor whiteColor] colorWithAlphaComponent:0.12]
                             titleColor:[UIColor whiteColor]];
    [rotL addTarget:self action:@selector(rotateLeftTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:rotL];
    UIButton *rotR = [self actionButton:@"+90°  ↻"
                                  frame:CGRectMake(p + (sw - 8) / 2 + 8, y, (sw - 8) / 2, 36)
                                  color:[[UIColor whiteColor] colorWithAlphaComponent:0.12]
                             titleColor:[UIColor whiteColor]];
    [rotR addTarget:self action:@selector(rotateRightTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:rotR];

    y += 48;
    [self.contentView addSubview:[self sectionLabel:@"SIĞDIRMA" y:y]];
    y += 26;

    self.modeControl = [[UISegmentedControl alloc] initWithItems:@[@"Sığdır", @"Doldur", @"Ger"]];
    self.modeControl.frame = CGRectMake(p, y, sw, 32);
    self.modeControl.selectedSegmentIndex = 0;
    if (@available(iOS 13.0, *)) {
        self.modeControl.selectedSegmentTintColor = [UIColor systemBlueColor];
        [self.modeControl setTitleTextAttributes:@{NSForegroundColorAttributeName: [UIColor whiteColor]}
                                        forState:UIControlStateNormal];
    }
    [self.modeControl addTarget:self action:@selector(modeChanged:) forControlEvents:UIControlEventValueChanged];
    [self.contentView addSubview:self.modeControl];

    y += 48;
    [self addSeparatorAtY:y];
    y += 10;

    [self.contentView addSubview:[self sectionLabel:@"KİLİT" y:y]];
    y += 26;

    UIView *lockRow = [[UIView alloc] initWithFrame:CGRectMake(p, y, sw, 44)];
    lockRow.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.05];
    lockRow.layer.cornerRadius = 8;
    lockRow.userInteractionEnabled = YES;
    [self.contentView addSubview:lockRow];

    self.lockLabel = [[UILabel alloc] initWithFrame:CGRectMake(12, 0, sw - 70, 44)];
    self.lockLabel.text = @"🔒  Overlay Kilitle";
    self.lockLabel.font = [UIFont systemFontOfSize:15];
    self.lockLabel.textColor = [UIColor whiteColor];
    [lockRow addSubview:self.lockLabel];

    self.lockSwitch = [[UISwitch alloc] initWithFrame:CGRectMake(sw - 59, 7, 0, 0)];
    self.lockSwitch.onTintColor = [UIColor systemBlueColor];
    [self.lockSwitch addTarget:self action:@selector(lockChanged:) forControlEvents:UIControlEventValueChanged];
    [lockRow addSubview:self.lockSwitch];

    y += 52;
    UILabel *info = [[UILabel alloc] initWithFrame:CGRectMake(p, y, sw, 32)];
    info.text = @"Kilitliyken overlay hareket etmez, dokunmalar oyuna geçer. Çift dokunuş konumu sıfırlar.";
    info.font = [UIFont systemFontOfSize:11];
    info.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.45];
    info.numberOfLines = 2;
    [self.contentView addSubview:info];

    y += 40;
    [self addSeparatorAtY:y];
    y += 12;

    [self.contentView addSubview:[self sectionLabel:@"ÇEVİR" y:y]];
    y += 26;

    UIButton *flipH = [self actionButton:@"↔  Yatay"
                                   frame:CGRectMake(p, y, (sw - 8) / 2, 40)
                                   color:[[UIColor whiteColor] colorWithAlphaComponent:0.12]
                              titleColor:[UIColor whiteColor]];
    [flipH addTarget:self action:@selector(flipHTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:flipH];

    UIButton *flipV = [self actionButton:@"↕  Dikey"
                                   frame:CGRectMake(p + (sw - 8) / 2 + 8, y, (sw - 8) / 2, 40)
                                   color:[[UIColor whiteColor] colorWithAlphaComponent:0.12]
                              titleColor:[UIColor whiteColor]];
    [flipV addTarget:self action:@selector(flipVTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:flipV];

    y += 52;
    [self addSeparatorAtY:y];
    y += 10;

    [self.contentView addSubview:[self sectionLabel:@"GÖRÜNÜM" y:y]];
    y += 26;

    UIView *borderRow = [[UIView alloc] initWithFrame:CGRectMake(p, y, sw, 44)];
    borderRow.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.05];
    borderRow.layer.cornerRadius = 8;
    [self.contentView addSubview:borderRow];
    UILabel *borderLbl = [[UILabel alloc] initWithFrame:CGRectMake(12, 0, sw - 70, 44)];
    borderLbl.text = @"Kenarlık";
    borderLbl.font = [UIFont systemFontOfSize:15];
    borderLbl.textColor = [UIColor whiteColor];
    [borderRow addSubview:borderLbl];
    self.borderSwitch = [[UISwitch alloc] initWithFrame:CGRectMake(sw - 59, 7, 0, 0)];
    self.borderSwitch.onTintColor = [UIColor systemBlueColor];
    [self.borderSwitch addTarget:self action:@selector(borderChanged:) forControlEvents:UIControlEventValueChanged];
    [borderRow addSubview:self.borderSwitch];

    y += 52;
    UIView *gridRow = [[UIView alloc] initWithFrame:CGRectMake(p, y, sw, 44)];
    gridRow.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.05];
    gridRow.layer.cornerRadius = 8;
    [self.contentView addSubview:gridRow];
    UILabel *gridLbl = [[UILabel alloc] initWithFrame:CGRectMake(12, 0, sw - 70, 44)];
    gridLbl.text = @"Hizalama ızgarası";
    gridLbl.font = [UIFont systemFontOfSize:15];
    gridLbl.textColor = [UIColor whiteColor];
    [gridRow addSubview:gridLbl];
    self.gridSwitch = [[UISwitch alloc] initWithFrame:CGRectMake(sw - 59, 7, 0, 0)];
    self.gridSwitch.onTintColor = [UIColor systemBlueColor];
    [self.gridSwitch addTarget:self action:@selector(gridChanged:) forControlEvents:UIControlEventValueChanged];
    [gridRow addSubview:self.gridSwitch];

    y += 56;
    [self.contentView addSubview:[self sectionLabel:@"KONUM (1 pt / 10 pt)" y:y]];
    y += 26;

    CGFloat nw = (sw - 16) / 3.0;
    NSArray *nudgeTitles = @[@"←10", @"↑10", @"→10", @"←1", @"↓10", @"→1"];
    NSArray *nudgeTags = @[@701, @703, @702, @711, @704, @712];
    for (NSInteger i = 0; i < 6; i++) {
        NSInteger row = i / 3;
        NSInteger col = i % 3;
        UIButton *b = [self actionButton:nudgeTitles[i]
                                  frame:CGRectMake(p + col * (nw + 8), y + row * 40, nw, 36)
                                  color:[[UIColor whiteColor] colorWithAlphaComponent:0.10]
                             titleColor:[UIColor whiteColor]];
        b.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
        b.tag = [nudgeTags[i] integerValue];
        [b addTarget:self action:@selector(nudgeTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self.contentView addSubview:b];
    }

    y += 88;
    [self.contentView addSubview:[self sectionLabel:@"YAPIŞTIR" y:y]];
    y += 26;
    NSArray *snapTitles = @[@"Orta", @"Sol", @"Sağ", @"Üst", @"Alt"];
    CGFloat sw5 = (sw - 16) / 5.0;
    for (NSInteger i = 0; i < 5; i++) {
        UIButton *b = [self actionButton:snapTitles[i]
                                  frame:CGRectMake(p + i * (sw5 + 4), y, sw5, 32)
                                  color:[[UIColor whiteColor] colorWithAlphaComponent:0.10]
                             titleColor:[UIColor whiteColor]];
        b.titleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
        b.tag = 800 + i;
        [b addTarget:self action:@selector(snapTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self.contentView addSubview:b];
    }

    y += 44;
    [self addSeparatorAtY:y];
    y += 16;

    self.toggleOverlayButton = [self actionButton:@"👁  Overlay Göster / Gizle"
                                            frame:CGRectMake(p, y, sw, 44)
                                            color:[UIColor systemBlueColor]
                                       titleColor:[UIColor whiteColor]];
    [self.toggleOverlayButton addTarget:self action:@selector(toggleOvert:0.14]
                               titleColor:[UIColor systemRedColor]];
    [self.resetButton addTarget:self action:@selector(resetTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:self.resetButton];
}

- (UIButton *)actionButton:(NSString *)title frame:(CGRect)frame color:(UIColor *)bg titleColor:(UIColor *)tc {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.frame = frame;
    [b setTitle:title forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    [b setTitleColor:tc forState:UIControlStateNormal];
    b.backgroundColor = bg;
    b.layer.cornerRadius = 8;
    b.exclusiveTouch = YES;
    return b;
}

- (UILabel *)sectionLabel:(NSString *)text y:(CGFloat)y {
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(16, y, self.view.bounds.size.width - 32, 20)];
    l.text = text;
    l.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    l.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.55];
    return l;
}

- (void)addSeparatorAtY:(CGFloat)y {
    UIView *sep = [[UIView alloc] initWithFrame:CGRectMake(16, y, self.view.bounds.size.width - 32, 0.5)];
    sep.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.14];
    sep.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.contentView addSubview:sep];
}

#pragma mark - State

- (void)loadState {
    OverlayManager *mgr = [OverlayManager sharedManager];
    self.opacitySlider.value = (float)[mgr currentOpacity];
    self.opacityValueLabel.text = [NSString stringWithFormat:@"%.0f%%", [mgr currentOpacity] * 100.0];
    self.scaleSlider.value = (float)[mgr currentScale];
    self.scaleValueLabel.text = [NSString stringWithFormat:@"%.1f×", [mgr currentScale]];
    self.lockSwitch.on = mgr.isLocked;
    self.lockLabel.text = mgr.isLocked ? @"🔓  Overlay Kilidini Aç" : @"🔒  Overlay Kilitle";
    self.modeControl.selectedSegmentIndex = [mgr contentModeIndex];
    self.imagePreview.image = [mgr currentImage];
    self.sizeModeControl.selectedSegmentIndex = [mgr sizeMode];
    CGFloat deg = [mgr currentRotation] * 180.0 / M_PI;
    while (deg > 180.0) deg -= 360.0;
    while (deg < -180.0) deg += 360.0;
    self.rotationSlider.value = (float)deg;
    self.rotationValueLabel.text = [NSString stringWithFormat:@"%.0f°", deg];
    self.borderSwitch.on = [mgr showsBorder];
    self.gridSwitch.on = [mgr showsGrid];
    [self refreshSizeInfo];
}

- (NSString *)ratioStringForSize:(CGSize)s {
    if (s.width < 1 || s.height < 1) return @"—";
    NSInteger w = (NSInteger)llround(s.width);
    NSInteger h = (NSInteger)llround(s.height);
    NSInteger a = w, b = h;
    while (b != 0) { NSInteger t = a % b; a = b; b = t; }
    NSInteger g = MAX(1, a);
    NSInteger rw = w / g, rh = h / g;
    if (rw <= 32 && rh <= 32) {
        return [NSString stringWithFormat:@"%ld:%ld", (long)rw, (long)rh];
    }
    return [NSString stringWithFormat:@"%.2f:1", s.width / s.height];
}

- (void)refreshSizeInfo {
    OverlayManager *mgr = [OverlayManager sharedManager];
    CGSize overlay = [mgr currentOverlaySize];
    CGSize native = [mgr imageNativeSize];
    NSString *ratio = [self ratioStringForSize:(native.width > 0 ? native : overlay)];
    if (native.width > 0) {
        BOOL clamped = (native.width > overlay.width + 0.5 || native.height > overlay.height + 0.5);
        self.sizeInfoLabel.text = [NSString stringWithFormat:
            @"Fotoğraf %.0f × %.0f px  (%@)\nOverlay %.0f × %.0f pt%@",
            native.width, native.height, ratio,
            overlay.width, overlay.height,
            clamped ? @"  ·  ekrana sığdırıldı" : @""];
    } else {
        self.sizeInfoLabel.text = [NSString stringWithFormat:
            @"Görsel yok — overlay %.0f × %.0f pt", overlay.width, overlay.height];
    }
}

#pragma mark - Actions

- (void)closeTapped {
    [[OverlayManager sharedManager] hideSettingsPanel];
}

- (void)selectImageTapped {
    OLLog(@"Opening PHPicker");
    PHPickerConfiguration *config = [[PHPickerConfiguration alloc] init];
    config.filter = [PHPickerFilter imagesFilter];
    config.selectionLimit = 1;
    PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:config];
    picker.delegate = self;
    picker.modalPresentationStyle = UIModalPresentationFormSheet;
    [[OverlayManager sharedManager] presentModal:picker];
}

- (void)pasteTapped {
    UIImage *img = [UIPasteboard generalPasteboard].image;
    if (!img) {
        [self showAlert:@"Pano boş" msg:@"Önce bir görsel kopyalayın."];
        return;
    }
    [[OverlayManager sharedManager] setOverlayImage:img];
    self.imagePreview.image = img;
    [self refreshSizeInfo];
    [[OverlayManager sharedManager] showToast:@"Görsel panodan alındı"];
}

- (void)sizeModeChanged:(UISegmentedControl *)c {
    [[OverlayManager sharedManager] setSizeMode:c.selectedSegmentIndex];
    [self refreshSizeInfo];
    self.scaleSlider.value = (float)[[OverlayManager sharedManager] currentScale];
    self.scaleValueLabel.text = [NSString stringWithFormat:@"%.1f×", [[OverlayManager sharedManager] currentScale]];
}

- (void)customSizeTapped {
    OverlayManager *mgr = [OverlayManager sharedManager];
    CGSize cur = [mgr sizeMode] == 1 ? [mgr customSize] : [mgr currentOverlaySize];
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Özel boyut"
        message:@"Overlay genişliği × yüksekliği (nokta). Fotoğraf oranından bağımsızdır."
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.keyboardType = UIKeyboardTypeDecimalPad;
        tf.placeholder = @"Genişlik";
        tf.text = [NSString stringWithFormat:@"%.0f", cur.width];
        tf.textAlignment = NSTextAlignmentCenter;
    }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.keyboardType = UIKeyboardTypeDecimalPad;
        tf.placeholder = @"Yükseklik";
        tf.text = [NSString stringWithFormat:@"%.0f", cur.height];
        tf.textAlignment = NSTextAlignmentCenter;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"İptal" style:UIAlertActionStyleCancel handler:^(__unused UIAlertAction *a) {
        [mgr restoreKeyWindow];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Uygula" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
        CGFloat w = [alert.textFields[0].text doubleValue];
        CGFloat h = [alert.textFields[1].text doubleValue];
        if (w < 40) w = 40;
        if (h < 40) h = 40;
        [mgr setCustomSize:CGSizeMake(w, h)];
        self.sizeModeControl.selectedSegmentIndex = 1;
        self.scaleSlider.value = 1.0f;
        self.scaleValueLabel.text = @"1.0×";
        [self refreshSizeInfo];
        [mgr restoreKeyWindow];
    }]];
    [mgr presentModal:alert];
}

- (void)presetTapped:(UIButton *)btn {
    CGFloat rw = 1, rh = 1;
    switch (btn.tag) {
        case 500: rw = 1; rh = 1; break;
        case 501: rw = 9; rh = 16; break;
        case 502: rw = 16; rh = 9; break;
        case 503: rw = 4; rh = 3; break;
        case 504: rw = 3; rh = 4; break;
        default: break;
    }
    OverlayManager *mgr = [OverlayManager sharedManager];
    CGSize screen = mgr.overlayWindow ? mgr.overlayWindow.bounds.size : [UIScreen mainScreen].bounds.size;
    CGFloat maxW = screen.width * 0.72;
    CGFloat maxH = screen.height * 0.62;
    CGFloat f = MIN(maxW / rw, maxH / rh);
    [mgr setCustomSize:CGSizeMake(rw * f, rh * f)];
    self.sizeModeControl.selectedSegmentIndex = 1;
    self.scaleSlider.value = 1.0f;
    self.scaleValueLabel.text = @"1.0×";
    [self refreshSizeInfo];
}

- (void)opacityChanged:(UISlider *)slider {
    [[OverlayManager sharedManager] setOpacity:slider.value];
    self.opacityValueLabel.text = [NSString stringWithFormat:@"%.0f%%", slider.value * 100.0];
}

- (void)opacityPresetTapped:(UIButton *)btn {
    CGFloat values[] = {0.25, 0.50, 0.75, 1.00};
    NSInteger i = btn.tag - 600;
    if (i < 0 || i > 3) return;
    CGFloat v = values[i];
    [[OverlayManager sharedManager] setOpacity:v];
    self.opacitySlider.value = (float)v;
    self.opacityValueLabel.text = [NSString stringWithFormat:@"%.0f%%", v * 100.0];
}

- (void)rotationChanged:(UISlider *)slider {
    CGFloat rad = slider.value * (CGFloat)M_PI / 180.0;
    [[OverlayManager sharedManager] setRotation:rad];
    self.rotationValueLabel.text = [NSString stringWithFormat:@"%.0f°", slider.value];
}

- (void)rotateLeftTapped {
    OverlayManager *mgr = [OverlayManager sharedManager];
    [mgr rotateByDegrees:-90];
    CGFloat deg = [mgr currentRotation] * 180.0 / M_PI;
    while (deg > 180.0) deg -= 360.0;
    while (deg < -180.0) deg += 360.0;
    self.rotationSlider.value = (float)deg;
    self.rotationValueLabel.text = [NSString stringWithFormat:@"%.0f°", deg];
}

- (void)rotateRightTapped {
    OverlayManager *mgr = [OverlayManager sharedManager];
    [mgr rotateByDegrees:90];
    CGFloat deg = [mgr currentRotation] * 180.0 / M_PI;
    while (deg > 180.0) deg -= 360.0;
    while (deg < -180.0) deg += 360.0;
    self.rotationSlider.value = (float)deg;
    self.rotationValueLabel.text = [NSString stringWithFormat:@"%.0f°", deg];
}

- (void)borderChanged:(UISwitch *)sw {
    [[OverlayManager sharedManager] setShowsBorder:sw.isOn];
}

- (void)gridChanged:(UISwitch *)sw {
    [[OverlayManager sharedManager] setShowsGrid:sw.isOn];
}

- (void)nudgeTapped:(UIButton *)btn {
    CGPoint d = CGPointZero;
    switch (btn.tag) {
        case 701: d = CGPointMake(-10, 0); break;
        case 702: d = CGPointMake(10, 0); break;
        case 703: d = CGPointMake(0, -10); break;
        case 704: d = CGPointMake(0, 10); break;
        case 711: d = CGPointMake(-1, 0); break;
        case 712: d = CGPointMake(1, 0); break;
        default: break;
    }
    [[OverlayManager sharedManager] nudgeBy:d];
}

- (void)snapTapped:(UIButton *)btn {
    [[OverlayManager sharedManager] snapToAlignment:btn.tag - 800];
}

- (void)scaleChanged:(UISlider *)slider {
    [[OverlayManager sharedManager] setScale:slider.value];
    self.scaleValueLabel.text = [NSString stringWithFormat:@"%.1f×", slider.value];
}

- (void)modeChanged:(UISegmentedControl *)c {
    [[OverlayManager sharedManager] setContentModeIndex:c.selectedSegmentIndex];
}

- (void)lockChanged:(UISwitch *)sw {
    [[OverlayManager sharedManager] setLocked:sw.isOn];
    self.lockLabel.text = sw.isOn ? @"🔓  Overlay Kilidini Aç" : @"🔒  Overlay Kilitle";
}

- (void)flipHTapped {
    OverlayManager *mgr = [OverlayManager sharedManager];
    [mgr setFlipHorizontal:![mgr flipHorizontal]];
}

- (void)flipVTapped {
    OverlayManager *mgr = [OverlayManager sharedManager];
    [mgr setFlipVertical:![mgr flipVertical]];
}

- (void)toggleOverlayTapped {
    [[OverlayManager sharedManager] toggleOverlay];
}

- (void)hideMenuTapped {
    [[OverlayManager sharedManager] setMenuHidden:YES];
    [[OverlayManager sharedManager] hideSettingsPanel];
}

- (void)resetPosTapped {
    [[OverlayManager sharedManager] resetTransform];
    self.scaleSlider.value = 1.0f;
    self.scaleValueLabel.text = @"1.0×";
    self.rotationSlider.value = 0;
    self.rotationValueLabel.text = @"0°";
}

- (void)resetTapped {
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Sıfırla"
        message:@"Tüm ayarlar ve görsel silinecek."
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"İptal" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Sıfırla" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *a) {
        OverlayManager *mgr = [OverlayManager sharedManager];
        [mgr resetAllSettings];
        [self loadState];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - PHPickerViewControllerDelegate

- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
    [picker dismissViewControllerAnimated:YES completion:^{
        [[OverlayManager sharedManager] restoreKeyWindow];
    }];
    PHPickerResult *result = results.firstObject;
    if (!result) return;
    NSItemProvider *provider = result.itemProvider;
    if (![provider canLoadObjectOfClass:[UIImage class]]) return;
    [provider loadObjectOfClass:[UIImage class] completionHandler:^(id<NSItemProviderReading> obj, NSError *error) {
        UIImage *img = (UIImage *)obj;
        if (!img) {
            OLLog(@"PHPicker load failed: %@", error);
            return;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [[OverlayManager sharedManager] setOverlayImage:img];
            self.imagePreview.image = img;
            [self refreshSizeInfo];
            self.scaleSlider.value = (float)[[OverlayManager sharedManager] currentScale];
            self.scaleValueLabel.text = [NSString stringWithFormat:@"%.1f×", [[OverlayManager sharedManager] currentScale]];
            OLLog(@"Image selected.");
        });
    }];
}

#pragma mark - Alert

- (void)showAlert:(NSString *)title msg:(NSString *)msg {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:msg
                                                        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Tamam" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

@end
