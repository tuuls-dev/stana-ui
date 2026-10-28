#import "STNPrivate.h"

void stn_clipboard_write(stn_utf8 text) {
	NSPasteboard *p = NSPasteboard.generalPasteboard;
	[p clearContents];
	[p setString:STNUTF8(text) forType:NSPasteboardTypeString];
}
char *stn_clipboard_copy(size_t *length) {
	NSString *value = [NSPasteboard.generalPasteboard stringForType:NSPasteboardTypeString];
	if (!value) {
		*length = 0;
		return NULL;
	}
	NSData *data = [value dataUsingEncoding:NSUTF8StringEncoding];
	*length = data.length;
	char *result = malloc(data.length + 1);
	if (!result) {
		*length = 0;
		return NULL;
	}
	memcpy(result, data.bytes, data.length);
	result[data.length] = 0;
	return result;
}
void stn_string_free(char *value) { free(value); }

@interface STNMenuTarget : NSObject
@property(nonatomic) void *context;
@property(nonatomic) stn_command_callback callback;
- (void)invoke:(NSMenuItem *)item;
@end
@implementation STNMenuTarget
- (void)invoke:(NSMenuItem *)item {
	if (self.callback)
		self.callback(self.context, (uint64_t)item.tag);
}
@end
static STNMenuTarget *menuTarget;
static NSMutableDictionary<NSNumber *, NSMenuItem *> *menuItems;
static NSMutableDictionary<NSNumber *, NSMenu *> *submenus;
static uint64_t menuSerial;

void stn_menu_reset(void *context, stn_command_callback callback) {
	stn_app_initialize();
	if (menuTarget) {
		menuTarget.callback = NULL;
		menuTarget.context = NULL;
	}
	menuTarget = [STNMenuTarget new];
	menuTarget.context = context;
	menuTarget.callback = callback;
	menuItems = [NSMutableDictionary dictionary];
	submenus = [NSMutableDictionary dictionary];
	menuSerial = 0;
	NSMenu *main = [[NSMenu alloc] initWithTitle:@""];
	main.autoenablesItems = NO;
	NSApp.mainMenu = main;
	submenus[@0] = main;
	NSMenuItem *app = [NSMenuItem new];
	app.submenu = [[NSMenu alloc] initWithTitle:NSProcessInfo.processInfo.processName];
	[main addItem:app];
	[app.submenu addItemWithTitle:@"About" action:@selector(orderFrontStandardAboutPanel:) keyEquivalent:@""];
	[app.submenu addItem:NSMenuItem.separatorItem];
	[app.submenu addItemWithTitle:@"Hide" action:@selector(hide:) keyEquivalent:@"h"];
	[app.submenu addItemWithTitle:@"Quit" action:@selector(terminate:) keyEquivalent:@"q"];
}
uint64_t stn_menu_add(uint64_t parent, stn_utf8 title, uint64_t command, stn_utf8 key, uint32_t modifiers, bool enabled,
                      bool checked) {
	NSMenu *menu = submenus[@(parent)];
	if (!menu)
		return 0;
	uint64_t identity = ++menuSerial;
	NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:STNUTF8(title)
	                                              action:command ? @selector(invoke:) : nil
	                                       keyEquivalent:STNUTF8(key)];
	item.target = menuTarget;
	item.tag = (NSInteger)command;
	item.enabled = enabled;
	item.state = checked ? NSControlStateValueOn : NSControlStateValueOff;
	item.keyEquivalentModifierMask =
	    ((modifiers & 1) ? NSEventModifierFlagCommand : 0) | ((modifiers & 2) ? NSEventModifierFlagShift : 0) |
	    ((modifiers & 4) ? NSEventModifierFlagOption : 0) | ((modifiers & 8) ? NSEventModifierFlagControl : 0);
	if (!command) {
		item.submenu = [[NSMenu alloc] initWithTitle:STNUTF8(title)];
		item.submenu.autoenablesItems = NO;
		submenus[@(identity)] = item.submenu;
	}
	[menu addItem:item];
	menuItems[@(identity)] = item;
	return identity;
}
void stn_menu_update(uint64_t identity, stn_utf8 title, bool enabled, bool checked) {
	NSMenuItem *item = menuItems[@(identity)];
	item.title = STNUTF8(title);
	item.enabled = enabled;
	item.state = checked ? NSControlStateValueOn : NSControlStateValueOff;
}
static STNWindowHost *STNModalHost(NSWindow *window) {
	return [window.delegate isKindOfClass:STNWindowHost.class] ? (STNWindowHost *)window.delegate : nil;
}
static void STNModalBegin(STNWindowHost *host) {
	if (host) {
		host.modalDepth += 1;
		[host emit:(stn_event){.kind = 14, .x = 1}];
	}
}
static void STNModalEnd(STNWindowHost *host) {
	if (host && host.modalDepth) {
		host.modalDepth -= 1;
		[host emit:(stn_event){.kind = 14, .x = host.modalDepth > 0}];
	}
}

