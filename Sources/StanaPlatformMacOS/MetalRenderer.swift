import CStanaMacOS
import Foundation
import StanaGraphics
import StanaPrimitives
import StanaScene

@MainActor package final class MetalRenderer: Renderer {
	private weak var window: MacOSWindow?
	package private(set) var backingRevision: UInt64 = 0
	package private(set) var surfaceEpoch: UInt64 = 1
	package private(set) var presentation = PresentationTracker()
	package var onPresentation: ((UInt64, Bool) -> Void)?
	package var onFailure: ((String) -> Void)?
	package var onDiagnostic: ((STNGPUDiagnostic) -> Void)?
	package var onGeometry: ((PresentationGeometry, Bool, Bool) -> Void)?
	private var geometry: [UInt64: PresentationGeometry] = [:]
	private let encoder = MetalSceneEncoder()
	private var executionFailureCount = 0
	private var requiresRecovery = false
	private var observationsPaused = false

	package init(window: MacOSWindow) throws {
		self.window = window
		guard let handle = window.handle, stn_metal_initialize(handle) else {
			throw STNError.nativeFailure("Metal device or command queue unavailable")
		}
	}

	package func invalidate() {
		nextRevision(&surfaceEpoch)
		backingRevision = 0
		presentation.reset(epoch: surfaceEpoch)
		geometry.removeAll()
		observationsPaused = false
		if let handle = window?.handle { stn_metal_invalidate(handle) }
	}

	package func submit(_ scene: SceneSnapshot) throws -> FrameCompletion {
		guard let handle = window?.handle else { throw STNError.nodeDisposed }
		if requiresRecovery {
			requiresRecovery = false
			executionFailureCount = 0
			invalidate()
			throw STNError.cancelled
		}
		if geometry.count >= 256 {
			if !observationsPaused {
				observationsPaused = true
				stn_metal_pause_observations(handle, true)
				onFailure?(
					"Presentation observation history exhausted; admission is suspended until a usable acknowledgement or renderer recovery"
				)
			}
			throw STNError.cancelled
		}
		let start = ProcessInfo.processInfo.systemUptime
		let bytes = try encoder.encode(scene)
		geometry[scene.sceneRevision] = scene.geometry
		let accepted = bytes.withUnsafeBytes {
			stn_metal_submit(handle, $0.bindMemory(to: UInt8.self).baseAddress, $0.count)
		}
		stn_metal_ui_timing(
			handle,
			scene.sceneRevision,
			scene.planningMilliseconds,
			(ProcessInfo.processInfo.systemUptime - start) * 1000
		)
		guard accepted else { throw STNError.nativeFailure("Metal packet rejected") }
		return .init(sceneRevision: scene.sceneRevision, surfaceEpoch: surfaceEpoch, presentationConfirmed: false)
	}

	package func receive(_ event: stn_event) {
		guard event.epoch == surfaceEpoch else { return }
		let id = PresentationAttemptID(epoch: event.epoch, sequence: event.sequence, scene: event.identity)
		switch event.kind {
		case 23:
			if let diagnostic = try? JSONDecoder().decode(STNGPUDiagnostic.self, from: Data(event.text.string.utf8)) {
				onDiagnostic?(diagnostic)
			}
		case 17:
			backingRevision = max(backingRevision, event.identity)
		case 21:
			presentation.submitted(id)
			Task { @MainActor [weak self] in
				try? await Task.sleep(for: .seconds(1))
				guard let self, self.presentation.confirmed?.sequence != id.sequence else { return }
				self.presentation.markUnknown(id)
				if self.presentation.ambiguous == id {
					self.publish(id.scene, confirmed: false)
					if let handle = self.window?.handle { stn_metal_retry(handle, id.scene) }
				}
			}
		case 18:
			executionFailureCount = 0
			if presentation.gpu(id, success: true) { publish(id.scene, confirmed: true) }
		case 19:
			if presentation.presented(id, timestamp: event.x) { publish(id.scene, confirmed: true) }
		case 20:
			if event.sequence > 0 {
				_ = presentation.gpu(id, success: false)
				publish(id.scene, confirmed: false)
			}
			if event.sequence == 0 { geometry.removeValue(forKey: event.identity) }
			onFailure?(event.text.string)
		case 24:
			if event.sequence > 0 {
				_ = presentation.gpu(id, success: false)
				publish(id.scene, confirmed: false)
			}
			executionFailureCount += 1
			if executionFailureCount == 1 { invalidate() } else { requiresRecovery = true; backingRevision = 0 }
			onFailure?(event.text.string)
		default: break
		}
	}

	private func publish(_ scene: UInt64, confirmed: Bool) {
		onPresentation?(scene, confirmed)
		if let snapshot = geometry[scene] { onGeometry?(snapshot, confirmed, presentation.ambiguous != nil) }
		if confirmed { geometry = geometry.filter { $0.key >= scene } }
		if confirmed, observationsPaused, geometry.count < 256 {
			observationsPaused = false
			if let handle = window?.handle { stn_metal_pause_observations(handle, false) }
		}
	}

	package func detach() {
		if let handle = window?.handle { stn_metal_detach(handle) }
		onPresentation = nil
		onFailure = nil
		onDiagnostic = nil
		onGeometry = nil
		geometry.removeAll()
		window = nil
	}
}
