import CStanaMacOS
import Foundation
import StanaCore
import StanaPrimitives
import StanaScene
import Testing

@testable import StanaPlatformMacOS

extension NativeWindowServer {
	@Suite(.serialized)
	@MainActor struct NativeMetalTests {
		private func wait(_ condition: () -> Bool) async throws {
			for _ in 0..<400 {
				if condition() { return }
				try await Task.sleep(for: .milliseconds(10))
			}
			try #require(condition(), "Timed out waiting for native Metal completion")
		}

		private func capture(_ scene: SceneSnapshot, in window: MacOSWindow) async throws -> STNRenderedImage {
			_ = try window.renderer.submit(scene)
			try await wait { window.renderer.backingRevision >= scene.sceneRevision }
			try await Task.sleep(for: .milliseconds(10))
			return try await window.capture()
		}

		@Test func workerRasterAndGPUContentReachCompleteOffscreenAndPresentation() async throws {
			let window = try MacOSWindow(title: "Metal hybrid verification", size: .init(width: 240, height: 160))
			window.graphics.onFailure = { Issue.record("Metal failure: \($0)") }
			defer { window.close() }
			let document = Document(size: .init(width: 240, height: 160))
			defer { document.close() }
			document.root.bounds = .init(width: 240, height: 160)
			let gpu = document.create(.gpuCanvas, parent: document.root)
			gpu.bounds = .init(x: 30, y: 30, width: 80, height: 70)
			gpu.gpuDrawing.fillRect(
				.init(width: 80, height: 70),
				color: STNColor(red: 0.9, green: 0.1, blue: 0.2),
				cornerRadius: 8
			)
			let label = document.create(.canvas, parent: document.root)
			label.bounds = .init(x: 50, y: 50, width: 40, height: 30)
			label.canvasCommands = [.fill(.init(width: 40, height: 30), .init(red: 0.1, green: 0.6, blue: 0.3), 0)]
			window.show()
			try await Task.sleep(for: .milliseconds(50))
			let scene = SceneBuilder(document: document)
				.build(surfaceEpoch: window.renderer.surfaceEpoch, backingRevision: 0)
			_ = try window.renderer.submit(scene)
			try await wait { window.renderer.backingRevision == scene.sceneRevision }
			try await wait {
				window.graphics.presentation.confirmed?.scene == scene.sceneRevision
					|| window.graphics.presentation.ambiguous?.scene == scene.sceneRevision
			}
			#expect(stn_window_export_png(window.handle, "/tmp/stana-metal-hybrid.png"))
			#expect(stn_window_pixel_hash(window.handle) != 0)
			let json = try #require(stn_metal_copy_diagnostics(window.handle))
			defer { stn_string_free(json) }
			let counters = try #require(
				JSONSerialization.jsonObject(with: Data(String(cString: json).utf8)) as? [String: Any]
			)
			if window.graphics.presentation.confirmed == nil {
				#expect((counters["zeroPresentationObservations"] as? Int ?? 0) > 0)
				#expect(window.graphics.presentation.ambiguous?.scene == scene.sceneRevision)
			}
			if ProcessInfo.processInfo.environment["STANA_REQUIRE_PRESENTED"] == "1" {
				#expect(window.graphics.presentation.confirmed?.scene == scene.sceneRevision)
			}
			#expect((counters["rasterPixels"] as? Int ?? 0) > 0)
			#expect((counters["gpuLeafDraws"] as? Int ?? 0) == 1)
		}

