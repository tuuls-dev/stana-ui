import StanaCore
import StanaPrimitives

@MainActor public struct STNButton: STNComponent, PrimitiveComponent {
	@MainActor public struct Properties {
		package var configuration = NodeConfiguration()

		public init(
			text: some STNPropertyConvertible<String>,
			layout: STNLayoutProperties = .init(),
			textStyle: STNTextProperties = .init(),
			appearance: STNAppearanceProperties = .init(),
			interaction: STNInteractionProperties = .init(),
			accessibility: STNAccessibilityProperties = .init(),
			lifecycle: STNLifecycleProperties = .init(),
			onActivate: @escaping @MainActor () -> Void
		) {
			configuration.text = text.asProperty()
			configuration.style.padding = .init(top: 7, leading: 14, bottom: 7, trailing: 14)
			configuration.onActivate = onActivate
			configuration.apply(
				layout: layout,
				textStyle: textStyle,
				appearance: appearance,
				interaction: interaction,
				accessibility: accessibility,
				lifecycle: lifecycle
			)
		}
	}

	private let properties: Properties

	public init(properties: Properties) {
		self.properties = properties
	}

	public func makeContent(in context: STNComponentContext) -> STNEmpty {
		return STNEmpty()
	}

	package func mount(in context: MountContext) {
		properties.configuration.mount(
			.button,
			in: context,
			configure: { node in
			}
		)
	}
}
