#import "STNPrivate.h"
#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>
#import <IOSurface/IOSurface.h>
#import <simd/simd.h>

// Mutable objects below never cross the private bridge. Each worker owns its
// CGContext; each host encodes serially using tracked Metal resources.
@interface STNMetalRenderer : NSObject
@property(nonatomic, weak) STNWindowHost *host;
@property(nonatomic, strong) CAMetalLayer *layer;
- (instancetype)initWithHost:(STNWindowHost *)host;
- (void)requestFrame;
- (void)setAnimationDemand:(BOOL)active;
- (void)pauseForObservations:(BOOL)paused;
- (void)retryPresentation:(uint64_t)revision;
- (void)submit:(NSDictionary *)scene;
- (void)invalidate;
- (void)detach;
- (NSDictionary *)diagnostics;
- (void)reportDiagnostics:(void (^)(NSDictionary *))completion;
- (BOOL)exportTo:(NSString *)path linear:(BOOL)linear;
- (uint64_t)pixelHash;
- (void)readback:(void (^)(NSData *, NSUInteger, NSUInteger, BOOL, uint64_t, NSString *))completion;
- (void)testFinalMode:(int32_t)mode rasterDelay:(double)delay starved:(BOOL)starved;
- (void)recordUIPlanning:(double)planning transport:(double)transport scene:(uint64_t)scene;
- (void)recordInputTimestamp:(double)arrival started:(double)start;
@end

typedef struct {
    vector_float4 rect, uv, color, clip;
    vector_float4 row0, row1, target, options;
    uint32_t mode, linear, sourceLinear, masked;
} STNMetalQuad;

@interface STNMetalAllocation : NSObject
@property(nonatomic, strong) id<MTLTexture> texture;
@property(nonatomic, strong) id<MTLBuffer> buffer;
@property(nonatomic) IOSurfaceRef surface;
@property(nonatomic) NSUInteger bytes;
@end

@interface STNMetalTile : NSObject
@property(nonatomic, copy) NSString *key;
@property(nonatomic, strong) STNMetalAllocation *allocation;
@property(nonatomic) CGRect core, padded;
@end

@interface STNMetalSurface : NSObject
@property(nonatomic, copy) NSString *key;
@property(nonatomic) CGRect bounds;
@property(nonatomic) double scale;
@property(nonatomic) BOOL linear;
@property(nonatomic) BOOL valid;
@property(nonatomic, strong) NSArray<NSDictionary *> *directInputs;
@property(nonatomic, strong) NSArray<NSString *> *cacheKeys;
@property(nonatomic) CGAffineTransform backdropTransform;
@property(nonatomic) CGRect backdropPanel;
@property(nonatomic, copy) NSString *contextID;
@property(nonatomic, strong) NSArray<STNMetalTile *> *tiles;
@end

void STNRasterFill(CGContextRef, stn_rect, stn_color, double);
void STNRasterStroke(CGContextRef, stn_rect, stn_color, double, double);
void STNRasterText(CGContextRef, stn_utf8, stn_rect, double, double, stn_color, bool);
void STNRasterImage(CGContextRef, NSData *, stn_rect);
