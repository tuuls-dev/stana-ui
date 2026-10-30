import Foundation
import Stana
import StanaPrimitives
import Testing

@testable import StanaPlatformMacOS

extension NativeWindowServer {
	@Suite(.serialized)
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
				.withNativeString {
					#expect(nativeCheckedReplace(native, $0, 0, 5, identity, selection.head.revision))
					#expect(
						!nativeCheckedReplace(native, $0, 0, 5, identity, selection.head.revision)
					)
				}
			#expect(value.value == "world")
			"undo:".withNativeString { #expect(nativeTextAction(native, $0, true)) }
			#expect(value.value == "hello")
		}

		@Test func nativeMenusRespectReadOnlyAndSecureState() throws {
			let value = STNSignal("selectable")
			let options = STNSignal(STNTextField.Options())
			var plain: STNTextFieldHandle?
			var secure: STNTextFieldHandle?
			let window = STNWindow(
				properties: .init(title: "Text menu verification", size: .init(width: 480, height: 180))
			) {
				STNVStack {
					STNTextField(
						properties: .init(value: value.binding, options: options, onEditorMount: { plain = $0 })
					)
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
			"copy:".withNativeString { #expect(nativeTextAction(native, $0, false)) }
			"cut:".withNativeString { #expect(nativeTextAction(native, $0, false)) }
			options.value.isReadOnly = true
			"copy:".withNativeString { #expect(nativeTextAction(native, $0, false)) }
			"cut:".withNativeString { #expect(!nativeTextAction(native, $0, false)) }
			try #require(secure).requestFocus()
			try #require(secure).selectAll()
			"copy:".withNativeString { #expect(!nativeTextAction(native, $0, false)) }
			#expect(try #require(secure).resolution().features.allSatisfy { $0.availability == .inapplicable })
		}

		@Test func showcaseIsCapturedWithToolkitStylingAndNativeTextGeometry() async throws {
			let value = STNSignal("Hello مرحبا 👩🏽‍💻")
			let window = STNWindow(properties: .init(title: "Text fields", size: .init(width: 500, height: 210))) {
				STNVStack(properties: .init(spacing: 20, layout: .init(padding: STNInsets(24)))) {
					STNTextField(
						properties: .init(
							value: value.binding,
							placeholder: "Text",
							options: STNTextField.Options(),
							layout: .init(frame: STNFrame(width: 440)),
							appearance: .init(borderColor: STNColor.accent, borderWidth: 2)
						)
					)
					STNTextField(
						properties: .init(
							value: value.binding,
							options: STNTextField.Options(isReadOnly: true, alignment: .trailing),
							layout: .init(frame: STNFrame(width: 440))
						)
					)
				}
			}
			try STNApplication.open(window)
			defer { window.close() }
			let session = try #require(window.session)
			let native = try #require(session.window as? MacOSWindow)
			session.draw()
			try await waitForNativeBacking(native)
			#expect(try await exportNativePNG(native, "/tmp/stana-text-fields-verification.png"))
			#expect(session.errors.isEmpty)
		}
	}
}
