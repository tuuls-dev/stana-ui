import StanaCore
import StanaPrimitives

@MainActor public struct STNHStack: STNComponent, PrimitiveComponent {
	@MainActor public struct Properties {
		package var configuration = NodeConfiguration()

		public init(
			alignment: STNAlignment = .leading,
			spacing: Double = 0,
			layout: STNLayoutProperties = .init(),
			appearance: STNAppearanceProperties = .init(),
			interaction: STNInteractionProperties = .init(),
			accessibility: STNAccessibilityProperties = .init(),
			lifecycle: STNLifecycleProperties = .init()
		) {
			precondition(spacing.isFinite && spacing >= 0)
			configuration.style.alignment = alignment
			configuration.style.spacing = spacing
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
		properties.configuration.mount(.hStack, in: context, content: content)
	}
}
