#import "STNWindowClasses.h"

@implementation STNHostWindow
- (BOOL)canBecomeKeyWindow {
	return self.nativeHost.keyPreference != 2;
}
- (BOOL)canBecomeMainWindow {
	return self.nativeHost.mainPreference != 2;
}
@end
@implementation STNHostPanel
- (BOOL)canBecomeKeyWindow {
	return self.nativeHost.keyPreference != 2;
}
- (BOOL)canBecomeMainWindow {
	return self.nativeHost.mainPreference == 1;
}
@end

static BOOL STNPreference(int32_t value, BOOL automatic) { return value == 0 ? automatic : value == 1; }
static NSSize STNSize(stn_rect value) { return NSMakeSize(value.width, value.height); }
static CGFloat STNScreenTop(void) { return NSScreen.screens.firstObject.frame.size.height; }
static stn_rect STNPortableRect(NSRect value) {
	return (stn_rect){value.origin.x, STNScreenTop() - NSMaxY(value), value.size.width, value.size.height};
}
static NSRect STNNativeFrame(stn_rect value) {
	return NSMakeRect(value.x, STNScreenTop() - value.y - value.height, value.width, value.height);
}
static NSString *STNScreenID(NSScreen *screen) {
	return [screen.deviceDescription[@"NSScreenNumber"] stringValue] ?: @"";
}

static char STNWindowObservationContext;
@implementation STNWindowHost (Configuration)
- (void)refreshObservedTabGroup {
	NSWindowTabGroup *group = self.window.tabGroup;
	if (group == self.observedTabGroup)
		return;
	if (self.observedTabGroup)
		for (NSString *key in @[ @"windows", @"selectedWindow", @"overviewVisible", @"tabBarVisible" ])
			[self.observedTabGroup removeObserver:self forKeyPath:key context:&STNWindowObservationContext];
	self.observedTabGroup = group;
	if (group)
		for (NSString *key in @[ @"windows", @"selectedWindow", @"overviewVisible", @"tabBarVisible" ])
			[group addObserver:self forKeyPath:key options:0 context:&STNWindowObservationContext];
}
- (void)startObservingWindow {
	if (self.isSurface || self.observingWindow)
		return;
	self.observingWindow = YES;
	for (NSString *key in @[ @"contentLayoutRect", @"tabbedWindows", @"tabGroup" ])
		[self.window addObserver:self forKeyPath:key options:0 context:&STNWindowObservationContext];
	[self refreshObservedTabGroup];
}
- (void)stopObservingWindow {
	if (!self.observingWindow)
		return;
	self.observingWindow = NO;
	for (NSString *key in @[ @"contentLayoutRect", @"tabbedWindows", @"tabGroup" ])
		[self.window removeObserver:self forKeyPath:key context:&STNWindowObservationContext];
	if (self.observedTabGroup)
		for (NSString *key in @[ @"windows", @"selectedWindow", @"overviewVisible", @"tabBarVisible" ])
			[self.observedTabGroup removeObserver:self forKeyPath:key context:&STNWindowObservationContext];
	self.observedTabGroup = nil;
}
- (void)observeValueForKeyPath:(NSString *)key
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context {
	if (context != &STNWindowObservationContext) {
		[super observeValueForKeyPath:key ofObject:object change:change context:context];
		return;
	}
	if (self.closing)
		return;
	if ([key isEqualToString:@"tabGroup"])
		[self refreshObservedTabGroup];
	if ([key isEqualToString:@"contentLayoutRect"])
		[self windowDidResize:[NSNotification notificationWithName:NSWindowDidResizeNotification object:self.window]];
	else
		[self publishState];
}
- (void)publishState {
	if (self.closing || !self.windowCallbacks.state || self.applyingConfiguration)
		return;
	NSWindow *w = self.window;
	NSRect content = self.view.bounds;
	NSRect safe = self.isSurface ? self.view.bounds : [self.view convertRect:w.contentLayoutRect fromView:nil];
	NSArray<NSWindow *> *children = w.childWindows ?: @[], *tabs = w.tabbedWindows ?: @[];
	NSMutableData *childData = [NSMutableData dataWithLength:children.count * sizeof(uint64_t)];
	NSMutableData *tabData = [NSMutableData dataWithLength:tabs.count * sizeof(uint64_t)];
	uint64_t *childIDs = childData.mutableBytes, *tabIDs = tabData.mutableBytes;
	for (NSUInteger i = 0; i < children.count; i++)
		childIDs[i] = (uint64_t)children[i].windowNumber;
	for (NSUInteger i = 0; i < tabs.count; i++)
		tabIDs[i] = (uint64_t)tabs[i].windowNumber;
	stn_window_state state = {.visible = w.visible,
	                          .key = w.keyWindow,
	                          .main = w.mainWindow,
	                          .minimized = w.miniaturized,
	                          .zoomed = w.zoomed,
	                          .fullscreen = (w.styleMask & NSWindowStyleMaskFullScreen) != 0,
	                          .fullscreen_transition = self.fullscreenTransition,
	                          .live_resize = w.inLiveResize,
	                          .active_space = w.onActiveSpace,
	                          .occluded = (w.occlusionState & NSWindowOcclusionStateVisible) == 0,
	                          .has_sheet = w.attachedSheet != nil,
	                          .is_sheet = w.sheetParent != nil,
	                          .has_sharing = w.hasActiveWindowSharingSession,
	                          .frame = STNPortableRect(w.frame),
	                          .content = {0, 0, content.size.width, content.size.height},
	                          .safe_content = {safe.origin.x, safe.origin.y, safe.size.width, safe.size.height},
	                          .scale = w.backingScaleFactor,
	                          .selected_tab = (uint64_t)w.tabGroup.selectedWindow.windowNumber,
	                          .tab_bar_visible = w.tabGroup.tabBarVisible,
	                          .tab_overview_visible = w.tabGroup.overviewVisible,
	                          .identity = (uint64_t)w.windowNumber,
	                          .parent = w.parentWindow ? (uint64_t)w.parentWindow.windowNumber : 0,
	                          .children = childIDs,
	                          .child_count = children.count,
	                          .tabs = tabIDs,
	                          .tab_count = tabs.count,
	                          .screen_id = STNBorrowedString(STNScreenID(w.screen))};
	self.windowCallbacks.state(self.context, &state);
}
- (void)completeOperation:(uint64_t)operation status:(int32_t)status result:(int32_t)result {
	if (!self.closing && operation && self.windowCallbacks.operation)
		self.windowCallbacks.operation(self.context, operation, status, result);
}
- (void)becameIdle {
	if (!self.closing && self.windowCallbacks.idle)
		self.windowCallbacks.idle(self.context);
}
@end
void stn_window_set_callbacks(stn_window p, stn_window_callbacks callbacks) { STNHost(p).windowCallbacks = callbacks; }
void stn_window_publish_state(stn_window p) { [STNHost(p) publishState]; }
bool stn_window_busy(stn_window p) {
	STNWindowHost *h = STNHost(p);
	return h.window.inLiveResize || h.draggingWindow || h.fullscreenTransition || h.window.attachedSheet ||
	       (h.window.styleMask & NSWindowStyleMaskFullScreen) != 0;
}

