import AppKit
import Foundation

@MainActor enum NativeTextServices {
	static func enabled(_ feature: Int, policy: Int32) -> Bool {
		if policy != 0 {
			return policy == 2
		}

		switch feature {
		case 0: return (UserDefaults.standard.object(forKey: "NSContinuousSpellCheckingEnabled") as? Bool) ?? true
		case 1: return UserDefaults.standard.bool(forKey: "NSGrammarCheckingEnabled")
		case 2: return NSSpellChecker.isAutomaticSpellingCorrectionEnabled
		case 3: return NSSpellChecker.isAutomaticQuoteSubstitutionEnabled
		case 4: return NSSpellChecker.isAutomaticDashSubstitutionEnabled
		case 5: return NSSpellChecker.isAutomaticTextReplacementEnabled
		case 6: return NSSpellChecker.isAutomaticTextCompletionEnabled
		case 7: return true
		default: return false
		}
	}
}

extension MacOSWindow {
	package var caretInterval: Double { caretPeriod(off: false) }

	package var caretOffInterval: Double { caretPeriod(off: true) }

	private func caretPeriod(off: Bool) -> Double {
		(UserDefaults.standard.object(
			forKey: off ? "NSTextInsertionPointBlinkPeriodOff" : "NSTextInsertionPointBlinkPeriodOn"
		) as? NSNumber)
		.map { max(0, $0.doubleValue / 1_000) } ?? 0.5
	}

	package func textServiceEnabled(_ feature: Int, policies: [Int32]) -> Bool {
		NativeTextServices.enabled(feature, policy: feature < policies.count ? policies[feature] : 0)
	}

	package func configureText(identity: UInt64, readOnly: Bool, canUndo: Bool, canRedo: Bool, policies: [Int32]) {
		guard !closed else {
			return
		}

		if view.textIdentity != identity || view.textReadOnly != readOnly || view.textPolicies != policies {
			view.invalidateTextServices()
		}

		view.textIdentity = identity
		view.textReadOnly = readOnly
		view.textCanUndo = canUndo
		view.textCanRedo = canRedo
		view.textPolicies = policies
	}
}

