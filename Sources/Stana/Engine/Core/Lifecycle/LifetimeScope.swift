import StanaPrimitives

@MainActor package final class LifetimeScope {
	package private(set) var isAlive = true
	private var resources: [(ResourceToken, () -> Void)] = []
	private var cleanups: [() -> Void] = []
	package var requestRevision: UInt64 = 0
	package let id = ScopeID()

	package init() {}

	@discardableResult package func own(_ cancel: @escaping () -> Void) -> ResourceToken {
		let token = ResourceToken()
		if isAlive {
			resources.append((token, cancel))
		} else {
			cancel()
		}

		return token
	}

	package func disown(_ token: ResourceToken) {
		resources.removeAll { $0.0 == token }
	}

	@discardableResult package func adopt(_ child: LifetimeScope) -> ResourceToken {
		let token = own { child.dispose() }
		if child.isAlive {
			child.resources.append((token, { [weak self] in self?.disown(token) }))
		} else {
			disown(token)
		}

		return token
	}

	package func onDispose(_ cleanup: @escaping () -> Void) {
		if isAlive {
			cleanups.append(cleanup)
		}
	}

	package func dispose() {
		guard isAlive else {
			return
		}

		isAlive = false
		let cancellations = resources
		resources.removeAll()
		let callbacks = cleanups
		cleanups.removeAll()
		for (_, cancel) in cancellations {
			cancel()
		}

		for callback in callbacks {
			ReactiveRuntime.shared.afterCommit(callback)
		}
	}
}
