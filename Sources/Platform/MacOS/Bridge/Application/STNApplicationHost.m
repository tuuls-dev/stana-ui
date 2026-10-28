#import "../STNPrivate.h"

@interface STNAppDelegate : NSObject <NSApplicationDelegate>
@end
@implementation STNAppDelegate
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
	return YES;
}
@end
static STNAppDelegate *applicationDelegate;

uint32_t stn_abi_version(void) { return STN_ABI_VERSION; }
void stn_app_initialize(void) {
	NSCAssert([NSThread isMainThread], @"Stana host must run on the main thread");
	[NSApplication sharedApplication];
	[NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
	if (!applicationDelegate) {
		applicationDelegate = [STNAppDelegate new];
		NSApp.delegate = applicationDelegate;
	}
}
void stn_app_run(void) {
	stn_app_initialize();
	[NSApp activate];
	[NSApp run];
}
void stn_app_stop(void) {
	[NSApp stop:nil];
	[NSApp postEvent:[NSEvent otherEventWithType:NSEventTypeApplicationDefined
	                                    location:NSZeroPoint
	                               modifierFlags:0
	                                   timestamp:0
	                                windowNumber:0
	                                     context:nil
	                                     subtype:0
	                                       data1:0
	                                       data2:0]
	         atStart:NO];
}