@MainActor
final class TextCheckingSession: NSObject, @MainActor NSTextCheckingClient, @MainActor NSTextInputClient,
	@MainActor NSTextInputTraits
{
	weak var view: ContentView?
	let identity: UInt64
	let revision: UInt64
	var invalid = false
	var lastSelection: NSRange
	var lastAnnotations: [[Int]] = []
	let annotations: NSMutableAttributedString
	var controller: NSTextCheckingController!

	init(view: ContentView, snapshot: NativeTextSnapshot) {
		self.view = view
		identity = view.textIdentity
		revision = snapshot.revision
		lastSelection = snapshot.selection
		annotations = NSMutableAttributedString(string: snapshot.text)
		super.init()
		controller = NSTextCheckingController(client: self)
	}

	var isCurrent: Bool {
		!invalid && view?.textIdentity == identity && view?.textSnapshot?.revision == revision
			&& view?.textReadOnly == false && view?.textSnapshot?.secure == false
			&& view?.textSnapshot?.marked.location == NSNotFound
	}

	func adjust(_ range: NSRange) -> NSRange {
		if range.location == NSNotFound {
			return NSRange(location: 0, length: annotations.length)
		}

		if range.location > annotations.length {
			return NSRange(location: NSNotFound, length: 0)
		}

		return NSRange(location: range.location, length: min(range.length, annotations.length - range.location))
	}

	func annotatedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
		guard isCurrent, adjust(range).location != NSNotFound else {
			return nil
		}

		let paragraph = NSRange(location: 0, length: annotations.length)
		actualRange?.pointee = paragraph
		return annotations.attributedSubstring(from: paragraph)
	}

	func setAnnotations(_ attributes: [NSAttributedString.Key: String], range: NSRange) {
		let range = adjust(range)
		guard isCurrent, range.location != NSNotFound else {
			return
		}

		annotations.setAttributes(attributes, range: range)
		publishAnnotations()
	}

	func addAnnotations(_ attributes: [NSAttributedString.Key: String], range: NSRange) {
		let range = adjust(range)
		guard isCurrent, range.location != NSNotFound else {
			return
		}

		annotations.addAttributes(attributes, range: range)
		publishAnnotations()
	}

	func removeAnnotation(_ annotationName: NSAttributedString.Key, range: NSRange) {
		let range = adjust(range)
		guard isCurrent, range.location != NSNotFound else {
			return
		}

		annotations.removeAttribute(annotationName, range: range)
		publishAnnotations()
	}

	func publishAnnotations() {
		Task { @MainActor [weak self] in
			guard let self, self.isCurrent else {
				return
			}

			var ranges: [[Int]] = []
			self.annotations.enumerateAttribute(
				.spellingState,
				in: NSRange(location: 0, length: self.annotations.length)
			) { value, range, _ in
				if (value as? NSNumber)?.intValue != 0, value != nil {
					ranges.append([range.location, range.length])
				}
			}
			guard ranges != self.lastAnnotations, let data = try? JSONEncoder().encode(ranges) else {
				return
			}

			self.lastAnnotations = ranges
			self.view?.textRequest(7, text: String(decoding: data, as: UTF8.self), revision: self.revision)
		}
	}

	func replaceCharacters(in range: NSRange, withAnnotatedString string: NSAttributedString) {
		let range = adjust(range)
		guard isCurrent, range.location != NSNotFound else {
			return
		}

		view?.textRequest(1, text: string.string, replacement: range, revision: revision)
	}

	func selectAndShow(_ range: NSRange) {
		let range = adjust(range)
		guard isCurrent, range.location != NSNotFound else {
			return
		}

		view?.textRequest(5, replacement: range, selected: range, revision: revision)
	}

	func view(for range: NSRange, firstRect: NSRectPointer?, actualRange: NSRangePointer?) -> NSView? {
		let range = adjust(range)
		guard isCurrent, range.location != NSNotFound else {
			return nil
		}

		actualRange?.pointee = range
		firstRect?.pointee = view?.textSnapshot?.rect(for: range) ?? .zero
		return view
	}

	func candidateListTouchBarItem() -> NSCandidateListTouchBarItem<AnyObject>? {
		nil
	}

	func insertText(_ string: Any, replacementRange: NSRange) {
		if isCurrent {
			view?.insertText(string, replacementRange: replacementRange)
		}
	}

	func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
		if isCurrent {
			view?.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
		}
	}

	func unmarkText() {
		if isCurrent {
			view?.unmarkText()
		}
	}

	func hasMarkedText() -> Bool {
		isCurrent && view?.hasMarkedText() == true
	}

	func markedRange() -> NSRange {
		isCurrent
			? view?.markedRange() ?? NSRange(location: NSNotFound, length: 0) : NSRange(location: NSNotFound, length: 0)
	}

	func selectedRange() -> NSRange {
		isCurrent ? view?.selectedRange() ?? NSRange() : NSRange()
	}

	func validAttributesForMarkedText() -> [NSAttributedString.Key] {
		[]
	}

	func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
		annotatedSubstring(forProposedRange: range, actualRange: actualRange)
	}

	func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
		isCurrent ? view?.firstRect(forCharacterRange: range, actualRange: actualRange) ?? .zero : .zero
	}

	func characterIndex(for point: NSPoint) -> Int {
		isCurrent ? view?.characterIndex(for: point) ?? NSNotFound : NSNotFound
	}

	func doCommand(by selector: Selector) {
		if isCurrent {
			view?.doCommand(by: selector)
		}
	}

	func trait(_ index: Int) -> NSTextInputTraitType {
		let policies = view?.textPolicies ?? []
		return NativeTextServices.enabled(index, policy: index < policies.count ? policies[index] : 0) ? .yes : .no
	}

	func setTrait(_ trait: NSTextInputTraitType, index: Int) {
		guard isCurrent else {
			return
		}

		let policy = trait == .default ? 0 : trait == .yes ? 2 : 1
		view?.textRequest(8, text: "[\(index),\(policy)]", revision: revision)
	}

	var spellCheckingType: NSTextInputTraitType {
		get {
			trait(0)
		}
		set {
			setTrait(newValue, index: 0)
		}
	}

	var grammarCheckingType: NSTextInputTraitType {
		get {
			trait(1)
		}
		set {
			setTrait(newValue, index: 1)
		}
	}

	var autocorrectionType: NSTextInputTraitType {
		get {
			trait(2)
		}
		set {
			setTrait(newValue, index: 2)
		}
	}

	var smartQuotesType: NSTextInputTraitType {
		get {
			trait(3)
		}
		set {
			setTrait(newValue, index: 3)
		}
	}

	var smartDashesType: NSTextInputTraitType {
		get {
			trait(4)
		}
		set {
			setTrait(newValue, index: 4)
		}
	}

	var textReplacementType: NSTextInputTraitType {
		get {
			trait(5)
		}
		set {
			setTrait(newValue, index: 5)
		}
	}

	var textCompletionType: NSTextInputTraitType {
		get {
			trait(6)
		}
		set {
			setTrait(newValue, index: 6)
		}
	}

	var inlinePredictionType: NSTextInputTraitType {
		get {
			.no
		}
		set {}
	}

	var dataDetectionType: NSTextInputTraitType {
		get {
			.no
		}
		set {}
	}

	var linkDetectionType: NSTextInputTraitType {
		get {
			.no
		}
		set {}
	}

	var smartInsertDeleteType: NSTextInputTraitType {
		get {
			.no
		}
		set {}
	}
}

