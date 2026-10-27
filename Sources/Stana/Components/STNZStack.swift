import StanaCore
import StanaPrimitives

@MainActor public struct STNZStack: STNComponent, PrimitiveComponent {
	@MainActor public struct Properties {
		package var configuration = NodeConfiguration()

		public init(
			alignment: STNAlignment = .leading,
			spacing: Double = 0,
			padding: STNInsets = 0,
			frame: STNFrame = .init(),
			background: STNColor = .clear,
			cornerRadius: Double = 0,
			borderWidth: Double = 0,
			borderColor: STNColor = .border,
			clip: Bool = false,
			opacity: Double = 1,
			visibility: STNVisibility = .visible,
			isEnabled: Bool = true,
			inert: Bool = false,
			accessibility: STNAccessibilityProperties = .init(),
			onPointerDown: (@MainActor (STNPointerEvent) -> Void)? = nil,
			onPointerMove: (@MainActor (STNPointerEvent) -> Void)? = nil,
			onPointerUp: (@MainActor (STNPointerEvent) -> Void)? = nil,
			onPointerCancel: (@MainActor (STNPointerEvent) -> Void)? = nil,
			onPointerDownCapture: (@MainActor (STNPointerEvent) -> Void)? = nil,
			onPointerMoveCapture: (@MainActor (STNPointerEvent) -> Void)? = nil,
			onPointerUpCapture: (@MainActor (STNPointerEvent) -> Void)? = nil,
			onMount: (@MainActor (STNNodeHandle) -> Void)? = nil
		) {
			self.init(
				alignment: alignment,
				spacing: spacing,
				padding: padding,
				frame: frame,
				background: Property(background),
				cornerRadius: cornerRadius,
				borderWidth: borderWidth,
				borderColor: borderColor,
				clip: clip,
				opacity: Property(opacity),
				visibility: visibility,
				isEnabled: isEnabled,
				inert: inert,
				accessibility: accessibility,
				onPointerDown: onPointerDown,
				onPointerMove: onPointerMove,
				onPointerUp: onPointerUp,
				onPointerCancel: onPointerCancel,
				onPointerDownCapture: onPointerDownCapture,
				onPointerMoveCapture: onPointerMoveCapture,
				onPointerUpCapture: onPointerUpCapture,
				onMount: onMount
			)
		}

		public init(
			alignment: STNAlignment = .leading,
			spacing: Double = 0,
			padding: STNInsets = 0,
			frame: STNFrame = .init(),
			background: STNColor = .clear,
			cornerRadius: Double = 0,
			borderWidth: Double = 0,
			borderColor: STNColor = .border,
			clip: Bool = false,
			opacity: STNSignal<Double>,
			visibility: STNVisibility = .visible,
			isEnabled: Bool = true,
			inert: Bool = false,
			accessibility: STNAccessibilityProperties = .init(),
			onPointerDown: (@MainActor (STNPointerEvent) -> Void)? = nil,
			onPointerMove: (@MainActor (STNPointerEvent) -> Void)? = nil,
			onPointerUp: (@MainActor (STNPointerEvent) -> Void)? = nil,
			onPointerCancel: (@MainActor (STNPointerEvent) -> Void)? = nil,
			onPointerDownCapture: (@MainActor (STNPointerEvent) -> Void)? = nil,
			onPointerMoveCapture: (@MainActor (STNPointerEvent) -> Void)? = nil,
			onPointerUpCapture: (@MainActor (STNPointerEvent) -> Void)? = nil,
			onMount: (@MainActor (STNNodeHandle) -> Void)? = nil
		) {
			self.init(
				alignment: alignment,
				spacing: spacing,
				padding: padding,
				frame: frame,
				background: Property(background),
				cornerRadius: cornerRadius,
				borderWidth: borderWidth,
				borderColor: borderColor,
				clip: clip,
				opacity: Property(opacity),
				visibility: visibility,
				isEnabled: isEnabled,
				inert: inert,
				accessibility: accessibility,
				onPointerDown: onPointerDown,
				onPointerMove: onPointerMove,
				onPointerUp: onPointerUp,
				onPointerCancel: onPointerCancel,
				onPointerDownCapture: onPointerDownCapture,
				onPointerMoveCapture: onPointerMoveCapture,
				onPointerUpCapture: onPointerUpCapture,
				onMount: onMount
			)
		}

