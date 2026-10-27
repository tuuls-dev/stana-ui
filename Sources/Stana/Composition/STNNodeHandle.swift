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
}
