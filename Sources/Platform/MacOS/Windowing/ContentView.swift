import AppKit
import QuartzCore
import StanaPrimitives

@MainActor
final class ContentView: NSView, @MainActor NSTextInputClient, NSMenuItemValidation, @MainActor NSServicesMenuRequestor
{
	weak var host: MacOSWindow?
	nonisolated let accessibilityStore = AccessibilityStore()
	var textSnapshot: NativeTextSnapshot?
	var editing = false
	var textIdentity: UInt64 = 0
	var textReadOnly = false
	var textCanUndo = false
	var textCanRedo = false
	var textPolicies: [Int32] = []
	var checkingSession: TextCheckingSession?
	var serviceIdentity: UInt64 = 0
	var serviceRevision: UInt64 = 0
	var serviceSelection = NSRange()
	var insertedRange = NSRange()
	var textUserInsertion = false
	private var tracking: NSTrackingArea?

	override var isFlipped: Bool { true }

	override var isOpaque: Bool { host?.surfaceOpaque ?? false }

	override var acceptsFirstResponder: Bool { true }

	override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
		true
	}

	override var needsPanelToBecomeKey: Bool {
		if let event = NSApp.currentEvent, let host, let pointer = host.onPointer {
			let point = convert(event.locationInWindow, from: nil)
			return pointer(3, .init(x: point.x, y: point.y), false, 1, 0) != 0
		}

		return editing
	}

	override func viewDidMoveToWindow() {
		super.viewDidMoveToWindow()
		if window != nil {
			host?.graphics?.visibilityChanged()
		}

		if let window, editing {
			window.makeFirstResponder(self)
			inputContext?.activate()
		}
	}

	override func setFrameSize(_ newSize: NSSize) {
		super.setFrameSize(newSize)
		host?.resized()
	}

	override func resignFirstResponder() -> Bool {
		guard super.resignFirstResponder() else {
			return false
		}

		let root = (window as? HostWindow)?.host ?? (window as? HostPanel)?.host
		if host?.applyingConfiguration != true, root?.applyingConfiguration != true, host?.closed != true {
			host?.emit(.surfaceFocus(false))
		}

		return true
	}

	override func updateTrackingAreas() {
		super.updateTrackingAreas()
		if let tracking {
			removeTrackingArea(tracking)
		}

		let area = NSTrackingArea(
			rect: .zero,
			options: [.mouseMoved, .cursorUpdate, .activeInKeyWindow, .inVisibleRect],
			owner: self
		)
		tracking = area
		addTrackingArea(area)
	}

	override func draw(_ dirtyRect: NSRect) {
		guard let host, host.graphics?.detached == true else {
			return
		}

		host.onDraw?()
		guard let image = host.backing?.makeImage(), let context = NSGraphicsContext.current?.cgContext else {
			return
		}

		context.clear(bounds)
		context.saveGState()
		context.translateBy(x: 0, y: bounds.height)
		context.scaleBy(x: 1, y: -1)
		context.draw(image, in: bounds)
		context.restoreGState()
	}

	private func pointer(_ event: NSEvent, phase: Int) -> Int32 {
		guard let host else {
			return 0
		}

		let start = CACurrentMediaTime()
		defer {
			host.graphics.recordInput(arrival: event.timestamp, start: start)
		}

		let point = convert(event.locationInWindow, from: nil)
		let portable = STNPoint(x: point.x, y: point.y)
		if let handler = host.onPointer {
			return handler(phase, portable, event.modifierFlags.contains(.shift), event.clickCount, event.buttonNumber)
		}

		host.emit(.pointer(phase, portable))
		return 0
	}

	override func mouseDown(with event: NSEvent) {
		if editing, hasMarkedText(), inputContext?.handleEvent(event) == true {
			return
		}

		let action = pointer(event, phase: 0)
		if action == 1, let host, host.nativeWindow.isMovable {
			host.beginTracking()
			host.nativeWindow.performDrag(with: event)
		} else if action >= 16, let host, host.nativeWindow.styleMask.contains(.resizable) {
			host.resize(event, edges: action & 15)
		}
	}

	override func mouseDragged(with event: NSEvent) {
		if host?.resizeEdges != 0 {
			host?.resize(event, edges: 0)
		} else {
			_ = pointer(event, phase: 1)
		}
	}

	override func mouseMoved(with event: NSEvent) {
		_ = pointer(event, phase: 1)
		cursorUpdate(with: event)
	}

	override func mouseUp(with event: NSEvent) {
		if host?.resizeEdges != 0 {
			host?.resize(event, edges: -1)
		} else {
			_ = pointer(event, phase: 2)
		}
	}

	override func rightMouseDown(with event: NSEvent) {
		_ = pointer(event, phase: 0)
		_ = pointer(event, phase: 2)
		super.rightMouseDown(with: event)
	}

	override func cursorUpdate(with event: NSEvent) {
		let point = convert(event.locationInWindow, from: nil)
		let text = host?.onPointer?(3, .init(x: point.x, y: point.y), false, 1, 0) == 1
		(text ? NSCursor.iBeam : NSCursor.arrow).set()
	}

	override func scrollWheel(with event: NSEvent) {
		let start = CACurrentMediaTime()
		let point = convert(event.locationInWindow, from: nil)
		host?.emit(.scroll(.init(x: point.x, y: point.y), event.scrollingDeltaX, event.scrollingDeltaY))
		host?.graphics.recordInput(arrival: event.timestamp, start: start)
	}

	override func performKeyEquivalent(with event: NSEvent) -> Bool {
		let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
		if editing, event.modifierFlags.contains(.command), ["a", "c", "v", "x", "z"].contains(key) {
			keyDown(with: event)
			return true
		}

		return super.performKeyEquivalent(with: event)
	}

	override func keyDown(with event: NSEvent) {
		let start = CACurrentMediaTime()
		defer {
			host?.graphics.recordInput(arrival: event.timestamp, start: start)
		}

		let characters = event.charactersIgnoringModifiers ?? ""
		if editing {
			if event.modifierFlags.contains(.command) {
				let commands = [
					"a": "selectAll:", "c": "copy:", "v": "paste:", "x": "cut:",
					"z": event.modifierFlags.contains(.shift) ? "redo:" : "undo:",
				]
				if let command = commands[characters.lowercased()] {
					doCommand(by: NSSelectorFromString(command))
					return
				}
			}

			interpretKeyEvents([event])
		} else {
			host?.emit(.key(characters, event.modifierFlags.contains(.shift), event.modifierFlags.contains(.command)))
		}
	}

	override func viewDidChangeEffectiveAppearance() {
		super.viewDidChangeEffectiveAppearance()
		let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
		host?.currentDark = dark
		host?
			.emit(
				.appearance(
					dark,
					NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast,
					NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
				)
			)
	}
}

