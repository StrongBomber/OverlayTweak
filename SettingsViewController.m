/**
 * SettingsViewController.m — card-based overlay settings panel.
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
@property (nonatomic, strong) UISlider *cropLeftSlider;
@property (nonatomic, strong) UILabel *cropLeftValueLabel;
@property (nonatomic, strong) UISlider *cropRightSlider;
@property (nonatomic, strong) UILabel *cropRightValueLabel;
@property (nonatomic, strong) UISlider *cropTopSlider;
@property (nonatomic, strong) UILabel *cropTopValueLabel;
@property (nonatomic, strong) UISlider *cropBottomSlider;
@property (nonatomic, strong) UILabel *cropBottomValueLabel;
@property (nonatomic, strong) UISlider *pitchSlider;
@property (nonatomic, strong) UILabel *pitchValueLabel;
@property (nonatomic, strong) UISlider *yawSlider;
@property (nonatomic, strong) UILabel *yawValueLabel;
@property (nonatomic, strong) UISwitch *borderSwitch;
@property (nonatomic, strong) UISwitch *gridSwitch;
@property (nonatomic, strong) UIButton *toggleOverlayButton;
@property (nonatomic, strong) UIButton *resetButton;
@property (nonatomic, assign) BOOL uiBuilt;
- (CGFloat)addNamedSlider:(NSString *)title
                        y:(CGFloat)y
                       sw:(CGFloat)sw
                        p:(CGFloat)p
                    color:(UIColor *)color
                      min:(float)minValue
                      max:(float)maxValue
                   action:(SEL)action
                     unit:(NSString *)unit
                     bind:(void (^)(UISlider *slider, UILabel *valueLabel))bind;
- (void)refreshCropLabels;
- (void)tick;
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
    self.blurView.layer.cornerRadius = 22;
    self.blurView.clipsToBounds = YES;
    self.blurView.userInteractionEnabled = YES;
    [self.view addSubview:self.blurView];

    UIView *hairline = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 1.0 / [UIScreen mainScreen].scale)];
    hairline.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    hairline.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.18];
    [self.blurView.contentView addSubview:hairline];

    self.scrollView = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    self.scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.scrollView.showsVerticalScrollIndicator = YES;
    self.scrollView.alwaysBounceVertical = YES;
    self.scrollView.userInteractionEnabled = YES;
    self.scrollView.delaysContentTouches = NO;
    self.scrollView.indicatorStyle = UIScrollViewIndicatorStyleWhite;
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
    CGFloat h = CGRectGetMaxY(self.resetButton.frame) + 28;
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

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(p, 16, sw - 52, 24)];
    title.text = @"Overlay";
    title.font = [UIFont systemFontOfSize:22 weight:UIFontWeightBold];
    title.textColor = [UIColor whiteColor];
    [self.contentView addSubview:title];

    UILabel *ver = [[UILabel alloc] initWithFrame:CGRectMake(p, 40, sw - 52, 16)];
    ver.text = [NSString stringWithFormat:@"Ayarlar  ·  v%@", kOLVersion];
    ver.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    ver.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.45];
    [self.contentView addSubview:ver];

    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    closeBtn.frame = CGRectMake(self.view.bounds.size.width - p - 34, 16, 34, 34);
    [closeBtn setTitle:@"✕" forState:UIControlStateNormal];
    closeBtn.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    [closeBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    closeBtn.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.12];
    closeBtn.layer.cornerRadius = 17;
    closeBtn.exclusiveTouch = YES;
    [closeBtn addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:closeBtn];

    y = 68;

    /* GÖRSEL */
    y = [self section:@"GÖRSEL" y:y];
    UIView *imgCard = [self cardAtY:y height:88];
    self.imagePreview = [[UIImageView alloc] initWithFrame:CGRectMake(10, 10, 68, 68)];
    self.imagePreview.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.08];
    self.imagePreview.layer.cornerRadius = 12;
    self.imagePreview.clipsToBounds = YES;
    self.imagePreview.contentMode = UIViewContentModeScaleAspectFit;
    self.imagePreview.layer.borderWidth = 1.0 / [UIScreen mainScreen].scale;
    self.imagePreview.layer.borderColor = [[UIColor whiteColor] colorWithAlphaComponent:0.16].CGColor;
    [imgCard addSubview:self.imagePreview];

    CGFloat bw = sw - 10 - 68 - 10 - 10;
    self.imageSelectButton = [self actionButton:@"Galeriden seç"
                                          frame:CGRectMake(88, 12, bw, 30)
                                          color:[[UIColor systemBlueColor] colorWithAlphaComponent:0.85]
                                     titleColor:[UIColor whiteColor]];
    self.imageSelectButton.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    [self.imageSelectButton addTarget:self action:@selector(selectImageTapped) forControlEvents:UIControlEventTouchUpInside];
    [imgCard addSubview:self.imageSelectButton];

    self.pasteButton = [self actionButton:@"Panodan yapıştır"
                                    frame:CGRectMake(88, 46, bw, 30)
                                    color:[[UIColor whiteColor] colorWithAlphaComponent:0.10]
                               titleColor:[UIColor whiteColor]];
    self.pasteButton.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    [self.pasteButton addTarget:self action:@selector(pasteTapped) forControlEvents:UIControlEventTouchUpInside];
    [imgCard addSubview:self.pasteButton];
    y = CGRectGetMaxY(imgCard.frame) + 14;

    /* BOYUT */
    y = [self section:@"BOYUT" y:y];
    self.sizeModeControl = [[UISegmentedControl alloc] initWithItems:@[@"Fotoğrafa göre", @"Özel"]];
    self.sizeModeControl.frame = CGRectMake(p, y, sw, 34);
    self.sizeModeControl.selectedSegmentIndex = 0;
    [self styleSegment:self.sizeModeControl];
    [self.sizeModeControl addTarget:self action:@selector(sizeModeChanged:) forControlEvents:UIControlEventValueChanged];
    [self.contentView addSubview:self.sizeModeControl];

    y += 42;
    self.sizeInfoLabel = [[UILabel alloc] initWithFrame:CGRectMake(p + 4, y, sw - 8, 36)];
    self.sizeInfoLabel.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightRegular];
    self.sizeInfoLabel.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.62];
    self.sizeInfoLabel.numberOfLines = 2;
    self.sizeInfoLabel.text = @"Görsel seçilmedi";
    [self.contentView addSubview:self.sizeInfoLabel];

    y += 40;
    self.customSizeButton = [self actionButton:@"Genişlik × yükseklik"
                                         frame:CGRectMake(p, y, sw, 40)
                                         color:[[UIColor whiteColor] colorWithAlphaComponent:0.10]
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
    y += 46;

    /* ŞEFFAFLIK + ÖLÇEK */
    y = [self section:@"GÖRÜNÜRLÜK" y:y];
    y = [self addNamedSlider:@"Opaklık" y:y sw:sw p:p color:[UIColor systemBlueColor]
                         min:0.05f max:1.0f action:@selector(opacityChanged:)
                        unit:@"%" bind:^(UISlider *s, UILabel *l) {
                            self.opacitySlider = s;
                            self.opacityValueLabel = l;
                        }];
    NSArray *opPresets = @[@"25%", @"50%", @"75%", @"100%"];
    CGFloat opw = (sw - 18) / 4.0;
    for (NSInteger i = 0; i < 4; i++) {
        UIButton *b = [self actionButton:opPresets[i]
                                  frame:CGRectMake(p + i * (opw + 6), y, opw, 30)
                                  color:[[UIColor whiteColor] colorWithAlphaComponent:0.10]
                             titleColor:[UIColor whiteColor]];
        b.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
        b.tag = 600 + i;
        [b addTarget:self action:@selector(opacityPresetTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self.contentView addSubview:b];
    }
    y += 40;
    y = [self addNamedSlider:@"Ölçek" y:y sw:sw p:p color:[UIColor systemTealColor]
                         min:0.2f max:4.0f action:@selector(scaleChanged:)
                        unit:@"×" bind:^(UISlider *s, UILabel *l) {
                            self.scaleSlider = s;
                            self.scaleValueLabel = l;
                        }];

    /* RENK */
    y = [self section:@"RENK" y:y];
    UIButton *pickBtn = [self actionButton:@"Renk seç (eyedropper)"
                                     frame:CGRectMake(p, y, sw, 42)
                                     color:[UIColor systemPinkColor]
                                titleColor:[UIColor whiteColor]];
    pickBtn.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    [pickBtn addTarget:self action:@selector(colorPickTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:pickBtn];
    y += 48;
    UILabel *pickHint = [[UILabel alloc] initWithFrame:CGRectMake(p + 2, y, sw - 4, 34)];
    pickHint.text = @"Seçerken overlay %100 opak olur; bitince eski şeffaflık geri gelir. Renk kodu (#RRGGBB) gösterilir.";
    pickHint.font = [UIFont systemFontOfSize:11];
    pickHint.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.42];
    pickHint.numberOfLines = 2;
    [self.contentView addSubview:pickHint];
    y += 38;

    /* DÖNDÜRME */
    y = [self section:@"DÖNDÜRME" y:y];
    y = [self addNamedSlider:@"Z ekseni" y:y sw:sw p:p color:[UIColor systemOrangeColor]
                         min:-180.0f max:180.0f action:@selector(rotationChanged:)
                        unit:@"°" bind:^(UISlider *s, UILabel *l) {
                            self.rotationSlider = s;
                            self.rotationValueLabel = l;
                        }];
    UIButton *rotL = [self actionButton:@"↺  −90°"
                                  frame:CGRectMake(p, y, (sw - 8) / 2, 38)
                                  color:[[UIColor whiteColor] colorWithAlphaComponent:0.10]
                             titleColor:[UIColor whiteColor]];
    [rotL addTarget:self action:@selector(rotateLeftTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:rotL];
    UIButton *rotR = [self actionButton:@"+90°  ↻"
                                  frame:CGRectMake(p + (sw - 8) / 2 + 8, y, (sw - 8) / 2, 38)
                                  color:[[UIColor whiteColor] colorWithAlphaComponent:0.10]
                             titleColor:[UIColor whiteColor]];
    [rotR addTarget:self action:@selector(rotateRightTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:rotR];
    y += 50;

    /* KIRPMA */
    y = [self section:@"KIRPMA" y:y];
    UIButton *cropModeBtn = [self actionButton:@"Tutamaçlarla kırp"
                                         frame:CGRectMake(p, y, sw, 42)
                                         color:[UIColor systemPurpleColor]
                                    titleColor:[UIColor whiteColor]];
    cropModeBtn.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    [cropModeBtn addTarget:self action:@selector(cropModeTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:cropModeBtn];
    y += 48;
    UILabel *cropHint = [[UILabel alloc] initWithFrame:CGRectMake(p + 2, y, sw - 4, 34)];
    cropHint.text = @"Görsel yerinde kalır; sadece kırpma çerçevesi hareket eder. Tamam deyince uygulanır.";
    cropHint.font = [UIFont systemFontOfSize:11];
    cropHint.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.42];
    cropHint.numberOfLines = 2;
    [self.contentView addSubview:cropHint];
    y += 38;
    y = [self addNamedSlider:@"Sol" y:y sw:sw p:p color:[UIColor systemPurpleColor]
                         min:0 max:0.80f action:@selector(cropChanged:)
                        unit:@"%" bind:^(UISlider *s, UILabel *l) {
                            self.cropLeftSlider = s;
                            self.cropLeftValueLabel = l;
                        }];
    y = [self addNamedSlider:@"Sağ" y:y sw:sw p:p color:[UIColor systemPurpleColor]
                         min:0 max:0.80f action:@selector(cropChanged:)
                        unit:@"%" bind:^(UISlider *s, UILabel *l) {
                            self.cropRightSlider = s;
                            self.cropRightValueLabel = l;
                        }];
    y = [self addNamedSlider:@"Üst" y:y sw:sw p:p color:[UIColor systemPurpleColor]
                         min:0 max:0.80f action:@selector(cropChanged:)
                        unit:@"%" bind:^(UISlider *s, UILabel *l) {
                            self.cropTopSlider = s;
                            self.cropTopValueLabel = l;
                        }];
    y = [self addNamedSlider:@"Alt" y:y sw:sw p:p color:[UIColor systemPurpleColor]
                         min:0 max:0.80f action:@selector(cropChanged:)
                        unit:@"%" bind:^(UISlider *s, UILabel *l) {
                            self.cropBottomSlider = s;
                            self.cropBottomValueLabel = l;
                        }];
    UIButton *resetCrop = [self actionButton:@"Kırpmayı sıfırla"
                                       frame:CGRectMake(p, y, sw, 34)
                                       color:[[UIColor whiteColor] colorWithAlphaComponent:0.08]
                                  titleColor:[UIColor whiteColor]];
    resetCrop.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    [resetCrop addTarget:self action:@selector(resetCropTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:resetCrop];
    y += 46;

    /* ÇARPIT / WARP */
    y = [self section:@"ÇARPIT" y:y];
    UIButton *warpModeBtn = [self actionButton:@"Warp tutamaçları (3×3)"
                                         frame:CGRectMake(p, y, sw, 42)
                                         color:[UIColor systemOrangeColor]
                                    titleColor:[UIColor whiteColor]];
    warpModeBtn.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    [warpModeBtn addTarget:self action:@selector(warpModeTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:warpModeBtn];
    y += 48;
    UILabel *warpHint = [[UILabel alloc] initWithFrame:CGRectMake(p + 2, y, sw - 4, 34)];
    warpHint.text = @"Photoshop Distort + Warp. Köşeler dörtgen çarpıtır, iç noktalar mesh büker.";
    warpHint.font = [UIFont systemFontOfSize:11];
    warpHint.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.42];
    warpHint.numberOfLines = 2;
    [self.contentView addSubview:warpHint];
    y += 38;
    UIButton *resetWarp = [self actionButton:@"Warp'ı sıfırla"
                                       frame:CGRectMake(p, y, sw, 34)
                                       color:[[UIColor whiteColor] colorWithAlphaComponent:0.08]
                                  titleColor:[UIColor whiteColor]];
    resetWarp.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    [resetWarp addTarget:self action:@selector(resetWarpTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:resetWarp];
    y += 46;

    /* PERSPEKTİF */
    y = [self section:@"PERSPEKTİF" y:y];
    UIButton *perspModeBtn = [self actionButton:@"Tutamaçlarla perspektif"
                                          frame:CGRectMake(p, y, sw, 42)
                                          color:[UIColor systemYellowColor]
                                     titleColor:[UIColor colorWithWhite:0.12 alpha:1]];
    perspModeBtn.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    [perspModeBtn addTarget:self action:@selector(perspectiveModeTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:perspModeBtn];
    y += 48;
    UILabel *perspHint = [[UILabel alloc] initWithFrame:CGRectMake(p + 2, y, sw - 4, 34)];
    perspHint.text = @"Kırpma gibi kenar/köşe tutamaçları. Üst-alt pitch, sol-sağ yaw.";
    perspHint.font = [UIFont systemFontOfSize:11];
    perspHint.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.42];
    perspHint.numberOfLines = 2;
    [self.contentView addSubview:perspHint];
    y += 38;
    y = [self addNamedSlider:@"Pitch X" y:y sw:sw p:p color:[UIColor systemYellowColor]
                         min:-70.0f max:70.0f action:@selector(pitchChanged:)
                        unit:@"°" bind:^(UISlider *s, UILabel *l) {
                            self.pitchSlider = s;
                            self.pitchValueLabel = l;
                        }];
    y = [self addNamedSlider:@"Yaw Y" y:y sw:sw p:p color:[UIColor systemYellowColor]
                         min:-70.0f max:70.0f action:@selector(yawChanged:)
                        unit:@"°" bind:^(UISlider *s, UILabel *l) {
                            self.yawSlider = s;
                            self.yawValueLabel = l;
                        }];
    UIButton *resetPersp = [self actionButton:@"Perspektifi sıfırla"
                                        frame:CGRectMake(p, y, sw, 34)
                                        color:[[UIColor whiteColor] colorWithAlphaComponent:0.08]
                                   titleColor:[UIColor whiteColor]];
    resetPersp.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    [resetPersp addTarget:self action:@selector(resetPerspectiveTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:resetPersp];
    y += 46;

    /* SIĞDIRMA */
    y = [self section:@"SIĞDIRMA" y:y];
    self.modeControl = [[UISegmentedControl alloc] initWithItems:@[@"Sığdır", @"Doldur", @"Ger"]];
    self.modeControl.frame = CGRectMake(p, y, sw, 34);
    self.modeControl.selectedSegmentIndex = 0;
    [self styleSegment:self.modeControl];
    [self.modeControl addTarget:self action:@selector(modeChanged:) forControlEvents:UIControlEventValueChanged];
    [self.contentView addSubview:self.modeControl];
    y += 48;

    /* KİLİT */
    y = [self section:@"KİLİT" y:y];
    UIView *lockRow = [self cardAtY:y height:48];
    self.lockLabel = [[UILabel alloc] initWithFrame:CGRectMake(14, 0, sw - 80, 48)];
    self.lockLabel.text = @"Overlay kilitle";
    self.lockLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    self.lockLabel.textColor = [UIColor whiteColor];
    [lockRow addSubview:self.lockLabel];
    self.lockSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    self.lockSwitch.onTintColor = [UIColor systemBlueColor];
    [self.lockSwitch addTarget:self action:@selector(lockChanged:) forControlEvents:UIControlEventValueChanged];
    self.lockSwitch.frame = CGRectMake(sw - 65, 8.5, 0, 0);
    [lockRow addSubview:self.lockSwitch];
    y = CGRectGetMaxY(lockRow.frame) + 8;
    UILabel *info = [[UILabel alloc] initWithFrame:CGRectMake(p + 2, y, sw - 4, 32)];
    info.text = @"Kilitliyken overlay hareket etmez, dokunmalar oyuna geçer. Çift dokunuş konumu sıfırlar. Uzun basınca kilitlenir.";
    info.font = [UIFont systemFontOfSize:11];
    info.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.42];
    info.numberOfLines = 2;
    [self.contentView addSubview:info];
    y += 40;

    /* ÇEVİR */
    y = [self section:@"ÇEVİR" y:y];
    UIButton *flipH = [self actionButton:@"Yatay  ↔"
                                   frame:CGRectMake(p, y, (sw - 8) / 2, 42)
                                   color:[[UIColor whiteColor] colorWithAlphaComponent:0.10]
                              titleColor:[UIColor whiteColor]];
    [flipH addTarget:self action:@selector(flipHTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:flipH];
    UIButton *flipV = [self actionButton:@"Dikey  ↕"
                                   frame:CGRectMake(p + (sw - 8) / 2 + 8, y, (sw - 8) / 2, 42)
                                   color:[[UIColor whiteColor] colorWithAlphaComponent:0.10]
                              titleColor:[UIColor whiteColor]];
    [flipV addTarget:self action:@selector(flipVTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:flipV];
    y += 54;

    /* GÖRÜNÜM */
    y = [self section:@"GÖRÜNÜM" y:y];
    UIView *borderRow = [self cardAtY:y height:48];
    UILabel *borderLbl = [[UILabel alloc] initWithFrame:CGRectMake(14, 0, sw - 80, 48)];
    borderLbl.text = @"Kenarlık";
    borderLbl.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    borderLbl.textColor = [UIColor whiteColor];
    [borderRow addSubview:borderLbl];
    self.borderSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    self.borderSwitch.onTintColor = [UIColor systemBlueColor];
    [self.borderSwitch addTarget:self action:@selector(borderChanged:) forControlEvents:UIControlEventValueChanged];
    self.borderSwitch.frame = CGRectMake(sw - 65, 8.5, 0, 0);
    [borderRow addSubview:self.borderSwitch];
    y = CGRectGetMaxY(borderRow.frame) + 8;
    UIView *gridRow = [self cardAtY:y height:48];
    UILabel *gridLbl = [[UILabel alloc] initWithFrame:CGRectMake(14, 0, sw - 80, 48)];
    gridLbl.text = @"Hizalama ızgarası";
    gridLbl.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    gridLbl.textColor = [UIColor whiteColor];
    [gridRow addSubview:gridLbl];
    self.gridSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    self.gridSwitch.onTintColor = [UIColor systemBlueColor];
    [self.gridSwitch addTarget:self action:@selector(gridChanged:) forControlEvents:UIControlEventValueChanged];
    self.gridSwitch.frame = CGRectMake(sw - 65, 8.5, 0, 0);
    [gridRow addSubview:self.gridSwitch];
    y = CGRectGetMaxY(gridRow.frame) + 16;

    /* KONUM */
    y = [self section:@"KONUM" y:y];
    CGFloat nw = (sw - 16) / 3.0;
    NSArray *nudgeTitles = @[@"← 10", @"↑ 10", @"→ 10", @"← 1", @"↓ 10", @"→ 1"];
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

    y = [self section:@"YAPIŞTIR" y:y];
    NSArray *snapTitles = @[@"Orta", @"Sol", @"Sağ", @"Üst", @"Alt"];
    CGFloat sw5 = (sw - 16) / 5.0;
    for (NSInteger i = 0; i < 5; i++) {
        UIButton *b = [self actionButton:snapTitles[i]
                                  frame:CGRectMake(p + i * (sw5 + 4), y, sw5, 34)
                                  color:[[UIColor whiteColor] colorWithAlphaComponent:0.10]
                             titleColor:[UIColor whiteColor]];
        b.titleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
        b.tag = 800 + i;
        [b addTarget:self action:@selector(snapTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self.contentView addSubview:b];
    }
    y += 50;

    self.toggleOverlayButton = [self actionButton:@"Overlay göster / gizle"
                                            frame:CGRectMake(p, y, sw, 46)
                                            color:[UIColor systemBlueColor]
                                       titleColor:[UIColor whiteColor]];
    self.toggleOverlayButton.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    [self.toggleOverlayButton addTarget:self action:@selector(toggleOverlayTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:self.toggleOverlayButton];
    y += 54;

    UIButton *hideMenu = [self actionButton:@"Menü butonunu gizle"
                                      frame:CGRectMake(p, y, sw, 44)
                                      color:[[UIColor whiteColor] colorWithAlphaComponent:0.10]
                                 titleColor:[UIColor whiteColor]];
    [hideMenu addTarget:self action:@selector(hideMenuTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:hideMenu];
    y += 52;

    UIButton *resetPos = [self actionButton:@"Konumu ortala"
                                      frame:CGRectMake(p, y, sw, 44)
                                      color:[[UIColor whiteColor] colorWithAlphaComponent:0.10]
                                 titleColor:[UIColor whiteColor]];
    [resetPos addTarget:self action:@selector(resetPosTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:resetPos];
    y += 56;

    self.resetButton = [self actionButton:@"Tüm ayarları sıfırla"
                                    frame:CGRectMake(p, y, sw, 46)
                                    color:[[UIColor systemRedColor] colorWithAlphaComponent:0.16]
                               titleColor:[UIColor systemRedColor]];
    self.resetButton.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    [self.resetButton addTarget:self action:@selector(resetTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:self.resetButton];
}

#pragma mark - Chrome helpers

- (UIView *)cardAtY:(CGFloat)y height:(CGFloat)h {
    UIView *c = [[UIView alloc] initWithFrame:CGRectMake(16, y, self.view.bounds.size.width - 32, h)];
    c.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.07];
    c.layer.cornerRadius = 14;
    c.layer.borderWidth = 1.0 / [UIScreen mainScreen].scale;
    c.layer.borderColor = [[UIColor whiteColor] colorWithAlphaComponent:0.10].CGColor;
    c.userInteractionEnabled = YES;
    [self.contentView addSubview:c];
    return c;
}

- (CGFloat)section:(NSString *)text y:(CGFloat)y {
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(20, y, self.view.bounds.size.width - 40, 18)];
    l.text = text;
    l.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
    l.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.42];
    [self.contentView addSubview:l];
    return y + 24;
}

- (void)styleSegment:(UISegmentedControl *)c {
    if (@available(iOS 13.0, *)) {
        c.selectedSegmentTintColor = [UIColor systemBlueColor];
        [c setTitleTextAttributes:@{NSForegroundColorAttributeName: [UIColor whiteColor],
                                    NSFontAttributeName: [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold]}
                         forState:UIControlStateNormal];
        [c setTitleTextAttributes:@{NSForegroundColorAttributeName: [UIColor whiteColor]}
                         forState:UIControlStateSelected];
    }
}

- (UIButton *)actionButton:(NSString *)title frame:(CGRect)frame color:(UIColor *)bg titleColor:(UIColor *)tc {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.frame = frame;
    [b setTitle:title forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    [b setTitleColor:tc forState:UIControlStateNormal];
    b.backgroundColor = bg;
    b.layer.cornerRadius = 12;
    b.exclusiveTouch = YES;
    b.adjustsImageWhenHighlighted = YES;
    return b;
}

- (CGFloat)addNamedSlider:(NSString *)title
                        y:(CGFloat)y
                       sw:(CGFloat)sw
                        p:(CGFloat)p
                    color:(UIColor *)color
                      min:(float)minValue
                      max:(float)maxValue
                   action:(SEL)action
                     unit:(NSString *)unit
                     bind:(void (^)(UISlider *slider, UILabel *valueLabel))bind {
    UILabel *name = [[UILabel alloc] initWithFrame:CGRectMake(p, y, 72, 18)];
    name.text = title;
    name.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    name.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.62];
    [self.contentView addSubview:name];

    UILabel *v = [[UILabel alloc] initWithFrame:CGRectMake(self.view.bounds.size.width - p - 52, y, 52, 18)];
    v.text = [unit isEqualToString:@"%"] ? @"0%" : ([unit isEqualToString:@"×"] ? @"1.0×" : @"0°");
    v.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightSemibold];
    v.textColor = [UIColor whiteColor];
    v.textAlignment = NSTextAlignmentRight;
    [self.contentView addSubview:v];

    UISlider *s = [[UISlider alloc] initWithFrame:CGRectMake(p, y + 18, sw, 28)];
    s.minimumValue = minValue;
    s.maximumValue = maxValue;
    s.value = minValue > 0 ? minValue : 0;
    s.minimumTrackTintColor = color;
    s.maximumTrackTintColor = [[UIColor whiteColor] colorWithAlphaComponent:0.18];
    [s addTarget:self action:action forControlEvents:UIControlEventValueChanged];
    [self.contentView addSubview:s];

    if (bind) bind(s, v);
    return y + 50;
}

- (void)tick {
    if (@available(iOS 10.0, *)) {
        UIImpactFeedbackGenerator *g = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
        [g impactOccurred];
    }
}

#pragma mark - State

- (void)loadState {
    OverlayManager *mgr = [OverlayManager sharedManager];
    self.opacitySlider.value = (float)[mgr currentOpacity];
    self.opacityValueLabel.text = [NSString stringWithFormat:@"%.0f%%", [mgr currentOpacity] * 100.0];
    self.scaleSlider.value = (float)[mgr currentScale];
    self.scaleValueLabel.text = [NSString stringWithFormat:@"%.1f×", [mgr currentScale]];
    self.lockSwitch.on = mgr.isLocked;
    self.lockLabel.text = mgr.isLocked ? @"Kilidi aç" : @"Overlay kilitle";
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
    UIEdgeInsets crop = [mgr cropInsets];
    self.cropLeftSlider.value = (float)crop.left;
    self.cropRightSlider.value = (float)crop.right;
    self.cropTopSlider.value = (float)crop.top;
    self.cropBottomSlider.value = (float)crop.bottom;
    [self refreshCropLabels];
    CGFloat pitchDeg = [mgr pitch] * 180.0 / M_PI;
    CGFloat yawDeg = [mgr yaw] * 180.0 / M_PI;
    self.pitchSlider.value = (float)pitchDeg;
    self.yawSlider.value = (float)yawDeg;
    self.pitchValueLabel.text = [NSString stringWithFormat:@"%.0f°", pitchDeg];
    self.yawValueLabel.text = [NSString stringWithFormat:@"%.0f°", yawDeg];
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
    [self tick];
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
    [self tick];
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
    [self tick];
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
    [self tick];
}

- (void)rotateRightTapped {
    OverlayManager *mgr = [OverlayManager sharedManager];
    [mgr rotateByDegrees:90];
    CGFloat deg = [mgr currentRotation] * 180.0 / M_PI;
    while (deg > 180.0) deg -= 360.0;
    while (deg < -180.0) deg += 360.0;
    self.rotationSlider.value = (float)deg;
    self.rotationValueLabel.text = [NSString stringWithFormat:@"%.0f°", deg];
    [self tick];
}

- (void)refreshCropLabels {
    self.cropLeftValueLabel.text = [NSString stringWithFormat:@"%.0f%%", self.cropLeftSlider.value * 100.0];
    self.cropRightValueLabel.text = [NSString stringWithFormat:@"%.0f%%", self.cropRightSlider.value * 100.0];
    self.cropTopValueLabel.text = [NSString stringWithFormat:@"%.0f%%", self.cropTopSlider.value * 100.0];
    self.cropBottomValueLabel.text = [NSString stringWithFormat:@"%.0f%%", self.cropBottomSlider.value * 100.0];
}

- (void)cropChanged:(UISlider *)slider {
    (void)slider;
    UIEdgeInsets insets = UIEdgeInsetsMake(self.cropTopSlider.value,
                                           self.cropLeftSlider.value,
                                           self.cropBottomSlider.value,
                                           self.cropRightSlider.value);
    [[OverlayManager sharedManager] setCropInsets:insets];
    [self refreshCropLabels];
}

- (void)colorPickTapped {
    [self tick];
    [[OverlayManager sharedManager] beginColorPickMode];
}

- (void)cropModeTapped {
    [self tick];
    [[OverlayManager sharedManager] beginCropMode];
}

- (void)warpModeTapped {
    [self tick];
    [[OverlayManager sharedManager] beginWarpMode];
}

- (void)resetWarpTapped {
    [[OverlayManager sharedManager] resetWarp];
    [self tick];
}

- (void)perspectiveModeTapped {
    [self tick];
    [[OverlayManager sharedManager] beginPerspectiveMode];
}

- (void)resetCropTapped {
    [[OverlayManager sharedManager] resetCrop];
    self.cropLeftSlider.value = 0;
    self.cropRightSlider.value = 0;
    self.cropTopSlider.value = 0;
    self.cropBottomSlider.value = 0;
    [self refreshCropLabels];
}

- (void)pitchChanged:(UISlider *)slider {
    CGFloat rad = slider.value * (CGFloat)M_PI / 180.0;
    [[OverlayManager sharedManager] setPitch:rad];
    self.pitchValueLabel.text = [NSString stringWithFormat:@"%.0f°", slider.value];
}

- (void)yawChanged:(UISlider *)slider {
    CGFloat rad = slider.value * (CGFloat)M_PI / 180.0;
    [[OverlayManager sharedManager] setYaw:rad];
    self.yawValueLabel.text = [NSString stringWithFormat:@"%.0f°", slider.value];
}

- (void)resetPerspectiveTapped {
    [[OverlayManager sharedManager] resetPerspective];
    self.pitchSlider.value = 0;
    self.yawSlider.value = 0;
    self.pitchValueLabel.text = @"0°";
    self.yawValueLabel.text = @"0°";
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
    [self tick];
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
    self.lockLabel.text = sw.isOn ? @"Kilidi aç" : @"Overlay kilitle";
    [self tick];
}

- (void)flipHTapped {
    OverlayManager *mgr = [OverlayManager sharedManager];
    [mgr setFlipHorizontal:![mgr flipHorizontal]];
    [self tick];
}

- (void)flipVTapped {
    OverlayManager *mgr = [OverlayManager sharedManager];
    [mgr setFlipVertical:![mgr flipVertical]];
    [self tick];
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
    self.pitchSlider.value = 0;
    self.yawSlider.value = 0;
    self.pitchValueLabel.text = @"0°";
    self.yawValueLabel.text = @"0°";
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
