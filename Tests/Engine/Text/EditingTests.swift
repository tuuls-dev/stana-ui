import Foundation
import StanaPrimitives
import Testing

@testable import StanaText

@Suite @MainActor struct EditingTests {
	@Test func externalEchoPreservesButReplacementCancelsComposition() throws {
		let b = TextBuffer("A")
		try b.setMarked("に", selected: .init(location: 1, length: 0), replacement: nil)
		b.external("A")
		#expect(b.markedText == "に")
		b.external("Replacement")
		#expect(b.markedText == nil)
		#expect(b.undoCount == 0)
	}

	@Test func staleAndInvalidIndicesAreRejected() throws {
		let b = TextBuffer("👩🏽‍💻")
		#expect(throws: STNError.invalidTextRange) { try b.select(.init(location: 1, length: 0)) }
		let old = STNTextPosition(utf8Offset: 0, revision: b.revision)
		try b.replace(with: "!")
		#expect(throws: STNError.staleTextPosition) { try b.setSelection(.init(anchor: old, head: old)) }
	}

	@Test func selectionOnlyChangesDoNotChangeTextRevision() throws {
		let b = TextBuffer("Hello")
		let revision = UInt64(0)
		try b.select(.init(location: 1, length: 2))
		#expect(b.revision == revision)
		try b.replace(with: "i")
		#expect(b.text == "Hilo")
		b.undo()
		#expect(b.text == "Hello")
		b.redo()
		#expect(b.text == "Hilo")
	}

	@Test func cancelledCompositionDoesNotEnterModelOrUndo() throws {
		let b = TextBuffer("Test")
		try b.setMarked("字", selected: .init(location: 1, length: 0), replacement: nil)
		b.cancelComposition()
		#expect(b.text == "Test")
		#expect(b.undoCount == 0)
	}
}

@Suite @MainActor struct ExtendedEditingTests {
	@Test func adjacentTypingCoalescesUntilAnExplicitSelection() throws {
		let buffer = TextBuffer("")
		try buffer.replace(with: "a", group: .typing)
		try buffer.replace(with: "b", group: .typing)
		#expect(buffer.undoCount == 1)
		try buffer.select(.init(location: 1, length: 0))
		try buffer.replace(with: "!", group: .typing)
		buffer.undo()
		#expect(buffer.text == "ab")
		buffer.undo()
		#expect(buffer.text == "")
		buffer.redo()
		#expect(buffer.text == "ab")
	}

	@Test func deletionGroupsRestoreTheOriginalCaretAndNoOpsDoNotEnterUndo() throws {
		let buffer = TextBuffer("abc")
		try buffer.delete(backward: true)
		try buffer.delete(backward: true)
		#expect(buffer.undoCount == 1)
		buffer.undo()
		#expect(buffer.text == "abc")
		#expect(buffer.selection.location == 3)
		try buffer.select(.init(location: 0, length: 0))
		let count = buffer.undoCount
		try buffer.delete(backward: true)
		#expect(buffer.undoCount == count)
	}

	@Test func directionalSelectionsSurviveCrossingTheAnchor() throws {
		let buffer = TextBuffer("hello")
		try buffer.select(anchor: 3, head: 1)
		#expect(try buffer.currentSelection().anchor.utf8Offset == 3)
		buffer.move(1, extending: true)
		buffer.move(1, extending: true)
		buffer.move(1, extending: true)
		#expect(buffer.selection == .init(location: 3, length: 1))
		#expect(try buffer.currentSelection().head.utf8Offset == 4)
	}

	@Test func selectingInsideAGraphemeIsRejectedWithoutCancellingComposition() throws {
		let buffer = TextBuffer("e\u{301}")
		try buffer.setMarked("に", selected: .init(location: 1, length: 0), replacement: nil)
		#expect(throws: STNError.invalidTextRange) { try buffer.select(.init(location: 1, length: 0)) }
		#expect(buffer.markedText == "に")
	}

	@Test func wordAndLineDeletionUseCompleteUnicodeBoundaries() throws {
		let buffer = TextBuffer("hello, world 👩🏽‍💻")
		try buffer.delete(backward: true, word: true)
		#expect(buffer.text == "hello, world ")
		try buffer.delete(backward: true, word: true)
		#expect(buffer.text == "hello, ")
		try buffer.delete(backward: true, edge: true)
		#expect(buffer.text.isEmpty)
		buffer.undo()
		#expect(buffer.text == "hello, ")
	}
}

@Suite @MainActor struct ReplacementBoundaryTests {
	@Test func equalReplacementCollapsesSelectionWithoutCreatingUndo() throws {
		let buffer = TextBuffer("abc")
		try buffer.select(.init(location: 0, length: 3))
		try buffer.replace(with: "abc")
		#expect(buffer.selection == .init(location: 3, length: 0))
		#expect(buffer.undoCount == 0)
	}

	@Test func insertionThatJoinsAGraphemeLeavesAValidCaret() throws {
		let buffer = TextBuffer("\u{301}")
		try buffer.select(.init(location: 0, length: 0))
		try buffer.replace(with: "e")
		#expect(buffer.text == "e\u{301}")
		#expect(buffer.selection.location == 2)
		try buffer.delete(backward: true)
		#expect(buffer.text.isEmpty)
	}
}
