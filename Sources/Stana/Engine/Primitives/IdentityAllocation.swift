import Synchronization

/// Process-local uniqueness, not resource publication. Zero is reserved.
package final class IdentityAllocator: Sendable {
	package static let shared = IdentityAllocator()
	private let value: Atomic<UInt64>

	package init(startingAt value: UInt64 = 0) {
		self.value = Atomic(value)
	}

	package func next() -> UInt64 {
		var current = value.load(ordering: .relaxed)
		while true {
			guard current < .max else {
				fatalError("Stana: identity namespace exhausted")
			}

			let result = value.compareExchange(
				expected: current,
				desired: current + 1,
				ordering: .relaxed
			)
			if result.exchanged {
				return current + 1
			}

			current = result.original
		}
	}
}

/// Shared across scopes: an adoption token participates in two scope resource registries.
@MainActor package enum UIIdentityAllocator {
	private static var value: UInt64 = 0

	package static func next() -> UInt64 {
		nextRevision(&value)
		return value
	}
}

package struct DocumentID: Hashable, Sendable {
	package let rawValue: UInt64

	@MainActor package init() {
		rawValue = UIIdentityAllocator.next()
	}
}

package struct ScopeID: Hashable, Sendable {
	package let rawValue: UInt64

	@MainActor package init() {
		rawValue = UIIdentityAllocator.next()
	}
}

package struct ResourceToken: Hashable, Sendable {
	package let rawValue: UInt64

	@MainActor package init() {
		rawValue = UIIdentityAllocator.next()
	}
}

package struct FrameID: Hashable, Sendable {
	package let rawValue: UInt64

	@MainActor package init() {
		rawValue = UIIdentityAllocator.next()
	}
}

package struct RenderVersion: Hashable, Sendable {
	package let rawValue: UInt64

	package init() {
		rawValue = IdentityAllocator.shared.next()
	}
}