static void STNButton(NSWindow *w, NSWindowButton button, int32_t visibility, int32_t enabled, BOOL allowed) {
	NSButton *b = [w standardWindowButton:button];
	b.hidden = visibility == 2;
	b.enabled = STNPreference(enabled, allowed);
}
static NSRect STNConstrain(NSWindow *, NSRect);
int32_t stn_window_validate_config(stn_window p, const stn_window_config *c) {
	NSWindowStyleMask style = c->frame == 2 ? NSWindowStyleMaskBorderless : NSWindowStyleMaskTitled;
	if (c->full_size_content == 1 && c->frame != 2)
		style |= NSWindowStyleMaskFullSizeContentView;
	NSSize min = [NSWindow frameRectForContentRect:NSMakeRect(0, 0, c->min_content.width, c->min_content.height)
	                                     styleMask:style]
	                 .size;
	min.width = MAX(min.width, c->min_frame.width);
	min.height = MAX(min.height, c->min_frame.height);
	NSSize max = NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX);
	if (c->max_content.width > 0 && c->max_content.height > 0)
		max = [NSWindow frameRectForContentRect:NSMakeRect(0, 0, c->max_content.width, c->max_content.height)
		                              styleMask:style]
		          .size;
	if (c->max_frame.width > 0)
		max.width = MIN(max.width, c->max_frame.width);
	if (c->max_frame.height > 0)
		max.height = MIN(max.height, c->max_frame.height);
	if (min.width > max.width || min.height > max.height)
		return 2;
	if (c->aspect.width > 0 && c->aspect.height > 0) {
		NSSize decoration =
		    c->frame_aspect ? NSZeroSize : [NSWindow frameRectForContentRect:NSZeroRect styleMask:style].size;
		CGFloat ratio = c->aspect.width / c->aspect.height;
		CGFloat low = MAX(min.width - decoration.width, (min.height - decoration.height) * ratio);
		CGFloat high = MIN(max.width - decoration.width, (max.height - decoration.height) * ratio);
		if (low > high)
			return 2;
	}
	return 0;
}
void stn_window_apply(stn_window p, const stn_window_config *c) {
	STNWindowHost *h = STNHost(p);
	NSWindow *w = h.window;
	h.applyingConfiguration = YES;
	NSSize contentSize = h.view.bounds.size;
	NSPoint topLeft = NSMakePoint(NSMinX(w.frame), NSMaxY(w.frame));
	NSResponder *responder = w.firstResponder;
	BOOL restoreResponder = [responder isKindOfClass:STNContentView.class];
	NSWindowStyleMask mask = c->frame == 2 ? NSWindowStyleMaskBorderless : NSWindowStyleMaskTitled;
	if (c->can_close)
		mask |= NSWindowStyleMaskClosable;
	if (c->can_minimize)
		mask |= NSWindowStyleMaskMiniaturizable;
	if (c->resizable)
		mask |= NSWindowStyleMaskResizable;
	if (h.role == 2)
		mask |= NSWindowStyleMaskUtilityWindow;
	if (h.role == 3)
		mask |= NSWindowStyleMaskHUDWindow;
	if (h.role == 4)
		mask |= NSWindowStyleMaskNonactivatingPanel;
	if (c->full_size_content == 1 && c->frame != 2)
		mask |= NSWindowStyleMaskFullSizeContentView;
	mask |= w.styleMask & NSWindowStyleMaskFullScreen;
	if (w.styleMask != mask) {
		if (!(mask & NSWindowStyleMaskTitled) && (w.styleMask & NSWindowStyleMaskTitled)) {
			while (w.titlebarAccessoryViewControllers.count)
				[w removeTitlebarAccessoryViewControllerAtIndex:w.titlebarAccessoryViewControllers.count - 1];
			w.toolbar = nil;
			h.toolbarDelegate = nil;
			h.accessories = @{};
		}
		w.styleMask = mask;
		w.contentView = h.view;
		[w setContentSize:contentSize];
		[w setFrameTopLeftPoint:topLeft];
		if (restoreResponder && [(NSView *)responder window] == w)
			[w makeFirstResponder:responder];
	}
	h.keyPreference = c->can_key;
	h.mainPreference = c->can_main;
	if (c->can_key == 2 && w.keyWindow)
		[w resignKeyWindow];
	if (c->can_main == 2 && w.mainWindow)
		[w resignMainWindow];
	w.subtitle = STNUTF8(c->subtitle);
	w.titleVisibility = c->title_visibility == 2 ? NSWindowTitleHidden : NSWindowTitleVisible;
	w.titlebarAppearsTransparent = c->title_transparent == 1;
	w.titlebarSeparatorStyle = (NSTitlebarSeparatorStyle)c->separator;
	STNButton(w, NSWindowCloseButton, c->close_visibility, c->close_enabled, c->can_close);
	STNButton(w, NSWindowMiniaturizeButton, c->minimize_visibility, c->minimize_enabled, c->can_minimize);
	STNButton(w, NSWindowZoomButton, c->zoom_visibility, c->zoom_enabled, c->resizable);
	w.alphaValue = c->opacity;
	w.hasShadow = STNPreference(c->shadow, YES);
	w.backgroundColor = [NSColor colorWithSRGBRed:c->background.red
	                                        green:c->background.green
	                                         blue:c->background.blue
	                                        alpha:c->background.alpha];
	h.surfaceOpaque = c->background.alpha >= 1;
	w.opaque = h.surfaceOpaque;
	w.appearance = c->appearance == 1   ? [NSAppearance appearanceNamed:NSAppearanceNameAqua]
	               : c->appearance == 2 ? [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua]
	                                    : nil;
	w.movable = c->movable;
	// Stana resolves background dragging against its retained hit-test tree.
	w.movableByWindowBackground = NO;
	w.ignoresMouseEvents = c->ignores_mouse;
	w.acceptsMouseMovedEvents = c->mouse_moved;
	w.allowsToolTipsWhenApplicationIsInactive = STNPreference(c->inactive_tooltips, NO);
	w.hidesOnDeactivate = STNPreference(c->hides_on_deactivate, h.role != 0);
	w.canHide = STNPreference(c->can_hide, YES);
	w.preventsApplicationTerminationWhenModal = STNPreference(c->prevents_termination, YES);
	w.excludedFromWindowsMenu = c->excluded_from_menu;
	w.canBecomeVisibleWithoutLogin = c->visible_without_login;
	if ([w isKindOfClass:NSPanel.class]) {
		NSPanel *panel = (NSPanel *)w;
		panel.floatingPanel = STNPreference(c->floating_panel, NO);
		panel.becomesKeyOnlyIfNeeded = STNPreference(c->key_only_if_needed, NO);
		panel.worksWhenModal = STNPreference(c->works_when_modal, NO);
	}
	w.level = c->automatic_level && [w isKindOfClass:NSPanel.class] && ((NSPanel *)w).floatingPanel
	              ? NSFloatingWindowLevel
	              : c->level;
	const NSWindowAnimationBehavior animations[] = {
	    NSWindowAnimationBehaviorDefault, NSWindowAnimationBehaviorNone, NSWindowAnimationBehaviorDocumentWindow,
	    NSWindowAnimationBehaviorUtilityWindow, NSWindowAnimationBehaviorAlertPanel};
	w.animationBehavior = animations[MAX(0, MIN(4, c->animation))];
	NSWindowCollectionBehavior collection = 0;
	if (c->spaces == 1)
		collection |= NSWindowCollectionBehaviorCanJoinAllSpaces;
	if (c->spaces == 2)
		collection |= NSWindowCollectionBehaviorMoveToActiveSpace;
	const NSWindowCollectionBehavior management[] = {0, NSWindowCollectionBehaviorManaged,
	                                                 NSWindowCollectionBehaviorTransient,
	                                                 NSWindowCollectionBehaviorStationary};
	const NSWindowCollectionBehavior membership[] = {0, NSWindowCollectionBehaviorPrimary,
	                                                 NSWindowCollectionBehaviorAuxiliary,
	                                                 NSWindowCollectionBehaviorCanJoinAllApplications};
	const NSWindowCollectionBehavior fullscreen[] = {0, NSWindowCollectionBehaviorFullScreenPrimary,
	                                                 NSWindowCollectionBehaviorFullScreenAuxiliary,
	                                                 NSWindowCollectionBehaviorFullScreenNone};
	collection |= management[MAX(0, MIN(3, c->management))] | membership[MAX(0, MIN(3, c->application_membership))] |
	              fullscreen[MAX(0, MIN(3, c->fullscreen))];
	if (c->cycle)
		collection |=
		    c->cycle == 1 ? NSWindowCollectionBehaviorParticipatesInCycle : NSWindowCollectionBehaviorIgnoresCycle;
	if (c->tiling)
		collection |= c->tiling == 1 ? NSWindowCollectionBehaviorFullScreenAllowsTiling
		                             : NSWindowCollectionBehaviorFullScreenDisallowsTiling;
	w.collectionBehavior = collection;
	const NSWindowTabbingMode tabbing[] = {NSWindowTabbingModeAutomatic, NSWindowTabbingModePreferred,
	                                       NSWindowTabbingModeDisallowed};
	w.tabbingMode = tabbing[MAX(0, MIN(2, c->tabbing))];
	w.tabbingIdentifier = STNUTF8(c->tabbing_identifier);
	// Clear previous constraints before installing the next complete snapshot.
	w.minSize = NSZeroSize;
	w.maxSize = NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX);
	w.contentMinSize = STNSize(c->min_content);
	w.contentMaxSize = c->max_content.width > 0 && c->max_content.height > 0 ? STNSize(c->max_content)
	                                                                         : NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX);
	NSSize frameMinimum = w.minSize, frameMaximum = w.maxSize;
	frameMinimum.width = MAX(frameMinimum.width, c->min_frame.width);
	frameMinimum.height = MAX(frameMinimum.height, c->min_frame.height);
	if (c->max_frame.width > 0)
		frameMaximum.width = MIN(frameMaximum.width, c->max_frame.width);
	if (c->max_frame.height > 0)
		frameMaximum.height = MIN(frameMaximum.height, c->max_frame.height);
	w.minSize = frameMinimum;
	w.maxSize = frameMaximum;
	h.configuredAspect = STNSize(c->aspect);
	h.configuredIncrements = STNSize(c->increments);
	h.aspectIsFrame = c->frame_aspect;
	h.incrementsAreFrame = c->frame_increments;
	if (c->aspect.width > 0 && c->aspect.height > 0) {
		if (c->frame_aspect)
			w.aspectRatio = STNSize(c->aspect);
		else
			w.contentAspectRatio = STNSize(c->aspect);
	} else {
		w.contentAspectRatio = NSZeroSize;
		NSSize increments =
		    c->increments.width > 0 && c->increments.height > 0 ? STNSize(c->increments) : NSMakeSize(1, 1);
		if (c->frame_increments)
			w.resizeIncrements = increments;
		else
			w.contentResizeIncrements = increments;
	}
	w.minFullScreenContentSize = STNSize(c->min_fullscreen);
	w.maxFullScreenContentSize = c->max_fullscreen.width > 0 && c->max_fullscreen.height > 0
	                                 ? STNSize(c->max_fullscreen)
	                                 : NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX);
	w.preservesContentDuringLiveResize = STNPreference(c->preserves_content, YES);
	for (NSInteger edge = 0; edge < 4; edge++) {
		CGFloat thickness = edge == NSMinXEdge   ? c->content_border.x
		                    : edge == NSMaxXEdge ? c->content_border.width
		                    : edge == NSMaxYEdge ? c->content_border.y
		                                         : c->content_border.height;
		[w setAutorecalculatesContentBorderThickness:!c->has_content_border forEdge:(NSRectEdge)edge];
		if (c->has_content_border)
			[w setContentBorderThickness:thickness forEdge:(NSRectEdge)edge];
	}
	NSString *url = STNUTF8(c->represented_url);
	w.representedURL = url.length ? [NSURL URLWithString:url] : nil;
	w.documentEdited = c->document_edited;
	h.followsMinimizedTitle = !c->has_minimized_title;
	w.miniwindowTitle = c->has_minimized_title ? STNUTF8(c->minimized_title) : w.title;
	w.miniwindowImage = c->minimized_image && c->minimized_image_length
	                        ? [[NSImage alloc] initWithData:[NSData dataWithBytes:c->minimized_image
	                                                                       length:c->minimized_image_length]]
	                        : nil;
	w.dockTile.badgeLabel = STNUTF8(c->dock_badge);
	if (w.styleMask & NSWindowStyleMaskTitled) {
		w.tab.title = c->has_tab_title ? STNUTF8(c->tab_title) : nil;
		w.tab.toolTip = c->has_tab_tooltip ? STNUTF8(c->tab_tooltip) : nil;
	}
	if (!(w.styleMask & NSWindowStyleMaskFullScreen)) {
		NSRect constrained = STNConstrain(w, w.frame);
		if (!NSEqualRects(constrained, w.frame))
			[w setFrame:constrained display:NO];
	}
	[h.view setNeedsDisplay:YES];
	[w invalidateShadow];
	h.applyingConfiguration = NO;
	[h windowDidResize:[NSNotification notificationWithName:NSWindowDidResizeNotification object:w]];
	[h.view viewDidChangeEffectiveAppearance];
}