extension MacOSWindow {
	func beginTracking() {
		dragTimer?.invalidate()
		draggingWindow = true
		let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] timer in
			if self == nil {
				timer.invalidate()
				return
			}

			MainActor.assumeIsolated {
				guard let self, !self.closed, NSEvent.pressedMouseButtons & 1 != 0 else {
					self?.dragTimer?.invalidate()
					self?.dragTimer = nil
					self?.draggingWindow = false
					self?.resizeEdges = 0
					self?.publishState()
					self?.onIdle?()
					return
				}
			}
		}
		dragTimer = timer
		RunLoop.main.add(timer, forMode: .common)
	}

	func resize(_ event: NSEvent, edges: Int32) {
		if edges > 0 {
			resizeEdges = edges
			resizeOriginal = nativeWindow.frame
			resizeStart = nativeWindow.convertPoint(toScreen: event.locationInWindow)
			beginTracking()
			return
		}

		if edges < 0 {
			dragTimer?.invalidate()
			dragTimer = nil
			resizeEdges = 0
			draggingWindow = false
			publishState()
			onIdle?()
			return
		}

		guard resizeEdges != 0, !closed else {
			return
		}

		let point = nativeWindow.convertPoint(toScreen: event.locationInWindow)
		let dx = point.x - resizeStart.x, dy = point.y - resizeStart.y
		var frame = resizeOriginal
		if resizeEdges & 1 != 0 {
			frame.size.height += dy
		}

		if resizeEdges & 2 != 0 {
			frame.origin.x += dx
			frame.size.width -= dx
		}

		if resizeEdges & 4 != 0 {
			frame.origin.y += dy
			frame.size.height -= dy
		}

		if resizeEdges & 8 != 0 {
			frame.size.width += dx
		}

		frame = constrain(frame)
		if resizeEdges & 2 != 0 {
			frame.origin.x = resizeOriginal.maxX - frame.width
		}

		if resizeEdges & 4 != 0 {
			frame.origin.y = resizeOriginal.maxY - frame.height
		}

		nativeWindow.setFrame(frame, display: true)
	}
}
