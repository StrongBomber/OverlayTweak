/**
 * CPMExecutionController.m
 * Execution Controller & Safety System implementation.
 */
#import "CPMExecutionController.h"
#import "CPMShapeDecomposer.h"
#import "CPMTouchInjector.h"
#import "CPMUICalibration.h"
#import "CPMVinylShape.h"
#import "OverlayCommon.h"

@interface CPMExecutionController ()
@property (nonatomic, assign, readwrite) CPMAutomationStep currentState;
@property (nonatomic, assign, readwrite) CGFloat progress;
@property (nonatomic, assign, readwrite) NSUInteger layersPlaced;
@property (nonatomic, assign, readwrite) NSUInteger totalLayers;
@property (nonatomic, assign, readwrite) BOOL isRunning;
@property (nonatomic, assign, readwrite) BOOL isPaused;
@property (nonatomic, assign, readwrite) BOOL emergencyStopActive;
@property (nonatomic, strong) NSOperationQueue *execQueue;
@property (nonatomic, strong) NSMutableArray<CPMVinylShape*> *shapesQueue;
@property (nonatomic, copy) NSString *calibrationID;
@end

@implementation CPMExecutionController

- (instancetype)init {
    self = [super init];
    if (self) {
        _execQueue = [[NSOperationQueue alloc] init];
        _execQueue.maxConcurrentOperationCount = 1;
        _execQueue.qualityOfService = NSQualityOfServiceUserInitiated;
        _currentState = CPMAutomationStepNone;
        _progress = 0;
        _layersPlaced = 0;
        _totalLayers = 0;
        _isRunning = NO;
        _isPaused = NO;
        _emergencyStopActive = NO;
        _maxLayers = 200;
        _touchDelayMs = 15.0;
        _respectLayerLimit = YES;
        _decomposer = [CPMShapeDecomposer sharedDecomposer];
        _injector = [CPMTouchInjector sharedInjector];
        _injector.eventDelayMs = _touchDelayMs;
        _calibration = [CPMUICalibration defaultCalibrationForScreenSize:[UIScreen mainScreen].bounds.size];
        _calibrationID = _calibration.calibrationID;
        _shapesQueue = [NSMutableArray array];
    }
    return self;
}

- (void)dealloc {
    [_execQueue cancelAllOperations];
}

- (void)startAutomationWithImage:(UIImage *)image roiRect:(CGRect)roiRect {
    if ([self isRunning]) return;
    
    self.referenceImage = image;
    self.referenceROIRect = roiRect;
    self.emergencyStopActive = NO;
    self.isPaused = NO;
    self.currentState = CPMAutomationStepLoadingImage;
    self.progress = 0;
    self.layersPlaced = 0;
    
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([self.delegate respondsToSelector:@selector(controller:didChangeState:)]) {
            [self.delegate controller:self didChangeState:self.currentState];
        }
    });
    
    self.isRunning = YES;
    
    [self.execQueue addOperationWithBlock:^{
        @autoreleasepool {
            [self executeAutomation];
        }
    }];
}

- (void)executeAutomation {
    if (self.emergencyStopActive) {
        [self finishWithState:CPMAutomationStepStopped];
        return;
    }
    
    // Step 1: Load & validate image
    self.currentState = CPMAutomationStepDecomposingImage;
    [self notifyState];
    
    CPMShapeDecompositionConfig *config = [CPMShapeDecompositionConfig configForCarBodyWithMaxLayers:self.maxLayers];
    config.roiRect = self.referenceROIRect;
    
    // Step 2: Decompose image
    __block CPMShapeDecompositionResult *result = nil;
    __block NSError *decomposeError = nil;
    
    dispatch_group_t group = dispatch_group_create();
    dispatch_group_enter(group);
    
    __weak typeof(self) weakSelf = self;
    self.decomposer.progressCallback = ^(CGFloat p) {
        dispatch_async(dispatch_get_main_queue(), ^{
            weakSelf.progress = p * 0.3; // 0-30% for decomposition
            [weakSelf notifyProgress];
        });
    };
    
    [self.decomposer decomposeImage:self.referenceImage withConfig:config completion:^(CPMShapeDecompositionResult *res, NSError *err) {
        result = res;
        decomposeError = err;
        dispatch_group_leave(group);
    }];
    
    dispatch_group_wait(group, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(30.0 * NSEC_PER_SEC)));
    
    if (self.emergencyStopActive || self.isPaused) {
        [self finishWithState:self.isPaused ? CPMAutomationStepPaused : CPMAutomationStepStopped];
        return;
    }
    
    if (decomposeError || !result || ![result meetsQualityThreshold]) {
        NSError *err = decomposeError ?: [NSError errorWithDomain:@"CPMExecutionController"
                                                            code:-1
                                                        userInfo:@{NSLocalizedDescriptionKey:@"Decomposition failed or low quality"}];
        [self finishWithState:CPMAutomationStepFailed];
        if ([self.delegate respondsToSelector:@selector(controller:didEncounterError:)]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.delegate controller:self didEncounterError:err];
            });
        }
        return;
    }
    
    // Step 3: Place layers
    self.currentState = CPMAutomationStepPlacingLayers;
    [self notifyState];
    
    self.shapesQueue = [NSMutableArray arrayWithArray:result.shapes];
    self.totalLayers = MIN(self.shapesQueue.count, self.maxLayers);
    self.progress = 0.3; // Completed decomposition phase
    
    NSUInteger layerIndex = 0;
    for (CPMVinylShape *shape in self.shapesQueue) {
        if (layerIndex >= self.maxLayers) break;
        if (self.emergencyStopActive || self.isPaused) {
            if (self.isPaused) {
                [self finishWithState:CPMAutomationStepPaused];
            } else {
                [self finishWithState:CPMAutomationStepStopped];
            }
            return;
        }
        
        // Place the layer via touch injection
        [self placeShape:shape atIndex:layerIndex total:self.totalLayers];
        layerIndex++;
    }
    
    if (!self.emergencyStopActive && !self.isPaused) {
        [self finishWithState:CPMAutomationStepCompleted];
    }
}

