import Foundation
import StanaPrimitives

package enum NodeKind: String, Sendable {
	case root, group, box, hStack, vStack, zStack, spacer, text, image, button, toggle, textField, scroll, canvas,
		focusScope
}

package struct Dirty: OptionSet, Sendable {
	package let rawValue: UInt8

	package init(rawValue: UInt8) {
		self.rawValue = rawValue
	}

	package static let layout = Self(rawValue: 1)
	package static let paint = Self(rawValue: 2)
	package static let semantics = Self(rawValue: 4)
	package static let all: Self = [.layout, .paint, .semantics]
}

package struct NodeStyle: Equatable, Sendable {
	package init() {}

	package var padding = STNInsets.zero
	package var frame = STNFrame()
	package var alignment = STNAlignment.leading
	package var spacing: Double = 0
	package var background = STNColor.clear
	package var foreground = STNColor.text
	package var borderColor = STNColor.border
	package var borderWidth: Double = 0
	package var cornerRadius: Double = 0
	package var opacity: Double = 1
	package var font = STNFont.system()
	package var clip = false
	package var isEnabled = true
	package var visibility = STNVisibility.visible
	package var inert = false
	package var flex: Double = 0
	package var secure = false
	package var accessibilityLabel: String?
	package var accessibilityHint: String?
	package var heading: Int?
	package var semanticGroup = false
	// 0 inherit, -1 exclude, 1 native move, 16 | edge bits native resize.
	package var windowInteraction: Int32 = 0
}

@MainActor package final class NodeRecord {
	package let id: STNNodeID
	package let kind: NodeKind
	package weak var parent: NodeRecord?
	package var children: [NodeRecord] = []
	package let scope: LifetimeScope
	private weak var ownerScope: LifetimeScope?
	private var ownershipToken: UUID?
	package var style = NodeStyle()
	package var text = ""
	package var placeholder = ""
	package var isOn = false
	package var textBinding: STNBinding<String>?
	package var toggleBinding: STNBinding<Bool>?
	package var imageData: Data?
	package var bounds = STNRect.zero
	package var measured = STNSize.zero
	package var contentSize = STNSize.zero
	package var baseline: Double = 0
	package var scrollOffset = STNPoint.zero
	package var inputVersion: UInt64 = 0
	package var measureVersion: UInt64 = 0
	package var placedMeasureVersion: UInt64?
	package var measureCache: [AnyHashable: STNSize] = [:]
	package var onActivate: (() -> Void)?
	package var onSubmit: (() -> Void)?
	package var onPointerDown: ((STNPointerEvent) -> Void)?
	package var onPointerMove: ((STNPointerEvent) -> Void)?
	package var onPointerUp: ((STNPointerEvent) -> Void)?
	package var onPointerCancel: ((STNPointerEvent) -> Void)?
	package var onPointerDownCapture: ((STNPointerEvent) -> Void)?
	package var onPointerMoveCapture: ((STNPointerEvent) -> Void)?
	package var onPointerUpCapture: ((STNPointerEvent) -> Void)?
	package var canvasCommands: [CanvasCommand] = []

	package init(id: STNNodeID, kind: NodeKind, scope: LifetimeScope) {
		self.id = id
		self.kind = kind
		self.scope = scope
	}

	package func attachLifetime(to owner: LifetimeScope) {
		if let ownershipToken {
			ownerScope?.disown(ownershipToken)
			scope.disown(ownershipToken)
		}

		ownerScope = owner
		ownershipToken = owner.adopt(scope)
	}

	package var isFocusable: Bool {
		[.button, .toggle, .textField].contains(kind) && style.isEnabled && style.visibility == .visible && !style.inert
	}
}

package enum CanvasCommand: Hashable, Sendable {
	case fill(STNRect, STNColor, Double)
	case stroke(STNRect, STNColor, Double, Double)
}