static NSRect STNConstrain(NSWindow *w, NSRect frame) {
	frame.size.width = MAX(w.minSize.width, MIN(w.maxSize.width, frame.size.width));
	frame.size.height = MAX(w.minSize.height, MIN(w.maxSize.height, frame.size.height));
	STNWindowHost *host = [(id)w nativeHost];
	BOOL frameSizing = host.configuredAspect.width > 0 ? host.aspectIsFrame : host.incrementsAreFrame;
	NSRect content = frameSizing ? frame : [w contentRectForFrameRect:frame];
	NSSize decoration = NSMakeSize(frame.size.width - content.size.width, frame.size.height - content.size.height);
	NSSize low = NSMakeSize(MAX(0, w.minSize.width - decoration.width), MAX(0, w.minSize.height - decoration.height));
	NSSize high = NSMakeSize(w.maxSize.width - decoration.width, w.maxSize.height - decoration.height);
	NSSize ratio = host.configuredAspect;
	if (ratio.width > 0 && ratio.height > 0) {
		CGFloat aspect = ratio.width / ratio.height;
		CGFloat minWidth = MAX(low.width, low.height * aspect), maxWidth = MIN(high.width, high.height * aspect);
		content.size.width = MAX(minWidth, MIN(maxWidth, content.size.width));
		content.size.height = content.size.width / aspect;
	} else {
		NSSize step = host.configuredIncrements;
		if (step.width > 1)
			content.size.width = MAX(low.width, MIN(high.width, round(content.size.width / step.width) * step.width));
		if (step.height > 1)
			content.size.height =
			    MAX(low.height, MIN(high.height, round(content.size.height / step.height) * step.height));
	}
	frame.size = NSMakeSize(content.size.width + decoration.width, content.size.height + decoration.height);
	return frame;
}
void STNBeginWindowTracking(STNWindowHost *h) {
	[h.dragTimer invalidate];
	h.draggingWindow = YES;
	__weak STNWindowHost *weakHost = h;
	h.dragTimer = [NSTimer timerWithTimeInterval:0.05
	                                     repeats:YES
	                                       block:^(NSTimer *timer) {
		                                       STNWindowHost *host = weakHost;
		                                       if (!host || host.closing || !(NSEvent.pressedMouseButtons & 1)) {
			                                       [timer invalidate];
			                                       host.dragTimer = nil;
			                                       host.draggingWindow = NO;
			                                       host.resizeEdges = 0;
			                                       [host publishState];
			                                       [host becameIdle];
		                                       }
	                                       }];
	[NSRunLoop.mainRunLoop addTimer:h.dragTimer forMode:NSRunLoopCommonModes];
}
void STNResizeWindow(STNWindowHost *h, NSEvent *event, int32_t edges) {
	NSWindow *w = h.window;
	if (edges > 0) {
		h.resizeEdges = edges;
		h.resizeOriginal = w.frame;
		h.resizeStart = [w convertPointToScreen:event.locationInWindow];
		STNBeginWindowTracking(h);
		return;
	}
	if (edges < 0) {
		[h.dragTimer invalidate];
		h.dragTimer = nil;
		h.resizeEdges = 0;
		h.draggingWindow = NO;
		[h publishState];
		[h becameIdle];
		return;
	}
	edges = h.resizeEdges;
	if (!edges || h.closing)
		return;
	NSPoint point = [w convertPointToScreen:event.locationInWindow];
	CGFloat dx = point.x - h.resizeStart.x, dy = point.y - h.resizeStart.y;
	NSRect original = h.resizeOriginal, f = original;
	if (edges & 1)
		f.size.height += dy;
	if (edges & 2) {
		f.origin.x += dx;
		f.size.width -= dx;
	}
	if (edges & 4) {
		f.origin.y += dy;
		f.size.height -= dy;
	}
	if (edges & 8)
		f.size.width += dx;
	f = STNConstrain(w, f);
	if (edges & 2)
		f.origin.x = NSMaxX(original) - f.size.width;
	if (edges & 4)
		f.origin.y = NSMaxY(original) - f.size.height;
	[w setFrame:f display:YES];
}
int32_t stn_window_action(stn_window p, int32_t action) {
	STNWindowHost *h = STNHost(p);
	NSWindow *w = h.window;
	if (!w || h.closing)
		return 2;
	switch (action) {
	case 1: {
		if (!w.canBecomeKeyWindow)
			return 2;
		NSResponder *responder = w.firstResponder;
		[w makeKeyAndOrderFront:nil];
		[w makeFirstResponder:[responder isKindOfClass:STNContentView.class] && [(NSView *)responder window] == w
		                          ? responder
								  : h.view];
		break;
	}
	case 2:
		[w orderFront:nil];
		break;
	case 3:
		[w orderOut:nil];
		break;
	case 4: {
		if (!w.canBecomeKeyWindow)
			return 2;
		NSResponder *responder = w.firstResponder;
		[w makeKeyWindow];
		[w makeFirstResponder:[responder isKindOfClass:STNContentView.class] && [(NSView *)responder window] == w
		                          ? responder
								  : h.view];
		break;
	}
	case 5:
		[w center];
		break;
	case 6:
		if (!(w.styleMask & NSWindowStyleMaskMiniaturizable))
			return 1;
		[w miniaturize:nil];
		break;
	case 7:
		[w deminiaturize:nil];
		break;
	case 8:
		if (!(w.styleMask & NSWindowStyleMaskResizable))
			return 1;
		[w zoom:nil];
		break;
	case 9:
		[w orderFront:nil];
		break;
	case 10:
		[w orderBack:nil];
		break;
	case 11:
		if (!(w.styleMask & NSWindowStyleMaskClosable))
			return 1;
		if ([h windowShouldClose:w])
			[w close];
		break;
	case 14:
		if (!w.toolbar || !w.toolbar.allowsUserCustomization)
			return 1;
		[w runToolbarCustomizationPalette:nil];
		break;
	case 15:
		if (!w.toolbar)
			return 1;
		[w toggleToolbarShown:nil];
		break;
	case 16:
		if (!w.tabGroup)
			return 1;
		[w selectNextTab:nil];
		break;
	case 17:
		if (!w.tabGroup)
			return 1;
		[w selectPreviousTab:nil];
		break;
	case 18:
		if (!w.tabGroup)
			return 1;
		[w moveTabToNewWindow:nil];
		break;
	case 19:
		if (w.tabbingMode == NSWindowTabbingModeDisallowed)
			return 1;
		[w mergeAllWindows:nil];
		break;
	case 20:
		if (!w.tabGroup)
			return 1;
		[w toggleTabBar:nil];
		break;
	case 21:
		if (!w.tabGroup)
			return 1;
		[w toggleTabOverview:nil];
		break;
	default:
		return 1;
	}
	[h windowDidResize:[NSNotification notificationWithName:NSWindowDidResizeNotification object:h.window]];
	return 0;
}
int32_t stn_window_fullscreen(stn_window p, bool value, uint64_t operation) {
	STNWindowHost *h = STNHost(p);
	NSWindow *w = h.window;
	if (h.fullscreenTransition || w.attachedSheet || w.sheetParent)
		return 2;
	if (((w.styleMask & NSWindowStyleMaskFullScreen) != 0) == value) {
		[h completeOperation:operation status:0 result:0];
		return 0;
	}
	if (value && (!(w.styleMask & NSWindowStyleMaskTitled) || !(w.styleMask & NSWindowStyleMaskResizable) ||
	              (w.collectionBehavior & NSWindowCollectionBehaviorFullScreenNone)))
		return 1;
	if (value && !(w.collectionBehavior &
	               (NSWindowCollectionBehaviorFullScreenPrimary | NSWindowCollectionBehaviorFullScreenAuxiliary)))
		w.collectionBehavior |= NSWindowCollectionBehaviorFullScreenPrimary;
	h.fullscreenOperation = operation;
	h.fullscreenTransition = value ? 1 : 2;
	[w toggleFullScreen:nil];
	[h publishState];
	return 0;
}
int32_t stn_window_set_frame(stn_window p, stn_rect frame, bool animate) {
	STNWindowHost *h = STNHost(p);
	if (h.fullscreenTransition || (h.window.styleMask & NSWindowStyleMaskFullScreen))
		return 2;
	[h.window setFrame:STNConstrain(h.window, STNNativeFrame(frame)) display:YES animate:animate];
	[h publishState];
	return 0;
}
int32_t stn_window_set_content_size(stn_window p, double width, double height) {
	STNWindowHost *h = STNHost(p);
	if (h.fullscreenTransition || (h.window.styleMask & NSWindowStyleMaskFullScreen))
		return 2;
	NSRect frame = [h.window frameRectForContentRect:NSMakeRect(0, 0, width, height)];
	frame.origin = h.window.frame.origin;
	[h.window setFrame:STNConstrain(h.window, frame) display:YES];
	[h publishState];
	return 0;
}
int32_t stn_window_relate(stn_window p, stn_window other, int32_t relationship) {
	STNWindowHost *h = STNHost(p), *o = STNHost(other);
	if (!h || !o || h == o || h.closing || o.closing)
		return 2;
	if (relationship == 1 || relationship == 2) {
		for (NSWindow *ancestor = h.window; ancestor; ancestor = ancestor.parentWindow)
			if (ancestor == o.window)
				return 2;
		if (o.window.sheetParent || o.window.parentWindow || o.window.tabbedWindows.count > 1)
			return 2;
		[h.window addChildWindow:o.window ordered:relationship == 1 ? NSWindowAbove : NSWindowBelow];
	} else if (relationship == 3) {
		if (o.window.parentWindow != h.window)
			return 2;
		[h.window removeChildWindow:o.window];
	} else if (relationship == 4 || relationship == 5) {
		if (!(h.window.styleMask & NSWindowStyleMaskTitled) || !(o.window.styleMask & NSWindowStyleMaskTitled) ||
		    h.role || o.role || h.window.tabbingMode == NSWindowTabbingModeDisallowed ||
		    o.window.tabbingMode == NSWindowTabbingModeDisallowed)
			return 1;
		if (h.window.sheetParent || o.window.sheetParent || h.window.parentWindow || o.window.parentWindow)
			return 2;
		[h.window addTabbedWindow:o.window ordered:relationship == 4 ? NSWindowBelow : NSWindowAbove];
	} else if (relationship == 6 || relationship == 7) {
		if (!h.window.tabGroup || ![h.window.tabGroup.windows containsObject:o.window])
			return 2;
		if (relationship == 6)
			h.window.tabGroup.selectedWindow = o.window;
		else
			[h.window.tabGroup removeWindow:o.window];
	} else
		return 1;
	[h publishState];
	[o publishState];
	return 0;
}
int32_t stn_window_begin_sheet(stn_window p, stn_window sheet, bool critical, uint64_t operation) {
	STNWindowHost *h = STNHost(p), *s = STNHost(sheet);
	if (!h || !s || h == s || h.closing || s.closing || s.window.sheetParent || s.window.parentWindow ||
	    s.window.tabbedWindows.count > 1)
		return 2;
	if (h.window.attachedSheet && !critical)
		return 2;
	h.modalDepth += 1;
	[h emit:(stn_event){.kind = 14, .x = 1}];
	__weak STNWindowHost *weakHost = h;
	void (^finished)(NSModalResponse) = ^(NSModalResponse result) {
		STNWindowHost *host = weakHost;
		if (host.modalDepth)
			host.modalDepth -= 1;
		[host emit:(stn_event){.kind = 14, .x = host.modalDepth > 0}];
		[host publishState];
		[s publishState];
		[host completeOperation:operation status:0 result:(int32_t)result];
		[host becameIdle];
	};
	if (critical)
		[h.window beginCriticalSheet:s.window completionHandler:finished];
	else
		[h.window beginSheet:s.window completionHandler:finished];
	[h publishState];
	[s publishState];
	return 0;
}
int32_t stn_window_end_sheet(stn_window p, int32_t result) {
	NSWindow *w = STNHost(p).window;
	if (!w.sheetParent)
		return 2;
	[w.sheetParent endSheet:w returnCode:result];
	[w orderOut:nil];
	return 0;
}
int32_t stn_window_share(stn_window p, stn_window other, uint64_t operation) {
	STNWindowHost *h = STNHost(p), *o = STNHost(other);
	__weak STNWindowHost *weakHost = h;
	void (^finished)(NSError *) = ^(NSError *error) {
		STNWindowHost *host = weakHost;
		[host publishState];
		[host completeOperation:operation status:error ? 3 : 0 result:0];
	};
	if (o) {
		if (!h.window.hasActiveWindowSharingSession)
			return 2;
		[h.window transferWindowSharingToWindow:o.window completionHandler:finished];
		return 0;
	}
	if (@available(macOS 15.0, *)) {
		[h.window requestSharingOfWindow:h.window completionHandler:finished];
		return 0;
	}
	return 1;
}
void stn_window_place(stn_window p, stn_utf8 identifier, stn_utf8 screenID, stn_utf8 autosave, bool hasOrigin, double x,
                      double y) {
	NSWindow *w = STNHost(p).window;
	w.identifier = STNUTF8(identifier);
	NSString *target = STNUTF8(screenID);
	for (NSScreen *screen in NSScreen.screens)
		if ([STNScreenID(screen) isEqualToString:target]) {
			NSRect frame = w.frame;
			frame.origin = NSMakePoint(NSMidX(screen.visibleFrame) - frame.size.width / 2,
			                           NSMidY(screen.visibleFrame) - frame.size.height / 2);
			[w setFrame:frame display:NO];
			break;
		}
	if (hasOrigin)
		[w setFrameTopLeftPoint:NSMakePoint(x, STNScreenTop() - y)];
	NSString *name = STNUTF8(autosave);
	if (name.length) {
		[w setFrameUsingName:name];
		[w setFrameAutosaveName:name];
	}
	NSRect frame = [w constrainFrameRect:w.frame toScreen:w.screen];
	[w setFrame:frame display:NO];
	[STNHost(p) publishState];
}
void stn_window_erase_saved_frame(stn_utf8 name) { [NSWindow removeFrameUsingName:STNUTF8(name)]; }
uint64_t stn_window_test_style(stn_window p) { return STNHost(p).window.styleMask; }
double stn_window_test_property(stn_window p, int32_t property) {
	NSWindow *w = STNHost(p).window;
	switch (property) {
	case 1:
		return w.opaque;
	case 2:
		return w.canBecomeKeyWindow;
	case 3:
		return w.canBecomeMainWindow;
	case 4:
		return [w isKindOfClass:NSPanel.class];
	case 5:
		return w.contentMinSize.width;
	case 6:
		return w.contentMinSize.height;
	case 7:
		return w.alphaValue;
	case 8:
		return w.hasShadow;
	case 9:
		return [w standardWindowButton:NSWindowCloseButton].hidden;
	case 10:
		return [w standardWindowButton:NSWindowMiniaturizeButton].hidden;
	case 11:
		return [w standardWindowButton:NSWindowZoomButton].hidden;
	case 12:
		return w.contentMaxSize.width;
	case 13:
		return w.contentMaxSize.height;
	case 14:
		return w.toolbar.items.count;
	case 15:
		return (w.styleMask & NSWindowStyleMaskTitled) ? w.titlebarAccessoryViewControllers.count : 0;
	default:
		return -1;
	}
}

int32_t stn_window_manage_frame(stn_window p, stn_utf8 name, bool restore, bool *restored) {
	STNWindowHost *h = STNHost(p);
	if (stn_window_busy(p))
		return 2;
	NSString *key = STNUTF8(name);
	if (!key.length)
		return 2;
	if (restore) {
		*restored = [h.window setFrameUsingName:key];
		NSRect frame = [h.window constrainFrameRect:h.window.frame toScreen:h.window.screen];
		[h.window setFrame:STNConstrain(h.window, frame) display:YES];
		[h windowDidResize:[NSNotification notificationWithName:NSWindowDidResizeNotification object:h.window]];
	} else {
		[h.window saveFrameUsingName:key];
		*restored = YES;
	}
	return 0;
}
void stn_screens(void *context, stn_screen_callback callback) {
	stn_app_initialize();
	for (NSScreen *screen in NSScreen.screens) {
		stn_screen value = {.identifier = STNBorrowedString(STNScreenID(screen)),
		                    .name = STNBorrowedString(screen.localizedName),
		                    .frame = STNPortableRect(screen.frame),
		                    .visible_frame = STNPortableRect(screen.visibleFrame),
		                    .scale = screen.backingScaleFactor};
		callback(context, &value);
	}
}
