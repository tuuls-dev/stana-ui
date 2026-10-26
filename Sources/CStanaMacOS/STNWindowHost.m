#import "STNPrivate.h"

@implementation STNWindowHost
- (void)emit:(stn_event)event { if (!self.closing && self.eventCallback) self.eventCallback(self.context, &event); }
- (void)textRequest:(int)kind text:(NSString *)text replacement:(NSRange)replacement selected:(NSRange)selected {
    [self textRequest:kind text:text replacement:replacement selected:selected revision:self.view.textSnapshot.revision];
}
- (void)textRequest:(int)kind text:(NSString *)text replacement:(NSRange)replacement selected:(NSRange)selected revision:(uint64_t)revision {
    if (!self.closing && self.textCallback) self.textCallback(self.context, kind, STNBorrowedString(text),
        replacement.location == NSNotFound ? UINT64_MAX : replacement.location, replacement.length, selected.location, selected.length, revision);
}
- (void)windowDidResize:(NSNotification *)n {
    NSSize s = self.view.bounds.size;
    [self emit:(stn_event){.kind=1, .x=s.width, .y=s.height, .a=self.window.backingScaleFactor}];
    [self.view setNeedsDisplay:YES];
}
- (void)windowDidChangeBackingProperties:(NSNotification *)n { [self windowDidResize:n]; }
- (void)windowDidMove:(NSNotification *)n { [self windowDidResize:n]; }
- (void)windowDidChangeScreen:(NSNotification *)n { [self windowDidResize:n]; }
- (void)windowWillClose:(NSNotification *)n { [self emit:(stn_event){.kind=7}]; }
- (void)windowDidResignKey:(NSNotification *)n {
    [self.view.inputContext discardMarkedText]; [self emit:(stn_event){.kind=11}];
}
- (void)dealloc {
    if (_backing) CGContextRelease(_backing);
    if (_appearanceObserver) [[NSDistributedNotificationCenter defaultCenter] removeObserver:_appearanceObserver];
    if (_displayObserver) [NSWorkspace.sharedWorkspace.notificationCenter removeObserver:_displayObserver];
}
@end

stn_window stn_window_create(stn_utf8 title, double width, double height, void *context, stn_event_callback event, stn_draw_callback draw, stn_text_callback text) {
    stn_app_initialize();
    STNWindowHost *host = [STNWindowHost new];
    host.context = context; host.eventCallback = event; host.drawCallback = draw; host.textCallback = text;
    host.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, width, height)
        styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskMiniaturizable|NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
    host.window.releasedWhenClosed = NO; host.window.title = STNUTF8(title); host.window.delegate = host;
    host.view = [[STNContentView alloc] initWithFrame:NSMakeRect(0, 0, width, height)]; host.view.host = host;
    host.window.contentView = host.view; host.window.acceptsMouseMovedEvents = YES;
    host.semanticNodes = @{}; host.pendingText=[NSMutableDictionary dictionary]; [host.window center];
    __weak STNWindowHost *weakHost = host;
    host.appearanceObserver = [[NSDistributedNotificationCenter defaultCenter] addObserverForName:@"AppleInterfaceThemeChangedNotification" object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *n) {
        STNWindowHost *h = weakHost;
        if (h) [h emit:(stn_event){.kind=10, .x=[h.view.effectiveAppearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua,NSAppearanceNameDarkAqua]] == NSAppearanceNameDarkAqua, .y=NSWorkspace.sharedWorkspace.accessibilityDisplayShouldIncreaseContrast, .a=NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion}];
    }];
    host.displayObserver = [NSWorkspace.sharedWorkspace.notificationCenter addObserverForName:NSWorkspaceAccessibilityDisplayOptionsDidChangeNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *n) { [weakHost.view viewDidChangeEffectiveAppearance]; }];
    return (__bridge_retained void *)host;
}
void stn_window_show(stn_window p) { STNWindowHost *h=STNHost(p); [h.window makeKeyAndOrderFront:nil]; [h.window makeFirstResponder:h.view]; [h windowDidResize:[NSNotification notificationWithName:NSWindowDidResizeNotification object:h.window]]; [h.view viewDidChangeEffectiveAppearance]; }
void stn_window_redraw(stn_window p) { [STNHost(p).view setNeedsDisplay:YES]; }
void stn_window_title(stn_window p, stn_utf8 title) { STNHost(p).window.title = STNUTF8(title); }
void stn_window_destroy(stn_window p) {
    if (!p) return;
    STNWindowHost *host = (__bridge_transfer STNWindowHost *)p;
    host.closing = YES; host.eventCallback = NULL; host.drawCallback = NULL; host.textCallback = NULL; host.context = NULL;
    [host.view.inputContext deactivate]; host.window.delegate = nil; host.view.host = nil; [host.window close];
    host.semanticNodes = @{};
}
void stn_window_focus_text(stn_window p, bool editing) {
    STNContentView *view = STNHost(p).view; view.editing = editing;
    if (editing) { [view.window makeFirstResponder:view]; [view.inputContext activate]; }
    else { [view.inputContext deactivate]; view.textSnapshot = nil; }
}
void stn_window_discard_marked(stn_window p) { [STNHost(p).view.inputContext discardMarkedText]; }
bool stn_window_test_key_equivalent(stn_window p, stn_utf8 key) {
    STNWindowHost *host=STNHost(p); NSString *characters=STNUTF8(key);
    NSEvent *event=[NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:NSEventModifierFlagCommand timestamp:0 windowNumber:host.window.windowNumber context:nil characters:characters charactersIgnoringModifiers:characters isARepeat:NO keyCode:0];
    return [host.view performKeyEquivalent:event];
}

