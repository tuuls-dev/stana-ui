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
