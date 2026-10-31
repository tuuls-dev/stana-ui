import AppKit
import Foundation
import StanaScene
import StanaCore
import StanaPrimitives
import Testing

@testable import Stana
@testable import StanaPlatformMacOS
@MakeSTNSymbol(mirrorsInRTL: true)
private struct NativeSymbolArrow {
	static let svg =
		"<svg viewBox='0 0 24 24' fill='none' stroke='currentColor' stroke-width='3' stroke-linecap='round'><path d='M-3 12H26M16 2L26 12L16 22'/></svg>"
}

extension NativeWindowServer {
	@Suite(.serialized) @MainActor struct SymbolNativeTests {
		@Test func explicitViewAndHostVisibilityIncludesAttachedSurfaces() throws {
			let window = try MacOSWindow(title: "Symbol visibility", size: .init(width: 120, height: 80))
			defer { window.close() }
			window.show()
			let surface = try MacOSWindow(title: "Surface", size: .init(width: 24, height: 24), parent: window)
			defer { surface.close() }
			var visible = false
			surface.onSymbolVisibility = { visible = $0 }
			window.view.addSubview(surface.view)
			surface.publishSymbolVisibility()
			#expect(visible)
			surface.view.isHidden = true
			#expect(!visible)
			surface.view.isHidden = false
			#expect(visible)
			// A mere occlusion notification must not pause a visible symbol host.
			NotificationCenter.default.post(
				name: NSWindow.didChangeOcclusionStateNotification,
				object: window.nativeWindow
			)
			#expect(visible)
			surface.view.removeFromSuperview()
			#expect(!visible)
		}

		@Test func workerMetalCapturePreservesLabelsAndClearsAnimatedOverflow() async throws {
			let environment = STNEnvironment()
			let color = STNSignal(STNColor.text)
			var errors: [STNSymbolDiagnostic] = []
			let window = STNWindow(
				properties: .init(
					title: "Symbol verification",
					size: .init(width: 260, height: 150),
					environment: environment
				)
			) {
				STNVStack(properties: .init(spacing: 12, layout: .init(padding: STNInsets(20)))) {
					STNSymbol(
						properties: .init(
							symbol: NativeSymbolArrow.asset,
							size: 40,
							color: color,
							accessibility: .init(label: "Forward"),
							onError: { errors.append($0) }
						)
					)
					STNText(properties: .init(text: "Retained vector symbol"))
				}
			}

			try STNApplication.open(window)
			defer { window.close() }

			let session = try #require(window.session)
			let native = try #require(session.window as? MacOSWindow)
			let node = try #require(session.document.orderedNodes.first { $0.kind == .symbol })
			let baseline = node.baseline
			session.draw()
			try await waitForNativeBacking(native, after: 0)
			native.onDraw = nil

			func capture(_ builder: SceneBuilder) async throws -> STNRenderedImage {
				let scene = builder.build(
					surfaceEpoch: native.renderer.surfaceEpoch,
					backingRevision: native.renderer.backingRevision
				)
				try await native.graphics.prepareOffscreenForTesting(scene, adoptDesired: true)
				return try await native.capture()
			}

			let first = try await capture(session.scene)
			let originalSemantics = try #require(session.semanticSnapshot.nodes.first { $0.role == .image })
			for direction in [STNLayoutDirection.leftToRight, .rightToLeft] {
				environment.layoutDirection.value = direction
				environment.isDark.value = true
				color.value = .accent
				node.symbol?.effect = .init(scale: 1.08, verticalFraction: -0.12)
				session.document.paintChanges[node.id] = .content
				session.document.dirty.insert(.paint)
				let moving = try await capture(session.scene)
				#expect(moving.data != first.data)
				node.symbol?.effect = .init()
				session.document.paintChanges[node.id] = .content
				session.document.dirty.insert(.paint)
				let incremental = try await capture(session.scene)
				let rebuilt = try await capture(SceneBuilder(document: session.document))
				#expect(incremental.data == rebuilt.data)
				#expect(node.baseline == baseline)
				let semantics = try #require(session.semanticSnapshot.nodes.first { $0.role == .image })
				#expect(semantics.label == originalSemantics.label && semantics.bounds == originalSemantics.bounds)
			}
			#expect(try await exportNativePNG(native, "/tmp/stana-symbols-native.png"))
			#expect(errors.isEmpty)
		}
	}
}
