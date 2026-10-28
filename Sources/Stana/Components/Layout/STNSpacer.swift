import StanaCore
import StanaPrimitives

@MainActor public struct STNSpacer: STNComponent, PrimitiveComponent {
	@MainActor public struct Properties {
		public let minLength: Double
		public let weight: Double

		public init(minLength: Double = 0, weight: Double = 1) {
			precondition(minLength.isFinite && minLength >= 0 && weight.isFinite && weight > 0)
			self.minLength = minLength
			self.weight = weight
		}
	}

	private let properties: Properties

	public init(properties: Properties = .init()) {
		self.properties = properties
	}

	public func makeContent(in context: STNComponentContext) -> STNEmpty {
		return STNEmpty()
	}

	package func mount(in context: MountContext) {
		var config = NodeConfiguration()
		config.style.flex = properties.weight
		config.style.frame = .init(minWidth: properties.minLength, minHeight: properties.minLength)
		config.mount(.spacer, in: context)
	}
}
