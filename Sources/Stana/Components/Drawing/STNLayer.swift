import StanaCore
import StanaPrimitives

@MainActor public struct STNLayer: STNComponent, PrimitiveComponent {
	@MainActor public struct Properties {
		package var configuration = NodeConfiguration()
		package let transform: Property<STNAffineTransform>

		public init(
			transform: some STNPropertyConvertible<STNAffineTransform> = STNAffineTransform.identity,
			layout: STNLayoutProperties = .init(),
			appearance: STNAppearanceProperties = .init(),
			interaction: STNInteractionProperties = .init(),
			accessibility: STNAccessibilityProperties = .init(),
			lifecycle: STNLifecycleProperties = .init()
		) {
			self.transform = transform.asProperty()
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
		var configuration = properties.configuration
		configuration.style.retained = true
		configuration.mount(.layer, in: context, content: content) { node in
			properties.transform.install(in: context, node: node, dirty: [.compositing, .semantics]) {
				$0.style.transform = $1
			}
		}
	}
}
