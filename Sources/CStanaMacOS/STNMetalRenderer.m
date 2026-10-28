#import "STNMetal.h"
#import "STNMetalShaders.h"
#include <time.h>

static const NSUInteger STNSingleAllocationLimit=256*1024*1024;
static id<MTLDevice> STNDevice;
static NSLock *STNMemoryLock;
static NSUInteger STNAllocatedBytes, STNAdmissionCapacity;
static NSUInteger STNDefaultCapacity;
static double STNLastPressure;
static double STNCopyBandwidth;
static NSHashTable<STNMetalRenderer *> *STNRenderers;
static id<MTLLibrary> STNSharedLibrary;
static NSCache<NSString *, id> *STNSharedPipelines;
static NSCache<NSString *, NSDictionary *> *STNSharedApplications;
static void STNCalibrateBandwidth(void);
static dispatch_queue_t STNCompiler;
static dispatch_source_t STNPressure;
static NSUInteger STNPacketCount;
static NSMutableArray<void (^)(void)> *STNPacketWaiters;
static NSObject *STNPacketLock;

static void STNAcquirePacket(void (^start)(void)) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{ STNPacketLock=[NSObject new]; STNPacketWaiters=[NSMutableArray new]; });
    BOOL admitted=NO;
    @synchronized(STNPacketLock) {
        if (STNPacketCount<6) { STNPacketCount++; admitted=YES; }
        else [STNPacketWaiters addObject:start];
    }
    if (admitted) start();
}
static void STNReleasePacket(void) {
    void (^next)(void)=nil;
    @synchronized(STNPacketLock) {
        NSCAssert(STNPacketCount>0,@"Stana packet admission underflow");
        if (STNPacketWaiters.count) { next=STNPacketWaiters[0]; [STNPacketWaiters removeObjectAtIndex:0]; }
        else STNPacketCount--;
    }
    if (next) next();
}
@interface STNPacketPermit : NSObject
@end
@implementation STNPacketPermit
- (void)dealloc { STNReleasePacket(); }
@end

static CGRect STNArrayRect(NSArray *a) {
    return CGRectMake([a[0] doubleValue],[a[1] doubleValue],[a[2] doubleValue],[a[3] doubleValue]);
}
static stn_rect STNABI(CGRect r) { return (stn_rect){r.origin.x,r.origin.y,r.size.width,r.size.height}; }
static vector_float4 STNVector(CGRect r) { return (vector_float4){r.origin.x,r.origin.y,r.size.width,r.size.height}; }
static stn_color STNArrayColor(NSArray *a) { return (stn_color){[a[0] doubleValue],[a[1] doubleValue],[a[2] doubleValue],[a[3] doubleValue]}; }
static CGAffineTransform STNArrayTransform(NSArray *a) {
    return CGAffineTransformMake([a[0] doubleValue],[a[1] doubleValue],[a[2] doubleValue],[a[3] doubleValue],[a[4] doubleValue],[a[5] doubleValue]);
}
static CGAffineTransform STNAnchoredTransform(NSDictionary *node) {
    CGRect r=STNArrayRect(node[@"bounds"]);
    CGAffineTransform t=STNArrayTransform(node[@"transform"]);
    t.tx+=r.origin.x-t.a*r.origin.x-t.c*r.origin.y;
    t.ty+=r.origin.y-t.b*r.origin.x-t.d*r.origin.y;
    return t;
}
static BOOL STNInvertible(CGAffineTransform t) {
    double s=fmax(fmax(fabs(t.a),fabs(t.b)),fmax(fabs(t.c),fabs(t.d)));
    if (!isfinite(s)||s==0) return NO;
    double det=(t.a/s)*(t.d/s)-(t.b/s)*(t.c/s);
    return det!=0 && isfinite(det) && isfinite((t.d/s/det)/s) && isfinite((t.a/s/det)/s);
}
static CGAffineTransform STNCompose(CGAffineTransform parent, CGAffineTransform child) {
    return CGAffineTransformMake(parent.a*child.a+parent.c*child.b,parent.b*child.a+parent.d*child.b,
        parent.a*child.c+parent.c*child.d,parent.b*child.c+parent.d*child.d,
        parent.a*child.tx+parent.c*child.ty+parent.tx,parent.b*child.tx+parent.d*child.ty+parent.ty);
}
static MTLPixelFormat STNFormat(NSString *name) {
    if ([name isEqual:@"bgra8Unorm"]) return MTLPixelFormatBGRA8Unorm;
    if ([name isEqual:@"r8Unorm"]) return MTLPixelFormatR8Unorm;
    return MTLPixelFormatRGBA16Float;
}
static NSUInteger STNPixelBytes(MTLPixelFormat format) {
    return format==MTLPixelFormatRGBA16Float ? 8 : format==MTLPixelFormatR8Unorm ? 1 : 4;
}
static uint64_t STNUInt64(id value) {
    return [value isKindOfClass:NSString.class] ? strtoull([value UTF8String],NULL,10) : [value unsignedLongLongValue];
}
static NSData *STNCanonicalReadback(id<MTLBuffer> buffer, NSUInteger row, NSUInteger rawRow, NSUInteger height) {
    NSMutableData *data=[NSMutableData dataWithLength:rawRow*height];
    for (NSUInteger y=0;y<height;y++) memcpy((uint8_t *)data.mutableBytes+y*rawRow,(uint8_t *)buffer.contents+y*row,rawRow);
    return data;
}
static double STNThreadCPUTime(void) {
    struct timespec t={0}; clock_gettime(CLOCK_THREAD_CPUTIME_ID,&t); return t.tv_sec+t.tv_nsec*1e-9;
}
static void STNMetalInitializeDevice(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        STNDevice=MTLCreateSystemDefaultDevice(); STNMemoryLock=[NSLock new];
        NSUInteger physical=NSProcessInfo.processInfo.physicalMemory/4;
        NSUInteger recommended=STNDevice.recommendedMaxWorkingSetSize/2;
        STNAdmissionCapacity=recommended ? MIN(physical,recommended) : physical;
        STNDefaultCapacity=STNAdmissionCapacity;
        STNCompiler=dispatch_queue_create("dev.stana.metal.compiler",DISPATCH_QUEUE_SERIAL);
        STNRenderers=[NSHashTable weakObjectsHashTable];
        STNSharedPipelines=[NSCache new]; STNSharedPipelines.countLimit=64;
        STNSharedApplications=[NSCache new]; STNSharedApplications.countLimit=32;
        dispatch_async(STNCompiler, ^{ STNCalibrateBandwidth(); });
        STNPressure=dispatch_source_create(DISPATCH_SOURCE_TYPE_MEMORYPRESSURE,0,DISPATCH_MEMORYPRESSURE_WARN|DISPATCH_MEMORYPRESSURE_CRITICAL,STNCompiler);
        dispatch_source_set_event_handler(STNPressure, ^{
            [STNMemoryLock lock]; STNAdmissionCapacity=MAX((NSUInteger)1,STNDefaultCapacity/2); STNLastPressure=CACurrentMediaTime(); [STNMemoryLock unlock];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,10*NSEC_PER_SEC),STNCompiler, ^{
                [STNMemoryLock lock]; if (CACurrentMediaTime()-STNLastPressure>=10) STNAdmissionCapacity=STNDefaultCapacity; [STNMemoryLock unlock];
            });
        });
        dispatch_resume(STNPressure);
    });
}

@implementation STNMetalAllocation
- (void)dealloc {
    if (_surface) CFRelease(_surface);
    [STNMemoryLock lock]; NSCAssert(STNAllocatedBytes>=_bytes,@"Stana allocation ledger underflow");
    STNAllocatedBytes-=_bytes; [STNMemoryLock unlock];
}
@end
@implementation STNMetalTile
@end
@implementation STNMetalSurface
@end

static STNMetalAllocation *STNAllocate(NSUInteger width, NSUInteger height, MTLPixelFormat format, BOOL raster, NSUInteger samples) {
    NSUInteger bpp=STNPixelBytes(format);
    if (!width||!height||width>16384||height>16384||width>STNSingleAllocationLimit/height/bpp) return nil;
    NSUInteger row=IOSurfaceAlignProperty(kIOSurfaceBytesPerRow,width*bpp);
    if (row>STNSingleAllocationLimit/height) return nil;
    if (samples>STNSingleAllocationLimit/(row*height)) return nil;
    NSUInteger reserved=IOSurfaceAlignProperty(kIOSurfaceAllocSize,row*height*samples);
    [STNMemoryLock lock];
    BOOL admitted=reserved<=STNAdmissionCapacity && STNAllocatedBytes<=STNAdmissionCapacity-reserved;
    if (admitted) STNAllocatedBytes+=reserved;
    [STNMemoryLock unlock];
    if (!admitted) return nil;
    STNMetalAllocation *a=[STNMetalAllocation new]; a.bytes=reserved;
    MTLTextureDescriptor *d=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:format width:width height:height mipmapped:NO];
    d.hazardTrackingMode=MTLHazardTrackingModeTracked;
    d.usage=MTLTextureUsageShaderRead|MTLTextureUsageShaderWrite|MTLTextureUsageRenderTarget;
    if (samples>1) { d.textureType=MTLTextureType2DMultisample; d.sampleCount=samples; d.usage=MTLTextureUsageRenderTarget; }
    if (raster) {
        a.surface=IOSurfaceCreate((__bridge CFDictionaryRef)@{
            (__bridge NSString *)kIOSurfaceWidth:@(width),(__bridge NSString *)kIOSurfaceHeight:@(height),
            (__bridge NSString *)kIOSurfaceBytesPerElement:@(bpp),(__bridge NSString *)kIOSurfaceBytesPerRow:@(row),
            (__bridge NSString *)kIOSurfaceAllocSize:@(reserved),(__bridge NSString *)kIOSurfacePixelFormat:@((uint32_t)'BGRA')});
        d.storageMode=MTLStorageModeShared;
        if (a.surface) a.texture=[STNDevice newTextureWithDescriptor:d iosurface:a.surface plane:0];
    } else {
        d.storageMode=MTLStorageModePrivate;
        a.texture=[STNDevice newTextureWithDescriptor:d];
    }
    if (!a.texture) return nil;
    // Individually allocated textures report the Metal allocation, IOSurfaces the
    // actual aligned allocation. They are one charge, never two charges.
    NSUInteger actual=raster ? IOSurfaceGetAllocSize(a.surface) : MAX(reserved,a.texture.allocatedSize);
    [STNMemoryLock lock];
    if (actual>reserved && (actual-reserved>STNAdmissionCapacity || STNAllocatedBytes>STNAdmissionCapacity-(actual-reserved))) {
        [STNMemoryLock unlock]; return nil;
    }
    STNAllocatedBytes+=actual-reserved; a.bytes=actual; [STNMemoryLock unlock];
    return a;
}
static void STNCalibrateBandwidth(void) {
    NSUInteger length=32*1024*1024;
    [STNMemoryLock lock]; BOOL admitted=STNAllocatedBytes+2*length<=STNAdmissionCapacity;
    if (admitted) STNAllocatedBytes+=2*length; [STNMemoryLock unlock]; if (!admitted||!STNDevice) return;
    STNMetalAllocation *a=[STNMetalAllocation new],*b=[STNMetalAllocation new]; a.bytes=b.bytes=length;
    a.buffer=[STNDevice newBufferWithLength:length options:MTLResourceStorageModeShared|MTLResourceHazardTrackingModeTracked];
    b.buffer=[STNDevice newBufferWithLength:length options:MTLResourceStorageModeShared|MTLResourceHazardTrackingModeTracked];
    if (!a.buffer||!b.buffer) return;
    memset(a.buffer.contents,0,length);
    id<MTLCommandQueue> queue=[STNDevice newCommandQueue]; id<MTLCommandBuffer> buffer=[queue commandBuffer];
    id<MTLBlitCommandEncoder> e=[buffer blitCommandEncoder];
    for (NSUInteger i=0;i<16;i++) {
        [e copyFromBuffer:a.buffer sourceOffset:0 toBuffer:b.buffer destinationOffset:0 size:length];
        [e copyFromBuffer:b.buffer sourceOffset:0 toBuffer:a.buffer destinationOffset:0 size:length];
    }
    [e endEncoding]; [buffer addCompletedHandler:^(id<MTLCommandBuffer> completed) {
        double seconds=completed.GPUEndTime-completed.GPUStartTime;
        if (completed.status==MTLCommandBufferStatusCompleted&&seconds>0) {
            [STNMemoryLock lock]; STNCopyBandwidth=(double)length*64/seconds; [STNMemoryLock unlock];
        }
        (void)a; (void)b; (void)queue;
    }]; [buffer commit];
}

// Lazy per-host cursors: no large window fills a global operation queue with
// thousands of tiles. Active workers are the only dispatched runnable jobs.
@interface STNRasterBatch : NSObject
@property(nonatomic, strong) NSArray<void (^)(void)> *jobs;
@property(nonatomic) NSUInteger cursor, running;
@property(nonatomic, copy) void (^completion)(void);
@end
@implementation STNRasterBatch
@end

@interface STNRasterWorkers : NSObject
@property(nonatomic, strong) NSMutableArray<STNRasterBatch *> *batches;
@property(nonatomic) NSUInteger active, limit, next;
@property(nonatomic) NSUInteger peak;
- (void)add:(NSArray<void (^)(void)> *)jobs completion:(void (^)(void))completion;
@end
@implementation STNRasterWorkers
- (instancetype)init {
    if ((self=[super init])) { _batches=[NSMutableArray new]; _limit=MAX(1,MIN(4,(NSInteger)NSProcessInfo.processInfo.activeProcessorCount-1)); }
    return self;
}
- (void)pump {
    while (self.active<self.limit && self.batches.count) {
        STNRasterBatch *selected=nil;
        NSUInteger count=self.batches.count;
        for (NSUInteger i=0;i<count;i++) {
            self.next%=self.batches.count;
            STNRasterBatch *b=self.batches[self.next]; self.next=(self.next+1)%self.batches.count;
            NSUInteger cap=count>1 ? (self.limit+1)/2 : self.limit;
            if (b.cursor<b.jobs.count && b.running<cap) { selected=b; break; }
        }
        if (!selected) break;
        void (^job)(void)=selected.jobs[selected.cursor++]; selected.running++; self.active++;
        self.peak=MAX(self.peak,self.active);
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0), ^{
            @autoreleasepool { job(); }
            @synchronized(self) {
                selected.running--; self.active--;
                if (selected.cursor==selected.jobs.count && !selected.running) {
                    [self.batches removeObjectIdenticalTo:selected]; selected.completion();
                }
                [self pump];
            }
        });
    }
}
- (void)add:(NSArray<void (^)(void)> *)jobs completion:(void (^)(void))completion {
    if (!jobs.count) { completion(); return; }
    STNRasterBatch *b=[STNRasterBatch new]; b.jobs=jobs; b.completion=completion;
    @synchronized(self) { [self.batches addObject:b]; [self pump]; }
}
@end
static STNRasterWorkers *STNWorkers(void) {
    static STNRasterWorkers *workers; static dispatch_once_t once;
    dispatch_once(&once, ^{ workers=[STNRasterWorkers new]; }); return workers;
}

@interface STNMetalPrepared : NSObject
@property(nonatomic, strong) NSDictionary *scene;
@property(nonatomic, strong) STNMetalSurface *final;
@property(nonatomic, strong) NSArray *leases;
@property(nonatomic) uint64_t epoch, revision;
@property(nonatomic) BOOL linear, extendedOutput;
@property(nonatomic) double headroom;
@property(nonatomic) double targetTimestamp, framePeriod;
@property(nonatomic) double preparationStart, offscreenSeconds;
@property(nonatomic) BOOL direct;
@property(atomic, strong) STNPacketPermit *permit;
@property(nonatomic, strong) STNMetalAllocation *drawableAllowance;
@end
@implementation STNMetalPrepared
@end

@interface STNMetalRenderer ()
@property(nonatomic, strong) id<MTLCommandQueue> queue;
@property(nonatomic, strong) id<MTLLibrary> library;
@property(nonatomic, strong) NSMutableDictionary<NSString *, id> *pipelines;
@property(nonatomic, strong) NSMutableDictionary<NSString *, STNMetalSurface *> *cache;
@property(nonatomic, strong) NSMutableDictionary<NSString *, id> *programCache;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *validPrograms, *pendingPrograms;
@property(nonatomic, strong) NSMutableDictionary<NSString *, STNMetalSurface *> *programOutputs, *pendingOutputs;
@property(nonatomic, strong) NSMutableSet<NSString *> *usedPrograms;
@property(nonatomic) uint64_t preparingRevision, preparingEpoch;
@property(nonatomic) BOOL programUnavailable;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *state;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *counts;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSMutableArray<NSDictionary *> *> *timings;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *objects, *expandedObjects;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *scales;
@property(nonatomic, strong) NSMapTable<id<MTLTexture>, STNMetalAllocation *> *multisample;
@property(nonatomic) NSUInteger currentSampleCount;
@property(nonatomic, copy) NSString *latestRoot;
@property(nonatomic, strong) NSMutableSet<NSString *> *usedKeys;
@property(nonatomic, strong) dispatch_queue_t encoding;
@property(nonatomic, strong) CADisplayLink *displayLink;
@property(nonatomic, strong) NSDictionary *desired;
@property(nonatomic, strong) STNMetalPrepared *ready, *last;
@property(nonatomic, strong) id<MTLTexture> transparent;
@property(nonatomic, strong) STNMetalAllocation *drawableAllowance;
@property(nonatomic) NSUInteger drawableAllowanceKey;
@property(atomic) BOOL preparing, acquiring, animation, demand, detached, workingLinear;
@property(nonatomic) BOOL profileDirty, windowHDRDemand;
@property(nonatomic) BOOL observationsPaused;
@property(atomic) uint64_t epoch, sequence, submittedRevision;
@property(atomic) uint64_t failedEpoch;
@property(nonatomic) uint64_t watchdogRevision;
@property(nonatomic) double noHDRSince, promotedAt, retryDelay;
@property(nonatomic) NSUInteger frameIndex, denseFrames, sparseFrames, lastModeSwitch;
@property(nonatomic) BOOL directMode;
@property(nonatomic) double persistentCost, directCost;
@property(nonatomic) double nativeScale;
@property(nonatomic) double copyBytesPerFrame, requestedRate, negotiatedRate;
@property(atomic) double minimumFramePeriod;
@property(nonatomic) double preparationEWMA, totalGPUEWMA, copyGPUEWMA;
@property(nonatomic) NSUInteger completedPreparations;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *pathCosts;
@property(atomic) int32_t forcedFinalMode;
@property(atomic) double rasterDelay;
@property(atomic) BOOL starved;
@property(atomic, copy) NSString *failure;
@end

