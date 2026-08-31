/**
 * CPMShapeDecomposer.m
 * Image Vectorization & Shape Decomposition Engine.
 * Decomposes images into CPM-compatible vinyl primitives.
 *
 * Algorithms:
 * - K-Means color quantization (Accelerate framework)
 * - Edge detection (Sobel operator)
 * - Contour tracing (8-connected boundary following)
 * - Douglas-Peucker polygon simplification
 * - Shape classification (circularity, convexity, vertex count)
 * - Ear clipping triangulation for complex polygons
 */
#import "CPMShapeDecomposer.h"
#import "CPMVinylShape.h"
#import <CoreImage/CoreImage.h>
#import <CoreGraphics/CoreGraphics.h>
#import <Accelerate/Accelerate.h>
#import <math.h>

#pragma mark - Utility

static inline CGFloat clamp(CGFloat v, CGFloat min, CGFloat max) {
    return MAX(min, MIN(max, v));
}

static inline CGFloat dist(CGPoint a, CGPoint b) {
    CGFloat dx = a.x-b.x, dy = a.y-b.y;
    return sqrt(dx*dx + dy*dy);
}

static inline CGFloat polygonArea(NSArray<NSValue*> *v) {
    CGFloat a=0; NSInteger n=v.count;
    if (n<3) return 0;
    for (NSInteger i=0;i<n;i++) {
        CGPoint p1=[v[i] CGPointValue], p2=[v[(i+1)%n] CGPointValue];
        a += p1.x*p2.y - p2.x*p1.y;
    }
    return fabs(a)*0.5;
}

static inline CGFloat polygonPerimeter(NSArray<NSValue*> *v) {
    CGFloat p=0; NSInteger n=v.count;
    if (n<2) return 0;
    for (NSInteger i=0;i<n;i++) {
        CGPoint a=[v[i] CGPointValue], b=[v[(i+1)%n] CGPointValue];
        p += dist(a,b);
    }
    return p;
}

#pragma mark - K-Means Color Quantization

@interface CPMKMeans : NSObject
@property (nonatomic, assign) NSInteger k;
@property (nonatomic, assign) NSInteger maxIter;
- (instancetype)initWithK:(NSInteger)k;
- (NSArray<UIColor*> *)quantize:(NSData*)pixelData width:(size_t)w height:(size_t)h maxColors:(NSInteger)c;
@end

@implementation CPMKMeans
- (instancetype)initWithK:(NSInteger)k {
    self = [super init];
    if (self) { _k = MAX(2,MIN(32,k)); _maxIter = 20; }
    return self;
}

