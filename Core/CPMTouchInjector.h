/**
 * CPMTouchInjector.h
 * Touch Injection & Macro Automation System.
 * Implements low-level iOS touch synthesis using IOHIDEvent APIs
 * for automating CPM vinyl editor interactions.
 */
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <IOKit/hidsystem/IOHIDLib.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, CPMTouchEventPhase) {
    CPMTouchEventPhaseBegan,
    CPMTouchEventPhaseMoved,
    CPMTouchEventPhaseEnded,
    CPMTouchEventPhaseCancelled,
};

typedef NS_ENUM(NSInteger, CPMTouchActionType) {
    CPMTouchActionTypeTap,
    CPMTouchActionTypeDrag,
    CPMTouchActionTypeLongPress,
    CPMTouchActionTypeSliderDrag,
};

@interface CPMTouchEvent : NSObject

@property (nonatomic, assign) CGPoint location;
@property (nonatomic, assign) NSTimeInterval timestamp;
@property (nonatomic, assign) CPMTouchEventPhase phase;
@property (nonatomic, assign) NSInteger touchId; // Synthetic touch identifier
@property (nonatomic, copy, nullable) NSString *description;

- (instancetype)initWithLocation:(CGPoint)loc phase:(CPMTouchEventPhase)phase;
+ (instancetype)tapAt:(CGPoint)loc;
+ (instancetype)dragFrom:(CGPoint)from to:(CGPoint)to steps:(NSInteger)steps;
+ (instancetype)longPressAt:(CGPoint)loc duration:(NSTimeInterval)duration;

@end

@interface CPMTouchSequence : NSObject

@property (nonatomic, copy, readonly) NSArray<CPMTouchEvent *> *events;
@property (nonatomic, assign, readonly) NSTimeInterval totalDuration;

- (instancetype)sequenceWithEvents:(NSArray<CPMTouchEvent *> *)events;
+ (instancetype)tapSequenceAt:(CGPoint)loc;
+ (instancetype)dragSequenceFrom:(CGPoint)from to:(CGPoint)to;
+ (instancetype)sliderDragSequenceAt:(CGPoint)sliderCenter fromValue:(CGFloat)from toValue:(CGFloat)to sliderRange:(CGSize)range;
+ (instancetype)colorPickerSequenceAt:(CGPoint)loc red:(CGFloat)r green:(CGFloat)g blue:(CGFloat)b;

@end

@interface CPMTouchInjector : NSObject

+ (instancetype)sharedInjector;
@property (nonatomic, assign, readonly) BOOL isTouching;
@property (nonatomic, assign) NSTimeInterval eventDelayMs; // Delay between touch events (default 15ms)

// Core touch synthesis
- (void)synthesizeTapAt:(CGPoint)screenPoint;
- (void)synthesizeDragFrom:(CGPoint)fromPoint to:(CGPoint)toPoint;
- (void)synthesizeLongPressAt:(CGPoint)screenPoint duration:(NSTimeInterval)duration;
- (void)synthesizeSliderAdjustAt:(CGPoint)sliderCenter fromValue:(CGFloat)fromValue toValue:(CGFloat)toValue sliderRange:(CGSize)range;

// Execute a pre-built sequence
- (void)executeSequence:(CPM

TouchSequence *)sequence completion:(void(^)(BOOL success))completion;
- (void)cancelCurrentInjection;

// Emergency stop
- (void)emergencyStop;
@property (nonatomic, assign, readonly) BOOL emergencyStopActive;

// Calibration helpers
- (CGPoint)adjustPointForScreenScale:(CGPoint)point;
- (CGPoint)pointInWindowCoordinates:(CGPoint)point;

// Device info
@property (nonatomic, assign, readonly) CGFloat screenScale;
@property (nonatomic, assign, readonly) CGSize screenBounds;

// Touch logging (for debugging)
@property (nonatomic, assign) BOOL logTouchEvents;

@end

NS_ASSUME_NONNULL_END
