/**
 * CPMUICalibration.m
 * Implementation of CPM UI Layout Mapper & Calibration Engine.
 * Manages UI element anchor coordinates for CPM vinyl editor automation.
 */
#import "CPMUICalibration.h"

#pragma mark - CPMUIElementAnchor

@implementation CPMUIElementAnchor

- (instancetype)initWithType:(CPMUIElementType)type center:(CGPoint)c size:(CGSize)s {
    self = [super init];
    if (self) {
        _elementType = type;
        _center = c;
        _size = s;
        _isValid = YES;
    }
    return self;
}

- (BOOL)containsPoint:(CGPoint)point {
    CGRect r = CGRectMake(self.center.x - self.size.width/2,
                          self.center.y - self.size.height/2,
                          self.size.width, self.size.height);
    return CGRectContainsPoint(r, point);
}

- (NSDictionary<NSString*,id> *)toDictionary {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    d[@"type"] = @(self.elementType);
    d[@"center"] = @{@"x": @(self.center.x), @"y": @(self.center.y)};
    d[@"size"] = @{@"width": @(self.size.width), @"height": @(self.size.height)};
    if (self.displayName) d[@"displayName"] = self.displayName;
    d[@"isValid"] = @(self.isValid);
    if (self.elementType >= CPMUIElementTypeRedSlider &&
        self.elementType <= CPMUIElementTypeRotateSlider) {
        d[@"sliderMinX"] = @(self.sliderMinX);
        d[@"sliderMaxX"] = @(self.sliderMaxX);
        d[@"sliderMinY"] = @(self.sliderMinY);
        d[@"sliderMaxY"] = @(self.sliderMaxY);
    }
    return [d copy];
}

+ (instancetype)anchorFromDictionary:(NSDictionary<NSString*,id> *)dict {
    if (!dict) return nil;
    NSInteger type = [dict[@"type"] integerValue];
    NSDictionary *center = dict[@"center"];
    NSDictionary *size = dict[@"size"];
    if (!center || !size) return nil;
    CGPoint c = CGPointMake([center[@"x"] doubleValue], [center[@"y"] doubleValue]);
    CGSize s = CGSizeMake([size[@"width"] doubleValue], [size[@"height"] doubleValue]);
    CPMUIElementAnchor *anchor = [[self alloc] initWithType:type center:c size:s];
    anchor.displayName = dict[@"displayName"];
    anchor.isValid = [dict[@"isValid"] boolValue];
    if (type >= CPMUIElementTypeRedSlider && type <= CPMUIElementTypeRotateSlider) {
        anchor.sliderMinX = [dict[@"sliderMinX"] doubleValue];
        anchor.sliderMaxX = [dict[@"sliderMaxX"] doubleValue];
        anchor.sliderMinY = [dict[@"sliderMinY"] doubleValue];
        anchor.sliderMaxY = [dict[@"sliderMaxY"] doubleValue];
    }
    return anchor;
}

@end

#pragma mark - CPMUICalibration

@interface CPMUICalibration ()
@property (nonatomic, copy, readwrite) NSString *calibrationID;
@property (nonatomic, copy, readwrite) NSArray<CPMUIElementAnchor *> *anchors;
@end

@implementation CPMUICalibration

+ (instancetype)defaultCalibrationForScreenSize:(CGSize)screenSize {
    // Load from bundled JSON or create default based on device
    NSString *path = [[NSBundle mainBundle] pathForResource:@"cpm_ui_anchors" ofType:@"json"];
    if (path) {
        NSData *data = [NSData dataWithContentsOfFile:path];
        if (data) {
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            CPMUICalibration *cal = [self calibrationFromJSON:json];
            cal.calibrationID = json[@"calibrationID"] ?: @"default";
            return cal;
        }
    }
    // Fallback: create basic calibration for common screen sizes
    CPMUICalibration *cal = [[self alloc] init];
    cal.calibrationID = @"generated_default";
    cal.screenSize = screenSize;
    cal.scaleFactor = 1.0;
    cal.isLandscape = screenSize.width > screenSize.height;
    NSMutableArray<CPMUIElementAnchor *> *anchors = [NSMutableArray array];
    CGFloat w = screenSize.width, h = screenSize.height;
    CGFloat cx = w * 0.85, cy = h * 0.05;
    [anchors addObject:[[CPMUIElementAnchor alloc] initWithType:CPMUIElementTypeAddShape
                                                       center:CGPointMake(cx,cy) size:CGSizeMake(50,50)]];
    [anchors addObject:[[CPMUIElementAnchor alloc] initWithType:CPMUIElementTypeShapeSelector
                                                       center:CGPointMake(w*0.15,h*0.4) size:CGSizeMake(80,300)]];
    [anchors addObject:[[CPMUIElementAnchor alloc] initWithType:CPMUIElementTypeColorPicker
                                                       center:CGPointMake(w*0.8,c*0.18) size:CGSizeMake(60,60)]];
    CGFloat sliderY = h*0.33;
    for (int i=0;i<3;i++) {
        [anchors addObject:[[CPMUIElementAnchor alloc] initWithType:CPMUIElementTypeRedSlider+i
                                                           center:CGPointMake(w*0.85,sliderY+i*h*0.04)
                                                           size:CGSizeMake(w*0.5,20)]];
    }
    sliderY = h*0.5;
    for (int i=0;i<2;i++) {
        [anchors addObject:[[CPMUIElementAnchor alloc] initWithType:CPMUIElementTypeScaleSlider+i
                                                           center:CGPointMake(w*0.85,sliderY+i*h*0.04)
                                                           size:CGSizeMake(w*0.5,20)]];
    }
    [anchors addObject:[[CPMUIElementAnchor alloc] initWithType:CPMUIElementTypeMoveJoystick
                                                       center:CGPointMake(w*0.85,h*0.62) size:CGSizeMake(80,80)]];
    [anchors addObject:[[CPMUIElementAnchor alloc] initWithType:CPMUIElementTypeConfirmButton
                                                       center:CGPointMake(w*0.85,h*0.82) size:CGSizeMake(80,40)]];
    [anchors addObject:[[CPMUIElementAnchor alloc] initWithType:CPMUIElementTypeCancelButton
                                                       center:CGPointMake(w*0.65,h*0.82) size:CGSizeMake(80,40)]];
    cal.anchors = [anchors copy];
    return cal;
}

