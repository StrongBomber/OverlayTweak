/**
 * CPMExecutionController.h
 * Execution Controller & Safety System.
 * Background-thread execution for automation with real-time progress,
 * emergency stop, and pause/resume capabilities.
 */
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@class CPMVinylShape;
@class CPMShapeDecomposer;
@class CPMTouchInjector;
@class CPMUICalibration;

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, CPMAutomationStep) {
    CPMAutomationStepNone = 0,
    CPMAutomationStepLoadingImage = 1,
    CPMAutomationStepDecomposingImage = 2,
    CPMAutomationStepPlacingLayers = 3,
    CPMAutomationStepPaused = 4,
    CPMAutomationStepCompleted = 5,
    CPMAutomationStepStopped = 6,
    CPMAutomationStepFailed = 7,
};

@protocol CPMExecutionControllerDelegate <NSObject>
@optional
- (void)controller:(id)controller didUpdateProgress:(CGFloat)progress;
- (void)controller:(id)controller didChangeState:(CPMAutomationStep)state;
- (void)controller:(id)controller didPlaceLayer:(NSUInteger)layerIndex total:(NSUInteger)total;
- (void)controller:(id)controller didEncounterError:(NSError *)error;
- (void)controllerDidRequestEmergencyStop:(id)controller;
@end

@interface CPMExecutionController : NSObject

@property (nonatomic, weak, nullable) id<CPMExecutionControllerDelegate> delegate;
@property (nonatomic, assign, readonly) CPMAutomationStep currentState;
@property (nonatomic, assign, readonly) CGFloat progress; // 0.0 - 1.0
@property (nonatomic, assign, readonly) NSUInteger layersPlaced;
@property (nonatomic, assign, readonly) NSUInteger totalLayers;
@property (nonatomic, assign, readonly) BOOL isRunning;
@property (nonatomic, assign, readonly) BOOL isPaused;
@property (nonatomic, assign, readonly) BOOL emergencyStopActive;

@property (nonatomic, strong, nullable) UIImage *referenceImage;
@property (nonatomic, assign, nullable) CGRect referenceROIRect;

// Configuration
@property (nonatomic, assign) NSInteger maxLayers;              // Default: 200
@property (nonatomic, assign) NSTimeInterval touchDelayMs;     // Default: 15ms
@property (nonatomic, assign) BOOL respectLayerLimit;          // Stop at CPM layer limit

// Dependencies (injected for testing)
@property (nonatomic, strong, nullable) CPMShapeDecomposer *decomposer;
@property (nonatomic, strong, nullable) CPMTouchInjector *injector;
@property (nonatomic, strong, nullable) CPMUICalibration *calibration;

// Actions
- (void)startAutomationWithImage:(UIImage *)image roiRect:(CGRect)roiRect;
- (void)pauseAutomation;
- (void)resumeAutomation;
- (void)stopAutomation;
- (void)emergencyStop;
- (void)setMaxLayers:(NSInteger)limit;
- (void)setTouchDelay:(NSTimeInterval)ms;

// Progress callback (alternative to delegate)
@property (nonatomic, copy, nullable) void (^progressHandler)(CGFloat progress, NSUInteger placed, NSUInteger total);
@property (nonatomic, copy, nullable) void (^stateHandler)(CPMAutomationStep state);

// Status
- (NSString *)statusDescription;
- (void)reset;

@end

NS_ASSUME_NONNULL_END
