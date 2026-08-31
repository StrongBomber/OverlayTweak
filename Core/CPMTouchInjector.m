/**
 * CPMTouchInjector.m
 * Touch Injection & Macro Automation System implementation.
 *
 * Uses IOHIDEvent APIs for low-level touch synthesis.
 * Also supports PTFakeTouch-style injection via private APIs.
 *
 * Import note: Requires linking against IOKit.framework and
 * possibly PrivateFrameworks (GraphicsServices) for full functionality.
 * Use with caution - may require jailbreak or special entitlements.
 */

#import "CPMTouchInjector.h"
#import <QuartzCore/QuartzCore.h>
#import <IOKit/IOKitLib.h>
#import <IOKit/hidsystem/IOHIDLib.h>
#import <mach/mach.h>

#pragma mark - Utility

static CGFloat clamp(CGFloat v, CGFloat min, CGFloat max) {
    return MAX(min, MIN(max, v));
}

static CGFloat mapRange(CGFloat value, CGFloat fromMin, CGFloat fromMax, CGFloat toMin, CGFloat toMax) {
    CGFloat normalized = (value - fromMin) / (fromMax - fromMin);
    return toMin + normalized * (toMax - toMin);
}

#pragma mark - CPMTouchEvent

@implementation CPMTouchEvent

- (instancetype)initWithLocation:(CGPoint)loc phase:(CPMTouchEventPhase)phase {
    self = [super init];
    if (self) {
        _location = loc;
        _timestamp = [[NSDate date] timeIntervalSince1970];
        _phase = phase;
        _touchId = arc4random_uniform(10000) + 1;
    }
    return self;
}

+ (instancetype)tapAt:(CGPoint)loc {
    CPMTouchEvent *e = [[self alloc] initWithLocation:loc phase:CPMTouchEventPhaseBegan];
    e.timestamp = [[NSDate date] timeIntervalSince1970];
    return e;
}

+ (instancetype)dragFrom:(CGPoint)from to:(CGPoint)to steps:(NSInteger)steps {
    NSMutableArray<CPMTouchEvent *> *events = [NSMutableArray array];
    for (NSInteger i = 0; i <= steps; i++) {
        CGFloat t = (CGFloat)i / steps;
        CGPoint pt = CGPointMake(from.x + (to.x - from.x) * t,
                                  from.y + (to.y - from.y) * t);
        CPMTouchEvent *e = [[self alloc] initWithLocation:pt phase:CPMTouchEventPhaseMoved];
        e.timestamp = [[NSDate date] timeIntervalSince1970] + i * 0.015;
        [events addObject:e];
    }
    // Add end event
    CPMTouchEvent *end = [[self alloc] initWithLocation:to phase:CPMTouchEventPhaseEnded];
    end.timestamp = [[NSDate date] timeIntervalSince1970] + (steps + 1) * 0.015;
    [events addObject:end];
    // Return first event as representative
    return events.firstObject;
}

+ (instancetype)longPressAt:(CGPoint)loc duration:(NSTimeInterval)duration {
    CPMTouchEvent *begin = [[self alloc] initWithLocation:loc phase:CPMTouchEventPhaseBegan];
    CPMTouchEvent *end = [[self alloc] initWithLocation:loc phase:CPMTouchEventPhaseEnded];
    end.timestamp = begin.timestamp + duration;
    // Return begin as representative
    return begin;
}

@end

#pragma mark - CPMTouchSequence

@implementation CPMTouchSequence

- (instancetype)initWithEvents:(NSArray<CPMTouchEvent *> *)events {
    self = [super init];
    if (self) {
        _events = [events copy];
        if (events.count > 0) {
            NSTimeInterval start = [events.firstObject timestamp];
            NSTimeInterval end = [events.lastObject timestamp];
            _totalDuration = end - start;
        }
    }
    return self;
}

+ (instancetype)tapSequenceAt:(CGPoint)loc {
    CPMTouchEvent *tap = [CPMTouchEvent tapAt:loc];
    return [[self alloc] initWithEvents:@[tap]];
}

+ (instancetype)dragSequenceFrom:(CGPoint)from to:(CGPoint)to {
    CPMTouchEvent *drag = [CPMTouchEvent dragFrom:from to:to steps:10];
    CPMTouchEvent *begin = [[CPMTouchEvent alloc] initWithLocation:from phase:CPMTouchEventPhaseBegan];
    CPMTouchEvent *end = [[CPMTouchEvent alloc] initWithLocation:to phase:CPMTouchEventPhaseEnded];
    end.timestamp = drag.timestamp + 0.015;
    return [[self alloc] initWithEvents:@[begin, drag, end]];
}

