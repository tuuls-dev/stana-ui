import Foundation
import Testing

@testable import StanaText

@Suite @MainActor struct TextBufferTests {
	@Test func compositionPublishesOnceAndUndoesAsOneEdit() throws {
		let buffer = TextBuffer("Hello ")
		var changes: [String] = []
		buffer.onChange = { changes.append($0) }
		try buffer.setMarked("に", selected: .init(location: 1, length: 0), replacement: nil)
		try buffer.setMarked("日本", selected: .init(location: 2, length: 0), replacement: nil)
		#expect(changes.isEmpty)
		#expect(buffer.displayText == "Hello 日本")
		try buffer.commitComposition()
		#expect(changes == ["Hello 日本"])
		buffer.undo()
		#expect(buffer.text == "Hello ")
	}

	@Test func graphemeDeletionAndIndexRoundTrips() throws {
		let value = "a👩🏽‍💻e\u{301}"
		let buffer = TextBuffer(value)
		try buffer.delete(backward: true)
		#expect(buffer.text == "a👩🏽‍💻")
		try buffer.delete(backward: true)
		#expect(buffer.text == "a")
		for index in value.indices {
			let byte = value.utf8.distance(from: value.utf8.startIndex, to: index)
			let utf16 = try TextIndices.utf16(utf8: byte, in: value)
			#expect(try TextIndices.utf8(utf16: utf16, in: value) == byte)
		}
	}
}
