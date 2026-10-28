import Foundation
import StanaPrimitives

package struct PaintCPUItem: Equatable, Sendable {
	package let id: STNNodeID
	package let version: UUID
	package let bounds: STNRect
	package let commands: [DrawCommand]
}

package struct PaintGPUItem: Equatable, Sendable {
	package let version = UUID()
	package let id: STNNodeID
	package let bounds: STNRect
	package let drawing: STNGPUDrawing
	package var colors = GPUColorEnvironment()
}

package enum PaintEntry: Equatable, Sendable {
	case cpu(PaintCPUItem)
	case gpu(PaintGPUItem)
	case group(PaintGroup)

	package var requiresExtended: Bool {
		switch self {
		case .cpu: false
		case .gpu(let item): item.drawing.requiresExtended
		case .group(let group): group.requiresExtended
		}
	}
}

package struct PaintGroup: Equatable, Sendable {
	package private(set) var version = UUID()
	package let id: STNNodeID
	package let bounds: STNRect
	package let transform: STNAffineTransform
	package let opacity: Double
	package let clips: Bool
	package let radius: Double
	package let backdrop: STNBackdropEffect?
	package var children: PaintSequence {
		didSet { version = UUID() }
	}

	package init(
		id: STNNodeID,
		bounds: STNRect,
		transform: STNAffineTransform,
		opacity: Double,
		clips: Bool,
		radius: Double,
		backdrop: STNBackdropEffect?,
		children: [PaintEntry]
	) {
		self.id = id
		self.bounds = bounds
		self.transform = transform
		self.opacity = opacity
		self.clips = clips
		self.radius = radius
		self.backdrop = backdrop
		self.children = PaintSequence(children)
	}

	package func updating(
		bounds: STNRect,
		transform: STNAffineTransform,
		opacity: Double,
		clips: Bool,
		radius: Double,
		backdrop: STNBackdropEffect?
	) -> Self {
		var result = Self(
			id: id,
			bounds: bounds,
			transform: transform,
			opacity: opacity,
			clips: clips,
			radius: radius,
			backdrop: backdrop,
			children: []
		)
		result.children = children
		return result
	}

	package var requiresExtended: Bool {
		if case .program(let program) = backdrop?.operation, program.outputColor == .extendedLinear {
			return true
		}

		return children.requiresExtended
	}
}
