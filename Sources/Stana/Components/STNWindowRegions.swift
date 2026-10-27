import StanaCore
import StanaPrimitives

/// A native move region. Controls, pointer handlers and nested exclusions keep
/// their input; this wrapper does not implement dragging by moving pixels.
@MainActor public struct STNWindowDragRegion: STNComponent, PrimitiveComponent {
	public enum Mode: Sendable {
		case drag, exclude
	}

	public struct Properties: Sendable {
		public var mode: Mode
		public var frame: STNFrame
		public var padding: STNInsets

		public init(mode: Mode = .drag, frame: STNFrame = .init(), padding: STNInsets = 0) {
			self.mode = mode
			self.frame = frame
			self.padding = padding
		}
	}

	private let properties: Properties
	private let content: () -> STNGroup

	public init(properties: Properties = .init(), @STNBuilder content: @escaping () -> STNGroup) {
		self.properties = properties
		self.content = content
	}

	public func makeContent(in context: STNComponentContext) -> STNEmpty {
		return STNEmpty()
	}

	package func mount(in context: MountContext) {
		var configuration = NodeConfiguration()
		configuration.style.frame = properties.frame
		configuration.style.padding = properties.padding
		configuration.style.windowInteraction = properties.mode == .drag ? 1 : -1
		configuration.mount(.box, in: context, content: content)
	}
}

@MainActor public struct STNWindowResizeRegion: STNComponent, PrimitiveComponent {
	public struct Edges: OptionSet, Sendable {
		public let rawValue: Int32

		public init(rawValue: Int32) {
			self.rawValue = rawValue
		}

		public static let top = Self(rawValue: 1), leading = Self(rawValue: 2), bottom = Self(rawValue: 4),
			trailing = Self(rawValue: 8)
	}

	public struct Properties: Sendable {
		public var edges: Edges
		public var frame: STNFrame

		public init(edges: Edges, frame: STNFrame = .init()) {
			self.edges = edges
			self.frame = frame
		}
	}

	private let properties: Properties
	private let content: () -> STNGroup

	public init(properties: Properties, @STNBuilder content: @escaping () -> STNGroup) {
		self.properties = properties
		self.content = content
	}

	public func makeContent(in context: STNComponentContext) -> STNEmpty {
		return STNEmpty()
	}

	package func mount(in context: MountContext) {
		precondition(properties.edges.rawValue > 0 && properties.edges.rawValue & ~15 == 0)
		var configuration = NodeConfiguration()
		configuration.style.frame = properties.frame
		configuration.style.windowInteraction = 16 | properties.edges.rawValue
		configuration.mount(.box, in: context, content: content)
	}
}

/// Insets its content to the unobscured portion of the window. Place this at the
/// surface root; put full-bleed decoration in a sibling Z-stack layer.
@MainActor public struct STNWindowContent: STNComponent, PrimitiveComponent {
	public struct Properties: Sendable {
		public var avoidsChrome: Bool

		public init(avoidsChrome: Bool = true) {
			self.avoidsChrome = avoidsChrome
		}
	}

	private let properties: Properties
	private let content: () -> STNGroup

	public init(properties: Properties = .init(), @STNBuilder content: @escaping () -> STNGroup) {
		self.properties = properties
		self.content = content
	}

	public func makeContent(in context: STNComponentContext) -> STNEmpty {
		return STNEmpty()
	}

	package func mount(in context: MountContext) {
		var configuration = NodeConfiguration()
		configuration.style.frame = .init(maxWidth: .infinity, maxHeight: .infinity)
		configuration.mount(.box, in: context, content: content) { node in
			guard properties.avoidsChrome else {
				return
			}

			let subscription = context.session.safeContentBounds.subscribe {
				[weak node, weak document = context.session.document] bounds in
				guard let node, let document, node.scope.isAlive else {
					return
				}

				let size = document.viewport
				node.style.padding = .init(
					top: max(0, bounds.minY),
					leading: max(0, bounds.minX),
					bottom: max(0, size.height - bounds.maxY),
					trailing: max(0, size.width - bounds.maxX)
				)
				document.changed(node, .all)
			}
			node.scope.own { subscription.cancel() }
		}
	}
}
