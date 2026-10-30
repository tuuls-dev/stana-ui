import Foundation
import StanaCore
import StanaPrimitives

public struct STNRequestToken: Sendable {
	package let scopeID: ScopeID
	package let revision: UInt64
}

/// Capabilities owned by one mounted component, never mutable engine records.
@MainActor public struct STNComponentContext {
	package let scope: LifetimeScope
	package weak var session: MountSession?
	public let environment: STNEnvironment

	package init(scope: LifetimeScope, session: MountSession) {
		self.scope = scope
		self.session = session
		environment = session.environment
	}

	public func state<Value>(initial: Value, equals: @escaping (Value, Value) -> Bool) -> STNSignal<Value> {
		.init(initial, equals: equals)
	}

	public func state<Value: Equatable>(initial: Value) -> STNSignal<Value> {
		.init(initial)
	}

	public func own(_ subscription: STNSubscription) {
		scope.own { subscription.cancel() }
	}

	public func onDispose(_ cleanup: @escaping @MainActor () -> Void) {
		scope.onDispose(cleanup)
	}

	@discardableResult public func beginRequest() -> STNRequestToken {
		precondition(scope.requestRevision < .max, "Stana: request revision exhausted")
		scope.requestRevision += 1
		return .init(scopeID: scope.id, revision: scope.requestRevision)
	}

	public func isCurrent(_ token: STNRequestToken) -> Bool {
		scope.isAlive && scope.id == token.scopeID && scope.requestRevision == token.revision
	}

	public func task(
		operation: @escaping @MainActor (STNComponentContext) async throws -> Void,
		onError: @escaping @MainActor (any Error) -> Void
	) {
		ReactiveRuntime.shared.assertCanMutate("task creation")
		let scope = scope
		guard let session, scope.isAlive else {
			return
		}

		session.document.deferMount {
			guard scope.isAlive else {
				return
			}

			let registration = ScopeTaskRegistration()
			let task = Task { @MainActor in
				defer {
					if let token = registration.token {
						scope.disown(token)
					}
				}

				do {
					try await operation(self)
				} catch is CancellationError {} catch {
					if scope.isAlive && !Task.isCancelled {
						onError(error)
					}
				}
			}
			registration.token = scope.own { task.cancel() }
		}
	}
}

@MainActor private final class ScopeTaskRegistration {
	var token: ResourceToken?
}
