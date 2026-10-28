import Foundation
import Stana

@MainActor private func uniforms(_ time: Double) -> STNGPUResource {
	var values: [Float] = [Float(time), 0, 0, 0]
	return .buffer(STNGPUBuffer(data: values.withUnsafeMutableBytes { Data($0) }))
}

@MainActor private func chart(at time: Double) -> STNGPUDrawing {
	var drawing = STNGPUDrawing()
	drawing.fillRect(
		.init(width: 840, height: 260),
		color: STNColor(red: 0.04, green: 0.07, blue: 0.13),
		cornerRadius: 18
	)
	for index in 0..<28 {
		let height = 35 + 120 * (0.5 + 0.5 * sin(Double(index) * 0.45 + time))
		drawing.fillRect(
			.init(x: 14 + Double(index) * 29, y: 244 - height, width: 20, height: height),
			color: STNColor(red: 0.1, green: 0.4 + Double(index % 3) * 0.1, blue: 0.9),
			cornerRadius: 4
		)
	}
	let points = (0..<64)
		.map { index in
			STNPoint(x: 16 + Double(index) * 12.8, y: 120 + 65 * sin(Double(index) * 0.13 + time * 0.7))
		}
	drawing.strokePolyline(points, color: STNExtendedColor(red: 0.2, green: 2.5, blue: 1.2), width: 3)
	return drawing
}

@MainActor private struct HybridContent: STNComponent {
	let field: STNGPUProgram
	let glass: STNGPUProgram

	func makeContent(in context: STNComponentContext) -> some STNComponent {
		let active = context.state(initial: true)
		let time = context.state(initial: 0.0)
		let chartDrawing = context.state(initial: chart(at: 0))
		let fieldDrawing = context.state(initial: STNGPUDrawing(program: field))
		let glassEffect = context.state(initial: STNBackdropEffect.program(glass))
		context.onFrame(isActive: active) { frame in
			time.value += frame.elapsed
			chartDrawing.value = chart(at: time.value)
			if let next = try? field.updatingResources(["time": uniforms(time.value)]) {
				fieldDrawing.value = STNGPUDrawing(program: next)
			}
			if let next = try? glass.updatingResources(["time": uniforms(time.value)]) {
				glassEffect.value = .program(next)
			}
		}
		STNVStack(properties: .init(spacing: 16, layout: .init(padding: STNInsets(24)))) {
			STNHStack(properties: .init(spacing: 20)) {
				STNText(
					properties: .init(
						text: "Retained • Metal • Swift",
						textStyle: .init(font: STNFont.system(size: 26, weight: .semibold))
					)
				)
				STNToggle(properties: .init(text: "Animate", isOn: active.binding))
			}
			STNBox(
				properties: .init(
					layout: .init(frame: STNFrame(width: 840, height: 260)),
					appearance: .init(cornerRadius: 18, clip: true)
				)
			) {
				STNGPUCanvas(
					properties: .init(drawing: chartDrawing, layout: .init(frame: STNFrame(width: 840, height: 260)))
				)
				STNBackdrop(
					properties: .init(
						effect: STNBackdropEffect.blur(radius: 10),
						transform: time.map { .translation(x: 40 + 20 * sin($0), y: 30) },
						layout: .init(frame: STNFrame(width: 250, height: 120)),
						appearance: .init(opacity: time.map { 0.65 + 0.3 * sin($0 * 0.4) }, cornerRadius: 16)
					)
				) {
					STNVStack(
						properties: .init(
							spacing: 8,
							layout: .init(padding: STNInsets(16), frame: STNFrame(width: 250, height: 120))
						)
					) {
						STNText(
							properties: .init(text: "Finite-radius frost", textStyle: .init(foreground: STNColor.white))
						)
						STNButton(
							properties: .init(text: "Ordinary CPU control", onActivate: { active.value.toggle() })
						)
					}
				}
				STNBackdrop(
					properties: .init(
						effect: glassEffect,
						transform: STNAffineTransform.translation(x: 440, y: 110),
						layout: .init(frame: STNFrame(width: 290, height: 115)),
						appearance: .init(cornerRadius: 16)
					)
				) {
					STNText(
						properties: .init(
							text: "Custom glass-like distortion",
							layout: .init(padding: STNInsets(16)),
							textStyle: .init(foreground: STNColor.white)
						)
					)
				}
				STNLayer(
					properties: .init(
						transform: STNAffineTransform.translation(x: 585, y: 16),
						layout: .init(frame: STNFrame(width: 220, height: 36))
					)
				) {
					STNBox(
						properties: .init(
							layout: .init(padding: STNInsets(8)),
							appearance: .init(background: STNColor.surface, cornerRadius: 8)
						)
					) {
						STNText(properties: .init(text: "Later CPU tooltip stays on top"))
					}
				}
			}
			STNHStack(properties: .init(spacing: 18)) {
				STNGPUCanvas(
					properties: .init(drawing: fieldDrawing, layout: .init(frame: STNFrame(width: 270, height: 170)))
				)
				STNLayer(
					properties: .init(
						layout: .init(frame: STNFrame(width: 550, height: 170)),
						appearance: .init(cornerRadius: 14, clip: true)
					)
				) {
					STNBox(
						properties: .init(
							layout: .init(frame: STNFrame(width: 550, height: 170)),
							appearance: .init(background: STNColor.surface)
						)
					) {
						STNText(
							properties: .init(
								text: "This isolated group establishes a local backdrop context",
								layout: .init(padding: STNInsets(14))
							)
						)
						STNBackdrop(
							properties: .init(
								effect: STNBackdropEffect.blur(radius: 5),
								transform: STNAffineTransform.translation(x: 30, y: 55),
								layout: .init(frame: STNFrame(width: 490, height: 85)),
								appearance: .init(cornerRadius: 10)
							)
						) {
							STNText(
								properties: .init(
									text:
										"Nested frost sees only earlier local paint—not the chart outside this group.",
									layout: .init(padding: STNInsets(10))
								)
							)
						}
					}
				}
			}
			STNScrollView(
				properties: .init(
					layout: .init(frame: STNFrame(width: 840, height: 150)),
					appearance: .init(cornerRadius: 12, clip: true)
				)
			) {
				STNVStack(properties: .init(spacing: 6, layout: .init(padding: STNInsets(12)))) {
					for index in 0..<300 {
						STNText(
							properties: .init(
								text: "Retained row \(index) — tiled raster content",
								layout: .init(frame: STNFrame(width: 800, height: 22))
							)
						)
					}
				}
			}
		}
	}
}

