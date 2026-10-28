#import "STNPrivate.h"

bool stn_text_service_enabled(int32_t feature, int32_t policy) {
	if (policy)
		return policy == 2;
	switch (feature) {
	case 0: {
		id value = [NSUserDefaults.standardUserDefaults objectForKey:@"NSContinuousSpellCheckingEnabled"];
		return value ? [value boolValue] : YES;
	}
	case 1:
		return [NSUserDefaults.standardUserDefaults boolForKey:@"NSGrammarCheckingEnabled"];
	case 2:
		return NSSpellChecker.automaticSpellingCorrectionEnabled;
	case 3:
		return NSSpellChecker.automaticQuoteSubstitutionEnabled;
	case 4:
		return NSSpellChecker.automaticDashSubstitutionEnabled;
	case 5:
		return NSSpellChecker.automaticTextReplacementEnabled;
	case 6:
		return NSSpellChecker.automaticTextCompletionEnabled;
	case 7:
		return true;
	default:
		return false;
	}
}
double stn_caret_interval(bool off) {
	id value = [NSUserDefaults.standardUserDefaults
	    objectForKey:off ? @"NSTextInsertionPointBlinkPeriodOff" : @"NSTextInsertionPointBlinkPeriodOn"];
	return value ? MAX(0, [value doubleValue] / 1000.0) : 0.5;
}

// A checking client belongs to one immutable editor identity/revision. Replacing
// it invalidates pending work before a different editor or value is published.
@interface STNTextCheckingSession : NSObject <NSTextCheckingClient>
@property(nonatomic, weak) STNContentView *view;
@property(nonatomic) uint64_t identity, revision;
@property(nonatomic) BOOL invalid;
@property(nonatomic) NSRange lastSelection;
@property(nonatomic, copy) NSData *lastAnnotations;
@property(nonatomic, strong) NSMutableAttributedString *annotations;
@property(nonatomic, strong) NSTextCheckingController *controller;
- (BOOL)isCurrent;
- (NSRange)adjust:(NSRange)range;
- (void)publishAnnotations;
@end

