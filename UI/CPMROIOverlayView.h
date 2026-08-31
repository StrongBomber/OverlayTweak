/**
 * CPMROIOverlayView.h
 * ROI Selector overlay for defining drawing area on the target car.
 */
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@protocol CPMROIOverlayViewDelegate <NSObject>
@optional
- (void)roiOverlay:(id)overlay didFinishWithRect:(CGRect)rect;
- (void)roiOverlayDidCancel:(id)overlay;
@end

@interface CPMROIOverlayView : UIView

@property (nonatomic, weak, nullable) id<CPMROIOverlayViewDelegate> delegate;
@property (nonatomic, assign, readonly) CGRect selectedRect;
@property (nonatomic, assign) BOOL showGuides;
@property (nonatomic, assign) BOOL showCenterCrosshair;

- (instancetype)initWithFrame:(CGRect)frame;
- (void)beginSelection;
- (void)cancelSelection;
- (void)clearSelection;

@end

NS_ASSUME_NONNULL_END
