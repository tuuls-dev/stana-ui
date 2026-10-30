#if DEBUG
	import AppKit
	import Foundation
	import Stana
	import StanaCore
	import StanaPrimitives

	@testable import StanaPlatformMacOS

	@main struct NativeInputProbeApp {
		@MainActor static func main() throws {
			try NativeInputProbe.run()
		}
	}

	struct NativeProbeFailure: Error {
		let message: String
	}

	@MainActor enum NativeInputProbe {
		static func run() throws {
			let parent = STNWindow(
				properties: .init(title: "Stana input qualification", size: .init(width: 400, height: 320))
			) {
				STNText(properties: .init(text: "Parent"))
			}
			var failure: (any Error)?
			Task { @MainActor in
				do {
					try await exercise(parent)
				} catch {
					failure = error
					log("Input qualification failed: \(error)")
				}

				STNApplication.stop()
			}
			STNApplication.run(windows: [parent])
			if let failure {
				throw failure
			}
		}

		private static func log(_ message: String) {
			FileHandle.standardOutput.write(Data((message + "\n").utf8))
		}

		private static func require(_ condition: Bool, _ message: String) throws {
			if !condition {
				throw NativeProbeFailure(message: message)
			}
		}

		private static func wait(_ message: String, _ condition: () -> Bool) async throws {
			for _ in 0..<600 {
				if condition() {
					return
				}

				try await Task.sleep(for: .milliseconds(10))
			}

			throw NativeProbeFailure(message: message)
		}

		private static func click(_ node: NodeRecord, in session: MountSession, native: MacOSWindow) throws {
			guard let geometry = session.document.interactionGeometry?.entries[node.id] else {
				throw NativeProbeFailure(message: "Missing confirmed control geometry")
			}

			let bounds = geometry.projectedBounds
			let point = STNPoint(x: bounds.minX + bounds.size.width / 2, y: bounds.minY + bounds.size.height / 2)
			try require(session.document.allowsLocation(point), "Confirmed control remains gated")
			let local = native.view.convert(CGPoint(x: point.x, y: point.y), to: nil)
			for kind in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
				guard
					let event = NSEvent.mouseEvent(
						with: kind,
						location: local,
						modifierFlags: [],
						timestamp: ProcessInfo.processInfo.systemUptime,
						windowNumber: native.nativeWindow.windowNumber,
						context: nil,
						eventNumber: 1,
						clickCount: 1,
						pressure: 1
					)
				else {
					throw NativeProbeFailure(message: "Native pointer event construction failed")
				}

				NSApp.sendEvent(event)
			}
		}

		private static func exercise(_ parent: STNWindow) async throws {
			let query = STNSignal("")
			var activations = 0
			for mode in ["sheet", "secondary", "child", "public-sheet"] {
				let child = STNWindow(
					properties: .init(title: "First click: \(mode)", size: .init(width: 300, height: 260))
				) {
					STNVStack(properties: .init(spacing: 8)) {
						STNTextField(properties: .init(value: query.binding, accessibility: .init(label: "Search")))
						STNScrollView(properties: .init(layout: .init(frame: STNFrame(width: 280, height: 180)))) {
							STNVStack(properties: .init(spacing: 4)) {
								for index in 0..<25 {
									STNButton(
										properties: .init(
											text: "Row \(index)",
											layout: .init(frame: STNFrame(width: 240, height: 28)),
											onActivate: { activations += 1 }
										)
									)
								}
							}
						}
					}
				}
				for pass in 0..<2 {
					// Restore the active parent after the preceding native close animation.
					try parent.show()
					NSApp.activate()
					try await wait("Parent did not become active before opening its child") {
						NSApp.isActive && parent.state.value.isKey
					}

					query.value = ""
					var sheet: Task<Int32, any Error>?
					if mode == "public-sheet" {
						sheet = Task { @MainActor in try await parent.presentSheet(child) }
						try await wait("Public sheet did not open") { child.session != nil }
					} else {
						try child.open(using: MacOSHost(), show: false)
					}

					guard let session = child.session, let native = session.window as? MacOSWindow else {
						throw NativeProbeFailure(message: "Missing native child session")
					}

					defer {
						sheet?.cancel()
						try? child.endSheet(result: -1)
						child.close()
					}

					session.draw()
					if mode != "public-sheet" {
						do {
							try await wait("Hidden offscreen preparation failed") {
								native.renderer.backingRevision > 0
							}
						} catch {
							let report = try await native.renderingDiagnostics()
							log(
								"Hidden: viewport \(session.document.viewport), dirty \(session.document.dirty), epoch \(native.graphics.surfaceEpoch), counters \(report.counters), errors \(session.errors)"
							)
							throw error
						}

						try require(
							native.graphics.presentation.confirmed == nil,
							"Hidden rendering falsely confirmed presentation"
						)
					}

					if mode == "sheet" {
						guard let nativeParent = parent.session?.window as? MacOSWindow else {
							throw NativeProbeFailure(message: "Missing parent host")
						}

						sheet = Task { @MainActor in try await nativeParent.presentSheet(native, critical: false) }
						try await wait("Sheet did not attach") { native.nativeWindow.sheetParent != nil }
					} else if mode == "child" {
						try parent.addChild(child)
						try child.show()
					} else if mode == "secondary" {
						native.nativeWindow.makeKeyAndOrderFront(nil)
						native.graphics.visibilityChanged()
					}

					do {
						try await wait("Positive presentation/input readiness missing: \(mode), pass \(pass)") {
							native.graphics.presentation.confirmed != nil && session.document.confirmedGeometry != nil
						}
					} catch {
						let report = try await native.renderingDiagnostics()
						log(
							"Readiness: visible=\(native.state.isVisible), key=\(native.state.isKey), occluded=\(native.state.isOccluded), positive=\(report.counters["positivePresentationObservations", default: 0]), zero=\(report.counters["zeroPresentationObservations", default: 0])"
						)
						throw error
					}

					try require(
						parent.session?.document.root.style.inert == (mode == "sheet" || mode == "public-sheet"),
						"Incorrect parent modality"
					)
					guard
						let row = session.document.orderedNodes.first(where: {
							$0.kind == .button && $0.text == "Row 0"
						}),
						let field = session.document.orderedNodes.first(where: { $0.kind == .textField })
					else {
						throw NativeProbeFailure(message: "Missing real controls")
					}

					let before = activations
					try click(row, in: session, native: native)
					try require(activations == before + 1, "First coordinate row click failed")
					try click(field, in: session, native: native)
					try require(session.document.focused == field.id, "Coordinate editor focus failed")
					guard
						let key = NSEvent.keyEvent(
							with: .keyDown,
							location: .zero,
							modifierFlags: [],
							timestamp: ProcessInfo.processInfo.systemUptime,
							windowNumber: native.nativeWindow.windowNumber,
							context: nil,
							characters: "a",
							charactersIgnoringModifiers: "a",
							isARepeat: false,
							keyCode: 0
						)
					else {
						throw NativeProbeFailure(message: "Native key event construction failed")
					}

					NSApp.sendEvent(key)
					try require(query.value == "a", "First native typing failed")
					if let sheet {
						try child.endSheet(result: 0)
						_ = try await sheet.value
					}

					log(
						"First-click PASS: \(mode), pass \(pass), epoch \(native.graphics.surfaceEpoch), confirmed \(native.graphics.presentation.confirmed!.scene)"
					)
					child.close()
				}
			}

			try require(activations == 8, "Incomplete pointer matrix")
			log("Input-readiness qualification passed: 8/8")
		}
	}

#else
	@main struct NativeInputProbeApp {
		static func main() {
			fatalError("The native input test fixture requires a debug build")
		}
	}
#endif
