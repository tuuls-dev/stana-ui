#import "STNPrivate.h"

static NSString *STNRole(int role) {
    switch (role) {
        case 0:return NSAccessibilityWindowRole; case 1:return NSAccessibilityGroupRole;
        case 2:if (@available(macOS 26.0, *)) return NSAccessibilityHeadingRole; else return NSAccessibilityStaticTextRole;
        case 3:return NSAccessibilityStaticTextRole;
        case 4:return NSAccessibilityButtonRole; case 5:return NSAccessibilityCheckBoxRole;
        case 6:return NSAccessibilityTextFieldRole; case 7:return NSAccessibilityImageRole;
        case 8:return NSAccessibilityScrollAreaRole; default:return NSAccessibilityGroupRole;
    }
}
@implementation STNAccessibilityElement
- (NSDictionary *)current { @synchronized(self.host) { return self.descriptor; } }
- (STNTextSnapshot *)textSnapshot { return self.current[@"textSnapshot"]; }
- (BOOL)isAccessibilityElement { return self.host != nil && self.current != nil; }
- (NSString *)accessibilityRole { return self.current[@"role"]; }
- (NSString *)accessibilitySubrole { return [self.current[@"secure"] boolValue] ? NSAccessibilitySecureTextFieldSubrole : nil; }
- (NSString *)accessibilityLabel { return self.current[@"label"]; }
- (NSString *)accessibilityHelp { return self.current[@"hint"]; }
- (id)accessibilityValue {
    NSDictionary *d=self.current;
    if ([d[@"secure"] boolValue]) return nil;
    STNTextSnapshot *text=d[@"textSnapshot"];
    if (text && [d[@"role"] isEqual:NSAccessibilityTextFieldRole]) return text.text;
    return [d[@"role"] isEqual:NSAccessibilityCheckBoxRole] ? @([d[@"value"] boolValue]) : d[@"value"];
}
- (BOOL)isAccessibilityEnabled { return self.host && ![self.current[@"disabled"] boolValue]; }
- (BOOL)isAccessibilityFocused { return [self.current[@"focused"] boolValue]; }
- (void)setAccessibilityFocused:(BOOL)focused {
    if (focused && self.isAccessibilityEnabled) {
        __weak STNWindowHost *h=self.host; uint64_t identity=self.identity;
        dispatch_async(dispatch_get_main_queue(), ^{ [h emit:(stn_event){.kind=9,.identity=identity}]; });
    }
}
- (NSRect)accessibilityFrame { return [self.current[@"screenBounds"] rectValue]; }
- (id)accessibilityParent { STNWindowHost *h=self.host; @synchronized(h) { return h.semanticNodes[self.current[@"parentID"]] ?: h.view; } }
- (NSArray *)accessibilityChildren { return self.current[@"children"] ?: @[]; }
- (NSString *)accessibilityValueDescription { return nil; }
- (BOOL)accessibilityPerformPress {
    if (!self.isAccessibilityEnabled) return NO;
    __weak STNWindowHost *h=self.host; uint64_t identity=self.identity;
    dispatch_async(dispatch_get_main_queue(), ^{ [h emit:(stn_event){.kind=8,.identity=identity}]; }); return YES;
}
- (BOOL)isAccessibilitySelectorAllowed:(SEL)selector {
    if (selector==@selector(accessibilityPerformPress)) {
        NSString *role=self.current[@"role"]; return self.isAccessibilityEnabled && ([role isEqual:NSAccessibilityButtonRole] || [role isEqual:NSAccessibilityCheckBoxRole]);
    }
    return [super isAccessibilitySelectorAllowed:selector];
}
- (NSRange)accessibilitySelectedTextRange { return self.textSnapshot ? self.textSnapshot.selection : NSMakeRange(0,0); }
- (void)setAccessibilitySelectedTextRange:(NSRange)range {
    if (!self.isAccessibilityEnabled) return;
    __weak STNWindowHost *h=self.host; uint64_t identity=self.identity, revision=self.textSnapshot.revision;
    dispatch_async(dispatch_get_main_queue(), ^{
        STNAccessibilityElement *current=h.semanticNodes[@(identity)]; if (!current.isAccessibilityEnabled) return;
        [h emit:(stn_event){.kind=9,.identity=identity}]; [h textRequest:5 text:@"" replacement:range selected:range revision:revision];
    });
}
- (NSString *)accessibilitySelectedText {
    STNTextSnapshot *s=self.textSnapshot;
    if (!s || s.secure || NSMaxRange(s.selection)>s.text.length) return @"";
    return [s.text substringWithRange:s.selection];
}
- (NSInteger)accessibilityNumberOfCharacters { return self.textSnapshot.secure ? 0 : self.textSnapshot.text.length; }
- (NSInteger)accessibilityInsertionPointLineNumber { return 0; }
- (NSRange)accessibilityVisibleCharacterRange { return NSMakeRange(0,self.accessibilityNumberOfCharacters); }
- (NSString *)accessibilityStringForRange:(NSRange)range {
    STNTextSnapshot *s=self.textSnapshot; if (!s || s.secure || NSMaxRange(range)>s.text.length) return nil;
    return [s.text substringWithRange:range];
}
- (NSAttributedString *)accessibilityAttributedStringForRange:(NSRange)range {
    NSString *s=[self accessibilityStringForRange:range]; return s ? [[NSAttributedString alloc] initWithString:s] : nil;
}
- (NSRange)accessibilityRangeForIndex:(NSInteger)index {
    NSString *s=self.textSnapshot.text;
    if (index<0 || index>=s.length) return NSMakeRange(MAX(0,MIN(index,(NSInteger)s.length)),0);
    return [s rangeOfComposedCharacterSequenceAtIndex:index];
}
- (NSInteger)accessibilityLineForIndex:(NSInteger)index { return 0; }
- (NSRange)accessibilityRangeForLine:(NSInteger)line { return line==0 ? NSMakeRange(0,self.accessibilityNumberOfCharacters) : NSMakeRange(NSNotFound,0); }
- (NSRect)accessibilityFrameForRange:(NSRange)range {
    NSDictionary *d=self.current; STNTextSnapshot *s=d[@"textSnapshot"];
    if (!s) return [d[@"screenBounds"] rectValue];
    NSRect r=STNTextRangeRect(s,range), local=[d[@"bounds"] rectValue], screen=[d[@"screenBounds"] rectValue];
    return NSMakeRect(screen.origin.x+r.origin.x-local.origin.x,screen.origin.y+screen.size.height-(r.origin.y-local.origin.y)-r.size.height,r.size.width,r.size.height);
}
- (void)setAccessibilityValue:(id)value {
    if (!self.isAccessibilityEnabled || ![value isKindOfClass:NSString.class]) return;
    NSString *text=[value copy]; __weak STNWindowHost *h=self.host; uint64_t identity=self.identity, revision=self.textSnapshot.revision;
    dispatch_async(dispatch_get_main_queue(), ^{
        STNAccessibilityElement *current=h.semanticNodes[@(identity)]; if (!current.isAccessibilityEnabled) return;
        [h emit:(stn_event){.kind=9,.identity=identity}]; [h textRequest:6 text:text replacement:NSMakeRange(NSNotFound,0) selected:NSMakeRange(0,0) revision:revision];
    });
}
@end

