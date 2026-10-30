import AppKit
import Foundation
import Metal
import QuartzCore
import StanaGraphics
import StanaPrimitives
import StanaScene

private actor FrameAdmission {
	static let shared = FrameAdmission()
	private var active = 0
	private var serial: UInt64 = 0
	private var waiting: [(UInt64, CheckedContinuation<Void, any Error>)] = []

	func acquire() async throws -> FramePermit {
		try Task.checkCancellation()
		if active < 6 {
			active += 1
		} else {
			nextRevision(&serial)
			let token = serial
			try await withTaskCancellationHandler {
				try await withCheckedThrowingContinuation { waiting.append((token, $0)) }
			} onCancel: {
				Task { await self.cancel(token) }
			}
		}

		let permit = FramePermit { Task { await self.release() } }
		try Task.checkCancellation()
		return permit
	}

	private func cancel(_ token: UInt64) {
		guard let index = waiting.firstIndex(where: { $0.0 == token }) else {
			return
		}

		waiting.remove(at: index).1.resume(throwing: CancellationError())
	}

	private func release() {
		precondition(active > 0, "Stana: frame admission underflow")
		if waiting.isEmpty {
			active -= 1
		} else {
			waiting.removeFirst().1.resume()
		}
	}

	var accounting: (active: Int, waiting: Int) { (active, waiting.count) }
}

private final class FramePermit: Sendable {
	private let release: @Sendable () -> Void

	init(_ release: @escaping @Sendable () -> Void) {
		self.release = release
	}

	deinit {
		release()
	}
}

