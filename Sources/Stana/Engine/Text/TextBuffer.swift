import Foundation
import StanaPrimitives

@MainActor package final class TextBuffer {
	struct State {
		let text: String
		let selection: NSRange
	}

	package private(set) var text: String
	package private(set) var revision: UInt64 = 0
	package private(set) var selection: NSRange
	private var selectionAnchor: Int?
	private var selectionHead: Int?
	package private(set) var markedText: String?
	package private(set) var markedSelection = NSRange(location: 0, length: 0)
	private var compositionRange: NSRange?
	private var undoStack: [State] = []
	private var redoStack: [State] = []
	package var onChange: ((String) -> Void)?
	package var onPresentationChange: (() -> Void)?
	package var isSecure = false
	package enum EditGroup { case typing, backwardDelete, forwardDelete }
	private var editGroup: EditGroup?
	package var canUndo: Bool { !undoStack.isEmpty }
	package var canRedo: Bool { !redoStack.isEmpty }
	package var wordRange: (String, Int) -> NSRange = TextBoundaries.wordRange

	package func breakUndoGroup() {
		editGroup = nil
	}

	package func currentSelection() throws -> STNTextSelection {
		let anchor = selectionAnchor ?? selection.location
		let head = selectionHead ?? NSMaxRange(selection)
		return try .init(
			anchor: .init(utf8Offset: TextIndices.utf8(utf16: anchor, in: text), revision: revision),
			head: .init(utf8Offset: TextIndices.utf8(utf16: head, in: text), revision: revision)
		)
	}

	package func select(anchor: Int, head: Int) throws {
		try applySelection(NSRange(location: min(anchor, head), length: abs(head - anchor)), anchor: anchor, head: head)
	}

	package var head: Int {
		selectionHead ?? NSMaxRange(selection)
	}

	package var anchor: Int {
		selectionAnchor ?? selection.location
	}
	package let maxUTF8Bytes = 1_048_576

	package init(_ text: String) {
		self.text = text
		selection = NSRange(location: text.utf16.count, length: 0)
	}

	package var displayText: String {
		guard let markedText, let range = compositionRange, let indices = try? TextIndices.range(utf16: range, in: text)
		else {
			return text
		}

		return text.replacingCharacters(in: indices, with: markedText)
	}

	package var markedRange: NSRange {
		guard let markedText, let range = compositionRange else {
			return NSRange(location: NSNotFound, length: 0)
		}

		return NSRange(location: range.location, length: markedText.utf16.count)
	}

	package var displaySelection: NSRange {
		if markedText != nil, let range = compositionRange {
			return NSRange(location: range.location + markedSelection.location, length: markedSelection.length)
		}

		return selection
	}

	package var undoCount: Int {
		undoStack.count
	}

	package func replace(_ range: NSRange? = nil, with replacement: String, group: EditGroup? = nil) throws {
		let target = range ?? compositionRange ?? selection
		let indices = try TextIndices.range(utf16: target, in: text)
		let normalized = replacement.replacingOccurrences(of: "\r\n", with: " ")
			.replacingOccurrences(
				of: "\n",
				with: " "
			)
			.replacingOccurrences(of: "\r", with: " ")
		let candidate = text.replacingCharacters(in: indices, with: normalized)
		guard candidate.utf8.count <= maxUTF8Bytes else {
			throw STNError.invalidTextRange
		}

		guard candidate != text else {
			selection = NSRange(
				location: TextBoundaries.ceiling(target.location + normalized.utf16.count, in: text),
				length: 0
			)
			selectionAnchor = nil
			selectionHead = nil
			breakUndoGroup()
			cancelComposition()
			return
		}

		if group == nil || group != editGroup {
			undoStack.append(.init(text: text, selection: selection))
		}

		editGroup = group
		if undoStack.count > 200 {
			undoStack.removeFirst()
		}

		redoStack.removeAll()
		text = candidate
		nextRevision(&revision)
		selection = NSRange(
			location: TextBoundaries.ceiling(target.location + normalized.utf16.count, in: text),
			length: 0
		)
		selectionAnchor = nil
		selectionHead = nil
		markedText = nil
		compositionRange = nil
		onChange?(text)
		onPresentationChange?()
	}

	package func setMarked(_ value: String, selected: NSRange, replacement: NSRange?) throws {
		breakUndoGroup()
		let target = compositionRange ?? replacement ?? selection
		_ = try TextIndices.range(utf16: target, in: text)
		_ = try TextIndices.range(utf16: selected, in: value)
		guard value.utf8.count + text.utf8.count <= maxUTF8Bytes else {
			throw STNError.invalidTextRange
		}

		if markedText != value || compositionRange != target {
			nextRevision(&revision)
		}

		compositionRange = target
		markedText = value
		markedSelection = selected
		onPresentationChange?()
	}

	package func cancelComposition() {
		if markedText != nil {
			nextRevision(&revision)
		}

		markedText = nil
		compositionRange = nil
		onPresentationChange?()
	}

	package func commitComposition() throws {
		guard let markedText else {
			return
		}

		try replace(compositionRange, with: markedText)
	}

	package func external(_ value: String) {
		guard value != text else {
			return
		}

		breakUndoGroup()
		cancelComposition()
		text = value
		nextRevision(&revision)
		undoStack.removeAll()
		redoStack.removeAll()
		let limit = min(selection.location, text.utf16.count)
		selection = NSRange(location: TextBoundaries.snap(limit, in: text), length: 0)
		selectionAnchor = nil
		selectionHead = nil
		if (try? TextIndices.range(utf16: selection, in: text)) == nil {
			selection.location = text.utf16.count
		}

		onPresentationChange?()
	}

	package func select(_ range: NSRange) throws {
		try applySelection(range, anchor: nil, head: nil)
	}

	private func applySelection(_ range: NSRange, anchor: Int?, head: Int?) throws {
		_ = try TextIndices.range(utf16: range, in: text)
		guard TextBoundaries.snap(range.location, in: text) == range.location,
			TextBoundaries.snap(NSMaxRange(range), in: text) == NSMaxRange(range)
		else {
			throw STNError.invalidTextRange
		}

		breakUndoGroup()
		if markedText != nil {
			nextRevision(&revision)
			markedText = nil
			compositionRange = nil
		}

		selection = range
		selectionAnchor = anchor
		selectionHead = head
		onPresentationChange?()
	}

	package func setSelection(_ value: STNTextSelection) throws {
		guard value.anchor.revision == revision, value.head.revision == revision else {
			throw STNError.staleTextPosition
		}

		let a = try TextIndices.utf16(utf8: value.anchor.utf8Offset, in: text)
		let b = try TextIndices.utf16(utf8: value.head.utf8Offset, in: text)
		try select(anchor: a, head: b)
	}

	package func undo() {
		breakUndoGroup()
		guard let previous = undoStack.popLast() else {
			return
		}

		selectionAnchor = nil
		selectionHead = nil
		cancelComposition()
		redoStack.append(.init(text: text, selection: selection))
		text = previous.text
		selection = previous.selection
		nextRevision(&revision)
		onChange?(text)
		onPresentationChange?()
	}

	package func redo() {
		breakUndoGroup()
		guard let next = redoStack.popLast() else {
			return
		}

		selectionAnchor = nil
		selectionHead = nil
		cancelComposition()
		undoStack.append(.init(text: text, selection: selection))
		text = next.text
		selection = next.selection
		nextRevision(&revision)
		onChange?(text)
		onPresentationChange?()
	}

	package func move(_ direction: Int, extending: Bool = false, word: Bool = false, edge: Bool = false) {
		breakUndoGroup()
		if markedText != nil {
			try? commitComposition()
		}

		if !extending && selection.length > 0 && !word && !edge {
			selection = NSRange(location: direction < 0 ? selection.location : NSMaxRange(selection), length: 0)
			selectionAnchor = nil
			selectionHead = nil
			onPresentationChange?()
			return
		}

		let utf16 =
			extending
			? (selectionHead ?? (direction < 0 ? selection.location : NSMaxRange(selection)))
			: (direction < 0 ? selection.location : NSMaxRange(selection))
		guard let indices = try? TextIndices.range(utf16: NSRange(location: utf16, length: 0), in: text) else {
			return
		}

		var target = indices.lowerBound
		if edge {
			target = direction < 0 ? text.startIndex : text.endIndex
		} else if direction < 0, target > text.startIndex {
			target = text.index(before: target)
			if word {
				while target > text.startIndex, text[target].isWhitespace {
					target = text.index(before: target)
				}

				let offset = text.utf16.distance(from: text.utf16.startIndex, to: target)
				let range = wordRange(text, offset)
				if let indices = try? TextIndices.range(utf16: range, in: text) {
					target = indices.lowerBound
				}
			}
		} else if direction > 0, target < text.endIndex {
			if word {
				let range = wordRange(text, utf16)
				if let indices = try? TextIndices.range(utf16: range, in: text), indices.upperBound > target {
					target = indices.upperBound
				} else {
					target = text.index(after: target)
				}

				while target < text.endIndex, text[target].isWhitespace {
					target = text.index(after: target)
				}
			} else {
				target = text.index(after: target)
			}
		}

		let offset = text.utf16.distance(from: text.utf16.startIndex, to: target)
		if extending {
			let anchor = selectionAnchor ?? (direction < 0 ? NSMaxRange(selection) : selection.location)
			selectionAnchor = anchor
			selectionHead = offset
			selection = NSRange(location: min(anchor, offset), length: abs(anchor - offset))
		} else {
			selection = NSRange(location: offset, length: 0)
			selectionAnchor = nil
			selectionHead = nil
		}

		onPresentationChange?()
	}

	package func delete(backward: Bool, word: Bool = false, edge: Bool = false) throws {
		if markedText != nil {
			try commitComposition()
		}

		if selection.length > 0 {
			try replace(with: "")
			return
		}

		let original = selection.location
		let previousGroup = editGroup
		move(backward ? -1 : 1, word: word, edge: edge)
		editGroup = previousGroup
		let next = selection.location
		selection = NSRange(location: original, length: 0)
		try replace(
			NSRange(location: min(original, next), length: abs(original - next)),
			with: "",
			group: word || edge ? nil : (backward ? .backwardDelete : .forwardDelete)
		)
	}
}