@implementation STNTextCheckingSession
- (BOOL)isCurrent {
	STNContentView *v = self.view;
	return !self.invalid && v && v.textIdentity == self.identity && v.textSnapshot.revision == self.revision &&
	       !v.textReadOnly && !v.textSnapshot.secure && v.textSnapshot.marked.location == NSNotFound;
}
- (NSRange)adjust:(NSRange)range {
	NSUInteger length = self.annotations.length;
	if (range.location == NSNotFound)
		return NSMakeRange(0, length);
	if (range.location > length)
		return NSMakeRange(NSNotFound, 0);
	return NSMakeRange(range.location, MIN(range.length, length - range.location));
}
- (NSAttributedString *)annotatedSubstringForProposedRange:(NSRange)range actualRange:(NSRangePointer)actual {
	if (![self isCurrent])
		return nil;
	range = [self adjust:range];
	if (range.location == NSNotFound)
		return nil;
	range = NSMakeRange(0, self.annotations.length); // A field is one paragraph.
	if (actual)
		*actual = range;
	return [self.annotations attributedSubstringFromRange:range];
}
- (void)setAnnotations:(NSDictionary<NSAttributedStringKey, NSString *> *)attributes range:(NSRange)range {
	range = [self adjust:range];
	if (![self isCurrent] || range.location == NSNotFound)
		return;
	[self.annotations setAttributes:attributes range:range];
	[self publishAnnotations];
}
- (void)addAnnotations:(NSDictionary<NSAttributedStringKey, NSString *> *)attributes range:(NSRange)range {
	range = [self adjust:range];
	if (![self isCurrent] || range.location == NSNotFound)
		return;
	[self.annotations addAttributes:attributes range:range];
	[self publishAnnotations];
}
- (void)removeAnnotation:(NSAttributedStringKey)name range:(NSRange)range {
	range = [self adjust:range];
	if (![self isCurrent] || range.location == NSNotFound)
		return;
	[self.annotations removeAttribute:name range:range];
	[self publishAnnotations];
}
- (void)publishAnnotations {
	dispatch_async(dispatch_get_main_queue(), ^{
		if (![self isCurrent])
			return;
		NSMutableArray *ranges = [NSMutableArray array];
		[self.annotations enumerateAttribute:NSSpellingStateAttributeName
		                             inRange:NSMakeRange(0, self.annotations.length)
		                             options:0
		                          usingBlock:^(id value, NSRange range, BOOL *stop) {
			                          if ([value integerValue])
				                          [ranges addObject:@[ @(range.location), @(range.length) ]];
		                          }];
		NSData *data = [NSJSONSerialization dataWithJSONObject:ranges options:0 error:nil];
		if ([data isEqual:self.lastAnnotations])
			return;
		self.lastAnnotations = data;
		NSString *json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
		[self.view.host textRequest:7
		                       text:json
		                replacement:NSMakeRange(NSNotFound, 0)
		                   selected:NSMakeRange(0, 0)
		                   revision:self.revision];
	});
}
- (void)replaceCharactersInRange:(NSRange)range withAnnotatedString:(NSAttributedString *)string {
	range = [self adjust:range];
	if (![self isCurrent] || range.location == NSNotFound)
		return;
	[self.view.host textRequest:1
	                       text:string.string
	                replacement:range
	                   selected:NSMakeRange(0, 0)
	                   revision:self.revision];
}
- (void)selectAndShowRange:(NSRange)range {
	range = [self adjust:range];
	if (![self isCurrent] || range.location == NSNotFound)
		return;
	[self.view.host textRequest:5 text:@"" replacement:range selected:range revision:self.revision];
}
- (NSView *)viewForRange:(NSRange)range firstRect:(NSRectPointer)rect actualRange:(NSRangePointer)actual {
	range = [self adjust:range];
	if (![self isCurrent] || range.location == NSNotFound)
		return nil;
	if (actual)
		*actual = range;
	if (rect)
		*rect = STNTextRangeRect(self.view.textSnapshot, range);
	return self.view;
}
- (NSCandidateListTouchBarItem *)candidateListTouchBarItem {
	return nil;
}
- (void)insertText:(id)value replacementRange:(NSRange)range {
	if ([self isCurrent])
		[self.view insertText:value replacementRange:range];
}
- (void)setMarkedText:(id)value selectedRange:(NSRange)selected replacementRange:(NSRange)range {
	if ([self isCurrent])
		[self.view setMarkedText:value selectedRange:selected replacementRange:range];
}
- (void)unmarkText {
	if ([self isCurrent])
		[self.view unmarkText];
}
- (BOOL)hasMarkedText {
	return [self isCurrent] && self.view.hasMarkedText;
}
- (NSRange)markedRange {
	return [self isCurrent] ? self.view.markedRange : NSMakeRange(NSNotFound, 0);
}
- (NSRange)selectedRange {
	return [self isCurrent] ? self.view.selectedRange : NSMakeRange(NSNotFound, 0);
}
- (NSArray<NSAttributedStringKey> *)validAttributesForMarkedText {
	return @[];
}
- (NSAttributedString *)attributedSubstringForProposedRange:(NSRange)range actualRange:(NSRangePointer)actual {
	return [self annotatedSubstringForProposedRange:range actualRange:actual];
}
- (NSRect)firstRectForCharacterRange:(NSRange)range actualRange:(NSRangePointer)actual {
	return [self isCurrent] ? [self.view firstRectForCharacterRange:range actualRange:actual] : NSZeroRect;
}
- (NSUInteger)characterIndexForPoint:(NSPoint)point {
	return [self isCurrent] ? [self.view characterIndexForPoint:point] : NSNotFound;
}
- (void)doCommandBySelector:(SEL)selector {
	if ([self isCurrent])
		[self.view doCommandBySelector:selector];
}
- (NSTextInputTraitType)trait:(NSUInteger)index {
	int32_t policy = index < self.view.textPolicies.count ? self.view.textPolicies[index].intValue : 0;
	return stn_text_service_enabled((int32_t)index, policy) ? NSTextInputTraitTypeYes : NSTextInputTraitTypeNo;
}
- (void)setTrait:(NSTextInputTraitType)value index:(NSUInteger)index {
	if (![self isCurrent])
		return;
	int32_t policy = value == NSTextInputTraitTypeDefault ? 0 : value == NSTextInputTraitTypeYes ? 2 : 1;
	NSString *json = [NSString stringWithFormat:@"[%lu,%d]", (unsigned long)index, policy];
	[self.view.host textRequest:8
	                       text:json
	                replacement:NSMakeRange(NSNotFound, 0)
	                   selected:NSMakeRange(0, 0)
	                   revision:self.revision];
}
- (void)setSpellCheckingType:(NSTextInputTraitType)value {
	[self setTrait:value index:0];
}
- (void)setGrammarCheckingType:(NSTextInputTraitType)value {
	[self setTrait:value index:1];
}
- (void)setAutocorrectionType:(NSTextInputTraitType)value {
	[self setTrait:value index:2];
}
- (void)setSmartQuotesType:(NSTextInputTraitType)value {
	[self setTrait:value index:3];
}
- (void)setSmartDashesType:(NSTextInputTraitType)value {
	[self setTrait:value index:4];
}
- (void)setTextReplacementType:(NSTextInputTraitType)value {
	[self setTrait:value index:5];
}
- (void)setTextCompletionType:(NSTextInputTraitType)value {
	[self setTrait:value index:6];
}
- (NSTextInputTraitType)spellCheckingType {
	return [self trait:0];
}
- (NSTextInputTraitType)grammarCheckingType {
	return [self trait:1];
}
- (NSTextInputTraitType)autocorrectionType {
	return [self trait:2];
}
- (NSTextInputTraitType)smartQuotesType {
	return [self trait:3];
}
- (NSTextInputTraitType)smartDashesType {
	return [self trait:4];
}
- (NSTextInputTraitType)textReplacementType {
	return [self trait:5];
}
- (NSTextInputTraitType)textCompletionType {
	return [self trait:6];
}
- (NSTextInputTraitType)inlinePredictionType {
	return NSTextInputTraitTypeNo;
}
- (NSTextInputTraitType)dataDetectionType {
	return NSTextInputTraitTypeNo;
}
- (NSTextInputTraitType)linkDetectionType {
	return NSTextInputTraitTypeNo;
}
- (NSTextInputTraitType)smartInsertDeleteType {
	return NSTextInputTraitTypeNo;
}
@end