		public init(
			alignment: STNAlignment = .leading,
			spacing: Double = 0,
			padding: STNInsets = 0,
			frame: STNFrame = .init(),
			background: STNColor = .clear,
			cornerRadius: Double = 0,
			borderWidth: Double = 0,
			borderColor: STNColor = .border,
			clip: Bool = false,
			opacity: STNComputed<Double>,
			visibility: STNVisibility = .visible,
			isEnabled: Bool = true,
			inert: Bool = false,
			accessibility: STNAccessibilityProperties = .init(),
			onPointerDown: (@MainActor (STNPointerEvent) -> Void)? = nil,
			onPointerMove: (@MainActor (STNPointerEvent) -> Void)? = nil,
			onPointerUp: (@MainActor (STNPointerEvent) -> Void)? = nil,
			onPointerCancel: (@MainActor (STNPointerEvent) -> Void)? = nil,
			onPointerDownCapture: (@MainActor (STNPointerEvent) -> Void)? = nil,
			onPointerMoveCapture: (@MainActor (STNPointerEvent) -> Void)? = nil,
			onPointerUpCapture: (@MainActor (STNPointerEvent) -> Void)? = nil,
			onMount: (@MainActor (STNNodeHandle) -> Void)? = nil
		) {
			self.init(
				alignment: alignment,
				spacing: spacing,
				padding: padding,
				frame: frame,
				background: Property(background),
				cornerRadius: cornerRadius,
				borderWidth: borderWidth,
				borderColor: borderColor,
				clip: clip,
				opacity: Property(opacity),
				visibility: visibility,
				isEnabled: isEnabled,
				inert: inert,
				accessibility: accessibility,
				onPointerDown: onPointerDown,
				onPointerMove: onPointerMove,
				onPointerUp: onPointerUp,
				onPointerCancel: onPointerCancel,
				onPointerDownCapture: onPointerDownCapture,
				onPointerMoveCapture: onPointerMoveCapture,
				onPointerUpCapture: onPointerUpCapture,
				onMount: onMount
			)
		}

		public init(
			alignment: STNAlignment = .leading,
			spacing: Double = 0,
			padding: STNInsets = 0,
			frame: STNFrame = .init(),
			background: STNSignal<STNColor>,
			cornerRadius: Double = 0,
			borderWidth: Double = 0,
			borderColor: STNColor = .border,
			clip: Bool = false,
			opacity: Double = 1,
			visibility: STNVisibility = .visible,
			isEnabled: Bool = true,
			inert: Bool = false,
			accessibility: STNAccessibilityProperties = .init(),
			onPointerDown: (@MainActor (STNPointerEvent) -> Void)? = nil,
			onPointerMove: (@MainActor (STNPointerEvent) -> Void)? = nil,
			onPointerUp: (@MainActor (STNPointerEvent) -> Void)? = nil,
			onPointerCancel: (@MainActor (STNPointerEvent) -> Void)? = nil,
			onPointerDownCapture: (@MainActor (STNPointerEvent) -> Void)? = nil,
			onPointerMoveCapture: (@MainActor (STNPointerEvent) -> Void)? = nil,
			onPointerUpCapture: (@MainActor (STNPointerEvent) -> Void)? = nil,
			onMount: (@MainActor (STNNodeHandle) -> Void)? = nil
		) {
			self.init(
				alignment: alignment,
				spacing: spacing,
				padding: padding,
				frame: frame,
				background: Property(background),
				cornerRadius: cornerRadius,
				borderWidth: borderWidth,
				borderColor: borderColor,
				clip: clip,
				opacity: Property(opacity),
				visibility: visibility,
				isEnabled: isEnabled,
				inert: inert,
				accessibility: accessibility,
				onPointerDown: onPointerDown,
				onPointerMove: onPointerMove,
				onPointerUp: onPointerUp,
				onPointerCancel: onPointerCancel,
				onPointerDownCapture: onPointerDownCapture,
				onPointerMoveCapture: onPointerMoveCapture,
				onPointerUpCapture: onPointerUpCapture,
				onMount: onMount
			)
		}

