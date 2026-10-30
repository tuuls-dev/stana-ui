import StanaCore
import StanaPrimitives

/// Overlays children in declaration order, centered vertically within its padded content rectangle.
@MainActor public struct STNZStack: STNComponent, PrimitiveComponent {
	/// Horizontal alignment resolved using the document's layout direction.
	public enum Alignment: Equatable, Sendable {
		case leading, center, trailing

		package var nodeAlignment: STNAlignment {
			switch self {
			case .leading: .leading
			case .center: .center
			case .trailing: .trailing
			}
		}
	}

	@MainActor public struct Properties {
		package var configuration = NodeConfiguration()

		public init(
			alignment: Alignment = .center,
			layout: STNLayoutProperties = .init(),
			appearance: STNAppearanceProperties = .init(),
			interaction: STNInteractionProperties = .init(),
			accessibility: STNAccessibilityProperties = .init(),
			lifecycle: STNLifecycleProperties = .init()
		) {
			configuration.style.alignment = alignment.nodeAlignment
			configuration.apply(
				layout: layout,
				appearance: appearance,
				interaction: interaction,
				accessibility: accessibility,
				lifecycle: lifecycle
			)
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
		properties.configuration.mount(.zStack, in: context, content: content)
	}
}
