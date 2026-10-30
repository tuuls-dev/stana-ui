import Foundation

public enum STNPresentationAcknowledgement: String, Sendable {
	case confirmed, pending, unknown
}

public struct STNPresentationBounds: Equatable, Sendable {
	public let bounds: STNRect
	public let geometryRevision: UInt64
	public let acknowledgement: STNPresentationAcknowledgement

	package init(bounds: STNRect, geometryRevision: UInt64, acknowledgement: STNPresentationAcknowledgement) {
		self.bounds = bounds
		self.geometryRevision = geometryRevision
		self.acknowledgement = acknowledgement
	}
}

package struct GeometryClip: Equatable, Sendable {
	package let rect: STNRect
	package let localToHost: STNAffineTransform
	package let radius: Double

	package init(rect: STNRect, localToHost: STNAffineTransform, radius: Double) {
		self.rect = rect
		self.localToHost = localToHost
		self.radius = radius
	}

	package func contains(_ hostPoint: STNPoint) -> Bool {
		guard let inverse = localToHost.inverse else { return false }
		let p = inverse.applying(to: hostPoint)
		guard rect.contains(p) else { return false }
		let r = min(radius, rect.size.width / 2, rect.size.height / 2)
		if r <= 0 { return true }
		let x = max(abs(p.x - (rect.minX + rect.size.width / 2)) - (rect.size.width / 2 - r), 0)
		let y = max(abs(p.y - (rect.minY + rect.size.height / 2)) - (rect.size.height / 2 - r), 0)
		return x * x + y * y <= r * r
	}
}

package struct GeometryEntry: Equatable, Sendable {
	package let id: STNNodeID
	package let layoutBounds: STNRect
	package let localToHost: STNAffineTransform
	package let clips: [GeometryClip]
	package let textRevision: UInt64

	package init(
		id: STNNodeID,
		layoutBounds: STNRect,
		localToHost: STNAffineTransform,
		clips: [GeometryClip],
		textRevision: UInt64
	) {
		self.id = id
		self.layoutBounds = layoutBounds
		self.localToHost = localToHost
		self.clips = clips
		self.textRevision = textRevision
	}

	package var projectedBounds: STNRect {
		localToHost.enclosing(.init(width: layoutBounds.size.width, height: layoutBounds.size.height))
	}

	package func contains(_ hostPoint: STNPoint) -> Bool {
		guard let inverse = localToHost.inverse else { return false }
		return STNRect(width: layoutBounds.size.width, height: layoutBounds.size.height)
			.contains(inverse.applying(to: hostPoint))
			&& clips.allSatisfy { $0.contains(hostPoint) }
	}
}

package struct PresentationGeometry: Equatable, Sendable {
	package let revision: UInt64
	package let order: [STNNodeID]
	package let entries: [STNNodeID: GeometryEntry]

	package init(revision: UInt64, order: [STNNodeID], entries: [STNNodeID: GeometryEntry]) {
		self.revision = revision
		self.order = order
		self.entries = entries
	}
}