@implementation STNContentView
- (BOOL)isFlipped { return YES; }
- (BOOL)isOpaque { return YES; }
- (BOOL)acceptsFirstResponder { return YES; }
- (BOOL)acceptsFirstMouse:(NSEvent *)event { return YES; }
- (void)updateTrackingAreas {
    [super updateTrackingAreas]; if (self.tracking) [self removeTrackingArea:self.tracking];
    self.tracking = [[NSTrackingArea alloc] initWithRect:NSZeroRect options:NSTrackingMouseMoved|NSTrackingActiveInKeyWindow|NSTrackingInVisibleRect owner:self userInfo:nil]; [self addTrackingArea:self.tracking];
}
- (void)drawRect:(NSRect)dirty {
    STNWindowHost *h=self.host;
    if (h.drawCallback) h.drawCallback(h.context);
    if (h.backing) {
        CGImageRef image= CGBitmapContextCreateImage(h.backing);
        CGContextRef ctx=NSGraphicsContext.currentContext.CGContext;
        CGContextSaveGState(ctx); CGContextTranslateCTM(ctx,0,self.bounds.size.height); CGContextScaleCTM(ctx,1,-1);
        CGContextDrawImage(ctx, self.bounds, image); CGContextRestoreGState(ctx); CGImageRelease(image);
    }
}
- (void)pointer:(NSEvent *)event kind:(int)kind { NSPoint p=[self convertPoint:event.locationInWindow fromView:nil]; [self.host emit:(stn_event){.kind=kind,.x=p.x,.y=p.y}]; }
- (void)mouseDown:(NSEvent *)e { [self pointer:e kind:2]; }
- (void)mouseDragged:(NSEvent *)e { [self pointer:e kind:3]; }
- (void)mouseMoved:(NSEvent *)e { [self pointer:e kind:3]; }
- (void)mouseUp:(NSEvent *)e { [self pointer:e kind:4]; }
- (void)scrollWheel:(NSEvent *)e { NSPoint p=[self convertPoint:e.locationInWindow fromView:nil]; [self.host emit:(stn_event){.kind=5,.x=p.x,.y=p.y,.a=e.scrollingDeltaX,.b=e.scrollingDeltaY}]; }
- (BOOL)performKeyEquivalent:(NSEvent *)event {
    NSString *key=event.charactersIgnoringModifiers.lowercaseString;
    if ((event.modifierFlags & NSEventModifierFlagCommand) && self.editing && [@[@"a",@"c",@"v",@"x",@"z"] containsObject:key]) { [self keyDown:event]; return YES; }
    return [super performKeyEquivalent:event];
}
- (void)keyDown:(NSEvent *)e {
    NSString *characters=e.charactersIgnoringModifiers ?: @"";
    if (self.editing) {
        if (e.modifierFlags & NSEventModifierFlagCommand) {
            NSDictionary *commands=@{@"a":@"selectAll:",@"c":@"copy:",@"v":@"paste:",@"x":@"cut:",@"z":(e.modifierFlags & NSEventModifierFlagShift) ? @"redo:" : @"undo:"};
            NSString *command=commands[characters.lowercaseString];
            if (command) { [self doCommandBySelector:NSSelectorFromString(command)]; return; }
        }
        [self interpretKeyEvents:@[e]];
    } else {
        [self.host emit:(stn_event){.kind=6,.text=STNBorrowedString(characters),.a=(e.modifierFlags & NSEventModifierFlagShift)!=0,.b=(e.modifierFlags & NSEventModifierFlagCommand)!=0}];
    }
}
- (void)viewDidChangeEffectiveAppearance {
    [super viewDidChangeEffectiveAppearance];
    NSString *appearance=[self.effectiveAppearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua,NSAppearanceNameDarkAqua]];
    [self.host emit:(stn_event){.kind=10,.x=[appearance isEqualToString:NSAppearanceNameDarkAqua],.y=NSWorkspace.sharedWorkspace.accessibilityDisplayShouldIncreaseContrast,.a=NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion}];
}
@end
