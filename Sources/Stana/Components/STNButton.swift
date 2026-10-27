import StanaCore
import StanaPrimitives

@MainActor public struct STNButton: STNComponent, PrimitiveComponent {
	@MainActor public struct Properties {
		package var configuration = NodeConfiguration()

		public init(
			text: String,
			font: STNFont = .system(),
			foreground: STNColor = .text,
			padding: STNInsets = .init(top: 7, leading: 14, bottom: 7, trailing: 14),
			frame: STNFrame = .init(),
			background: STNColor = .clear,
			isEnabled: Bool = true,
			accessibility: STNAccessibilityProperties = .init(),
			onMount: (@MainActor (STNNodeHandle) -> Void)? = nil,
			onActivate: @escaping @MainActor () -> Void
		) {
			self.init(
				text: Property(text),
				font: font,
				foreground: foreground,
				padding: padding,
				frame: frame,
				background: background,
				isEnabled: Property(isEnabled),
				accessibility: accessibility,
				onMount: onMount,
				onActivate: onActivate
			)
		}

		public init(
			text: String,
			font: STNFont = .system(),
			foreground: STNColor = .text,
			padding: STNInsets = .init(top: 7, leading: 14, bottom: 7, trailing: 14),
			frame: STNFrame = .init(),
			background: STNColor = .clear,
			isEnabled: STNSignal<Bool>,
			accessibility: STNAccessibilityProperties = .init(),
			onMount: (@MainActor (STNNodeHandle) -> Void)? = nil,
			onActivate: @escaping @MainActor () -> Void
		) {
			self.init(
				text: Property(text),
				font: font,
				foreground: foreground,
				padding: padding,
				frame: frame,
				background: background,
				isEnabled: Property(isEnabled),
				accessibility: accessibility,
				onMount: onMount,
				onActivate: onActivate
			)
		}

		public init(
			text: String,
			font: STNFont = .system(),
			foreground: STNColor = .text,
			padding: STNInsets = .init(top: 7, leading: 14, bottom: 7, trailing: 14),
			frame: STNFrame = .init(),
			background: STNColor = .clear,
			isEnabled: STNComputed<Bool>,
			accessibility: STNAccessibilityProperties = .init(),
			onMount: (@MainActor (STNNodeHandle) -> Void)? = nil,
			onActivate: @escaping @MainActor () -> Void
		) {
			self.init(
				text: Property(text),
				font: font,
				foreground: foreground,
				padding: padding,
				frame: frame,
				background: background,
				isEnabled: Property(isEnabled),
				accessibility: accessibility,
				onMount: onMount,
				onActivate: onActivate
			)
		}

		public init(
			text: STNSignal<String>,
			font: STNFont = .system(),
			foreground: STNColor = .text,
			padding: STNInsets = .init(top: 7, leading: 14, bottom: 7, trailing: 14),
			frame: STNFrame = .init(),
			background: STNColor = .clear,
			isEnabled: Bool = true,
			accessibility: STNAccessibilityProperties = .init(),
			onMount: (@MainActor (STNNodeHandle) -> Void)? = nil,
			onActivate: @escaping @MainActor () -> Void
		) {
			self.init(
				text: Property(text),
				font: font,
				foreground: foreground,
				padding: padding,
				frame: frame,
				background: background,
				isEnabled: Property(isEnabled),
				accessibility: accessibility,
				onMount: onMount,
				onActivate: onActivate
			)
		}

		public init(
			text: STNSignal<String>,
			font: STNFont = .system(),
			foreground: STNColor = .text,
			padding: STNInsets = .init(top: 7, leading: 14, bottom: 7, trailing: 14),
			frame: STNFrame = .init(),
			background: STNColor = .clear,
			isEnabled: STNSignal<Bool>,
			accessibility: STNAccessibilityProperties = .init(),
			onMount: (@MainActor (STNNodeHandle) -> Void)? = nil,
			onActivate: @escaping @MainActor () -> Void
		) {
			self.init(
				text: Property(text),
				font: font,
				foreground: foreground,
				padding: padding,
				frame: frame,
				background: background,
				isEnabled: Property(isEnabled),
				accessibility: accessibility,
				onMount: onMount,
				onActivate: onActivate
			)
		}

