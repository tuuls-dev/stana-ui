import Foundation
import Stana
import StanaAccessibility
import StanaCore
import StanaGraphics
import StanaPrimitives
import StanaScene
import StanaText

/// A deterministic public consumer host. Never creates NSApplication or a window.
@MainActor public final class STNTestHost {
	private let session: MountSession
	private var backingRevision: UInt64 = 0
	private var presentation = PresentationTracker()
	private var submissionSequence: UInt64 = 0
	private var attempts: [UInt64: (PresentationAttemptID, PresentationGeometry)] = [:]

	/// Uses the same last-confirmed/unknown-failure policy as native interaction.
	public func enablePresentationTesting() {
		session.document.usesPresentationGeometry = true
	}

	public func reportGPUCompletion(submission: UInt64, success: Bool) {
		guard let (id, geometry) = attempts[submission] else { return }
		if presentation.gpu(id, success: success) {
			session.document.publishPresentation(
				geometry,
				confirmed: true,
				preserveAmbiguity: presentation.ambiguous != nil
			)
		} else if !success {
			session.document.publishPresentation(geometry, confirmed: false)
		}
	}

	public func reportPresentation(submission: UInt64, timestamp: Double) {
		guard let (id, geometry) = attempts[submission] else { return }
		if presentation.presented(id, timestamp: timestamp) {
			session.document.publishPresentation(
				geometry,
				confirmed: true,
				preserveAmbiguity: presentation.ambiguous != nil
			)
			attempts = attempts.filter { $0.key >= submission }
		}
	}

	public func reportPresentationUnknown(submission: UInt64) {
		guard let (id, geometry) = attempts[submission] else { return }
		presentation.markUnknown(id)
		if presentation.ambiguous == id { session.document.publishPresentation(geometry, confirmed: false) }
	}

	public init(size: STNSize = .init(width: 800, height: 600), environment: STNEnvironment = .init()) {
		session = MountSession(size: size, text: TestTextService(), environment: environment)
	}

	public var environment: STNEnvironment {
		session.environment
	}

	public var metrics: STNMetrics {
		session.document.metrics
	}

	public var nodeIDs: [STNNodeID] {
		nodes.map(\.id)
	}

	public var textValues: [String] {
		nodes.filter { $0.kind == "text" }.map(\.text)
	}

	/// The last complete published snapshot, including during a collecting batch.
	public var nodes: [STNNodeSnapshot] {
		session.nodeSnapshots
	}

	public func queryNodes() throws -> [STNNodeSnapshot] {
		try session.document.snapshots()
	}

	public var semantics: STNSemanticSnapshot {
		session.semanticSnapshot ?? session.semantics.snapshot()
	}

	public var errors: [STNError] {
		session.errors
	}

	public var needsDisplay: Bool {
		session.document.dirty.contains(.paint)
	}

	public func mount(@STNBuilder _ content: () -> STNGroup) {
		session.mount(content)
	}

	public func flush() {
		session.commit()
	}

	/// Runs one admitted animation transaction using an explicit monotonic clock.
	public func advanceFrame(timestamp: Double, targetTimestamp: Double) {
		precondition(timestamp.isFinite && targetTimestamp.isFinite && targetTimestamp >= timestamp)
		session.tickFrames(timestamp: timestamp, target: targetTimestamp)
	}

	public func activate(_ id: STNNodeID) throws {
		_ = try session.document.resolve(id)
		session.document.activate(id)
	}

	public func focus(_ id: STNNodeID) throws {
		guard session.document.isEligible(id) else {
			throw STNError.notFocusable
		}

		session.document.setFocus(id)
	}

	public func tab(backward: Bool = false) {
		session.document.focusNext(backward: backward)
	}

	public func click(at point: STNPoint, shift: Bool = false, clickCount: Int = 1, button: Int = 0) {
		_ = session.pointer(0, at: point, shift: shift, clickCount: clickCount, button: button)
		_ = session.pointer(2, at: point, shift: shift, clickCount: clickCount, button: button)
	}

	public func pointerDown(at point: STNPoint, shift: Bool = false, clickCount: Int = 1, button: Int = 0) {
		_ = session.pointer(0, at: point, shift: shift, clickCount: clickCount, button: button)
	}

	public func pointerMove(to point: STNPoint) {
		_ = session.pointer(1, at: point)
	}

	public func pointerUp(at point: STNPoint) {
		_ = session.pointer(2, at: point)
	}

	public func cancelPointer() {
		_ = session.pointer(4, at: .zero)
	}

	/// Advances caret blinking and edge-drag autoscrolling without wall-clock waits.
	public func advanceEditorTime(by seconds: Double) {
		precondition(seconds.isFinite && seconds >= 0)
		session.tickEditors(by: seconds)
	}

	public func resize(to size: STNSize) {
		session.document.viewport = size
		session.document.changed(session.document.root, .all)
	}

	public func insertText(_ value: String) {
		session.edit(1, text: value, range: nil, selected: .init(location: 0, length: 0))
	}

	public func setMarkedText(_ value: String, selectedRange: NSRange) {
		session.edit(2, text: value, range: nil, selected: selectedRange)
	}

	public func commitMarkedText() {
		session.edit(3, text: "", range: nil, selected: .init(location: 0, length: 0))
	}

	public func select(_ range: NSRange) throws {
		guard let focused = session.document.focused, let editor = session.editors[focused] else {
			throw STNError.notFocusable
		}

		try editor.select(range)
	}

	/// Records the current complete scene. Withhold acknowledgement to emulate a dropped frame.
	public func render(acknowledge: Bool = true) -> STNRecordedFrame? {
		guard needsDisplay else {
			return nil
		}

		let scene = session.scene.build(surfaceEpoch: 1, backingRevision: backingRevision)
		nextRevision(&submissionSequence)
		let id = PresentationAttemptID(epoch: 1, sequence: submissionSequence, scene: scene.sceneRevision)
		presentation.submitted(id)
		if let geometry = scene.geometry { attempts[submissionSequence] = (id, geometry) }
		if acknowledge {
			backingRevision = scene.sceneRevision
		}

		return .init(
			documentRevision: scene.documentRevision,
			sceneRevision: scene.sceneRevision,
			damage: scene.damage,
			commandCount: scene.commands.count,
			submissionSequence: submissionSequence
		)
	}

	public func command(_ selector: String) {
		session.edit(4, text: selector, range: nil, selected: .init(location: 0, length: 0))
	}

	public func editorState(_ id: STNNodeID) -> STNEditorSnapshot? {
		guard let editor = session.editors[id], let node = session.document.nodes[id] else {
			return nil
		}

		return .init(
			text: node.style.secure ? "<secure>" : editor.text,
			selection: editor.selection,
			markedText: node.style.secure ? nil : editor.markedText,
			revision: editor.revision,
			undoCount: editor.undoCount
		)
	}

	public func close() {
		session.close()
	}
}

public struct STNRecordedFrame: Sendable {
	public let documentRevision: UInt64
	public let sceneRevision: UInt64
	public let damage: [STNRect]
	public let commandCount: Int
	public let submissionSequence: UInt64
}

public struct STNEditorSnapshot: Equatable, Sendable {
	public let text: String
	public let selection: NSRange
	public let markedText: String?
	public let revision: UInt64
	public let undoCount: Int
}