+ (instancetype)calibrationFromJSON:(NSDictionary<NSString*,id> *)json {
    if (!json) return nil;
    CPMUICalibration *cal = [[self alloc] init];
    cal.calibrationID = json[@"calibrationID"] ?: @"unknown";
    NSDictionary *ss = json[@"screenSize"];
    if (ss) {
        cal.screenSize = CGSizeMake([ss[@"width"] doubleValue], [ss[@"height"] doubleValue]);
    }
    cal.scaleFactor = [json[@"scaleFactor"] doubleValue];
    cal.isLandscape = [json[@"isLandscape"] boolValue];
    NSMutableArray<CPMUIElementAnchor *> *anchors = [NSMutableArray array];
    for (NSDictionary *a in json[@"anchors"]) {
        CPMUIElementAnchor *anchor = [CPMUIElementAnchor anchorFromDictionary:a];
        if (anchor) [anchors addObject:anchor];
    }
    cal.anchors = [anchors copy];
    return cal;
}

- (NSDictionary<NSString*,id> *)toJSON {
    NSMutableDictionary *j = [NSMutableDictionary dictionary];
    j[@"calibrationID"] = self.calibrationID;
    j[@"screenSize"] = @{@"width": @(self.screenSize.width), @"height": @(self.screenSize.height)};
    j[@"scaleFactor"] = @(self.scaleFactor);
    j[@"isLandscape"] = @(self.isLandscape);
    NSMutableArray *arr = [NSMutableArray array];
    for (CPMUIElementAnchor *a in self.anchors) [arr addObject:[a toDictionary]];
    j[@"anchors"] = arr;
    return [j copy];
}

- (CPMUIElementAnchor *)anchorForType:(CPMUIElementType)type {
    for (CPMUIElementAnchor *a in self.anchors) {
        if (a.elementType == type) return a;
    }
    return nil;
}

- (CGPoint)mappedPositionFromImagePosition:(CGPoint)imagePos roiRect:(CGRect)roiScreenRect {
    // Map image-space position (0..1 within ROI) to screen coordinates
    CGFloat rx = roiScreenRect.origin.x + imagePos.x * roiScreenRect.size.width;
    CGFloat ry = roiScreenRect.origin.y + imagePos.y * roiScreenRect.size.height;
    return CGPointMake(rx, ry);
}

- (void)setAnchor:(CPMUIElementAnchor *)anchor forType:(CPMUIElementType)type {
    NSMutableArray *newAnchors = [NSMutableArray arrayWithArray:self.anchors];
    BOOL found = NO;
    for (NSInteger i=0; i<newAnchors.count; i++) {
        if (newAnchors[i].elementType == type) {
            newAnchors[i] = anchor;
            found = YES;
            break;
        }
    }
    if (!found) [newAnchors addObject:anchor];
    self.anchors = [newAnchors copy];
}

- (void)shiftAllAnchorsBy:(CGPoint)delta {
    NSMutableArray *newAnchors = [NSMutableArray arrayWithCapacity:self.anchors.count];
    for (CPMUIElementAnchor *a in self.anchors) {
        CPMUIElementAnchor *newA = [a copy];
        newA.center = CGPointMake(a.center.x+delta.x, a.center.y+delta.y);
        if (a.elementType >= CPMUIElementTypeRedSlider &&
            a.elementType <= CPMUIElementTypeRotateSlider) {
            newA.sliderMinX += delta.x;
            newA.sliderMaxX += delta.x;
            newA.sliderMinY += delta.y;
            newA.sliderMaxY += delta.y;
        }
        [newAnchors addObject:newA];
    }
    self.anchors = [newAnchors copy];
}

- (void)saveToUserDefaults {
    NSString *key = [NSString stringWithFormat:@"cpm_calibration_%@", self.calibrationID];
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud setObject:[self toJSON] forKey:key];
}

+ (instancetype)loadFromUserDefaults:(NSString *)calibrationID {
    if (!calibrationID) return nil;
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    NSDictionary *json = [ud objectForKey:[NSString stringWithFormat:@"cpm_calibration_%@", calibrationID]];
    if (json) return [self calibrationFromJSON:json];
    return nil;
}

- (id)copyWithZone:(NSZone *)zone {
    CPMUICalibration *copy = [[CPMUICalibration allocWithZone:zone] init];
    copy.calibrationID = self.calibrationID;
    copy.screenSize = self.screenSize;
    copy.scaleFactor = self.scaleFactor;
    copy.isLandscape = self.isLandscape;
    NSMutableArray *newAnchors = [NSMutableArray arrayWithCapacity:self.anchors.count];
    for (CPMUIElementAnchor *a in self.anchors) {
        [newAnchors addObject:[a copyWithZone:zone]];
    }
    copy.anchors = [newAnchors copy];
    return copy;
}

@end