void stn_window_text_options(stn_window window, uint64_t identity, bool readOnly, bool undo, bool redo,
                             const int32_t *policies, size_t count) {
	STNContentView *view = STNHost(window).view;
	NSMutableArray *values = [NSMutableArray array];
	for (size_t i = 0; i < count; i++)
		[values addObject:@(policies[i])];
	if (view.textIdentity != identity || view.textReadOnly != readOnly || ![view.textPolicies isEqual:values])
		[view invalidateTextServices];
	view.textIdentity = identity;
	view.textReadOnly = readOnly;
	view.textCanUndo = undo;
	view.textCanRedo = redo;
	view.textPolicies = values;
}

@implementation STNContentView (TextServices)
- (void)invalidateTextServices {
	self.checkingSession.invalid = YES;
	[self.checkingSession.controller invalidate];
	self.checkingSession = nil;
	[NSSpellChecker.sharedSpellChecker dismissCorrectionIndicatorForView:self];
}
- (void)refreshTextServices {
	BOOL userInsertion = self.textUserInsertion;
	NSRange inserted = self.insertedRange;
	self.textUserInsertion = NO;
	if (self.textReadOnly || self.textSnapshot.secure || self.textSnapshot.marked.location != NSNotFound) {
		[self invalidateTextServices];
		return;
	}
	if (self.checkingSession && [self.checkingSession isCurrent]) {
		if (!NSEqualRanges(self.checkingSession.lastSelection, self.textSnapshot.selection)) {
			self.checkingSession.lastSelection = self.textSnapshot.selection;
			[self.checkingSession.controller didChangeSelectedRange];
		}
		return;
	}
	[self invalidateTextServices];
	STNTextCheckingSession *session = [STNTextCheckingSession new];
	session.lastSelection = self.textSnapshot.selection;
	session.view = self;
	session.identity = self.textIdentity;
	session.revision = self.textSnapshot.revision;
	session.annotations = [[NSMutableAttributedString alloc] initWithString:self.textSnapshot.text];
	session.controller = [[NSTextCheckingController alloc] initWithClient:session];
	self.checkingSession = session;
	// Run outside publication: checking can synchronously propose another edit.
	dispatch_async(dispatch_get_main_queue(), ^{
		if (![session isCurrent])
			return;
		[session.controller didChangeTextInRange:NSMakeRange(0, session.annotations.length)];
		if (userInsertion) {
			[session.controller insertedTextInRange:[session adjust:inserted]];
			[session.controller considerTextCheckingForRange:NSMakeRange(0, session.annotations.length)];
		} else {
			NSTextCheckingTypes types = 0;
			if ([session spellCheckingType] == NSTextInputTraitTypeYes)
				types |= NSTextCheckingTypeSpelling;
			if ([session grammarCheckingType] == NSTextInputTraitTypeYes)
				types |= NSTextCheckingTypeGrammar;
			if (types)
				[session.controller checkTextInRange:NSMakeRange(0, session.annotations.length)
				                               types:types
				                             options:@{}];
		}
	});
}
- (void)copy:(id)sender {
	[self doCommandBySelector:_cmd];
}
- (void)cut:(id)sender {
	[self doCommandBySelector:_cmd];
}
- (void)paste:(id)sender {
	[self doCommandBySelector:_cmd];
}
- (void)selectAll:(id)sender {
	[self doCommandBySelector:_cmd];
}
- (void)undo:(id)sender {
	[self doCommandBySelector:_cmd];
}
- (void)redo:(id)sender {
	[self doCommandBySelector:_cmd];
}
- (BOOL)validateMenuItem:(NSMenuItem *)item {
	if (!self.editing || !self.textSnapshot)
		return NO;
	SEL action = item.action;
	BOOL selected = self.textSnapshot.selection.length > 0, writable = !self.textReadOnly;
	if (action == @selector(copy:))
		return selected && !self.textSnapshot.secure;
	if (action == @selector(cut:))
		return writable && selected && !self.textSnapshot.secure;
	if (action == @selector(paste:))
		return writable &&
		       [NSPasteboard.generalPasteboard canReadItemWithDataConformingToTypes:@[ NSPasteboardTypeString ]];
	if (action == @selector(undo:))
		return writable && self.textCanUndo;
	if (action == @selector(redo:))
		return writable && self.textCanRedo;
	if (action == @selector(complete:))
		return writable && !self.textSnapshot.secure &&
		       stn_text_service_enabled(6, self.textPolicies.count > 6 ? self.textPolicies[6].intValue : 0);
	if (action == @selector(selectAll:))
		return self.textSnapshot.text.length > 0;
	return writable && !self.textSnapshot.secure;
}
- (NSMenu *)menuForEvent:(NSEvent *)event {
	if (!self.editing || !self.textSnapshot)
		return nil;
	NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Text"];
	NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
	NSPoint screen = [self.window convertPointToScreen:[self convertPoint:point toView:nil]];
	NSUInteger index = [self characterIndexForPoint:screen];
	NSRange effective;
	NSMenu *checking =
	    [self.checkingSession.controller menuAtIndex:index
	                              clickedOnSelection:NSLocationInRange(index, self.textSnapshot.selection)
	                                  effectiveRange:&effective];
	for (NSMenuItem *item in checking.itemArray)
		[menu addItem:[item copy]];
	NSArray *titles = @[ @"Undo", @"Redo", @"Cut", @"Copy", @"Paste", @"Select All", @"Complete" ];
	NSArray *actions = @[ @"undo:", @"redo:", @"cut:", @"copy:", @"paste:", @"selectAll:", @"complete:" ];
	for (NSUInteger i = 0; i < titles.count; i++) {
		NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:titles[i]
		                                              action:NSSelectorFromString(actions[i])
		                                       keyEquivalent:@""];
		item.target = self;
		[menu addItem:item];
	}
	if ([self.checkingSession isCurrent]) {
		NSMenuItem *spelling = [[NSMenuItem alloc] initWithTitle:@"Spelling and Grammar…"
		                                                  action:@selector(showGuessPanel:)
		                                           keyEquivalent:@""];
		spelling.target = self.checkingSession.controller;
		[menu addItem:spelling];
		NSMenuItem *substitutions = [[NSMenuItem alloc] initWithTitle:@"Substitutions…"
		                                                       action:@selector(orderFrontSubstitutionsPanel:)
		                                                keyEquivalent:@""];
		substitutions.target = self.checkingSession.controller;
		[menu addItem:substitutions];
	}
	if (!self.textSnapshot.secure) {
		NSMenuItem *services = [[NSMenuItem alloc] initWithTitle:@"Services" action:nil keyEquivalent:@""];
		services.submenu = [[NSMenu alloc] initWithTitle:@"Services"];
		[menu addItem:services];
	}
	return menu;
}
- (void)complete:(id)sender {
	STNTextCheckingSession *session = self.checkingSession;
	if (![session isCurrent] || !stn_text_service_enabled(6, self.textPolicies[6].intValue))
		return;
	NSString *text = self.textSnapshot.text;
	NSUInteger end = self.textSnapshot.selection.location, start = end;
	while (start > 0 &&
	       ![NSCharacterSet.whitespaceAndNewlineCharacterSet characterIsMember:[text characterAtIndex:start - 1]])
		start--;
	NSRange range = NSMakeRange(start, end - start);
	NSArray *words =
	    [NSSpellChecker.sharedSpellChecker completionsForPartialWordRange:range
	                                                             inString:text
	                                                             language:nil
	                                               inSpellDocumentWithTag:session.controller.spellCheckerDocumentTag];
	if (!words.count)
		return;
	[NSSpellChecker.sharedSpellChecker
	    showCorrectionIndicatorOfType:NSCorrectionIndicatorTypeGuesses
	                    primaryString:words.firstObject
	               alternativeStrings:words.count > 1 ? [words subarrayWithRange:NSMakeRange(1, words.count - 1)] : @[]
	                  forStringInRect:STNTextRangeRect(self.textSnapshot, range)
	                             view:self
	                completionHandler:^(NSString *accepted) {
		                if (accepted && [session isCurrent])
			                [session replaceCharactersInRange:range
			                              withAnnotatedString:[[NSAttributedString alloc] initWithString:accepted]];
	                }];
}
- (id)validRequestorForSendType:(NSPasteboardType)sendType returnType:(NSPasteboardType)returnType {
	if (self.editing && !self.textSnapshot.secure && (!sendType || [sendType isEqual:NSPasteboardTypeString]) &&
	    (!returnType || (!self.textReadOnly && [returnType isEqual:NSPasteboardTypeString])) &&
	    self.textSnapshot.selection.length) {
		self.serviceIdentity = self.textIdentity;
		self.serviceRevision = self.textSnapshot.revision;
		self.serviceSelection = self.textSnapshot.selection;
		return self;
	}
	return [super validRequestorForSendType:sendType returnType:returnType];
}
- (BOOL)writeSelectionToPasteboard:(NSPasteboard *)pasteboard types:(NSArray<NSPasteboardType> *)types {
	STNTextSnapshot *snapshot = self.textSnapshot;
	if (!self.editing || snapshot.secure || ![types containsObject:NSPasteboardTypeString] ||
	    !snapshot.selection.length)
		return NO;
	self.serviceIdentity = self.textIdentity;
	self.serviceRevision = snapshot.revision;
	self.serviceSelection = snapshot.selection;
	[pasteboard declareTypes:@[ NSPasteboardTypeString ] owner:nil];
	return [pasteboard setString:[snapshot.text substringWithRange:snapshot.selection] forType:NSPasteboardTypeString];
}
- (BOOL)readSelectionFromPasteboard:(NSPasteboard *)pasteboard {
	NSString *value = [pasteboard stringForType:NSPasteboardTypeString];
	if (!value || self.textReadOnly || self.textSnapshot.secure || self.serviceIdentity != self.textIdentity ||
	    self.serviceRevision != self.textSnapshot.revision ||
	    !NSEqualRanges(self.serviceSelection, self.textSnapshot.selection))
		return NO;
	[self.host textRequest:1
	                  text:value
	           replacement:self.textSnapshot.selection
	              selected:NSMakeRange(0, 0)
	              revision:self.serviceRevision];
	return YES;
}
@end

// Test-only entry points exercise the same native responder and checking paths.
bool stn_window_test_text_action(stn_window window, stn_utf8 name, bool perform) {
	STNContentView *view = STNHost(window).view;
	SEL selector = NSSelectorFromString(STNUTF8(name));
	NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"Test" action:selector keyEquivalent:@""];
	if (![view validateMenuItem:item])
		return false;
	if (perform)
		[NSApp sendAction:selector to:view from:nil];
	return true;
}
bool stn_window_test_checked_replace(stn_window window, stn_utf8 text, uint64_t location, uint64_t length,
                                     uint64_t identity, uint64_t revision) {
	STNTextCheckingSession *session = STNHost(window).view.checkingSession;
	if (![session isCurrent] || session.identity != identity || session.revision != revision)
		return false;
	[session replaceCharactersInRange:NSMakeRange(location, length)
	              withAnnotatedString:[[NSAttributedString alloc] initWithString:STNUTF8(text)]];
	return true;
}
