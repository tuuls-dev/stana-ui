import CStanaMacOS
import Foundation
import Stana
import StanaAccessibility
import StanaCore
import StanaPrimitives
import Testing

@testable import StanaPlatformMacOS
@testable import StanaScene

extension NativeWindowServer {
	@Suite(.serialized)
	@MainActor struct NativeHostTests {
		@Test func externalAuthoringProducesACustomDrawnAccessibleWindow() async throws {
			let name = STNSignal("Alloys")
			let enabled = STNSignal(true)
			let window = STNWindow(properties: .init(title: "Stana verification", size: .init(width: 480, height: 340)))
			{
				STNVStack(properties: .init(spacing: 18, layout: .init(padding: STNInsets(24)))) {
					STNText(
						properties: .init(
							text: "Preferences",
							textStyle: .init(font: STNFont.system(size: 26, weight: .bold)),
							accessibility: .init(heading: 1)
						)
					)
					STNTextField(properties: .init(value: name.binding, accessibility: .init(label: "Display name")))
					STNToggle(properties: .init(text: "Notifications", isOn: enabled.binding))
					STNButton(properties: .init(text: "Save", onActivate: {}))
				}
			}
			try STNApplication.open(window)
			defer {
				window.close()
			}

			let session = try #require(window.session)
			session.draw()
			let native = try #require(session.window as? MacOSWindow)
			try await waitForNativeBacking(native)
			#expect(session.document.viewport.width > 0 && session.document.viewport.height > 0)
			#expect(session.errors.isEmpty)
			#expect(native.renderer.backingRevision > 0)
			#expect(stn_window_semantic_count(native.handle) == 4)
			#expect(stn_window_export_png(native.handle, "/tmp/stana-preferences-verification.png"))
			name.value = "Updated"
			session.draw()
			#expect(session.document.metrics.mountedNodes > 0)
		}

		@Test func retainedRasterMatchesFullRedrawAndPublishesNativeElements() throws {
			let window = try MacOSWindow(title: "Stana native verification", size: .init(width: 240, height: 160))
			defer {
				window.close()
			}

			window.editing(true)
			"s".withNativeUTF8 { #expect(!stn_window_test_key_equivalent(window.handle, $0)) }
			"c".withNativeUTF8 { #expect(stn_window_test_key_equivalent(window.handle, $0)) }
			window.editing(false)
			let renderer = CoreGraphicsRenderer(window: window)
			let full = STNRect(width: 240, height: 160)

			func scene(_ revision: UInt64, x: Double, damage: [STNRect], base: UInt64) -> SceneSnapshot {
				.init(
					documentRevision: revision,
					sceneRevision: revision,
					surfaceEpoch: renderer.surfaceEpoch,
					damageBaseRevision: base,
					damage: damage,
					commands: [
						.fill(full, .white, radius: 0),
						.fill(.init(x: x, y: 20, width: 40, height: 30), .accent.resolved(dark: false), radius: 5),
						.text(
							"Hello مرحبا",
							.init(x: 16, y: 80, width: 180, height: 30),
							.system(size: 16),
							.black,
							wraps: false
						),
					],
					size: full.size
				)
			}

			_ = try renderer.submit(scene(1, x: 10, damage: [full], base: 0))
			_ = try renderer.submit(scene(2, x: 80, damage: [.init(x: 10, y: 20, width: 110, height: 30)], base: 1))
			let incremental = stn_window_pixel_hash(window.handle)
			_ = try renderer.submit(scene(3, x: 80, damage: [full], base: 2))
			#expect(incremental != 0)
			#expect(incremental == stn_window_pixel_hash(window.handle))
			#expect(stn_window_export_png(window.handle, "/tmp/stana-native-verification.png"))
			let document = Document(size: full.size)
			STNTransaction.perform {
				let button = document.create(.button, parent: document.root)
				button.text = "Press"
				button.bounds = .init(x: 10, y: 10, width: 80, height: 30)
			}
			let snapshot = SemanticProjection(document: document).snapshot()
			window.accessibility.publish(snapshot)
			#expect(stn_window_semantic_count(window.handle) == 1)
			#expect(stn_window_semantic_revision(window.handle) == snapshot.revision)
			document.close()
		}
	}
}