		public init(
			alignment: STNAlignment = .leading,
			spacing: Double = 0,
			padding: STNInsets = 0,
			frame: STNFrame = .init(),
			background: STNSignal<STNColor>,
			cornerRadius: Double = 0,
			borderWidth: Double = 0,
			borderColor: STNColor = .border,
			clip: Bool = false,
			opacity: STNSignal<Double>,
			visibility: STNVisibility = .visible,
			isEnabled: Bool = true,
			inert: Bool = false,
			accessibility: STNAccessibilityProperties = .init(),
			onPointerDown: (@MainActor (STNPointerEvent) -> Void)? = nil,
			onPointerMove: (@MainActor (STNPointerEvent) -> Void)? = nil,
			onPointerUp: (@MainActor (STNPointerEvent) -> Void)? = nil,
			onPointerCancel: (@MainActor (STNPointerEvent) -> Void)? = nil,
			onPointerDownCapture: (@MainActor (STNPointerEvent) -> Void)? = nil,
			onPointerMoveCapture: (@MainActor (STNPointerEvent) -> Void)? = nil,
			onPointerUpCapture: (@MainActor (STNPointerEvent) -> Void)? = nil,
			onMount: (@MainActor (STNNodeHandle) -> Void)? = nil
		) {
			self.init(
				alignment: alignment,
				spacing: spacing,
				padding: padding,
				frame: frame,
				background: Property(background),
				cornerRadius: cornerRadius,
				borderWidth: borderWidth,
				borderColor: borderColor,
				clip: clip,
				opacity: Property(opacity),
				visibility: visibility,
				isEnabled: isEnabled,
				inert: inert,
				accessibility: accessibility,
				onPointerDown: onPointerDown,
				onPointerMove: onPointerMove,
				onPointerUp: onPointerUp,
				onPointerCancel: onPointerCancel,
				onPointerDownCapture: onPointerDownCapture,
				onPointerMoveCapture: onPointerMoveCapture,
				onPointerUpCapture: onPointerUpCapture,
				onMount: onMount
			)
		}

		public init(
			alignment: STNAlignment = .leading,
			spacing: Double = 0,
			padding: STNInsets = 0,
			frame: STNFrame = .init(),
			background: STNSignal<STNColor>,
			cornerRadius: Double = 0,
			borderWidth: Double = 0,
			borderColor: STNColor = .border,
			clip: Bool = false,
			opacity: STNComputed<Double>,
			visibility: STNVisibility = .visible,
			isEnabled: Bool = true,
			inert: Bool = false,
			accessibility: STNAccessibilityProperties = .init(),
			onPointerDown: (@MainActor (STNPointerEvent) -> Void)? = nil,
			onPointerMove: (@MainActor (STNPointerEvent) -> Void)? = nil,
			onPointerUp: (@MainActor (STNPointerEvent) -> Void)? = nil,
			onPointerCancel: (@MainActor (STNPointerEvent) -> Void)? = nil,
			onPointerDownCapture: (@MainActor (STNPointerEvent) -> Void)? = nil,
			onPointerMoveCapture: (@MainActor (STNPointerEvent) -> Void)? = nil,
			onPointerUpCapture: (@MainActor (STNPointerEvent) -> Void)? = nil,
			onMount: (@MainActor (STNNodeHandle) -> Void)? = nil
		) {
			self.init(
				alignment: alignment,
				spacing: spacing,
				padding: padding,
				frame: frame,
				background: Property(background),
				cornerRadius: cornerRadius,
				borderWidth: borderWidth,
				borderColor: borderColor,
				clip: clip,
				opacity: Property(opacity),
				visibility: visibility,
				isEnabled: isEnabled,
				inert: inert,
				accessibility: accessibility,
				onPointerDown: onPointerDown,
				onPointerMove: onPointerMove,
				onPointerUp: onPointerUp,
				onPointerCancel: onPointerCancel,
				onPointerDownCapture: onPointerDownCapture,
				onPointerMoveCapture: onPointerMoveCapture,
				onPointerUpCapture: onPointerUpCapture,
				onMount: onMount
			)
		}