- (NSArray<UIColor*> *)quantize:(NSData*)data width:(size_t)w height:(size_t)h maxColors:(NSInteger)c {
    if (!data || w<1||h<1) return @[];
    const uint8_t *px = data.bytes;
    size_t stride = (w*h > 100000) ? 4 : 1;
    NSMutableArray<NSArray<NSNumber*>*> *points = [NSMutableArray array];
    for (size_t y=0;y<h;y+=stride) {
        for (size_t x=0;x<w;x+=stride) {
            size_t i=(y*w+x)*4;
            CGFloat r=px[i]/255.0, g=px[i+1]/255.0, b=px[i+2]/255.0;
            [points addObject:@[@(r),@(g),@(b)]];
        }
    }
    size_t n = points.count;
    if (n < c) {
        // Return unique colors directly
        NSMutableSet<NSString*> *set = [NSMutableSet set];
        for (NSArray<NSNumber*> *p in points) {
            [set addObject:[NSString stringWithFormat:@"%.3f,%.3f,%.3f",p[0],p[1],p[2]]];
        }
        if (set.count <= c) {
            NSMutableArray<UIColor*> *colors = [NSMutableArray array];
            for (NSString *key in set) {
                NSArray *parts = [key componentsSeparatedByString:@","];
                if (parts.count==3)
                    [colors addObject:[UIColor colorWithRed:[parts[0] floatValue]
                                                      green:[parts[1] floatValue]
                                                       blue:[parts[2] floatValue] alpha:1]];
            }
            return colors;
        }
    }
    // K-Means
    size_t kk = MIN(c, n);
    NSMutableArray<NSArray<NSNumber*>*> *centroids = [NSMutableArray arrayWithCapacity:kk];
    NSMutableSet<NSNumber*> *used = [NSMutableSet set];
    for (size_t i=0; i<kk; i++) {
        NSUInteger idx;
        do { idx = arc4random_uniform((uint32_t)n); }
        while ([used containsObject:@(idx)]);
        [used addObject:@(idx)];
        centroids[i] = points[idx];
    }
    for (NSInteger iter=0; iter<_maxIter; iter++) {
        NSMutableArray<NSMutableArray<NSArray<NSNumber*>*>*> *clusters = [NSMutableArray arrayWithCapacity:kk];
        for (size_t i=0;i<kk;i++) clusters[i] = [NSMutableArray array];
        for (NSArray<NSNumber*> *pt in points) {
            CGFloat minD=CGFLOAT_MAX; NSUInteger best=0;
            for (size_t ci=0;ci<kk;ci++) {
                CGFloat dx=pt[0].floatValue-centroids[ci][0].floatValue;
                CGFloat dy=pt[1].floatValue-centroids[ci][1].floatValue;
                CGFloat dz=pt[2].floatValue-centroids[ci][2].floatValue;
                CGFloat d=dx*dx+dy*dy+dz*dz;
                if (d<minD) { minD=d; best=ci; }
            }
            [clusters[best] addObject:pt];
        }
        CGFloat movement=0;
        for (size_t ci=0;ci<kk;ci++) {
            if (clusters[ci].count==0) continue;
            CGFloat sr=0,sg=0,sb=0;
            for (NSArray<NSNumber*> *pt in clusters[ci]) {
                sr+=pt[0].floatValue; sg+=pt[1].floatValue; sb+=pt[2].floatValue;
            }
            CGFloat cnt=clusters[ci].count;
            NSArray<NSNumber*> *nc = @[@(sr/cnt),@(sg/cnt),@(sb/cnt)];
            CGFloat dx=nc[0].floatValue-centroids[ci][0].floatValue;
            CGFloat dy=nc[1].floatValue-centroids[ci][1].floatValue;
            CGFloat dz=nc[2].floatValue-centroids[ci][2].floatValue;
            movement += sqrt(dx*dx+dy*dy+dz*dz);
            centroids[ci] = nc;
        }
        if (movement < 0.01*kk) break;
    }
    NSMutableArray<UIColor*> *palette = [NSMutableArray arrayWithCapacity:kk];
    for (NSArray<NSNumber*> *c in centroids) {
        [palette addObject:[UIColor colorWithRed:c[0].floatValue green:c[1].floatValue blue:c[2].floatValue alpha:1]];
    }
    [palette sortUsingComparator:^NSComparisonResult(UIColor *a, UIColor *b) {
        CGFloat la = 0.299*CGColorGetRed(a.CGColor)[0]+0.587*CGColorGetGreen(a.CGColor)[0]+0.114*CGColorGetBlue(a.CGColor)[0];
        CGFloat lb = 0.299*CGColorGetRed(b.CGColor)[0]+0.587*CGColorGetGreen(b.CGColor)[0]+0.114*CGColorGetBlue(b.CGColor)[0];
        return la>lb ? NSOrderedDescending : NSOrderedAscending;
    }];
    return palette;
}
@end

#pragma mark - Contour Finder (Sobel + Boundary Tracing)

@interface CPMContourFinder : NSObject
- (NSArray<NSArray<NSValue*>*> *)findContours:(NSData*)data width:(size_t)w height:(size_t)h threshold:(CGFloat)t;
@end

@implementation CPMContourFinder

- (NSArray<NSArray<NSValue*>*> *)findContours:(NSData*)data width:(size_t)w height:(size_t)h threshold:(CGFloat)t {
    if (!data || w<2||h<2) return @[];
    const uint8_t *px = data.bytes;
    
    // Convert to grayscale
    NSMutableArray<NSNumber*> *gray = [NSMutableArray arrayWithCapacity:w*h];
    for (size_t y=0;y<h;y++) {
        for (size_t x=0;x<w;x++) {
            size_t i=(y*w+x)*4;
            CGFloat r=px[i]/255.0, g=px[i+1]/255.0, b=px[i+2]/255.0;
            [gray addObject:@(0.299*r+0.587*g+0.114*b)];
        }
    }
    
    // Sobel edge detection
    NSMutableArray<NSNumber*> *edges = [NSMutableArray arrayWithCapacity:w*h];
    for (size_t y=0;y<h;y++) {
        for (size_t x=0;x<w;x++) {
            CGFloat gx=0, gy=0;
            for (int ky=-1;ky<=1;ky++) {
                for (int kx=-1;kx<=1;kx++) {
                    size_t px2=x+(size_t)kx, py2=y+(size_t)ky;
                    if (px2>=w||py2>=h||px2<0||py2<0) continue;
                    size_t idx=(NSInteger)(py2*w+px2);
                    CGFloat v=gray[idx].floatValue;
                    CGFloat wx=(kx==0)?0:(kx==1?1:-1);
                    CGFloat wy=(ky==0)?0:(ky==1?1:-1);
                    gx+=v*wx; gy+=v*wy;
                }
            }
            CGFloat mag = sqrt(gx*gx+gy*gy);
            [edges addObject:@(clamp(mag,0,1))];
        }
    }
    
    // Threshold
    t = clamp(t, 0.05, 0.5);
    NSMutableArray<NSNumber*> *binary = [NSMutableArray arrayWithCapacity:w*h];
    for (NSNumber *e in edges) [binary addObject:@([e floatValue]>t?1:0)];
    
    // Boundary tracing
    NSMutableArray<NSArray<NSValue*>*> *contours = [NSMutableArray array];
    NSMutableSet<NSNumber*> *visited = [NSMutableSet set];
    
    for (size_t y=0;y<h;y++) {
        for (size_t x=0;x<w;x++) {
            NSInteger idx=(NSInteger)(y*w+x);
            if (binary[idx].intValue==1 && ![visited containsObject:@(idx)]) {
                NSMutableArray<NSValue*> *contour = [NSMutableArray array];
                [self trace:binary w:w h:h startX:x startY:y visited:visited contour:contour];
                if (contour.count>=4) {
                    NSArray<NSValue*> *simplified = [self simplify:contour tolerance:2.0];
                    [contours addObject:simplified];
                }
            }
        }
    }
    
    // Sort by area descending
    [contours sortUsingComparator:^NSComparisonResult(NSArray<NSValue*> *a, NSArray<NSValue*> *b) {
        CGFloat aa=polygonArea(a), ab=polygonArea(b);
        return ab>aa ? NSOrderedAscending : NSOrderedDescending;
    }];
    
    return contours;
}

