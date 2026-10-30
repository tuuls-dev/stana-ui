import StanaPrimitives

package struct PresentationAttemptID: Hashable, Sendable {
	package let epoch: UInt64
	package let sequence: UInt64
	package let scene: UInt64

	package init(epoch: UInt64, sequence: UInt64, scene: UInt64) {
		self.epoch = epoch
		self.sequence = sequence
		self.scene = scene
	}
}

/// Joins observations for the *same* attempt. Completion is not presentation.
package struct PresentationTracker: Sendable {
	package struct Attempt: Sendable {
		package var gpuSucceeded = false
		package var timestamp: Double?
		package var unknown = false
		package var failed = false
	}

	package private(set) var epoch: UInt64 = 1
	package private(set) var confirmed: PresentationAttemptID?
	package private(set) var confirmedTimestamp: Double?
	package private(set) var ambiguous: PresentationAttemptID?
	package private(set) var attempts: [PresentationAttemptID: Attempt] = [:]

	package init() {}

	package mutating func reset(epoch: UInt64) {
		self.epoch = epoch
		attempts.removeAll()
		ambiguous = nil
		// The displayed last-known geometry is kept by its host until replaced.
		confirmed = nil
		confirmedTimestamp = nil
	}

	package mutating func submitted(_ id: PresentationAttemptID) {
		guard id.epoch == epoch else { return }
		attempts[id] = attempts[id] ?? Attempt()
	}

	@discardableResult package mutating func gpu(_ id: PresentationAttemptID, success: Bool) -> Bool {
		guard id.epoch == epoch, var attempt = attempts[id] else { return false }
		attempt.gpuSucceeded = success
		attempt.failed = !success
		attempts[id] = attempt
		if !success { markUnknown(id) }
		return confirm(id)
	}

	@discardableResult package mutating func presented(_ id: PresentationAttemptID, timestamp: Double) -> Bool {
		guard id.epoch == epoch, timestamp.isFinite, timestamp > 0, var attempt = attempts[id] else { return false }
		attempt.timestamp = timestamp
		attempts[id] = attempt
		return confirm(id)
	}

	package mutating func markUnknown(_ id: PresentationAttemptID) {
		guard id.epoch == epoch, var attempt = attempts[id], confirmed.map({ $0.sequence < id.sequence }) ?? true else {
			return
		}
		attempt.unknown = true
		attempts[id] = attempt
		if ambiguous.map({ $0.sequence < id.sequence }) ?? true { ambiguous = id }
	}

	private mutating func confirm(_ id: PresentationAttemptID) -> Bool {
		guard let attempt = attempts[id], attempt.gpuSucceeded, !attempt.failed, let time = attempt.timestamp,
			confirmed.map({ $0.sequence < id.sequence && $0.scene <= id.scene }) ?? true
		else { return false }
		confirmed = id
		confirmedTimestamp = time
		if ambiguous.map({ $0.sequence <= id.sequence }) ?? false { ambiguous = nil }
		attempts = attempts.filter { $0.key.sequence >= id.sequence }
		return true
	}
}
