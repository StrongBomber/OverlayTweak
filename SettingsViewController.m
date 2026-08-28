/**
 * ==============================================================================
 * SettingsViewController.m
 * ==============================================================================
 * Kritik düzeltmeler:
 *   1. userInteractionEnabled = YES (tüm view'larda)
 *   2. exclusiveTouch = YES (butonlarda)
 *   3. cancelButtonTapsOutside: Arka plana tıklayınca kapatma
 *   4. UIImagePickerController presentViewController düzeltmesi
 * ==============================================================================
 */

#import "SettingsViewController.h"
#import "OverlayManager.h"

@interface SettingsViewController () <UIImagePickerControllerDelegate, UINavigationControllerDelegate>
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIView *contentView;
@property (nonatomic, strong) UIVisualEffectView *blurView;
@property (nonatomic, strong) UIButton *imageSelectButton;
@property (nonatomic, strong) UIImageView *imagePreview;
@property (nonatomic, strong) UISlider *opacitySlider;
@property (nonatomic, strong) UILabel *opacityValueLabel;
@property (nonatomic, strong) UILabel *lockLabel;
@property (nonatomic, strong) UISwitch *lockSwitch;
@property (nonatomic, strong) UIButton *toggleOverlayButton;
@property (nonatomic, strong) UIButton *resetButton;
@end

@implementation SettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    // Kritik: Tüm view'larda userInteractionEnabled
    self.view.userInteractionEnabled = YES;
    self.view.backgroundColor = [UIColor clearColor];

    // Blur arka plan
    UIBlurEffect *blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark];
    self.blurView = [[UIVisualEffectView alloc] initWithEffect:blur];
    self.blurView.frame = self.view.bounds;
    self.blurView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.blurView.layer.cornerRadius = 16;
    self.blurView.clipsToBounds = YES;
    self.blurView.userInteractionEnabled = YES;
    [self.view addSubview:self.blurView];

    // Scroll view
    self.scrollView = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    self.scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.scrollView.showsVerticalScrollIndicator = NO;
    self.scrollView.userInteractionEnabled = YES;
    [self.blurView.contentView addSubview:self.scrollView];

    self.contentView = [[UIView alloc] initWithFrame:self.view.bounds];
    self.contentView.userInteractionEnabled = YES;
    [self.scrollView addSubview:self.contentView];

    [self buildUI];
    [self loadState];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat h = CGRectGetMaxY(self.resetButton.frame) + 20;
    self.scrollView.contentSize = CGSizeMake(self.view.bounds.size.width, h);
    self.contentView.frame = CGRectMake(0, 0, self.view.bounds.size.width, h);
}

#pragma mark - UI Oluşturma