- (void)trace:(NSArray<NSNumber*> *)binary w:(size_t)w h:(size_t)h startX:(size_t)x startY:(size_t)y visited:(NSMutableSet<NSNumber*> *)visited contour:(NSMutableArray<NSValue*> *)contour {
    NSInteger idx=(NSInteger)(y*w+x);
    CGPoint cur = CGPointMake((CGFloat)x, (CGFloat)y);
    [contour addObject:[NSValue valueWithCGPoint:cur]];
    [visited addObject:@(idx)];
    
    int dx[] = {1,1,0,-1,-1,-1,0,1};
    int dy[] = {0,-1,-1,-1,0,1,1,1};
    int dir = 0;
    size_t iters=0, maxiters=w*h;
    
    while (iters<maxiters) {
        iters++;
        BOOL found=NO;
        for (int i=0;i<8;i++) {
            int td=(dir+i)%8;
            size_t nx=x+dx[td], ny=y+dy[td];
            if (nx>=w||ny>=h||nx<0||ny<0) continue;
            NSInteger ni=(NSInteger)(ny*w+nx);
            if (binary[ni].intValue==1 && ![visited containsObject:@(ni)]) {
                cur = CGPointMake((CGFloat)nx, (CGFloat)ny);
                [contour addObject:[NSValue valueWithCGPoint:cur]];
                [visited addObject:@(ni)];
                dir = (td+4)%8;
                found=YES;
                break;
            }
        }
        if (!found) break;
    }
    
    if (contour.count>1) {
        CGPoint first=[contour[0] CGPointValue], last=[[contour lastObject] CGPointValue];
        if (dist(first,last)<1.0) [contour removeLastObject];
    }
}

- (NSArray<NSValue*> *)simplify:(NSArray<NSValue*> *)contour tolerance:(CGFloat)tol {
    if (contour.count<=2) return contour;
    return [self douglasPeucker:contour si:0 ei:(NSInteger)contour.count-1 tol:tol];
}

- (NSArray<NSValue*> *)douglasPeucker:(NSArray<NSValue*> *)contour si:(NSInteger)s ei:(NSInteger)e tol:(CGFloat)tol {
    if (e<=s+1) return @[[contour[s]],[contour[e]]];
    CGPoint sp=[contour[s] CGPointValue], ep=[contour[e] CGPointValue];
    CGFloat maxD=0; NSInteger maxI=s;
    for (NSInteger i=s+1;i<e;i++) {
        CGPoint pt=[contour[i] CGPointValue];
        CGFloat d=[self pointLineDist:pt ls:sp le:ep];
        if (d>maxD) { maxD=d; maxI=i; }
    }
    if (maxD>tol) {
        NSArray<NSValue*> *left=[self douglasPeucker:contour si:s ei:maxI tol:tol];
        NSArray<NSValue*> *right=[self douglasPeucker:contour si:maxI ei:e tol:tol];
        NSMutableArray<NSValue*> *r=[NSMutableArray arrayWithArray:left];
        for (NSInteger i=1;i<(NSInteger)right.count;i++) [r addObject:right[i]];
        return r;
    }
    return @[[contour[s]],[contour[e]]];
}

- (CGFloat)pointLineDist:(CGPoint)p ls:(CGPoint)ls le:(CGPoint)le {
    CGFloat dx=le.x-ls.x, dy=le.y-ls.y;
    CGFloat len=sqrt(dx*dx+dy*dy);
    if (len<0.001) return dist(p,ls);
    CGFloat t=((p.x-ls.x)*dx+(p.y-ls.y)*dy)/(len*len);
    t=clamp(t,0,1);
    CGPoint proj=CGPointMake(ls.x+t*dx, ls.y+t*dy);
    return dist(p,proj);
}

@end

#pragma mark - Shape Classifier

@implementation CPMShapeClassifier

