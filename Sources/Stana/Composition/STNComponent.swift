import StanaCore
import StanaPrimitives

/// A description mounted once per instance. State updates do not rerun this function.
@MainActor public protocol STNComponent {
	associatedtype Content: STNComponent

	@STNBuilder func makeContent(in context: STNComponentContext) -> Content
}

/// The terminal composition value. Normally produced by `STNBuilder`.
@MainActor public struct STNEmpty: STNComponent {
	public init() {}

	public func makeContent(in context: STNComponentContext) -> STNEmpty {
		return self
	}
}

@MainActor public struct STNGroup: STNComponent {
	package var components: [any STNComponent]

	public init() {
		components = []
	}

	package init(components: [any STNComponent]) {
		self.components = components
	}

	public func makeContent(in context: STNComponentContext) -> STNEmpty {
		return STNEmpty()
	}
}

@MainActor package protocol PrimitiveComponent {
	func mount(in context: MountContext)
}

@MainActor package struct MountContext {
	package let session: MountSession
	package let parent: NodeRecord
	package let scope: LifetimeScope

	package func mount(_ component: any STNComponent) {
		session.document.metrics.builderExecutions += 1
		if component is STNEmpty {
			return
		}

		if let group = component as? STNGroup {
			for child in group.components {
				mount(child)
			}

			return
		}

		if let primitive = component as? any PrimitiveComponent {
			primitive.mount(in: self)
			return
		}

		let childScope = LifetimeScope()
		scope.adopt(childScope)
		let context = STNComponentContext(scope: childScope, session: session)
		let content = component.makeContent(in: context)
		MountContext(session: session, parent: parent, scope: childScope).mount(content)
	}
}