extension ContentView {
	func invalidateTextServices() {
		checkingSession?.invalid = true
		checkingSession?.controller.invalidate()
		checkingSession = nil
		NSSpellChecker.shared.dismissCorrectionIndicator(for: self)
	}

	func refreshTextServices() {
		let userInsertion = textUserInsertion, inserted = insertedRange
		textUserInsertion = false
		guard let snapshot = textSnapshot, !textReadOnly, !snapshot.secure, snapshot.marked.location == NSNotFound
		else {
			invalidateTextServices()
			return
		}

		if let session = checkingSession, session.isCurrent {
			if session.lastSelection != snapshot.selection {
				session.lastSelection = snapshot.selection
				session.controller.didChangeSelectedRange()
			}

			return
		}

		invalidateTextServices()
		let session = TextCheckingSession(view: self, snapshot: snapshot)
		checkingSession = session
		Task { @MainActor [weak session] in
			guard let session, session.isCurrent else {
				return
			}

			let range = NSRange(location: 0, length: session.annotations.length)
			session.controller.didChangeText(in: range)
			if userInsertion {
				session.controller.insertedText(in: session.adjust(inserted))
				session.controller.considerTextChecking(for: range)
			} else {
				var types: NSTextCheckingTypes = 0
				if session.spellCheckingType == .yes {
					types |= NSTextCheckingResult.CheckingType.spelling.rawValue
				}

				if session.grammarCheckingType == .yes {
					types |= NSTextCheckingResult.CheckingType.grammar.rawValue
				}

				if types != 0 {
					session.controller.checkText(in: range, types: types, options: [:])
				}
			}
		}
	}