+ (CPMShapeType)classify:(NSArray<NSValue*> *)contour minConvexity:(CGFloat)mc {
    if (contour.count<3) return CPMShapeTypeSquare;
    CGFloat A=polygonArea(contour), P=polygonPerimeter(contour);
    if (P<1) return CPMShapeTypeSquare;
    CGFloat circ=(4*M_PI*A)/(P*P);
    NSArray<NSValue*> *hull=[self convexHull:contour];
    CGFloat hullA=polygonArea(hull);
    CGFloat conv=(hullA>0)?(A/hullA):0;
    
    if (circ>0.75 && conv>0.85) return CPMShapeTypeCircle;
    if (contour.count==3 && conv>mc) return CPMShapeTypeTriangle;
    if (contour.count==4 && conv>0.9) {
        if ([self isRectangle:contour]) return CPMShapeTypeSquare;
    }
    CGFloat bbArea=[self bbArea:contour];
    if (bbArea>0 && A/bbArea<0.3 && P>50) return CPMShapeTypeLine;
    if (contour.count<=6 && conv>mc) return CPMShapeTypePolygon;
    return CPMShapeTypePolygon;
}

+ (BOOL)isRectangle:(NSArray<NSValue*> *)c {
    if (c.count<4||c.count>12) return NO;
    NSArray<NSValue*> *simp=[self simplifyToQuad:c];
    if (simp.count!=4) return NO;
    CGPoint pts[4];
    for (int i=0;i<4;i++) pts[i]=[simp[i] CGPointValue];
    CGFloat angs[4];
    angs[0]=[self angle:pts[0] b:pts[1] c:pts[2]];
    angs[1]=[self angle:pts[1] b:pts[2] c:pts[3]];
    angs[2]=[self angle:pts[2] b:pts[3] c:pts[0]];
    angs[3]=[self angle:pts[3] b:pts[0] c:pts[1]];
    for (int i=0;i<4;i++) {
        if (fabs(angs[i]-M_PI_2)>0.35) return NO;
    }
    return YES;
}

+ (BOOL)isLikelyCircle:(NSArray<NSValue*> *)c {
    if (c.count<8) return NO;
    CGPoint ctr=[self centroid:c];
    CGFloat avgR=0;
    for (NSValue *v in c) avgR+=dist([v CGPointValue],ctr);
    avgR/=c.count;
    CGFloat var=0;
    for (NSValue *v in c) {
        CGFloat r=dist([v CGPointValue],ctr);
        var+=pow(r-avgR,2);
    }
    var/=c.count;
    return sqrt(var)/avgR < 0.15;
}

+ (BOOL)isLikelyTriangle:(NSArray<NSValue*> *)c {
    if (c.count<3||c.count>8) return NO;
    return [self simplifyToTri:c].count==3;
}

