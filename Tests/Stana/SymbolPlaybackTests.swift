import Foundation
import StanaCore
import StanaPrimitives
import StanaTesting
import Testing

@testable import Stana
@Suite struct SymbolPlaybackTests {
	@Test(arguments: [STNSymbolEffect.rotate, .pulse, .bounce], [0.0, 0.25, 0.5, 0.75, 1.0])
	func exactSamples(effect: STNSymbolEffect, phase: Double) {
		let sample = SymbolPlaybackState.sample(effect: effect, phase: phase)
		switch effect {
		case .rotate: #expect(sample.rotation == (phase == 1 ? 0 : 2 * .pi * phase))
		case .pulse: #expect(abs(sample.scale - (1 + 0.08 * pow(sin(.pi * phase), 2))) < 1e-12)
		case .bounce: #expect(abs(sample.verticalFraction + 0.12 * pow(sin(.pi * phase), 2)) < 1e-12)
		}
	}

	@Test(arguments: [STNSymbolEffect.rotate, .pulse, .bounce])
	func onceCompletesAndLoopWraps(effect: STNSymbolEffect) {
		for looping in [false, true] {
			var state = SymbolPlaybackState()
			state.reconcile(
				assetChanged: true,
				playback: looping ? .loop(effect) : .once(effect, request: 1),
				reducedMotion: false,
				visible: true
			)
			state.advance(by: 100)
			#expect(state.elapsed == 0)
			state.advance(by: effect == .bounce ? 0.3 : 0.5)
			#expect(state.sample == SymbolPlaybackState.sample(effect: effect, phase: 0.5))
			state.advance(by: effect == .bounce ? 0.3 : 0.5)
			#expect(state.sample == SymbolEffectSample())
			#expect(state.needsFrame == looping)
		}
	}

	@Test func requestDeduplicationCancellationAndReuse() {
		var state = SymbolPlaybackState()

		func apply(_ playback: STNSymbolPlayback, changed: Bool = false) {
			state.reconcile(assetChanged: changed, playback: playback, reducedMotion: false, visible: true)
		}

		apply(.once(.bounce, request: 7))
		state.advance(by: 0); state.advance(by: 0.2)
		apply(.once(.bounce, request: 7))
		#expect(state.elapsed == 0.2)
		apply(.once(.pulse, request: 7))
		#expect(!state.needsFrame)
		apply(.none); apply(.once(.bounce, request: 7))
		#expect(!state.needsFrame)
		apply(.loop(.pulse)); apply(.once(.bounce, request: 7))
		#expect(!state.needsFrame)
		apply(.once(.bounce, request: 8))
		#expect(state.needsFrame)
		apply(.once(.bounce, request: 7))
		#expect(state.needsFrame && state.elapsed == 0)
		apply(.once(.bounce, request: 7), changed: true)
		#expect(!state.needsFrame)
		apply(.once(.bounce, request: 9), changed: true)
		#expect(state.needsFrame)
	}

	@Test func visibilityPausesWithoutCatchupAndHiddenChangesReplacePending() {
		var state = SymbolPlaybackState()
		state.reconcile(assetChanged: true, playback: .once(.rotate, request: 1), reducedMotion: false, visible: true)
		state.advance(by: 0); state.advance(by: 0.25)
		state.reconcile(assetChanged: false, playback: .once(.rotate, request: 1), reducedMotion: false, visible: false)
		state.advance(by: 100)
		#expect(state.elapsed == 0.25 && !state.needsFrame)
		state.reconcile(assetChanged: false, playback: .once(.rotate, request: 1), reducedMotion: false, visible: true)
		state.advance(by: 100)
		#expect(state.elapsed == 0.25)
		state.reconcile(assetChanged: false, playback: .once(.rotate, request: 2), reducedMotion: false, visible: false)
		#expect(state.elapsed == 0 && !state.needsFrame && state.lastRequest == 2)
		state.reconcile(assetChanged: false, playback: .once(.rotate, request: 3), reducedMotion: false, visible: true)
		#expect(state.needsFrame && state.elapsed == 0 && state.lastRequest == 3)
	}

	@Test func reducedMotionConsumesOnceAndRestartsOnlyLoops() {
		for playback in [STNSymbolPlayback.loop(.pulse), .once(.bounce, request: 42)] {
			var state = SymbolPlaybackState()
			state.reconcile(assetChanged: true, playback: playback, reducedMotion: false, visible: true)
			state.advance(by: 0); state.advance(by: 0.2)
			state.reconcile(assetChanged: false, playback: playback, reducedMotion: true, visible: false)
			#expect(state.sample == SymbolEffectSample() && !state.needsFrame)
			state.reconcile(assetChanged: false, playback: playback, reducedMotion: false, visible: true)
			#expect(state.needsFrame == (playback == .loop(.pulse)))
			#expect(state.elapsed == 0)
		}
	}

	@Test func longLoopDeltaAndFailureRecovery() {
		var state = SymbolPlaybackState()
		state.reconcile(assetChanged: true, playback: .loop(.rotate), reducedMotion: false, visible: true)
		state.advance(by: 0); state.advance(by: 12345.25)
		#expect(state.elapsed == 0.25)
		state.reconcile(
			assetChanged: false,
			playback: .loop(.rotate),
			reducedMotion: false,
			visible: true,
			available: false
		)
		#expect(!state.needsFrame && state.sample == SymbolEffectSample())
		state.reconcile(assetChanged: false, playback: .loop(.rotate), reducedMotion: false, visible: true)
		#expect(state.needsFrame && state.elapsed == 0)
	}
}
