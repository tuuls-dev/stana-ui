import CoreGraphics
import StanaGraphics
import StanaPrimitives
import StanaScene

@MainActor package final class CoreGraphicsRenderer: Renderer {
	private weak var window: MacOSWindow?
	package private(set) var backingRevision: UInt64 = 0
	package private(set) var surfaceEpoch: UInt64 = 1

	package init(window: MacOSWindow) {
		self.window = window
		window.graphics.detach()
	}

	package func invalidate() {
		nextRevision(&surfaceEpoch)
		backingRevision = 0
	}

	package func submit(_ scene: SceneSnapshot) throws -> FrameCompletion {
		guard let window, !window.closed else {
			throw STNError.nodeDisposed
		}

		let scale = window.nativeWindow.backingScaleFactor
		let width = Int(ceil(scene.size.width * scale)), height = Int(ceil(scene.size.height * scale))
		guard width > 0, height > 0, width <= 16_384, height <= 16_384, width <= 67_108_864 / height else {
			throw STNError.nativeFailure("Raster surface exceeds checked allocation limit")
		}

		var full =
			scene.damageBaseRevision != backingRevision || scene.surfaceEpoch != surfaceEpoch || backingRevision == 0
		if window.backing?.width != width || window.backing?.height != height || window.backingScale != scale {
			window.backing = CGContext(
				data: nil,
				width: width,
				height: height,
				bitsPerComponent: 8,
				bytesPerRow: width * 4,
				space: CGColorSpace(name: CGColorSpace.sRGB)!,
				bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
			)
			window.backingScale = scale
			window.backing?.translateBy(x: 0, y: Double(height))
			window.backing?.scaleBy(x: scale, y: -scale)
			full = true
		}

		guard let context = window.backing else {
			throw STNError.nativeFailure("Raster context allocation failed")
		}

		if full || !scene.damage.isEmpty {
			context.saveGState()
			if !full {
				context.beginPath()
				for rect in scene.damage {
					context.addRect(rect.cgRect)
				}

				context.clip()
			}

			context.clear(CGRect(x: 0, y: 0, width: scene.size.width, height: scene.size.height))
			window.rasterCanvas.draw(scene.commands, in: context)
			context.restoreGState()
			window.view.needsDisplay = true
		}

		backingRevision = scene.sceneRevision
		return .init(sceneRevision: backingRevision, surfaceEpoch: surfaceEpoch, presentationConfirmed: false)
	}

	package func detach() {
		window = nil
	}
}