		public init(
			text: STNSignal<String>,
			font: STNFont = .system(),
			foreground: STNColor = .text,
			padding: STNInsets = .init(top: 7, leading: 14, bottom: 7, trailing: 14),
			frame: STNFrame = .init(),
			background: STNColor = .clear,
			isEnabled: STNComputed<Bool>,
			accessibility: STNAccessibilityProperties = .init(),
			onMount: (@MainActor (STNNodeHandle) -> Void)? = nil,
			onActivate: @escaping @MainActor () -> Void
		) {
			self.init(
				text: Property(text),
				font: font,
				foreground: foreground,
				padding: padding,
				frame: frame,
				background: background,
				isEnabled: Property(isEnabled),
				accessibility: accessibility,
				onMount: onMount,
				onActivate: onActivate
			)
		}

		public init(
			text: STNComputed<String>,
			font: STNFont = .system(),
			foreground: STNColor = .text,
			padding: STNInsets = .init(top: 7, leading: 14, bottom: 7, trailing: 14),
			frame: STNFrame = .init(),
			background: STNColor = .clear,
			isEnabled: Bool = true,
			accessibility: STNAccessibilityProperties = .init(),
			onMount: (@MainActor (STNNodeHandle) -> Void)? = nil,
			onActivate: @escaping @MainActor () -> Void
		) {
			self.init(
				text: Property(text),
				font: font,
				foreground: foreground,
				padding: padding,
				frame: frame,
				background: background,
				isEnabled: Property(isEnabled),
				accessibility: accessibility,
				onMount: onMount,
				onActivate: onActivate
			)
		}

		public init(
			text: STNComputed<String>,
			font: STNFont = .system(),
			foreground: STNColor = .text,
			padding: STNInsets = .init(top: 7, leading: 14, bottom: 7, trailing: 14),
			frame: STNFrame = .init(),
			background: STNColor = .clear,
			isEnabled: STNSignal<Bool>,
			accessibility: STNAccessibilityProperties = .init(),
			onMount: (@MainActor (STNNodeHandle) -> Void)? = nil,
			onActivate: @escaping @MainActor () -> Void
		) {
			self.init(
				text: Property(text),
				font: font,
				foreground: foreground,
				padding: padding,
				frame: frame,
				background: background,
				isEnabled: Property(isEnabled),
				accessibility: accessibility,
				onMount: onMount,
				onActivate: onActivate
			)
		}

		public init(
			text: STNComputed<String>,
			font: STNFont = .system(),
			foreground: STNColor = .text,
			padding: STNInsets = .init(top: 7, leading: 14, bottom: 7, trailing: 14),
			frame: STNFrame = .init(),
			background: STNColor = .clear,
			isEnabled: STNComputed<Bool>,
			accessibility: STNAccessibilityProperties = .init(),
			onMount: (@MainActor (STNNodeHandle) -> Void)? = nil,
			onActivate: @escaping @MainActor () -> Void
		) {
			self.init(
				text: Property(text),
				font: font,
				foreground: foreground,
				padding: padding,
				frame: frame,
				background: background,
				isEnabled: Property(isEnabled),
				accessibility: accessibility,
				onMount: onMount,
				onActivate: onActivate
			)
		}

		private init(
			text: Property<String>,
			font: STNFont = .system(),
			foreground: STNColor = .text,
			padding: STNInsets = .init(top: 7, leading: 14, bottom: 7, trailing: 14),
			frame: STNFrame = .init(),
			background: STNColor = .clear,
			isEnabled: Property<Bool>,
			accessibility: STNAccessibilityProperties = .init(),
			onMount: (@MainActor (STNNodeHandle) -> Void)? = nil,
			onActivate: @escaping @MainActor () -> Void
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
			configuration.onActivate = onActivate
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
