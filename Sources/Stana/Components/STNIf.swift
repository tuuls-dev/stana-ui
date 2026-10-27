import StanaCore
import StanaPrimitives

@MainActor public struct STNIf: STNComponent, PrimitiveComponent {
	private let condition: Property<Bool>
	private let thenContent: () -> STNGroup
	private let elseContent: () -> STNGroup

	public init(
		_ condition: STNSignal<Bool>,
		@STNBuilder then content: @escaping () -> STNGroup,
		@STNBuilder else alternative: @escaping () -> STNGroup = { STNGroup() }
	) {
		self.condition = Property(condition)
		thenContent = content
		elseContent = alternative
	}

	public init(
		_ condition: STNComputed<Bool>,
		@STNBuilder then content: @escaping () -> STNGroup,
		@STNBuilder else alternative: @escaping () -> STNGroup = { STNGroup() }
	) {
		self.condition = Property(condition)
		thenContent = content
		elseContent = alternative
	}

	public func makeContent(in context: STNComponentContext) -> STNEmpty {
		return STNEmpty()
	}

	package func mount(in context: MountContext) {
		let region = context.session.document.create(.group, parent: context.parent)
		region.attachLifetime(to: context.scope)
		let state = BranchState()
		region.scope.own { state.scope?.dispose() }
		let observation = ValueObservation(read: condition.read, equals: { $0 == $1 }) {
			[weak session = context.session, weak region] value in
			guard let session, let region, region.scope.isAlive else {
				return
			}

			state.scope?.dispose()
			let scope = LifetimeScope()
			state.scope = scope
			let next = MountContext(session: session, parent: region, scope: scope)
			next.mount(value ? thenContent() : elseContent())
			session.document.changed(region, .all)
		}
		region.scope.own { observation.cancel() }
		ReactiveRuntime.shared.enqueue(observation)
	}
}

@MainActor private final class BranchState {
	var scope: LifetimeScope?
}