@implementation STNMetalRenderer
- (instancetype)initWithHost:(STNWindowHost *)host {
    STNMetalInitializeDevice();
    if (!STNDevice) return nil;
    if ((self=[super init])) {
        _host=host; _epoch=1; _retryDelay=0.016;
        _queue=[STNDevice newCommandQueue]; if (!_queue) return nil;
        _encoding=dispatch_queue_create("dev.stana.metal.host",DISPATCH_QUEUE_SERIAL);
        _pipelines=[NSMutableDictionary new]; _cache=[NSMutableDictionary new]; _programCache=[NSMutableDictionary new];
        _state=[NSMutableDictionary new]; _counts=[NSMutableDictionary new];
        _timings=[NSMutableDictionary new];
        _validPrograms=[NSMutableDictionary new]; _pendingPrograms=[NSMutableDictionary new]; _usedPrograms=[NSMutableSet new];
        _programOutputs=[NSMutableDictionary new]; _pendingOutputs=[NSMutableDictionary new];
        _objects=[NSMutableDictionary new]; _expandedObjects=[NSMutableDictionary new];
        _scales=[NSMutableDictionary new];
        _pathCosts=[NSMutableDictionary new];
        _multisample=[NSMapTable weakToStrongObjectsMapTable]; _currentSampleCount=1;
        _layer=[CAMetalLayer layer]; _layer.device=STNDevice; _layer.pixelFormat=MTLPixelFormatBGRA8Unorm;
        _layer.framebufferOnly=YES; _layer.opaque=host.surfaceOpaque; _layer.maximumDrawableCount=3;
        CGColorSpaceRef color=CGColorSpaceCreateWithName(kCGColorSpaceSRGB); _layer.colorspace=color; CGColorSpaceRelease(color);
        host.view.layer=_layer; host.view.wantsLayer=YES; _layer.frame=host.view.bounds;
        _displayLink=[host.view displayLinkWithTarget:self selector:@selector(tick:)];
        [_displayLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes]; _displayLink.paused=YES;
        [STNRenderers addObject:self];
    }
    return self;
}
- (void)count:(NSString *)name amount:(NSUInteger)n {
    self.counts[name]=@([self.counts[name] unsignedLongLongValue]+n);
}
- (void)recordUIPlanning:(double)planning transport:(double)transport scene:(uint64_t)scene {
    dispatch_async(self.encoding, ^{
        [self timing:@"uiPlanning" milliseconds:planning scene:scene];
        [self timing:@"uiTransport" milliseconds:transport scene:scene];
    });
}
- (void)recordInputTimestamp:(double)arrival started:(double)start {
    double end=CACurrentMediaTime(); uint64_t scene=STNUInt64(self.desired[@"revision"]);
    dispatch_async(self.encoding, ^{
        if (isfinite(arrival)&&arrival>0&&start>=arrival) [self timing:@"inputArrivalToDispatch" milliseconds:(start-arrival)*1000 scene:scene];
        [self timing:@"uiInputOccupancy" milliseconds:(end-start)*1000 scene:scene];
    });
}
- (void)timing:(NSString *)name milliseconds:(double)value scene:(uint64_t)scene {
    if (!isfinite(value)||value<0) return;
    NSMutableArray *samples=self.timings[name]; if (!samples) { samples=[NSMutableArray new]; self.timings[name]=samples; }
    if (samples.count==8192) [samples removeObjectAtIndex:0];
    [samples addObject:@{@"sceneRevision":@(scene),@"milliseconds":@(value)}];
}
- (void)emit:(int32_t)kind frame:(STNMetalPrepared *)frame sequence:(uint64_t)sequence time:(double)time message:(NSString *)message {
    double enqueued=CACurrentMediaTime();
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.detached) return;
        [self.host emit:(stn_event){.kind=kind,.identity=frame.revision,.epoch=frame.epoch,.sequence=sequence,.x=time,.text=STNBorrowedString(message)}];
        if (kind==19) {
            double delivered=CACurrentMediaTime();
            dispatch_async(self.encoding, ^{
                [self timing:@"acknowledgementDelivery" milliseconds:(delivered-enqueued)*1000 scene:frame.revision];
                if (time>0) [self timing:@"presentedTimestampDelay" milliseconds:(enqueued-time)*1000 scene:frame.revision];
            });
        }
    });
}
- (void)requestFrame {
    if (self.detached) return;
    self.demand=YES;
    if (!self.observationsPaused&&!self.preparing&&!self.acquiring&&!self.ready) self.displayLink.paused=NO;
}
- (void)pauseForObservations:(BOOL)paused {
    self.observationsPaused=paused;
    if (paused) self.displayLink.paused=YES; else [self requestFrame];
}
- (void)setAnimationDemand:(BOOL)active {
    self.animation=active;
    if (active) [self requestFrame];
    else if (!self.demand) self.displayLink.paused=YES;
}
- (void)testFinalMode:(int32_t)mode rasterDelay:(double)delay starved:(BOOL)starved {
    self.forcedFinalMode=mode; self.rasterDelay=MAX(0,MIN(1,delay)); self.starved=starved;
    if (!starved&&self.ready) [self presentReady];
}
- (void)tick:(CADisplayLink *)link {
    if (self.observationsPaused) { link.paused=YES; return; }
    STNWindowHost *host=self.host;
    if (!host || self.detached || !host.view.window || !host.window.visible || host.window.miniaturized) { link.paused=YES; return; }
    if (self.preparing||self.acquiring||self.ready) { link.paused=YES; return; }
    BOOL requested=self.demand; self.demand=NO; link.paused=YES;
    double uiStart=CACurrentMediaTime();
    [host emit:(stn_event){.kind=16,.x=link.timestamp,.y=link.targetTimestamp}];
    if (host.drawCallback) host.drawCallback(host.context);
    double uiDuration=(CACurrentMediaTime()-uiStart)*1000; uint64_t uiScene=STNUInt64(self.desired[@"revision"]);
    dispatch_async(self.encoding, ^{ [self timing:@"uiFrameOccupancy" milliseconds:uiDuration scene:uiScene]; });
    if (!self.preparing&&self.profileDirty&&self.desired) { self.profileDirty=NO; [self submit:self.desired]; }
    if (!self.preparing&&requested&&self.last) { self.ready=self.last; [self presentReady]; }
    if (!self.preparing&&self.animation) link.paused=NO;
}
- (void)invalidate {
    self.epoch++; self.ready=nil; self.desired=nil; self.watchdogRevision=0;
    self.failedEpoch=0;
    dispatch_async(self.encoding, ^{
        [self.cache removeAllObjects]; [self.state removeAllObjects]; [self.programOutputs removeAllObjects];
        [self.pendingOutputs removeAllObjects]; [self.multisample removeAllObjects];
    });
    [self requestFrame];
}
- (void)retryPresentation:(uint64_t)revision {
    if (self.watchdogRevision==revision||self.preparing||self.acquiring||self.ready||self.last.revision!=revision||self.last.epoch!=self.epoch) return;
    self.watchdogRevision=revision; self.ready=self.last; [self presentReady];
}
- (void)detach {
    self.detached=YES; [self.displayLink invalidate]; self.displayLink=nil;
    self.desired=nil; self.ready=nil; self.last=nil;
    [self refreshWindowColorDemand];
    dispatch_async(self.encoding, ^{ [self.cache removeAllObjects]; [self.state removeAllObjects]; [self.programCache removeAllObjects]; });
}
- (void)fail:(NSString *)reason frame:(STNMetalPrepared *)frame {
    self.failure=reason ?: @"Metal resource or pipeline failure";
    [self emit:20 frame:frame sequence:0 time:0 message:self.failure];
    frame.permit=nil;
    dispatch_async(dispatch_get_main_queue(), ^{ self.preparing=NO; if (self.demand) [self requestFrame]; });
}
- (void)gpuFailure:(NSString *)reason frame:(STNMetalPrepared *)frame sequence:(uint64_t)sequence {
    if (frame.epoch==self.epoch) self.failedEpoch=frame.epoch;
    self.failure=reason ?: @"GPU execution failed"; frame.permit=nil;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (frame.epoch==self.epoch) { self.displayLink.paused=YES; self.demand=NO; self.preparing=NO; }
    });
    [self emit:24 frame:frame sequence:sequence time:0 message:self.failure];
}
- (STNMetalAllocation *)allocation:(NSUInteger)width height:(NSUInteger)height format:(MTLPixelFormat)format raster:(BOOL)raster leases:(NSMutableArray *)leases {
    STNMetalAllocation *a=STNAllocate(width,height,format,raster,1);
    if (!a) self.failure=@"Metal allocation exceeds device capacity, dimensions, or 256 MiB limit";
    if (a) { [leases addObject:a]; [self count:raster?@"rasterAllocationBytes":@"gpuAllocationBytes" amount:a.bytes]; }
    return a;
}
- (id<MTLBuffer>)buffer:(NSData *)data length:(NSUInteger)length leases:(NSMutableArray *)leases {
    if (!length||length>STNSingleAllocationLimit) { self.failure=@"Invalid buffer dimensions or 256 MiB limit"; return nil; }
    NSUInteger reserved=(length+4095)&~(NSUInteger)4095;
    [STNMemoryLock lock]; BOOL admitted=reserved<=STNAdmissionCapacity&&STNAllocatedBytes<=STNAdmissionCapacity-reserved;
    if (admitted) STNAllocatedBytes+=reserved; [STNMemoryLock unlock];
    if (!admitted) { self.failure=@"Buffer exceeds device admission capacity"; return nil; }
    STNMetalAllocation *owner=[STNMetalAllocation new]; owner.bytes=reserved;
    owner.buffer=data?[STNDevice newBufferWithBytes:data.bytes length:length options:MTLResourceStorageModeShared|MTLResourceHazardTrackingModeTracked]:[STNDevice newBufferWithLength:length options:MTLResourceStorageModeShared|MTLResourceHazardTrackingModeTracked];
    if (!owner.buffer) { self.failure=@"Metal buffer allocation failed"; return nil; }
    [leases addObject:owner]; [self count:@"bufferAllocationBytes" amount:reserved]; return owner.buffer;
}
- (STNMetalAllocation *)reserveDrawablePool:(NSUInteger)bytes {
    if (self.drawableAllowanceKey==bytes) return self.drawableAllowance;
    [STNMemoryLock lock]; BOOL admitted=bytes<=STNAdmissionCapacity&&STNAllocatedBytes<=STNAdmissionCapacity-bytes;
    if (admitted) STNAllocatedBytes+=bytes; [STNMemoryLock unlock];
    if (!admitted) { self.failure=@"Estimated drawable-pool allowance exceeds device capacity"; return nil; }
    STNMetalAllocation *allowance=[STNMetalAllocation new]; allowance.bytes=bytes;
    self.drawableAllowance=allowance; self.drawableAllowanceKey=bytes; self.counts[@"drawablePoolEstimatedBytes"]=@(bytes);
    return allowance;
}
- (id<MTLRenderPipelineState>)pipeline:(NSString *)fragment format:(MTLPixelFormat)format blend:(BOOL)blend mesh:(BOOL)mesh {
    NSString *key=[NSString stringWithFormat:@"%@:%lu:%d:%d:%lu",fragment,(unsigned long)format,blend,mesh,(unsigned long)self.currentSampleCount];
    id<MTLRenderPipelineState> cached=self.pipelines[key] ?: [STNSharedPipelines objectForKey:key];
    if (cached) { [self count:@"pipelineHits" amount:1]; return cached; }
    MTLRenderPipelineDescriptor *d=[MTLRenderPipelineDescriptor new];
    d.vertexFunction=[self.library newFunctionWithName:mesh?@"stn_mesh":([fragment isEqual:@"stn_present_batch"]?@"stn_batch_quad":@"stn_quad")];
    d.fragmentFunction=[self.library newFunctionWithName:fragment]; d.colorAttachments[0].pixelFormat=format;
    d.rasterSampleCount=self.currentSampleCount ?: 1;
    d.colorAttachments[0].blendingEnabled=blend;
    d.colorAttachments[0].sourceRGBBlendFactor=MTLBlendFactorOne; d.colorAttachments[0].sourceAlphaBlendFactor=MTLBlendFactorOne;
    d.colorAttachments[0].destinationRGBBlendFactor=MTLBlendFactorOneMinusSourceAlpha;
    d.colorAttachments[0].destinationAlphaBlendFactor=MTLBlendFactorOneMinusSourceAlpha;
    NSError *error; cached=[STNDevice newRenderPipelineStateWithDescriptor:d error:&error];
    if (!cached) { self.failure=error.localizedDescription; return nil; }
    self.pipelines[key]=cached; [STNSharedPipelines setObject:cached forKey:key]; [self count:@"pipelineMisses" amount:1]; return cached;
}
- (id<MTLComputePipelineState>)compute:(NSString *)name {
    id<MTLComputePipelineState> p=self.pipelines[name] ?: [STNSharedPipelines objectForKey:name];
    if (!p) {
        NSError *error; p=[STNDevice newComputePipelineStateWithFunction:[self.library newFunctionWithName:name] error:&error];
        if (p) { self.pipelines[name]=p; [STNSharedPipelines setObject:p forKey:name]; } else self.failure=error.localizedDescription;
    }
    return p;
}
- (id<MTLRenderCommandEncoder>)encoder:(id<MTLCommandBuffer>)buffer target:(id<MTLTexture>)texture clear:(BOOL)clear {
    MTLRenderPassDescriptor *d=[MTLRenderPassDescriptor renderPassDescriptor];
    d.colorAttachments[0].texture=texture; d.colorAttachments[0].loadAction=clear?MTLLoadActionClear:MTLLoadActionLoad;
    d.colorAttachments[0].storeAction=MTLStoreActionStore; d.colorAttachments[0].clearColor=MTLClearColorMake(0,0,0,0);
    STNMetalAllocation *msaa=[self.multisample objectForKey:texture]; self.currentSampleCount=msaa?4:1;
    if (msaa) {
        d.colorAttachments[0].texture=msaa.texture; d.colorAttachments[0].resolveTexture=texture;
        d.colorAttachments[0].storeAction=MTLStoreActionStoreAndMultisampleResolve;
    }
    return [buffer renderCommandEncoderWithDescriptor:d];
}
- (STNMetalQuad)quad:(CGRect)rect target:(CGRect)target transform:(CGAffineTransform)t linear:(BOOL)linear {
    STNMetalQuad q={0}; q.rect=STNVector(rect); q.uv=(vector_float4){0,0,1,1}; q.color=(vector_float4){1,1,1,1};
    q.target=STNVector(target); q.row0=(vector_float4){t.a,t.c,t.tx,0}; q.row1=(vector_float4){t.b,t.d,t.ty,0};
    q.options.z=1; q.linear=linear; q.sourceLinear=linear; return q;
}
- (void)draw:(STNMetalQuad)q texture:(id<MTLTexture>)texture encoder:(id<MTLRenderCommandEncoder>)encoder format:(MTLPixelFormat)format fragment:(NSString *)fragment blend:(BOOL)blend {
    id<MTLRenderPipelineState> pipeline=[self pipeline:fragment format:format blend:blend mesh:NO];
    if (!pipeline) return;
    [encoder setRenderPipelineState:pipeline]; [encoder setVertexBytes:&q length:sizeof(q) atIndex:0];
    [encoder setFragmentBytes:&q length:sizeof(q) atIndex:0];
    [encoder setFragmentTexture:texture ?: self.transparent atIndex:0];
    [encoder useResource:texture ?: self.transparent usage:MTLResourceUsageRead stages:MTLRenderStageFragment];
    [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6];
}
- (NSArray<STNMetalTile *> *)tiles:(CGRect)bounds scale:(double)scale format:(MTLPixelFormat)format raster:(BOOL)raster leases:(NSMutableArray *)leases {
    NSArray *tiles=[self tileLayout:bounds scale:scale];
    if (!tiles) return nil;
    for (STNMetalTile *tile in tiles) {
        tile.allocation=[self allocation:(NSUInteger)llround(tile.padded.size.width*scale) height:(NSUInteger)llround(tile.padded.size.height*scale) format:format raster:raster leases:leases];
        if (!tile.allocation) return nil;
    }
    return tiles;
}
- (NSArray<STNMetalTile *> *)tileLayout:(CGRect)bounds scale:(double)scale {
    return [self tileLayout:bounds scale:scale visible:bounds];
}
- (NSArray<STNMetalTile *> *)tileLayout:(CGRect)bounds scale:(double)scale visible:(CGRect)visible {
    double x=floor(bounds.origin.x*scale), y=floor(bounds.origin.y*scale);
    double maxX=ceil(CGRectGetMaxX(bounds)*scale), maxY=ceil(CGRectGetMaxY(bounds)*scale);
    if (!isfinite(x)||!isfinite(y)||!isfinite(maxX)||!isfinite(maxY)||maxX<=x||maxY<=y) return @[];
    double width=maxX-x,height=maxY-y;
    BOOL tiled=width>1024||height>1024||width*height>1000000;
    if (self.forcedFinalMode==4 || [NSProcessInfo.processInfo.environment[@"STANA_METAL_UNTILED"] boolValue]) tiled=NO;
    NSUInteger edge=tiled?512:(NSUInteger)MAX(width,height);
    CGRect needed=CGRectIntersection(bounds,CGRectInset(visible,-(double)edge/scale,-(double)edge/scale));
    if (CGRectIsNull(needed)||CGRectIsEmpty(needed)) return @[];
    double firstX=x+MAX(0,floor((needed.origin.x*scale-x)/edge))*edge;
    double firstY=y+MAX(0,floor((needed.origin.y*scale-y)/edge))*edge;
    double endX=MIN(maxX,x+ceil((CGRectGetMaxX(needed)*scale-x)/edge)*edge);
    double endY=MIN(maxY,y+ceil((CGRectGetMaxY(needed)*scale-y)/edge)*edge);
    if ((endX-firstX)/edge*(endY-firstY)/edge>16384) { self.failure=@"Visible surface tile budget exceeded"; return nil; }
    NSMutableArray *tiles=[NSMutableArray new];
    // Grid anchored in surface-local coordinates, never at a damage rectangle.
    for (double ty=firstY;ty<endY;ty+=edge) for (double tx=firstX;tx<endX;tx+=edge) {
        CGRect core=CGRectMake(tx/scale,ty/scale,MIN(edge,maxX-tx)/scale,MIN(edge,maxY-ty)/scale);
        CGRect padded=CGRectInset(core,-2/scale,-2/scale);
        STNMetalTile *tile=[STNMetalTile new]; tile.core=core; tile.padded=padded; [tiles addObject:tile];
    }
    return tiles;
}
- (void)rasterCommands:(NSArray *)commands tile:(STNMetalTile *)tile scale:(double)scale {
    double delay=self.rasterDelay;
    if (delay>0) [NSThread sleepForTimeInterval:delay];
    IOSurfaceRef surface=tile.allocation.surface;
    if (IOSurfaceLock(surface,0,NULL)!=kIOReturnSuccess) { self.failure=@"IOSurface writer lock failed"; return; }
    size_t width=IOSurfaceGetWidth(surface),height=IOSurfaceGetHeight(surface);
    CGColorSpaceRef color=CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef c=CGBitmapContextCreate(IOSurfaceGetBaseAddress(surface),width,height,8,IOSurfaceGetBytesPerRow(surface),color,kCGImageAlphaPremultipliedFirst|kCGBitmapByteOrder32Little);
    CGColorSpaceRelease(color);
    if (!c) { IOSurfaceUnlock(surface,0,NULL); self.failure=@"CoreGraphics context creation failed"; return; }
    CGContextClearRect(c,CGRectMake(0,0,width,height));
    CGContextTranslateCTM(c,0,height); CGContextScaleCTM(c,scale,-scale);
    CGContextTranslateCTM(c,-tile.padded.origin.x,-tile.padded.origin.y);
    for (NSDictionary *command in commands) {
        if (self.detached) break;
        NSString *op=command[@"op"];
        CGRect r=command[@"rect"]?STNArrayRect(command[@"rect"]):CGRectZero;
        stn_color color=command[@"color"]?STNArrayColor(command[@"color"]):(stn_color){0};
        if ([op isEqual:@"fill"]) STNRasterFill(c,STNABI(r),color,[command[@"radius"] doubleValue]);
        else if ([op isEqual:@"stroke"]) STNRasterStroke(c,STNABI(r),color,[command[@"width"] doubleValue],[command[@"radius"] doubleValue]);
        else if ([op isEqual:@"text"]) STNRasterText(c,STNBorrowedString(command[@"text"]),STNABI(r),[command[@"size"] doubleValue],[command[@"weight"] doubleValue],color,[command[@"wraps"] boolValue]);
        else if ([op isEqual:@"image"]) STNRasterImage(c,[[NSData alloc] initWithBase64EncodedString:command[@"data"] options:0],STNABI(r));
        else if ([op isEqual:@"clip"]) { CGContextSaveGState(c); CGContextClipToRect(c,r); }
        else if ([op isEqual:@"unclip"]) CGContextRestoreGState(c);
        else if ([op isEqual:@"opacity"]) { CGContextSaveGState(c); CGContextSetAlpha(c,[command[@"opacity"] doubleValue]); CGContextBeginTransparencyLayer(c,NULL); }
        else if ([op isEqual:@"endOpacity"]) { CGContextEndTransparencyLayer(c); CGContextRestoreGState(c); }
        else if ([op isEqual:@"transform"]) { CGContextSaveGState(c); CGContextConcatCTM(c,STNArrayTransform(command[@"matrix"])); }
        else if ([op isEqual:@"endTransform"]) CGContextRestoreGState(c);
        else if ([op isEqual:@"roundedClip"]) {
            CGContextSaveGState(c); double radius=[command[@"radius"] doubleValue];
            CGPathRef path=CGPathCreateWithRoundedRect(r,radius,radius,NULL); CGContextAddPath(c,path); CGContextClip(c); CGPathRelease(path);
        }
    }
    CGContextFlush(c); CGContextRelease(c); IOSurfaceUnlock(surface,0,NULL);
}
- (NSString *)signature:(NSDictionary *)node {
    if (![node[@"kind"] isEqual:@"group"]) return [NSString stringWithFormat:@"%@:%@:%@",node[@"id"],node[@"version"],node[@"bounds"]];
    NSMutableString *key=[NSMutableString stringWithFormat:@"%@:%@:%@:%@:%@:%@",node[@"id"],node[@"bounds"],node[@"transform"],node[@"opacity"],node[@"radius"],node[@"backdrop"]?:@""];
    for (NSDictionary *child in node[@"children"]) [key appendString:[self signature:child]];
    return key;
}
- (CGRect)contentBounds:(NSDictionary *)node {
    CGRect bounds=STNArrayRect(node[@"bounds"]);
    if ([node[@"kind"] isEqual:@"group"] && ![node[@"clip"] boolValue]) {
        for (NSDictionary *child in node[@"children"]) {
            CGRect r=[self contentBounds:child];
            if ([child[@"kind"] isEqual:@"group"]) r=CGRectApplyAffineTransform(r,STNAnchoredTransform(child));
            bounds=CGRectUnion(bounds,r);
        }
    }
    return bounds;
}
- (NSMutableDictionary *)prepareTree:(NSDictionary *)node scale:(double)scale visible:(CGRect)visible world:(CGAffineTransform)world jobs:(NSMutableArray *)jobs leases:(NSMutableArray *)leases {
    NSMutableDictionary *prepared=[node mutableCopy]; NSString *kind=node[@"kind"];
    if ([kind isEqual:@"group"]) {
        CGAffineTransform local=STNAnchoredTransform(node);
        if (STNInvertible(local)) visible=CGRectApplyAffineTransform(visible,CGAffineTransformInvert(local));
        else visible=CGRectZero;
        world=STNCompose(world,local);
        CGRect extent=[self contentBounds:node];
        if ([node[@"clip"] boolValue]) visible=CGRectIntersection(visible,extent);
        // Reverse paint-order closure keeps off-output contributors required by
        // visible filters, including chains of overlapping backdrop entries.
        for (NSDictionary *child in [node[@"children"] reverseObjectEnumerator]) if (child[@"backdrop"]) {
            CGAffineTransform t=STNAnchoredTransform(child);
            CGRect output=CGRectApplyAffineTransform(STNArrayRect(child[@"bounds"]),t);
            if (!CGRectIntersectsRect(output,visible)) continue;
            NSDictionary *effect=child[@"backdrop"]; BOOL custom=[effect[@"kind"] isEqual:@"program"];
            if (custom&&!effect[@"program"][@"samplingRadius"]) visible=extent;
            else {
                double radius=custom?[effect[@"program"][@"samplingRadius"] doubleValue]:[effect[@"radius"] doubleValue];
                double x=(radius+2/scale)*(fabs(t.a)+fabs(t.c)),y=(radius+2/scale)*(fabs(t.b)+fabs(t.d));
                visible=CGRectUnion(visible,CGRectIntersection(CGRectInset(output,-x,-y),extent));
            }
        }
    }
    prepared[@"visible"]=[NSValue valueWithRect:NSRectFromCGRect(visible)];
    if ([kind isEqual:@"gpu"]) for (NSDictionary *command in node[@"commands"]) if ([command[@"op"] isEqual:@"program"]) [self.usedPrograms addObject:node[@"id"]];
    if ([node[@"backdrop"][@"kind"] isEqual:@"program"]) [self.usedPrograms addObject:[@"backdrop:" stringByAppendingString:node[@"id"]]];
    if ([kind isEqual:@"cpu"]) {
        NSString *slot=[@"cpu:" stringByAppendingString:node[@"id"]]; [self.usedKeys addObject:slot];
        NSString *key=[NSString stringWithFormat:@"%@:%g:%@:%d",[self signature:node],scale,NSStringFromRect(NSRectFromCGRect(visible)),self.forcedFinalMode==4];
        STNMetalSurface *surface=self.cache[slot];
        if (surface && [surface.key isEqual:key] && surface.valid) {
            [self.usedKeys addObjectsFromArray:surface.cacheKeys ?: @[]];
            [self count:@"tileHits" amount:surface.tiles.count]; prepared[@"surface"]=surface; return prepared;
        }
        surface=[STNMetalSurface new]; surface.key=key; surface.scale=scale; surface.bounds=[self contentBounds:node];
        NSMutableArray *tiles=[[self tileLayout:surface.bounds scale:scale visible:visible] mutableCopy],*cacheKeys=[NSMutableArray new];
        if (!tiles) return nil;
        for (NSUInteger tileIndex=0;tileIndex<tiles.count;tileIndex++) {
            STNMetalTile *tile=tiles[tileIndex];
            NSString *tileSlot=[NSString stringWithFormat:@"%@#tile:%g,%g",slot,tile.core.origin.x*scale,tile.core.origin.y*scale];
            [cacheKeys addObject:tileSlot]; [self.usedKeys addObject:tileSlot];
            NSMutableString *tileKey=[NSMutableString stringWithFormat:@"%g:%@",scale,NSStringFromRect(NSRectFromCGRect(tile.padded))];
            NSMutableArray *commands=[NSMutableArray new];
            if (node[@"items"]) {
                for (NSDictionary *item in node[@"items"]) if (CGRectIntersectsRect(STNArrayRect(item[@"bounds"]),tile.padded)) {
                    [tileKey appendFormat:@"%@:%@",item[@"id"],item[@"version"]]; [commands addObjectsFromArray:item[@"commands"]];
                }
            } else { [tileKey appendString:key]; [commands addObjectsFromArray:node[@"commands"]]; }
            STNMetalSurface *cached=self.cache[tileSlot];
            if (cached.valid&&[cached.key isEqual:tileKey]) { tiles[tileIndex]=cached.tiles[0]; [self count:@"tileHits" amount:1]; continue; }
            tile.allocation=[self allocation:(NSUInteger)llround(tile.padded.size.width*scale) height:(NSUInteger)llround(tile.padded.size.height*scale) format:MTLPixelFormatBGRA8Unorm raster:YES leases:leases];
            if (!tile.allocation) return nil;
            tile.key=tileKey;
            STNMetalSurface *version=[STNMetalSurface new]; version.key=tileKey; version.tiles=@[tile]; version.valid=YES; self.cache[tileSlot]=version;
            NSArray *immutableCommands=[commands copy];
            double enqueued=CACurrentMediaTime(); uint64_t revision=self.preparingRevision;
            [jobs addObject:^{
                double start=CACurrentMediaTime(),cpu=STNThreadCPUTime();
                [self rasterCommands:immutableCommands tile:tile scale:scale];
                double elapsed=CACurrentMediaTime()-start,elapsedCPU=STNThreadCPUTime()-cpu;
                dispatch_async(self.encoding, ^{
                    [self timing:@"rasterQueueDelay" milliseconds:(start-enqueued)*1000 scene:revision];
                    [self timing:@"rasterWorkerWall" milliseconds:elapsed*1000 scene:revision];
                    [self timing:@"rasterWorkerCPU" milliseconds:elapsedCPU*1000 scene:revision];
                });
            }];
            [self count:@"tileMisses" amount:1];
            [self count:@"rasterPixels" amount:tile.allocation.texture.width*tile.allocation.texture.height];
        }
        surface.tiles=tiles; surface.cacheKeys=cacheKeys;
        surface.valid=YES; self.cache[slot]=surface; prepared[@"surface"]=surface;
    } else if ([kind isEqual:@"group"]) {
        CGAffineTransform t=world;
        double trace=t.a*t.a+t.b*t.b+t.c*t.c+t.d*t.d, det=t.a*t.d-t.b*t.c;
        double singular=sqrt(MAX(0,(trace+sqrt(MAX(0,trace*trace-4*det*det)))/2));
        double required=self.nativeScale*singular,now=CACurrentMediaTime(),native=self.nativeScale ?: scale;
        NSDictionary *oldScale=self.scales[node[@"id"]];
        double cached=[oldScale[@"scale"] doubleValue],lowSince=[oldScale[@"lowSince"] doubleValue];
        double chosen=required<=native?native:native*pow(sqrt(2),ceil(log(required*1.125/native)/log(sqrt(2))));
        double rasterScale=cached>0?cached:chosen;
        if (required>rasterScale*1.05) { rasterScale=chosen; lowSince=0; }
        else if (required<=rasterScale*0.5) {
            if (!lowSince) lowSince=now;
            if (now-lowSince>=0.5) { rasterScale=chosen; lowSince=0; }
        } else lowSince=0;
        if (rasterScale>8) [self count:@"resolutionLimitedSurfaces" amount:1];
        rasterScale=MIN(8,MAX(native,rasterScale));
        self.scales[node[@"id"]]=@{@"scale":@(rasterScale),@"lowSince":@(lowSince)};
        NSMutableArray *children=[NSMutableArray new], *run=[NSMutableArray new];
        void (^flush)(void)=^{
            if (!run.count) return;
            NSMutableArray *commands=[NSMutableArray new]; CGRect bounds=CGRectNull; NSMutableString *version=[NSMutableString new];
            for (NSDictionary *item in run) {
                bounds=CGRectUnion(bounds,STNArrayRect(item[@"bounds"])); [commands addObjectsFromArray:item[@"commands"]];
                [version appendFormat:@"%@:%@",item[@"id"],item[@"version"]];
            }
            NSDictionary *chunk=@{@"kind":@"cpu",@"id":[NSString stringWithFormat:@"%@/%@",node[@"id"],run[0][@"id"]],
                @"version":version,@"bounds":@[@(bounds.origin.x),@(bounds.origin.y),@(bounds.size.width),@(bounds.size.height)],@"commands":commands,@"items":[run copy]};
            NSMutableDictionary *p=[self prepareTree:chunk scale:rasterScale visible:visible world:world jobs:jobs leases:leases];
            if (p) [children addObject:p]; [run removeAllObjects];
        };
        for (NSDictionary *child in node[@"children"]) {
            if ([child[@"kind"] isEqual:@"cpu"]) [run addObject:child];
            else {
                flush(); NSMutableDictionary *p=[self prepareTree:child scale:rasterScale visible:visible world:world jobs:jobs leases:leases];
                if (!p) return nil;
                [children addObject:p];
            }
        }
        flush(); prepared[@"children"]=children; prepared[@"scale"]=@(rasterScale);
    }
    return prepared;
}
- (void)drawSurface:(STNMetalSurface *)surface into:(STNMetalTile *)target buffer:(id<MTLCommandBuffer>)buffer transform:(CGAffineTransform)t opacity:(double)opacity clip:(CGRect)clip radius:(double)radius masked:(BOOL)masked linear:(BOOL)linear {
    if (!STNInvertible(t)) return;
    id<MTLRenderCommandEncoder> encoder=nil;
    for (STNMetalTile *source in surface.tiles) {
        CGRect projected=CGRectApplyAffineTransform(source.core,t);
        if (!CGRectIntersectsRect(projected,target.padded)) continue;
        if (!encoder) encoder=[self encoder:buffer target:target.allocation.texture clear:NO];
        STNMetalQuad q=[self quad:source.core target:target.padded transform:t linear:linear];
        q.uv=(vector_float4){(source.core.origin.x-source.padded.origin.x)/source.padded.size.width,
            (source.core.origin.y-source.padded.origin.y)/source.padded.size.height,
            source.core.size.width/source.padded.size.width,source.core.size.height/source.padded.size.height};
        q.sourceLinear=surface.linear; q.options.z=opacity; q.clip=STNVector(clip); q.options.x=radius; q.masked=masked;
        [self draw:q texture:source.allocation.texture encoder:encoder format:target.allocation.texture.pixelFormat fragment:@"stn_fragment" blend:YES];
    }
    [encoder endEncoding];
}
- (STNMetalSurface *)gather:(STNMetalSurface *)surface buffer:(id<MTLCommandBuffer>)buffer leases:(NSMutableArray *)leases {
    if (surface.directInputs) {
        STNMetalSurface *materialized=[STNMetalSurface new]; materialized.bounds=surface.bounds;
        materialized.scale=surface.scale; materialized.linear=surface.linear;
        materialized.tiles=[self tiles:surface.bounds scale:surface.scale format:surface.linear?MTLPixelFormatRGBA16Float:MTLPixelFormatBGRA8Unorm raster:NO leases:leases];
        if (!materialized.tiles) return nil;
        for (STNMetalTile *tile in materialized.tiles) {
            id<MTLRenderCommandEncoder> clear=[self encoder:buffer target:tile.allocation.texture clear:YES]; [clear endEncoding];
            [self drawDirect:surface.directInputs into:tile buffer:buffer linear:surface.linear];
        }
        surface=materialized;
    }
    NSUInteger w=(NSUInteger)ceil(surface.bounds.size.width*surface.scale),h=(NSUInteger)ceil(surface.bounds.size.height*surface.scale);
    STNMetalAllocation *a=[self allocation:w height:h format:surface.linear?MTLPixelFormatRGBA16Float:MTLPixelFormatBGRA8Unorm raster:NO leases:leases];
    if (!a) return nil;
    STNMetalTile *tile=[STNMetalTile new]; tile.core=surface.bounds; tile.padded=surface.bounds; tile.allocation=a;
    id<MTLRenderCommandEncoder> clear=[self encoder:buffer target:a.texture clear:YES]; [clear endEncoding];
    [self drawSurface:surface into:tile buffer:buffer transform:CGAffineTransformIdentity opacity:1 clip:CGRectZero radius:0 masked:NO linear:surface.linear];
    STNMetalSurface *result=[STNMetalSurface new]; result.key=surface.key; result.bounds=surface.bounds; result.scale=surface.scale; result.linear=surface.linear; result.tiles=@[tile];
    [self count:@"prefixCopyBytes" amount:w*h*STNPixelBytes(a.texture.pixelFormat)*2]; return result;
}
- (STNMetalSurface *)capture:(STNMetalSurface *)surface region:(CGRect)region buffer:(id<MTLCommandBuffer>)buffer leases:(NSMutableArray *)leases {
    double scale=surface.scale;
    double x=floor(region.origin.x*scale)/scale,y=floor(region.origin.y*scale)/scale;
    CGRect bounds=CGRectMake(x,y,ceil(CGRectGetMaxX(region)*scale)/scale-x,ceil(CGRectGetMaxY(region)*scale)/scale-y);
    STNMetalAllocation *a=[self allocation:(NSUInteger)llround(bounds.size.width*scale) height:(NSUInteger)llround(bounds.size.height*scale) format:surface.linear?MTLPixelFormatRGBA16Float:MTLPixelFormatBGRA8Unorm raster:NO leases:leases];
    if (!a) return nil;
    STNMetalTile *tile=[STNMetalTile new]; tile.core=bounds; tile.padded=bounds; tile.allocation=a;
    id<MTLRenderCommandEncoder> clear=[self encoder:buffer target:a.texture clear:YES]; [clear endEncoding];
    [self drawSurface:surface into:tile buffer:buffer transform:CGAffineTransformIdentity opacity:1 clip:CGRectZero radius:0 masked:NO linear:surface.linear];
    STNMetalSurface *result=[STNMetalSurface new]; result.bounds=bounds; result.scale=scale; result.linear=surface.linear; result.tiles=@[tile];
    [self count:@"prefixCapturedPixels" amount:a.texture.width*a.texture.height];
    [self count:@"prefixCopyBytes" amount:a.texture.width*a.texture.height*STNPixelBytes(a.texture.pixelFormat)*2]; return result;
}
- (STNMetalSurface *)blur:(STNMetalSurface *)input radius:(double)radius transform:(CGAffineTransform)transform buffer:(id<MTLCommandBuffer>)buffer leases:(NSMutableArray *)leases {
    if (radius<=0) return input;
    double trace=transform.a*transform.a+transform.b*transform.b+transform.c*transform.c+transform.d*transform.d;
    double det=transform.a*transform.d-transform.b*transform.c;
    double localScale=input.scale*sqrt((trace+sqrt(MAX(0,trace*trace-4*det*det)))/2);
    if (!isfinite(localScale)||localScale<=0) { self.failure=@"Invalid backdrop filter scale"; return nil; }
    NSUInteger r=(NSUInteger)ceil(radius*localScale);
    if (r>16384) { self.failure=@"Backdrop sampling radius exceeds checked dimensions"; return nil; }
    STNMetalTile *tile=input.tiles[0]; id<MTLTexture> source=tile.allocation.texture;
    id<MTLComputePipelineState> pipeline=[self compute:@"stn_blur"]; if (!pipeline) return nil;
    STNMetalAllocation *scratch=[self allocation:source.width height:source.height format:source.pixelFormat raster:NO leases:leases];
    STNMetalAllocation *output=[self allocation:source.width height:source.height format:source.pixelFormat raster:NO leases:leases];
    if (!scratch||!output) return nil;
    for (NSUInteger i=0;i<2;i++) {
        id<MTLComputeCommandEncoder> e=[buffer computeCommandEncoder];
        [e setComputePipelineState:pipeline];
        id<MTLTexture> read=i?scratch.texture:source, write=i?output.texture:scratch.texture;
        [e setTexture:read atIndex:0]; [e setTexture:write atIndex:1];
        [e useResource:read usage:MTLResourceUsageRead]; [e useResource:write usage:MTLResourceUsageWrite];
        struct { uint32_t width,height,radius,horizontal; vector_float2 direction; } p={(uint32_t)source.width,(uint32_t)source.height,(uint32_t)r,i==0,{0,0}};
        p.direction=i?(vector_float2){transform.c*input.scale/localScale,transform.d*input.scale/localScale}:(vector_float2){transform.a*input.scale/localScale,transform.b*input.scale/localScale};
        [e setBytes:&p length:sizeof(p) atIndex:0];
        [e dispatchThreads:MTLSizeMake(source.width,source.height,1) threadsPerThreadgroup:MTLSizeMake(8,8,1)]; [e endEncoding];
    }
    STNMetalTile *out=[STNMetalTile new]; out.core=tile.core; out.padded=tile.padded; out.allocation=output;
    STNMetalSurface *result=[STNMetalSurface new]; result.bounds=input.bounds; result.scale=input.scale; result.linear=input.linear; result.tiles=@[out];
    [self count:@"filterPasses" amount:2]; [self count:@"filterSourcePixels" amount:source.width*source.height]; return result;
}
- (id<MTLFunction>)function:(NSString *)name library:(id<MTLLibrary>)library constants:(NSDictionary *)constants error:(NSError **)error {
    if (!constants.count) return [library newFunctionWithName:name];
    MTLFunctionConstantValues *values=[MTLFunctionConstantValues new];
    for (NSString *key in constants) {
        NSDictionary *c=constants[key]; NSString *kind=c[@"kind"];
        if ([kind isEqual:@"bool"]) { bool v=[c[@"value"] boolValue]; [values setConstantValue:&v type:MTLDataTypeBool withName:key]; }
        else if ([kind isEqual:@"int"]) { int32_t v=[c[@"value"] intValue]; [values setConstantValue:&v type:MTLDataTypeInt withName:key]; }
        else { float v=[c[@"value"] floatValue]; [values setConstantValue:&v type:MTLDataTypeFloat withName:key]; }
    }
    return [library newFunctionWithName:name constantValues:values error:error];
}
- (BOOL)validateBindings:(NSArray<id<MTLBinding>> *)bindings pass:(NSDictionary *)pass stage:(NSString *)stage program:(NSDictionary *)program {
    for (id<MTLBinding> reflected in bindings) {
        if (!reflected.used || !reflected.argument) continue;
        NSString *kind;
        switch (reflected.type) {
            case MTLBindingTypeBuffer: kind=@"buffer"; break;
            case MTLBindingTypeTexture: kind=@"texture"; break;
            case MTLBindingTypeSampler: kind=@"sampler"; break;
            default: self.failure=@"Shader binding: unsupported indirect or threadgroup resource"; return NO;
        }
        NSDictionary *declared=nil;
        for (NSDictionary *b in pass[@"bindings"]) {
            NSString *name=b[@"resource"],*resourceKind=program[@"resources"][name][@"kind"];
            if ([resourceKind isEqual:@"storage"]||[name isEqual:@"$backdropCoordinates"]) resourceKind=@"buffer";
            if ([resourceKind isEqual:@"target"]||[resourceKind isEqual:@"state"]||[name isEqual:@"$backdrop"]) resourceKind=@"texture";
            if ([b[@"stage"] isEqual:stage]&&[b[@"index"] unsignedIntegerValue]==reflected.index&&[kind isEqual:resourceKind]) { declared=b; break; }
        }
        if (!declared || (reflected.access!=MTLBindingAccessReadOnly&&![declared[@"access"] isEqual:@"write"])) {
            self.failure=[NSString stringWithFormat:@"Shader binding: %@ %@(%lu) is missing or has incompatible access",stage,kind,(unsigned long)reflected.index]; return NO;
        }
        if (reflected.type==MTLBindingTypeTexture) {
            id<MTLTextureBinding> texture=(id<MTLTextureBinding>)reflected;
            if (texture.textureType!=MTLTextureType2D||texture.arrayLength>1) { self.failure=@"Shader binding: only declared two-dimensional texture bindings are supported"; return NO; }
        }
        if (reflected.type==MTLBindingTypeBuffer) {
            NSDictionary *r=program[@"resources"][declared[@"resource"]];
            NSUInteger length=[r[@"kind"] isEqual:@"storage"]?[r[@"length"] unsignedIntegerValue]:[[[NSData alloc] initWithBase64EncodedString:r[@"data"] ?: @"" options:0] length];
            if (![declared[@"resource"] isEqual:@"$backdropCoordinates"] && length<((id<MTLBufferBinding>)reflected).bufferDataSize) { self.failure=@"Shader binding: buffer is shorter than the reflected argument"; return NO; }
        }
    }
    return YES;
}
- (void)diagnoseProgram:(NSDictionary *)program instance:(NSString *)instance category:(NSString *)category message:(NSString *)message {
    NSDictionary *diagnostic=@{@"category":category,@"programVersion":program[@"version"],@"instance":instance,@"message":message ?: @"Application shader unavailable"};
    NSData *data=[NSJSONSerialization dataWithJSONObject:diagnostic options:NSJSONWritingSortedKeys error:NULL];
    STNMetalPrepared *token=[STNMetalPrepared new]; token.epoch=self.preparingEpoch; token.revision=self.preparingRevision;
    [self emit:23 frame:token sequence:0 time:0 message:[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]];
}
- (NSDictionary *)compileProgram:(NSDictionary *)program {
    NSString *key=program[@"pipelineVersion"]; NSDictionary *cached=self.programCache[key] ?: [STNSharedApplications objectForKey:key];
    if (cached) {
        NSUInteger index=0;
        for (NSDictionary *pass in program[@"passes"]) {
            NSDictionary *stages=cached[@"reflections"][index++];
            for (NSString *stage in stages) {
                if (![self validateBindings:stages[stage] pass:pass stage:stage program:program]) return nil;
            }
        }
        [self count:@"applicationPipelineHits" amount:1]; return cached;
    }
    __block NSDictionary *compiled=nil;
    double compileStart=CACurrentMediaTime();
    dispatch_sync(STNCompiler, ^{
        NSError *error; id<MTLLibrary> library;
        if (program[@"source"]) library=[STNDevice newLibraryWithSource:program[@"source"] options:nil error:&error];
        else {
            NSData *bytes=[[NSData alloc] initWithBase64EncodedString:program[@"library"] options:0];
            dispatch_data_t data=dispatch_data_create(bytes.bytes,bytes.length,STNCompiler,^{ (void)bytes; });
            library=[STNDevice newLibraryWithData:data error:&error];
        }
        if (!library) { self.failure=[@"Shader compiler: " stringByAppendingString:error.localizedDescription ?: @"Invalid library"]; return; }
        NSMutableArray *pipelines=[NSMutableArray new], *reflections=[NSMutableArray new];
        for (NSDictionary *pass in program[@"passes"]) {
            id pipeline;
            if ([pass[@"kind"] isEqual:@"compute"]) {
                id<MTLFunction> function=[self function:pass[@"function"] library:library constants:program[@"constants"] error:&error];
                if (!function) { self.failure=error.localizedDescription ?: @"Missing compute entry point"; return; }
                MTLComputePipelineReflection *reflection;
                pipeline=[STNDevice newComputePipelineStateWithFunction:function options:MTLPipelineOptionBindingInfo reflection:&reflection error:&error];
                if (pipeline&&![self validateBindings:reflection.bindings pass:pass stage:@"compute" program:program]) return;
                if (pipeline) [reflections addObject:@{@"compute":reflection.bindings ?: @[]}];
            } else {
                MTLRenderPipelineDescriptor *d=[MTLRenderPipelineDescriptor new];
                d.vertexFunction=[self function:pass[@"vertex"] library:library constants:program[@"constants"] error:&error];
                d.fragmentFunction=[self function:pass[@"fragment"] library:library constants:program[@"constants"] error:&error];
                if (!d.vertexFunction||!d.fragmentFunction) { self.failure=error.localizedDescription ?: @"Missing render entry point"; return; }
                NSDictionary *target=program[@"resources"][pass[@"target"]];
                d.colorAttachments[0].pixelFormat=STNFormat(target[@"format"]);
                d.colorAttachments[0].blendingEnabled=[pass[@"blends"] boolValue];
                d.colorAttachments[0].sourceRGBBlendFactor=MTLBlendFactorOne; d.colorAttachments[0].sourceAlphaBlendFactor=MTLBlendFactorOne;
                d.colorAttachments[0].destinationRGBBlendFactor=MTLBlendFactorOneMinusSourceAlpha; d.colorAttachments[0].destinationAlphaBlendFactor=MTLBlendFactorOneMinusSourceAlpha;
                MTLRenderPipelineReflection *reflection;
                pipeline=[STNDevice newRenderPipelineStateWithDescriptor:d options:MTLPipelineOptionBindingInfo reflection:&reflection error:&error];
                if (pipeline&&(![self validateBindings:reflection.vertexBindings pass:pass stage:@"vertex" program:program]||![self validateBindings:reflection.fragmentBindings pass:pass stage:@"fragment" program:program])) return;
                if (pipeline) [reflections addObject:@{@"vertex":reflection.vertexBindings ?: @[],@"fragment":reflection.fragmentBindings ?: @[]}];
            }
            if (!pipeline) { self.failure=[@"Shader pipeline: " stringByAppendingString:error.localizedDescription ?: @"Unsupported device"]; return; }
            [pipelines addObject:pipeline];
        }
        compiled=@{@"library":library,@"pipelines":pipelines,@"reflections":reflections};
    });
    if (compiled) { self.programCache[key]=compiled; [STNSharedApplications setObject:compiled forKey:key]; [self count:@"applicationPipelineMisses" amount:1]; }
    [self timing:@"shaderCompile" milliseconds:(CACurrentMediaTime()-compileStart)*1000 scene:self.preparingRevision];
    return compiled;
}
- (STNMetalSurface *)runProgram:(NSDictionary *)program instance:(NSString *)instance bounds:(CGRect)bounds scale:(double)scale backdrop:(STNMetalSurface *)backdrop buffer:(id<MTLCommandBuffer>)buffer leases:(NSMutableArray *)leases updates:(NSMutableDictionary *)updates {
    [self.usedPrograms addObject:instance]; self.programUnavailable=NO;
    NSDictionary *compiled=[self compileProgram:program];
    if (!compiled) {
        NSString *message=self.failure;
        [self diagnoseProgram:program instance:instance category:[message hasPrefix:@"Shader binding"]?@"binding":@"compiler" message:message]; self.failure=nil;
        NSDictionary *fallback=self.validPrograms[instance];
        if (!fallback) { self.programUnavailable=YES; return nil; }
        program=fallback; compiled=[self compileProgram:program]; if (!compiled) return nil;
    }
    self.pendingPrograms[instance]=program;
    NSString *outputKey=[NSString stringWithFormat:@"%@:%@:%g:%@",program[@"version"],NSStringFromRect(NSRectFromCGRect(bounds)),scale,backdrop.key ?: @""];
    STNMetalSurface *previousOutput=self.programOutputs[instance];
    if (previousOutput.valid&&[previousOutput.key isEqual:outputKey]) return previousOutput;
    NSMutableDictionary *resources=[NSMutableDictionary new],*previous=[NSMutableDictionary new],*nextState=[NSMutableDictionary new];
    NSDictionary *committed=self.state[instance];
    BOOL sameEpoch=[committed[@"version"] isEqual:program[@"stateVersion"]];
    for (NSString *name in program[@"resources"]) {
        NSDictionary *r=program[@"resources"][name]; NSString *kind=r[@"kind"];
        if ([kind isEqual:@"sampler"]) {
            MTLSamplerDescriptor *d=[MTLSamplerDescriptor new];
            d.minFilter=d.magFilter=[r[@"filter"] isEqual:@"nearest"]?MTLSamplerMinMagFilterNearest:MTLSamplerMinMagFilterLinear;
            d.sAddressMode=d.tAddressMode=MTLSamplerAddressModeClampToZero;
            resources[name]=[STNDevice newSamplerStateWithDescriptor:d]; continue;
        }
        NSData *data=r[@"data"]?[[NSData alloc] initWithBase64EncodedString:r[@"data"] options:0]:nil;
        if ([kind isEqual:@"storage"]) {
            NSUInteger length=[r[@"length"] unsignedIntegerValue];
            id<MTLBuffer> value=[self buffer:nil length:length leases:leases]; if (!value) return nil;
            id<MTLBlitCommandEncoder> e=[buffer blitCommandEncoder]; [e fillBuffer:value range:NSMakeRange(0,length) value:0]; [e endEncoding];
            resources[name]=value; continue;
        }
        if ([kind isEqual:@"buffer"]) {
            if (!data.length||data.length>STNSingleAllocationLimit) { self.failure=@"Invalid application buffer allocation"; return nil; }
            id<MTLBuffer> value=[self buffer:data length:data.length leases:leases];
            if (!value) { self.failure=@"Application buffer allocation failed"; return nil; }
            [leases addObject:value]; resources[name]=value; continue;
        }
        NSUInteger width=[r[@"width"] unsignedIntegerValue],height=[r[@"height"] unsignedIntegerValue];
        if (!width) width=(NSUInteger)ceil(bounds.size.width*scale);
        if (!height) height=(NSUInteger)ceil(bounds.size.height*scale);
        STNMetalAllocation *a=[self allocation:width height:height format:STNFormat(r[@"format"]) raster:NO leases:leases];
        if (!a) return nil;
        resources[name]=a.texture;
        if ([kind isEqual:@"state"]) {
            STNMetalAllocation *old=sameEpoch?committed[@"slots"][name]:nil;
            if (!old) {
                old=[self allocation:width height:height format:a.texture.pixelFormat raster:NO leases:leases];
                if (!old) return nil;
                if (!data) { id<MTLRenderCommandEncoder> e=[self encoder:buffer target:old.texture clear:YES]; [e endEncoding]; }
            }
            previous[name]=old.texture; nextState[name]=a;
            if (sameEpoch && committed[@"slots"][name]) data=nil;
            else if (data) resources[[name stringByAppendingString:@"$initial"]]=old.texture;
        }
        if (data.length) {
            NSUInteger rawRow=width*STNPixelBytes(a.texture.pixelFormat),row=(rawRow+255)&~(NSUInteger)255;
            if (data.length!=rawRow*height || row>STNSingleAllocationLimit/height) { self.failure=@"Texture upload stride or length is invalid"; return nil; }
            NSMutableData *padded=[NSMutableData dataWithLength:row*height];
            for (NSUInteger y=0;y<height;y++) memcpy((uint8_t *)padded.mutableBytes+y*row,(const uint8_t *)data.bytes+y*rawRow,rawRow);
            id<MTLBuffer> upload=[self buffer:padded length:padded.length leases:leases];
            if (!upload) { self.failure=@"Shader upload allocation failed"; return nil; }
            [leases addObject:upload]; id<MTLBlitCommandEncoder> e=[buffer blitCommandEncoder];
            id<MTLTexture> destination=resources[[name stringByAppendingString:@"$initial"]] ?: a.texture;
            [e copyFromBuffer:upload sourceOffset:0 sourceBytesPerRow:row sourceBytesPerImage:row*height sourceSize:MTLSizeMake(width,height,1) toTexture:destination destinationSlice:0 destinationLevel:0 destinationOrigin:MTLOriginMake(0,0,0)];
            [e endEncoding];
        }
        if ([kind isEqual:@"texture"] && a.texture.pixelFormat!=MTLPixelFormatR8Unorm) {
            BOOL sourceLinear=[r[@"color"] isEqual:@"extendedLinear"],linear=[program[@"color"] isEqual:@"extendedLinear"];
            BOOL straight=![r[@"premultiplied"] boolValue];
            if (sourceLinear!=linear||straight) {
                STNMetalAllocation *converted=[self allocation:width height:height format:linear?MTLPixelFormatRGBA16Float:MTLPixelFormatBGRA8Unorm raster:NO leases:leases]; if (!converted) return nil;
                id<MTLRenderCommandEncoder> e=[self encoder:buffer target:converted.texture clear:YES];
                CGRect rect=CGRectMake(0,0,width,height); STNMetalQuad q=[self quad:rect target:rect transform:CGAffineTransformIdentity linear:linear];
                q.sourceLinear=sourceLinear; q.mode=straight?2:0;
                [self draw:q texture:a.texture encoder:e format:converted.texture.pixelFormat fragment:@"stn_fragment" blend:NO]; [e endEncoding];
                resources[name]=converted.texture; [self count:@"colorIngressPasses" amount:1];
            }
        }
    }
    if (backdrop) {
        resources[@"$backdrop"]=backdrop.tiles[0].allocation.texture;
        CGAffineTransform t=backdrop.backdropTransform, inverse=CGAffineTransformInvert(t);
        vector_float4 coordinates[]={STNVector(backdrop.bounds),STNVector(backdrop.backdropPanel),
            {t.a,t.c,t.tx,0},{t.b,t.d,t.ty,0},{inverse.a,inverse.c,inverse.tx,0},{inverse.b,inverse.d,inverse.ty,0},
            {backdrop.scale,backdrop.linear,0,0}};
        NSData *data=[NSData dataWithBytes:coordinates length:sizeof(coordinates)];
        id<MTLBuffer> mapping=[self buffer:data length:data.length leases:leases]; if (!mapping) return nil;
        resources[@"$backdropCoordinates"]=mapping;
    }
    NSUInteger passIndex=0;
    for (NSDictionary *pass in program[@"passes"]) {
        BOOL compute=[pass[@"kind"] isEqual:@"compute"];
        id encoder; id pipeline=compiled[@"pipelines"][passIndex++];
        if (compute) { encoder=[buffer computeCommandEncoder]; [encoder setComputePipelineState:pipeline]; }
        else { encoder=[self encoder:buffer target:resources[pass[@"target"]] clear:YES]; [encoder setRenderPipelineState:pipeline]; }
        for (NSDictionary *binding in pass[@"bindings"]) {
            NSString *name=binding[@"resource"],*stage=binding[@"stage"];
            id resource=[binding[@"previous"] boolValue]?previous[name]:resources[name];
            if (!resource) { [encoder endEncoding]; self.failure=@"Missing shader resource (backdrop is available only to an effect)"; return nil; }
            NSUInteger index=[binding[@"index"] unsignedIntegerValue];
            MTLResourceUsage access=[binding[@"access"] isEqual:@"write"]?MTLResourceUsageWrite:MTLResourceUsageRead;
            BOOL texture=[resource conformsToProtocol:@protocol(MTLTexture)],sampler=[resource conformsToProtocol:@protocol(MTLSamplerState)];
            if (compute) {
                if (texture) [(id<MTLComputeCommandEncoder>)encoder setTexture:resource atIndex:index];
                else if (sampler) [(id<MTLComputeCommandEncoder>)encoder setSamplerState:resource atIndex:index];
                else [(id<MTLComputeCommandEncoder>)encoder setBuffer:resource offset:0 atIndex:index];
                if (!sampler) [(id<MTLComputeCommandEncoder>)encoder useResource:resource usage:access];
            } else if ([stage isEqual:@"vertex"]) {
                if (texture) [encoder setVertexTexture:resource atIndex:index];
                else if (sampler) [encoder setVertexSamplerState:resource atIndex:index];
                else [encoder setVertexBuffer:resource offset:0 atIndex:index];
                if (!sampler) [encoder useResource:resource usage:access stages:MTLRenderStageVertex];
            } else {
                if (texture) [encoder setFragmentTexture:resource atIndex:index];
                else if (sampler) [encoder setFragmentSamplerState:resource atIndex:index];
                else [encoder setFragmentBuffer:resource offset:0 atIndex:index];
                if (!sampler) [encoder useResource:resource usage:access stages:MTLRenderStageFragment];
            }
        }
        if (compute) {
            NSArray *size=pass[@"threads"];
            NSUInteger w=MIN((NSUInteger)8,((id<MTLComputePipelineState>)pipeline).threadExecutionWidth);
            NSUInteger h=MIN((NSUInteger)8,((id<MTLComputePipelineState>)pipeline).maxTotalThreadsPerThreadgroup/w);
            [encoder dispatchThreads:MTLSizeMake([size[0] unsignedIntegerValue],[size[1] unsignedIntegerValue],[size[2] unsignedIntegerValue]) threadsPerThreadgroup:MTLSizeMake(w,h,1)];
        } else if (pass[@"indices"]) {
            [encoder drawIndexedPrimitives:MTLPrimitiveTypeTriangle indexCount:[pass[@"count"] unsignedIntegerValue] indexType:MTLIndexTypeUInt32 indexBuffer:resources[pass[@"indices"]] indexBufferOffset:0 instanceCount:[pass[@"instances"] unsignedIntegerValue]];
        } else [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:[pass[@"count"] unsignedIntegerValue] instanceCount:[pass[@"instances"] unsignedIntegerValue]];
        [encoder endEncoding];
    }
    if (nextState.count) updates[instance]=@{@"version":program[@"stateVersion"],@"slots":nextState,@"step":@(sameEpoch?[committed[@"step"] unsignedLongLongValue]+1:1)};
    id<MTLTexture> output=resources[program[@"output"]];
    if (![output conformsToProtocol:@protocol(MTLTexture)]) { self.failure=@"Program output is not a texture"; return nil; }
    STNMetalAllocation *owner=nil;
    for (id lease in leases) if ([lease isKindOfClass:STNMetalAllocation.class] && ((STNMetalAllocation *)lease).texture==output) { owner=lease; break; }
    STNMetalTile *tile=[STNMetalTile new]; tile.core=bounds; tile.padded=bounds; tile.allocation=owner;
    STNMetalSurface *surface=[STNMetalSurface new]; surface.bounds=bounds; surface.scale=scale; surface.linear=[program[@"color"] isEqual:@"extendedLinear"]; surface.tiles=@[tile];
    surface.key=outputKey; self.pendingOutputs[instance]=surface;
    [self count:@"programPasses" amount:passIndex]; return surface;
}
- (STNMetalSurface *)gpu:(NSDictionary *)node scale:(double)scale linear:(BOOL)linear buffer:(id<MTLCommandBuffer>)buffer leases:(NSMutableArray *)leases updates:(NSMutableDictionary *)updates {
    NSString *slot=[@"gpu:" stringByAppendingString:node[@"id"]]; [self.usedKeys addObject:slot];
    NSString *key=[NSString stringWithFormat:@"%@:%g:%d",[self signature:node],scale,linear];
    STNMetalSurface *surface=self.cache[slot];
    if (surface.valid && [surface.key isEqual:key]) return surface;
    surface=[STNMetalSurface new]; surface.key=key; surface.bounds=STNArrayRect(node[@"bounds"]); surface.scale=scale; surface.linear=linear;
    surface.tiles=[self tiles:surface.bounds scale:scale format:linear?MTLPixelFormatRGBA16Float:MTLPixelFormatBGRA8Unorm raster:NO leases:leases];
    if (!surface.tiles) return nil;
    [STNMemoryLock lock]; BOOL enableMSAA=STNAdmissionCapacity==STNDefaultCapacity; [STNMemoryLock unlock];
    if (enableMSAA&&[STNDevice supportsTextureSampleCount:4]) for (STNMetalTile *tile in surface.tiles) {
        STNMetalAllocation *msaa=STNAllocate(tile.allocation.texture.width,tile.allocation.texture.height,tile.allocation.texture.pixelFormat,NO,4);
        if (!msaa) { self.failure=@"Multisample allocation exceeds device capacity"; return nil; }
        [self.multisample setObject:msaa forKey:tile.allocation.texture]; [leases addObject:msaa]; [self count:@"multisampleBytes" amount:msaa.bytes];
    }
    for (STNMetalTile *tile in surface.tiles) { id<MTLRenderCommandEncoder> e=[self encoder:buffer target:tile.allocation.texture clear:YES]; [e endEncoding]; }
    NSArray *commands=node[@"commands"]; NSUInteger commandIndex=0;
    while (commandIndex<commands.count) {
        NSDictionary *command=commands[commandIndex];
        NSString *op=command[@"op"];
        if ([op isEqual:@"program"]) {
            commandIndex++;
            STNMetalSurface *output=[self runProgram:command[@"program"] instance:node[@"id"] bounds:surface.bounds scale:scale backdrop:nil buffer:buffer leases:leases updates:updates];
            if (!output) { if (self.programUnavailable) { self.programUnavailable=NO; continue; } return nil; }
            for (STNMetalTile *tile in surface.tiles) [self drawSurface:output into:tile buffer:buffer transform:CGAffineTransformIdentity opacity:1 clip:CGRectZero radius:0 masked:NO linear:linear];
            continue;
        }
        // Keep each ordinary drawing run inside one encoder per tile. Ending
        // an MSAA encoder after every rectangle resolves/stores the complete
        // tile repeatedly, turning a small chart into full-tile copy traffic.
        NSUInteger runStart=commandIndex++;
        while (commandIndex<commands.count&&![commands[commandIndex][@"op"] isEqual:@"program"]) commandIndex++;
        for (STNMetalTile *tile in surface.tiles) {
            id<MTLRenderCommandEncoder> e=[self encoder:buffer target:tile.allocation.texture clear:NO];
            for (NSUInteger index=runStart;index<commandIndex;index++) {
                NSDictionary *command=commands[index]; NSString *op=command[@"op"];
                if ([op isEqual:@"mesh"]) {
                    NSArray *vertices=command[@"vertices"],*indices=command[@"indices"];
                    NSMutableData *v=[NSMutableData dataWithLength:vertices.count*6*sizeof(float)],*ix=[NSMutableData dataWithLength:indices.count*sizeof(uint32_t)];
                    float *vp=v.mutableBytes; uint32_t *ip=ix.mutableBytes;
                    for (NSArray *vertex in vertices) for (NSNumber *value in vertex) *vp++=value.floatValue;
                    for (NSNumber *index in indices) *ip++=index.unsignedIntValue;
                    if (v.length && ix.length) {
                        id<MTLBuffer> vb=[self buffer:v length:v.length leases:leases];
                        id<MTLBuffer> ib=[self buffer:ix length:ix.length leases:leases];
                        if (!vb||!ib) { [e endEncoding]; self.failure=@"Geometry buffer allocation failed"; return nil; }
                        [leases addObjectsFromArray:@[vb,ib]];
                        STNMetalQuad q=[self quad:surface.bounds target:tile.padded transform:CGAffineTransformIdentity linear:linear];
                        [e setRenderPipelineState:[self pipeline:@"stn_mesh_fragment" format:tile.allocation.texture.pixelFormat blend:YES mesh:YES]];
                        [e setVertexBuffer:vb offset:0 atIndex:0]; [e setVertexBytes:&q length:sizeof(q) atIndex:1];
                        [e useResource:vb usage:MTLResourceUsageRead stages:MTLRenderStageVertex];
                        [e drawIndexedPrimitives:MTLPrimitiveTypeTriangle indexCount:indices.count indexType:MTLIndexTypeUInt32 indexBuffer:ib indexBufferOffset:0];
                    }
                } else if ([op isEqual:@"polyline"]) {
                    // A single union-coverage pass avoids double alpha at round joins.
                    NSArray *points=command[@"points"];
                    if (points.count) {
                        NSMutableData *data=[NSMutableData dataWithLength:(points.count+1)*2*sizeof(float)]; float *p=data.mutableBytes;
                        for (NSArray *point in points) { *p++=[point[0] floatValue]; *p++=[point[1] floatValue]; }
                        NSUInteger count=points.count;
                        if ([command[@"closed"] boolValue]) { *p++=[points[0][0] floatValue]; *p=[points[0][1] floatValue]; count++; }
                        id<MTLBuffer> pointsBuffer=[self buffer:data length:data.length leases:leases];
                        if (!pointsBuffer) { [e endEncoding]; return nil; }
                        [leases addObject:pointsBuffer];
                        STNMetalQuad q=[self quad:surface.bounds target:tile.padded transform:CGAffineTransformIdentity linear:linear];
                        q.color=(vector_float4){[command[@"color"][0] floatValue],[command[@"color"][1] floatValue],[command[@"color"][2] floatValue],[command[@"color"][3] floatValue]};
                        q.sourceLinear=[command[@"linear"] boolValue]; q.options.x=[command[@"width"] floatValue]; q.options.y=count;
                        [e setFragmentBuffer:pointsBuffer offset:0 atIndex:1];
                        [e useResource:pointsBuffer usage:MTLResourceUsageRead stages:MTLRenderStageFragment];
                        [self draw:q texture:nil encoder:e format:tile.allocation.texture.pixelFormat fragment:@"stn_line" blend:YES];
                    }
                } else {
                    CGRect rect=STNArrayRect(command[@"rect"]); rect.origin.x+=surface.bounds.origin.x; rect.origin.y+=surface.bounds.origin.y;
                    STNMetalQuad q=[self quad:CGRectInset(rect,-1/scale,-1/scale) target:tile.padded transform:CGAffineTransformIdentity linear:linear];
                    q.mode=1; q.color=(vector_float4){[command[@"color"][0] floatValue],[command[@"color"][1] floatValue],[command[@"color"][2] floatValue],[command[@"color"][3] floatValue]};
                    q.sourceLinear=[command[@"linear"] boolValue]; q.masked=YES; q.clip=STNVector(rect);
                    q.options.x=[command[@"radius"] doubleValue]; q.options.y=[op isEqual:@"ellipse"];
                    [self draw:q texture:nil encoder:e format:tile.allocation.texture.pixelFormat fragment:@"stn_fragment" blend:YES];
                }
            }
            [e endEncoding]; [self count:@"gpuDrawingEncoders" amount:1];
        }
    }
    for (STNMetalTile *tile in surface.tiles) tile.key=key;
    self.cache[slot]=surface; [self count:@"gpuLeafDraws" amount:1]; return surface;
}
- (BOOL)replaceBackdrop:(NSDictionary *)node context:(STNMetalSurface *)context contributors:(NSArray *)contributors foreground:(STNMetalSurface *)foreground buffer:(id<MTLCommandBuffer>)buffer leases:(NSMutableArray *)leases updates:(NSMutableDictionary *)updates {
    NSDictionary *effect=node[@"backdrop"];
    CGAffineTransform transform=STNAnchoredTransform(node);
    if (!STNInvertible(transform)) return YES;
    CGRect output=CGRectApplyAffineTransform(STNArrayRect(node[@"bounds"]),transform);
    if (!CGRectIntersectsRect(output,context.bounds)) return YES;
    double radius=0,expandX=0,expandY=0;
    if ([effect[@"kind"] isEqual:@"blur"]) {
        radius=[effect[@"radius"] doubleValue];
        expandX=(radius+1/context.scale)*(fabs(transform.a)+fabs(transform.c));
        expandY=(radius+1/context.scale)*(fabs(transform.b)+fabs(transform.d));
    } else if ([effect[@"kind"] isEqual:@"program"]) {
        radius=[effect[@"program"][@"samplingRadius"] doubleValue];
        expandX=radius*hypot(transform.a,transform.c); expandY=radius*hypot(transform.b,transform.d);
    }
    BOOL nonlocal=[effect[@"kind"] isEqual:@"program"]&&!effect[@"program"][@"samplingRadius"];
    CGRect sourceRegion=nonlocal?context.bounds:CGRectIntersection(CGRectInset(output,-expandX-2/context.scale,-expandY-2/context.scale),context.bounds);
    NSString *slot=[@"backdrop:" stringByAppendingString:node[@"id"]]; [self.usedKeys addObject:slot];
    NSMutableString *key=[NSMutableString stringWithFormat:@"%@:%@:%@:%@:%@:%g:%d",context.contextID,effect,node[@"transform"],NSStringFromRect(NSRectFromCGRect(context.bounds)),NSStringFromRect(NSRectFromCGRect(sourceRegion)),context.scale,context.linear];
    for (NSDictionary *contributor in contributors) {
        [self count:@"backdropDependencyVisits" amount:1];
        if (CGRectIntersectsRect([contributor[@"bounds"] rectValue],sourceRegion)) [key appendString:contributor[@"version"]];
    }
    // Only the same-frame earlier prefix is eligible for this immutable input.
    STNMetalSurface *filtered=self.cache[slot];
    if (!filtered.valid||![filtered.key isEqual:key]) {
        STNMetalSurface *prefix=[self capture:context region:sourceRegion buffer:buffer leases:leases]; if (!prefix) return NO;
        prefix.key=key;
        prefix.backdropTransform=transform; prefix.backdropPanel=STNArrayRect(node[@"bounds"]);
        filtered=prefix;
        if ([effect[@"kind"] isEqual:@"blur"]) filtered=[self blur:prefix radius:radius transform:transform buffer:buffer leases:leases];
        else if ([effect[@"kind"] isEqual:@"program"]) filtered=[self runProgram:effect[@"program"] instance:slot bounds:prefix.bounds scale:context.scale backdrop:prefix buffer:buffer leases:leases updates:updates];
        if (!filtered&&self.programUnavailable) { self.programUnavailable=NO; return YES; }
        if (filtered) { filtered.key=key; self.cache[slot]=filtered; }
        [self count:@"backdropCacheMisses" amount:1];
    } else [self count:@"backdropCacheHits" amount:1];
    if (!filtered) return NO;
    if (filtered.linear!=context.linear) {
        STNMetalAllocation *converted=[self allocation:filtered.tiles[0].allocation.texture.width height:filtered.tiles[0].allocation.texture.height format:context.linear?MTLPixelFormatRGBA16Float:MTLPixelFormatBGRA8Unorm raster:NO leases:leases];
        if (!converted) return NO;
        STNMetalTile *tile=[STNMetalTile new]; tile.core=filtered.bounds; tile.padded=filtered.bounds; tile.allocation=converted;
        id<MTLRenderCommandEncoder> clear=[self encoder:buffer target:converted.texture clear:YES]; [clear endEncoding];
        [self drawSurface:filtered into:tile buffer:buffer transform:CGAffineTransformIdentity opacity:1 clip:CGRectZero radius:0 masked:NO linear:context.linear];
        STNMetalSurface *result=[STNMetalSurface new]; result.key=key; result.bounds=filtered.bounds; result.scale=filtered.scale; result.linear=context.linear; result.tiles=@[tile];
        filtered=result; self.cache[slot]=result; [self count:@"colorIngressPasses" amount:1];
    }
    STNMetalSurface *fg=[self gather:foreground buffer:buffer leases:leases]; if (!fg) return NO;
    CGAffineTransform inverse=CGAffineTransformInvert(transform);
    id<MTLComputePipelineState> pipeline=[self compute:@"stn_replace"]; if (!pipeline) return NO;
    NSMutableArray *tiles=[NSMutableArray new];
    for (STNMetalTile *tile in context.tiles) {
        STNMetalAllocation *a=[self allocation:tile.allocation.texture.width height:tile.allocation.texture.height format:tile.allocation.texture.pixelFormat raster:NO leases:leases];
        if (!a) return NO;
        id<MTLComputeCommandEncoder> e=[buffer computeCommandEncoder]; [e setComputePipelineState:pipeline];
        NSArray *textures=@[tile.allocation.texture,filtered.tiles[0].allocation.texture,fg.tiles[0].allocation.texture,a.texture];
        for (NSUInteger i=0;i<4;i++) { [e setTexture:textures[i] atIndex:i]; [e useResource:textures[i] usage:i==3?MTLResourceUsageWrite:MTLResourceUsageRead]; }
        struct { vector_float4 context,panel,row0,row1,options,source,foreground; } p;
        p.context=STNVector(tile.padded); p.panel=STNVector(STNArrayRect(node[@"bounds"]));
        p.row0=(vector_float4){inverse.a,inverse.c,inverse.tx,0}; p.row1=(vector_float4){inverse.b,inverse.d,inverse.ty,0};
        p.options=(vector_float4){context.scale,[node[@"radius"] floatValue],[node[@"opacity"] floatValue],[effect[@"kind"] isEqual:@"identity"]};
        p.source=STNVector(filtered.bounds); p.foreground=STNVector(fg.bounds);
        [e setBytes:&p length:sizeof(p) atIndex:0];
        [e dispatchThreads:MTLSizeMake(a.texture.width,a.texture.height,1) threadsPerThreadgroup:MTLSizeMake(8,8,1)]; [e endEncoding];
        STNMetalTile *replacement=[STNMetalTile new]; replacement.core=tile.core; replacement.padded=tile.padded; replacement.allocation=a;
        replacement.key=[NSString stringWithFormat:@"backdrop:%@:%@:%@",node[@"backdrop"],context.key,foreground.key]; [tiles addObject:replacement];
    }
    context.tiles=tiles; [self count:@"backdropCaptures" amount:1]; return YES;
}
- (STNMetalSurface *)group:(NSDictionary *)node scale:(double)scale linear:(BOOL)linear buffer:(id<MTLCommandBuffer>)buffer leases:(NSMutableArray *)leases updates:(NSMutableDictionary *)updates root:(BOOL)root {
    NSString *slot=[@"group:" stringByAppendingString:node[@"id"]]; [self.usedKeys addObject:slot];
    CGRect bounds=root?STNArrayRect(node[@"bounds"]):[self contentBounds:node];
    CGRect visible=node[@"visible"]?[node[@"visible"] rectValue]:bounds;
    NSString *key=[NSString stringWithFormat:@"%@:%g:%d:%@:%@:%d",node[@"sequence"] ?: [self signature:node],scale,linear,node[@"bounds"],NSStringFromRect(NSRectFromCGRect(visible)),self.forcedFinalMode==4];
    // Child dictionaries contain immutable resource identities (CPU surfaces)
    // and version tokens, not a global scene revision.
    STNMetalSurface *old=self.cache[slot];
    if (!(root&&(self.directMode||self.forcedFinalMode>=3)) && old.valid && [old.key isEqual:key]) {
        [self.usedKeys addObjectsFromArray:old.cacheKeys ?: @[]]; [self count:@"groupCacheHits" amount:1]; return old;
    }
    NSMutableArray *inputs=[NSMutableArray new]; BOOL hasBackdrop=NO;
    for (NSDictionary *child in node[@"children"]) {
        NSString *kind=child[@"kind"]; STNMetalSurface *input;
        if ([kind isEqual:@"cpu"]) input=child[@"surface"];
        else if ([kind isEqual:@"gpu"]) input=[self gpu:child scale:scale linear:linear buffer:buffer leases:leases updates:updates];
        else input=[self group:child scale:[child[@"scale"] doubleValue] linear:linear buffer:buffer leases:leases updates:updates root:NO];
        if (!input) return nil;
        [inputs addObject:input]; if (child[@"backdrop"]) hasBackdrop=YES;
    }
    STNMetalSurface *surface=[STNMetalSurface new]; surface.contextID=node[@"id"]; surface.key=key; surface.bounds=bounds; surface.scale=scale; surface.linear=linear;
    if (root&&self.directMode&&!linear&&!hasBackdrop) {
        NSMutableArray *entries=[NSMutableArray new];
        for (NSUInteger i=0;i<inputs.count;i++) [entries addObject:@{@"node":node[@"children"][i],@"surface":inputs[i]}];
        surface.directInputs=entries; surface.tiles=@[]; [self.cache removeObjectForKey:slot]; return surface;
    }
    NSArray *allocated=[self tileLayout:bounds scale:scale visible:visible];
    if (!allocated) return nil;
    NSMutableArray *tiles=[allocated mutableCopy];
    // Per-tile dependency keys retain unchanged final/group cores. A changed
    // tile is always a new writable generation, so old readers cannot conflict.
    if (!hasBackdrop) {
        for (NSUInteger tileIndex=0;tileIndex<tiles.count;tileIndex++) {
            STNMetalTile *tile=tiles[tileIndex]; NSMutableString *tileKey=[NSMutableString stringWithFormat:@"%g:%d:%@",scale,linear,NSStringFromRect(NSRectFromCGRect(tile.padded))];
            for (NSUInteger i=0;i<inputs.count;i++) {
                NSDictionary *child=node[@"children"][i]; STNMetalSurface *input=inputs[i];
                CGAffineTransform t=[child[@"kind"] isEqual:@"group"]?STNAnchoredTransform(child):CGAffineTransformIdentity;
                if (CGRectIntersectsRect(CGRectApplyAffineTransform(input.bounds,t),tile.padded)) {
                    [tileKey appendFormat:@"%@:%@:%@:%@",child[@"transform"],child[@"opacity"],child[@"clip"],child[@"radius"]];
                    if ([child[@"kind"] isEqual:@"cpu"]) {
                        // A different allocation of a neighboring raster tile
                        // does not change the pixels in this final tile's gutter.
                        for (NSDictionary *item in child[@"items"] ?: @[child]) if ([item[@"commands"] count]&&CGRectIntersectsRect(STNArrayRect(item[@"bounds"]),tile.padded)) [tileKey appendFormat:@"%@:%@",item[@"id"],item[@"version"]];
                    } else {
                        for (STNMetalTile *source in input.tiles) if (CGRectIntersectsRect(CGRectApplyAffineTransform(source.core,t),tile.padded)) [tileKey appendString:source.key ?: input.key ?: @""];
                    }
                }
            }
            NSString *tileSlot=[NSString stringWithFormat:@"%@/%g,%g",slot,tile.core.origin.x*scale,tile.core.origin.y*scale]; [self.usedKeys addObject:tileSlot];
            STNMetalSurface *cached=self.cache[tileSlot];
            if (!(root&&(self.directMode||self.forcedFinalMode>=3)) && cached.valid && [cached.key isEqual:tileKey]) { tiles[tileIndex]=cached.tiles[0]; [self count:@"finalTileHits" amount:root]; continue; }
            tile.allocation=[self allocation:(NSUInteger)llround(tile.padded.size.width*scale) height:(NSUInteger)llround(tile.padded.size.height*scale) format:linear?MTLPixelFormatRGBA16Float:MTLPixelFormatBGRA8Unorm raster:NO leases:leases];
            if (!tile.allocation) return nil;
            id<MTLRenderCommandEncoder> clear=[self encoder:buffer target:tile.allocation.texture clear:YES]; [clear endEncoding];
            for (NSUInteger i=0;i<inputs.count;i++) {
                NSDictionary *child=node[@"children"][i]; BOOL group=[child[@"kind"] isEqual:@"group"];
                [self drawSurface:inputs[i] into:tile buffer:buffer transform:group?STNAnchoredTransform(child):CGAffineTransformIdentity opacity:group?[child[@"opacity"] doubleValue]:1 clip:STNArrayRect(child[@"bounds"]) radius:[child[@"radius"] doubleValue] masked:group&&[child[@"clip"] boolValue] linear:linear];
            }
            STNMetalSurface *version=[STNMetalSurface new]; version.key=tileKey; version.tiles=@[tile]; self.cache[tileSlot]=version;
            tile.key=tileKey;
            [self count:root?@"finalPixelsRedrawn":@"groupPixelsRedrawn" amount:tile.allocation.texture.width*tile.allocation.texture.height];
        }
        surface.tiles=tiles;
    } else {
        surface.tiles=tiles;
        for (STNMetalTile *tile in tiles) {
            tile.allocation=[self allocation:(NSUInteger)llround(tile.padded.size.width*scale) height:(NSUInteger)llround(tile.padded.size.height*scale) format:linear?MTLPixelFormatRGBA16Float:MTLPixelFormatBGRA8Unorm raster:NO leases:leases];
            if (!tile.allocation) return nil;
        }
        for (STNMetalTile *tile in tiles) { id<MTLRenderCommandEncoder> clear=[self encoder:buffer target:tile.allocation.texture clear:YES]; [clear endEncoding]; }
        NSMutableArray *contributors=[NSMutableArray new];
        for (NSUInteger i=0;i<inputs.count;i++) {
            NSDictionary *child=node[@"children"][i]; BOOL group=[child[@"kind"] isEqual:@"group"];
            if (child[@"backdrop"]) {
                if (![self replaceBackdrop:child context:surface contributors:contributors foreground:inputs[i] buffer:buffer leases:leases updates:updates]) return nil;
            } else for (STNMetalTile *tile in surface.tiles) {
                [self drawSurface:inputs[i] into:tile buffer:buffer transform:group?STNAnchoredTransform(child):CGAffineTransformIdentity opacity:group?[child[@"opacity"] doubleValue]:1 clip:STNArrayRect(child[@"bounds"]) radius:[child[@"radius"] doubleValue] masked:group&&[child[@"clip"] boolValue] linear:linear];
            }
            CGAffineTransform t=group?STNAnchoredTransform(child):CGAffineTransformIdentity;
            STNMetalSurface *input=inputs[i];
            if ([child[@"kind"] isEqual:@"cpu"]) {
                for (NSDictionary *item in child[@"items"] ?: @[child]) {
                    if (![item[@"commands"] count]) continue;
                    [contributors addObject:@{@"bounds":[NSValue valueWithRect:NSRectFromCGRect(STNArrayRect(item[@"bounds"]))],@"version":[NSString stringWithFormat:@"%@:%@",item[@"id"],item[@"version"]]}];
                }
            } else {
                // A preceding effect's pixels depend on its captured prefix,
                // not just its unchanged foreground and descriptor. Include
                // that dependency epoch so halo changes propagate through a
                // chain even when the original source misses the later halo.
                NSString *effectKey=child[@"backdrop"]?self.cache[[@"backdrop:" stringByAppendingString:child[@"id"]]].key:@"";
                NSString *version=[NSString stringWithFormat:@"%@:%@:%@:%@:%@",input.key,child[@"transform"],child[@"opacity"],child[@"backdrop"],effectKey];
                [contributors addObject:@{@"bounds":[NSValue valueWithRect:NSRectFromCGRect(CGRectApplyAffineTransform(input.bounds,t))],@"version":version}];
            }
        }
        [self count:@"backdropContextPixelsRedrawn" amount:(NSUInteger)ceil(bounds.size.width*scale)*ceil(bounds.size.height*scale)];
    }
    surface.cacheKeys=self.usedKeys.allObjects;
    if (!(root&&self.directMode)) self.cache[slot]=surface;
    else {
        [self.cache removeObjectForKey:slot];
        for (NSString *key in self.cache.allKeys) if ([key hasPrefix:[slot stringByAppendingString:@"/"]]) [self.cache removeObjectForKey:key];
    }
    return surface;
}
- (void)drawDirect:(NSArray *)inputs into:(STNMetalTile *)tile buffer:(id<MTLCommandBuffer>)buffer linear:(BOOL)linear {
    for (NSDictionary *entry in inputs) {
        NSDictionary *child=entry[@"node"]; BOOL group=[child[@"kind"] isEqual:@"group"];
        [self drawSurface:entry[@"surface"] into:tile buffer:buffer transform:group?STNAnchoredTransform(child):CGAffineTransformIdentity opacity:group?[child[@"opacity"] doubleValue]:1 clip:STNArrayRect(child[@"bounds"]) radius:[child[@"radius"] doubleValue] masked:group&&[child[@"clip"] boolValue] linear:linear];
    }
}
- (void)selectFinalPath:(NSDictionary *)scene {
    self.frameIndex++;
    NSArray *size=scene[@"size"]; double area=[size[0] doubleValue]*[size[1] doubleValue],damage=0;
    CGRect viewport=CGRectMake(0,0,[size[0] doubleValue],[size[1] doubleValue]);
    for (NSArray *r in scene[@"damage"]) { CGRect clipped=CGRectIntersection(STNArrayRect(r),viewport); if (!CGRectIsNull(clipped)) damage+=clipped.size.width*clipped.size.height; }
    double fraction=area>0?MIN(1,damage/area):1;
    self.denseFrames=fraction>=0.6?self.denseFrames+1:0;
    self.sparseFrames=fraction<=0.2?self.sparseFrames+1:0;
    NSString *forced=NSProcessInfo.processInfo.environment[@"STANA_METAL_FINAL_MODE"];
    NSString *profile=self.workingLinear?@"linear":@"encoded";
    self.persistentCost=[self.pathCosts[[profile stringByAppendingString:@":persistent"]] doubleValue];
    self.directCost=[self.pathCosts[[profile stringByAppendingString:@":direct"]] doubleValue];
    if (self.forcedFinalMode==1) forced=@"persistent";
    if (self.forcedFinalMode==2) forced=@"direct";
    if (self.forcedFinalMode>=3) forced=@"persistent";
    BOOL next=self.directMode;
    if ([forced isEqual:@"direct"]) next=YES;
    else if ([forced isEqual:@"persistent"]) next=NO;
    else if (self.frameIndex-self.lastModeSwitch>=60) {
        if (!self.directMode&&self.denseFrames>=8&&(self.directCost==0||self.directCost<self.persistentCost)) next=YES;
        if (self.directMode&&self.sparseFrames>=30) next=NO;
    }
    if (next!=self.directMode) { self.directMode=next; self.lastModeSwitch=self.frameIndex; [self count:@"finalModeSwitches" amount:1]; }
    self.counts[@"directMode"]=@(next); self.counts[@"damageFraction"]=@(fraction);
}
- (NSDictionary *)expand:(NSString *)reference depth:(NSUInteger)depth {
    if (depth>512) { self.failure=@"Paint depth budget exceeded"; return nil; }
    NSDictionary *cached=self.expandedObjects[reference]; if (cached) return cached;
    NSDictionary *object=self.objects[reference]; if (!object) { self.failure=@"Missing retained paint object"; return nil; }
    if (![object[@"kind"] isEqual:@"group"]) return object;
    NSMutableDictionary *group=[object mutableCopy]; NSMutableArray *children=[NSMutableArray new];
    NSMutableArray *stack=[NSMutableArray new]; NSString *cursor=object[@"sequence"]; NSUInteger visits=0;
    while (cursor||stack.count) {
        while (cursor) {
            if (++visits>300000) { self.failure=@"Invalid retained paint sequence"; return nil; }
            NSDictionary *branch=self.objects[cursor];
            if (![branch[@"kind"] isEqual:@"sequence"]) { self.failure=@"Invalid paint sequence reference"; return nil; }
            [stack addObject:branch]; cursor=branch[@"left"];
        }
        NSDictionary *branch=stack.lastObject; [stack removeLastObject];
        NSDictionary *child=[self expand:branch[@"entry"] depth:depth+1]; if (!child) return nil;
        [children addObject:child]; cursor=branch[@"right"];
    }
    group[@"children"]=children; self.expandedObjects[reference]=group; return group;
}
- (void)pruneObjects {
    if (!self.latestRoot) return;
    NSMutableSet *live=[NSMutableSet new]; NSMutableArray *pending=[NSMutableArray arrayWithObject:self.latestRoot];
    while (pending.count) {
        NSString *key=pending.lastObject; [pending removeLastObject];
        if ([live containsObject:key]) continue;
        [live addObject:key]; NSDictionary *object=self.objects[key];
        for (NSString *field in @[@"left",@"right",@"entry",@"sequence"]) if (object[field]) [pending addObject:object[field]];
    }
    for (NSString *key in self.objects.allKeys) if (![live containsObject:key]) { [self.objects removeObjectForKey:key]; [self.expandedObjects removeObjectForKey:key]; }
    self.counts[@"retainedPaintObjects"]=@(self.objects.count);
}
- (BOOL)refreshWindowColorDemand {
    // Hosted toolbar/titlebar surfaces share the containing window's working
    // profile. A profile-only replay reuses raw program output and never resets
    // or advances temporal state.
    NSWindow *window=self.host.window; BOOL required=NO;
    NSArray<STNMetalRenderer *> *renderers=STNRenderers.allObjects;
    for (STNMetalRenderer *renderer in renderers) {
        if (renderer.detached||renderer.host.window!=window||renderer.host.view.hidden) continue;
        NSDictionary *scene=renderer.desired;
        if ([scene[@"extended"] boolValue]||[scene[@"mode"] isEqual:@"extendedLinear"]) { required=YES; break; }
    }
    for (STNMetalRenderer *renderer in renderers) {
        if (renderer.detached||renderer.host.window!=window||renderer.windowHDRDemand==required) continue;
        renderer.windowHDRDemand=required;
        if (renderer!=self&&renderer.desired) { renderer.profileDirty=YES; [renderer requestFrame]; }
    }
    return required;
}
- (void)submit:(NSDictionary *)scene {
    if (self.detached) return;
    dispatch_async(self.encoding, ^{
        [self.objects addEntriesFromDictionary:scene[@"objects"] ?: @{}];
        if (scene[@"rootRef"]) self.latestRoot=scene[@"rootRef"];
    });
    self.desired=scene;
    if (self.preparing||self.ready||self.acquiring) return;
    self.preparing=YES; self.displayLink.paused=YES;
    STNMetalPrepared *frame=[STNMetalPrepared new]; frame.scene=scene; frame.epoch=STNUInt64(scene[@"epoch"]); frame.revision=STNUInt64(scene[@"revision"]);
    frame.preparationStart=CACurrentMediaTime();
    frame.targetTimestamp=[scene[@"targetTimestamp"] doubleValue]; frame.framePeriod=[scene[@"framePeriod"] doubleValue];
    double scale=self.host.window.backingScaleFactor ?: 1;
    double time=CACurrentMediaTime(); NSString *mode=scene[@"mode"];
    BOOL hdr=[self refreshWindowColorDemand];
    if (hdr) { if (!self.workingLinear) self.promotedAt=time; self.workingLinear=YES; self.noHDRSince=0; }
    else if (self.workingLinear) {
        if (!self.noHDRSince) {
            self.noHDRSince=time; double absence=time;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,10*NSEC_PER_SEC),dispatch_get_main_queue(), ^{
                if (!self.detached&&self.workingLinear&&self.noHDRSince==absence) { self.profileDirty=YES; [self requestFrame]; }
            });
        }
        if (time-self.noHDRSince>=10 && time-self.promotedAt>=5) self.workingLinear=NO;
    }
    frame.linear=self.workingLinear;
    frame.extendedOutput=frame.linear&&![mode isEqual:@"sdr"];
    frame.headroom=frame.extendedOutput?MAX(1,self.host.window.screen.maximumExtendedDynamicRangeColorComponentValue):1;
    STNAcquirePacket(^{
    frame.permit=[STNPacketPermit new];
    dispatch_async(self.encoding, ^{ @autoreleasepool {
        if (self.detached||frame.epoch!=self.epoch) { dispatch_async(dispatch_get_main_queue(), ^{ self.preparing=NO; [self requestFrame]; }); return; }
        self.failure=nil; self.usedKeys=[NSMutableSet new];
        self.nativeScale=scale;
        self.preparingRevision=frame.revision; self.preparingEpoch=frame.epoch;
        [self.pendingPrograms removeAllObjects]; [self.usedPrograms removeAllObjects];
        [self.pendingOutputs removeAllObjects];
        [self selectFinalPath:scene]; BOOL direct=self.directMode;
        frame.direct=direct;
        NSArray *size=scene[@"size"];
        self.counts[@"backingWidth"]=@(ceil([size[0] doubleValue]*scale));
        self.counts[@"backingHeight"]=@(ceil([size[1] doubleValue]*scale));
        self.counts[@"backingScale"]=@(scale); self.counts[@"displayHeadroom"]=@(frame.headroom);
        double pixels=ceil([size[0] doubleValue]*scale)*ceil([size[1] doubleValue]*scale);
        if (!isfinite(pixels)||pixels>SIZE_MAX/24) { [self fail:@"Invalid drawable dimensions" frame:frame]; return; }
        frame.drawableAllowance=[self reserveDrawablePool:(NSUInteger)pixels*(frame.extendedOutput?8:4)*3];
        if (!frame.drawableAllowance) { [self fail:self.failure frame:frame]; return; }
        if (!self.library) {
            dispatch_sync(STNCompiler, ^{
                NSError *error;
                if (!STNSharedLibrary) STNSharedLibrary=[STNDevice newLibraryWithSource:STNMetalShaderSource() options:nil error:&error];
                self.library=STNSharedLibrary;
                if (!self.library) self.failure=error.localizedDescription;
            });
            if (!self.library) { [self fail:self.failure frame:frame]; return; }
            MTLTextureDescriptor *d=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:1 height:1 mipmapped:NO]; d.storageMode=MTLStorageModeShared; d.hazardTrackingMode=MTLHazardTrackingModeTracked;
            self.transparent=[STNDevice newTextureWithDescriptor:d]; uint32_t zero=0; [self.transparent replaceRegion:MTLRegionMake2D(0,0,1,1) mipmapLevel:0 withBytes:&zero bytesPerRow:4];
        }
        NSMutableArray *leases=[NSMutableArray new],*jobs=[NSMutableArray new];
        NSDictionary *root=scene[@"root"] ?: [self expand:scene[@"rootRef"] depth:0];
        CGRect viewport=CGRectMake(0,0,[size[0] doubleValue],[size[1] doubleValue]);
        NSMutableDictionary *tree=root?[self prepareTree:root scale:scale visible:viewport world:CGAffineTransformIdentity jobs:jobs leases:leases]:nil;
        if (!tree||self.failure) { [self fail:self.failure frame:frame]; return; }
        [STNWorkers() add:jobs completion:^{
            dispatch_async(self.encoding, ^{ @autoreleasepool {
                if (self.detached||frame.epoch!=self.epoch||self.failure) { [self fail:self.failure ?: @"Canceled surface epoch" frame:frame]; return; }
                id<MTLCommandBuffer> buffer=[self.queue commandBuffer];
                double encodeStart=CACurrentMediaTime();
                if (!buffer) { [self fail:@"Offscreen command buffer unavailable" frame:frame]; return; }
                NSMutableDictionary *updates=[NSMutableDictionary new];
                frame.final=[self group:tree scale:scale linear:frame.linear buffer:buffer leases:leases updates:updates root:YES];
                if (frame.final&&!frame.final.directInputs&&!frame.final.tiles.count) self.failure=@"Final composite has no resident visible tiles";
                self.currentSampleCount=1;
                [self pipeline:@"stn_present_batch" format:frame.extendedOutput?MTLPixelFormatRGBA16Float:MTLPixelFormatBGRA8Unorm blend:NO mesh:NO];
                [self pipeline:@"stn_fragment" format:MTLPixelFormatBGRA8Unorm blend:YES mesh:NO];
                if (!frame.final||self.failure) { [self fail:self.failure frame:frame]; return; }
                frame.leases=leases;
                [buffer addCompletedHandler:^(id<MTLCommandBuffer> completed) {
                    dispatch_async(self.encoding, ^{
                        if (completed.status!=MTLCommandBufferStatusCompleted) {
                            [self.multisample removeAllObjects];
                            if (frame.epoch==self.epoch) { [self.cache removeAllObjects]; [self.state removeAllObjects]; [self.programOutputs removeAllObjects]; }
                            [self gpuFailure:completed.error.localizedDescription frame:frame sequence:0]; return;
                        }
                        if (self.detached||frame.epoch!=self.epoch||self.failedEpoch==frame.epoch) {
                            frame.permit=nil;
                            dispatch_async(dispatch_get_main_queue(), ^{ self.preparing=NO; if (self.failedEpoch!=self.epoch) [self requestFrame]; }); return;
                        }
                        for (STNMetalSurface *surface in self.cache.allValues) surface.valid=YES;
                        [self.multisample removeAllObjects];
                        [self.state addEntriesFromDictionary:updates];
                        [self.validPrograms addEntriesFromDictionary:self.pendingPrograms];
                        for (STNMetalSurface *output in self.pendingOutputs.allValues) output.valid=YES;
                        [self.programOutputs addEntriesFromDictionary:self.pendingOutputs];
                        for (NSString *instance in self.state.allKeys) if (![self.usedPrograms containsObject:instance]) [self.state removeObjectForKey:instance];
                        for (NSString *instance in self.validPrograms.allKeys) if (![self.usedPrograms containsObject:instance]) [self.validPrograms removeObjectForKey:instance];
                        for (NSString *instance in self.programOutputs.allKeys) if (![self.usedPrograms containsObject:instance]) [self.programOutputs removeObjectForKey:instance];
                        NSMutableSet *livePipelines=[NSMutableSet new];
                        for (NSDictionary *program in self.validPrograms.allValues) [livePipelines addObject:program[@"pipelineVersion"]];
                        for (NSString *key in self.programCache.allKeys) if (![livePipelines containsObject:key]) [self.programCache removeObjectForKey:key];
                        frame.leases=@[];
                        [self pruneObjects];
                        for (NSString *key in self.cache.allKeys) if (![self.usedKeys containsObject:key]) { [self.cache removeObjectForKey:key]; [self count:@"tileEvictions" amount:1]; }
                        [self count:@"offscreenSubmissions" amount:1];
                        double cost=completed.GPUEndTime-completed.GPUStartTime;
                        frame.offscreenSeconds=cost;
                        [self timing:@"offscreenGPU" milliseconds:cost*1000 scene:frame.revision];
                        double preparation=CACurrentMediaTime()-frame.preparationStart;
                        [self timing:@"preparationLatency" milliseconds:preparation*1000 scene:frame.revision];
                        self.completedPreparations++;
                        if (self.completedPreparations>8) self.preparationEWMA=self.preparationEWMA?0.8*self.preparationEWMA+0.2*preparation:preparation;
                        dispatch_async(dispatch_get_main_queue(), ^{
                            self.preparing=NO;
                            if (frame.epoch!=self.epoch||self.detached) { [self requestFrame]; return; }
                            self.ready=frame;
                            [self emit:17 frame:frame sequence:0 time:completed.GPUEndTime-completed.GPUStartTime message:nil];
                            [self presentReady];
                        });
                    });
                }];
                [buffer commit];
                [self timing:@"offscreenEncoding" milliseconds:(CACurrentMediaTime()-encodeStart)*1000 scene:frame.revision];
            }});
        }];
    }});
    });
}
- (void)presentReady {
    STNMetalPrepared *frame=self.ready;
    if (!frame||self.acquiring||self.detached||frame.epoch!=self.epoch) return;
    STNWindowHost *host=self.host;
    if (!host.window.visible||host.window.miniaturized) return;
    if (!frame.permit) {
        self.acquiring=YES;
        STNAcquirePacket(^{
            STNPacketPermit *permit=[STNPacketPermit new];
            dispatch_async(dispatch_get_main_queue(), ^{
                self.acquiring=NO;
                if (self.ready!=frame||self.detached||frame.epoch!=self.epoch) return;
                frame.permit=permit; [self presentReady];
            });
        }); return;
    }
    self.acquiring=YES;
    NSArray *size=frame.scene[@"size"]; double scale=host.window.backingScaleFactor ?: 1;
    CGSize drawableSize=CGSizeMake(ceil([size[0] doubleValue]*scale),ceil([size[1] doubleValue]*scale));
    self.copyBytesPerFrame=drawableSize.width*drawableSize.height*((frame.extendedOutput?8:4)+(frame.linear?8:4));
    if (frame.final.directInputs) {
        self.copyBytesPerFrame=drawableSize.width*drawableSize.height*4;
        for (NSDictionary *entry in frame.final.directInputs) {
            STNMetalSurface *source=entry[@"surface"];
            for (STNMetalTile *tile in source.tiles) self.copyBytesPerFrame+=tile.core.size.width*tile.core.size.height*scale*scale*(STNPixelBytes(tile.allocation.texture.pixelFormat)+8);
        }
    }
    self.requestedRate=MAX(1,host.window.screen.maximumFramesPerSecond ?: 60);
    if (![self negotiatePresentationRates]) { self.acquiring=NO; return; }
    self.layer.drawableSize=drawableSize; self.layer.contentsScale=scale;
    self.layer.frame=host.view.bounds;
    self.layer.pixelFormat=frame.extendedOutput?MTLPixelFormatRGBA16Float:MTLPixelFormatBGRA8Unorm;
    self.layer.wantsExtendedDynamicRangeContent=frame.extendedOutput; self.layer.opaque=host.surfaceOpaque;
    frame.headroom=frame.extendedOutput?MAX(1,host.window.screen.maximumExtendedDynamicRangeColorComponentValue):1;
    CGColorSpaceRef color=CGColorSpaceCreateWithName(frame.extendedOutput?kCGColorSpaceExtendedLinearSRGB:kCGColorSpaceSRGB);
    self.layer.colorspace=color; CGColorSpaceRelease(color);
    [CATransaction flush];
    dispatch_async(self.encoding, ^{ @autoreleasepool {
        if (self.detached||frame.epoch!=self.epoch||self.failedEpoch==frame.epoch) { dispatch_async(dispatch_get_main_queue(), ^{ self.acquiring=NO; if (self.failedEpoch!=self.epoch) [self requestFrame]; }); return; }
        // Nothing asynchronous is prepared while a drawable is held. All
        // worker, compiler, and offscreen GPU dependencies have succeeded.
        id<CAMetalDrawable> drawable=self.starved?nil:[self.layer nextDrawable];
        if (drawable) [self count:@"drawableAcquisitions" amount:1];
        if (!drawable) {
            [self count:@"drawableStarvation" amount:1];
            dispatch_async(dispatch_get_main_queue(), ^{
                self.acquiring=NO;
                double delay=self.retryDelay; self.retryDelay=MIN(0.25,delay*2);
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(delay*NSEC_PER_SEC)),dispatch_get_main_queue(), ^{ [self presentReady]; });
            }); return;
        }
        if (drawable.texture.width!=(NSUInteger)drawableSize.width||drawable.texture.height!=(NSUInteger)drawableSize.height||drawable.texture.pixelFormat!=self.layer.pixelFormat||frame.epoch!=self.epoch) {
            dispatch_async(dispatch_get_main_queue(), ^{ self.acquiring=NO; self.ready=nil; [self requestFrame]; }); return;
        }
        if (frame.revision<self.submittedRevision) { dispatch_async(dispatch_get_main_queue(), ^{ self.acquiring=NO; self.ready=nil; [self requestFrame]; }); return; }
        id<MTLCommandBuffer> buffer=[self.queue commandBuffer];
        if (!buffer) { dispatch_async(dispatch_get_main_queue(), ^{ self.acquiring=NO; }); [self fail:@"Presentation command buffer unavailable" frame:frame]; return; }
        uint64_t sequence=++self.sequence; self.submittedRevision=frame.revision;
        STNMetalPrepared *token=[STNMetalPrepared new]; token.revision=frame.revision; token.epoch=frame.epoch;
        token.targetTimestamp=frame.targetTimestamp; token.framePeriod=frame.framePeriod;
        [self emit:21 frame:token sequence:sequence time:CACurrentMediaTime() message:nil];
        __weak STNMetalRenderer *weakSelf=self;
        [drawable addPresentedHandler:^(id<MTLDrawable> presented) {
            double timestamp=presented.presentedTime;
            // Capture only scalar identity/timing, not drawable or frame leases.
            [weakSelf emit:19 frame:token sequence:sequence time:timestamp message:nil];
            STNMetalRenderer *renderer=weakSelf;
            if (renderer) dispatch_async(renderer.encoding, ^{
                [renderer count:timestamp>0?@"positivePresentationObservations":@"zeroPresentationObservations" amount:1];
                renderer.counts[@"lastPresentedTime"]=@(timestamp);
                if (timestamp>0&&token.targetTimestamp>0) {
                    [renderer timing:@"presentationTargetLateness" milliseconds:MAX(0,timestamp-token.targetTimestamp)*1000 scene:token.revision];
                    if (token.framePeriod>0&&timestamp-token.targetTimestamp>token.framePeriod*0.5) [renderer count:@"missedPresentationTargets" amount:1];
                }
            });
        }];
        id<MTLRenderCommandEncoder> encoder=[self encoder:buffer target:drawable.texture clear:YES];
        CGRect target=CGRectMake(0,0,[size[0] doubleValue],[size[1] doubleValue]);
        if (frame.final.directInputs) {
            [encoder endEncoding]; encoder=nil;
            STNMetalAllocation *destination=[STNMetalAllocation new]; destination.texture=drawable.texture;
            STNMetalTile *tile=[STNMetalTile new]; tile.core=target; tile.padded=target; tile.allocation=destination;
            [self drawDirect:frame.final.directInputs into:tile buffer:buffer linear:NO];
        } else {
        id<MTLRenderPipelineState> pipeline=[self pipeline:@"stn_present_batch" format:drawable.texture.pixelFormat blend:NO mesh:NO];
        [encoder setRenderPipelineState:pipeline];
        for (NSUInteger start=0;start<frame.final.tiles.count;start+=16) {
            NSUInteger count=MIN((NSUInteger)16,frame.final.tiles.count-start);
            STNMetalQuad quads[16]; id<MTLTexture> textures[16];
            for (NSUInteger i=0;i<16;i++) textures[i]=self.transparent;
            for (NSUInteger i=0;i<count;i++) {
            STNMetalTile *tile=frame.final.tiles[start+i];
            STNMetalQuad q=[self quad:tile.core target:target transform:CGAffineTransformIdentity linear:frame.linear];
            q.uv=(vector_float4){(tile.core.origin.x-tile.padded.origin.x)/tile.padded.size.width,
                (tile.core.origin.y-tile.padded.origin.y)/tile.padded.size.height,
                tile.core.size.width/tile.padded.size.width,tile.core.size.height/tile.padded.size.height};
            q.sourceLinear=frame.extendedOutput; q.options.w=frame.headroom;
            quads[i]=q; textures[i]=tile.allocation.texture;
            }
            [encoder setVertexBytes:quads length:sizeof(STNMetalQuad)*count atIndex:0];
            [encoder setFragmentBytes:quads length:sizeof(STNMetalQuad)*count atIndex:0];
            [encoder setFragmentTextures:textures withRange:NSMakeRange(0,16)];
            for (NSUInteger i=0;i<count;i++) [encoder useResource:textures[i] usage:MTLResourceUsageRead stages:MTLRenderStageFragment];
            [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6 instanceCount:count];
        }
        [encoder endEncoding];
        }
        [buffer addCompletedHandler:^(id<MTLCommandBuffer> completed) {
            BOOL success=completed.status==MTLCommandBufferStatusCompleted;
            if (success) [weakSelf emit:18 frame:token sequence:sequence time:completed.GPUEndTime-completed.GPUStartTime message:nil];
            else [weakSelf gpuFailure:completed.error.localizedDescription frame:token sequence:sequence];
            // This completion, not the presentation observation, ends read leases.
            (void)frame;
            frame.permit=nil;
            STNMetalRenderer *renderer=weakSelf;
            if (renderer) dispatch_async(renderer.encoding, ^{
                double copy=completed.GPUEndTime-completed.GPUStartTime,total=copy+frame.offscreenSeconds;
                [renderer timing:@"presentationGPU" milliseconds:copy*1000 scene:frame.revision];
                renderer.totalGPUEWMA=renderer.totalGPUEWMA?0.8*renderer.totalGPUEWMA+0.2*total:total;
                renderer.copyGPUEWMA=renderer.copyGPUEWMA?0.8*renderer.copyGPUEWMA+0.2*copy:copy;
                renderer.minimumFramePeriod=MAX(renderer.preparationEWMA/0.8,MAX(renderer.totalGPUEWMA/0.8,renderer.copyGPUEWMA/0.2));
                NSString *key=[NSString stringWithFormat:@"%@:%@",frame.linear?@"linear":@"encoded",frame.direct?@"direct":@"persistent"];
                double old=[renderer.pathCosts[key] doubleValue]; renderer.pathCosts[key]=@(old?old*0.8+total*0.2:total);
            });
        }];
        if (frame.targetTimestamp>0) [buffer presentDrawable:drawable atTime:frame.targetTimestamp];
        else [buffer presentDrawable:drawable];
        [buffer commit];
        [self count:@"presentationSubmissions" amount:1];
        [self count:@"presentationCopyBytes" amount:(NSUInteger)drawableSize.width*drawableSize.height*(STNPixelBytes(drawable.texture.pixelFormat)+(frame.final.directInputs?0:(frame.final.linear?8:4)))];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.acquiring=NO; self.retryDelay=0.016; self.last=frame;
            if (self.ready==frame) self.ready=nil;
            if (self.desired!=frame.scene) { NSDictionary *desired=self.desired; [self submit:desired]; }
            else if (self.animation||self.demand) [self requestFrame];
        });
    }});
}
- (BOOL)negotiatePresentationRates {
    [STNMemoryLock lock]; double bandwidth=STNCopyBandwidth ?: 8e9; [STNMemoryLock unlock];
    double budget=bandwidth*0.25,total=0;
    NSMutableArray<STNMetalRenderer *> *hosts=[NSMutableArray new]; NSMutableArray<NSNumber *> *divisors=[NSMutableArray new];
    for (STNMetalRenderer *renderer in STNRenderers.allObjects) {
        if (!renderer.detached&&renderer.host.window.visible&&!renderer.host.window.miniaturized&&renderer.host.view.window&&!renderer.host.view.hiddenOrHasHiddenAncestor&&renderer.copyBytesPerFrame>0) {
            double divisor=MAX(1,MIN(renderer.requestedRate,ceil(renderer.requestedRate*renderer.minimumFramePeriod)));
            [hosts addObject:renderer]; [divisors addObject:@(divisor)]; total+=renderer.copyBytesPerFrame*renderer.requestedRate/divisor;
        }
    }
    while (total>budget) {
        NSInteger selected=-1; double largest=-1;
        for (NSUInteger i=0;i<hosts.count;i++) {
            STNMetalRenderer *renderer=hosts[i]; double divisor=divisors[i].doubleValue;
            if (divisor>=renderer.requestedRate) continue;
            double weight=renderer.host.window.keyWindow?2:1;
            double traffic=renderer.copyBytesPerFrame*renderer.requestedRate/divisor/weight;
            if (traffic>largest) { largest=traffic; selected=(NSInteger)i; }
        }
        if (selected<0) return NO;
        STNMetalRenderer *renderer=hosts[(NSUInteger)selected]; double d=divisors[(NSUInteger)selected].doubleValue;
        total-=renderer.copyBytesPerFrame*renderer.requestedRate/d;
        divisors[(NSUInteger)selected]=@(d+1); total+=renderer.copyBytesPerFrame*renderer.requestedRate/(d+1);
    }
    for (NSUInteger i=0;i<hosts.count;i++) {
        STNMetalRenderer *renderer=hosts[i]; double rate=renderer.requestedRate/divisors[i].doubleValue;
        renderer.negotiatedRate=rate;
        renderer.displayLink.preferredFrameRateRange=CAFrameRateRangeMake(rate,rate,rate);
        dispatch_async(renderer.encoding, ^{
            renderer.counts[@"requestedPresentationRate"]=@(renderer.requestedRate);
            renderer.counts[@"negotiatedPresentationRate"]=@(rate);
            renderer.counts[@"copyBandwidthBytesPerSecond"]=@(bandwidth);
            renderer.counts[@"devicePresentationCopyBytesPerSecond"]=@(total);
        });
    }
    return YES;
}
- (NSDictionary *)diagnostics {
    __block NSDictionary *result;
    dispatch_sync(self.encoding, ^{
        NSMutableDictionary *values=[self.counts mutableCopy];
        [STNMemoryLock lock]; values[@"deviceAccountedBytes"]=@(STNAllocatedBytes); values[@"deviceCapacityBytes"]=@(STNAdmissionCapacity); [STNMemoryLock unlock];
        values[@"device"]=STNDevice.name ?: @"unavailable"; values[@"surfaceEpoch"]=@(self.epoch);
        values[@"driverAllocatedBytes"]=@(STNDevice.currentAllocatedSize);
        @synchronized(STNPacketLock) { values[@"deviceExecutionPackets"]=@(STNPacketCount); }
        STNRasterWorkers *workers=STNWorkers();
        @synchronized(workers) { values[@"workerLimit"]=@(workers.limit); values[@"activeWorkers"]=@(workers.active); values[@"peakWorkers"]=@(workers.peak); }
        values[@"failure"]=self.failure ?: @""; values[@"workingLinear"]=@(self.workingLinear); result=values;
        NSMutableDictionary *timings=[NSMutableDictionary new];
        for (NSString *name in self.timings) timings[name]=[self.timings[name] copy];
        values[@"timingSamples"]=timings;
    }); return result;
}
- (void)reportDiagnostics:(void (^)(NSDictionary *))completion {
    // Run the synchronous test diagnostic on an independent queue; callers of
    // the public async API never wait behind compilation or native encoding.
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0), ^{
        NSDictionary *snapshot=[self diagnostics];
        dispatch_async(dispatch_get_main_queue(), ^{ completion(snapshot); });
    });
}
- (void)readback:(void (^)(NSData *, NSUInteger, NSUInteger, BOOL, uint64_t, NSString *))completion {
    STNMetalPrepared *frame=self.ready ?: self.last;
    if (!frame) { completion(nil,0,0,NO,0,@"No successful offscreen frame is available"); return; }
    dispatch_async(self.encoding, ^{
        NSMutableArray *leases=[NSMutableArray new]; id<MTLCommandBuffer> buffer=[self.queue commandBuffer];
        STNMetalSurface *gathered=[self gather:frame.final buffer:buffer leases:leases];
        if (!gathered) { dispatch_async(dispatch_get_main_queue(), ^{ completion(nil,0,0,NO,0,self.failure); }); return; }
        id<MTLTexture> texture=gathered.tiles[0].allocation.texture;
        NSUInteger width=texture.width,height=texture.height,rawRow=width*STNPixelBytes(texture.pixelFormat),row=(rawRow+255)&~(NSUInteger)255;
        id<MTLBuffer> readback=[self buffer:nil length:row*height leases:leases];
        if (!readback) { dispatch_async(dispatch_get_main_queue(), ^{ completion(nil,0,0,NO,0,@"Readback allocation failed"); }); return; }
        id<MTLBlitCommandEncoder> e=[buffer blitCommandEncoder];
        [e copyFromTexture:texture sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0,0,0) sourceSize:MTLSizeMake(width,height,1) toBuffer:readback destinationOffset:0 destinationBytesPerRow:row destinationBytesPerImage:row*height]; [e endEncoding];
        [buffer addCompletedHandler:^(id<MTLCommandBuffer> completed) {
            NSData *data=completed.status==MTLCommandBufferStatusCompleted?STNCanonicalReadback(readback,row,rawRow,height):nil;
            dispatch_async(dispatch_get_main_queue(), ^{ completion(data,width,height,frame.linear,frame.revision,completed.error.localizedDescription); });
            (void)leases;
        }]; [buffer commit];
    });
}
- (NSData *)readPixels:(STNMetalPrepared *)frame width:(NSUInteger *)outWidth height:(NSUInteger *)outHeight {
    if (!frame) return nil;
    __block NSData *result; __block NSUInteger width=0,height=0;
    dispatch_sync(self.encoding, ^{
        NSMutableArray *leases=[NSMutableArray new]; id<MTLCommandBuffer> buffer=[self.queue commandBuffer];
        STNMetalSurface *gathered=[self gather:frame.final buffer:buffer leases:leases]; if (!gathered) return;
        id<MTLTexture> texture=gathered.tiles[0].allocation.texture; width=texture.width; height=texture.height;
        NSUInteger rawRow=width*STNPixelBytes(texture.pixelFormat),row=(rawRow+255)&~(NSUInteger)255;
        id<MTLBuffer> readback=[self buffer:nil length:row*height leases:leases];
        if (!readback) return;
        id<MTLBlitCommandEncoder> e=[buffer blitCommandEncoder];
        [e copyFromTexture:texture sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0,0,0) sourceSize:MTLSizeMake(width,height,1) toBuffer:readback destinationOffset:0 destinationBytesPerRow:row destinationBytesPerImage:row*height]; [e endEncoding];
        [buffer commit]; [buffer waitUntilCompleted];
        if (buffer.status==MTLCommandBufferStatusCompleted) result=STNCanonicalReadback(readback,row,rawRow,height);
    });
    if (outWidth) *outWidth=width; if (outHeight) *outHeight=height; return result;
}
- (uint64_t)pixelHash {
    NSData *data=[self readPixels:self.ready ?: self.last width:NULL height:NULL];
    if (!data) return 0;
    uint64_t hash=1469598103934665603ULL; const uint8_t *bytes=data.bytes;
    for (NSUInteger i=0;i<data.length;i++) { hash^=bytes[i]; hash*=1099511628211ULL; } return hash;
}
- (BOOL)exportTo:(NSString *)path linear:(BOOL)linear {
    STNMetalPrepared *frame=self.ready ?: self.last;
    NSUInteger width,height; NSData *data=[self readPixels:frame width:&width height:&height];
    if (!data) return NO;
    if (linear) {
        if (!frame.linear) return NO;
        // Raw RGBA IEEE-754 half-floats; a JSON sidecar supplies dimensions/profile.
        NSDictionary *metadata=@{@"width":@(width),@"height":@(height),@"format":@"rgba16Float",@"color":@"extendedLinearSRGB",@"premultiplied":@YES,@"sceneRevision":@(frame.revision)};
        NSData *json=[NSJSONSerialization dataWithJSONObject:metadata options:NSJSONWritingSortedKeys error:NULL];
        return [data writeToFile:path atomically:YES]&&[json writeToFile:[path stringByAppendingString:@".json"] atomically:YES];
    }
    NSMutableData *encoded=[NSMutableData dataWithLength:width*height*4]; uint8_t *out=encoded.mutableBytes;
    if (frame.linear) {
        const _Float16 *input=data.bytes;
        for (NSUInteger i=0;i<width*height;i++) {
            double alpha=input[i*4+3],r=0,g=0,b=0;
            if (alpha>0) {
                r=input[i*4]/alpha; g=input[i*4+1]/alpha; b=input[i*4+2]/alpha;
                double l=MAX(0,MAX(r,MAX(g,b))), k=0.75;
                double mapped=l>k?(k+0.25*(l-k)/(l-k+0.25))/l:1;
                r*=mapped; g*=mapped; b*=mapped;
                r=r<=0.0031308?12.92*r:1.055*pow(r,1/2.4)-0.055;
                g=g<=0.0031308?12.92*g:1.055*pow(g,1/2.4)-0.055;
                b=b<=0.0031308?12.92*b:1.055*pow(b,1/2.4)-0.055;
            }
            out[i*4]=(uint8_t)llround(MAX(0,MIN(1,b*alpha))*255); out[i*4+1]=(uint8_t)llround(MAX(0,MIN(1,g*alpha))*255);
            out[i*4+2]=(uint8_t)llround(MAX(0,MIN(1,r*alpha))*255); out[i*4+3]=(uint8_t)llround(MAX(0,MIN(1,alpha))*255);
        }
    } else memcpy(out,data.bytes,data.length);
    CGColorSpaceRef color=CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef c=CGBitmapContextCreate(out,width,height,8,width*4,color,kCGImageAlphaPremultipliedFirst|kCGBitmapByteOrder32Little); CGColorSpaceRelease(color);
    if (!c) return NO;
    CGImageRef image=CGBitmapContextCreateImage(c); CGContextRelease(c);
    CGImageDestinationRef destination=CGImageDestinationCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:path],CFSTR("public.png"),1,NULL);
    if (!destination) { CGImageRelease(image); return NO; }
    CGImageDestinationAddImage(destination,image,NULL); BOOL ok=CGImageDestinationFinalize(destination); CFRelease(destination); CGImageRelease(image); return ok;
}
@end

