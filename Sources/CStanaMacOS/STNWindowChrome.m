#import "STNPrivate.h"

@interface STNToolbarDelegate : NSObject <NSToolbarDelegate>
@property(nonatomic, weak) STNWindowHost *host;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSToolbarItem *> *items;
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, id> *commands;
@property(nonatomic, strong) NSArray<NSString *> *allowed, *defaults;
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, NSNumber *> *checked;
@end
@implementation STNToolbarDelegate
- (NSArray<NSToolbarItemIdentifier> *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar { return self.allowed; }
- (NSArray<NSToolbarItemIdentifier> *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar { return self.defaults; }
- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar itemForItemIdentifier:(NSToolbarItemIdentifier)identifier willBeInsertedIntoToolbar:(BOOL)flag {
    return self.items[identifier];
}
- (void)invoke:(id)sender {
    uint64_t command=(uint64_t)[sender tag]; STNWindowHost *h=self.host;
    if ([sender isKindOfClass:NSButton.class]) [(NSButton *)sender setState:[self.checked[@(command)] boolValue] ? NSControlStateValueOn : NSControlStateValueOff];
    if (!h.closing && h.windowCallbacks.command) h.windowCallbacks.command(h.context,command);
}
@end

static NSMenu *STNToolbarMenu(STNToolbarDelegate *delegate, const stn_toolbar_item *items, size_t count) {
    NSMenu *menu=[NSMenu new]; menu.autoenablesItems=NO;
    for (size_t i=0;i<count;i++) {
        const stn_toolbar_item *c=&items[i];
        if (c->kind==1) { [menu addItem:NSMenuItem.separatorItem]; continue; }
        NSMenuItem *item=[[NSMenuItem alloc] initWithTitle:STNUTF8(c->title) action:c->command ? @selector(invoke:) : nil keyEquivalent:@""];
        item.target=delegate; item.tag=(NSInteger)c->command; item.enabled=c->enabled; item.state=c->checked ? NSControlStateValueOn : NSControlStateValueOff;
        if (c->image && c->image_length) item.image=[[NSImage alloc] initWithData:[NSData dataWithBytes:c->image length:c->image_length]];
        if (c->command) delegate.commands[@(c->command)]=item;
        if (c->children && c->child_count) item.submenu=STNToolbarMenu(delegate,c->children,c->child_count);
        [menu addItem:item];
    }
    return menu;
}
static NSToolbarItem *STNToolbarItem(STNToolbarDelegate *delegate, const stn_toolbar_item *c) {
    NSString *identifier=c->kind==2 ? NSToolbarSpaceItemIdentifier : c->kind==3 ? NSToolbarFlexibleSpaceItemIdentifier : STNUTF8(c->identifier);
    NSToolbarItem *item;
    if (c->kind==4) {
        NSToolbarItemGroup *group=[[NSToolbarItemGroup alloc] initWithItemIdentifier:identifier];
        NSMutableArray *children=[NSMutableArray new];
        for (size_t i=0;i<c->child_count;i++) [children addObject:STNToolbarItem(delegate,&c->children[i])];
        group.subitems=children; item=group;
    } else if (c->kind==5) {
        NSMenuToolbarItem *menu=[[NSMenuToolbarItem alloc] initWithItemIdentifier:identifier];
        menu.menu=STNToolbarMenu(delegate,c->children,c->child_count); item=menu;
    } else {
        item=[[NSToolbarItem alloc] initWithItemIdentifier:identifier];
        if (c->kind==6 && c->surface) {
            STNWindowHost *surface=STNHost(c->surface); item.view=surface.view;
        } else if (c->kind==1) {
            NSView *space=[[NSView alloc] initWithFrame:NSMakeRect(0,0,c->kind==3 ? 32 : 12,24)];
            if (c->kind==3) space.autoresizingMask=NSViewWidthSizable;
            item.view=space;
            if (c->kind==1) {
                NSBox *line=[[NSBox alloc] initWithFrame:NSMakeRect(5,2,1,20)]; line.boxType=NSBoxSeparator; [space addSubview:line];
            }
        }
    }
    item.label=STNUTF8(c->title); item.paletteLabel=item.label; item.toolTip=STNUTF8(c->tooltip);
    item.enabled=c->enabled; item.visibilityPriority=c->priority; item.autovalidates=NO;
    if (c->command) {
        item.target=delegate; item.action=@selector(invoke:); item.tag=(NSInteger)c->command;
        delegate.commands[@(c->command)]=item; delegate.checked[@(c->command)]=@(c->checked);
        NSButton *button=[NSButton buttonWithTitle:STNUTF8(c->title) target:delegate action:@selector(invoke:)];
        [button setButtonType:NSButtonTypePushOnPushOff]; button.bezelStyle=NSBezelStyleTexturedRounded;
        button.tag=(NSInteger)c->command; button.state=c->checked ? NSControlStateValueOn : NSControlStateValueOff;
        button.enabled=c->enabled; button.toolTip=STNUTF8(c->tooltip); [button sizeToFit]; item.view=button;
    }
    if (c->image && c->image_length) item.image=[[NSImage alloc] initWithData:[NSData dataWithBytes:c->image length:c->image_length]];
    if ([item.view isKindOfClass:NSButton.class]) {
        NSButton *button=(NSButton *)item.view; button.image=item.image;
        button.imagePosition=item.image ? NSImageLeading : NSNoImage; [button sizeToFit];
    }
    delegate.items[identifier]=item; return item;
}
int32_t stn_window_toolbar(stn_window p, stn_utf8 identifier, const stn_toolbar_item *items, size_t count,
    const stn_utf8 *defaults, size_t defaultCount, bool allowsCustomization, bool autosaves,
    bool replacing, bool visible, int32_t style, int32_t display) {
    STNWindowHost *h=STNHost(p); NSWindow *w=h.window;
    if (replacing) {
        if (!identifier.length) { w.toolbar=nil; h.toolbarDelegate=nil; [h publishState]; return 0; }
        STNToolbarDelegate *delegate=[STNToolbarDelegate new]; delegate.host=h;
        delegate.items=[NSMutableDictionary new]; delegate.commands=[NSMutableDictionary new]; delegate.checked=[NSMutableDictionary new];
        NSMutableArray *allowed=[NSMutableArray new],*defaultIDs=[NSMutableArray new];
        NSMutableDictionary *nativeIDs=[NSMutableDictionary new];
        for (size_t i=0;i<count;i++) {
            NSToolbarItem *item=STNToolbarItem(delegate,&items[i]); [allowed addObject:item.itemIdentifier];
            nativeIDs[STNUTF8(items[i].identifier)]=item.itemIdentifier;
        }
        for (size_t i=0;i<defaultCount;i++) [defaultIDs addObject:nativeIDs[STNUTF8(defaults[i])] ?: STNUTF8(defaults[i])];
        delegate.allowed=allowed; delegate.defaults=defaultIDs;
        NSToolbar *toolbar=[[NSToolbar alloc] initWithIdentifier:STNUTF8(identifier)];
        toolbar.delegate=delegate; toolbar.allowsUserCustomization=allowsCustomization;
        toolbar.autosavesConfiguration=autosaves;
        h.toolbarDelegate=delegate; w.toolbar=toolbar;
    }
    w.toolbarStyle=(NSWindowToolbarStyle)style;
    if (w.toolbar) {
        w.toolbar.visible=visible; w.toolbar.displayMode=(NSToolbarDisplayMode)display;
        STNToolbarDelegate *delegate=h.toolbarDelegate;
        for (id value in delegate.commands.allValues) if ([value isKindOfClass:NSToolbarItem.class]) {
            NSToolbarItem *item=value;
            if ([item.view isKindOfClass:NSButton.class]) {
                NSButton *button=(NSButton *)item.view;
                button.imagePosition=!button.image || display==3 ? NSNoImage : display==2 ? NSImageOnly : NSImageLeading;
                [button sizeToFit];
            }
        }
    }
    [h windowDidResize:[NSNotification notificationWithName:NSWindowDidResizeNotification object:h.window]]; return 0;
}
void stn_window_toolbar_update(stn_window p, uint64_t commandID, stn_utf8 title, bool enabled, bool checked) {
    STNToolbarDelegate *delegate=STNHost(p).toolbarDelegate; id item=delegate.commands[@(commandID)];
    if ([item isKindOfClass:NSMenuItem.class]) {
        NSMenuItem *menu=item; menu.title=STNUTF8(title); menu.enabled=enabled; menu.state=checked ? NSControlStateValueOn : NSControlStateValueOff;
    } else if ([item isKindOfClass:NSToolbarItem.class]) {
        NSToolbarItem *toolbar=item; toolbar.label=STNUTF8(title); toolbar.paletteLabel=toolbar.label; toolbar.enabled=enabled;
        delegate.checked[@(commandID)]=@(checked);
        if ([toolbar.view isKindOfClass:NSButton.class]) {
            NSButton *button=(NSButton *)toolbar.view; button.title=toolbar.label; button.enabled=enabled;
            button.state=checked ? NSControlStateValueOn : NSControlStateValueOff; [button sizeToFit];
        }
    }
}
int32_t stn_window_accessories(stn_window p, const stn_window_accessory *accessories, size_t count) {
    STNWindowHost *h=STNHost(p);
    if (!(h.window.styleMask & NSWindowStyleMaskTitled)) return count ? 1 : 0;
    NSMutableDictionary *byID=[NSMutableDictionary new]; NSMutableArray *ordered=[NSMutableArray new];
    for (size_t i=0;i<count;i++) {
        const stn_window_accessory *c=&accessories[i]; NSString *key=STNUTF8(c->identifier);
        NSTitlebarAccessoryViewController *controller=h.accessories[key]; STNWindowHost *surface=STNHost(c->surface);
        if (!controller || controller.view!=surface.view) { controller=[NSTitlebarAccessoryViewController new]; controller.view=surface.view; }
        controller.layoutAttribute=c->placement==0 ? NSLayoutAttributeLeading : c->placement==1 ? NSLayoutAttributeTrailing : NSLayoutAttributeBottom;
        controller.fullScreenMinHeight=c->fullscreen_minimum_height; controller.hidden=c->hidden;
        byID[key]=controller; [ordered addObject:controller];
    }
    if (![h.window.titlebarAccessoryViewControllers isEqualToArray:ordered]) {
        while (h.window.titlebarAccessoryViewControllers.count) [h.window removeTitlebarAccessoryViewControllerAtIndex:h.window.titlebarAccessoryViewControllers.count-1];
        for (NSTitlebarAccessoryViewController *controller in ordered) [h.window addTitlebarAccessoryViewController:controller];
    }
    h.accessories=byID;
    [h windowDidResize:[NSNotification notificationWithName:NSWindowDidResizeNotification object:h.window]]; return 0;
}

int32_t stn_window_tab_accessory(stn_window p, stn_window surface) {
    NSWindow *w=STNHost(p).window;
    if (!(w.styleMask & NSWindowStyleMaskTitled)) return surface ? 1 : 0;
    NSView *view=surface ? STNHost(surface).view : nil;
    if (w.tab.accessoryView!=view) {
        NSSize size=view.bounds.size;
        w.tab.accessoryView=view;
        if (view) {
            [view.widthAnchor constraintEqualToConstant:size.width].active=YES;
            [view.heightAnchor constraintEqualToConstant:size.height].active=YES;
        }
    }
    return 0;
}