		public init(
			alignment: STNAlignment = .leading,
			spacing: Double = 0,
			padding: STNInsets = 0,
			frame: STNFrame = .init(),
			background: STNComputed<STNColor>,
			cornerRadius: Double = 0,
			borderWidth: Double = 0,
			borderColor: STNColor = .border,
			clip: Bool = false,
			opacity: Double = 1,
			visibility: STNVisibility = .visible,
			isEnabled: Bool = true,
			inert: Bool = false,
			accessibility: STNAccessibilityProperties = .init(),
			onPointerDown: (@MainActor (STNPointerEvent) -> Void)? = nil,
			onPointerMove: (@MainActor (STNPointerEvent) -> Void)? = nil,
			onPointerUp: (@MainActor (STNPointerEvent) -> Void)? = nil,
			onPointerCancel: (@MainActor (STNPointerEvent) -> Void)? = nil,
			onPointerDownCapture: (@MainActor (STNPointerEvent) -> Void)? = nil,
			onPointerMoveCapture: (@MainActor (STNPointerEvent) -> Void)? = nil,
			onPointerUpCapture: (@MainActor (STNPointerEvent) -> Void)? = nil,
			onMount: (@MainActor (STNNodeHandle) -> Void)? = nil
		) {
			self.init(
				alignment: alignment,
				spacing: spacing,
				padding: padding,
				frame: frame,
				background: Property(background),
				cornerRadius: cornerRadius,
				borderWidth: borderWidth,
				borderColor: borderColor,
				clip: clip,
				opacity: Property(opacity),
				visibility: visibility,
				isEnabled: isEnabled,
				inert: inert,
				accessibility: accessibility,
				onPointerDown: onPointerDown,
				onPointerMove: onPointerMove,
				onPointerUp: onPointerUp,
				onPointerCancel: onPointerCancel,
				onPointerDownCapture: onPointerDownCapture,
				onPointerMoveCapture: onPointerMoveCapture,
				onPointerUpCapture: onPointerUpCapture,
				onMount: onMount
			)
		}

		public init(
			alignment: STNAlignment = .leading,
			spacing: Double = 0,
			padding: STNInsets = 0,
			frame: STNFrame = .init(),
			background: STNComputed<STNColor>,
			cornerRadius: Double = 0,
			borderWidth: Double = 0,
			borderColor: STNColor = .border,
			clip: Bool = false,
			opacity: STNSignal<Double>,
			visibility: STNVisibility = .visible,
			isEnabled: Bool = true,
			inert: Bool = false,
			accessibility: STNAccessibilityProperties = .init(),
			onPointerDown: (@MainActor (STNPointerEvent) -> Void)? = nil,
			onPointerMove: (@MainActor (STNPointerEvent) -> Void)? = nil,
			onPointerUp: (@MainActor (STNPointerEvent) -> Void)? = nil,
			onPointerCancel: (@MainActor (STNPointerEvent) -> Void)? = nil,
			onPointerDownCapture: (@MainActor (STNPointerEvent) -> Void)? = nil,
			onPointerMoveCapture: (@MainActor (STNPointerEvent) -> Void)? = nil,
			onPointerUpCapture: (@MainActor (STNPointerEvent) -> Void)? = nil,
			onMount: (@MainActor (STNNodeHandle) -> Void)? = nil
		) {
			self.init(
				alignment: alignment,
				spacing: spacing,
				padding: padding,
				frame: frame,
				background: Property(background),
				cornerRadius: cornerRadius,
				borderWidth: borderWidth,
				borderColor: borderColor,
				clip: clip,
				opacity: Property(opacity),
				visibility: visibility,
				isEnabled: isEnabled,
				inert: inert,
				accessibility: accessibility,
				onPointerDown: onPointerDown,
				onPointerMove: onPointerMove,
				onPointerUp: onPointerUp,
				onPointerCancel: onPointerCancel,
				onPointerDownCapture: onPointerDownCapture,
				onPointerMoveCapture: onPointerMoveCapture,
				onPointerUpCapture: onPointerUpCapture,
				onMount: onMount
			)
		}

