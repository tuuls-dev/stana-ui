import StanaCore
import StanaPrimitives

@MainActor package struct Property<Value: Equatable> {
	let read: () -> Value
	let reactive: Bool

	init(_ value: Value) {
		read = { value }
		reactive = false
	}

	init(_ signal: STNSignal<Value>) {
		read = { signal.value }
		reactive = true
	}

	init(_ computed: STNComputed<Value>) {
		read = { computed.value }
		reactive = true
	}

	func install(in context: MountContext, node: NodeRecord, dirty: Dirty, set: @escaping (NodeRecord, Value) -> Void) {
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

	func mount(
		_ kind: NodeKind,
		in context: MountContext,
		content: (() -> STNGroup)? = nil,
		configure: (NodeRecord) -> Void = { _ in }
	) {
		let node = context.session.document.create(kind, parent: context.parent)
		node.attachLifetime(to: context.scope)
		node.style = style
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
		// Text fields own their background through their reactive Options snapshot.
		if kind != .textField {
			background.install(in: context, node: node, dirty: .paint) { $0.style.background = $1 }
		}
		opacity.install(in: context, node: node, dirty: .paint) { n, value in
			precondition(value.isFinite && (0...1).contains(value))
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