@main struct HybridRenderingApp {
	@MainActor static func main() throws {
		let url = Bundle.module.url(forResource: "Hybrid", withExtension: "metal", subdirectory: "Resources")!
		let source = try String(contentsOf: url, encoding: .utf8)
		let field = try STNGPUProgram(
			shader: .metalSource(source),
			resources: [
				"field": .target(width: 128, height: 96), "output": .target(width: 128, height: 96),
				"time": uniforms(0),
			],
			passes: [
				.compute(
					.init(
						function: "field",
						width: 128,
						height: 96,
						bindings: [
							.init(resource: "field", index: 0, access: .write, stage: .compute),
							.init(resource: "time", index: 0, stage: .compute),
						]
					)
				),
				.render(
					.init(
						vertex: "fullscreen",
						fragment: "shade",
						bindings: [.init(resource: "field", index: 0, stage: .fragment)]
					)
				),
			]
		)
		let glass = try STNGPUProgram(
			shader: .metalSource(source),
			resources: ["output": .target(), "time": uniforms(0)],
			passes: [
				.render(
					.init(
						vertex: "fullscreen",
						fragment: "glass",
						bindings: [
							.backdrop(index: 0), .backdropCoordinates(index: 1),
							.init(resource: "time", index: 0, stage: .fragment),
						]
					)
				)
			],
			samplingRadius: 6
		)
		let window = STNWindow(properties: .init(title: "Stana Hybrid Rendering", size: .init(width: 900, height: 760)))
		{
			HybridContent(field: field, glass: glass)
		}
		var verificationError: (any Error)?
		if CommandLine.arguments.contains("--benchmark") {
			Task { @MainActor in
				do {
					try await NativeBenchmark.run(window: window)
				} catch {
					verificationError = error
					print("Native benchmark failed: \(error)")
				}
				STNApplication.stop()
			}
		}
		if CommandLine.arguments.contains("--smoke-test") {
			Task { @MainActor in
				try? await Task.sleep(for: .seconds(3))
				do {
					let image = try await window.capture()
					try image.data.write(to: URL(fileURLWithPath: "/tmp/stana-hybrid-scene.rgba16f"))
					try image.displayMappedBGRA().write(to: URL(fileURLWithPath: "/tmp/stana-hybrid-scene.bgra8"))
					print(
						"Hybrid capture: \(image.width)×\(image.height), scene \(image.sceneRevision), \(image.data.count) bytes"
					)
					let diagnostics = try await window.renderingDiagnostics()
					let json = try JSONEncoder().encode(diagnostics)
					try json.write(to: URL(fileURLWithPath: "/tmp/stana-hybrid-diagnostics.json"))
					print(String(decoding: json, as: UTF8.self))
				} catch {
					verificationError = error
					print("Hybrid capture failed: \(error)")
				}
				STNApplication.stop()
			}
		}
		STNApplication.run(windows: [window])
		if let verificationError { throw verificationError }
	}
}
