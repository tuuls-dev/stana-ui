import StanaCore
import StanaPrimitives

@MainActor public struct STNToggle: STNComponent, PrimitiveComponent {
	@MainActor public struct Properties {
		package var configuration = NodeConfiguration()
		package let isOn: STNBinding<Bool>

		public init(
			text: some STNPropertyConvertible<String>,
			isOn: STNBinding<Bool>,
			layout: STNLayoutProperties = .init(),
			textStyle: STNTextProperties = .init(),
			appearance: STNAppearanceProperties = .init(),
			interaction: STNInteractionProperties = .init(),
			accessibility: STNAccessibilityProperties = .init(),
			lifecycle: STNLifecycleProperties = .init()
		) {
			configuration.text = text.asProperty()
			self.isOn = isOn
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
			.toggle,
			in: context,
			configure: { node in
				node.toggleBinding = properties.isOn
				let observation = ValueObservation(read: { properties.isOn.value }, equals: { $0 == $1 }) {
					[weak document = context.session.document, weak node] value in
					guard let node, let document, node.scope.isAlive else {
						return
					}

					node.isOn = value
					document.changed(node, [.paint, .semantics])
				}
				node.scope.own { observation.cancel() }
				ReactiveRuntime.shared.enqueue(observation)
			}
		)
	}
}
