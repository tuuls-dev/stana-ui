import Foundation
import Stana
import StanaTesting
import Testing

@Suite @MainActor struct TextFieldTests {
	@Test func capturedEdgeDraggingAutoscrollsAndCancellationStopsIt() throws {
		let value = STNSignal(String(repeating: "abcdefghij", count: 10))
		let host = STNTestHost()
		host.mount { STNTextField(properties: .init(value: value.binding, layout: .init(frame: STNFrame(width: 100)))) }
		defer { host.close() }
		let node = try #require(host.nodes.first { $0.kind == "textField" })
		host.pointerDown(at: .init(x: node.bounds.minX + 9, y: node.bounds.minY + 10))
		host.pointerMove(to: .init(x: node.bounds.maxX + 20, y: node.bounds.minY + 10))
		let before = try #require(host.editorState(node.id)).selection.length
		host.advanceEditorTime(by: 0.05)
		let after = try #require(host.editorState(node.id)).selection.length
		#expect(after > before)
		host.cancelPointer()
		host.advanceEditorTime(by: 0.05)
		#expect(host.editorState(node.id)?.selection.length == after)
	}

	@Test func secureVisualArrowsDoNotStopInsideMaskedGraphemes() throws {
		let value = STNSignal("a👩🏽‍💻b")
		let host = STNTestHost()
		host.mount { STNTextField(properties: .init(value: value.binding, secure: true)) }
		defer { host.close() }
		let node = try #require(host.nodes.first { $0.kind == "textField" })
		try host.focus(node.id)
		host.command("moveLeft:")
		#expect(host.editorState(node.id)?.selection.location == value.value.utf16.count - 1)
		host.command("moveLeft:")
		#expect(host.editorState(node.id)?.selection.location == 1)
	}

	@Test func pointerSelectionSupportsDragShiftClickAndMultipleClicks() throws {
		let value = STNSignal("hello world")
		let host = STNTestHost()
		host.mount {
			STNTextField(
				properties: .init(
					value: value.binding,
					layout: .init(frame: STNFrame(width: 200)),
					textStyle: .init(font: STNFont.system(size: 15))
				)
			)
		}
		defer { host.close() }
		let node = try #require(host.nodes.first { $0.kind == "textField" })
		let y = node.bounds.minY + 10
		let unit = 15.0 * 0.6
		func point(_ index: Int) -> STNPoint { .init(x: node.bounds.minX + 8 + Double(index) * unit, y: y) }
		host.pointerDown(at: point(1))
		host.pointerMove(to: point(4))
		host.pointerUp(at: point(4))
		#expect(host.editorState(node.id)?.selection == NSRange(location: 1, length: 3))
		host.click(at: point(7), shift: true)
		#expect(host.editorState(node.id)?.selection == NSRange(location: 1, length: 6))
		host.click(at: point(8), clickCount: 2)
		#expect(host.editorState(node.id)?.selection == NSRange(location: 6, length: 5))
		host.click(at: point(8), clickCount: 3)
		#expect(host.editorState(node.id)?.selection == NSRange(location: 0, length: 11))
	}

	@Test func preventedPointerDefaultsDoNotSelectOrFocus() throws {
		let value = STNSignal("hello")
		let host = STNTestHost()
		host.mount {
			STNBox(properties: .init(interaction: .init(onPointerDownCapture: { $0.preventDefault() }))) {
				STNTextField(properties: .init(value: value.binding))
			}
		}
		defer { host.close() }
		let node = try #require(host.nodes.first { $0.kind == "textField" })
		host.click(at: .init(x: node.bounds.minX + 9, y: node.bounds.minY + 9))
		#expect(host.editorState(node.id)?.selection.location == 5)
		#expect(host.nodes.first { $0.id == node.id }?.isFocused == false)
	}

	@Test func readOnlyRejectsMutationsButSupportsSelectionAndExternalValues() throws {
		let value = STNSignal("original")
		let options = STNSignal(STNTextField.Options())
		let host = STNTestHost()
		var handle: STNTextFieldHandle?
		var changes: [String] = []
		host.mount {
			STNTextField(
				properties: .init(
					value: value.binding,
					options: options,
					onEditorMount: { handle = $0 },
					onChange: { changes.append($0) }
				)
			)
		}
		defer { host.close() }
		let editor = try #require(handle)
		try editor.requestFocus()
		host.insertText("!")
		let mounts = host.metrics.totalMounts
		options.value.isReadOnly = true
		try editor.selectAll()
		for command in [
			"deleteBackward:", "deleteForward:", "deleteWordBackward:", "deleteToEndOfLine:", "cut:", "paste:", "undo:",
			"redo:",
		] {
			host.command(command)
		}
		host.insertText("blocked")
		host.setMarkedText("に", selectedRange: .init(location: 1, length: 0))
		#expect(value.value == "original!")
		#expect(host.editorState(editor.id)?.markedText == nil)
		#expect(host.semantics.nodes.first { $0.owner == editor.id }?.isReadOnly == true)
		value.value = "external"
		#expect(host.editorState(editor.id)?.text == "external")
		#expect(changes == ["original!"])
		#expect(host.metrics.totalMounts == mounts)
		options.value.isReadOnly = false
		host.insertText(" works")
		#expect(value.value.contains("works"))
	}