- (void)placeShape:(CPMVinylShape *)shape atIndex:(NSUInteger)index total:(NSUInteger)total {
    // Convert shape parameters to touch actions
    CGPoint screenPos = [self calibration].mappedPositionFromImagePosition:shape.position
                                                                 roiRect:self.referenceROIRect;
    
    // 1. Tap "Add Shape" button
    CPMUIElementAnchor *addAnchor = [[self calibration] anchorForType:CPMUIElementTypeAddShape];
    if (addAnchor) {
        [self.injector synthesizeTapAt:addAnchor.center];
        [self sleepForTouchDelay];
    }
    
    // 2. Select shape type
    CPMUIElementAnchor *shapeSelector = [[self calibration] anchorForType:CPMUIElementTypeShapeSelector];
    if (shapeSelector && shape.shapeType != CPMShapeTypeSquare) {
        // Tap near the appropriate shape type in selector
        CGPoint typePos = CGPointMake(shapeSelector.center.x,
                                      shapeSelector.center.y + shape.shapeType * 40);
        [self.injector synthesizeTapAt:typePos];
        [self sleepForTouchDelay];
    }
    
    // 3. Set position via move joystick
    CPMUIElementAnchor *joystick = [[self calibration] anchorForType:CPMUIElementTypeMoveJoystick];
    if (joystick) {
        // Calculate joystick positions based on shape position relative to ROI center
        CGPoint roiCenter = CGPointMake(self.referenceROIRect.origin.x + self.referenceROIRect.size.width/2,
                                        self.referenceROIRect.origin.y + self.referenceROIRect.size.height/2);
        CGFloat dx = screenPos.x - roiCenter.x;
        CGFloat dy = screenPos.y - roiCenter.y;
        // Move joystick in appropriate direction (simplified)
        CGPoint joystickTarget = CGPointMake(joystick.center.x + dx * 0.5,
                                              joystick.center.y + dy * 0.5);
        [self.injector synthesizeDragFrom:joystick.center to:joystickTarget];
        [self sleepForTouchDelay];
    }
    
    // 4. Set color via sliders
    if (shape.shapeType != CPMShapeTypeLine || shape.scale.width > 10) {
        CPMUIElementAnchor *redSlider = [[self calibration] anchorForType:CPMUIElementTypeRedSlider];
        CPMUIElementAnchor *greenSlider = [[self calibration] anchorForType:CPMUIElementTypeGreenSlider];
        CPMUIElementAnchor *blueSlider = [[self calibration] anchorForType:CPMUIElementTypeBlueSlider];
        
        if (redSlider) {
            CGFloat redVal = clamp(shape.red / 255.0, 0, 1);
            CGSize sliderRange = CGSizeMake(redSlider.size.width, 0);
            [self.injector synthesizeSliderAdjustAt:redSlider.center
                                           fromValue:0.5 toValue:redVal sliderRange:sliderRange];
            [self sleepForTouchDelay];
        }
        if (greenSlider) {
            CGFloat greenVal = clamp(shape.green / 255.0, 0, 1);
            CGSize sliderRange = CGSizeMake(greenSlider.size.width, 0);
            [self.injector synthesizeSliderAdjustAt:greenSlider.center
                                           fromValue:0.5 toValue:greenVal sliderRange:sliderRange];
            [self sleepForTouchDelay];
        }
        if (blueSlider) {
            CGFloat blueVal = clamp(shape.blue / 255.0, 0, 1);
            CGSize sliderRange = CGSizeMake(blueSlider.size.width, 0);
            [self.injector synthesizeSliderAdjustAt:blueSlider.center
                                           fromValue:0.5 toValue:blueVal sliderRange:sliderRange];
            [self sleepForTouchDelay];
        }
    }
    
    // 5. Set scale & rotation
    CPMUIElementAnchor *scaleSlider = [[self calibration] anchorForType:CPMUIElementTypeScaleSlider];
    CPMUIElementAnchor *rotateSlider = [[self calibration] anchorForType:CPMUIElementTypeRotateSlider];
    
    if (scaleSlider) {
        CGFloat scaleVal = clamp(shape.scale.width / 100.0, 0.1, 2.0) / 2.0; // Normalize
        CGSize sliderRange = CGSizeMake(scaleSlider.size.width, 0);
        [self.injector synthesizeSliderAdjustAt:scaleSlider.center
                                       fromValue:0.5 toValue:scaleVal sliderRange:sliderRange];
        [self sleepForTouchDelay];
    }
    
    if (rotateSlider) {
        CGFloat rotVal = clamp(shape.rotationDegrees / 360.0, 0, 1);
        CGSize sliderRange = CGSizeMake(rotateSlider.size.width, 0);
        [self.injector synthesizeSliderAdjustAt:rotateSlider.center
                                       fromValue:0.5 toValue:rotVal sliderRange:sliderRange];
        [self sleepForTouchDelay];
    }
    
    // 6. Confirm layer
    CPMUIElementAnchor *confirmBtn = [[self calibration] anchorForType:CPMUIElementTypeConfirmButton];
    if (confirmBtn) {
        [self.injector synthesizeTapAt:confirmBtn.center];
        [self sleepForTouchDelay];
    }
    
    // Update progress
    self.layersPlaced = index + 1;
    self.progress = 0.3 + 0.7 * ((CGFloat)(index+1) / (CGFloat)total);
    [self notifyProgress];
    [self notifyLayerPlaced:index total:total];
}

