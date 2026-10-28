import Stana
import StanaTesting
import Testing

@MainActor private struct AnimatedLabel: STNComponent {
	let count: STNSignal<Int>
	let active: STNSignal<Bool>
	let receive: (STNFrameTime) -> Void

	func makeContent(in context: STNComponentContext) -> some STNComponent {
		context.onFrame(isActive: active) { frame in
			count.value += 1
			receive(frame)
		}
		STNText(properties: .init(text: count.map { String($0) }))
	}
}

@MainActor @Test func frameCallbacksMutateInOneTransactionAndStopWithTheirScope() {
	let count = STNSignal(0), active = STNSignal(true), shown = STNSignal(true)
	var frames: [STNFrameTime] = []
	let host = STNTestHost()
	host.mount {
		STNIf(shown) {
			AnimatedLabel(count: count, active: active, receive: { frames.append($0) })
		}
	}
	host.advanceFrame(timestamp: 1, targetTimestamp: 1.016)
	host.advanceFrame(timestamp: 1.02, targetTimestamp: 1.036)
	#expect(count.value == 2)
	#expect(frames[0].elapsed == 0)
	#expect(abs(frames[1].elapsed - 0.02) < 1e-10)
	active.value = false
	host.advanceFrame(timestamp: 2, targetTimestamp: 2.016)
	#expect(count.value == 2)
	active.value = true
	host.advanceFrame(timestamp: 3, targetTimestamp: 3.016)
	#expect(frames.last?.elapsed == 0)
	shown.value = false
	host.advanceFrame(timestamp: 4, targetTimestamp: 4.016)
	#expect(count.value == 3)
	host.close()
}

@MainActor @Test func returningToOldGeometryAndLateOlderConfirmationCannotClearNewerAmbiguity() throws {
	for previousUnknown in [false, true] {
		var clicks = 0
		let translation = STNSignal(STNAffineTransform.identity)
		let host = STNTestHost(size: .init(width: 400, height: 200))
		host.enablePresentationTesting()
		host.mount {
			STNLayer(properties: .init(transform: translation)) {
				STNButton(properties: .init(text: "Target", onActivate: { clicks += 1 }))
			}
		}
		let initial = try #require(host.render())
		host.reportGPUCompletion(submission: initial.submissionSequence, success: true)
		host.reportPresentation(submission: initial.submissionSequence, timestamp: 1)
		translation.value = .translation(x: 200, y: 0)
		let moved = try #require(host.render())
		host.reportGPUCompletion(submission: moved.submissionSequence, success: true)
		if previousUnknown { host.reportPresentationUnknown(submission: moved.submissionSequence) }
		translation.value = .identity
		let returned = try #require(host.render())
		host.reportGPUCompletion(submission: returned.submissionSequence, success: true)
		host.reportPresentationUnknown(submission: returned.submissionSequence)
		if previousUnknown {
			host.click(at: .init(x: 10, y: 10))
			#expect(clicks == 0)
		}
		// This older acknowledgement can update last-known geometry, but cannot
		// erase the newer unknown attempt at the original location.
		host.reportPresentation(submission: moved.submissionSequence, timestamp: 2)
		host.click(at: .init(x: 210, y: 10))
		host.click(at: .init(x: 10, y: 10))
		#expect(clicks == 0)
		host.reportPresentationUnknown(submission: returned.submissionSequence)
		host.click(at: .init(x: 210, y: 10))
		#expect(clicks == 0)
		host.reportPresentation(submission: returned.submissionSequence, timestamp: 3)
		host.click(at: .init(x: 10, y: 10))
		#expect(clicks == 1)
		host.close()
	}
}

@MainActor @Test func pendingGeometryDoesNotMoveUntilBothObservationsAndUnknownGatesOnlyChangedRegions() throws {
	var clicks = 0
	let translation = STNSignal(STNAffineTransform.identity)
	let host = STNTestHost(size: .init(width: 400, height: 200))
	host.enablePresentationTesting()
	host.mount {
		STNLayer(properties: .init(transform: translation)) {
			STNButton(properties: .init(text: "Target", onActivate: { clicks += 1 }))
		}
	}
	let initial = try #require(host.render())
	host.reportGPUCompletion(submission: initial.submissionSequence, success: true)
	host.click(at: .init(x: 10, y: 10))
	#expect(clicks == 0)
	host.reportPresentation(submission: initial.submissionSequence, timestamp: 1)
	host.click(at: .init(x: 10, y: 10))
	#expect(clicks == 1)
	translation.value = .translation(x: 200, y: 0)
	let moved = try #require(host.render())
	host.reportGPUCompletion(submission: moved.submissionSequence, success: true)
	host.click(at: .init(x: 10, y: 10))
	#expect(clicks == 2)
	host.reportPresentation(submission: moved.submissionSequence, timestamp: 0)
	host.reportPresentationUnknown(submission: moved.submissionSequence)
	host.click(at: .init(x: 10, y: 10))
	host.click(at: .init(x: 210, y: 10))
	#expect(clicks == 2)
	host.reportPresentation(submission: moved.submissionSequence, timestamp: 2)
	host.click(at: .init(x: 210, y: 10))
	#expect(clicks == 3)
	host.close()
}