+ (NSArray<CPMVinylShape*> *)decomposeContour:(NSArray<NSValue*> *)contour config:(CPMShapeDecompositionConfig *)cfg bounds:(CGRect)bounds zOrder:(NSInteger)z {
    NSMutableArray<CPMVinylShape*> *shapes=[NSMutableArray array];
    CPMShapeType type=[self classify:contour minConvexity:cfg.minConvexity];
    CGRect bb=[self bbOf:contour];
    CGPoint ctr=CGPointMake(bb.origin.x+bb.size.width*0.5, bb.origin.y+bb.size.height*0.5);
    UIColor *col = [UIColor colorWithWhite:0.5 alpha:1.0];
    
    switch (type) {
        case CPMShapeTypeCircle: {
            CGFloat d=MAX(bb.size.width,bb.size.height);
            CPMVinylShape *s=[CPMVinylShape circleAtPosition:ctr diameter:d rotation:0 red:0.5 green:0.5 blue:0.5 alpha:1.0];
            s.shapeType=CPMShapeTypeCircle; s.zOrder=z; s.scale=CGSizeMake(d,d); s.position=ctr;
            s.rotationDegrees=[self rotation:contour];
            s.red=s.red; s.green=s.green; s.blue=s.blue; // placeholder - would use avg color
            [shapes addObject:s];
            break;
        }
        case CPMShapeTypeSquare: {
            if ([self isRectangle:contour]) {
                CGFloat w=bb.size.width, h=bb.size.height;
                CPMVinylShape *s=[[CPMVinylShape alloc] init];
                s.shapeType=CPMShapeTypeSquare; s.zOrder=z; s.opacity=1.0;
                s.scale=CGSizeMake(w,h); s.position=ctr;
                s.red=128; s.green=128; s.blue=128;
                [shapes addObject:s];
            } else {
                CGFloat side=MAX(bb.size.width,bb.size.height);
                CPMVinylShape *s=[CPMVinylShape squareAtPosition:ctr side:side rotation:0 red:128 green:128 blue:128 alpha:1.0];
                s.zOrder=z; s.rotationDegrees=[self rotation:contour];
                [shapes addObject:s];
            }
            break;
        }
        case CPMShapeTypeTriangle: {
            NSArray<NSValue*> *tri=[self simplifyToTri:contour];
            if (tri.count==3) {
                CGPoint v0=[tri[0] CGPointValue], v1=[tri[1] CGPointValue], v2=[tri[2] CGPointValue];
                CPMVinylShape *s=[[CPMVinylShape alloc] init];
                s.shapeType=CPMShapeTypeTriangle; s.zOrder=z; s.opacity=1.0;
                s.polygonVertexCount=3; s.customVertices=[tri copy];
                CGPoint cc=CGPointMake((v0.x+v1.x+v2.x)*0.333, (v0.y+v1.y+v2.y)*0.333);
                s.position=cc;
                CGFloat maxD=0;
                for (CGPoint v in @[v0,v1,v2]) { CGFloat d=dist(v,cc); if(d>maxD)maxD=d; }
                s.scale=CGSizeMake(maxD*2,maxD*2);
                s.rotationDegrees=[self rotation:tri];
                s.red=128; s.green=128; s.blue=128;
                [shapes addObject:s];
            }
            break;
        }
        case CPMShapeTypeLine: {
            CGPoint p1=[contour[0] CGPointValue], p2=p1;
            CGFloat maxD=0;
            for (NSValue *v in contour) {
                CGPoint pt=[v CGPointValue];
                for (NSValue *v2 in contour) {
                    CGPoint pt2=[v2 CGPointValue];
                    CGFloat d=dist(pt,pt2);
                    if (d>maxD){maxD=d;p1=pt;p2=pt2;}
                }
            }
            CPMVinylShape *line=[CPMVinylShape lineFrom:p1 to:p2 color:[UIColor grayColor] opacity:1.0];
            line.zOrder=z;
            [shapes addObject:line];
            break;
        }
        case CPMShapeTypePolygon: {
            if (cfg.decomposeToPrimitives && contour.count>6) {
                NSArray<NSArray<NSValue*>*> *tris=[self triangulate:contour];
                for (NSArray<NSValue*> *tri in tris) {
                    CPMVinylShape *ts=[[CPMVinylShape alloc] init];
                    ts.shapeType=CPMShapeTypeTriangle; ts.zOrder=z; ts.opacity=1.0;
                    ts.polygonVertexCount=3; ts.customVertices=[tri copy];
                    CGPoint cc=[self centroid:tri];
                    ts.position=cc;
                    CGFloat maxD=0;
                    for (NSValue *v in tri) { CGFloat d=dist([v CGPointValue],cc); if(d>maxD)maxD=d; }
                    ts.scale=CGSizeMake(maxD*2,maxD*2);
                    ts.red=128; ts.green=128; ts.blue=128;
                    [shapes addObject:ts];
                }
            } else {
                CPMVinylShape *s=[[CPMVinylShape alloc] init];
                s.shapeType=CPMShapeTypePolygon; s.zOrder=z; s.opacity=1.0;
                s.polygonVertexCount=(NSInteger)contour.count; s.customVertices=[contour copy];
                CGPoint cc=[self centroid:contour];
                s.position=cc;
                CGFloat maxD=0;
                for (NSValue *v in contour) { CGFloat d=dist([v CGPointValue],cc); if(d>maxD)maxD=d; }
                s.scale=CGSizeMake(maxD*2,maxD*2);
                s.rotationDegrees=[self rotation:contour];
                s.red=128; s.green=128; s.blue=128;
                [shapes addObject:s];
            }
            break;
        }
        default: {
            CPMVinylShape *s=[CPMVinylShape squareAtPosition:ctr side:MAX(bb.size.width,bb.size.height) rotation:0 red:128 green:128 blue:128 alpha:1.0];
            s.zOrder=z;
            [shapes addObject:s];
            break;
        }
    }
    
    if (cfg.includeStrokeInfo && cfg.strokeWidth>0) {
        for (CPMVinylShape *s in shapes) {
            s.strokeWidth=cfg.strokeWidth;
            s.strokeRed=s.red*0.8; s.strokeGreen=s.green*0.8; s.strokeBlue=s.blue*0.8;
        }
    }
    return shapes;
}

#pragma mark - Geometry Helpers

+ (CGPoint)centroid:(NSArray<NSValue*> *)pts {
    CGFloat cx=0,cy=0;
    for (NSValue *v in pts) { CGPoint p=[v CGPointValue]; cx+=p.x; cy+=p.y; }
    return CGPointMake(cx/pts.count, cy/pts.count);
}

+ (CGRect)bbOf:(NSArray<NSValue*> *)pts {
    if (pts.count==0) return CGRectZero;
    CGFloat mnx=CGFLOAT_MAX,mny=CGFLOAT_MAX,mxx=-CGFLOAT_MAX,mxy=-CGFLOAT_MAX;
    for (NSValue *v in pts) {
        CGPoint p=[v CGPointValue];
        mnx=MIN(mnx,p.x); mny=MIN(mny,p.y);
        mxx=MAX(mxx,p.x); mxy=MAX(mxy,p.y);
    }
    return CGRectMake(mnx,mny,mxx-mnx,mxy-mny);
}