		@Test func applicationComputeAndHDRReadbackPreserveExtendedValues() async throws {
			let source = """
				#include <metal_stdlib>
				using namespace metal;
				kernel void paint(texture2d<half,access::write> output [[texture(0)]], uint2 p [[thread_position_in_grid]]) {
				    if (p.x < output.get_width() && p.y < output.get_height()) output.write(half4(4,1,0,1),p);
				}
				"""
			let program = try STNGPUProgram(
				shader: .metalSource(source),
				resources: ["output": .target(width: 64, height: 64)],
				passes: [
					.compute(
						.init(
							function: "paint",
							width: 64,
							height: 64,
							bindings: [
								.init(resource: "output", index: 0, access: .write, stage: .compute)
							]
						)
					)
				]
			)
			let window = try MacOSWindow(title: "Metal HDR verification", size: .init(width: 64, height: 64))
			window.graphics.onFailure = { Issue.record("Metal failure: \($0)") }
			defer { window.close() }
			let document = Document(size: .init(width: 64, height: 64))
			defer { document.close() }
			document.root.bounds = .init(width: 64, height: 64)
			let gpu = document.create(.gpuCanvas, parent: document.root)
			gpu.bounds = document.root.bounds
			gpu.gpuDrawing = .init(program: program)
			window.show()
			try await Task.sleep(for: .milliseconds(50))
			let scene = SceneBuilder(document: document)
				.build(surfaceEpoch: window.renderer.surfaceEpoch, backingRevision: 0)
			_ = try window.renderer.submit(scene)
			try await wait {
				window.graphics.presentation.confirmed?.scene == scene.sceneRevision
					|| window.graphics.presentation.ambiguous?.scene == scene.sceneRevision
			}
			#expect(stn_metal_export(window.handle, "/tmp/stana-metal-hdr.rgba16f", true))
			let data = try Data(contentsOf: URL(fileURLWithPath: "/tmp/stana-metal-hdr.rgba16f"))
			let values = data.withUnsafeBytes { Array($0.bindMemory(to: Float16.self)) }
			let metadata =
				try JSONSerialization.jsonObject(
					with: Data(contentsOf: URL(fileURLWithPath: "/tmp/stana-metal-hdr.rgba16f.json"))
				) as! [String: Any]
			let width = metadata["width"] as! Int
			let height = metadata["height"] as! Int
			#expect(values.count == width * height * 4)
			#expect(values[((height / 2) * width + width / 2) * 4] == 4)
		}