- (void)buildUI {
    CGFloat p = 16; // padding
    CGFloat sw = self.view.bounds.size.width - p * 2; // section width
    CGFloat y = 0;

    // === BAŞLIK ===
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(p, 12, 200, 30)];
    title.text = @"Overlay Ayarları";
    title.font = [UIFont systemFontOfSize:18 weight:UIFontWeightSemibold];
    title.textColor = [UIColor whiteColor];
    title.userInteractionEnabled = NO;
    [self.contentView addSubview:title];

    // Kapat butonu
    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    closeBtn.frame = CGRectMake(self.view.bounds.size.width - 44 - p, 12, 44, 30);
    closeBtn.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [closeBtn setTitle:@"✕" forState:UIControlStateNormal];
    closeBtn.titleLabel.font = [UIFont systemFontOfSize:20];
    [closeBtn setTitleColor:[UIColor lightGrayColor] forState:UIControlStateNormal];
    closeBtn.userInteractionEnabled = YES;
    closeBtn.exclusiveTouch = YES;
    [closeBtn addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:closeBtn];

    y = 52;
    [self addSeparatorAtY:y];
    y += 8;

    // === GÖRSEL ===
    UILabel *imgLabel = [self sectionLabel:@"GÖRSEL" y:y];
    [self.contentView addSubview:imgLabel];
    y += 24;

    CGFloat ps = 60; // preview size
    self.imagePreview = [[UIImageView alloc] initWithFrame:CGRectMake(p, y, ps, ps)];
    self.imagePreview.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.1];
    self.imagePreview.layer.cornerRadius = 8;
    self.imagePreview.clipsToBounds = YES;
    self.imagePreview.contentMode = UIViewContentModeScaleAspectFit;
    self.imagePreview.userInteractionEnabled = NO;
    [self.contentView addSubview:self.imagePreview];

    self.imageSelectButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.imageSelectButton.frame = CGRectMake(p + ps + 12, y, sw - ps - 12, 60);
    [self.imageSelectButton setTitle:@"📷  Galeriden Görsel Seç" forState:UIControlStateNormal];
    self.imageSelectButton.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    [self.imageSelectButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.imageSelectButton.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.15];
    self.imageSelectButton.layer.cornerRadius = 8;
    self.imageSelectButton.userInteractionEnabled = YES;
    self.imageSelectButton.exclusiveTouch = YES;
    [self.imageSelectButton addTarget:self action:@selector(selectImageTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:self.imageSelectButton];

    y += 76;
    [self addSeparatorAtY:y];
    y += 8;

    // === ŞEFFAFLIK ===
    UILabel *opLabel = [self sectionLabel:@"ŞEFFAFLIK" y:y];
    [self.contentView addSubview:opLabel];
    y += 28;

    self.opacitySlider = [[UISlider alloc] initWithFrame:CGRectMake(p, y, sw - 55, 30)];
    self.opacitySlider.minimumValue = 0;
    self.opacitySlider.maximumValue = 1;
    self.opacitySlider.value = 0.5;
    self.opacitySlider.minimumTrackTintColor = [UIColor systemBlueColor];
    self.opacitySlider.maximumTrackTintColor = [[UIColor whiteColor] colorWithAlphaComponent:0.2];
    self.opacitySlider.userInteractionEnabled = YES;
    [self.opacitySlider addTarget:self action:@selector(opacityChanged:) forControlEvents:UIControlEventValueChanged];
    [self.contentView addSubview:self.opacitySlider];

    self.opacityValueLabel = [[UILabel alloc] initWithFrame:CGRectMake(
        self.view.bounds.size.width - p - 50, y, 50, 30)];
    self.opacityValueLabel.text = @"50%";
    self.opacityValueLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    self.opacityValueLabel.textColor = [UIColor whiteColor];
    self.opacityValueLabel.textAlignment = NSTextAlignmentRight;
    self.opacityValueLabel.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    self.opacityValueLabel.userInteractionEnabled = NO;
    [self.contentView addSubview:self.opacityValueLabel];

    y += 44;
    [self addSeparatorAtY:y];
    y += 8;

    // === KİLİT ===
    UILabel *lockLbl = [self sectionLabel:@"KİLİT" y:y];
    [self.contentView addSubview:lockLbl];
    y += 28;

    UIView *lockRow = [[UIView alloc] initWithFrame:CGRectMake(p, y, sw, 44)];
    lockRow.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.05];
    lockRow.layer.cornerRadius = 8;
    lockRow.userInteractionEnabled = YES;
    [self.contentView addSubview:lockRow];

    self.lockLabel = [[UILabel alloc] initWithFrame:CGRectMake(12, 0, sw - 70, 44)];
    self.lockLabel.text = @"🔒  Overlay Kilitle";
    self.lockLabel.font = [UIFont systemFontOfSize:15];
    self.lockLabel.textColor = [UIColor whiteColor];
    self.lockLabel.userInteractionEnabled = NO;
    [lockRow addSubview:self.lockLabel];

    self.lockSwitch = [[UISwitch alloc] initWithFrame:CGRectMake(sw - 59, 7, 0, 0)];
    self.lockSwitch.onTintColor = [UIColor systemBlueColor];
    self.lockSwitch.userInteractionEnabled = YES;
    [self.lockSwitch addTarget:self action:@selector(lockChanged:) forControlEvents:UIControlEventValueChanged];
    [lockRow addSubview:self.lockSwitch];

    y += 60;

    UILabel *info = [[UILabel alloc] initWithFrame:CGRectMake(p, y, sw, 30)];
    info.text = @"Kilitliyken overlay hareket etmez ve\ndokunmalar oyuna geçer.";
    info.font = [UIFont systemFontOfSize:11];
    info.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.4];
    info.numberOfLines = 2;
    info.userInteractionEnabled = NO;
    [self.contentView addSubview:info];

    y += 44;
    [self addSeparatorAtY:y];
    y += 16;

    // === BUTONLAR ===
    self.toggleOverlayButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.toggleOverlayButton.frame = CGRectMake(p, y, sw, 44);
    [self.toggleOverlayButton setTitle:@"👁  Overlay Göster/Gizle" forState:UIControlStateNormal];
    self.toggleOverlayButton.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    [self.toggleOverlayButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.toggleOverlayButton.backgroundColor = [UIColor systemBlueColor];
    self.toggleOverlayButton.layer.cornerRadius = 8;
    self.toggleOverlayButton.userInteractionEnabled = YES;
    self.toggleOverlayButton.exclusiveTouch = YES;
    [self.toggleOverlayButton addTarget:self action:@selector(toggleOverlayTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:self.toggleOverlayButton];

    y += 56;

    self.resetButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.resetButton.frame = CGRectMake(p, y, sw, 44);
    [self.resetButton setTitle:@"🔄  Tüm Ayarları Sıfırla" forState:UIControlStateNormal];
    self.resetButton.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    [self.resetButton setTitleColor:[UIColor systemRedColor] forState:UIControlStateNormal];
    self.resetButton.backgroundColor = [[UIColor systemRedColor] colorWithAlphaComponent:0.1];
    self.resetButton.layer.cornerRadius = 8;
    self.resetButton.userInteractionEnabled = YES;
    self.resetButton.exclusiveTouch = YES;
    [self.resetButton addTarget:self action:@selector(resetTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:self.resetButton];
}

#pragma mark - Yardımcı UI

- (UILabel *)sectionLabel:(NSString *)text y:(CGFloat)y {
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(16, y, self.view.bounds.size.width - 32, 20)];
    l.text = text;
    l.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    l.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.6];
    l.userInteractionEnabled = NO;
    return l;
}

