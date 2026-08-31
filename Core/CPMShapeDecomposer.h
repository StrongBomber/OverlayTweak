/**
 * CPMShapeDecomposer.h
 * Image Vectorization & Shape Processing Engine.
 * Decomposes images into CPM-compatible vinyl primitives using
 * color quantization (K-Means), contour detection, and shape approximation.
 */
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@class CPMVinylShape;
@class CPMShapeDecompositionConfig;

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, CPMColorQuantizationMethod) {
    CPMColorQuantizationKMeans = 0,
    CPMColorQuantizationMedianCut = 1,
    CPMColorQuantizationPopularityBased = 2,
};

@interface CPMShapeDecompositionConfig : NSObject

@property (nonatomic, assign) NSInteger maxShapes;              // Default: 200 (CPM layer limit ~300)
@property (nonatomic, assign) NSInteger colorCount;             // Default: 8 (K-Means clusters)
@property (nonatomic, assign) CPMColorQuantizationMethod quantizationMethod;
@property (nonatomic, assign) CGFloat minShapeArea;             // Min area in pixels² to keep shape
@property (nonatomic, assign) CGFloat maxShapeArea;             // Max area to prevent giant shapes
@property (nonatomic, assign) BOOL includeStrokeInfo;
@property (nonatomic, assign) BOOL decomposeToPrimitives;       // Break complex polygons into triangles
@property (nonatomic, assign) CGFloat minConvexity;             // Filter non-convex shapes
@property (nonatomic, assign) CGFloat overlapTolerance;         // How much shapes can overlap
@property (nonatomic, assign) BOOL sortByArea;                  // Sort shapes by area (largest first)
@property (nonatomic, assign) CGFloat dpiScaleFactor;           // Scale for high-res images
@property (nonatomic, assign) CGRect roiRect;                   // Region of interest within image

+ (instancetype)defaultConfig;
+ (instancetype)configForCarBodyWithMaxLayers:(NSInteger)layerLimit;
+ (instancetype)configForDetailedLogoWithMaxLayers:(NSInteger)layerLimit;

@end

@interface CPMShapeDecompositionResult : NSObject

@property (nonatomic, copy, readonly) NSArray<CPMVinylShape *> *shapes;
@property (nonatomic, assign, readonly) NSTimeInterval processingTime;
@property (nonatomic, assign, readonly) NSUInteger inputPixelCount;
@property (nonatomic, assign, readonly) NSUInteger outputShapeCount;
@property (nonatomic, assign, readonly) CGFloat colorReductionRatio;
@property (nonatomic, assign, readonly) CGFloat shapeCoverageRatio;

- (BOOL)meetsQualityThreshold;
- (NSString *)summaryString;

@end

@interface CPMShapeDecomposer : NSObject

+ (instancetype)sharedDecomposer;

- (void)decomposeImage:(UIImage *)image
             withConfig:(CPMShapeDecompositionConfig *)config
            completion:(void (^)(CPMShapeDecompositionResult * _Nullable result, NSError * _Nullable error))completion;

- (void)cancelDecomposition;
@property (nonatomic, assign, readonly) BOOL isProcessing;

@property (nonatomic, copy, nullable) void (^progressCallback)(CGFloat progress);

// Access extracted palette from last processed image
@property (nonatomic, copy, readonly, nullable) NSArray<UIColor *> *extractedPalette;
@property (nonatomic, assign, readonly) NSUInteger lastPixelCount;
@property (nonatomic, assign, readonly) NSUInteger lastShapeCount;

@end

NS_ASSUME_NONNULL_END
