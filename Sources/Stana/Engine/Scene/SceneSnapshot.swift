import Foundation
import StanaPrimitives

package enum DrawCommand: Equatable, Sendable {
	case fill(STNRect, STNColor, radius: Double)
	case stroke(STNRect, STNColor, width: Double, radius: Double)
	case text(String, STNRect, STNFont, STNColor, wraps: Bool)
	case image(Data, STNRect)
	case pushClip(STNRect)
	case popClip
	case pushOpacity(Double)
	case popOpacity
	case pushTransform(STNAffineTransform)
	case popTransform
	case pushRoundedClip(STNRect, Double)
}

package struct SceneSnapshot: Sendable {
	package let documentRevision: UInt64
	package let sceneRevision: UInt64
	package let surfaceEpoch: UInt64
	package let damageBaseRevision: UInt64
	package let damage: [STNRect]
	private let referenceCommands: [DrawCommand]
	package let size: STNSize
	package var paint: PaintGroup? = nil
	package var colorMode: STNRenderingColorMode = .automatic
	package var geometry: PresentationGeometry? = nil
	package var planningMilliseconds: Double = -1
	package var targetTimestamp: Double = 0
	package var framePeriod: Double = 0

	package init(
		documentRevision: UInt64,
		sceneRevision: UInt64,
		surfaceEpoch: UInt64,
		damageBaseRevision: UInt64,
		damage: [STNRect],
		commands: [DrawCommand],
		size: STNSize,
		paint: PaintGroup? = nil,
		colorMode: STNRenderingColorMode = .automatic,
		geometry: PresentationGeometry? = nil
	) {
		self.documentRevision = documentRevision
		self.sceneRevision = sceneRevision
		self.surfaceEpoch = surfaceEpoch
		self.damageBaseRevision = damageBaseRevision
		self.damage = damage
		referenceCommands = commands
		self.size = size
		self.paint = paint
		self.colorMode = colorMode
		self.geometry = geometry
	}

	/// Reference interpretation is deliberately lazy: native Metal planning does
	/// not flatten a persistent paint tree on the UI executor for each update.
	package var commands: [DrawCommand] {
		guard let paint else { return referenceCommands }
		var commands: [DrawCommand] = []
		func visit(_ group: PaintGroup) {
			let origin = STNAffineTransform.translation(x: group.bounds.minX, y: group.bounds.minY)
			commands.append(
				.pushTransform(
					origin.concatenating(group.transform)
						.concatenating(.translation(x: -group.bounds.minX, y: -group.bounds.minY))
				)
			)
			if group.clips { commands.append(.pushRoundedClip(group.bounds, group.radius)) }
			commands.append(.pushOpacity(group.opacity))
			for child in group.children {
				switch child {
				case .cpu(let item): commands.append(contentsOf: item.commands)
				case .gpu: break
				case .group(let nested): visit(nested)
				}
			}
			commands.append(.popOpacity)
			if group.clips { commands.append(.popClip) }
			commands.append(.popTransform)
		}
		visit(paint)
		return commands
	}
}
