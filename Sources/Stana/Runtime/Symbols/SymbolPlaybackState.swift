import Foundation
import StanaCore
import StanaPrimitives

/// One mount's request history and active clock. Reconciled only after all reactive deliveries settle.
package struct SymbolPlaybackState {
	package private(set) var elapsed = 0.0
	package private(set) var active: STNSymbolEffect?
	package private(set) var looping = false
	package private(set) var lastRequest: UInt64?
	private var previous = STNSymbolPlayback.none
	private var initialized = false
	private var reduced = false
	private var visible = false
	private var available = true
	package private(set) var needsFrame = false
	package private(set) var resetClock = true

	package mutating func reconcile(
		assetChanged: Bool,
		playback: STNSymbolPlayback,
		reducedMotion: Bool,
		visible: Bool,
		available: Bool = true
	) {
		let initial = !initialized
		var newRequest = false
		if case .once(_, let request) = playback {
			newRequest = lastRequest != request
			lastRequest = request
		}

		if assetChanged || initial {
			stop()
		}

		switch playback {
		case .none: stop()
		case .loop(let effect):
			if initial || assetChanged || playback != previous || (reduced && !reducedMotion)
				|| (!self.available && available)
			{
				start(effect, looping: true)
			}
		case .once(let effect, _):
			if newRequest {
				start(effect, looping: false)
			} else if playback != previous || assetChanged {
				stop()
			}
		}

		if reducedMotion || !available {
			stop()
		}

		let demand = active != nil && visible && !reducedMotion && available
		if demand != needsFrame || visible != self.visible {
			resetClock = true
		}

		needsFrame = demand
		previous = playback
		self.visible = visible
		self.reduced = reducedMotion
		self.available = available
		initialized = true
	}

	private mutating func start(_ effect: STNSymbolEffect, looping: Bool) {
		active = effect
		self.looping = looping
		elapsed = 0
		resetClock = true
	}

	private mutating func stop() {
		active = nil
		elapsed = 0
		resetClock = true
	}

	package mutating func advance(by delta: Double) {
		guard needsFrame, let active else {
			return
		}

		let duration = active == .bounce ? 0.6 : 1.0
		if resetClock {
			resetClock = false
		} else if looping {
			elapsed = (elapsed + max(0, delta).truncatingRemainder(dividingBy: duration))
				.truncatingRemainder(dividingBy: duration)
		} else if delta >= duration - elapsed {
			stop()
			needsFrame = false
		} else {
			elapsed += max(0, delta)
		}
	}

	package var sample: SymbolEffectSample {
		guard let active else {
			return .init()
		}

		let duration = active == .bounce ? 0.6 : 1.0
		let phase = looping ? elapsed.truncatingRemainder(dividingBy: duration) / duration : min(elapsed / duration, 1)
		return Self.sample(effect: active, phase: phase)
	}

	package static func sample(effect: STNSymbolEffect, phase: Double) -> SymbolEffectSample {
		let wave = phase == 0 || phase == 1 ? 0 : pow(sin(.pi * phase), 2)
		switch effect {
		case .rotate: return .init(rotation: phase == 1 ? 0 : 2 * .pi * phase)
		case .pulse: return .init(scale: 1 + 0.08 * wave)
		case .bounce: return .init(verticalFraction: -0.12 * wave)
		}
	}
}

