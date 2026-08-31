/**
 * OverlayTweak — shared macros, version, UserDefaults keys.
 * Extended for Car Parking Multiplayer (CPM) Image-to-Vinyl Automation.
 */

#ifndef OverlayCommon_h
#define OverlayCommon_h

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#define OLLog(fmt, ...) NSLog(@"[OverlayTweak] " fmt, ##__VA_ARGS__)
#define CPM_LOG(fmt, ...) NSLog(@"[CPM-Automation] " fmt, ##__VA_ARGS__)

static NSString * const kOLVersion = @"2.0.0-CPM-Automation";

/* ==========================================================================
 * Original OverlayTweak UserDefaults keys
 * ========================================================================== */
static NSString * const kDefaultsOpacity        = @"overlay_opacity";
static NSString * const kDefaultsPositionX      = @"overlay_position_x";
static NSString * const kDefaultsPositionY      = @"overlay_position_y";
static NSString * const kDefaultsScale          = @"overlay_scale";
static NSString * const kDefaultsRotation       = @"overlay_rotation";
static NSString * const kDefaultsImageBookmark  = @"overlay_image_data"; /* legacy */
static NSString * const kDefaultsIsLocked       = @"overlay_is_locked";
static NSString * const kDefaultsOverlayVisible = @"overlay_visible";
static NSString * const kDefaultsMenuX          = @"overlay_menu_x";
static NSString * const kDefaultsMenuY          = @"overlay_menu_y";
static NSString * const kDefaultsMenuHidden     = @"overlay_menu_hidden";
static NSString * const kDefaultsFlipH          = @"overlay_flip_h";
static NSString * const kDefaultsFlipV          = @"overlay_flip_v";
static NSString * const kDefaultsContentMode    = @"overlay_content_mode";
static NSString * const kDefaultsWelcomeShown   = @"overlay_welcome_shown";
static NSString * const kDefaultsHasOpacity     = @"overlay_has_opacity";
static NSString * const kDefaultsSizeMode       = @"overlay_size_mode";   /* 0 = follow image, 1 = custom */
static NSString * const kDefaultsCustomWidth    = @"overlay_custom_w";
static NSString * const kDefaultsCustomHeight   = @"overlay_custom_h";
static NSString * const kDefaultsShowsBorder    = @"overlay_shows_border";
static NSString * const kDefaultsShowsGrid      = @"overlay_shows_grid";
static NSString * const kDefaultsPitch          = @"overlay_pitch";
static NSString * const kDefaultsYaw            = @"overlay_yaw";
static NSString * const kDefaultsCropL          = @"overlay_crop_l";
static NSString * const kDefaultsCropR          = @"overlay_crop_r";
static NSString * const kDefaultsCropT          = @"overlay_crop_t";
static NSString * const kDefaultsCropB          = @"overlay_crop_b";
static NSString * const kDefaultsWarpPts        = @"overlay_warp_pts";

/* ==========================================================================
 * CPM Automation UserDefaults keys
 * ========================================================================== */
static NSString * const kCPMDefaultsUIAnchors     = @"cpm_ui_anchors";
static NSString * const kCPMDefaultsAutoDrawActive = @"cpm_autodraw_active";
static NSString * const kCPMDefaultsAutoDrawPaused = @"cpm_autodraw_paused";
static NSString * const kCPMDefaultsLayerLimit    = @"cpm_layer_limit";
static NSString * const kCPMDefaultsTouchDelay    = @"cpm_touch_delay_ms";
static NSString * const kCPMDefaultsReferenceImage = @"cpm_reference_image";
static NSString * const kCPMDefaultsROIRect       = @"cpm_roi_rect";
static NSString * const kCPMDefaultsCalibrationVersion = @"cpm_calibration_version";
static NSString * const kCPMDefaultsLastSessionShapes = @"cpm_last_session_shapes";
static NSString * const kCPMDefaultsEmergencyStop = @"cpm_emergency_stop";

/* ==========================================================================
 * CPM Shape Primitive Types (matching CPM's vinyl editor)
 * ========================================================================== */
typedef NS_ENUM(NSInteger, CPMShapeType) {
    CPMShapeTypeSquare = 0,
    CPMShapeTypeCircle = 1,
    CPMShapeTypeTriangle = 2,
    CPMShapeTypeLine = 3,
    CPMShapeTypePolygon = 4,
    CPMShapeTypeCustom = 5
};

/* ==========================================================================
 * CPM Color Quantization Options
 * ========================================================================== */
typedef NS_ENUM(NSInteger, CPMColorQuantizationMode) {
    CPMColorQuantizationKMeans = 0,    // K-Means clustering
    CPMColorQuantizationMedianCut = 1, // Median cut algorithm
    CPMColorQuantizationPopularity = 2 // Popularity-based quantization
};

/* ==========================================================================
 * CPM Execution States
 * ========================================================================== */
typedef NS_ENUM(NSInteger, CPMExecutionState) {
    CPMExecutionStateIdle = 0,
    CPMExecutionStateProcessing = 1,
    CPMExecutionStatePlacingLayers = 2,
    CPMExecutionStatePaused = 3,
    CPMExecutionStateEmergencyStop = 4,
    CPMExecutionStateCompleted = 5,
    CPMExecutionStateFailed = 6
};

/* ==========================================================================
 * CPM UI Element Identifiers (for calibration mapping)
 * ========================================================================== */
typedef NS_ENUM(NSInteger, CPMUIElementID) {
    CPMUIElementAddShape = 0,
    CPMUIElementShapeSelector = 1,
    CPMUIElementColorPicker = 2,
    CPMUIElementRedSlider = 3,
    CPMUIElementGreenSlider = 4,
    CPMUIElementBlueSlider = 5,
    CPMUIElementScaleSlider = 6,
    CPMUIElementRotateSlider = 7,
    CPMUIElementMoveJoystick = 8,
    CPMUIElementConfirmButton = 9,
    CPMUIElementCancelButton = 10,
    CPMUIElementLayerListView = 11,
    CPMUIElementZoomControl = 12
};

/* ==========================================================================
 * CPM Screen Orientation
 * ========================================================================== */
typedef NS_ENUM(NSInteger, CPMScreenOrientation) {
    CPMScreenOrientationPortrait = 0,
    CPMScreenOrientationLandscapeLeft = 1,
    CPMScreenOrientationLandscapeRight = 2,
    CPMScreenOrientationPortraitUpsideDown = 3
};

#endif /* OverlayCommon_h */