	@Test func handlesAndCallbacksUseCommittedRevisionedState() throws {
		let value = STNSignal("A")
		let shown = STNSignal(true)
		let host = STNTestHost()
		var handle: STNTextFieldHandle?
		var changes: [String] = []
		var focuses: [Bool] = []
		var selections: [STNTextSelection] = []
		host.mount {
			STNIf(shown) {
				STNTextField(
					properties: .init(
						value: value.binding,
						onEditorMount: { handle = $0 },
						onChange: { text in
							#expect(host.nodes.first { $0.kind == "textField" }?.text == text)
							changes.append(text)
						},
						onFocusChange: { focuses.append($0) },
						onSelectionChange: { selections.append($0) }
					)
				)
			}
		}
		defer { host.close() }
		let editor = try #require(handle)
		let original = try editor.selection()
		try editor.requestFocus()
		try editor.requestFocus()
		host.setMarkedText("日本", selectedRange: .init(location: 2, length: 0))
		#expect(changes.isEmpty)
		host.commitMarkedText()
		#expect(changes == ["A日本"])
		#expect(throws: STNError.staleTextPosition) { try editor.setSelection(original) }
		let current = try editor.selection()
		try editor.setSelection(
			.init(anchor: current.head, head: .init(utf8Offset: 0, revision: current.head.revision))
		)
		#expect(try editor.selection().anchor == current.head)
		#expect(selections.last?.head.utf8Offset == 0)
		try editor.resignFocus()
		#expect(focuses == [true, false])
		shown.value = false
		#expect(throws: STNError.nodeDisposed) { try editor.selection() }
		#expect(throws: STNError.nodeDisposed) { try editor.resolution() }
	}

	@Test func reactiveOptionsPreserveCompositionUndoAndIdentity() throws {
		let value = STNSignal("A")
		let options = STNSignal(STNTextField.Options())
		let enabled = STNSignal(true)
		let host = STNTestHost()
		host.mount {
			STNTextField(
				properties: .init(value: value.binding, options: options, interaction: .init(isEnabled: enabled))
			)
		}
		defer { host.close() }
		let node = try #require(host.nodes.first { $0.kind == "textField" })
		try host.focus(node.id)
		host.insertText("!")
		host.setMarkedText("に", selectedRange: .init(location: 1, length: 0))
		let before = host.editorState(node.id)
		options.value.placeholderColor = .black
		options.value.alignment = .trailing
		#expect(host.editorState(node.id) == before)
		options.value.isReadOnly = true
		#expect(host.editorState(node.id)?.markedText == nil)
		#expect(value.value == "A!")
		#expect(host.editorState(node.id)?.undoCount == 1)
	}

	@Test func headlessResolutionDoesNotPretendNativeServicesAreAvailable() throws {
		let value = STNSignal("")
		let host = STNTestHost()
		var handle: STNTextFieldHandle?
		host.mount {
			STNTextField(
				properties: .init(
					value: value.binding,
					options: STNTextField.Options(textServices: .init(spelling: .enabled)),
					onEditorMount: { handle = $0 }
				)
			)
		}
		defer { host.close() }
		let resolution = try #require(handle).resolution()
		#expect(resolution.features.count == 8)
		#expect(resolution.features.allSatisfy { $0.availability == .unavailable && $0.isEnabled == nil })
	}

	@Test func caretClockInvalidatesPaintAndStopsForReadOnlyFields() throws {
		let value = STNSignal("")
		let options = STNSignal(STNTextField.Options())
		let host = STNTestHost()
		host.mount { STNTextField(properties: .init(value: value.binding, options: options)) }
		defer { host.close() }
		let node = try #require(host.nodes.first { $0.kind == "textField" })
		try host.focus(node.id)
		let visible = try #require(host.render())
		host.advanceEditorTime(by: 0.51)
		let hidden = try #require(host.render())
		#expect(hidden.commandCount == visible.commandCount - 1)
		host.insertText("a")
		_ = host.render()
		options.value.isReadOnly = true
		_ = host.render()
		host.advanceEditorTime(by: 2)
		#expect(!host.needsDisplay)
	}
}
