import Foundation
import Stana
import StanaPrimitives
import Testing

@testable import StanaPlatformMacOS

extension NativeWindowServer {
	@Suite(.serialized)
	@MainActor struct DirectionalLayoutTests {
		@Test func asymmetricPaddingAndEditorGeometryAreCapturedInBothDirections() async throws {
			let environment = STNEnvironment()
			let value = STNSignal("Logical padding")
			var editor: STNTextFieldHandle?
			let padding = STNInsets(top: 10, leading: 10, bottom: 10, trailing: 50)
			let window = STNWindow(
				properties: .init(
					title: "Logical padding",
					size: .init(width: 480, height: 230),
					environment: environment
				)
			) {
				STNVStack(properties: .init(spacing: 16, layout: .init(padding: STNInsets(20)))) {
					STNText(properties: .init(text: "Leading 10 / trailing 50"))
					STNHStack(
						properties: .init(
							spacing: 8,
							layout: .init(padding: padding, frame: STNFrame(width: 420)),
							appearance: .init(background: STNColor.surface)
						)
					) {
						STNButton(properties: .init(text: "First", onActivate: {}))
						STNButton(properties: .init(text: "Second", onActivate: {}))
					}
					STNTextField(
						properties: .init(
							value: value.binding,
							layout: .init(padding: padding, frame: STNFrame(width: 420)),
							onEditorMount: { editor = $0 }
						)
					)
				}
			}
			try STNApplication.open(window)
			defer {
				window.close()
			}

			let session = try #require(window.session)
			let native = try #require(session.window as? MacOSWindow)
			try #require(editor).requestFocus()
			try #require(editor).selectAll()
			let measures = session.document.metrics.measureCalls
			for (direction, suffix) in [(STNLayoutDirection.leftToRight, "ltr"), (.rightToLeft, "rtl")] {
				environment.layoutDirection.value = direction
				let before = native.renderer.backingRevision
				session.draw()
				try await waitForNativeBacking(native, after: before)
				#expect(try await exportNativePNG(native, "/tmp/stana-logical-padding-\(suffix).png"))
				let row = try #require(session.document.orderedNodes.first { $0.kind == .hStack })
				let first = try #require(session.document.orderedNodes.first { $0.kind == .button })
				if direction == .leftToRight {
					#expect(first.bounds.minX == row.bounds.minX + 10)
				} else {
					#expect(first.bounds.maxX == row.bounds.maxX - 10)
				}

				#expect(session.document.metrics.measureCalls == measures)
				#expect(session.errors.isEmpty)
			}
		}
	}
}
