import Foundation
import StanaPrimitives

package enum DrawCommand: Hashable, Sendable {
	case fill(STNRect, STNColor, radius: Double)
	case stroke(STNRect, STNColor, width: Double, radius: Double)
	case text(String, STNRect, STNFont, STNColor, wraps: Bool)
	case image(Data, STNRect)
	case pushClip(STNRect)
	case popClip
	case pushOpacity(Double)
	case popOpacity
}

package struct SceneSnapshot: Sendable {
	package let documentRevision: UInt64
	package let sceneRevision: UInt64
	package let surfaceEpoch: UInt64
	package let damageBaseRevision: UInt64
	package let damage: [STNRect]
	package let commands: [DrawCommand]
	package let size: STNSize
}
