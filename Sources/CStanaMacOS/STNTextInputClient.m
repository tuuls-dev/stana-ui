#import "STNPrivate.h"
@implementation STNTextSnapshot
@end

STNTextSnapshot *STNMakeTextSnapshot(stn_utf8 text, uint64_t start, uint64_t length, uint64_t marked, uint64_t markedLength, stn_rect bounds, const double *offsets, size_t count, uint64_t revision, bool secure) {
    STNTextSnapshot *snapshot=[STNTextSnapshot new]; snapshot.text=STNUTF8(text);
    snapshot.selection=NSMakeRange(MIN(start,snapshot.text.length), MIN(length,snapshot.text.length-MIN(start,snapshot.text.length)));
    snapshot.marked=NSMakeRange(marked==UINT64_MAX ? NSNotFound : marked,markedLength);
    snapshot.bounds=STNRect(bounds); snapshot.revision=revision; snapshot.secure=secure;
    NSMutableArray *values=[NSMutableArray arrayWithCapacity:count]; for (size_t i=0;i<count;i++) [values addObject:@(offsets[i])]; snapshot.offsets=values;
    return snapshot;
}
NSRect STNTextRangeRect(STNTextSnapshot *s, NSRange range) {
    if (!s || !s.offsets.count) return s.bounds;
    NSUInteger start=MIN(range.location,s.offsets.count-1), end=MIN(NSMaxRange(range),s.offsets.count-1);
    double x=s.offsets[start].doubleValue, y=s.offsets[end].doubleValue;
    return NSMakeRect(s.bounds.origin.x+MIN(x,y),s.bounds.origin.y,MAX(1,fabs(y-x)),s.bounds.size.height);
}
void stn_window_text_state(stn_window p, stn_utf8 text, uint64_t start, uint64_t length, uint64_t marked, uint64_t markedLength, stn_rect bounds, const double *offsets, size_t count, uint64_t revision, bool secure) {
    STNContentView *view=STNHost(p).view;
    view.textSnapshot=STNMakeTextSnapshot(text,start,length,marked,markedLength,bounds,offsets,count,revision,secure);
    [view.inputContext invalidateCharacterCoordinates];
}

@implementation STNContentView (TextInput)
- (void)insertText:(id)value replacementRange:(NSRange)range {
    NSString *text=[value isKindOfClass:NSAttributedString.class] ? [value string] : value;
    [self.host textRequest:1 text:text replacement:range selected:NSMakeRange(0,0)];
}
- (void)setMarkedText:(id)value selectedRange:(NSRange)selected replacementRange:(NSRange)range {
    NSString *text=[value isKindOfClass:NSAttributedString.class] ? [value string] : value;
    [self.host textRequest:2 text:text replacement:range selected:selected];
}
- (void)unmarkText { [self.host textRequest:3 text:@"" replacement:NSMakeRange(NSNotFound,0) selected:NSMakeRange(0,0)]; }
- (BOOL)hasMarkedText { return self.textSnapshot.marked.location != NSNotFound && self.textSnapshot != nil; }
- (NSRange)markedRange { return self.textSnapshot ? self.textSnapshot.marked : NSMakeRange(NSNotFound,0); }
- (NSRange)selectedRange { return self.textSnapshot ? self.textSnapshot.selection : NSMakeRange(0,0); }
- (NSArray<NSAttributedStringKey> *)validAttributesForMarkedText { return @[]; }
- (NSAttributedString *)attributedSubstringForProposedRange:(NSRange)range actualRange:(NSRangePointer)actual {
    NSString *text=self.textSnapshot.text ?: @""; if (range.location>text.length) return nil;
    NSRange valid=NSIntersectionRange(range,NSMakeRange(0,text.length)); if (actual) *actual=valid;
    return [[NSAttributedString alloc] initWithString:[text substringWithRange:valid]];
}
- (NSRect)firstRectForCharacterRange:(NSRange)range actualRange:(NSRangePointer)actual {
    if (actual) *actual=range;
    NSRect rect=STNTextRangeRect(self.textSnapshot,range);
    return [self.window convertRectToScreen:[self convertRect:rect toView:nil]];
}
- (NSUInteger)characterIndexForPoint:(NSPoint)point {
    NSPoint local=[self convertPoint:[self.window convertPointFromScreen:point] fromView:nil];
    NSArray *offsets=self.textSnapshot.offsets; double x=local.x-self.textSnapshot.bounds.origin.x;
    NSUInteger best=0; double distance=DBL_MAX;
    for (NSUInteger i=0;i<offsets.count;i++) { double d=fabs([offsets[i] doubleValue]-x); if (d<distance) { distance=d; best=i; } }
    return best;
}
- (void)doCommandBySelector:(SEL)selector { [self.host textRequest:4 text:NSStringFromSelector(selector) replacement:NSMakeRange(NSNotFound,0) selected:NSMakeRange(0,0)]; }
@end
