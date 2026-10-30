import Foundation
import StanaCore
import StanaPrimitives
import StanaPlatformMacOS

public struct STNFrameTime: Sendable {
	public let timestamp: Double
	public let targetTimestamp: Double
	public let elapsed: Double
}

@MainActor public final class STNFrameSubscription {
	private var cancellation: (() -> Void)?
	public private(set) var isCancelled = false

	package init(_ cancel: @escaping () -> Void) {
		cancellation = cancel
	}

	public func cancel() {
		guard !isCancelled else { return }
		isCancelled = true
		cancellation?()
		cancellation = nil
	}
}

@MainActor package final class FrameRegistration {
	let id = FrameID()
	weak var scope: LifetimeScope?
	let active: () -> Bool
	let callback: (STNFrameTime) -> Void
	var lastTimestamp: Double?
	var cancelled = false

	init(scope: LifetimeScope, active: @escaping () -> Bool, callback: @escaping (STNFrameTime) -> Void) {
		self.scope = scope
		self.active = active
		self.callback = callback
	}
}

extension STNComponentContext {
	@discardableResult public func onFrame(
		isActive: some STNPropertyConvertible<Bool> = true,
		_ callback: @escaping @MainActor (STNFrameTime) -> Void
	) -> STNFrameSubscription {
		registerFrame(active: isActive.asProperty(), callback: callback)
	}

	private func registerFrame(active: Property<Bool>, callback: @escaping (STNFrameTime) -> Void)
		-> STNFrameSubscription
	{
		let registration = FrameRegistration(scope: scope, active: active.read, callback: callback)
		let subscription = STNFrameSubscription { [weak session] in
			registration.cancelled = true
			session?.frameRegistrations.removeAll { $0.id == registration.id }
			session?.refreshFrameDemand()
		}
		guard let session, scope.isAlive else {
			subscription.cancel()
			return subscription
		}

		session.frameRegistrations.append(registration)
		scope.own { subscription.cancel() }
		if active.reactive {
			let observation = ValueObservation(read: active.read, equals: { $0 == $1 }) { [weak session] _ in
				registration.lastTimestamp = nil
				session?.refreshFrameDemand()
			}
			scope.own { observation.cancel() }
			ReactiveRuntime.shared.enqueue(observation)
		}

		session.refreshFrameDemand()
		return subscription
	}
}

extension MountSession {
	package func refreshFrameDemand() {
		(window as? MacOSWindow)?
			.setAnimationDemand(
				frameRegistrations.contains {
					!$0.cancelled && $0.scope?.isAlive == true && $0.active()
				}
			)
	}

	package func tickFrames(timestamp: Double, target: Double) {
		frameTargetTimestamp = target
		framePeriod = max(0, target - timestamp)
		let subscriptions = frameRegistrations
		STNTransaction.perform {
			for registration in subscriptions {
				guard !registration.cancelled, registration.scope?.isAlive == true, registration.active() else {
					registration.lastTimestamp = nil
					continue
				}

				let elapsed = registration.lastTimestamp.map { max(0, timestamp - $0) } ?? 0
				registration.lastTimestamp = timestamp
				registration.callback(.init(timestamp: timestamp, targetTimestamp: target, elapsed: elapsed))
			}
		}
	}
}