- (void)sleepForTouchDelay {
    // Small delay between touch operations
    usleep((useconds_t)(self.touchDelayMs * 1000));
}

- (void)pauseAutomation {
    if (![self isRunning] || self.isPaused || self.emergencyStopActive) return;
    self.isPaused = YES;
    self.currentState = CPMAutomationStepPaused;
    [self notifyState];
    [self.injector emergencyStop];
}

- (void)resumeAutomation {
    if (![self isRunning] || !self.isPaused || self.emergencyStopActive) return;
    self.isPaused = NO;
    self.currentState = CPMAutomationStepPlacingLayers;
    [self notifyState];
    // Resume execution - shapes queue continues
}

- (void)stopAutomation {
    if (![self isRunning]) return;
    self.emergencyStopActive = YES;
    [self.injector emergencyStop];
}

- (void)emergencyStop {
    [self stopAutomation];
    if ([self.delegate respondsToSelector:@selector(controllerDidRequestEmergencyStop:)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate controllerDidRequestEmergencyStop:self];
        });
    }
}

- (void)setMaxLayers:(NSInteger)limit {
    _maxLayers = MAX(1, MIN(300, limit));
}

- (void)setTouchDelay:(NSTimeInterval)ms {
    _touchDelayMs = MAX(5, MIN(500, ms));
    self.injector.eventDelayMs = _touchDelayMs;
}

- (void)finishWithState:(CPMAutomationStep)state {
    self.currentState = state;
    self.isRunning = NO;
    [self notifyState];
    if (self.progressHandler) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.progressHandler(self.progress, self.layersPlaced, self.totalLayers);
        });
    }
    if (self.stateHandler) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.stateHandler(state);
        });
    }
}

- (void)notifyProgress {
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([self.delegate respondsToSelector:@selector(controller:didUpdateProgress:)]) {
            [self.delegate controller:self didUpdateProgress:self.progress];
        }
        if (self.progressHandler) {
            self.progressHandler(self.progress, self.layersPlaced, self.totalLayers);
        }
    });
}

- (void)notifyState {
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([self.delegate respondsToSelector:@selector(controller:didChangeState:)]) {
            [self.delegate controller:self didChangeState:self.currentState];
        }
        if (self.stateHandler) {
            self.stateHandler(self.currentState);
        }
    });
}

- (void)notifyLayerPlaced:(NSUInteger)index total:(NSUInteger)total {
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([self.delegate respondsToSelector:@selector(controller:didPlaceLayer:atIndex:total:)]) {
            [self.delegate controller:self didPlaceLayer:index total:total];
        }
    });
}

- (NSString *)statusDescription {
    switch (self.currentState) {
        case CPMAutomationStepNone: return @"Idle";
        case CPMAutomationStepLoadingImage: return @"Loading image...";
        case CPMAutomationStepDecomposingImage: return @"Decomposing image...";
        case CPMAutomationStepPlacingLayers: return [NSString stringWithFormat:@"Placing layer %lu/%lu...",
                                                       (unsigned long)self.layersPlaced, (unsigned long)self.totalLayers];
        case CPMAutomationStepPaused: return @"Paused";
        case CPMAutomationStepCompleted: return @"Completed";
        case CPMAutomationStepStopped: return @"Stopped";
        case CPMAutomationStepFailed: return @"Failed";
        default: return @"Unknown";
    }
}

- (void)reset {
    self.currentState = CPMAutomationStepNone;
    self.progress = 0;
    self.layersPlaced = 0;
    self.totalLayers = 0;
    self.isRunning = NO;
    self.isPaused = NO;
    self.emergencyStopActive = NO;
    self.referenceImage = nil;
    self.referenceROIRect = CGRectZero;
    [self.execQueue cancelAllOperations];
    self.shapesQueue = [NSMutableArray array];
}

@end
