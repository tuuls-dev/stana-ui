import StanaGraphics
import Testing

@Test func presentationRequiresBothMatchingObservationsInEitherOrder() {
	for presentationFirst in [false, true] {
		var tracker = PresentationTracker()
		let id = PresentationAttemptID(epoch: 1, sequence: 1, scene: 8)
		tracker.submitted(id)
		if presentationFirst {
			let observed1 = !tracker.presented(id, timestamp: 2)
			#expect(observed1)
			#expect(tracker.confirmed == nil)
			let observed2 = tracker.gpu(id, success: true)
			#expect(observed2)
		} else {
			let observed3 = !tracker.gpu(id, success: true)
			#expect(observed3)
			#expect(tracker.confirmed == nil)
			let observed4 = tracker.presented(id, timestamp: 2)
			#expect(observed4)
		}
		#expect(tracker.confirmed == id)
		let observed5 = !tracker.presented(id, timestamp: 3)
		#expect(observed5)
	}
}

@Test func zeroUnknownAndOldCallbacksCannotAdvanceOrClearNewerAmbiguity() {
	var tracker = PresentationTracker()
	let a = PresentationAttemptID(epoch: 1, sequence: 1, scene: 1)
	let b = PresentationAttemptID(epoch: 1, sequence: 2, scene: 2)
	tracker.submitted(a)
	tracker.submitted(b)
	let observed6 = !tracker.gpu(a, success: true)
	#expect(observed6)
	let observed7 = !tracker.presented(a, timestamp: 0)
	#expect(observed7)
	let observed8 = !tracker.presented(a, timestamp: .nan)
	#expect(observed8)
	tracker.markUnknown(b)
	let observed9 = tracker.presented(a, timestamp: 1)
	#expect(observed9)
	#expect(tracker.ambiguous == b)
	let observed10 = !tracker.presented(b, timestamp: 2)
	#expect(observed10)
	let observed11 = tracker.gpu(b, success: true)
	#expect(observed11)
	#expect(tracker.ambiguous == nil)
	let observed12 = !tracker.gpu(a, success: true)
	#expect(observed12)
	#expect(tracker.confirmed == b)
	tracker.reset(epoch: 2)
	let observed13 = !tracker.presented(b, timestamp: 3)
	#expect(observed13)
}

@Test func failedGPUCannotConfirmEvenWithPositiveTimestamp() {
	var tracker = PresentationTracker()
	let id = PresentationAttemptID(epoch: 1, sequence: 1, scene: 1)
	tracker.submitted(id)
	let observed14 = !tracker.presented(id, timestamp: 1)
	#expect(observed14)
	let observed15 = !tracker.gpu(id, success: false)
	#expect(observed15)
	#expect(tracker.confirmed == nil)
}