+ (CGFloat)bbArea:(NSArray<NSValue*> *)pts {
    CGRect bb=[self bbOf:pts];
    return bb.size.width*bb.size.height;
}

+ (CGFloat)angle:(CGPoint)a b:(CGPoint)b c:(CGPoint)c {
    CGFloat dx1=b.x-a.x, dy1=b.y-a.y, dx2=c.x-b.x, dy2=c.y-b.y;
    CGFloat dot=dx1*dx2+dy1*dy2;
    CGFloat l1=sqrt(dx1*dx1+dy1*dy1), l2=sqrt(dx2*dx2+dy2*dy2);
    if (l1<0.001||l2<0.001) return M_PI_2;
    CGFloat cosA=dot/(l1*l2);
    cosA=clamp(cosA,-1,1);
    return acos(cosA);
}

+ (NSArray<NSValue*> *)convexHull:(NSArray<NSValue*> *)pts {
    if (pts.count<3) return pts;
    NSMutableArray<NSValue*> *sorted=[NSMutableArray arrayWithArray:pts];
    [sorted sortUsingComparator:^NSComparisonResult(NSValue *a, NSValue *b) {
        CGPoint pa=[a CGPointValue], pb=[b CGPointValue];
        if (pa.y!=pb.y) return pa.y<pb.y ? NSOrderedAscending : NSOrderedDescending;
        return pa.x<pb.x ? NSOrderedAscending : NSOrderedDescending;
    }];
    CGPoint pivot=[sorted[0] CGPointValue];
    NSMutableArray<NSValue*> *hull=[NSMutableArray array];
    for (NSValue *v in sorted) {
        CGPoint p=[v CGPointValue];
        while (hull.count>=2) {
            CGPoint h1=[hull[hull.count-2] CGPointValue];
            CGPoint h2=[hull[hull.count-1] CGPointValue];
            CGFloat cross=(h2.x-h1.x)*(p.y-h1.y)-(h2.y-h1.y)*(p.x-h1.x);
            if (cross<=0) [hull removeLastObject];
            else break;
        }
        [hull addObject:v];
    }
    if (hull.count>1 && CGPointEqualToPoint([hull[0] CGPointValue],[hull.lastObject CGPointValue]))
        [hull removeLastObject];
    return hull;
}

+ (NSArray<NSValue*> *)simplifyToQuad:(NSArray<NSValue*> *)c {
    if (c.count<4) return c;
    return [self douglasPeucker:c si:0 ei:(NSInteger)c.count-1 tol:5.0];
}

+ (NSArray<NSValue*> *)simplifyToTri:(NSArray<NSValue*> *)c {
    if (c.count<3) return c;
    return [self douglasPeucker:c si:0 ei:(NSInteger)c.count-1 tol:8.0];
}

+ (CGFloat)rotation:(NSArray<NSValue*> *)contour {
    if (contour.count<2) return 0;
    CGPoint ct=[self centroid:contour];
    CGFloat xx=0,xy=0,yy=0;
    for (NSValue *v in contour) {
        CGPoint p=[v CGPointValue];
        CGFloat dx=p.x-ct.x, dy=p.y-ct.y;
        xx+=dx*dx; xy+=dx*dy; yy+=dy*dy;
    }
    CGFloat angle=0.5*atan2(2*xy, xx-yy);
    return angle*180.0/M_PI;
}

+ (NSArray<NSArray<NSValue*>*> *)triangulate:(NSArray<NSValue*> *)poly {
    NSMutableArray<NSArray<NSValue*>*> *tris=[NSMutableArray array];
    NSMutableArray<NSValue*> *verts=[NSMutableArray arrayWithArray:poly];
    while (verts.count>3) {
        BOOL found=NO;
        for (NSInteger i=0;i<verts.count;i++) {
            NSInteger prev=(i-1+verts.count)%verts.count;
            NSInteger curr=i;
            NSInteger next=(i+1)%verts.count;
            CGPoint pv=[verts[prev] CGPointValue];
            CGPoint cv=[verts[curr] CGPointValue];
            CGPoint nv=[verts[next] CGPointValue];
            CGFloat cross=(cv.x-pv.x)*(nv.y-pv.y)-(cv.y-pv.y)*(nv.x-pv.x);
            if (cross<=0) continue;
            BOOL isEar=YES;
            for (NSInteger j=0;j<verts.count;j++) {
                if (j==prev||j==curr||j==next) continue;
                CGPoint tv=[verts[j] CGPointValue];
                if ([self pointInTri:tv a:pv b:cv c:nv]) { isEar=NO; break; }
            }
            if (isEar) {
                [tris addObject:@[verts[prev],verts[curr],verts[next]]];
                [verts removeObjectAtIndex:curr];
                found=YES;
                break;
            }
        }
        if (!found) break;
    }
    if (verts.count==3) [tris addObject:@[verts[0],verts[1],verts[2]]];
    return tris;
}

