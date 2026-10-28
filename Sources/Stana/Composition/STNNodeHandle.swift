import StanaCore
import StanaPrimitives

@MainActor public struct STNNodeHandle {
	private weak var document: Document?
	public let id: STNNodeID

	package init(document: Document, id: STNNodeID) {
		self.document = document
		self.id = id
	}

	public func requestFocus() throws {
		guard let document else {
			throw STNError.nodeDisposed
		}

		let node = try document.resolve(id)
		guard node.isFocusable, document.isEligible(id) else {
			throw STNError.notFocusable
		}

		document.setFocus(id)
	}

	public func bounds() throws -> STNRect {
		guard let document else {
			throw STNError.nodeDisposed
		}

		return try document.geometry(id)
	}

	/// Last presentation-confirmed bounds, not an assertion about current scanout.
	public func presentationBounds() throws -> STNPresentationBounds? {
		guard let document else { throw STNError.nodeDisposed }
		_ = try document.resolve(id)
		guard let geometry = document.confirmedGeometry, let entry = geometry.entries[id] else { return nil }
		return .init(
			bounds: entry.projectedBounds,
			geometryRevision: geometry.revision,
			acknowledgement: document.presentationAcknowledgement
		)
	}
}
