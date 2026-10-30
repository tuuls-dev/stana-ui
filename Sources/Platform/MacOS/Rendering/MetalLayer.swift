import AppKit
import Metal
import QuartzCore
import Synchronization

/// Never hold the reference mutex across native callbacks or drawable waits.
final class MetalLayer: Sendable {
	private let storage = Mutex(CAMetalLayer())

	@MainActor func install(in view: NSView, device: any MTLDevice, opaque: Bool) {
		storage.withLock { $0 = CAMetalLayer() }
		let layer = storage.withLock { $0 }
		layer.device = device
		layer.pixelFormat = .bgra8Unorm
		layer.framebufferOnly = true
		layer.isOpaque = opaque
		layer.maximumDrawableCount = 3
		layer.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
		layer.frame = view.bounds
		view.wantsLayer = true
		view.layer = layer
	}

	@MainActor func configure(bounds: CGRect, size: CGSize, scale: Double, opaque: Bool, extended: Bool) {
		CATransaction.begin()
		CATransaction.setDisableActions(true)
		defer {
			CATransaction.commit()
		}

		let layer = storage.withLock { $0 }
		layer.frame = bounds
		layer.contentsScale = scale
		layer.drawableSize = size
		layer.isOpaque = opaque
		layer.pixelFormat = extended ? .rgba16Float : .bgra8Unorm
		layer.wantsExtendedDynamicRangeContent = extended
		layer.colorspace = CGColorSpace(name: extended ? CGColorSpace.extendedLinearSRGB : CGColorSpace.sRGB)
	}

	func nextDrawable(acquire: (CAMetalLayer) -> (any CAMetalDrawable)? = { $0.nextDrawable() }) -> (
		any CAMetalDrawable
	)? {
		let layer = storage.withLock { $0 }
		return acquire(layer)
	}
}
