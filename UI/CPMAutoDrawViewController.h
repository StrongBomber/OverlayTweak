/**
 * CPMAutoDrawViewController.h
 * Control panel for CPM Image-to-Vinyl Automation.
 * Provides buttons for Load Image, Select Region, Set Layer Limit,
 * Start Auto-Draw, Pause/Stop, and progress display.
 */
#import <UIKit/UIKit.h>

@class CPMExecutionController;

NS_ASSUME_NONNULL_BEGIN

@protocol CPMAutoDrawViewControllerDelegate <NSObject>
@optional
- (void)autoDrawControllerDidRequestImage:(id)controller;
- (void)autoDrawController:(id)controller didRequestROISelection:(BOOL)startFromCurrent;
- (void)autoDrawControllerDidRequestStart:(id)controller;
- (void)autoDrawControllerDidRequestPause:(id)controller;
- (void)autoDrawControllerDidRequestStop:(id)controller;
- (void)autoDrawController:(id)controller didUpdateProgress:(CGFloat)progress;
- (void)autoDrawController:(id)controller didUpdateLayerCount:(NSUInteger)placed total:(NSUInteger)total;
- (void)autoDrawController:(id)controller didEncounterError:(NSError *)error;
@end

@interface CPMAutoDrawViewController : UIViewController

@property (nonatomic, weak, nullable) id<CPMAutoDrawViewControllerDelegate> delegate;
@property (nonatomic, strong, nullable) UIImage *referenceImage;
@property (nonatomic, assign, nullable) CGRect roiRect;
@property (nonatomic, assign) BOOL roiSelectionEnabled;
@property (nonatomic, strong, nullable) CPMExecutionController *executionController;

// UI Controls
- (void)setLayerLimit:(NSInteger)limit;
- (NSInteger)layerLimit;
- (void)setTouchDelay:(NSTimeInterval)ms;
- (NSTimeInterval)touchDelay;

// Lifecycle
- (void)loadReferenceImage:(UIImage *)image;
- (void)clearReferenceImage;
- (void)updateROI:(CGRect)rect;
- (void)showControlsAnimated:(BOOL)animated;
- (void)hideControlsAnimated:(BOOL)animated;

// Status
- (NSString *)statusText;

@end

NS_ASSUME_NONNULL_END