+ (instancetype)sliderDragSequenceAt:(CGPoint)sliderCenter fromValue:(CGFloat)fromValue toValue:(CGFloat)toValue sliderRange:(CGSize)range {
    CGFloat minX = sliderCenter.x - range.width * 0.5;
    CGFloat maxX = sliderCenter.x + range.width * 0.5;
    CGFloat fromX = mapRange(fromValue, 0, 1, minX, maxX);
    CGFloat toX = mapRange(toValue, 0, 1, minX, maxX);
    CGPoint from = CGPointMake(fromX, sliderCenter.y);
    CGPoint to = CGPointMake(toX, sliderCenter.y);
    return [self dragSequenceFrom:from to:to];
}

+ (instancetype)colorPickerSequenceAt:(CGPoint)loc red:(CGFloat)r green:(CGFloat)g blue:(CGFloat)b {
    // Simulate tapping the color picker
    CPMTouchSequence *tap = [self tapSequenceAt:loc];
    // In a full implementation, this would also simulate slider adjustments
    // for R, G, B values. Placeholder for now.
    return tap;
}

@end

#pragma mark - CPMTouchInjector

// Private IOHID system interface
static CFMachPortRef _touchEventPort = NULL;
static io_iterator_t _hidIterator = 0;
static IOHIDDeviceRef _defaultDevice = NULL;

@interface CPMTouchInjector ()
@property (nonatomic, assign, readwrite) BOOL emergencyStopActive;
@property (nonatomic, assign, readwrite) BOOL logTouchEvents;
@end

@implementation CPMTouchInjector

+ (instancetype)sharedInjector {
    static CPMTouchInjector *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[CPMTouchInjector alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _emergencyStopActive = NO;
        _logTouchEvents = NO;
        _eventDelayMs = 15.0;
        _screenScale = [UIScreen mainScreen].scale;
        _screenBounds = [UIScreen mainScreen].bounds.size;
        [self setupHIDAccess];
    }
    return self;
}

- (void)dealloc {
    [self cleanupHIDAccess];
}

- (void)setupHIDAccess {
    // Setup IOHID system for touch event injection
    // Note: This requires appropriate entitlements/permissions
    CFMutableSetRef devices = IOHIDeviceSetCreate(NULL);
    if (!devices) return;

    // Get the default touch device
    io_iterator_t iterator;
    CFMutableDictionaryRef matchingDict = IOOPCICollectionCreate(kCFAllocatorDefault);
    if (!matchingDict) return;

    IOHIDServiceGetMatchingServices(kIOMasterPortDefault, matchingDict, &iterator);
    _hidIterator = iterator;

    if (iterator) {
        io_object_t obj;
        while ((obj = IOIteratorNext(iterator))) {
            IOHIDDeviceRef device = (IOHIDDeviceRef)obj;
            if (device) {
                _defaultDevice = device;
                break;
            }
        }
    }

    CFRelease(devices);
    CFRelease(matchingDict);
}

- (void)cleanupHIDAccess {
    if (_hidIterator) {
        IOObjectRelease(_hidIterator);
        _hidIterator = 0;
    }
    _defaultDevice = NULL;
}

#pragma mark - Touch Synthesis

- (void)synthesizeTapAt:(CGPoint)screenPoint {
    if (self.emergencyStopActive) return;
    CGPoint pt = [self pointInWindowCoordinates:screenPoint];
    // Create and send tap events
    [self sendTouchEventAt:pt phase:CPMTouchEventPhaseBegan];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (!self.emergencyStopActive) {
            [self sendTouchEventAt:pt phase:CPMTouchEventPhaseEnded];
        }
    });
    if (self.logTouchEvents) OLLog(@"[TouchInjector] Tap at %.1f, %.1f", pt.x, pt.y);
}

- (void)synthesizeDragFrom:(CGPoint)fromPoint to:(CGPoint)toPoint {
    if (self.emergencyStopActive) return;
    CGPoint from = [self pointInWindowCoordinates:fromPoint];
    CGPoint to = [self pointInWindowCoordinates:toPoint];
    [self sendTouchEventAt:from phase:CPMTouchEventPhaseBegan];
    // Send intermediate moves
    for (int i = 1; i <= 10; i++) {
        CGFloat t = (CGFloat)i / 10;
        CGPoint pt = CGPointMake(from.x + (to.x - from.x) * t,
                                  from.y + (to.y - from.y) * t);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                     (int64_t)(i * self.eventDelayMs * NSEC_PER_SEC / 1000)),
                       dispatch_get_main_queue(), ^{
            if (!self.emergencyStopActive) {
                [self sendTouchEventAt:pt phase:CPMTouchEventPhaseMoved];
            }
        });
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                 (int64_t)(11 * self.eventDelayMs * NSEC_PER_SEC / 1000)),
                   dispatch_get_main_queue(), ^{
        if (!self.emergencyStopActive) {
            [self sendTouchEventAt:to phase:CPMTouchEventPhaseEnded];
        }
    });
}

