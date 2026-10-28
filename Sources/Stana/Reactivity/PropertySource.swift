import StanaCore
import StanaPrimitives

/// A read-only input accepted by reactive Stana properties. Conversion does not read reactive state.
@MainActor public protocol STNPropertyConvertible<Value> {
	associatedtype Value

	func asProperty() -> STNProperty<Value>
}

/// An erased constant or reactive input. Subscriptions belong to the mounted component, not this value.
@MainActor public struct STNProperty<Value>: STNPropertyConvertible {
	package let read: () -> Value
	package let reactive: Bool

	public init(_ value: Value) {
		read = { value }
		reactive = false
	}

	public init(_ signal: STNSignal<Value>) {
		read = { signal.value }
		reactive = true
	}

	public init(_ computed: STNComputed<Value>) {
		read = { computed.value }
		reactive = true
	}

	public func asProperty() -> STNProperty<Value> {
		self
	}
}

package typealias Property<Value> = STNProperty<Value>

extension STNProperty where Value: Equatable {
	package func install(
		in context: MountContext,
		node: NodeRecord,
		dirty: Dirty,
		set: @escaping (NodeRecord, Value) -> Void
	) {
		if !reactive {
			set(node, read())
			return
		}

		let observation = ValueObservation(read: read, equals: { $0 == $1 }) {
			[weak document = context.session.document, weak node] value in
			guard let document, let node, node.scope.isAlive else {
				return
			}

			set(node, value)
			document.changed(node, dirty)
		}
		node.scope.own { observation.cancel() }
		ReactiveRuntime.shared.enqueue(observation)
	}
}

