import AppKit
import StanaPrimitives

struct NativeTextSnapshot: Sendable {
	let text: String
	let selection, marked: NSRange
	let bounds: CGRect
	let offsets: [Double]
	let revision: UInt64
	let secure: Bool
	let transform: STNAffineTransform
	let geometryMatches: Bool
	let geometryRevision: UInt64
	let fallbackRect: CGRect

	func rect(for range: NSRange) -> CGRect {
		guard geometryMatches else {
			return fallbackRect
		}

		guard !offsets.isEmpty else {
			return transform.enclosing(bounds.stana).cgRect
		}

		let start = min(range.location, offsets.count - 1)
		let end = min(
			range.length <= Int.max - range.location ? range.location + range.length : Int.max,
			offsets.count - 1
		)
		let x = offsets[start], y = offsets[end]
		return
			transform.enclosing(
				.init(x: bounds.minX + min(x, y), y: bounds.minY, width: max(1, abs(y - x)), height: bounds.height)
			)
			.cgRect
	}
}

extension MacOSWindow {
	package func editing(_ value: Bool) {
		guard !closed else {
			return
		}

		view.editing = value
		if value {
			nativeWindow.makeFirstResponder(view)
			view.inputContext?.activate()
		} else {
			view.inputContext?.deactivate()
			view.invalidateTextServices()
			view.textSnapshot = nil
			view.textIdentity = 0
		}
	}

	package func discardMarkedText() {
		view.inputContext?.discardMarkedText()
	}

	package func publishText(
		_ text: String,
		selection: NSRange,
		marked: NSRange,
		bounds: STNRect,
		offsets: [Double],
		revision: UInt64,
		secure: Bool,
		nodeID: UInt64? = nil,
		transform: STNAffineTransform = .identity,
		geometryMatches: Bool = true,
		geometryRevision: UInt64 = 0
	) {
		guard !closed else {
			return
		}

		let previous =
			nodeID.flatMap { id in pendingText[id] ?? semanticNodes.values.first { $0.node?.id.nativeID == id }?.text }
			?? view.textSnapshot
		let location = min(selection.location, text.utf16.count)
		let selection = NSRange(location: location, length: min(selection.length, text.utf16.count - location))
		let snapshot = NativeTextSnapshot(
			text: text,
			selection: selection,
			marked: marked,
			bounds: bounds.cgRect,
			offsets: offsets,
			revision: revision,
			secure: secure,
			transform: transform,
			geometryMatches: geometryMatches,
			geometryRevision: geometryRevision,
			fallbackRect: previous.map { $0.rect(for: $0.selection) } ?? .zero
		)
		if let nodeID {
			pendingText[nodeID] = snapshot
		} else {
			view.textSnapshot = snapshot
			view.inputContext?.invalidateCharacterCoordinates()
			view.refreshTextServices()
		}

		if !geometryMatches {
			graphics.requestFrame()
		}
	}
}

extension ContentView {
	func textRequest(
		_ kind: Int32,
		text: String = "",
		replacement: NSRange? = nil,
		selected: NSRange = NSRange(),
		revision: UInt64? = nil
	) {
		guard let host, !host.closed else {
			return
		}

		host.onText?(kind, text, replacement, selected, revision ?? textSnapshot?.revision ?? 0, textIdentity)
	}

	func insertText(_ string: Any, replacementRange: NSRange) {
		let text = (string as? NSAttributedString)?.string ?? string as? String ?? ""
		let range = replacementRange.location == NSNotFound ? nil : replacementRange
		let target = range ?? (hasMarkedText() ? markedRange() : selectedRange())
		let normalized = text.replacingOccurrences(of: "\r\n", with: " ").replacingOccurrences(of: "\n", with: " ")
			.replacingOccurrences(of: "\r", with: " ")
		textUserInsertion = true
		insertedRange = NSRange(location: target.location, length: normalized.utf16.count)
		textRequest(1, text: text, replacement: range)
	}

	func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
		let text = (string as? NSAttributedString)?.string ?? string as? String ?? ""
		textRequest(
			2,
			text: text,
			replacement: replacementRange.location == NSNotFound ? nil : replacementRange,
			selected: selectedRange
		)
	}

	func unmarkText() {
		if hasMarkedText() {
			textUserInsertion = true
			insertedRange = markedRange()
		}

		textRequest(3)
	}

	func hasMarkedText() -> Bool {
		textSnapshot?.marked.location != NSNotFound && textSnapshot != nil
	}

	func markedRange() -> NSRange {
		textSnapshot?.marked ?? NSRange(location: NSNotFound, length: 0)
	}

	func selectedRange() -> NSRange {
		textSnapshot?.selection ?? NSRange()
	}

	func validAttributesForMarkedText() -> [NSAttributedString.Key] {
		[]
	}

	func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
		guard let snapshot = textSnapshot, !snapshot.secure, range.location <= snapshot.text.utf16.count else {
			return nil
		}

		let valid = NSIntersectionRange(range, NSRange(location: 0, length: snapshot.text.utf16.count))
		actualRange?.pointee = valid
		return NSAttributedString(string: (snapshot.text as NSString).substring(with: valid))
	}

	func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
		actualRange?.pointee = range
		guard let window, let snapshot = textSnapshot else {
			return .zero
		}

		return window.convertToScreen(convert(snapshot.rect(for: range), to: nil))
	}

	func characterIndex(for point: NSPoint) -> Int {
		guard let window, let snapshot = textSnapshot else {
			return 0
		}

		guard snapshot.geometryMatches, let inverse = snapshot.transform.inverse else {
			return snapshot.selection.location
		}

		let local = convert(window.convertPoint(fromScreen: point), from: nil)
		let x = inverse.applying(to: .init(x: local.x, y: local.y)).x - snapshot.bounds.minX
		return snapshot.offsets.indices.min { abs(snapshot.offsets[$0] - x) < abs(snapshot.offsets[$1] - x) } ?? 0
	}

	override func doCommand(by selector: Selector) {
		if selector == #selector(complete(_:)) {
			complete(nil)
			return
		}

		textRequest(4, text: NSStringFromSelector(selector))
	}
}