	@objc func copy(_ sender: Any?) {
		doCommand(by: #selector(copy(_:)))
	}

	@objc func cut(_ sender: Any?) {
		doCommand(by: #selector(cut(_:)))
	}

	@objc func paste(_ sender: Any?) {
		doCommand(by: #selector(paste(_:)))
	}

	@objc override func selectAll(_ sender: Any?) {
		doCommand(by: #selector(selectAll(_:)))
	}

	@objc func undo(_ sender: Any?) {
		doCommand(by: #selector(undo(_:)))
	}

	@objc func redo(_ sender: Any?) {
		doCommand(by: #selector(redo(_:)))
	}

	func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
		guard editing, let snapshot = textSnapshot else {
			return false
		}

		let selected = snapshot.selection.length > 0, writable = !textReadOnly
		switch menuItem.action {
		case #selector(copy(_:)): return selected && !snapshot.secure
		case #selector(cut(_:)): return selected && writable && !snapshot.secure
		case #selector(paste(_:)):
			return writable
				&& NSPasteboard.general.canReadItem(withDataConformingToTypes: [
					NSPasteboard.PasteboardType.string.rawValue
				])
		case #selector(undo(_:)): return writable && textCanUndo
		case #selector(redo(_:)): return writable && textCanRedo
		case #selector(complete(_:)):
			return writable && !snapshot.secure
				&& NativeTextServices.enabled(6, policy: textPolicies.count > 6 ? textPolicies[6] : 0)
		case #selector(selectAll(_:)): return !snapshot.text.isEmpty
		default: return writable && !snapshot.secure
		}
	}

	override func menu(for event: NSEvent) -> NSMenu? {
		guard editing, let snapshot = textSnapshot else {
			return nil
		}

		let menu = NSMenu(title: "Text")
		if let window, let session = checkingSession {
			let screen = window.convertPoint(toScreen: event.locationInWindow)
			let index = characterIndex(for: screen)
			var range = NSRange()
			if let checking = session.controller.menu(
				at: index,
				clickedOnSelection: NSLocationInRange(index, snapshot.selection),
				effectiveRange: &range
			) {
				for item in checking.items {
					if let copy = item.copy() as? NSMenuItem {
						menu.addItem(copy)
					}
				}
			}
		}

		for (title, action) in [
			("Undo", #selector(undo(_:))), ("Redo", #selector(redo(_:))), ("Cut", #selector(cut(_:))),
			("Copy", #selector(copy(_:))), ("Paste", #selector(paste(_:))), ("Select All", #selector(selectAll(_:))),
			("Complete", #selector(complete(_:))),
		] {
			let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
			item.target = self
			menu.addItem(item)
		}

		if let session = checkingSession, session.isCurrent {
			for (title, selector) in [
				("Spelling and Grammar…", "showGuessPanel:"), ("Substitutions…", "orderFrontSubstitutionsPanel:"),
			] {
				let item = NSMenuItem(title: title, action: NSSelectorFromString(selector), keyEquivalent: "")
				item.target = session.controller
				menu.addItem(item)
			}
		}

		if !snapshot.secure {
			let item = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")

			item.submenu = NSMenu(title: "Services")
			menu.addItem(item)
		}

		return menu
	}

	@objc override func complete(_ sender: Any?) {
		guard let session = checkingSession, session.isCurrent, let snapshot = textSnapshot,
			NativeTextServices.enabled(6, policy: textPolicies.count > 6 ? textPolicies[6] : 0)
		else {
			return
		}

		let text = snapshot.text as NSString
		let end = snapshot.selection.location
		var start = end
		while start > 0,
			!CharacterSet.whitespacesAndNewlines.contains(UnicodeScalar(text.character(at: start - 1)) ?? " ")
		{
			start -= 1
		}

		let range = NSRange(location: start, length: end - start)
		guard
			let words = NSSpellChecker.shared.completions(
				forPartialWordRange: range,
				in: snapshot.text,
				language: nil,
				inSpellDocumentWithTag: session.controller.spellCheckerDocumentTag
			), let first = words.first
		else {
			return
		}

		NSSpellChecker.shared.showCorrectionIndicator(
			of: .guesses,
			primaryString: first,
			alternativeStrings: Array(words.dropFirst()),
			forStringIn: snapshot.rect(for: range),
			view: self
		) { [weak session] accepted in
			Task { @MainActor in
				guard let accepted, let session, session.isCurrent else {
					return
				}

				session.replaceCharacters(in: range, withAnnotatedString: NSAttributedString(string: accepted))
			}
		}
	}

	override func validRequestor(
		forSendType sendType: NSPasteboard.PasteboardType?,
		returnType: NSPasteboard.PasteboardType?
	) -> Any? {
		if editing, let snapshot = textSnapshot, !snapshot.secure, (sendType == nil || sendType == .string),
			(returnType == nil || (!textReadOnly && returnType == .string)), snapshot.selection.length > 0
		{
			serviceIdentity = textIdentity
			serviceRevision = snapshot.revision
			serviceSelection = snapshot.selection
			return self
		}

		return super.validRequestor(forSendType: sendType, returnType: returnType)
	}

	func writeSelection(to pasteboard: NSPasteboard, types: [NSPasteboard.PasteboardType]) -> Bool {
		guard editing, let snapshot = textSnapshot, !snapshot.secure, types.contains(.string),
			snapshot.selection.length > 0
		else {
			return false
		}

		serviceIdentity = textIdentity
		serviceRevision = snapshot.revision
		serviceSelection = snapshot.selection
		pasteboard.declareTypes([.string], owner: nil)
		return pasteboard.setString((snapshot.text as NSString).substring(with: snapshot.selection), forType: .string)
	}

	func readSelection(from pasteboard: NSPasteboard) -> Bool {
		guard let value = pasteboard.string(forType: .string), let snapshot = textSnapshot, !textReadOnly,
			!snapshot.secure,
			serviceIdentity == textIdentity, serviceRevision == snapshot.revision,
			serviceSelection == snapshot.selection
		else {
			return false
		}

		textRequest(1, text: value, replacement: snapshot.selection, revision: serviceRevision)
		return true
	}
}
