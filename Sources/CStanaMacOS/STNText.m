#import "STNPrivate.h"

CTFontRef STNCreateFont(double size, double weight) {
    CTFontRef base=CTFontCreateUIFontForLanguage(kCTFontUIFontSystem,size,NULL);
    NSDictionary *traits=@{(__bridge NSString *)kCTFontTraitsAttribute:@{(__bridge NSString *)kCTFontWeightTrait:@(weight)}};
    CTFontDescriptorRef descriptor=CTFontDescriptorCreateWithAttributes((__bridge CFDictionaryRef)traits);
    CTFontRef result=CTFontCreateCopyWithAttributes(base,size,NULL,descriptor); CFRelease(base); CFRelease(descriptor); return result;
}
static NSAttributedString *STNAttributed(stn_utf8 text, double size, double weight) {
    CTFontRef font=STNCreateFont(size,weight);
    NSAttributedString *result=[[NSAttributedString alloc] initWithString:STNUTF8(text) attributes:@{(__bridge NSString *)kCTFontAttributeName:(__bridge id)font}];
    CFRelease(font); return result;
}
stn_text_metrics stn_text_measure(stn_utf8 text, double size, double weight, double maxWidth, bool wraps) {
    NSAttributedString *attributed=STNAttributed(text,size,weight); CTFontRef font=STNCreateFont(size,weight);
    double baseline=CTFontGetAscent(font), minimum=ceil(baseline+CTFontGetDescent(font)+CTFontGetLeading(font)); CFRelease(font);
    if (wraps && isfinite(maxWidth) && maxWidth>0) {
        CTFramesetterRef setter=CTFramesetterCreateWithAttributedString((__bridge CFAttributedStringRef)attributed);
        CGSize measured=CTFramesetterSuggestFrameSizeWithConstraints(setter,CFRangeMake(0,0),NULL,CGSizeMake(maxWidth,CGFLOAT_MAX),NULL); CFRelease(setter);
        return (stn_text_metrics){ceil(measured.width),MAX(minimum,ceil(measured.height)),baseline};
    }
    CTLineRef line=CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)attributed);
    double width=CTLineGetTypographicBounds(line,NULL,NULL,NULL); CFRelease(line);
    return (stn_text_metrics){ceil(width),minimum,baseline};
}
double stn_text_offset(stn_utf8 text, double size, double weight, uint64_t index) {
    NSAttributedString *s=STNAttributed(text,size,weight); CTLineRef line=CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)s);
    double offset=CTLineGetOffsetForStringIndex(line,MIN(index,s.length),NULL); CFRelease(line); return offset;
}
void stn_text_offsets(stn_utf8 text, double size, double weight, double *offsets, size_t count) {
    NSAttributedString *s=STNAttributed(text,size,weight); CTLineRef line=CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)s);
    for (size_t i=0;i<count;i++) offsets[i]=CTLineGetOffsetForStringIndex(line,MIN(i,s.length),NULL);
    CFRelease(line);
}
uint64_t stn_text_index(stn_utf8 text, double size, double weight, double x) {
    NSAttributedString *s=STNAttributed(text,size,weight); CTLineRef line=CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)s);
    CFIndex index=CTLineGetStringIndexForPosition(line,CGPointMake(x,0)); CFRelease(line);
    return index==kCFNotFound ? s.length : MAX(0,index);
}
