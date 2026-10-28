import Stana
import StanaTesting
import Testing

@MainActor @Test func gpuCanvasAndRetainedLayerKeepIdentityAcrossUpdates() throws {
	var initial = STNGPUDrawing()
	initial.fillRect(.init(width: 40, height: 30), color: STNColor.white)
	let drawing = STNSignal(initial)
	let transform = STNSignal(STNAffineTransform.identity)
	let host = STNTestHost()
	host.mount {
		STNLayer(properties: .init(transform: transform)) {
			STNGPUCanvas(properties: .init(drawing: drawing, layout: .init(frame: STNFrame(width: 100, height: 80))))
			STNBackdrop(
				properties: .init(
					effect: STNBackdropEffect.blur(radius: 8),
					layout: .init(frame: STNFrame(width: 60, height: 30))
				)
			) {
				STNText(properties: .init(text: "Over the prefix"))
			}
		}
	}
	let ids = host.nodeIDs
	let mounts = host.metrics.totalMounts
	transform.value = .translation(x: 20, y: 30)
	var next = drawing.value
	next.fillEllipse(.init(width: 40, height: 40), color: STNExtendedColor(red: 2, green: 0, blue: 0))
	drawing.value = next
	#expect(host.nodeIDs == ids)
	#expect(host.metrics.totalMounts == mounts)
	#expect(host.render() != nil)
	host.close()
}

@MainActor @Test func transformedHitTestingUsesInverseAndRoundedClip() {
	var clicks = 0
	let host = STNTestHost(size: .init(width: 300, height: 200))
	host.mount {
		STNLayer(
			properties: .init(
				transform: STNAffineTransform.translation(x: 100, y: 40),
				layout: .init(frame: STNFrame(width: 80, height: 50)),
				appearance: .init(cornerRadius: 20, clip: true)
			)
		) {
			STNButton(properties: .init(text: "Move", onActivate: { clicks += 1 }))
		}
	}
	host.click(at: .init(x: 10, y: 10))
	#expect(clicks == 0)
	host.click(at: .init(x: 120, y: 60))
	#expect(clicks == 1)
	host.close()
}