bool stn_metal_initialize(stn_window window) {
    STNWindowHost *host=STNHost(window); if (!host) return false;
    if (!host.metal) host.metal=[[STNMetalRenderer alloc] initWithHost:host]; return host.metal!=nil;
}
bool stn_metal_submit(stn_window window, const uint8_t *bytes, size_t count) {
    if (!bytes||count>64*1024*1024) return false;
    NSDictionary *scene=[NSJSONSerialization JSONObjectWithData:[NSData dataWithBytes:bytes length:count] options:0 error:NULL];
    if (![scene isKindOfClass:NSDictionary.class]||!STNHost(window).metal) return false;
    [STNHost(window).metal submit:scene]; return true;
}
void stn_metal_invalidate(stn_window window) { [STNHost(window).metal invalidate]; }
void stn_metal_detach(stn_window window) {
    STNWindowHost *host=STNHost(window); [host.metal detach]; host.metal=nil;
    host.view.layer=nil; host.view.wantsLayer=NO;
}
void stn_metal_animation(stn_window window, bool active) { [STNHost(window).metal setAnimationDemand:active]; }
void stn_metal_pause_observations(stn_window window, bool paused) { [STNHost(window).metal pauseForObservations:paused]; }
void stn_metal_retry(stn_window window, uint64_t revision) { [STNHost(window).metal retryPresentation:revision]; }
char *stn_metal_copy_diagnostics(stn_window window) {
    NSDictionary *values=[STNHost(window).metal diagnostics] ?: @{};
    NSData *json=[NSJSONSerialization dataWithJSONObject:values options:NSJSONWritingSortedKeys error:NULL];
    return strdup([[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding].UTF8String ?: "{}");
}
void stn_metal_diagnostics(stn_window window, void *context, stn_json_callback callback) {
    STNMetalRenderer *renderer=STNHost(window).metal;
    if (!renderer) { callback(context,STNBorrowedString(@"{}")); return; }
    [renderer reportDiagnostics:^(NSDictionary *snapshot) {
        NSData *json=[NSJSONSerialization dataWithJSONObject:snapshot options:NSJSONWritingSortedKeys error:NULL];
        callback(context,STNBorrowedString([[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding]));
    }];
}
void stn_metal_ui_timing(stn_window window, uint64_t scene, double planning, double transport) { [STNHost(window).metal recordUIPlanning:planning transport:transport scene:scene]; }
bool stn_metal_export(stn_window window, const char *path, bool linear) { return [STNHost(window).metal exportTo:STNString(path) linear:linear]; }
void stn_metal_test_configuration(stn_window window, int32_t mode, double delay, bool starved) {
    [STNHost(window).metal testFinalMode:mode rasterDelay:delay starved:starved];
}
void stn_metal_readback(stn_window window, void *context, stn_readback_callback callback) {
    if (!STNHost(window).metal) { callback(context,NULL,0,0,0,false,0,STNBorrowedString(@"Renderer is detached")); return; }
    [STNHost(window).metal readback:^(NSData *data, NSUInteger width, NSUInteger height, BOOL linear, uint64_t revision, NSString *error) {
        callback(context,data.bytes,data.length,width,height,linear,revision,STNBorrowedString(error));
    }];
}
