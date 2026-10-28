import StanaCore
import StanaPrimitives

@MainActor public struct STNGPUCanvas: STNComponent, PrimitiveComponent {
	@MainActor public struct Properties {
		package var configuration = NodeConfiguration()
		package let drawing: Property<STNGPUDrawing>
		package var onError: ((STNGPUDiagnostic) -> Void)?

		public init(
			drawing: some STNPropertyConvertible<STNGPUDrawing>,
			layout: STNLayoutProperties = .init(),
			appearance: STNAppearanceProperties = .init(),
			interaction: STNInteractionProperties = .init(),
			accessibility: STNAccessibilityProperties = .init(),
			lifecycle: STNLifecycleProperties = .init(),
			onError: (@MainActor (STNGPUDiagnostic) -> Void)? = nil
		) {
			self.drawing = drawing.asProperty()
			configuration.style.clip = true
			self.onError = onError
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

	public init(properties: Properties) {
		self.properties = properties
	}

	public func makeContent(in context: STNComponentContext) -> STNEmpty {
		return STNEmpty()
	}

	package func mount(in context: MountContext) {
		let configuration = properties.configuration
		configuration.mount(
			.gpuCanvas,
			in: context,
			configure: { node in
				node.onGPUError = properties.onError
				properties.drawing.install(in: context, node: node, dirty: .paint) { $0.gpuDrawing = $1 }
			}
		)
	}
}
