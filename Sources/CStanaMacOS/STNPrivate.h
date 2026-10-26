#import <AppKit/AppKit.h>
#import <CoreText/CoreText.h>
#import <ImageIO/ImageIO.h>
#import "include/stana_macos.h"

@class STNContentView, STNTextSnapshot;
@interface STNWindowHost : NSObject <NSWindowDelegate>
@property(nonatomic, strong) NSWindow *window;
@property(nonatomic, strong) STNContentView *view;
@property(nonatomic) void *context;
@property(nonatomic) stn_event_callback eventCallback;
@property(nonatomic) stn_draw_callback drawCallback;
@property(nonatomic) stn_text_callback textCallback;
@property(nonatomic) CGContextRef backing;
@property(nonatomic) size_t pixelWidth, pixelHeight;
@property(nonatomic) double scale;
@property(nonatomic) BOOL closing;
@property(nonatomic) NSUInteger modalDepth;
@property(nonatomic, strong) NSDictionary<NSNumber *, id> *semanticNodes;
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, STNTextSnapshot *> *pendingText;
@property(nonatomic) uint64_t semanticRevision;
@property(nonatomic, strong) id appearanceObserver;
@property(nonatomic, strong) id displayObserver;
- (void)emit:(stn_event)event;
- (void)textRequest:(int)kind text:(NSString *)text replacement:(NSRange)replacement selected:(NSRange)selected;
- (void)textRequest:(int)kind text:(NSString *)text replacement:(NSRange)replacement selected:(NSRange)selected revision:(uint64_t)revision;
@end

@interface STNTextSnapshot : NSObject
@property(nonatomic, copy) NSString *text;
@property(nonatomic) NSRange selection, marked;
@property(nonatomic) NSRect bounds;
@property(nonatomic, strong) NSArray<NSNumber *> *offsets;
@property(nonatomic) uint64_t revision;
@property(nonatomic) BOOL secure;
@end

@interface STNContentView : NSView
@property(nonatomic, weak) STNWindowHost *host;
@property(nonatomic, strong) STNTextSnapshot *textSnapshot;
@property(nonatomic) BOOL editing;
@property(nonatomic, strong) NSTrackingArea *tracking;
@end

@interface STNContentView (TextInput) <NSTextInputClient>
@end

@interface STNAccessibilityElement : NSAccessibilityElement
@property(nonatomic, weak) STNWindowHost *host;
@property(nonatomic) uint64_t identity;
@property(nonatomic, strong) NSDictionary *descriptor;
@property(nonatomic, readonly, strong) STNTextSnapshot *textSnapshot;
@end

static inline NSString *STNString(const char *s) { return s ? ([NSString stringWithUTF8String:s] ?: @"") : @""; }
static inline NSString *STNUTF8(stn_utf8 s) { return s.bytes ? ([[NSString alloc] initWithBytes:s.bytes length:s.length encoding:NSUTF8StringEncoding] ?: @"") : @""; }
static inline stn_utf8 STNBorrowedString(NSString *s) { return (stn_utf8){s.UTF8String,[s lengthOfBytesUsingEncoding:NSUTF8StringEncoding]}; }
static inline STNWindowHost *STNHost(stn_window p) { return (__bridge STNWindowHost *)p; }
static inline CGRect STNRect(stn_rect r) { return CGRectMake(r.x, r.y, r.width, r.height); }
STNTextSnapshot *STNMakeTextSnapshot(stn_utf8, uint64_t, uint64_t, uint64_t, uint64_t, stn_rect, const double *, size_t, uint64_t, bool);
CTFontRef STNCreateFont(double size, double weight);
NSRect STNTextRangeRect(STNTextSnapshot *, NSRange);
