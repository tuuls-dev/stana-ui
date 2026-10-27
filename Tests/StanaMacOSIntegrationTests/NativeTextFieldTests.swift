import CStanaMacOS
import Foundation
import Stana
import StanaPrimitives
import Testing

@testable import StanaPlatformMacOS

@Suite(.enabled(if: ProcessInfo.processInfo.environment["STANA_GUI_TESTS"] == "1"), .serialized)
@MainActor struct NativeTextFieldTests {
	@Test func nativeCheckingReplacementUsesBindingUndoAndRevisionGuards() throws {
		let value = STNSignal("hello")
		var editor: STNTextFieldHandle?
		let window = STNWindow(
			properties: .init(title: "Text service verification", size: .init(width: 480, height: 160))
		) {
			STNTextField(properties: .init(value: value.binding, onEditorMount: { editor = $0 }))
		}
		try STNApplication.open(window)
		defer { window.close() }
		let session = try #require(window.session)
		let native = try #require(session.window as? MacOSWindow)
		let field = try #require(editor)
		try field.requestFocus()
		let selection = try field.selection()
		let identity = field.id.nativeID
		"world"
			.withNativeUTF8 {
				#expect(stn_window_test_checked_replace(native.handle, $0, 0, 5, identity, selection.head.revision))
				#expect(!stn_window_test_checked_replace(native.handle, $0, 0, 5, identity, selection.head.revision))
			}
		#expect(value.value == "world")
		"undo:".withNativeUTF8 { #expect(stn_window_test_text_action(native.handle, $0, true)) }
		#expect(value.value == "hello")
	}

	@Test func nativeMenusRespectReadOnlyAndSecureState() throws {
		let value = STNSignal("selectable")
		let options = STNSignal(STNTextField.Options())
		var plain: STNTextFieldHandle?
		var secure: STNTextFieldHandle?
		let window = STNWindow(properties: .init(title: "Text menu verification", size: .init(width: 480, height: 180)))
		{
			STNVStack {
				STNTextField(properties: .init(value: value.binding, options: options, onEditorMount: { plain = $0 }))
				STNTextField(properties: .init(value: value.binding, secure: true, onEditorMount: { secure = $0 }))
			}
		}
		try STNApplication.open(window)
		defer { window.close() }
		let session = try #require(window.session)
		let native = try #require(session.window as? MacOSWindow)
		let field = try #require(plain)
		try field.requestFocus()
		try field.selectAll()
		"copy:".withNativeUTF8 { #expect(stn_window_test_text_action(native.handle, $0, false)) }
		"cut:".withNativeUTF8 { #expect(stn_window_test_text_action(native.handle, $0, false)) }
		options.value.isReadOnly = true
		"copy:".withNativeUTF8 { #expect(stn_window_test_text_action(native.handle, $0, false)) }
		"cut:".withNativeUTF8 { #expect(!stn_window_test_text_action(native.handle, $0, false)) }
		try #require(secure).requestFocus()
		try #require(secure).selectAll()
		"copy:".withNativeUTF8 { #expect(!stn_window_test_text_action(native.handle, $0, false)) }
		#expect(try #require(secure).resolution().features.allSatisfy { $0.availability == .inapplicable })
	}

	@Test func showcaseIsCapturedWithToolkitStylingAndNativeTextGeometry() throws {
		let value = STNSignal("Hello مرحبا 👩🏽‍💻")
		let window = STNWindow(properties: .init(title: "Text fields", size: .init(width: 500, height: 210))) {
			STNVStack(properties: .init(spacing: 20, padding: 24)) {
				STNTextField(
					properties: .init(
						value: value.binding,
						placeholder: "Text",
						frame: .init(width: 440),
						options: .init(borderColor: .accent, borderWidth: 2)
					)
				)
				STNTextField(
					properties: .init(
						value: value.binding,
						frame: .init(width: 440),
						options: .init(isReadOnly: true, alignment: .trailing)
					)
				)
			}
		}
		try STNApplication.open(window)
		defer { window.close() }
		let session = try #require(window.session)
		let native = try #require(session.window as? MacOSWindow)
		session.draw()
		#expect(stn_window_export_png(native.handle, "/tmp/stana-text-fields-verification.png"))
		#expect(session.errors.isEmpty)
	}
}
