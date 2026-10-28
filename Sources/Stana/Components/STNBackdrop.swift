import StanaCore
import StanaPrimitives

@MainActor public struct STNBackdrop: STNComponent, PrimitiveComponent {
	@MainActor public struct Properties {
		package var configuration = NodeConfiguration()
		package let transform: Property<STNAffineTransform>
		package let effect: Property<STNBackdropEffect>

		public init(
			effect: some STNPropertyConvertible<STNBackdropEffect>,
			transform: some STNPropertyConvertible<STNAffineTransform> = STNAffineTransform.identity,
			layout: STNLayoutProperties = .init(),
			appearance: STNAppearanceProperties = .init(),
			interaction: STNInteractionProperties = .init(),
			accessibility: STNAccessibilityProperties = .init(),
			lifecycle: STNLifecycleProperties = .init()
		) {
			self.effect = effect.asProperty()
			self.transform = transform.asProperty()
			configuration.style.clip = true
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

	public init(properties: Properties, @STNBuilder content: @escaping () -> STNGroup) {
		self.properties = properties
		self.content = content
	}

	public func makeContent(in context: STNComponentContext) -> STNEmpty {
		return STNEmpty()
	}

	package func mount(in context: MountContext) {
		var configuration = properties.configuration
		configuration.style.retained = true
		configuration.mount(.backdrop, in: context, content: content) { node in
			properties.transform.install(in: context, node: node, dirty: [.compositing, .semantics]) {
				$0.style.transform = $1
			}
			properties.effect.install(in: context, node: node, dirty: .compositing) { $0.backdropEffect = $1 }
		}
	}
}
