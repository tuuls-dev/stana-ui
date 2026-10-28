#import "STNPrivate.h"
#import "STNMetal.h"

static void STNSetColor(CGContextRef c, stn_color color, BOOL stroke) {
	if (stroke)
		CGContextSetRGBStrokeColor(c, color.red, color.green, color.blue, color.alpha);
	else
		CGContextSetRGBFillColor(c, color.red, color.green, color.blue, color.alpha);
}
static CGPathRef STNPath(stn_rect rect, double radius) {
	return CGPathCreateWithRoundedRect(STNRect(rect), MAX(0, MIN(radius, MIN(rect.width, rect.height) / 2)),
	                                   MAX(0, MIN(radius, MIN(rect.width, rect.height) / 2)), NULL);
}
bool stn_frame_begin(stn_window p, double width, double height, const stn_rect *damage, size_t count, bool full) {
	STNWindowHost *h = STNHost(p);
	double scale = h.window.backingScaleFactor;
	size_t w = (size_t)ceil(width * scale), heightPx = (size_t)ceil(height * scale);
	if (!w || !heightPx || w > 16384 || heightPx > 16384 || w * heightPx > 67108864)
		return false;
	if (!h.backing || h.pixelWidth != w || h.pixelHeight != heightPx || h.scale != scale) {
		if (h.backing)
			CGContextRelease(h.backing);
		CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
		h.backing = CGBitmapContextCreate(NULL, w, heightPx, 8, w * 4, space,
		                                  kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
		CGColorSpaceRelease(space);
		if (!h.backing)
			return false;
		h.pixelWidth = w;
		h.pixelHeight = heightPx;
		h.scale = scale;
		full = true;
		CGContextTranslateCTM(h.backing, 0, heightPx);
		CGContextScaleCTM(h.backing, scale, -scale);
	}
	CGContextRef c = h.backing;
	CGContextSaveGState(c);
	if (!full) {
		CGContextBeginPath(c);
		for (size_t i = 0; i < count; i++)
			CGContextAddRect(c, STNRect(damage[i]));
		CGContextClip(c);
	}
	CGContextClearRect(c, CGRectMake(0, 0, width, height));
	return true;
}
void STNRasterFill(CGContextRef c, stn_rect r, stn_color color, double radius) {
	STNSetColor(c, color, NO);
	CGPathRef path = STNPath(r, radius);
	CGContextAddPath(c, path);
	CGContextFillPath(c);
	CGPathRelease(path);
}
void STNRasterStroke(CGContextRef c, stn_rect r, stn_color color, double width, double radius) {
	STNSetColor(c, color, YES);
	CGContextSetLineWidth(c, width);
	CGRect inset = CGRectInset(STNRect(r), width / 2, width / 2);
	if (inset.size.width < 0 || inset.size.height < 0)
		return;
	stn_rect inside = {inset.origin.x, inset.origin.y, inset.size.width, inset.size.height};
	CGPathRef path = STNPath(inside, MAX(0, radius - width / 2));
	CGContextAddPath(c, path);
	CGContextStrokePath(c);
	CGPathRelease(path);
}
void STNRasterText(CGContextRef c, stn_utf8 string, stn_rect rect, double size, double weight, stn_color color,
                   bool wraps) {
	CTFontRef font = STNCreateFont(size, weight);
	CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
	CGFloat rgba[] = {color.red, color.green, color.blue, color.alpha};
	CGColorRef cgColor = CGColorCreate(space, rgba);
	NSAttributedString *attributed =
	    [[NSAttributedString alloc] initWithString:STNUTF8(string)
	                                    attributes:@{
		                                    (__bridge NSString *)kCTFontAttributeName : (__bridge id)font,
		                                    (__bridge NSString *)kCTForegroundColorAttributeName : (__bridge id)cgColor
	                                    }];
	CGContextSaveGState(c);
	CGContextTranslateCTM(c, rect.x, rect.y + rect.height);
	CGContextScaleCTM(c, 1, -1);
	CGContextSetTextMatrix(c, CGAffineTransformIdentity);
	if (wraps && rect.width > 0 && rect.height > 0) {
		CTFramesetterRef setter = CTFramesetterCreateWithAttributedString((__bridge CFAttributedStringRef)attributed);
		CGPathRef path = CGPathCreateWithRect(CGRectMake(0, 0, rect.width, rect.height), NULL);
		CTFrameRef frame = CTFramesetterCreateFrame(setter, CFRangeMake(0, 0), path, NULL);
		CTFrameDraw(frame, c);
		CFRelease(frame);
		CGPathRelease(path);
		CFRelease(setter);
	} else {
		CTLineRef line = CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)attributed);
		CGContextSetTextPosition(c, 0, MAX(0, rect.height - CTFontGetAscent(font)));
		CTLineDraw(line, c);
		CFRelease(line);
	}
	CGContextRestoreGState(c);
	CGColorRelease(cgColor);
	CGColorSpaceRelease(space);
	CFRelease(font);
}
void stn_draw_fill(stn_window p, stn_rect r, stn_color c, double radius) {
	STNRasterFill(STNHost(p).backing, r, c, radius);
}
void stn_draw_stroke(stn_window p, stn_rect r, stn_color c, double width, double radius) {
	STNRasterStroke(STNHost(p).backing, r, c, width, radius);
}
void stn_draw_text(stn_window p, stn_utf8 text, stn_rect r, double size, double weight, stn_color c, bool wraps) {
	STNRasterText(STNHost(p).backing, text, r, size, weight, c, wraps);
}
static NSCache<NSData *, id> *imageCache;
static NSMutableSet<NSData *> *pendingImages;
static NSHashTable<STNWindowHost *> *imageObservers;
static id STNDecodeImage(NSData *data) {
	CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
	if (!source)
		return NSNull.null;
	NSDictionary *properties = (__bridge_transfer NSDictionary *)CGImageSourceCopyPropertiesAtIndex(source, 0, NULL);
	double width = [properties[(__bridge NSString *)kCGImagePropertyPixelWidth] doubleValue],
	       height = [properties[(__bridge NSString *)kCGImagePropertyPixelHeight] doubleValue];
	CGImageRef image = NULL;
	if (width > 0 && height > 0 && width * height <= 16777216)
		image = CGImageSourceCreateImageAtIndex(
		    source, 0,
		    (__bridge CFDictionaryRef)
		        @{(__bridge NSString *)kCGImageSourceShouldCacheImmediately : @YES});
	CFRelease(source);
	return image ? CFBridgingRelease(image) : NSNull.null;
}
void STNRasterImage(CGContextRef c, NSData *data, stn_rect rect) {
	static NSCache<NSData *, id> *cache;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		cache = [NSCache new];
		cache.totalCostLimit = 64 * 1024 * 1024;
		cache.countLimit = 128;
	});
	id image = [cache objectForKey:data];
	if (!image) {
		image = STNDecodeImage(data);
		NSUInteger cost = image == NSNull.null ? 1
		                                       : CGImageGetBytesPerRow((__bridge CGImageRef)image) *
		                                             CGImageGetHeight((__bridge CGImageRef)image);
		if (cost + data.length > 64 * 1024 * 1024)
			image = NSNull.null;
		else
			[cache setObject:image forKey:data cost:cost + data.length];
	}
	if (image == NSNull.null) {
		STNRasterFill(c, rect, (stn_color){0.8, 0.8, 0.82, 1}, 3);
		return;
	}
	CGContextSaveGState(c);
	CGContextTranslateCTM(c, rect.x, rect.y + rect.height);
	CGContextScaleCTM(c, 1, -1);
	CGContextDrawImage(c, CGRectMake(0, 0, rect.width, rect.height), (__bridge CGImageRef)image);
	CGContextRestoreGState(c);
}
void stn_draw_image(stn_window p, const uint8_t *bytes, size_t count, stn_rect rect) {
	if (!bytes || count > 32 * 1024 * 1024)
		return;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		imageCache = [NSCache new];
		imageCache.totalCostLimit = 64 * 1024 * 1024;
		imageCache.countLimit = 128;
		pendingImages = [NSMutableSet set];
		imageObservers = [NSHashTable weakObjectsHashTable];
	});
	[imageObservers addObject:STNHost(p)];
	NSData *lookup = [NSData dataWithBytesNoCopy:(void *)bytes length:count freeWhenDone:NO];
	id cached = [imageCache objectForKey:lookup];
	if (cached && cached != NSNull.null) {
		CGImageRef image = (__bridge CGImageRef)cached;
		CGContextRef c = STNHost(p).backing;
		CGContextSaveGState(c);
		CGContextTranslateCTM(c, rect.x, rect.y + rect.height);
		CGContextScaleCTM(c, 1, -1);
		CGContextDrawImage(c, CGRectMake(0, 0, rect.width, rect.height), image);
		CGContextRestoreGState(c);
		return;
	}
	// Deterministic placeholder while decoding, or on malformed input.
	stn_draw_fill(p, rect, (stn_color){0.8, 0.8, 0.82, 1}, 3);
	if (cached)
		return;
	@synchronized(pendingImages) {
		if (pendingImages.count >= 4 || [pendingImages containsObject:lookup])
			return;
		NSData *owned = [NSData dataWithBytes:bytes length:count];
		[pendingImages addObject:owned];
		dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
			@autoreleasepool {
				id decoded = STNDecodeImage(owned);
				NSUInteger cost = decoded == NSNull.null ? 1
				                                         : CGImageGetBytesPerRow((__bridge CGImageRef)decoded) *
				                                               CGImageGetHeight((__bridge CGImageRef)decoded);
				if (cost + owned.length > 64 * 1024 * 1024) {
					decoded = NSNull.null;
					cost = 1;
				}
				[imageCache setObject:decoded forKey:owned cost:cost + owned.length];
				@synchronized(pendingImages) {
					[pendingImages removeObject:owned];
				}
				dispatch_async(dispatch_get_main_queue(), ^{
					for (STNWindowHost *host in imageObservers.allObjects)
						[host emit:(stn_event){.kind = decoded == NSNull.null ? 13 : 12}];
				});
			}
		});
	}
}
void stn_draw_clip_push(stn_window p, stn_rect rect) {
	CGContextSaveGState(STNHost(p).backing);
	CGContextClipToRect(STNHost(p).backing, STNRect(rect));
}
void stn_draw_clip_pop(stn_window p) { CGContextRestoreGState(STNHost(p).backing); }
void stn_draw_transform_push(stn_window p, double a, double b, double c, double d, double tx, double ty) {
	CGContextRef context = STNHost(p).backing;
	CGContextSaveGState(context);
	CGContextConcatCTM(context, CGAffineTransformMake(a, b, c, d, tx, ty));
}
void stn_draw_rounded_clip_push(stn_window p, stn_rect rect, double radius) {
	CGContextRef c = STNHost(p).backing;
	CGContextSaveGState(c);
	CGPathRef path = STNPath(rect, radius);
	CGContextAddPath(c, path);
	CGContextClip(c);
	CGPathRelease(path);
}
void stn_draw_opacity_push(stn_window p, double opacity) {
	CGContextRef c = STNHost(p).backing;
	CGContextSaveGState(c);
	CGContextSetAlpha(c, opacity);
	CGContextBeginTransparencyLayer(c, NULL);
}
void stn_draw_opacity_pop(stn_window p) {
	CGContextRef c = STNHost(p).backing;
	CGContextEndTransparencyLayer(c);
	CGContextRestoreGState(c);
}
void stn_frame_end(stn_window p) { CGContextRestoreGState(STNHost(p).backing); }
uint64_t stn_window_pixel_hash(stn_window p) {
	if (STNHost(p).metal)
		return [STNHost(p).metal pixelHash];
	CGContextRef c = STNHost(p).backing;
	if (!c)
		return 0;
	const uint8_t *bytes = CGBitmapContextGetData(c);
	size_t count = CGBitmapContextGetBytesPerRow(c) * CGBitmapContextGetHeight(c);
	uint64_t hash = 1469598103934665603ULL;
	for (size_t i = 0; i < count; i++) {
		hash ^= bytes[i];
		hash *= 1099511628211ULL;
	}
	return hash;
}
bool stn_window_export_png(stn_window p, const char *path) {
	if (STNHost(p).metal)
		return [STNHost(p).metal exportTo:STNString(path) linear:NO];
	CGContextRef c = STNHost(p).backing;
	if (!c)
		return false;
	CGImageRef image = CGBitmapContextCreateImage(c);
	NSURL *url = [NSURL fileURLWithPath:STNString(path)];
	CGImageDestinationRef destination =
	    CGImageDestinationCreateWithURL((__bridge CFURLRef)url, CFSTR("public.png"), 1, NULL);
	if (!destination) {
		CGImageRelease(image);
		return false;
	}
	CGImageDestinationAddImage(destination, image, NULL);
	bool result = CGImageDestinationFinalize(destination);
	CFRelease(destination);
	CGImageRelease(image);
	return result;
}