- (void)synthesizeLongPressAt:(CGPoint)screenPoint duration:(NSTimeInterval)duration {
    if (self.emergencyStopActive) return;
    CGPoint pt = [self pointInWindowCoordinates:screenPoint];
    [self sendTouchEventAt:pt phase:CPMTouchEventPhaseBegan];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(duration * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (!self.emergencyStopActive) {
            [self sendTouchEventAt:pt phase:CPMTouchEventPhaseEnded];
        }
    });
}

- (void)synthesizeSliderAdjustAt:(CGPoint)sliderCenter fromValue:(CGFloat)fromValue toValue:(CGFloat)toValue sliderRange:(CGSize)range {
    if (self.emergencyStopActive) return;
    CGFloat minX = sliderCenter.x - range.width * 0.5;
    CGFloat maxX = sliderCenter.x + range.width * 0.5;
    CGFloat fromX = mapRange(fromValue, 0, 1, minX, maxX);
    CGFloat toX = mapRange(toValue, 0, 1, minX, maxX);
    CGPoint from = CGPointMake(fromX, sliderCenter.y);
    CGPoint to = CGPointMake(toX, sliderCenter.y);
    [self synthesizeDragFrom:from to:to];
}

- (void)sendTouchEventAt:(CGPoint)point phase:(CPMTouchEventPhase)phase {
    if (self.emergencyStopActive || !_defaultDevice) return;
    // Low-level touch event synthesis via IOHIDEvent
    // This is a placeholder - actual implementation would use IOHIDEventCreateDigitizerEvent
    // or similar private APIs for actual touch injection
    //
    // For non-jailbroken devices, you might use:
    // - A companion app with UI interaction (via CGEvent)
    // - Screen recording + computer vision for verification
    // - External hardware (Bluetooth touch simulator)
    //
    // For jailbreak devices, you can use:
    // - IOHIDEventCreateDigitizerEvent
    // - PTFakeTouch or similar libraries
    // - Substrate/Fishhook hooks into UIEvent handling

    if (self.logTouchEvents) {
        OLLog(@"[TouchInjector] Event: phase=%ld at (%.1f, %.1f)",
              (long)phase, point.x, point.y);
    }
}

#pragma mark - Sequence Execution

- (void)executeSequence:(CPMTouchSequence *)sequence completion:(void(^)(BOOL success))completion {
    if (self.emergencyStopActive || !sequence || sequence.events.count == 0) {
        if (completion) completion(NO);
        return;
    }

    dispatch_queue_t queue = dispatch_queue_create("com.overlaytweak.cpmtouch", DISPATCH_QUEUE_SERIAL);
    dispatch_async(queue, ^{
        NSTimeInterval startTime = [[NSDate date] timeIntervalSince1970];
        for (CPMTouchEvent *event in sequence.events) {
            if (self.emergencyStopActive) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (completion) completion(NO);
                });
                return;
            }
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                         (int64_t)((event.timestamp - startTime) * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                [self sendTouchEventAt:event.location
                                   phase:event.phase];
            });
        }
        // All events executed
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                     (int64_t)(sequence.totalDuration * NSEC_PER_SEC + 0.1 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            if (!self.emergencyStopActive && completion) {
                completion(YES);
            }
        });
    });
}

- (void)cancelCurrentInjection {
    self.emergencyStopActive = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        self.emergencyStopActive = NO;
    });
}

- (void)emergencyStop {
    [self cancelCurrentInjection];
    if (self.logTouchEvents) OLLog(@"[TouchInjector] EMERGENCY STOP");
}

#pragma mark - Coordinate Helpers

- (CGPoint)adjustPointForScreenScale:(CGPoint)point {
    return CGPointMake(point.x * self.screenScale, point.y * self.screenScale);
}

- (CGPoint)pointInWindowCoordinates:(CGPoint)point {
    // Convert from screen coordinates to window coordinates
    // For overlay windows at windowLevel + 100, touches go to underlying windows
    CGSize screenSize = [UIScreen mainScreen].bounds.size;
    return CGPointMake(point.x, screenSize.height - point.y); // Flip Y if needed
}

@end