@MainActor package final class MetalRenderer: NSObject, Renderer {
	private weak var window: MacOSWindow?
	private let owner: MetalEncoder
	private let layer: MetalLayer
	private var displayLink: CADisplayLink?
	private var desired: SceneSnapshot?
	private var ready: PreparedFrame?
	private var last: PreparedFrame?
	private var preparation: Task<Void, Never>?
	private var permit: FramePermit?
	private var admissionTask: Task<Void, Never>?
	private var presenting = false
	private var animation = false
	private var demand = false
	private var observationsPaused = false
	private var sequence: UInt64 = 0
	private var attachmentGeneration: UInt64 = 0
	private var surfaceSize: STNSize
	private var surfaceScale: Double
	private var retryRevision: UInt64?
	private var failureCount = 0
	private let referenceID = STNNodeID(document: DocumentID(), serial: 1)
	private var geometry: [UInt64: PresentationGeometry] = [:]

	private final class WeakRenderer {
		weak var value: MetalRenderer?

		init(_ value: MetalRenderer) {
			self.value = value
		}
	}

	private static var renderers: [WeakRenderer] = []
	private var workingLinear = false
	private var promotedAt = 0.0
	private var absentSince: Double?
	private var profileDirty = false
	private var drawableAllowance: MetalLease?
	private var drawableBytes = 0
	private let device: MetalDevice
	private var preparationEWMA = 0.0
	private var totalGPUEWMA = 0.0
	private var copyGPUEWMA = 0.0
	private var copyBytesPerFrame = 0.0
	private var requestedRate = 60.0
	private var negotiatedRate = 60.0
	private var sharedCopyTraffic = 0.0
	private var uiTimings: [String: [STNRenderTimingSample]] = [:]
	package private(set) var detached = false
	package private(set) var backingRevision: UInt64 = 0
	package private(set) var surfaceEpoch: UInt64 = 1
	package private(set) var presentation = PresentationTracker()
	package var onPresentation: ((UInt64, Bool) -> Void)?
	package var onFailure: ((String) -> Void)?
	package var onDiagnostic: ((STNNodeID, STNGPUDiagnostic) -> Void)?
	package var onGeometry: ((PresentationGeometry, Bool, Bool) -> Void)?
	var forcedFinalMode = 0
	var rasterDelay = 0.0
	var starved = false

	package init(window: MacOSWindow) throws {
		guard let device = MetalDevice.shared else {
			throw STNError.nativeFailure("Metal device unavailable")
		}

		self.device = device
		surfaceSize = window.view.bounds.size.stana
		surfaceScale = window.nativeWindow.backingScaleFactor
		owner = try MetalEncoder(device: device)
		layer = MetalLayer()
		self.window = window
		super.init()
		layer.install(in: window.view, device: device.device, opaque: window.surfaceOpaque)
		let link = window.view.displayLink(target: self, selector: #selector(tick(_:)))
		link.add(to: .main, forMode: .common)
		link.isPaused = true
		displayLink = link
		Self.renderers.append(WeakRenderer(self))
		switch ProcessInfo.processInfo.environment["STANA_METAL_FINAL_MODE"] {
		case "persistent": forcedFinalMode = 1
		case "direct": forcedFinalMode = 2
		default: break
		}

		if ProcessInfo.processInfo.environment["STANA_METAL_UNTILED"] == "1" {
			forcedFinalMode = 4
		}
	}

	func geometryChanged(size: STNSize, scale: Double) {
		guard size != surfaceSize || scale != surfaceScale else {
			return
		}

		surfaceSize = size
		surfaceScale = scale
		invalidate()
	}

	package func invalidate() {
		guard !detached else {
			return
		}

		nextRevision(&surfaceEpoch)
		backingRevision = 0
		presentation.reset(epoch: surfaceEpoch)
		geometry.removeAll()
		preparation?.cancel()
		admissionTask?.cancel()
		admissionTask = nil
		ready = nil
		last = nil
		desired = nil
		permit = nil
		retryRevision = nil
		observationsPaused = false
		let epoch = surfaceEpoch
		Task { await owner.reset(epoch: epoch) }
		requestFrame()
	}

	package func submit(_ scene: SceneSnapshot) throws -> FrameCompletion {
		guard !detached else {
			throw STNError.nodeDisposed
		}

		guard scene.surfaceEpoch == surfaceEpoch else {
			throw STNError.cancelled
		}

		guard geometry.count < 256, presentation.attempts.count < 256 else {
			observationsPaused = true
			displayLink?.isPaused = true
			throw STNError.cancelled
		}

		let start = CACurrentMediaTime()
		desired = scene
		if window?.isSurface == true, window?.view.window == nil, ready != nil {
			// Unattached chrome keeps the latest capture packet without display confirmation.
			ready = nil
			permit = nil
		}

		refreshColorDemand()
		geometry[scene.sceneRevision] = scene.geometry
		beginPreparation()
		let elapsed = CACurrentMediaTime() - start
		uiTiming("uiTransport", seconds: elapsed, scene: scene.sceneRevision)
		if scene.planningMilliseconds >= 0 {
			uiTiming("uiPlanning", seconds: scene.planningMilliseconds / 1_000, scene: scene.sceneRevision)
		}

		return .init(sceneRevision: scene.sceneRevision, surfaceEpoch: surfaceEpoch, presentationConfirmed: false)
	}

	private func negotiatePresentationRates() -> Bool {
		let peers = Self.renderers.compactMap(\.value)
			.filter {
				!$0.detached && $0.window?.nativeWindow.isVisible == true
					&& $0.window?.nativeWindow.isMiniaturized == false
					&& $0.window?.view.window != nil && $0.window?.view.isHiddenOrHasHiddenAncestor == false
					&& $0.copyBytesPerFrame > 0
			}
		var divisors = peers.map { peer in
			let period = max(peer.preparationEWMA / 0.8, peer.totalGPUEWMA / 0.8, peer.copyGPUEWMA / 0.2)
			return max(1, min(peer.requestedRate, ceil(peer.requestedRate * period)))
		}
		var total = peers.indices.reduce(0.0) {
			$0 + peers[$1].copyBytesPerFrame * peers[$1].requestedRate / divisors[$1]
		}
		let budget = device.copyBandwidth * 0.25
		while total > budget {
			let index = peers.indices.filter { divisors[$0] < peers[$0].requestedRate }
				.max { left, right in
					let l = peers[left], r = peers[right]
					let lw = l.window?.nativeWindow.isKeyWindow == true ? 2.0 : 1
					let rw = r.window?.nativeWindow.isKeyWindow == true ? 2.0 : 1
					return l.copyBytesPerFrame * l.requestedRate / divisors[left] / lw < r.copyBytesPerFrame
						* r.requestedRate / divisors[right] / rw
				}
			guard let index else {
				return false
			}

			total -= peers[index].copyBytesPerFrame * peers[index].requestedRate / divisors[index]
			divisors[index] += 1
			total += peers[index].copyBytesPerFrame * peers[index].requestedRate / divisors[index]
		}

		for index in peers.indices {
			let peer = peers[index]
			let rate = peer.requestedRate / divisors[index]
			peer.negotiatedRate = rate
			peer.sharedCopyTraffic = total
			peer.displayLink?.preferredFrameRateRange = CAFrameRateRange(
				minimum: Float(rate),
				maximum: Float(rate),
				preferred: Float(rate)
			)
		}

		return true
	}

	static func devicePressureRecovered() {
		for renderer in renderers.compactMap(\.value) where !renderer.detached {
			renderer.requestFrame()
		}
	}

	private func refreshColorDemand() {
		Self.renderers.removeAll { $0.value == nil || $0.value?.detached == true }
		guard let native = window?.nativeWindow else {
			return
		}

		let peers = Self.renderers.compactMap(\.value).filter { $0.window?.nativeWindow === native }
		let required = peers.contains {
			$0.desired?.colorMode == .extendedLinear || $0.desired?.paint?.requiresExtended == true
		}
		let now = CACurrentMediaTime()
		for peer in peers {
			let previous = peer.workingLinear
			if required {
				if !peer.workingLinear {
					peer.promotedAt = now
				}

				peer.workingLinear = true
				peer.absentSince = nil
			} else if peer.workingLinear {
				if let absent = peer.absentSince {
					if now - absent >= 10, now - peer.promotedAt >= 5 {
						peer.workingLinear = false
					}
				} else {
					peer.absentSince = now
					Task { @MainActor [weak peer] in
						try? await Task.sleep(for: .seconds(10))
						guard let peer, !peer.detached else {
							return
						}

						peer.refreshColorDemand()
					}
				}
			}

			if previous != peer.workingLinear, peer.desired != nil {
				peer.profileDirty = true
				if peer !== self {
					peer.requestFrame()
				}
			}
		}
	}

	private func beginPreparation() {
		guard !detached, !observationsPaused, preparation == nil, ready == nil, !presenting,
			let scene = desired, let window
		else {
			return
		}

		displayLink?.isPaused = true
		let scale = window.nativeWindow.backingScaleFactor
		refreshColorDemand()
		let linear = workingLinear
		let settings = RenderSettings(
			scale: scale,
			linear: linear,
			headroom: linear && scene.colorMode != .sdr
				? max(1, window.nativeWindow.screen?.maximumExtendedDynamicRangeColorComponentValue ?? 1) : 1,
			forceMode: forcedFinalMode,
			rasterDelay: rasterDelay
		)
		let width = ceil(scene.size.width * scale), height = ceil(scene.size.height * scale)
		guard width.isFinite, height.isFinite, width > 0, height > 0, width <= 16_384, height <= 16_384 else {
			onFailure?("Invalid drawable dimensions")
			return
		}

		let bytes = Int(width) * Int(height) * (linear && scene.colorMode != .sdr ? 8 : 4) * 3
		if drawableBytes != bytes {
			do {
				drawableAllowance = try device.reserve(bytes)
				drawableBytes = bytes
			} catch {
				onFailure?(String(describing: error))
				return
			}
		}

		profileDirty = false

		let owner = owner, id = referenceID
		preparation = Task { @MainActor [weak self] in
			do {
				let heldPermit = try await FrameAdmission.shared.acquire()
				try Task.checkCancellation()
				let frame = try await owner.prepare(scene, settings: settings, referenceID: id)
				guard let self, !self.detached else {
					return
				}

				self.preparation = nil
				guard self.surfaceEpoch == scene.surfaceEpoch else {
					self.beginPreparation()
					self.requestFrame()
					return
				}

				self.backingRevision = max(self.backingRevision, scene.sceneRevision)
				self.last = frame
				self.preparationEWMA =
					self.preparationEWMA == 0
					? frame.preparationSeconds : self.preparationEWMA * 0.8 + frame.preparationSeconds * 0.2
				for diagnostic in await owner.drainDiagnostics() {
					self.onDiagnostic?(diagnostic.node, diagnostic.diagnostic)
				}

				self.ready = frame
				self.permit = heldPermit
				self.presentReady()
			} catch {
				guard let self, !self.detached else {
					return
				}

				self.preparation = nil
				guard self.surfaceEpoch == scene.surfaceEpoch else {
					self.beginPreparation()
					self.requestFrame()
					return
				}

				if !(error is CancellationError), error as? STNError != .cancelled {
					let message = String(describing: error)
					self.onFailure?(message)
					await owner.failed(message)
					if (error as? MetalFailure)?.kind == .execution {
						self.failureCount += 1
						if self.failureCount == 1 {
							self.invalidate()
						}
					}
				} else {
					self.requestFrame()
				}
			}
		}
	}

	func requestFrame() {
		guard !detached else {
			return
		}

		demand = true
		if ready != nil {
			presentReady()
		} else if !observationsPaused, preparation == nil, !presenting {
			displayLink?.isPaused = false
		}
	}

	func sheetAttached() {
		guard let window else {
			return
		}

		// Sheet reparenting can strand pre-attachment drawable queues.
		// Replace the queue, not prepared state.
		nextRevision(&attachmentGeneration)
		presentation.reset(epoch: surfaceEpoch)
		presenting = false
		ready = ready ?? last
		layer.install(in: window.view, device: device.device, opaque: window.surfaceOpaque)
		visibilityChanged()
	}

	func visibilityChanged() {
		guard !detached else {
			return
		}

		if ready != nil {
			presentReady()
		}

		requestFrame()
	}

	func setAnimationDemand(_ active: Bool) {
		animation = active
		if active {
			requestFrame()
		} else if !demand {
			displayLink?.isPaused = true
		}
	}

	@objc private func tick(_ link: CADisplayLink) {
		link.isPaused = true
		guard !detached, !observationsPaused, let window, window.view.window != nil,
			window.nativeWindow.isVisible, !window.nativeWindow.isMiniaturized
		else {
			return
		}

		if ready != nil {
			presentReady()
			return
		}

		guard preparation == nil, !presenting else {
			return
		}

		let requested = demand
		demand = false
		let start = CACurrentMediaTime()
		window.onFrame?(link.timestamp, link.targetTimestamp)
		window.onDraw?()
		let revision = desired?.sceneRevision ?? 0
		let elapsed = CACurrentMediaTime() - start
		uiTiming("uiFrameOccupancy", seconds: elapsed, scene: revision)
		if preparation == nil, profileDirty || desired?.sceneRevision != last?.scene.sceneRevision {
			beginPreparation()
		}

		if preparation == nil, requested, !profileDirty, let last, last.scene.surfaceEpoch == surfaceEpoch {
			ready = last
			presentReady()
		}

		if preparation == nil, !presenting, animation {
			link.isPaused = false
		}
	}

	private func presentReady() {
		guard !detached, !presenting, !observationsPaused, !starved, let frame = ready, let window,
			window.view.window != nil, window.nativeWindow.isVisible, !window.nativeWindow.isMiniaturized
		else {
			return
		}

		guard frame.scene.surfaceEpoch == surfaceEpoch else {
			ready = nil
			permit = nil
			requestFrame()
			return
		}

		guard presentation.attempts.count < 256 else {
			observationsPaused = true
			displayLink?.isPaused = true
			return
		}

		if permit == nil {
			guard admissionTask == nil else {
				return
			}

			admissionTask = Task { @MainActor [weak self] in
				do {
					let permit = try await FrameAdmission.shared.acquire()
					guard let self else {
						return
					}

					self.admissionTask = nil
					guard !self.detached, self.ready === frame, self.surfaceEpoch == frame.scene.surfaceEpoch else {
						return
					}

					self.permit = permit
					self.presentReady()
				} catch {
					self?.admissionTask = nil
				}
			}
			return
		}

		let pixels =
			ceil(frame.scene.size.width * frame.settings.scale) * ceil(frame.scene.size.height * frame.settings.scale)
		copyBytesPerFrame =
			pixels
			* Double((frame.settings.linear && frame.scene.colorMode != .sdr ? 8 : 4) + (frame.settings.linear ? 8 : 4))
		if let inputs = frame.surface.directInputs {
			copyBytesPerFrame = pixels * 4
			for input in inputs {
				for tile in input.surface.tiles {
					copyBytesPerFrame +=
						Double(tile.core.width * tile.core.height) * frame.settings.scale * frame.settings.scale
						* Double(input.surface.linear ? 16 : 12)
				}
			}
		}

		requestedRate = Double(max(1, window.nativeWindow.screen?.maximumFramesPerSecond ?? 60))
		guard negotiatePresentationRates() else {
			return
		}

		layer.configure(
			bounds: window.view.bounds,
			size: CGSize(
				width: ceil(frame.scene.size.width * frame.settings.scale),
				height: ceil(frame.scene.size.height * frame.settings.scale)
			),
			scale: frame.settings.scale,
			opaque: window.surfaceOpaque,
			extended: frame.settings.linear && frame.scene.colorMode != .sdr
		)

		ready = nil
		presenting = true
		nextRevision(&sequence)
		let attempt = PresentationAttemptID(epoch: surfaceEpoch, sequence: sequence, scene: frame.scene.sceneRevision)
		let generation = attachmentGeneration
		let targetTimestamp = frame.scene.targetTimestamp
		let framePeriod = frame.scene.framePeriod
		let heldPermit = permit
		let heldAllowance = drawableAllowance
		permit = nil
		Task { @MainActor [weak self, owner, layer] in
			defer {
				withExtendedLifetime((heldPermit, heldAllowance)) {}
			}

			do {
				let result = try await owner.present(
					frame,
					layer: layer,
					onSubmitted: { [weak self] in
						guard let self, !self.detached, self.surfaceEpoch == attempt.epoch,
							self.attachmentGeneration == generation
						else {
							return false
						}

						self.presentation.submitted(attempt)
						self.watch(attempt)
						return true
					}
				) { [weak self] timestamp in
					let enqueued = CACurrentMediaTime()
					Task { @MainActor in
						guard let self, !self.detached, self.surfaceEpoch == attempt.epoch,
							self.attachmentGeneration == generation
						else {
							return
						}

						if self.presentation.presented(attempt, timestamp: timestamp) {
							self.publish(attempt.scene, confirmed: true)
						}

						self.uiTiming(
							"acknowledgementDelivery",
							seconds: CACurrentMediaTime() - enqueued,
							scene: attempt.scene
						)
						await self.owner.count(
							timestamp > 0 ? "positivePresentationObservations" : "zeroPresentationObservations"
						)
						if timestamp > 0 {
							self.uiTiming(
								"presentedTimestampDelay",
								seconds: max(0, enqueued - timestamp),
								scene: attempt.scene
							)
							if targetTimestamp > 0 {
								let lateness = max(0, timestamp - targetTimestamp)
								self.uiTiming("presentationTargetLateness", seconds: lateness, scene: attempt.scene)
								if framePeriod > 0, lateness > framePeriod * 0.5 {
									await self.owner.count("missedPresentationTargets")
								}
							}
						}
					}
				}
				guard let self, !self.detached, self.surfaceEpoch == attempt.epoch,
					self.attachmentGeneration == generation
				else {
					return
				}

				if result == nil {
					self.presenting = false
					self.ready = frame
					self.permit = heldPermit
					Task { @MainActor [weak self] in
						try? await Task.sleep(for: .milliseconds(16))
						self?.requestFrame()
					}
					return
				}

				let copy = result ?? 0
				self.copyGPUEWMA = self.copyGPUEWMA == 0 ? copy : self.copyGPUEWMA * 0.8 + copy * 0.2
				let total = copy + frame.offscreenSeconds
				self.totalGPUEWMA = self.totalGPUEWMA == 0 ? total : self.totalGPUEWMA * 0.8 + total * 0.2
				self.failureCount = 0
				if self.presentation.gpu(attempt, success: true) {
					self.publish(attempt.scene, confirmed: true)
				}

				self.presenting = false
				if self.desired?.sceneRevision != frame.scene.sceneRevision {
					self.beginPreparation()
				} else if self.animation || self.demand {
					self.requestFrame()
				}
			} catch {
				guard let self, !self.detached, self.attachmentGeneration == generation else {
					return
				}

				self.presenting = false
				if self.surfaceEpoch != attempt.epoch || error as? STNError == .cancelled {
					self.requestFrame()
					return
				}

				_ = self.presentation.gpu(attempt, success: false)
				self.publish(attempt.scene, confirmed: false)
				self.onFailure?(String(describing: error))
				self.failureCount += 1
				if self.failureCount == 1 {
					self.invalidate()
				} else {
					self.observationsPaused = true
					self.displayLink?.isPaused = true
				}
			}
		}
	}

	private func watch(_ attempt: PresentationAttemptID) {
		Task { @MainActor [weak self] in
			try? await Task.sleep(for: .seconds(1))
			guard let self, !self.detached, self.surfaceEpoch == attempt.epoch,
				self.presentation.confirmed?.sequence != attempt.sequence
			else {
				return
			}

			self.presentation.markUnknown(attempt)
			if self.presentation.ambiguous == attempt {
				self.publish(attempt.scene, confirmed: false)
				if self.retryRevision != attempt.scene, !self.presenting, self.ready == nil {
					self.retryRevision = attempt.scene
					self.ready = self.last
					self.presentReady()
				}
			}
		}
	}

	private func publish(_ scene: UInt64, confirmed: Bool) {
		onPresentation?(scene, confirmed)
		if let snapshot = geometry[scene] {
			onGeometry?(snapshot, confirmed, presentation.ambiguous != nil)
		}

		if confirmed {
			geometry = geometry.filter { $0.key >= scene }
		}

		if confirmed, observationsPaused, geometry.count < 256, presentation.attempts.count < 256 {
			observationsPaused = false
			requestFrame()
		}
	}

	private func uiTiming(_ name: String, seconds: Double, scene: UInt64) {
		guard seconds.isFinite, seconds >= 0 else {
			return
		}

		if uiTimings[name, default: []].count >= 8_192 {
			uiTimings[name]?.removeFirst()
		}

		uiTimings[name, default: []].append(.init(sceneRevision: scene, milliseconds: seconds * 1_000))
	}

	func recordInput(arrival: Double, start: Double) {
		let revision = desired?.sceneRevision ?? 0
		if arrival > 0, start >= arrival {
			uiTiming("inputArrivalToDispatch", seconds: start - arrival, scene: revision)
		}

		uiTiming("uiInputOccupancy", seconds: CACurrentMediaTime() - start, scene: revision)
	}

	func configureForTesting(mode: Int, rasterDelay: Double, starved: Bool) {
		forcedFinalMode = mode
		self.rasterDelay = max(0, min(1, rasterDelay))
		self.starved = starved
		if !starved {
			requestFrame()
		}
	}

	func prepareOffscreenForTesting(_ scene: SceneSnapshot) async throws {
		guard !detached, let window else {
			throw STNError.nodeDisposed
		}

		let settings = RenderSettings(
			scale: window.nativeWindow.backingScaleFactor,
			linear: scene.paint?.requiresExtended == true || scene.colorMode == .extendedLinear,
			headroom: 1,
			forceMode: forcedFinalMode,
			rasterDelay: rasterDelay
		)
		let frame = try await owner.prepare(scene, settings: settings, referenceID: referenceID)
		last = frame
		backingRevision = scene.sceneRevision
		for diagnostic in await owner.drainDiagnostics() {
			onDiagnostic?(diagnostic.node, diagnostic.diagnostic)
		}
	}

	func capture() async throws -> STNRenderedImage {
		guard !detached, let last else {
			throw STNError.nativeFailure("No completed offscreen frame")
		}

		return try await owner.readback(last)
	}

	func report() async throws -> STNRenderingDiagnostics {
		guard !detached else {
			throw STNError.nodeDisposed
		}

		let worker = await RasterWorkers.shared.accounting
		let admission = await FrameAdmission.shared.accounting
		let native = await owner.report(
			linear: workingLinear,
			confirmed: presentation.confirmed?.scene,
			timestamp: presentation.confirmedTimestamp
		)
		let ui: [String: Double] = [
			"requestedPresentationRate": requestedRate, "negotiatedPresentationRate": negotiatedRate,
			"copyBandwidthBytesPerSecond": device.copyBandwidth,
			"devicePresentationCopyBytesPerSecond": sharedCopyTraffic,
			"desiredSceneRevision": Double(desired?.sceneRevision ?? 0),
			"readySceneRevision": Double(ready?.scene.sceneRevision ?? 0),
			"preparing": preparation == nil ? 0 : 1, "presenting": presenting ? 1 : 0,
			"observationsPaused": observationsPaused ? 1 : 0, "trackedAttempts": Double(presentation.attempts.count),
			"geometryHistory": Double(geometry.count), "workerLimit": Double(worker.limit),
			"activeWorkers": Double(worker.active), "peakWorkers": Double(worker.peak),
			"waitingWorkers": Double(worker.waiting),
			"deviceExecutionPackets": Double(admission.active), "waitingExecutionPackets": Double(admission.waiting),
		]
		let counters = native.counters.merging(ui, uniquingKeysWith: { _, value in value })
		let samples = native.timingSamples.merging(uiTimings, uniquingKeysWith: { _, value in value })
		return .init(
			device: native.device,
			workingLinear: workingLinear,
			failure: native.lastFailure,
			confirmedRevision: native.confirmedSceneRevision,
			confirmedTime: native.confirmedPresentationTime,
			counters: counters,
			timingSamples: samples
		)
	}

	package func detach() {
		guard !detached else {
			return
		}

		detached = true
		displayLink?.invalidate()
		displayLink = nil
		preparation?.cancel()
		admissionTask?.cancel()
		admissionTask = nil
		desired = nil
		ready = nil
		last = nil
		permit = nil
		onPresentation = nil
		onFailure = nil
		onDiagnostic = nil
		onGeometry = nil
		geometry.removeAll()
		window?.view.layer = nil
		drawableAllowance = nil
		drawableBytes = 0
		refreshColorDemand()
		window = nil
		Task { await owner.reset(epoch: 0) }
	}
}

extension MacOSWindow {
	package func capture() async throws -> STNRenderedImage {
		if graphics.detached, let backing, let bytes = backing.data {
			return .init(
				width: backing.width,
				height: backing.height,
				format: .premultipliedBGRA8,
				sceneRevision: renderer.backingRevision,
				data: Data(bytes: bytes, count: backing.bytesPerRow * backing.height)
			)
		}

		return try await graphics.capture()
	}

	package func renderingDiagnostics() async throws -> STNRenderingDiagnostics {
		try await graphics.report()
	}
}