+ (BOOL)pointInTri:(CGPoint)p a:(CGPoint)a b:(CGPoint)b c:(CGPoint)c {
    CGFloat d1=[self sign:p p1:a p2:b];
    CGFloat d2=[self sign:p p1:b p2:c];
    CGFloat d3=[self sign:p p1:c p2:a];
    BOOL hn=(d1<0)||(d2<0)||(d3<0);
    BOOL hp=(d1>0)||(d2>0)||(d3>0);
    return !(hn&&hp);
}

+ (CGFloat)sign:(CGPoint)p p1:(CGPoint)p1 p2:(CGPoint)p2 {
    return (p.x-p2.x)*(p1.y-p2.y)-(p1.x-p2.x)*(p.y-p2.y);
}

+ (void)douglasPeucker:(NSArray<NSValue*> *)c si:(NSInteger)s ei:(NSInteger)e tol:(CGFloat)tol { }
@end

#pragma mark - Main Decomposer

@interface CPMShapeDecomposer ()
@property (nonatomic, strong) NSOperationQueue *queue;
@property (nonatomic, assign) BOOL cancelFlag;
@property (nonatomic, copy, nullable) NSArray<UIColor*> *cachedPalette;
@end

@implementation CPMShapeDecomposer

+ (instancetype)sharedDecomposer {
    static CPMShapeDecomposer *inst;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ inst = [[CPMSShapeDecomposer alloc] init]; });
    return inst;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _queue = [[NSOperationQueue alloc] init];
        _queue.maxConcurrentOperationCount = 1;
        _queue.qualityOfService = NSQualityOfServiceUserInitiated;
        _cancelFlag = NO;
        _isProcessing = NO;
        _cachedPalette = nil;
    }
    return self;
}

- (void)dealloc { [_queue cancelAllOperations]; }

- (void)decomposeImage:(UIImage *)image withConfig:(CPMShapeDecompositionConfig *)config completion:(void(^)(CPMShapeDecompositionResult*,NSError*))completion {
    if (!image) {
        NSError *err = [NSError errorWithDomain:@"CPMShapeDecomposer" code:-1 userInfo:@{NSLocalizedDescriptionKey:@"Image is nil"}];
        if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(nil,err); });
        return;
    }
    if ([self isProcessing]) {
        NSError *err = [NSError errorWithDomain:@"CPMShapeDecomposer" code:-2 userInfo:@{NSLocalizedDescriptionKey:@"Already processing"}];
        if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(nil,err); });
        return;
    }
    [self cancelDecomposition];
    self.cancelFlag = NO;
    self.isProcessing = YES;
    dispatch_async(self.queue, ^{
        @autoreleasepool {
            CPMShapeDecompositionResult *result = [self processImage:image config:config];
            self.isProcessing = NO;
            dispatch_async(dispatch_get_main_queue(), ^{
                if (self.cancelFlag) completion(nil,nil);
                else completion(result,nil);
            });
        }
    });
}

- (void)cancelDecomposition { self.cancelFlag=YES; [_queue cancelAllOperations]; }