@interface STNStandaloneAlert : NSObject <NSWindowDelegate>
@property(nonatomic, strong) NSAlert *alert;
@property(nonatomic) void *context;
@property(nonatomic) stn_dialog_callback callback;
@property(nonatomic) BOOL finished;
- (void)dismiss:(id)sender;
@end
static NSMutableSet<STNStandaloneAlert *> *standaloneAlerts;
@implementation STNStandaloneAlert
- (void)dismiss:(id)sender {
	if (self.finished)
		return;
	self.finished = YES;
	[self.alert.window close];
	if (self.callback)
		self.callback(self.context, NULL, 0);
	self.callback = NULL;
	self.context = NULL;
	[standaloneAlerts removeObject:self];
}
- (void)windowWillClose:(NSNotification *)notification {
	[self dismiss:nil];
}
@end
void stn_file_dialog(stn_window window, bool save, stn_utf8 suggestedName, void *context,
                     stn_dialog_callback callback) {
	NSSavePanel *panel = save ? [NSSavePanel savePanel] : [NSOpenPanel openPanel];
	if (save && suggestedName.length)
		panel.nameFieldStringValue = STNUTF8(suggestedName);
	if (!save) {
		NSOpenPanel *open = (NSOpenPanel *)panel;
		open.canChooseDirectories = NO;
		open.allowsMultipleSelection = NO;
	}
	NSWindow *parent = window ? STNHost(window).window : NSApp.mainWindow;
	__weak STNWindowHost *host = STNModalHost(parent);
	STNModalBegin(host);
	void (^complete)(NSModalResponse) = ^(NSModalResponse response) {
		STNModalEnd(host);
		callback(context, response == NSModalResponseOK ? panel.URL.path.UTF8String : NULL,
		         response == NSModalResponseOK ? 0 : 1);
	};
	if (parent)
		[panel beginSheetModalForWindow:parent completionHandler:complete];
	else
		[panel beginWithCompletionHandler:complete];
}
void stn_alert(stn_window window, stn_utf8 title, stn_utf8 message, void *context, stn_dialog_callback callback) {
	NSAlert *alert = [NSAlert new];
	alert.messageText = STNUTF8(title);
	alert.informativeText = STNUTF8(message);
	[alert addButtonWithTitle:@"OK"];
	NSWindow *parent = window ? STNHost(window).window : NSApp.mainWindow;
	__weak STNWindowHost *host = STNModalHost(parent);
	STNModalBegin(host);
	if (parent)
		[alert beginSheetModalForWindow:parent
		              completionHandler:^(NSModalResponse r) {
			              STNModalEnd(host);
			              callback(context, NULL, 0);
		              }];
	else {
		if (!standaloneAlerts)
			standaloneAlerts = [NSMutableSet set];
		STNStandaloneAlert *presenter = [STNStandaloneAlert new];
		presenter.alert = alert;
		presenter.context = context;
		presenter.callback = callback;
		[standaloneAlerts addObject:presenter];
		alert.window.delegate = presenter;
		alert.buttons.firstObject.target = presenter;
		alert.buttons.firstObject.action = @selector(dismiss:);
		[alert.window center];
		[alert.window makeKeyAndOrderFront:nil];
	}
}
