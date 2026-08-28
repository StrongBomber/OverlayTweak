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

    y += 42;
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
    y += 16;

    self.toggleOverlayButton = [self actionButton:@"👁  Overlay Göster / Gizle"
                                            frame:CGRectMake(p, y, sw, 44)
                                            color:[UIColor systemBlueColor]
                                       titleColor:[UIColor whiteColor]];
    [self.toggleOverlayButton addTarget:self action:@selector(toggleOverlayTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:self.toggleOverlayButton];

    y += 52;
    UIButton *hideMenu = [self actionButton:@"🫥  Menü Butonunu Gizle"
                                      frame:CGRectMake(p, y, sw, 44)
                                      color:[[UIColor whiteColor] colorWithAlphaComponent:0.10]
                                 titleColor:[UIColor whiteColor]];
    [hideMenu addTarget:self action:@selector(hideMenuTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:hideMenu];

    y += 52;
    UIButton *resetPos = [self actionButton:@"🎯  Konumu Ortala"
                                      frame:CGRectMake(p, y, sw, 44)
                                      color:[[UIColor whiteColor] colorWithAlphaComponent:0.10]
                                 titleColor:[UIColor whiteColor]];
    [resetPos addTarget:self action:@selector(resetPosTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:resetPos];

    y += 56;
    self.resetButton = [self actionButton:@"🔄  Tüm Ayarları Sıfırla"
                                    frame:CGRectMake(p, y, sw, 44)
                                    color:[[UIColor systemRedColor] colorWithAlphaComponent:0.14]
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
    [[OverlayManager sharedManager] showToast:@"Görsel panodan alındı"];
}

- (void)opacityChanged:(UISlider *)slider {
    [[OverlayManager sharedManager] setOpacity:slider.value];
    self.opacityValueLabel.text = [NSString stringWithFormat:@"%.0f%%", slider.value * 100.0];
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
