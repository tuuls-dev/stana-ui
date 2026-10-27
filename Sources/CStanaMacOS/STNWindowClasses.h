#import "STNPrivate.h"
@interface STNHostWindow : NSWindow
@property(nonatomic, weak) STNWindowHost *nativeHost;
@end
@interface STNHostPanel : NSPanel
@property(nonatomic, weak) STNWindowHost *nativeHost;
@end
void STNResizeWindow(STNWindowHost *, NSEvent *, int32_t);

void STNBeginWindowTracking(STNWindowHost *);
