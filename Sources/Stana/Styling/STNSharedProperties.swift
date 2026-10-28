import StanaCore
import StanaPrimitives

/// Reusable overrides. Unspecified fields retain the receiving component’s defaults.
@MainActor public struct STNLayoutProperties {
	package let padding: STNProperty<STNInsets>?
	package let frame: STNProperty<STNFrame>?

	public init(
		padding: (some STNPropertyConvertible<STNInsets>)? = Optional<STNInsets>.none,
		frame: (some STNPropertyConvertible<STNFrame>)? = Optional<STNFrame>.none
	) {
		self.padding = padding?.asProperty()
		self.frame = frame?.asProperty()
	}
}

/// Reusable overrides. Unspecified fields retain the receiving component’s defaults.
@MainActor public struct STNTextProperties {
	package let font: STNProperty<STNFont>?
	package let foreground: STNProperty<STNColor>?

	public init(
		font: (some STNPropertyConvertible<STNFont>)? = Optional<STNFont>.none,
		foreground: (some STNPropertyConvertible<STNColor>)? = Optional<STNColor>.none
	) {
		self.font = font?.asProperty()
		self.foreground = foreground?.asProperty()
	}
}

/// Reusable overrides. Unspecified fields retain the receiving component’s defaults.
@MainActor public struct STNAppearanceProperties {
	package let background: STNProperty<STNColor>?
	package let opacity: STNProperty<Double>?
	package let borderColor: STNProperty<STNColor>?
	package let borderWidth: STNProperty<Double>?
	package let cornerRadius: STNProperty<Double>?
	package let clip: Bool?
	package let visibility: STNVisibility?

	public init(
		background: (some STNPropertyConvertible<STNColor>)? = Optional<STNColor>.none,
		opacity: (some STNPropertyConvertible<Double>)? = Optional<Double>.none,
		borderColor: (some STNPropertyConvertible<STNColor>)? = Optional<STNColor>.none,
		borderWidth: (some STNPropertyConvertible<Double>)? = Optional<Double>.none,
		cornerRadius: (some STNPropertyConvertible<Double>)? = Optional<Double>.none,
		clip: Bool? = nil,
		visibility: STNVisibility? = nil
	) {
		self.background = background?.asProperty()
		self.opacity = opacity?.asProperty()
		self.borderColor = borderColor?.asProperty()
		self.borderWidth = borderWidth?.asProperty()
		self.cornerRadius = cornerRadius?.asProperty()
		self.clip = clip
		self.visibility = visibility
	}
}

/// Reusable overrides. Unspecified fields retain the receiving component’s defaults.
@MainActor public struct STNInteractionProperties {
	package let isEnabled: STNProperty<Bool>?
	package let inert: Bool?
	package let onPointerDown: (@MainActor (STNPointerEvent) -> Void)?
	package let onPointerMove: (@MainActor (STNPointerEvent) -> Void)?
	package let onPointerUp: (@MainActor (STNPointerEvent) -> Void)?
	package let onPointerCancel: (@MainActor (STNPointerEvent) -> Void)?
	package let onPointerDownCapture: (@MainActor (STNPointerEvent) -> Void)?
	package let onPointerMoveCapture: (@MainActor (STNPointerEvent) -> Void)?
	package let onPointerUpCapture: (@MainActor (STNPointerEvent) -> Void)?

	public init(
		isEnabled: (some STNPropertyConvertible<Bool>)? = Optional<Bool>.none,
		inert: Bool? = nil,
		onPointerDown: (@MainActor (STNPointerEvent) -> Void)? = nil,
		onPointerMove: (@MainActor (STNPointerEvent) -> Void)? = nil,
		onPointerUp: (@MainActor (STNPointerEvent) -> Void)? = nil,
		onPointerCancel: (@MainActor (STNPointerEvent) -> Void)? = nil,
		onPointerDownCapture: (@MainActor (STNPointerEvent) -> Void)? = nil,
		onPointerMoveCapture: (@MainActor (STNPointerEvent) -> Void)? = nil,
		onPointerUpCapture: (@MainActor (STNPointerEvent) -> Void)? = nil
	) {
		self.isEnabled = isEnabled?.asProperty()
		self.inert = inert
		self.onPointerDown = onPointerDown
		self.onPointerMove = onPointerMove
		self.onPointerUp = onPointerUp
		self.onPointerCancel = onPointerCancel
		self.onPointerDownCapture = onPointerDownCapture
		self.onPointerMoveCapture = onPointerMoveCapture
		self.onPointerUpCapture = onPointerUpCapture
	}
}

/// Reusable overrides. Unspecified fields retain the receiving component’s defaults.
@MainActor public struct STNLifecycleProperties {
	package let onMount: (@MainActor (STNNodeHandle) -> Void)?

	public init(
		onMount: (@MainActor (STNNodeHandle) -> Void)? = nil
	) {
		self.onMount = onMount
	}
}