		@Test func temporalStateCommitsOneThousandStepsAndInvalidReplacementPreservesLastValidOutput() async throws {
			let source = """
				#include <metal_stdlib>
				using namespace metal;
				kernel void step(texture2d<half,access::read> previous [[texture(0)]],
				    texture2d<half,access::write> next [[texture(1)]], constant uint4 &increment [[buffer(0)]],
				    uint2 p [[thread_position_in_grid]]) {
				    next.write(half4(previous.read(p).r + half(increment.x),0,0,1),p);
				}
				"""
			var bytes: [UInt32] = [1, 0, 0, 0]
			let input = STNGPUResource.buffer(STNGPUBuffer(data: bytes.withUnsafeMutableBytes { Data($0) }))
			let slot = try STNGPUStateSlot(width: 1, height: 1)
			var program = try STNGPUProgram(
				shader: .metalSource(source),
				resources: ["output": .state(slot), "increment": input],
				passes: [
					.compute(
						.init(
							function: "step",
							width: 1,
							bindings: [
								.init(resource: "output", index: 0, stage: .compute, previous: true),
								.init(resource: "output", index: 1, access: .write, stage: .compute),
								.init(resource: "increment", index: 0, stage: .compute),
							]
						)
					)
				]
			)
			let window = try MacOSWindow(title: "Temporal state", size: .init(width: 32, height: 32))
			window.graphics.onFailure = { Issue.record("Metal failure: \($0)") }
			var diagnostics: [STNGPUDiagnostic] = []
			window.graphics.onDiagnostic = { diagnostics.append($0) }
			defer { window.close() }
			let document = Document(size: .init(width: 32, height: 32))
			defer { document.close() }
			document.root.bounds = .init(width: 32, height: 32)
			let gpu = document.create(.gpuCanvas, parent: document.root)
			gpu.bounds = document.root.bounds
			let builder = SceneBuilder(document: document)
			let transport = MetalSceneEncoder()
			window.show()
			try await Task.sleep(for: .milliseconds(50))
			for _ in 0..<1_000 {
				program = try program.updatingResources(["increment": input])
				gpu.gpuDrawing = .init(program: program)
				document.changed(gpu, .paint)
				let scene = builder.build(
					surfaceEpoch: window.renderer.surfaceEpoch,
					backingRevision: window.renderer.backingRevision
				)
				// This verifies offscreen feedback, not display geometry. The XCTest
				// host can return only zero presentation timestamps, so bypass the
				// adapter's deliberately bounded unacknowledged-geometry admission.
				let packet = try transport.encode(scene)
				#expect(
					packet.withUnsafeBytes {
						stn_metal_submit(window.handle, $0.bindMemory(to: UInt8.self).baseAddress, $0.count)
					}
				)
				try await wait { window.renderer.backingRevision >= scene.sceneRevision }
			}
			let image = try await window.capture()
			#expect(image.format == .premultipliedRGBA16Float)
			#expect(
				image.data.withUnsafeBytes {
					$0.bindMemory(to: Float16.self)[(image.height / 2 * image.width + image.width / 2) * 4]
				} == 1_000
			)
			let invalid = try program.updatingResources(["increment": .buffer(STNGPUBuffer(data: Data([1])))])
			gpu.gpuDrawing = .init(program: invalid)
			document.changed(gpu, .paint)
			let preserved = try await capture(
				builder.build(
					surfaceEpoch: window.renderer.surfaceEpoch,
					backingRevision: window.renderer.backingRevision
				),
				in: window
			)
			#expect(preserved.data == image.data)
			#expect(diagnostics.contains { $0.category == .binding && $0.message.contains("shorter") })
			let reset = try STNGPUStateSlot(width: 1, height: 1, resetKey: "restart")
			program = try program.updatingResources(["output": .state(reset)])
			gpu.gpuDrawing = .init(program: program)
			document.changed(gpu, .paint)
			let restarted = try await capture(
				builder.build(
					surfaceEpoch: window.renderer.surfaceEpoch,
					backingRevision: window.renderer.backingRevision
				),
				in: window
			)
			#expect(
				restarted.data.withUnsafeBytes {
					$0.bindMemory(to: Float16.self)[(restarted.height / 2 * restarted.width + restarted.width / 2) * 4]
				} == 1
			)
		}

		@Test func backdropIdentityIsExactAndFiniteBlurMatchesIndependentPixelReferenceInBothPaths() async throws {
			let window = try MacOSWindow(title: "Backdrop reference", size: .init(width: 48, height: 32))
			window.graphics.onFailure = { Issue.record("Metal failure: \($0)") }
			defer { window.close() }
			window.show()
			try await Task.sleep(for: .milliseconds(50))
			let document = Document(size: .init(width: 48, height: 32))
			defer { document.close() }
			document.surfaceBackground = .clear
			document.root.bounds = .init(width: 48, height: 32)
			let gpu = document.create(.gpuCanvas, parent: document.root)
			gpu.bounds = document.root.bounds
			gpu.gpuDrawing.fillRect(
				.init(x: 16, width: 8, height: 32),
				color: STNColor(red: 1, green: 0.5, blue: 0, alpha: 0.5)
			)
			let builder = SceneBuilder(document: document)
			stn_metal_test_configuration(window.handle, 1, 0, false)
			let baseline = try await capture(
				builder.build(surfaceEpoch: window.renderer.surfaceEpoch, backingRevision: 0),
				in: window
			)
			let backdrop = document.create(.backdrop, parent: document.root)
			backdrop.bounds = document.root.bounds
			backdrop.style.retained = true
			backdrop.style.clip = true
			backdrop.style.cornerRadius = 5
			backdrop.style.opacity = 0.3
			backdrop.backdropEffect = .identity
			let identity = try await capture(
				builder.build(
					surfaceEpoch: window.renderer.surfaceEpoch,
					backingRevision: window.renderer.backingRevision
				),
				in: window
			)
			#expect(identity.data == baseline.data)
			backdrop.style.cornerRadius = 0
			backdrop.style.opacity = 1
			backdrop.backdropEffect = .blur(radius: 3)
			document.changed(backdrop, .compositing)
			let blurred = try await capture(
				builder.build(
					surfaceEpoch: window.renderer.surfaceEpoch,
					backingRevision: window.renderer.backingRevision
				),
				in: window
			)
			let radius = Int((3 * Double(baseline.width) / 48).rounded(.up))
			let reference = boxBlur(baseline.data, width: baseline.width, height: baseline.height, radius: radius)
			#expect(zip(blurred.data, reference).allSatisfy { abs(Int($0) - Int($1)) <= 2 })
			stn_metal_test_configuration(window.handle, 2, 0, false)
			document.changed(document.root, .paint)
			let direct = try await capture(
				builder.build(
					surfaceEpoch: window.renderer.surfaceEpoch,
					backingRevision: window.renderer.backingRevision
				),
				in: window
			)
			#expect(direct.data == blurred.data)
		}

		@Test func hostedSurfacesPromoteTogetherWhenTheWindowContainsHDR() async throws {
			let window = try MacOSWindow(title: "Shared color profile", size: .init(width: 64, height: 64))
			let chrome = try MacOSWindow(title: "", size: .init(width: 64, height: 32), parent: window)
			defer { chrome.close(); window.close() }
			let content = Document(size: .init(width: 64, height: 64))
			let accessory = Document(size: .init(width: 64, height: 32))
			defer { accessory.close(); content.close() }
			content.root.bounds = .init(width: 64, height: 64)
			accessory.root.bounds = .init(width: 64, height: 32)
			let chromeBuilder = SceneBuilder(document: accessory)
			window.show()
			try await Task.sleep(for: .milliseconds(50))
			let sdr = try await capture(
				chromeBuilder.build(surfaceEpoch: chrome.renderer.surfaceEpoch, backingRevision: 0),
				in: chrome
			)
			#expect(sdr.format == .premultipliedBGRA8)
			let gpu = content.create(.gpuCanvas, parent: content.root)
			gpu.bounds = content.root.bounds
			gpu.gpuDrawing.fillRect(gpu.bounds, color: STNExtendedColor(red: 2, green: 1, blue: 0))
			_ = try await capture(
				SceneBuilder(document: content).build(surfaceEpoch: window.renderer.surfaceEpoch, backingRevision: 0),
				in: window
			)
			accessory.changed(accessory.root, .paint)
			let hdr = try await capture(
				chromeBuilder.build(
					surfaceEpoch: chrome.renderer.surfaceEpoch,
					backingRevision: chrome.renderer.backingRevision
				),
				in: chrome
			)
			#expect(hdr.format == .premultipliedRGBA16Float)
			let diagnostics = try await chrome.renderingDiagnostics()
			#expect(diagnostics.workingColorProfile == "extendedLinearSRGB")
		}

		@Test func mixedPrefixReplacementKeepsForegroundSharpAndLaterPaintOutsideTheEffect() async throws {
			let window = try MacOSWindow(title: "Ordered translucent backdrop", size: .init(width: 48, height: 32))
			defer { window.close() }
			let document = Document(size: .init(width: 48, height: 32))
			defer { document.close() }
			document.surfaceBackground = .clear
			document.root.bounds = .init(width: 48, height: 32)
			let first = document.create(.canvas, parent: document.root)
			first.bounds = document.root.bounds
			first.canvasCommands = [.fill(first.bounds, .init(red: 1, green: 0, blue: 0, alpha: 0.5), 0)]
			let gpu = document.create(.gpuCanvas, parent: document.root)
			gpu.bounds = document.root.bounds
			gpu.gpuDrawing.fillRect(gpu.bounds, color: STNColor(red: 0, green: 0, blue: 1, alpha: 0.5))
			gpu.gpuDrawing.fillRect(gpu.bounds, color: STNColor(red: 1, green: 0, blue: 0, alpha: 0.25))
			let middle = document.create(.canvas, parent: document.root)
			middle.bounds = document.root.bounds
			middle.canvasCommands = [.fill(middle.bounds, .init(red: 0, green: 1, blue: 0, alpha: 0.25), 0)]
			let panel = document.create(.backdrop, parent: document.root)
			panel.bounds = document.root.bounds
			panel.style.retained = true
			panel.style.clip = true
			panel.style.opacity = 0.5
			panel.backdropEffect = .identity
			let foreground = document.create(.canvas, parent: panel)
			foreground.bounds = .init(x: 8, y: 8, width: 32, height: 16)
			foreground.canvasCommands = [
				.fill(.init(width: 32, height: 16), .init(red: 1, green: 1, blue: 1, alpha: 0.25), 0)
			]
			let later = document.create(.canvas, parent: document.root)
			later.bounds = .init(x: 20, y: 12, width: 8, height: 8)
			later.canvasCommands = [.fill(.init(width: 8, height: 8), .init(red: 1, green: 1, blue: 0), 0)]
			window.show()
			try await Task.sleep(for: .milliseconds(50))
			let builder = SceneBuilder(document: document)
			stn_metal_test_configuration(window.handle, 1, 0, false)
			let image = try await capture(
				builder.build(surfaceEpoch: window.renderer.surfaceEpoch, backingRevision: 0),
				in: window
			)
			let scale = Double(image.width) / 48
			func pixel(_ x: Int, _ y: Int) -> [Double] {
				let offset = (Int((Double(y) + 0.5) * scale) * image.width + Int((Double(x) + 0.5) * scale)) * 4
				return [2, 1, 0, 3].map { Double(image.data[offset + $0]) / 255 }
			}
			// Independent premultiplied reference: green over blue over red,
			// then mix(B, white over B, 0.5). Never source-over B a second time.
			let prefix = [0.328125, 0.25, 0.28125, 0.859375]
			let expected = prefix.map { $0 * 0.875 + 0.125 }
			#expect(zip(pixel(12, 16), expected).allSatisfy { abs($0 - $1) <= 2.0 / 255 })
			#expect(zip(pixel(3, 16), prefix).allSatisfy { abs($0 - $1) <= 2.0 / 255 })
			#expect(pixel(24, 16) == [1, 1, 0, 1])
			stn_metal_test_configuration(window.handle, 2, 0, false)
			document.changed(document.root, .paint)
			let direct = try await capture(
				builder.build(
					surfaceEpoch: window.renderer.surfaceEpoch,
					backingRevision: window.renderer.backingRevision
				),
				in: window
			)
			#expect(direct.data == image.data)
		}

		@Test func changedOffOutputHaloPropagatesThroughChainedBackdropInputs() async throws {
			let window = try MacOSWindow(title: "Chained backdrop dependency", size: .init(width: 48, height: 32))
			defer { window.close() }
			let document = Document(size: .init(width: 48, height: 32))
			defer { document.close() }
			document.surfaceBackground = .clear
			document.root.bounds = .init(width: 48, height: 32)
			let source = document.create(.canvas, parent: document.root)
			source.bounds = .init(x: 10, width: 2, height: 32)
			source.canvasCommands = [.fill(.init(width: 2, height: 32), .white, 0)]
			for (bounds, radius) in [
				(STNRect(x: 16, width: 16, height: 32), 10.0), (.init(x: 20, width: 4, height: 32), 4.0),
			] {
				let panel = document.create(.backdrop, parent: document.root)
				panel.bounds = bounds
				panel.style.retained = true
				panel.style.clip = true
				panel.backdropEffect = .blur(radius: radius)
			}
			let builder = SceneBuilder(document: document)
			window.show()
			try await Task.sleep(for: .milliseconds(50))
			let before = try await capture(
				builder.build(surfaceEpoch: window.renderer.surfaceEpoch, backingRevision: 0),
				in: window
			)
			source.canvasCommands = [.fill(.init(width: 2, height: 32), .black, 0)]
			document.changed(source, .paint)
			let incremental = try await capture(
				builder.build(
					surfaceEpoch: window.renderer.surfaceEpoch,
					backingRevision: window.renderer.backingRevision
				),
				in: window
			)
			let x = Int(20.5 * Double(before.width) / 48), y = before.height / 2
			#expect(before.data[(y * before.width + x) * 4] != incremental.data[(y * before.width + x) * 4])
			window.graphics.invalidate()
			document.changed(document.root, .paint)
			let rebuilt = try await capture(
				builder.build(surfaceEpoch: window.renderer.surfaceEpoch, backingRevision: 0),
				in: window
			)
			#expect(incremental.data == rebuilt.data)
		}

		private func boxBlur(_ source: Data, width: Int, height: Int, radius: Int) -> Data {
			var bytes = Array(source)
			for horizontal in [true, false] {
				var result = [UInt8](repeating: 0, count: bytes.count)
				for y in 0..<height {
					for x in 0..<width {
						for channel in 0..<4 {
							var sum = 0
							for offset in -radius...radius {
								let sx = x + (horizontal ? offset : 0), sy = y + (horizontal ? 0 : offset)
								if sx >= 0, sx < width, sy >= 0, sy < height {
									sum += Int(bytes[(sy * width + sx) * 4 + channel])
								}
							}
							result[(y * width + x) * 4 + channel] = UInt8(
								(Double(sum) / Double(radius * 2 + 1)).rounded()
							)
						}
					}
				}
				bytes = result
			}
			return Data(bytes)
		}

		@Test func stalledRasterDoesNotAcquireADrawableAndStarvationDoesNotPrepareMoreFrames() async throws {
			let window = try MacOSWindow(title: "Worker admission", size: .init(width: 100, height: 80))
			window.graphics.onFailure = { Issue.record("Metal failure: \($0)") }
			defer { window.close() }
			window.show()
			try await Task.sleep(for: .milliseconds(50))
			stn_metal_test_configuration(window.handle, 1, 0.1, true)
			let document = Document(size: .init(width: 100, height: 80))
			defer { document.close() }
			document.root.bounds = .init(width: 100, height: 80)
			let builder = SceneBuilder(document: document)
			let scene = builder.build(surfaceEpoch: window.renderer.surfaceEpoch, backingRevision: 0)
			_ = try window.renderer.submit(scene)
			try await Task.sleep(for: .milliseconds(30))
			var dispatchedKeys = 0
			window.onEvent = { event in if case .key = event { dispatchedKeys += 1 } }
			window.receive(
				stn_event(
					kind: 6,
					x: 0,
					y: 0,
					a: 0,
					b: 0,
					identity: 0,
					sequence: 0,
					epoch: 0,
					text: stn_utf8(bytes: nil, length: 0)
				)
			)
			#expect(dispatchedKeys == 1)
			#expect(window.renderer.backingRevision == 0)
			try await wait { window.renderer.backingRevision == scene.sceneRevision }
			for _ in 0..<100 { document.changed(document.root, .paint); window.requestRedraw() }
			try await Task.sleep(for: .milliseconds(100))
			let json = try #require(stn_metal_copy_diagnostics(window.handle))
			defer { stn_string_free(json) }
			let counters = try #require(
				JSONSerialization.jsonObject(with: Data(String(cString: json).utf8)) as? [String: Any]
			)
			#expect((counters["drawableAcquisitions"] as? Int ?? 0) == 0)
			#expect((counters["offscreenSubmissions"] as? Int ?? 0) == 1)
			stn_metal_test_configuration(window.handle, 1, 0, false)
		}

		@Test func sparseFinalTilesMatchForcedFullAndUntiledReconstructions() async throws {
			let window = try MacOSWindow(title: "Persistent final tiles", size: .init(width: 1920, height: 1080))
			window.graphics.onFailure = { Issue.record("Metal failure: \($0)") }
			defer { window.close() }
			window.show()
			try await Task.sleep(for: .milliseconds(50))
			let document = Document(size: .init(width: 1920, height: 1080))
			defer { document.close() }
			document.root.bounds = .init(width: 1920, height: 1080)
			let leaf = document.create(.canvas, parent: document.root)
			leaf.bounds = .init(x: 20, y: 20, width: 30, height: 30)
			leaf.canvasCommands = [.fill(.init(width: 30, height: 30), .white, 0)]
			let builder = SceneBuilder(document: document)
			stn_metal_test_configuration(window.handle, 1, 0, false)
			_ = try await capture(
				builder.build(surfaceEpoch: window.renderer.surfaceEpoch, backingRevision: 0),
				in: window
			)
			let before = try await window.renderingDiagnostics()
			leaf.canvasCommands = [.fill(.init(width: 30, height: 30), .black, 0)]
			document.changed(leaf, .paint)
			let incremental = try await capture(
				builder.build(
					surfaceEpoch: window.renderer.surfaceEpoch,
					backingRevision: window.renderer.backingRevision
				),
				in: window
			)
			let after = try await window.renderingDiagnostics()
			let pixels = Double(incremental.width * incremental.height)
			#expect(
				after.counters["rasterPixels", default: 0] - before.counters["rasterPixels", default: 0] <= pixels * 0.1
			)
			#expect(
				after.counters["finalPixelsRedrawn", default: 0] - before.counters["finalPixelsRedrawn", default: 0]
					<= pixels * 0.1
			)
			stn_metal_test_configuration(window.handle, 3, 0, false)
			document.changed(document.root, .paint)
			let full = try await capture(
				builder.build(
					surfaceEpoch: window.renderer.surfaceEpoch,
					backingRevision: window.renderer.backingRevision
				),
				in: window
			)
			#expect(incremental.data == full.data)
			stn_metal_test_configuration(window.handle, 4, 0, false)
			document.changed(document.root, .paint)
			let untiled = try await capture(
				builder.build(
					surfaceEpoch: window.renderer.surfaceEpoch,
					backingRevision: window.renderer.backingRevision
				),
				in: window
			)
			#expect(incremental.data == untiled.data)
		}
	}
}