public struct STNMetrics: Sendable, Equatable {
	public package(set) var totalMounts = 0
	public package(set) var mountedNodes = 0
	public package(set) var builderExecutions = 0
	public package(set) var propertyUpdates = 0
	public package(set) var measureCalls = 0
	public package(set) var placedNodes = 0
	public package(set) var recordedPaintItems = 0
	public package(set) var semanticChanges = 0
	public package(set) var logicalCommits = 0

	public init() {}
}

public struct STNNodeSnapshot: Sendable, Equatable {
	public let id: STNNodeID
	public let kind: String
	public let text: String
	public let bounds: STNRect
	public let isFocused: Bool
	public let isOn: Bool
	public let children: [STNNodeID]

	@MainActor package init(_ node: NodeRecord, focused: STNNodeID?) {
		id = node.id
		kind = node.kind.rawValue
		text = node.style.secure ? "<secure>" : node.text
		bounds = node.bounds
		isFocused = node.id == focused
		isOn = node.isOn
		children = node.children.map(\.id)
	}
}

@MainActor package final class Document {
	package let id = UUID()
	package private(set) var nodes: [STNNodeID: NodeRecord] = [:]
	package private(set) var serial: UInt64 = 0
	package private(set) var revision: UInt64 = 0
	package var metrics = STNMetrics()
	package var root: NodeRecord!
	package var dirty: Dirty = .all
	package var focused: STNNodeID?
	package var pressed: STNNodeID?
	package var captured: STNNodeID?
	package var viewport: STNSize
	package var windowBackgroundDragging = false
	package var surfaceBackground = STNColor.background
	package var isClosed = false
	package var dark = false
	package var highContrast = false
	package var direction = STNLayoutDirection.leftToRight
	package var textScale: Double = 1
	package var theme: STNTheme?
	package var onCommit: (() -> Void)?
	package var ensureGeometry: (() -> Void)?
	package var onFocusChanged: ((STNNodeID?) -> Void)?
	package var onDisposed: ((STNNodeID) -> Void)?
	package var onEditingFocusLoss: ((STNNodeID) -> Void)?
	package var onDiagnostic: ((String) -> Void)?
	package var dispatchSnapshots: [STNNodeSnapshot]?
	package private(set) var postMount: [() -> Void] = []

	package init(size: STNSize) {
		viewport = size
		root = create(.root, parent: nil)
	}

	package func create(_ kind: NodeKind, parent: NodeRecord?, scope: LifetimeScope = LifetimeScope()) -> NodeRecord {
		ReactiveRuntime.shared.assertCanMutate("tree mount")
		precondition(!isClosed && nodes.count < 100_000, "Stana: document node budget exceeded or document closed")
		nextRevision(&serial)
		let node = NodeRecord(id: .init(document: id, serial: serial), kind: kind, scope: scope)
		nodes[node.id] = node
		node.parent = parent
		parent?.children.append(node)
		if let parent {
			node.attachLifetime(to: parent.scope)
		}

		metrics.totalMounts += 1
		metrics.mountedNodes += 1
		scope.own { [weak self, weak node] in
			guard let self, let node else {
				return
			}

			self.remove(node)
		}
		changed(node, .all)
		return node
	}

	package func resolve(_ id: STNNodeID) throws -> NodeRecord {
		guard id.document == self.id else {
			throw STNError.wrongDocument
		}

		guard let node = nodes[id], node.scope.isAlive else {
			throw STNError.nodeDisposed
		}

		return node
	}

	package func lookup(_ nativeID: UInt64) -> NodeRecord? {
		nodes[.init(document: id, serial: nativeID)]
	}

	package func changed(_ node: NodeRecord, _ flags: Dirty) {
		guard !isClosed else {
			return
		}

		metrics.propertyUpdates += 1
		dirty.formUnion(flags)
		if flags.contains(.layout) {
			var current: NodeRecord? = node
			while let next = current {
				nextRevision(&next.inputVersion)
				next.measureCache.removeAll()
				current = next.parent
			}
		}

		ReactiveRuntime.shared.scheduleCommit(id: id) { [weak self] in self?.commit() }
	}

	package func invalidateEnvironment(layout: Bool) {
		if layout {
			for node in nodes.values {
				node.measureCache.removeAll()
				nextRevision(&node.inputVersion)
			}
		}

		changed(root, layout ? .all : [.paint, .semantics])
	}

	package func deferMount(_ body: @escaping () -> Void) {
		postMount.append(body)
	}

	package func commit() {
		guard !isClosed else {
			return
		}

		if let focused, !isEligible(focused) {
			setFocus(nil)
			focusNext()
			return
		}

		nextRevision(&revision)
		metrics.logicalCommits += 1
		onCommit?()
		let callbacks = postMount
		postMount.removeAll()
		for callback in callbacks {
			ReactiveRuntime.shared.afterCommit(callback)
		}
	}

	package func remove(_ node: NodeRecord) {
		ReactiveRuntime.shared.assertCanMutate("tree disposal")
		guard nodes[node.id] != nil else {
			return
		}

		let nextFocus = orderedNodes.filter { $0.id != node.id && $0.isFocusable }.map(\.id)
		for child in Array(node.children) {
			remove(child)
		}

		if focused == node.id {
			onEditingFocusLoss?(node.id)
			focused = nil
		}

		if pressed == node.id {
			pressed = nil
		}

		if captured == node.id {
			captured = nil
		}

		node.parent?.children.removeAll { $0 === node }
		nodes.removeValue(forKey: node.id)
		metrics.mountedNodes -= 1
		onDisposed?(node.id)
		node.scope.dispose()
		if let parent = node.parent {
			changed(parent, .all)
		}

		if focused == nil, let next = nextFocus.first(where: { isEligible($0) }) {
			setFocus(next)
		}
	}

	package func reorder(_ parent: NodeRecord, children: [NodeRecord]) throws {
		guard Set(children.map(\.id)).count == children.count,
			Set(children.map(\.id)) == Set(parent.children.map(\.id))
		else {
			throw STNError.invalidStructure
		}

		parent.children = children
		changed(parent, .all)
	}

	package func move(_ id: STNNodeID, to parentID: STNNodeID, at index: Int) throws {
		let node = try resolve(id)
		let destination = try resolve(parentID)
		guard node !== root, let oldParent = node.parent else {
			throw STNError.invalidStructure
		}

		var ancestor: NodeRecord? = destination
		while let candidate = ancestor {
			if candidate === node {
				throw STNError.invalidStructure
			}

			ancestor = candidate.parent
		}

		let count = destination.children.count - (oldParent === destination ? 1 : 0)
		guard index >= 0 && index <= count else {
			throw STNError.invalidStructure
		}

		STNTransaction.perform {
			oldParent.children.removeAll { $0 === node }
			destination.children.insert(node, at: index)
			node.parent = destination
			node.attachLifetime(to: destination.scope)
			changed(oldParent, .all)
			changed(destination, .all)
		}
	}

	package var orderedNodes: [NodeRecord] {
		var result: [NodeRecord] = []
		var stack = [root!]
		while let node = stack.popLast() {
			result.append(node)
			stack.append(contentsOf: node.children.reversed())
		}

		return result
	}

	package func snapshots() throws -> [STNNodeSnapshot] {
		if let dispatchSnapshots {
			return dispatchSnapshots
		}

		guard !ReactiveRuntime.shared.isCollecting else {
			throw STNError.transactionInProgress
		}

		ensureGeometry?()
		return orderedNodes.map { STNNodeSnapshot($0, focused: focused) }
	}

	package func geometry(_ id: STNNodeID) throws -> STNRect {
		if let dispatchSnapshots {
			guard let snapshot = dispatchSnapshots.first(where: { $0.id == id }) else {
				throw STNError.nodeDisposed
			}

			return snapshot.bounds
		}

		guard !ReactiveRuntime.shared.isCollecting else {
			throw STNError.transactionInProgress
		}

		ensureGeometry?()
		return try resolve(id).bounds
	}

	package func close() {
		guard !isClosed else {
			return
		}

		if let focused {
			onEditingFocusLoss?(focused)
		}

		isClosed = true
		focused = nil
		pressed = nil
		captured = nil
		root.scope.dispose()
		onCommit = nil
		ensureGeometry = nil
		onDisposed = nil
		onFocusChanged = nil
		nodes.removeAll()
		metrics.mountedNodes = 0
	}

	package func isEligible(_ id: STNNodeID) -> Bool {
		guard let node = nodes[id], node.isFocusable else {
			return false
		}

		var current: NodeRecord? = node
		while let n = current {
			if !n.scope.isAlive || n.style.visibility != .visible || n.style.inert || !n.style.isEnabled {
				return false
			}

			current = n.parent
		}

		return true
	}

	package func setFocus(_ id: STNNodeID?) {
		guard focused != id else {
			return
		}

		if let id, !isEligible(id) {
			return
		}

		STNTransaction.perform {
			if let old = focused {
				onEditingFocusLoss?(old)
			}

			focused = id
			onFocusChanged?(id)
			if let id {
				scrollIntoView(id)
			}

			dirty.formUnion([.paint, .semantics])
			root.map { changed($0, [.paint, .semantics]) }
		}
	}

	private func scrollIntoView(_ id: STNNodeID) {
		ensureGeometry?()
		guard let node = nodes[id] else {
			return
		}

		var ancestor = node.parent
		while let viewport = ancestor {
			defer {
				ancestor = viewport.parent
			}

			guard viewport.kind == .scroll else {
				continue
			}

			let rect = viewport.bounds.inset(by: viewport.style.padding)
			let bounds = node.bounds
			let dx =
				bounds.minX < rect.minX
				? bounds.minX - rect.minX : bounds.maxX > rect.maxX ? bounds.maxX - rect.maxX : 0
			let dy =
				bounds.minY < rect.minY
				? bounds.minY - rect.minY : bounds.maxY > rect.maxY ? bounds.maxY - rect.maxY : 0
			let old = viewport.scrollOffset
			viewport.scrollOffset = .init(
				x: min(max(0, old.x + dx), max(0, viewport.contentSize.width - rect.size.width)),
				y: min(max(0, old.y + dy), max(0, viewport.contentSize.height - rect.size.height))
			)
			if viewport.scrollOffset != old {
				changed(viewport, .all)
				ensureGeometry?()
			}
		}
	}

	package func focusNext(backward: Bool = false) {
		let eligible = orderedNodes.filter { isEligible($0.id) }.map(\.id)
		guard !eligible.isEmpty else {
			setFocus(nil)
			return
		}

		let index = focused.flatMap { eligible.firstIndex(of: $0) }
		let next =
			index.map { ($0 + (backward ? eligible.count - 1 : 1)) % eligible.count }
			?? (backward ? eligible.count - 1 : 0)
		setFocus(eligible[next])
	}

	package func activate(_ id: STNNodeID) {
		guard let node = nodes[id], isEligible(id) else {
			return
		}

		STNTransaction.perform {
			if node.kind == .toggle {
				node.toggleBinding?.value = !node.isOn
			}

			node.onActivate?()
		}
	}

	package func hitTest(_ point: STNPoint) -> NodeRecord? {
		ensureGeometry?()

		func visit(_ node: NodeRecord, clip: STNRect) -> NodeRecord? {
			guard node.style.visibility == .visible, !node.style.inert, node.style.isEnabled, clip.contains(point)
			else {
				return nil
			}

			let childClip = node.style.clip || node.kind == .scroll ? clip.intersection(node.bounds) : clip
			for child in node.children.reversed() {
				if let hit = visit(child, clip: childClip) {
					return hit
				}
			}

			if node.bounds.contains(point),
				node.isFocusable || node.onPointerDown != nil || node.onPointerMove != nil || node.onPointerUp != nil
					|| node.style.windowInteraction != 0 || (node.kind == .root && windowBackgroundDragging)
			{
				return node
			}

			return nil
		}

		return visit(root, clip: .init(width: viewport.width, height: viewport.height))
	}
}