@MainActor package final class MountedSymbol {
	weak var node: NodeRecord?
	weak var session: MountSession?
	var playback = STNSymbolPlayback.none
	var state = SymbolPlaybackState()
	var previousAsset: SymbolStorage?
	var previousStroke: Double?
	var previousScale: Double?
	var available = true
	var failedCodes: Set<String> = []
	var epoch: UInt64 = 0
	var onError: (@MainActor (STNSymbolDiagnostic) -> Void)?
	var registration: FrameRegistration?

	init(node: NodeRecord, session: MountSession, onError: (@MainActor (STNSymbolDiagnostic) -> Void)?) {
		self.node = node
		self.session = session
		self.onError = onError
	}

	func reconcile() {
		guard let node, let session, var symbol = node.symbol, node.scope.isAlive else {
			return
		}

		let changed = previousAsset != symbol.asset
		let square = symbolSquare(
			size: symbol.size,
			content: node.bounds.inset(by: node.style.padding, direction: session.document.direction)
		)
		let fitScale = square.size.width / max(symbol.asset.viewBox.size.width, symbol.asset.viewBox.size.height)
		var linear = STNAffineTransform.identity
		var scaleAncestor: NodeRecord? = node
		var scale = fitScale
		while let item = scaleAncestor {
			let t = item.style.transform
			let values = [
				t.a * linear.a + t.c * linear.b, t.b * linear.a + t.d * linear.b,
				t.a * linear.c + t.c * linear.d, t.b * linear.c + t.d * linear.d,
			]
			guard values.allSatisfy(\.isFinite) else {
				scale = .infinity
				break
			}

			linear = .init(a: values[0], b: values[1], c: values[2], d: values[3])
			let maximum = linear.maximumScale
			scale = fitScale == 0 || maximum == 0 ? 0 : fitScale * maximum
			scaleAncestor = item.parent
		}

		let stroke = symbol.asset.hasStroke ? symbol.strokeWidth : nil
		let retry = changed || previousStroke != stroke || previousScale != scale
		if retry {
			available = true
			failedCodes.removeAll()
			nextRevision(&symbol.generation)
			symbol.inkBounds = symbol.asset.inkBounds(strokeWidth: symbol.strokeWidth)
		}

		var visible = session.symbolHostVisible
		var ancestor: NodeRecord? = node
		while let item = ancestor {
			visible = visible && item.style.visibility == .visible
			ancestor = item.parent
		}

		state.reconcile(
			assetChanged: changed,
			playback: playback,
			reducedMotion: session.environment.reducedMotion.value,
			visible: visible,
			available: available
		)
		if state.resetClock {
			registration?.lastTimestamp = nil
		}

		symbol.effect = state.sample
		symbol.available = available
		if node.symbol != symbol {
			node.symbol = symbol
			session.document.changed(node, .paint)
		}

		previousAsset = symbol.asset
		previousStroke = stroke
		previousScale = scale
	}

	func tick(_ frame: STNFrameTime) {
		guard let node, let session, node.scope.isAlive else {
			return
		}

		state.advance(by: frame.elapsed)
		if node.symbol?.effect != state.sample {
			node.symbol?.effect = state.sample
			session.document.changed(node, .paint)
		}

		session.refreshFrameDemand()
	}

	func receive(_ result: SymbolRenderResult) {
		guard let node, let session, node.scope.isAlive, node.symbol?.generation == result.generation,
			epoch == 0 || epoch == result.epoch
		else {
			return
		}

		if epoch != result.epoch {
			failedCodes.removeAll()
			epoch = result.epoch
		}

		guard let code = result.code else {
			failedCodes.removeAll()
			if !available {
				available = true
				session.document.changed(node, .paint)
			}

			return
		}

		available = false
		let diagnostic: STNSymbolDiagnostic
		switch code {
		case .preparationFailed:
			diagnostic = .init(
				code: .preparationFailed,
				message: "Symbol path preparation failed; replace the asset or change its preparation inputs."
			)
		case .resourceLimitExceeded:
			diagnostic = .init(
				code: .resourceLimitExceeded,
				message: "Symbol preparation exceeded the renderer resource limit; simplify geometry or reduce scale."
			)
		case .renderingFailed:
			diagnostic = .init(
				code: .renderingFailed,
				message: "Symbol raster rendering failed; retry after renderer recovery."
			)
		}

		STNTransaction.perform { session.document.changed(node, .paint) }

		guard failedCodes.insert(String(describing: code)).inserted else {
			return
		}

		ReactiveRuntime.shared.afterCommit { [weak self] in
			guard let self, let node = self.node, node.scope.isAlive, node.symbol?.generation == result.generation
			else {
				return
			}

			if let onError = self.onError {
				onError(diagnostic)
			} else {
				self.session?.report(.nativeFailure(diagnostic.message))
			}
		}
	}
}
