import StanaPrimitives

@MainActor package final class LifetimeScope {
	package private(set) var isAlive = true

	private struct ResourceEntry {
		let cancel: () -> Void
		var previous: ResourceToken?
		var next: ResourceToken?
	}

	private var resources: [ResourceToken: ResourceEntry] = [:]
	private var firstResource: ResourceToken?
	private var lastResource: ResourceToken?
	private var cleanups: [() -> Void] = []
	package var requestRevision: UInt64 = 0
	package let id = ScopeID()

	package init() {}

	private func appendResource(_ token: ResourceToken, cancel: @escaping () -> Void) {
		precondition(isAlive)
		precondition(resources[token] == nil)
		resources[token] = ResourceEntry(cancel: cancel, previous: lastResource, next: nil)
		if let lastResource {
			resources[lastResource]!.next = token
		} else {
			firstResource = token
		}

		lastResource = token
	}

	@discardableResult package func own(_ cancel: @escaping () -> Void) -> ResourceToken {
		let token = ResourceToken()
		if isAlive {
			appendResource(token, cancel: cancel)
		} else {
			cancel()
		}

		return token
	}

	package func disown(_ token: ResourceToken) {
		guard let entry = resources.removeValue(forKey: token) else {
			return
		}

		if let previous = entry.previous {
			resources[previous]!.next = entry.next
		} else {
			firstResource = entry.next
		}

		if let next = entry.next {
			resources[next]!.previous = entry.previous
		} else {
			lastResource = entry.previous
		}

		withExtendedLifetime(entry) {}
	}

	@discardableResult package func adopt(_ child: LifetimeScope) -> ResourceToken {
		let token = own { child.dispose() }
		if child.isAlive {
			child.appendResource(token) { [weak self] in
				self?.disown(token)
			}
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
		var nextToken = firstResource
		resources = [:]
		firstResource = nil
		lastResource = nil
		let callbacks = cleanups
		cleanups.removeAll()

		while let token = nextToken {
			let entry = cancellations[token]!
			nextToken = entry.next
			entry.cancel()
		}

		for callback in callbacks {
			ReactiveRuntime.shared.afterCommit(callback)
		}

		withExtendedLifetime(cancellations) {}
	}
}
