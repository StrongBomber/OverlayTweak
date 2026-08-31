/**
 * CPMVinylShape.m
 * Implementation of CPM-compatible vinyl shape data model.
 */

#import "CPMVinylShape.h"

@interface CPMVinylShape ()
@property (nonatomic, copy, readwrite) NSString *identifier;
@end

@implementation CPMVinylShape

- (instancetype)init {
    self = [super init];
    if (self) {
        _identifier = [[NSUUID UUID] UUIDString];
        _shapeType = CPMShapeTypeSquare;
        _position = CGPointZero;
        _scale = CGSizeMake(10, 10);
        _rotationDegrees = 0.0;
        _red = 128; _green = 128; _blue = 128;
        _alpha = 1.0;
        _zOrder = 0;
        _strokeWidth = 0;
        _strokeRed = _red; _strokeGreen = _green; _strokeBlue = _blue;
    }
    return self;
}

- (instancetype)initWithType:(CPMShapeType)type
                     position:(CGPoint)pos
                        scale:(CGSize)size
                   rotation:(CGFloat)rotation
                       red:(CGFloat)r green:(CGFloat)g blue:(CGFloat)b
                     alpha:(CGFloat)a
{
    self = [self init];
    if (self) {
        _shapeType = type;
        _position = pos;
        _scale = size;
        _rotationDegrees = rotation;
        _red = r; _green = g; _blue = b;
        _alpha = a;
    }
    return self;
}

+ (instancetype)squareAtPosition:(CGPoint)pos
                           side:(CGFloat)side
                       rotation:(CGFloat)rotation
                            red:(CGFloat)r green:(CGFloat)g blue:(CGFloat)b
                          alpha:(CGFloat)a
{
    return [[self alloc] initWithType:CPMShapeTypeSquare
                             position:pos
                                scale:CGSizeMake(side, side)
                           rotation:rotation
                               red:r green:g blue:b
                             alpha:a];
}

+ (instancetype)circleAtPosition:(CGPoint)pos
                          diameter:(CGFloat)diameter
                        rotation:(CGFloat)rotation
                             red:(CGFloat)r green:(CGFloat)g blue:(CGFloat)b
                           alpha:(CGFloat)a
{
    return [[self alloc] initWithType:CPMShapeTypeCircle
                             position:pos
                                scale:CGSizeMake(diameter, diameter)
                           rotation:rotation
                               red:r green:g blue:b
                             alpha:a];
}

+ (instancetype)lineFrom:(CGPoint)startPoint to:(CGPoint)endPoint
                   color:(UIColor *)color
                 opacity:(CGFloat)opacity
{
    CPMVinylShape *shape = [[self alloc] init];
    shape.shapeType = CPMShapeTypeLine;
    
    CGFloat dx = endPoint.x - startPoint.x;
    CGFloat dy = endPoint.y - startPoint.y;
    CGFloat length = sqrt(dx*dx + dy*dy);
    CGFloat angleRad = atan2(dy, dx);
    CGFloat angleDeg = angleRad * 180.0 / M_PI;
    
    shape.position = CGPointMake((startPoint.x + endPoint.x)/2,
                                  (startPoint.y + endPoint.y)/2);
    shape.scale = CGSizeMake(MAX(1.0, length), 2.0); // Line thickness
    shape.rotationDegrees = angleDeg;
    shape.zOrder = 0;
    shape.alpha = opacity;
    
    CGFloat r=0, g=0, b=0, a=0;
    if ([color getRed:&r green:&g blue:&b alpha:&a]) {
        shape.red = r * 255;
        shape.green = g * 255;
        shape.blue = b * 255;
        shape.alpha = opacity;
    }
    return shape;
}

- (NSDictionary<NSString *, id> *)toCPMParametersDictionary {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    dict[@"id"] = self.identifier;
    dict[@"type"] = @(self.shapeType);
    dict[@"x"] = @(self.position.x);
    dict[@"y"] = @(self.position.y);
    dict[@"w"] = @(self.scale.width);
    dict[@"h"] = @(self.scale.height);
    dict[@"rotation"] = @(self.rotationDegrees);
    dict[@"r"] = @(floor(self.red));
    dict[@"g"] = @(floor(self.green));
    dict[@"b"] = @(floor(self.blue));
    dict[@"a"] = @(self.alpha);
    dict[@"z"] = @(self.zOrder);
    
    if (self.polygonVertices.count > 0) {
        NSMutableArray *verts = [NSMutableArray array];
        for (NSValue *v in self.polygonVertices) {
            CGPoint p = [v CGPointValue];
            [verts addObject:@{@"x": @(p.x), @"y": @(p.y)}];
        }
        dict[@"vertices"] = verts;
    }
    
    return [dict copy];
}

- (NSString *)debugDescription {
    return [NSString stringWithFormat:
            @"Shape %@: type=%@ pos=(%.1f,%.1f) size=%.1fx%.1f rot=%.1f° color=#%02X%02X%02X a=%.2f z=%ld",
            self.identifier,
            @(self.shapeType),
            self.position.x, self.position.y,
            self.scale.width, self.scale.height,
            self.rotationDegrees,
            (int)self.red, (int)self.green, (int)self.blue,
            self.alpha,
            (long)self.zOrder];
}

@end
