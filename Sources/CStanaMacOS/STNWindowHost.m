#import "STNPrivate.h"
#import "STNWindowClasses.h"

@implementation STNWindowHost
- (void)emit:(stn_event)event { if (self.applyingConfiguration && event.kind==1) return; if (!self.closing && self.eventCallback) self.eventCallback(self.context, &event); }
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
    [self publishState];
}
- (void)windowDidChangeBackingProperties:(NSNotification *)n { [self windowDidResize:n]; }
- (void)windowDidMove:(NSNotification *)n { [self windowDidResize:n]; }
- (void)windowDidChangeScreen:(NSNotification *)n { [self windowDidResize:n]; }
- (BOOL)windowShouldClose:(NSWindow *)sender {
    return !self.windowCallbacks.should_close || self.windowCallbacks.should_close(self.context);
}
- (void)windowWillClose:(NSNotification *)n { [self emit:(stn_event){.kind=7}]; }
- (void)windowDidBecomeKey:(NSNotification *)n { [self publishState]; }
- (void)windowDidBecomeMain:(NSNotification *)n { [self publishState]; }
- (void)windowDidResignMain:(NSNotification *)n { [self publishState]; }
- (void)windowDidMiniaturize:(NSNotification *)n { [self publishState]; }
- (void)windowDidDeminiaturize:(NSNotification *)n { [self publishState]; }
- (void)windowDidChangeOcclusionState:(NSNotification *)n { [self publishState]; }
- (void)windowWillStartLiveResize:(NSNotification *)n { [self publishState]; }
- (void)windowDidEndLiveResize:(NSNotification *)n { [self publishState]; [self becameIdle]; }
- (void)windowWillEnterFullScreen:(NSNotification *)n { self.fullscreenTransition=1; [self publishState]; }
- (void)windowWillExitFullScreen:(NSNotification *)n { self.fullscreenTransition=2; [self publishState]; }
- (void)finishFullscreen:(int32_t)status {
    uint64_t operation=self.fullscreenOperation; self.fullscreenOperation=0; self.fullscreenTransition=0;
    [self publishState]; [self completeOperation:operation status:status result:0]; [self becameIdle];
}
- (void)windowDidEnterFullScreen:(NSNotification *)n { [self finishFullscreen:0]; }
- (void)windowDidExitFullScreen:(NSNotification *)n { [self finishFullscreen:0]; }
- (void)windowDidFailToEnterFullScreen:(NSWindow *)w { [self finishFullscreen:3]; }
- (void)windowDidFailToExitFullScreen:(NSWindow *)w { [self finishFullscreen:3]; }
- (void)windowDidResignKey:(NSNotification *)n {
    [self.view.inputContext discardMarkedText]; [self emit:(stn_event){.kind=11}]; [self publishState];
}
- (void)dealloc {
    if (_backing) CGContextRelease(_backing);
    if (_appearanceObserver) [[NSDistributedNotificationCenter defaultCenter] removeObserver:_appearanceObserver];
    if (_displayObserver) [NSWorkspace.sharedWorkspace.notificationCenter removeObserver:_displayObserver];
}
@end

