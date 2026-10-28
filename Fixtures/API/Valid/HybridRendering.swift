import Foundation
import Stana

@MainActor func hybridRenderingFixture() throws {
	var drawing = STNGPUDrawing()
	drawing.fillRect(.init(width: 80, height: 50), color: STNColor.accent, cornerRadius: 8)
	drawing.fillEllipse(.init(x: 12, y: 12, width: 40, height: 40), color: STNExtendedColor(red: 4, green: 1, blue: 0))
	let geometry = STNGPUMesh(
		vertices: [
			.init(position: .zero, color: .init(red: 1, green: 0, blue: 0)),
			.init(position: .init(x: 50), color: .init(red: 0, green: 1, blue: 0)),
			.init(position: .init(y: 50), color: .init(red: 0, green: 0, blue: 1)),
		],
		indices: [0, 1, 2]
	)
	drawing.drawMesh(geometry)
	let value = STNSignal(drawing)
	let transform = STNSignal(STNAffineTransform.identity)
	let opacity = STNSignal(0.75)
	let effect = STNSignal(STNBackdropEffect.blur(radius: 12))
	let _ = STNWindow(
		properties: .init(
			title: "Hybrid rendering",
			configuration: STNWindow.Configuration(renderingColorMode: .automatic)
		)
	) {
		STNLayer(properties: .init(transform: transform, appearance: .init(opacity: opacity.map { $0 }))) {
			STNGPUCanvas(properties: .init(drawing: value, layout: .init(frame: STNFrame(width: 100, height: 100))))
			STNBackdrop(
				properties: .init(
					effect: effect,
					transform: transform.map { $0 },
					appearance: .init(opacity: opacity, cornerRadius: 12)
				)
			) {
				STNText(properties: .init(text: "Foreground is not part of the sampled prefix"))
			}
		}
	}
	let program = try STNGPUProgram(
		shader: .metalSource("application-provided Metal source"),
		resources: ["output": .target(), "uniforms": .buffer(.init(data: Data(repeating: 0, count: 16)))],
		passes: [
			.render(
				.init(
					vertex: "vertexMain",
					fragment: "fragmentMain",
					bindings: [
						.init(resource: "uniforms", index: 0, stage: .fragment)
					]
				)
			)
		]
	)
	let _ = STNGPUCanvas(properties: .init(drawing: STNGPUDrawing(program: program)))
}
