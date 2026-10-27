import StanaCore
import StanaPrimitives

public struct STNDrawing: Equatable, Sendable {
	package var commands: [CanvasCommand] = []

	public init() {}

	public mutating func fillRect(_ rect: STNRect, color: STNColor, cornerRadius: Double = 0) {
		precondition(cornerRadius.isFinite && cornerRadius >= 0)
		commands.append(.fill(rect, color, cornerRadius))
	}

	public mutating func strokeRect(_ rect: STNRect, color: STNColor, width: Double = 1, cornerRadius: Double = 0) {
		precondition(width.isFinite && width >= 0 && cornerRadius.isFinite && cornerRadius >= 0)
		commands.append(.stroke(rect, color, width, cornerRadius))
	}
}

@MainActor public struct STNCanvas: STNComponent, PrimitiveComponent {
	@MainActor public struct Properties {
		package var configuration = NodeConfiguration()
		package let drawing: Property<STNDrawing>

		public init(drawing: STNDrawing, frame: STNFrame = .init(), accessibility: STNAccessibilityProperties = .init())
		{
			self.drawing = Property(drawing)
			configuration.style.frame = frame
			configuration.accessibility = accessibility
		}

		public init(
			drawing: STNSignal<STNDrawing>,
			frame: STNFrame = .init(),
			accessibility: STNAccessibilityProperties = .init()
		) {
			self.drawing = Property(drawing)
			configuration.style.frame = frame
			configuration.accessibility = accessibility
		}

		public init(
			drawing: STNComputed<STNDrawing>,
			frame: STNFrame = .init(),
			accessibility: STNAccessibilityProperties = .init()
		) {
			self.drawing = Property(drawing)
			configuration.style.frame = frame
			configuration.accessibility = accessibility
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
		var configuration = properties.configuration
		configuration.style.clip = true
		configuration.mount(
			.canvas,
			in: context,
			configure: { node in
				properties.drawing.install(in: context, node: node, dirty: .paint) { $0.canvasCommands = $1.commands }
			}
		)
	}
}
