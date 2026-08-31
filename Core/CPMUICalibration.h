/**
 * CPMUICalibration.h
 * CPM UI Layout Mapper & Calibration Engine.
 * Maps CPM vinyl editor UI elements to screen coordinates.
 * Stores anchors in JSON for configurable calibration per device/orientation.
 */
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, CPMUIElementType) {
    CPMUIElementTypeAddShape = 0,
    CPMUIElementTypeShapeSelector = 1,
    CPMUIElementTypeColorPicker = 2,
    CPMUIElementTypeRedSlider = 3,
    CPMUIElementTypeGreenSlider = 4,
    CPMUIElementTypeBlueSlider = 5,
    CPMUIElementTypeScaleSlider = 6,
    CPMUIElementTypeRotateSlider = 7,
    CPMUIElementTypeMoveJoystick = 8,
    CPMUIElementTypeConfirmButton = 9,
    CPMUIElementTypeCancelButton = 10,
    CPMUIElementTypeLayerListView = 11,
    CPMUIElementTypeZoomControl = 12,
};

@interface CPMUIElementAnchor : NSObject

@property (nonatomic, assign) CPMUIElementType elementType;
@property (nonatomic, assign) CGPoint center;        // Center point of UI element
@property (nonatomic, assign) CGSize size;          // Approximate size of element
@property (nonatomic, assign) CGFloat sliderMinX;   // For sliders: min handle position X
@property (nonatomic, assign) CGFloat sliderMaxX;   // For sliders: max handle position X
@property (nonatomic, assign) CGFloat sliderMinY;   // For sliders: min handle position Y
@property (nonatomic, assign) CGFloat sliderMaxY;
@property (nonatomic, copy, nullable) NSString *displayName;
@property (nonatomic, assign) BOOL isValid;

- (instancetype)initWithType:(CPMUIElementType)type center:(CGPoint)c size:(CGSize)s;
- (BOOL)containsPoint:(CGPoint)point;
- (NSDictionary<NSString*,id> *)toDictionary;
+ (instancetype)anchorFromDictionary:(NSDictionary<NSString*,id> *)dict;

@end

@interface CPMUICalibration : NSObject

@property (nonatomic, copy, readonly) NSString *calibrationID;
@property (nonatomic, assign, readonly) CGSize screenSize;
@property (nonatomic, assign, readonly) CGFloat scaleFactor; // Calibration resolution / actual screen
@property (nonatomic, copy, readonly) NSArray<CPMUIElementAnchor *> *anchors;
@property (nonatomic, assign, readonly) BOOL isLandscape;

+ (instancetype)defaultCalibrationForScreenSize:(CGSize)screenSize;
+ (instancetype)calibrationFromJSON:(NSDictionary<NSString*,id> *)json;
- (NSDictionary<NSString*,id> *)toJSON;

- (nullable CPMUIElementAnchor *)anchorForType:(CPMUIElementType)type;
- (CGPoint)mappedPositionFromImagePosition:(CGPoint)imagePos roiRect:(CGRect)roiScreenRect;
- (void)setAnchor:(CPMUIElementAnchor *)anchor forType:(CPMUIElementType)type;
- (void)shiftAllAnchorsBy:(CGPoint)delta;

// Save/load from UserDefaults
- (void)saveToUserDefaults;
+ (nullable instancetype)loadFromUserDefaults:(NSString *)calibrationID;

@end

NS_ASSUME_NONNULL_END
