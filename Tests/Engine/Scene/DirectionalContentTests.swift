import StanaCore
import StanaPrimitives
import StanaScene
import Testing

@Suite @MainActor struct DirectionalContentTests {
	@Test(arguments: [STNLayoutDirection.leftToRight, .rightToLeft])
	func fullAndPatchedTextCanvasAndGPUUseTheSameLogicalInsets(direction: STNLayoutDirection) throws {
		let d = Document(size: .init(width: 200, height: 200))
		defer {
			d.close()
		}

		d.direction = direction
		d.root.bounds = .init(width: 200, height: 200)
		let label = d.create(.text, parent: d.root)
		label.text = "content"
		label.bounds = .init(width: 100, height: 40)
		label.style.padding = .init(top: 4, leading: 10, bottom: 6, trailing: 30)
		let canvas = d.create(.canvas, parent: d.root)
		canvas.bounds = label.bounds
		canvas.style.padding = label.style.padding
		canvas.canvasCommands = [.fill(.init(width: 5, height: 6), .white, 0)]
		let gpu = d.create(.gpuCanvas, parent: d.root)
		gpu.bounds = label.bounds
		gpu.style.padding = label.style.padding
		let builder = SceneBuilder(document: d)
		var backing: UInt64 = 0
		for full in [true, false] {
			if !full {
				label.style.foreground = .accent
				d.changed(label, .paint)
				canvas.canvasCommands = [.fill(.init(width: 5, height: 6), .black, 0)]
				d.changed(canvas, .paint)
				gpu.gpuDrawing.fillRect(.init(width: 10, height: 10), color: STNColor.white)
				d.changed(gpu, .paint)
			}

			let scene = builder.build(surfaceEpoch: 1, backingRevision: backing)
			backing = scene.sceneRevision
			let x = direction == .leftToRight ? 10.0 : 30.0
			#expect(
				scene.commands.contains {
					if case .text("content", let bounds, _, _, _) = $0 {
						return bounds == .init(x: x, y: 4, width: 60, height: 30)
					}
					return false
				}
			)
			#expect(
				scene.commands.contains {
					if case .fill(let bounds, _, _) = $0 {
						return bounds == .init(x: x, y: 4, width: 5, height: 6)
					}
					return false
				}
			)
			let paint = try #require(scene.paint)
			let gpuBounds = paint.children.compactMap { entry -> STNRect? in
				if case .gpu(let item) = entry {
					return item.bounds
				}
				return nil
			}
			#expect(gpuBounds == [.init(x: x, y: 4, width: 60, height: 30)])
		}
	}
}