- (void)addSeparatorAtY:(CGFloat)y {
    UIView *sep = [[UIView alloc] initWithFrame:CGRectMake(16, y, self.view.bounds.size.width - 32, 0.5)];
    sep.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.15];
    sep.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    sep.userInteractionEnabled = NO;
    [self.contentView addSubview:sep];
}

#pragma mark - Durum

- (void)loadState {
    OverlayManager *mgr = [OverlayManager sharedManager];
    self.opacitySlider.value = [mgr currentOpacity];
    self.opacityValueLabel.text = [NSString stringWithFormat:@"%.0f%%", [mgr currentOpacity] * 100];
    self.lockSwitch.on = mgr.isLocked;
    self.lockLabel.text = mgr.isLocked ? @"🔓  Overlay Kilidini Aç" : @"🔒  Overlay Kilitle";

    NSData *data = [[NSUserDefaults standardUserDefaults] objectForKey:kDefaultsImageBookmark];
    if (data) self.imagePreview.image = [UIImage imageWithData:data];
}

#pragma mark - Aksiyonlar

- (void)closeTapped {
    [[OverlayManager sharedManager] hideSettingsPanel];
}

- (void)selectImageTapped {
    OLLog(@"Görsel seç butonuna basıldı!");

    if (![UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypePhotoLibrary]) {
        [self showAlert:@"Hata" msg:@"Galeri erişimi yok."];
        return;
    }

    UIImagePickerController *picker = [[UIImagePickerController alloc] init];
    picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    picker.delegate = self;
    picker.allowsEditing = NO;
    picker.mediaTypes = @[@"public.image"];

    if (@available(iOS 13.0, *)) {
        picker.modalPresentationStyle = UIModalPresentationPageSheet;
    }

    // Kritik: Doğru view controller'dan present et
    [self presentViewController:picker animated:YES completion:^{
        OLLog(@"Galeri açıldı.");
    }];
}

- (void)opacityChanged:(UISlider *)slider {
    [[OverlayManager sharedManager] setOpacity:slider.value];
    self.opacityValueLabel.text = [NSString stringWithFormat:@"%.0f%%", slider.value * 100];
}

- (void)lockChanged:(UISwitch *)sw {
    [[OverlayManager sharedManager] setLocked:sw.isOn];
    self.lockLabel.text = sw.isOn ? @"🔓  Overlay Kilidini Aç" : @"🔒  Overlay Kilitle";
}

- (void)toggleOverlayTapped {
    [[OverlayManager sharedManager] toggleOverlay];
}

- (void)resetTapped {
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Sıfırla"
        message:@"Tüm ayarlar sıfırlanacak?"
        preferredStyle:UIAlertControllerStyleAlert];

    [alert addAction:[UIAlertAction actionWithTitle:@"İptal" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Sıfırla" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
        OverlayManager *mgr = [OverlayManager sharedManager];
        [mgr setOpacity:0.5];
        [mgr setLocked:NO];
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:kDefaultsImageBookmark];
        [[NSUserDefaults standardUserDefaults] synchronize];
        self.opacitySlider.value = 0.5;
        self.opacityValueLabel.text = @"50%";
        self.lockSwitch.on = NO;
        self.lockLabel.text = @"🔒  Overlay Kilitle";
        self.imagePreview.image = nil;
    }]];

    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - UIImagePickerControllerDelegate

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey,id> *)info {
    UIImage *img = info[UIImagePickerControllerOriginalImage];
    if (img) {
        [[OverlayManager sharedManager] setOverlayImage:img];
        self.imagePreview.image = img;
        OLLog(@"Görsel seçildi ve kaydedildi.");
    }
    [picker dismissViewControllerAnimated:YES completion:nil];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [picker dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Alert

- (void)showAlert:(NSString *)title msg:(NSString *)msg {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:msg
        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Tamam" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

@end
