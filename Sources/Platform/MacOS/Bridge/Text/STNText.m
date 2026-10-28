#import "../STNPrivate.h"

CTFontRef STNCreateFont(double size, double weight) {
	CTFontRef base = CTFontCreateUIFontForLanguage(kCTFontUIFontSystem, size, NULL);
	NSDictionary *traits =
	    @{(__bridge NSString *)kCTFontTraitsAttribute : @{(__bridge NSString *)kCTFontWeightTrait : @(weight)}};
	CTFontDescriptorRef descriptor = CTFontDescriptorCreateWithAttributes((__bridge CFDictionaryRef)traits);
	CTFontRef result = CTFontCreateCopyWithAttributes(base, size, NULL, descriptor);
	CFRelease(base);
	CFRelease(descriptor);
	return result;
}
static NSAttributedString *STNAttributed(stn_utf8 text, double size, double weight) {
	CTFontRef font = STNCreateFont(size, weight);
	NSAttributedString *result =
	    [[NSAttributedString alloc] initWithString:STNUTF8(text)
	                                    attributes:@{(__bridge NSString *)kCTFontAttributeName : (__bridge id)font}];
	CFRelease(font);
	return result;
}
stn_text_metrics stn_text_measure(stn_utf8 text, double size, double weight, double maxWidth, bool wraps) {
	NSAttributedString *attributed = STNAttributed(text, size, weight);
	CTFontRef font = STNCreateFont(size, weight);
	double baseline = CTFontGetAscent(font), minimum = ceil(baseline + CTFontGetDescent(font) + CTFontGetLeading(font));
	CFRelease(font);
	if (wraps && isfinite(maxWidth) && maxWidth > 0) {
		CTFramesetterRef setter = CTFramesetterCreateWithAttributedString((__bridge CFAttributedStringRef)attributed);
		CGSize measured = CTFramesetterSuggestFrameSizeWithConstraints(setter, CFRangeMake(0, 0), NULL,
		                                                               CGSizeMake(maxWidth, CGFLOAT_MAX), NULL);
		CFRelease(setter);
		return (stn_text_metrics){ceil(measured.width), MAX(minimum, ceil(measured.height)), baseline};
	}
	CTLineRef line = CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)attributed);
	double width = CTLineGetTypographicBounds(line, NULL, NULL, NULL);
	CFRelease(line);
	return (stn_text_metrics){ceil(width), minimum, baseline};
}
double stn_text_offset(stn_utf8 text, double size, double weight, uint64_t index) {
	NSAttributedString *s = STNAttributed(text, size, weight);
	CTLineRef line = CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)s);
	double offset = CTLineGetOffsetForStringIndex(line, MIN(index, s.length), NULL);
	CFRelease(line);
	return offset;
}
void stn_text_offsets(stn_utf8 text, double size, double weight, double *offsets, size_t count) {
	NSAttributedString *s = STNAttributed(text, size, weight);
	CTLineRef line = CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)s);
	for (size_t i = 0; i < count; i++)
		offsets[i] = CTLineGetOffsetForStringIndex(line, MIN(i, s.length), NULL);
	CFRelease(line);
}
uint64_t stn_text_index(stn_utf8 text, double size, double weight, double x) {
	NSAttributedString *s = STNAttributed(text, size, weight);
	CTLineRef line = CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)s);
	CFIndex index = CTLineGetStringIndexForPosition(line, CGPointMake(x, 0));
	if (index == kCFNotFound) {
		double distance = DBL_MAX;
		for (NSUInteger i = 0; i <= s.length; i++) {
			double candidate = CTLineGetOffsetForStringIndex(line, i, NULL), d = fabs(x - candidate);
			if (d < distance) {
				distance = d;
				index = i;
			}
		}
	}
	CFRelease(line);
	return MAX(0, index);
}

// Selection geometry is split at shaped runs, so a logical selection through
// mixed-direction text does not highlight unrelated visual glyphs.
size_t stn_text_selection_rects(stn_utf8 text, double size, double weight, uint64_t start, uint64_t length,
                                stn_rect *rects, size_t capacity) {
	NSAttributedString *s = STNAttributed(text, size, weight);
	if (start > s.length || length > s.length - start || !length)
		return 0;
	CTLineRef line = CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)s);
	CFArrayRef runs = CTLineGetGlyphRuns(line);
	size_t count = 0;
	NSRange selection = NSMakeRange(start, length);
	for (CFIndex i = 0; i < CFArrayGetCount(runs); i++) {
		CTRunRef run = (CTRunRef)CFArrayGetValueAtIndex(runs, i);
		CFRange runRange = CTRunGetStringRange(run);
		NSRange intersection = NSIntersectionRange(selection, NSMakeRange(runRange.location, runRange.length));
		if (!intersection.length)
			continue;
		CFIndex glyphCount = CTRunGetGlyphCount(run);
		NSMutableIndexSet *boundaries = [NSMutableIndexSet indexSetWithIndex:runRange.location + runRange.length];
		CFIndex *indices = calloc(MAX(1, glyphCount), sizeof(CFIndex));
		CTRunGetStringIndices(run, CFRangeMake(0, glyphCount), indices);
		for (CFIndex glyph = 0; glyph < glyphCount; glyph++)
			[boundaries addIndex:indices[glyph]];
		double left = DBL_MAX, right = -DBL_MAX;
		for (CFIndex glyph = 0; glyph < glyphCount; glyph++) {
			CFIndex stringIndex = indices[glyph];
			CFIndex next = [boundaries indexGreaterThanIndex:stringIndex];
			if (!NSIntersectionRange(intersection, NSMakeRange(stringIndex, next - stringIndex)).length)
				continue;
			CGPoint point;
			CGSize advance;
			CTRunGetPositions(run, CFRangeMake(glyph, 1), &point);
			CTRunGetAdvances(run, CFRangeMake(glyph, 1), &advance);
			left = MIN(left, MIN(point.x, point.x + advance.width));
			right = MAX(right, MAX(point.x, point.x + advance.width));
		}
		free(indices);
		if (left <= right) {
			if (count < capacity)
				rects[count] = (stn_rect){left, 0, MAX(0, right - left), size * 1.3};
			count++;
		}
	}
	CFRelease(line);
	return count;
}