@MainActor package struct NodeConfiguration {
	var style = NodeStyle()
	var font: Property<STNFont>?
	var foreground: Property<STNColor>?
	var padding: Property<STNInsets>?
	var frame: Property<STNFrame>?
	var borderColor: Property<STNColor>?
	var borderWidth: Property<Double>?
	var cornerRadius: Property<Double>?

	var text = Property("")
	var background = Property(STNColor.clear)
	var opacity = Property(1.0)
	var isEnabled = Property(true)
	var accessibility = STNAccessibilityProperties()
	var onMount: (@MainActor (STNNodeHandle) -> Void)?
	var onActivate: (@MainActor () -> Void)?
	var onSubmit: (@MainActor () -> Void)?
	var onPointerDown: (@MainActor (STNPointerEvent) -> Void)?
	var onPointerMove: (@MainActor (STNPointerEvent) -> Void)?
	var onPointerUp: (@MainActor (STNPointerEvent) -> Void)?
	var onPointerCancel: (@MainActor (STNPointerEvent) -> Void)?
	var onPointerDownCapture: (@MainActor (STNPointerEvent) -> Void)?
	var onPointerMoveCapture: (@MainActor (STNPointerEvent) -> Void)?
	var onPointerUpCapture: (@MainActor (STNPointerEvent) -> Void)?

	mutating func apply(
		layout: STNLayoutProperties,
		textStyle: STNTextProperties = .init(),
		appearance: STNAppearanceProperties,
		interaction: STNInteractionProperties,
		accessibility: STNAccessibilityProperties,
		lifecycle: STNLifecycleProperties
	) {
		if let value = layout.padding {
			padding = value
		}

		if let value = layout.frame {
			frame = value
		}

		if let value = textStyle.font {
			font = value
		}

		if let value = textStyle.foreground {
			foreground = value
		}

		if let value = appearance.background {
			background = value
		}

		if let value = appearance.opacity {
			opacity = value
		}

		if let value = appearance.borderColor {
			borderColor = value
		}

		if let value = appearance.borderWidth {
			borderWidth = value
		}

		if let value = appearance.cornerRadius {
			cornerRadius = value
		}

		if let value = appearance.clip {
			style.clip = value
		}

		if let value = appearance.visibility {
			style.visibility = value
		}

		if let value = interaction.inert {
			style.inert = value
		}

		if let value = interaction.isEnabled {
			isEnabled = value
		}

		onPointerDown = interaction.onPointerDown
		onPointerMove = interaction.onPointerMove
		onPointerUp = interaction.onPointerUp
		onPointerCancel = interaction.onPointerCancel
		onPointerDownCapture = interaction.onPointerDownCapture
		onPointerMoveCapture = interaction.onPointerMoveCapture
		onPointerUpCapture = interaction.onPointerUpCapture
		self.accessibility = accessibility
		onMount = lifecycle.onMount
	}

	func mount(
		_ kind: NodeKind,
		in context: MountContext,
		content: (() -> STNGroup)? = nil,
		configure: (NodeRecord) -> Void = { _ in }
	) {
		let node = context.session.document.create(kind, parent: context.parent)
		node.attachLifetime(to: context.scope)
		node.style = style
		node.style.retained = style.retained || opacity.reactive
		node.style.accessibilityHint = accessibility.hint
		node.style.heading = accessibility.heading
		node.style.semanticGroup = accessibility.group
		node.onActivate = onActivate
		node.onSubmit = onSubmit
		node.onPointerDown = onPointerDown
		node.onPointerMove = onPointerMove
		node.onPointerUp = onPointerUp
		node.onPointerCancel = onPointerCancel
		node.onPointerDownCapture = onPointerDownCapture
		node.onPointerMoveCapture = onPointerMoveCapture
		node.onPointerUpCapture = onPointerUpCapture
		configure(node)
		text.install(in: context, node: node, dirty: .all) { $0.text = $1 }
		background.install(in: context, node: node, dirty: .paint) { $0.style.background = $1 }
		font?
			.install(in: context, node: node, dirty: .all) { node, value in
				node.style.font = value
			}
		foreground?
			.install(in: context, node: node, dirty: .paint) { node, value in
				node.style.foreground = value
			}
		padding?
			.install(in: context, node: node, dirty: .all) { node, value in
				precondition(
					[value.top, value.leading, value.bottom, value.trailing].allSatisfy { $0.isFinite && $0 >= 0 },
					"Stana: invalid padding"
				)
				node.style.padding = value
			}
		frame?
			.install(in: context, node: node, dirty: .all) { node, value in
				precondition(
					value.minWidth.isFinite && value.minHeight.isFinite && value.minWidth >= 0 && value.minHeight >= 0
						&& value.maxWidth >= value.minWidth && value.maxHeight >= value.minHeight
						&& (value.width.map { $0.isFinite && $0 >= 0 } ?? true)
						&& (value.height.map { $0.isFinite && $0 >= 0 } ?? true),
					"Stana: invalid frame"
				)
				node.style.frame = value
			}
		borderColor?
			.install(in: context, node: node, dirty: .paint) { node, value in
				node.style.borderColor = value
			}
		borderWidth?
			.install(in: context, node: node, dirty: .paint) { node, value in
				precondition(value.isFinite && value >= 0, "Stana: invalid border width")
				node.style.borderWidth = value
			}
		cornerRadius?
			.install(in: context, node: node, dirty: .all) { node, value in
				precondition(value.isFinite && value >= 0, "Stana: invalid corner radius")
				node.style.cornerRadius = value
			}
		opacity.install(in: context, node: node, dirty: .compositing) { n, value in
			precondition(value.isFinite && (0...1).contains(value), "Stana: invalid opacity")
			n.style.opacity = value
		}
		isEnabled.install(in: context, node: node, dirty: [.paint, .semantics]) { $0.style.isEnabled = $1 }
		accessibility.label?.install(in: context, node: node, dirty: .semantics) { $0.style.accessibilityLabel = $1 }
		if let content {
			MountContext(session: context.session, parent: node, scope: node.scope).mount(content())
		}

		if let onMount {
			context.session.document.deferMount { [weak document = context.session.document, weak node] in
				guard let document, let node, node.scope.isAlive else {
					return
				}

				onMount(STNNodeHandle(document: document, id: node.id))
			}
		}
	}
}
