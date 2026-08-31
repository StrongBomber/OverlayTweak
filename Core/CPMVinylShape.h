/**
 * CPMVinylShape.h
 * CPM-compatible vinyl shape data model for Car Parking Multiplayer.
 * Represents primitives that CPM's vinyl editor can render:
 * squares, circles, triangles, lines, polygons.
 */
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, CPMShapeType) {
    CPMShapeTypeSquare    = 0,
    CPMShapeTypeCircle    = 1,
    CPMShapeTypeTriangle  = 2,
    CPMShapeTypeLine      = 3,
    CPMShapeTypePolygon   = 4,
};

@interface CPMVinylShape : NSObject

@property (nonatomic, copy) NSString *identifier;       // Unique ID for logging
@property (nonatomic, assign) CPMShapeType shapeType;
@property (nonatomic, assign) CGPoint position;          // Center X,Y (relative to ROI)
@property (nonatomic, assign) CGSize scale;              // Width, Height in points
@property (nonatomic, assign) CGFloat rotationDegrees;   // 0..360
@property (nonatomic, assign) CGFloat red;               // 0..255
@property (nonatomic, assign) CGFloat green;             // 0..255
@property (nonatomic, assign) CGFloat blue;              // 0..255
@property (nonatomic, assign) CGFloat alpha;             // 0..1
@property (nonatomic, assign) NSInteger zOrder;          // Layer priority (higher=top)

// For polygon shapes
@property (nonatomic, copy, nullable) NSArray<NSValue *> *polygonVertices;

// Stroke/outline (if CPM supports it in future)
@property (nonatomic, assign) CGFloat strokeRed;
@property (nonatomic, assign) CGFloat strokeGreen;
@property (nonatomic, assign) CGFloat strokeBlue;
@property (nonatomic, assign) CGFloat strokeWidth;

- (instancetype)initWithType:(CPMShapeType)type
                     position:(CGPoint)pos
                        scale:(CGSize)size
                   rotation:(CGFloat)rotation
                       red:(CGFloat)r green:(CGFloat)g blue:(CGFloat)b
                     alpha:(CGFloat)a;

+ (instancetype)squareAtPosition:(CGPoint)pos
                           side:(CGFloat)side
                       rotation:(CGFloat)rotation
                            red:(CGFloat)r green:(CGFloat)g blue:(CGFloat)b
                          alpha:(CGFloat)a;

+ (instancetype)circleAtPosition:(CGPoint)pos
                          diameter:(CGFloat)diameter
                        rotation:(CGFloat)rotation
                             red:(CGFloat)r green:(CGFloat)g blue:(CGFloat)b
                           alpha:(CGFloat)a;

+ (instancetype)lineFrom:(CGPoint)startPoint to:(CGPoint)endPoint
                   color:(UIColor *)color
                 opacity:(CGFloat)opacity;

- (NSDictionary<NSString *, id> *)toCPMParametersDictionary;
- (NSString *)debugDescription;

@end

NS_ASSUME_NONNULL_END
