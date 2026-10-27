import StanaCore
import StanaPrimitives

@MainActor public struct STNToggle: STNComponent, PrimitiveComponent {
	@MainActor public struct Properties {
		package var configuration = NodeConfiguration()
		package let isOn: STNBinding<Bool>

		public init(
			text: String,
			isOn: STNBinding<Bool>,
			font: STNFont = .system(),
			foreground: STNColor = .text,
			padding: STNInsets = 0,
			frame: STNFrame = .init(),
			background: STNColor = .clear,
			isEnabled: Bool = true,
			accessibility: STNAccessibilityProperties = .init(),
			onMount: (@MainActor (STNNodeHandle) -> Void)? = nil
		) {
			self.init(
				text: Property(text),
				isOn: isOn,
				font: font,
				foreground: foreground,
				padding: padding,
				frame: frame,
				background: background,
				isEnabled: Property(isEnabled),
				accessibility: accessibility,
				onMount: onMount
			)
		}

		public init(
			text: String,
			isOn: STNBinding<Bool>,
			font: STNFont = .system(),
			foreground: STNColor = .text,
			padding: STNInsets = 0,
			frame: STNFrame = .init(),
			background: STNColor = .clear,
			isEnabled: STNSignal<Bool>,
			accessibility: STNAccessibilityProperties = .init(),
			onMount: (@MainActor (STNNodeHandle) -> Void)? = nil
		) {
			self.init(
				text: Property(text),
				isOn: isOn,
				font: font,
				foreground: foreground,
				padding: padding,
				frame: frame,
				background: background,
				isEnabled: Property(isEnabled),
				accessibility: accessibility,
				onMount: onMount
			)
		}

		public init(
			text: String,
			isOn: STNBinding<Bool>,
			font: STNFont = .system(),
			foreground: STNColor = .text,
			padding: STNInsets = 0,
			frame: STNFrame = .init(),
			background: STNColor = .clear,
			isEnabled: STNComputed<Bool>,
			accessibility: STNAccessibilityProperties = .init(),
			onMount: (@MainActor (STNNodeHandle) -> Void)? = nil
		) {
			self.init(
				text: Property(text),
				isOn: isOn,
				font: font,
				foreground: foreground,
				padding: padding,
				frame: frame,
				background: background,
				isEnabled: Property(isEnabled),
				accessibility: accessibility,
				onMount: onMount
			)
		}

		public init(
			text: STNSignal<String>,
			isOn: STNBinding<Bool>,
			font: STNFont = .system(),
			foreground: STNColor = .text,
			padding: STNInsets = 0,
			frame: STNFrame = .init(),
			background: STNColor = .clear,
			isEnabled: Bool = true,
			accessibility: STNAccessibilityProperties = .init(),
			onMount: (@MainActor (STNNodeHandle) -> Void)? = nil
		) {
			self.init(
				text: Property(text),
				isOn: isOn,
				font: font,
				foreground: foreground,
				padding: padding,
				frame: frame,
				background: background,
				isEnabled: Property(isEnabled),
				accessibility: accessibility,
				onMount: onMount
			)
		}

		public init(
			text: STNSignal<String>,
			isOn: STNBinding<Bool>,
			font: STNFont = .system(),
			foreground: STNColor = .text,
			padding: STNInsets = 0,
			frame: STNFrame = .init(),
			background: STNColor = .clear,
			isEnabled: STNSignal<Bool>,
			accessibility: STNAccessibilityProperties = .init(),
			onMount: (@MainActor (STNNodeHandle) -> Void)? = nil
		) {
			self.init(
				text: Property(text),
				isOn: isOn,
				font: font,
				foreground: foreground,
				padding: padding,
				frame: frame,
				background: background,
				isEnabled: Property(isEnabled),
				accessibility: accessibility,
				onMount: onMount
			)
		}

		public init(
			text: STNSignal<String>,
			isOn: STNBinding<Bool>,
			font: STNFont = .system(),
			foreground: STNColor = .text,
			padding: STNInsets = 0,
			frame: STNFrame = .init(),
			background: STNColor = .clear,
			isEnabled: STNComputed<Bool>,
			accessibility: STNAccessibilityProperties = .init(),
			onMount: (@MainActor (STNNodeHandle) -> Void)? = nil
		) {
			self.init(
				text: Property(text),
				isOn: isOn,
				font: font,
				foreground: foreground,
				padding: padding,
				frame: frame,
				background: background,
				isEnabled: Property(isEnabled),
				accessibility: accessibility,
				onMount: onMount
			)
		}

		public init(
			text: STNComputed<String>,
			isOn: STNBinding<Bool>,
			font: STNFont = .system(),
			foreground: STNColor = .text,
			padding: STNInsets = 0,
			frame: STNFrame = .init(),
			background: STNColor = .clear,
			isEnabled: Bool = true,
			accessibility: STNAccessibilityProperties = .init(),
			onMount: (@MainActor (STNNodeHandle) -> Void)? = nil
		) {
			self.init(
				text: Property(text),
				isOn: isOn,
				font: font,
				foreground: foreground,
				padding: padding,
				frame: frame,
				background: background,
				isEnabled: Property(isEnabled),
				accessibility: accessibility,
				onMount: onMount
			)
		}

		public init(
			text: STNComputed<String>,
			isOn: STNBinding<Bool>,
			font: STNFont = .system(),
			foreground: STNColor = .text,
			padding: STNInsets = 0,
			frame: STNFrame = .init(),
			background: STNColor = .clear,
			isEnabled: STNSignal<Bool>,
			accessibility: STNAccessibilityProperties = .init(),
			onMount: (@MainActor (STNNodeHandle) -> Void)? = nil
		) {
			self.init(
				text: Property(text),
				isOn: isOn,
				font: font,
				foreground: foreground,
				padding: padding,
				frame: frame,
				background: background,
				isEnabled: Property(isEnabled),
				accessibility: accessibility,
				onMount: onMount
			)
		}

		public init(
			text: STNComputed<String>,
			isOn: STNBinding<Bool>,
			font: STNFont = .system(),
			foreground: STNColor = .text,
			padding: STNInsets = 0,
			frame: STNFrame = .init(),
			background: STNColor = .clear,
			isEnabled: STNComputed<Bool>,
			accessibility: STNAccessibilityProperties = .init(),
			onMount: (@MainActor (STNNodeHandle) -> Void)? = nil
		) {
			self.init(
				text: Property(text),
				isOn: isOn,
				font: font,
				foreground: foreground,
				padding: padding,
				frame: frame,
				background: background,
				isEnabled: Property(isEnabled),
				accessibility: accessibility,
				onMount: onMount
			)
		}

		private init(
			text: Property<String>,
			isOn: STNBinding<Bool>,
			font: STNFont = .system(),
			foreground: STNColor = .text,
			padding: STNInsets = 0,
			frame: STNFrame = .init(),
			background: STNColor = .clear,
			isEnabled: Property<Bool>,
			accessibility: STNAccessibilityProperties = .init(),
			onMount: (@MainActor (STNNodeHandle) -> Void)? = nil
		) {
			configuration.text = text
			configuration.isEnabled = isEnabled
			configuration.style.font = font
			configuration.style.foreground = foreground
			configuration.style.padding = padding
			configuration.style.frame = frame
			configuration.background = Property(background)
			configuration.accessibility = accessibility
			configuration.onMount = onMount

			self.isOn = isOn
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