		public init(
			alignment: STNAlignment = .leading,
			spacing: Double = 0,
			padding: STNInsets = 0,
			frame: STNFrame = .init(),
			background: STNComputed<STNColor>,
			cornerRadius: Double = 0,
			borderWidth: Double = 0,
			borderColor: STNColor = .border,
			clip: Bool = false,
			opacity: STNComputed<Double>,
			visibility: STNVisibility = .visible,
			isEnabled: Bool = true,
			inert: Bool = false,
			accessibility: STNAccessibilityProperties = .init(),
			onPointerDown: (@MainActor (STNPointerEvent) -> Void)? = nil,
			onPointerMove: (@MainActor (STNPointerEvent) -> Void)? = nil,
			onPointerUp: (@MainActor (STNPointerEvent) -> Void)? = nil,
			onPointerCancel: (@MainActor (STNPointerEvent) -> Void)? = nil,
			onPointerDownCapture: (@MainActor (STNPointerEvent) -> Void)? = nil,
			onPointerMoveCapture: (@MainActor (STNPointerEvent) -> Void)? = nil,
			onPointerUpCapture: (@MainActor (STNPointerEvent) -> Void)? = nil,
			onMount: (@MainActor (STNNodeHandle) -> Void)? = nil
		) {
			self.init(
				alignment: alignment,
				spacing: spacing,
				padding: padding,
				frame: frame,
				background: Property(background),
				cornerRadius: cornerRadius,
				borderWidth: borderWidth,
				borderColor: borderColor,
				clip: clip,
				opacity: Property(opacity),
				visibility: visibility,
				isEnabled: isEnabled,
				inert: inert,
				accessibility: accessibility,
				onPointerDown: onPointerDown,
				onPointerMove: onPointerMove,
				onPointerUp: onPointerUp,
				onPointerCancel: onPointerCancel,
				onPointerDownCapture: onPointerDownCapture,
				onPointerMoveCapture: onPointerMoveCapture,
				onPointerUpCapture: onPointerUpCapture,
				onMount: onMount
			)
		}

		private init(
			alignment: STNAlignment = .leading,
			spacing: Double = 0,
			padding: STNInsets = 0,
			frame: STNFrame = .init(),
			background: Property<STNColor>,
			cornerRadius: Double = 0,
			borderWidth: Double = 0,
			borderColor: STNColor = .border,
			clip: Bool = false,
			opacity: Property<Double>,
			visibility: STNVisibility = .visible,
			isEnabled: Bool = true,
			inert: Bool = false,
			accessibility: STNAccessibilityProperties = .init(),
			onPointerDown: (@MainActor (STNPointerEvent) -> Void)? = nil,
			onPointerMove: (@MainActor (STNPointerEvent) -> Void)? = nil,
			onPointerUp: (@MainActor (STNPointerEvent) -> Void)? = nil,
			onPointerCancel: (@MainActor (STNPointerEvent) -> Void)? = nil,
			onPointerDownCapture: (@MainActor (STNPointerEvent) -> Void)? = nil,
			onPointerMoveCapture: (@MainActor (STNPointerEvent) -> Void)? = nil,
			onPointerUpCapture: (@MainActor (STNPointerEvent) -> Void)? = nil,
			onMount: (@MainActor (STNNodeHandle) -> Void)? = nil
		) {
			precondition(
				cornerRadius.isFinite && cornerRadius >= 0 && borderWidth.isFinite && borderWidth >= 0
					&& spacing.isFinite && spacing >= 0
			)
			configuration.style.padding = padding
			configuration.style.frame = frame
			configuration.style.alignment = alignment
			configuration.style.spacing = spacing
			configuration.style.cornerRadius = cornerRadius
			configuration.style.borderWidth = borderWidth
			configuration.style.borderColor = borderColor
			configuration.style.clip = clip
			configuration.style.visibility = visibility
			configuration.style.inert = inert
			configuration.background = background
			configuration.opacity = opacity
			configuration.isEnabled = Property(isEnabled)
			configuration.accessibility = accessibility
			configuration.onPointerDown = onPointerDown
			configuration.onPointerMove = onPointerMove
			configuration.onPointerUp = onPointerUp
			configuration.onMount = onMount
			configuration.onPointerCancel = onPointerCancel
			configuration.onPointerDownCapture = onPointerDownCapture
			configuration.onPointerMoveCapture = onPointerMoveCapture
			configuration.onPointerUpCapture = onPointerUpCapture
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
		properties.configuration.mount(.zStack, in: context, content: content)
	}
}