stn_window stn_window_create(stn_utf8 title, double width, double height, void *context, stn_event_callback event, stn_draw_callback draw, stn_text_callback text) {
    return stn_window_create_role(title, width, height, 0, context, event, draw, text);
}
stn_window stn_window_create_role(stn_utf8 title, double width, double height, int32_t role, void *context, stn_event_callback event, stn_draw_callback draw, stn_text_callback text) {
    return stn_window_create_host(title,width,height,role,NULL,context,event,draw,text);
}
stn_window stn_window_create_host(stn_utf8 title, double width, double height, int32_t role, stn_window parent, void *context, stn_event_callback event, stn_draw_callback draw, stn_text_callback text) {
    stn_app_initialize();
    STNWindowHost *host = [STNWindowHost new];
    host.context = context; host.eventCallback = event; host.drawCallback = draw; host.textCallback = text;
    host.role = role; host.surfaceOpaque = YES; host.followsMinimizedTitle=YES;
    if (parent) {
        host.isSurface=YES; host.window=STNHost(parent).window; host.surfaceOpaque=NO;
        host.view=[[STNContentView alloc] initWithFrame:NSMakeRect(0,0,width,height)]; host.view.host=host;
        host.semanticNodes=@{}; host.pendingText=[NSMutableDictionary dictionary];
        return (__bridge_retained void *)host;
    }
    NSWindowStyleMask style = NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskMiniaturizable|NSWindowStyleMaskResizable;
    if (role == 2) style |= NSWindowStyleMaskUtilityWindow;
    if (role == 3) style |= NSWindowStyleMaskHUDWindow;
    if (role == 4) style |= NSWindowStyleMaskNonactivatingPanel;
    host.window = [[(role ? STNHostPanel.class : STNHostWindow.class) alloc] initWithContentRect:NSMakeRect(0,0,width,height) styleMask:style backing:NSBackingStoreBuffered defer:NO];
    [(id)host.window setNativeHost:host];
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
    [host startObservingWindow];
    return (__bridge_retained void *)host;
}
void stn_window_show(stn_window p) { stn_window_action(p,1); [STNHost(p).view viewDidChangeEffectiveAppearance]; }
void stn_window_redraw(stn_window p) { [STNHost(p).view setNeedsDisplay:YES]; }
void stn_window_title(stn_window p, stn_utf8 title) {
    STNWindowHost *h=STNHost(p); h.window.title=STNUTF8(title);
    if (h.followsMinimizedTitle) h.window.miniwindowTitle=h.window.title;
}
void stn_window_destroy(stn_window p) {
    if (!p) return;
    STNWindowHost *host = (__bridge_transfer STNWindowHost *)p;
    [host.dragTimer invalidate]; host.dragTimer=nil; [host stopObservingWindow];
    host.closing = YES; host.windowCallbacks = (stn_window_callbacks){0}; host.eventCallback = NULL; host.drawCallback = NULL; host.textCallback = NULL; host.context = NULL;
    [host.view.inputContext deactivate]; host.view.host = nil;
    if (host.isSurface) { [host.view removeFromSuperview]; }
    else {
        if (host.window.sheetParent) [host.window.sheetParent endSheet:host.window returnCode:0];
        for (NSWindow *sheet in host.window.sheets) [host.window endSheet:sheet returnCode:0];
        host.window.toolbar=nil; host.toolbarDelegate=nil;
        if (host.window.styleMask & NSWindowStyleMaskTitled)
            while (host.window.titlebarAccessoryViewControllers.count) [host.window removeTitlebarAccessoryViewControllerAtIndex:host.window.titlebarAccessoryViewControllers.count-1];
        host.window.delegate=nil; [host.window close];
    }
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
- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    if (self.window && self.editing) {
        [self.window makeFirstResponder:self]; [self.inputContext activate];
    }
}
- (void)setFrameSize:(NSSize)size {
    [super setFrameSize:size];
    if (self.host) [self.host windowDidResize:[NSNotification notificationWithName:NSWindowDidResizeNotification object:self.window]];
}
- (BOOL)isOpaque { return self.host.surfaceOpaque; }
- (BOOL)needsPanelToBecomeKey {
    NSEvent *event=NSApp.currentEvent;
    if (event && self.host.windowCallbacks.pointer) {
        NSPoint p=[self convertPoint:event.locationInWindow fromView:nil];
        return self.host.windowCallbacks.pointer(self.host.context,3,p.x,p.y)!=0;
    }
    return self.editing;
}
- (BOOL)acceptsFirstResponder { return YES; }
- (BOOL)resignFirstResponder {
    if (![super resignFirstResponder]) return NO;
    STNWindowHost *root=[(id)self.window nativeHost];
    if (!self.host.applyingConfiguration && !root.applyingConfiguration && !self.host.closing) {
        [self.host emit:(stn_event){.kind=15,.x=0}];
    }
    return YES;
}
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
        CGContextClearRect(ctx, NSRectToCGRect(self.bounds));
        CGContextSaveGState(ctx); CGContextTranslateCTM(ctx,0,self.bounds.size.height); CGContextScaleCTM(ctx,1,-1);
        CGContextDrawImage(ctx, self.bounds, image); CGContextRestoreGState(ctx); CGImageRelease(image);
    }
}
- (void)pointer:(NSEvent *)event kind:(int)kind {
    NSPoint p=[self convertPoint:event.locationInWindow fromView:nil];
    if (self.host.windowCallbacks.pointer) self.host.windowCallbacks.pointer(self.host.context,kind-2,p.x,p.y);
    else [self.host emit:(stn_event){.kind=kind,.x=p.x,.y=p.y}];
}
- (void)mouseDown:(NSEvent *)e {
    STNWindowHost *host=self.host;
    if (!host.windowCallbacks.pointer) { [self pointer:e kind:2]; return; }
    NSPoint p=[self convertPoint:e.locationInWindow fromView:nil];
    int32_t action=host.windowCallbacks.pointer(host.context,0,p.x,p.y);
    if (action==1 && host.window.movable) {
        STNBeginWindowTracking(host); [host.window performWindowDragWithEvent:e];
    } else if (action>=16 && (host.window.styleMask & NSWindowStyleMaskResizable)) {
        STNResizeWindow(host,e,action & 15);
    }
}
- (void)mouseDragged:(NSEvent *)e {
    if (self.host.resizeEdges) STNResizeWindow(self.host,e,0);
    else [self pointer:e kind:3];
}
- (void)mouseMoved:(NSEvent *)e { [self pointer:e kind:3]; }
- (void)mouseUp:(NSEvent *)e {
    if (self.host.resizeEdges) STNResizeWindow(self.host,e,-1);
    else [self pointer:e kind:4];
}
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

bool stn_window_test_marked_text(stn_window p, stn_utf8 text, bool commit) {
    NSResponder *responder=STNHost(p).window.firstResponder;
    if (![responder isKindOfClass:STNContentView.class] || ![(STNContentView *)responder editing]) return false;
    STNContentView *view=(STNContentView *)responder;
    if (commit) [view unmarkText];
    else {
        NSString *string=STNUTF8(text);
        [view setMarkedText:string selectedRange:NSMakeRange(string.length,0) replacementRange:NSMakeRange(NSNotFound,0)];
    }
    return true;
}