- (CPMShapeDecompositionResult *)processImage:(UIImage *)image config:(CPMShapeDecompositionConfig *)config {
    NSDate *start = [NSDate date];
    CGImageRef cgimg = image.CGImage;
    if (!cgimg) return nil;
    size_t w = CGImageGetWidth(cgimg), h = CGImageGetHeight(cgimg);
    NSUInteger pc = (NSUInteger)(w*h);
    self.lastPixelCount = pc;
    if (self.progressCallback) self.progressCallback(0.05);
    
    CGRect roi = config.roiRect;
    if (!CGRectIsValid(roi)||CGRectIsEmpty(roi)) roi=CGRectMake(0,0,w,h);
    roi = CGRectIntersection(roi, CGRectMake(0,0,w,h));
    
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    size_t bpp=4, bpr=bpp*w;
    NSMutableData *data = [NSMutableData dataWithLength:bpr*h];
    CGContextRef ctx = CGBitmapContextCreate(data.mutableBytes, w, h, 8, bpr, cs,
                                              kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder32Big);
    CGContextDrawImage(ctx, CGRectMake(0,0,w,h), cgimg);
    CGColorSpaceRelease(cs);
    CGContextRelease(ctx);
    CFRelease(cgimg);
    if (self.progressCallback) self.progressCallback(0.15);
    
    // Color quantization
    CPMKMeans *km = [[CPMKMeans alloc] initWithK:config.colorCount];
    self.extractedPalette = [km quantize:data width:w height:h maxColors:config.colorCount];
    if (self.progressCallback) self.progressCallback(0.30);
    
    // Extract ROI
    size_t rx=(size_t)roi.origin.x, ry=(size_t)roi.origin.y;
    size_t rw=(size_t)roi.size.width, rh=(size_t)roi.size.height;
    NSMutableData *roiData = [NSMutableData dataWithLength:rw*rh*4];
    const uint8_t *src = data.bytes;
    uint8_t *dst = roiData.mutableBytes;
    for (size_t y=0;y<rh;y++) {
        for (size_t x=0;x<rw;x++) {
            size_t si=((ry+y)*w+(rx+x))*4;
            size_t di=(y*rw+x)*4;
            dst[di]=src[si]; dst[di+1]=src[si+1]; dst[di+2]=src[si+2]; dst[di+3]=src[si+3];
        }
    }
    if (self.progressCallback) self.progressCallback(0.45);
    
    // Contour detection
    CPMContourFinder *finder = [[CPMContourFinder alloc] init];
    NSArray<NSArray<NSValue*>*> *contours = [finder findContours:roiData width:rw height:rh threshold:0.12];
    if (self.progressCallback) self.progressCallback(0.60);
    
    // Decompose contours into shapes
    NSMutableArray<CPMVinylShape*> *shapes = [NSMutableArray array];
    NSInteger z=0;
    for (NSArray<NSValue*> *contour in contours) {
        if (self.cancelFlag) break;
        CGFloat A=polygonArea(contour);
        if (A<config.minShapeArea||A>config.maxShapeArea) continue;
        NSArray<CPMVinylShape*> *newShapes = [CPMShapeClassifier decomposeContour:contour config:config bounds:roi zOrder:z++];
        for (CPMVinylShape *s in newShapes) {
            if (shapes.count>=config.maxShapes) break;
            [shapes addObject:s];
        }
        if (self.progressCallback) self.progressCallback(0.60+0.35*((CGFloat)shapes.count/(CGFloat)config.maxShapes));
    }
    
    // Sort by area if requested
    if (config.sortByArea) {
        [shapes sortUsingComparator:^NSComparisonResult(CPMVinylShape *a, CPMVinylShape *b) {
            CGFloat aa=a.scale.width*a.scale.height, ab=b.scale.width*b.scale.height;
            return ab>aa ? NSOrderedAscending : NSOrderedDescending;
        }];
    }
    if (shapes.count>config.maxShapes)
        shapes = [shapes subarrayWithRange:NSMakeRange(0,config.maxShapes)];
    
    NSTimeInterval elapsed = [[NSDate date] timeIntervalSinceDate:start];
    CGFloat totalArea = rw*rh;
    CGFloat cov=0;
    for (CPMVinylShape *s in shapes) cov += s.scale.width*s.scale.height;
    cov = MIN(1.0, cov/totalArea);
    if (self.progressCallback) self.progressCallback(1.0);
    
    CPMShapeDecompositionResult *result = [[CPMShapeDecompositionResult alloc] init];
    result.shapes = [shapes copy];
    result.processingTime = elapsed;
    result.inputPixelCount = pc;
    result.outputShapeCount = shapes.count;
    result.colorReductionRatio = (CGFloat)config.colorCount / MAX(1,(NSInteger)pc);
    result.shapeCoverageRatio = cov;
    self.lastShapeCount = shapes.count;
    return result;
}

#pragma mark - CPMShapeDecompositionResult

- (BOOL)meetsQualityThreshold {
    return self.outputShapeCount>0 && self.shapeCoverageRatio>0.1;
}

- (NSString *)summaryString {
    return [NSString stringWithFormat:@"Decomposition: %lu px → %lu shapes (%.1f%% coverage) in %.2fs",
            (unsigned long)self.inputPixelCount, (unsigned long)self.outputShapeCount,
            self.shapeCoverageRatio*100, self.processingTime];
}
@end

#pragma mark - CPMShapeDecompositionConfig

@implementation CPMShapeDecompositionConfig

+ (instancetype)defaultConfig {
    CPMShapeDecompositionConfig *c = [[CPMShapeDecompositionConfig alloc] init];
    c.maxShapes = 150; c.colorCount = 8; c.quantizationMethod = CPMColorQuantizationKMeans;
    c.minShapeArea = 50; c.maxShapeArea = 10000; c.includeStrokeInfo = YES;
    c.decomposeToPrimitives = YES; c.minConvexity = 0.7; c.overlapTolerance = 0.15;
    c.sortByArea = YES; c.dpiScaleFactor = 1.0;
    return c;
}

+ (instancetype)configForCarBodyWithMaxLayers:(NSInteger)limit {
    CPMShapeDecompositionConfig *c = [self defaultConfig];
    c.maxShapes = MIN(limit, 200); c.colorCount = 6;
    c.minShapeArea = 100; c.maxShapeArea = 15000; c.decomposeToPrimitives = YES;
    c.minConvexity = 0.6; c.overlapTolerance = 0.2;
    return c;
}

+ (instancetype)configForDetailedLogoWithMaxLayers:(NSInteger)limit {
    CPMShapeDecompositionConfig *c = [self defaultConfig];
    c.maxShapes = MIN(limit, 300); c.colorCount = 12;
    c.minShapeArea = 25; c.maxShapeArea = 20000;
    c.quantizationMethod = CPMColorQuantizationMedianCut;
    c.decomposeToPrimitives = NO; c.minConvexity = 0.85; c.overlapTolerance = 0.1;
    c.sortByArea = YES;
    return c;
}

@end
