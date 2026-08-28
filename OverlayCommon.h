/**
 * OverlayTweak — shared macros, version, UserDefaults keys.
 */

#ifndef OverlayCommon_h
#define OverlayCommon_h

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#define OLLog(fmt, ...) NSLog(@"[OverlayTweak] " fmt, ##__VA_ARGS__)

static NSString * const kOLVersion = @"1.2.0";

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

#endif /* OverlayCommon_h */
