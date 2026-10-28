import StanaCore
import StanaPrimitives

public enum STNAccessibilityRole: String, Sendable {
	case window, group, heading, staticText, button, checkBox, textField, image, scrollArea
}

public struct STNSemanticSnapshot: Equatable, Sendable {
	public let revision: UInt64
	public let nodes: [STNSemanticNode]
}

public struct STNSemanticNode: Equatable, Sendable {
	public let id: STNSemanticID
	public let owner: STNNodeID
	public let parent: STNSemanticID?
	public let role: STNAccessibilityRole
	public let label: String
	public let hint: String?
	public let value: String?
	public let bounds: STNRect
	public let isDisabled: Bool
	public let isFocused: Bool
	public let isOffscreen: Bool
	public let isSecure: Bool
	public let isReadOnly: Bool
	public let headingLevel: Int?
	public package(set) var geometryRevision: UInt64? = nil
	public package(set) var geometryAcknowledgement: STNPresentationAcknowledgement = .confirmed
}

@MainActor package protocol AccessibilityBridge: AnyObject {
	func publish(_ snapshot: STNSemanticSnapshot)

	func detach()
}

@MainActor package final class SemanticProjection {
	let document: Document
	private var previous: [STNSemanticID: STNSemanticNode] = [:]

	package init(document: Document) {
		self.document = document
	}

	package func snapshot() -> STNSemanticSnapshot {
		if document.isClosed {
			document.metrics.semanticChanges += previous.count
			previous.removeAll()
			return .init(revision: document.revision, nodes: [])
		}

		var result: [STNSemanticNode] = []

		func visit(_ node: NodeRecord, parent: STNSemanticID?, clip: STNRect, disabled: Bool) {
			guard node.style.visibility == .visible else {
				return
			}

			let role: STNAccessibilityRole?
			switch node.kind {
			case .root: role = .window
			case .text: role = node.style.heading == nil ? .staticText : .heading
			case .button: role = .button
			case .toggle: role = .checkBox
			case .textField: role = .textField
			case .image, .canvas: role = node.style.accessibilityLabel == nil ? nil : .image
			case .scroll: role = .scrollArea
			case .focusScope: role = .group
			default: role = node.style.semanticGroup ? .group : nil
			}

			let unavailable = disabled || !node.style.isEnabled || node.style.inert
			let geometry = document.usesPresentationGeometry ? document.confirmedGeometry?.entries[node.id] : nil
			let projectedBounds = document.usesPresentationGeometry ? (geometry?.projectedBounds ?? .zero) : node.bounds
			let clipVisible =
				geometry?.clips
				.allSatisfy {
					projectedBounds.intersects($0.localToHost.enclosing($0.rect))
				} ?? true
			if let role {
				result.append(
					.init(
						id: STNSemanticID(owner: node.id),
						owner: node.id,
						parent: parent,
						role: role,
						label: node.style.accessibilityLabel
							?? (node.kind == .textField ? node.placeholder : node.text),
						hint: node.style.accessibilityHint,
						value: node.style.secure
							? nil
							: (node.kind == .textField
								? node.text : node.kind == .toggle ? (node.isOn ? "1" : "0") : nil),
						bounds: projectedBounds,
						isDisabled: unavailable,
						isFocused: document.focused == node.id,
						isOffscreen: !projectedBounds.intersects(
							.init(width: document.viewport.width, height: document.viewport.height)
						)
							|| !clipVisible
							|| (document.usesPresentationGeometry && geometry?.localToHost.inverse == nil),
						isSecure: node.style.secure,
						isReadOnly: node.style.isReadOnly,
						headingLevel: node.style.heading,
						geometryRevision: document.usesPresentationGeometry
							? document.confirmedGeometry?.revision : document.revision,
						geometryAcknowledgement: document.usesPresentationGeometry
							? document.presentationAcknowledgement : .confirmed
					)
				)
			}

			let nextClip = node.style.clip || node.kind == .scroll ? clip.intersection(node.bounds) : clip
			for child in node.children {
				visit(
					child,
					parent: role == nil ? parent : STNSemanticID(owner: node.id),
					clip: nextClip,
					disabled: unavailable
				)
			}
		}

		visit(
			document.root,
			parent: nil,
			clip: .init(width: document.viewport.width, height: document.viewport.height),
			disabled: false
		)
		let next = Dictionary(uniqueKeysWithValues: result.map { ($0.id, $0) })
		document.metrics.semanticChanges += next.filter { previous[$0.key] != $0.value }.count
		document.metrics.semanticChanges += previous.keys.filter { next[$0] == nil }.count
		previous = next
		document.dirty.remove(.semantics)
		return .init(revision: document.revision, nodes: result)
	}
}