@implementation STNContentView (Accessibility)
- (BOOL)isAccessibilityElement { return NO; }
- (NSArray *)accessibilityChildren {
    STNWindowHost *h=self.host; @synchronized(h) {
        NSMutableArray *result=[NSMutableArray array];
        for (STNAccessibilityElement *node in h.semanticNodes.allValues) if ([node.current[@"rootChild"] boolValue]) [result addObject:node];
        [result sortUsingComparator:^NSComparisonResult(STNAccessibilityElement *a,STNAccessibilityElement *b) { return [a.current[@"order"] compare:b.current[@"order"]]; }]; return result;
    }
}
- (id)accessibilityHitTest:(NSPoint)point {
    STNWindowHost *h=self.host; @synchronized(h) {
        NSArray *nodes=[h.semanticNodes.allValues sortedArrayUsingComparator:^NSComparisonResult(STNAccessibilityElement *a,STNAccessibilityElement *b) { return [b.current[@"order"] compare:a.current[@"order"]]; }];
        for (STNAccessibilityElement *node in nodes) if (NSPointInRect(point,node.accessibilityFrame)) return node;
    } return self;
}
@end

void stn_window_publish_semantics(stn_window p, uint64_t revision, const stn_semantic_node *nodes, size_t count) {
    STNWindowHost *h=STNHost(p); NSMutableDictionary *next=[NSMutableDictionary dictionaryWithCapacity:count];
    NSMutableDictionary *descriptors=[NSMutableDictionary dictionaryWithCapacity:count];
    NSMutableArray *notifications=[NSMutableArray array];
    uint64_t rootID=0;
    for (size_t i=0;i<count;i++) if (nodes[i].role==0) rootID=nodes[i].identity;
    for (size_t i=0;i<count;i++) {
        const stn_semantic_node *n=&nodes[i]; if (n->role==0) continue;
        STNAccessibilityElement *element=h.semanticNodes[@(n->identity)] ?: [STNAccessibilityElement new]; element.host=h; element.identity=n->identity;
        NSRect local=STNRect(n->bounds), screen=[h.window convertRectToScreen:[h.view convertRect:local toView:nil]];
        NSMutableDictionary *d=[@{@"role":STNRole(n->role),@"label":STNUTF8(n->label),@"hint":STNUTF8(n->hint),@"value":STNUTF8(n->value),@"bounds":[NSValue valueWithRect:local],@"screenBounds":[NSValue valueWithRect:screen],@"disabled":@(n->disabled),@"focused":@(n->focused),@"offscreen":@(n->offscreen),@"secure":@(n->secure),@"rootChild":@(n->parent==rootID || n->parent==0),@"parentID":@(n->parent),@"children":[NSMutableArray array],@"order":@(i)} mutableCopy];
        if (h.pendingText[@(n->identity)]) d[@"textSnapshot"]=h.pendingText[@(n->identity)];
        STNTextSnapshot *oldText=element.descriptor[@"textSnapshot"], *newText=d[@"textSnapshot"];
        if (oldText && newText && !NSEqualRanges(oldText.selection,newText.selection)) [notifications addObject:@[element,NSAccessibilitySelectedTextChangedNotification]];
        if (![element.descriptor[@"label"] isEqual:d[@"label"]]) [notifications addObject:@[element,NSAccessibilityTitleChangedNotification]];
        if (![element.descriptor[@"value"] isEqual:d[@"value"]]) [notifications addObject:@[element,NSAccessibilityValueChangedNotification]];
        if (n->focused && ![element.descriptor[@"focused"] boolValue]) [notifications addObject:@[element,NSAccessibilityFocusedUIElementChangedNotification]];
        next[@(n->identity)]=element; descriptors[@(n->identity)]=d;
    }
    for (size_t i=0;i<count;i++) {
        NSNumber *key=@(nodes[i].identity); if (!next[key]) continue;
        NSMutableDictionary *d=descriptors[key]; STNAccessibilityElement *parent=next[d[@"parentID"]];
        if (parent) { [descriptors[d[@"parentID"]][@"children"] addObject:next[key]]; }
    }
    BOOL structureChanged=![[NSSet setWithArray:h.semanticNodes.allKeys] isEqualToSet:[NSSet setWithArray:next.allKeys]];
    @synchronized(h) {
        for (NSNumber *key in h.semanticNodes) if (!next[key]) { STNAccessibilityElement *old=h.semanticNodes[key]; old.descriptor=nil; old.host=nil; }
        for (NSNumber *key in next) { STNAccessibilityElement *element=next[key]; element.descriptor=[descriptors[key] copy]; }
        h.semanticNodes=[next copy]; h.semanticRevision=revision;
        [h.pendingText removeAllObjects];
    }
    for (NSArray *pair in notifications) NSAccessibilityPostNotification(pair[0],pair[1]);
    if (structureChanged) NSAccessibilityPostNotification(h.view,NSAccessibilityLayoutChangedNotification);
}
void stn_window_semantic_text(stn_window p, uint64_t identity, stn_utf8 text, uint64_t start, uint64_t length, stn_rect bounds, const double *offsets, size_t count, uint64_t revision, bool secure) {
    STNWindowHost *h=STNHost(p); STNTextSnapshot *s=STNMakeTextSnapshot(text,start,length,UINT64_MAX,0,bounds,offsets,count,revision,secure);
    h.pendingText[@(identity)]=s;
}
size_t stn_window_semantic_count(stn_window p) { return STNHost(p).semanticNodes.count; }
uint64_t stn_window_semantic_revision(stn_window p) { return STNHost(p).semanticRevision; }
