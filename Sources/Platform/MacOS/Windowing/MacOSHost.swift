import AppKit
import Foundation
import StanaAccessibility
import StanaGraphics
import StanaPlatform
import StanaPrimitives
import StanaText

@MainActor package final class MacOSHost: PlatformHost {
	package let textService: any TextService = CoreTextService()

	package init() {}

	package func createWindow(title: String, size: STNSize, options: STNWindowOptions) throws -> any PlatformWindow {
		try MacOSWindow(title: title, size: size, options: options)
	}

	package func createSurface(in window: any PlatformWindow, size: STNSize) throws -> any PlatformWindow {
		guard let parent = window as? MacOSWindow, !parent.closed else {
			throw STNWindowError.closed
		}

		return try MacOSWindow(title: "", size: size, options: parent.options, parent: parent)
	}

	package func run() {
		NativeApplication.run()
	}
}

@MainActor final class HostWindow: NSWindow {
	weak var host: MacOSWindow?

	override var canBecomeKey: Bool { host?.options.interaction.canBecomeKey != .disabled }

	override var canBecomeMain: Bool { host?.options.interaction.canBecomeMain != .disabled }
}

@MainActor final class HostPanel: NSPanel {
	weak var host: MacOSWindow?

	override var canBecomeKey: Bool { host?.options.interaction.canBecomeKey != .disabled }

	override var canBecomeMain: Bool { host?.options.interaction.canBecomeMain == .enabled }
}

@MainActor package final class MacOSWindow: NSObject, PlatformWindow, NSWindowDelegate {
	var nativeWindow: NSWindow!
	var view: ContentView!
	var closed = false
	var applyingConfiguration = false
	var isSurface = false
	var surfaceOpaque = true
	var modalDepth = 0
	var draggingWindow = false
	var resizeEdges: Int32 = 0
	var resizeOriginal = CGRect.zero
	var resizeStart = CGPoint.zero
	var dragTimer: Timer?
	var observations: [NSKeyValueObservation] = []
	var tabObservations: [NSKeyValueObservation] = []
	var notificationObservers: [NSObjectProtocol] = []
	var observedTabGroup: NSWindowTabGroup?
	var toolbarDelegate: ToolbarDelegate?
	var accessories: [String: NSTitlebarAccessoryViewController] = [:]
	var fullscreenOperation: CheckedContinuation<Void, any Error>?
	var operations: [UInt64: CheckedContinuation<Int32, any Error>] = [:]
	var operationSerial: UInt64 = 0
	var fullscreenTransition = STNWindowState.FullscreenTransition.idle
	var semanticNodes: [STNSemanticID: NativeAccessibilityElement] = [:]
	var semanticOrder: [STNSemanticID] = []
	var semanticRevision: UInt64 = 0
	var pendingText: [UInt64: NativeTextSnapshot] = [:]
	var backing: CGContext?
	var backingScale: Double = 1
	var rasterCanvas = RasterCanvas()
	package var onEvent: ((PlatformEvent) -> Void)?
	package var onDraw: (() -> Void)?
	package var onState: ((STNWindowState) -> Void)?
	package var onPointer: ((Int, STNPoint, Bool, Int, Int) -> Int32)?
	package var shouldClose: (() -> Bool)?
	package var onIdle: (() -> Void)?
	package var onCommand: ((UInt64) -> Void)?
	package var onText: ((Int32, String, NSRange?, NSRange, UInt64, UInt64) -> Void)?
	package var onSymbolVisibility: ((Bool) -> Void)?
	package var onFrame: ((Double, Double) -> Void)?
	package var options: STNWindowOptions
	package var state = STNWindowState()
	package var currentDark = false
	package var graphics: MetalRenderer!
	private var semantics: MacOSAccessibility!

	package var renderer: any Renderer { graphics }

	package var accessibility: any AccessibilityBridge { semantics }

	package var supportsChrome: Bool { !closed && !isSurface && nativeWindow.styleMask.contains(.titled) }

	package var isBusy: Bool {
		!closed
			&& (nativeWindow.inLiveResize || draggingWindow || fullscreenTransition != .idle
				|| nativeWindow.attachedSheet != nil || nativeWindow.styleMask.contains(.fullScreen))
	}

	package init(title: String, size: STNSize, options: STNWindowOptions = .init(), parent: MacOSWindow? = nil) throws {
		try options.validate()
		guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else {
			throw STNWindowError.invalidConfiguration("Initial content size must be finite and positive")
		}

		self.options = options
		super.init()
		NativeApplication.initialize()
		isSurface = parent != nil
		view = ContentView(frame: CGRect(x: 0, y: 0, width: size.width, height: size.height))
		view.host = self
		if let parent {
			nativeWindow = parent.nativeWindow
			surfaceOpaque = false
		} else {
			var style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable]
			switch options.creation.role {
			case .utility: style.insert(.utilityWindow)
			case .hud: style.insert(.hudWindow)
			case .nonactivatingPanel: style.insert(.nonactivatingPanel)
			default: break
			}

			if options.creation.role == .window {
				let window = HostWindow(contentRect: view.frame, styleMask: style, backing: .buffered, defer: false)
				window.host = self
				nativeWindow = window
			} else {
				let window = HostPanel(contentRect: view.frame, styleMask: style, backing: .buffered, defer: false)
				window.host = self
				nativeWindow = window
			}

			nativeWindow.isReleasedWhenClosed = false
			nativeWindow.title = title
			nativeWindow.delegate = self
			nativeWindow.contentView = view
			nativeWindow.acceptsMouseMovedEvents = true
			nativeWindow.center()
		}

		do {
			graphics = try MetalRenderer(window: self)
			semantics = MacOSAccessibility(window: self)
			if parent == nil {
				try apply(options)
				place(options.creation)
				startObserving()
			}

			observeSymbolVisibility()
			publishState()
		} catch {
			close()
			throw error
		}
	}

	package var symbolIsVisible: Bool {
		!closed && nativeWindow.isVisible && !nativeWindow.isMiniaturized && view.window != nil
			&& !view.isHiddenOrHasHiddenAncestor && NSApp?.isHidden != true
	}

	package func publishSymbolVisibility() {
		onSymbolVisibility?(symbolIsVisible)
	}

	private func observeSymbolVisibility() {
		// Notifications trigger a check of explicit visibility only; occlusion is not hiding.
		for name in [
			NSWindow.didChangeOcclusionStateNotification, NSWindow.didMiniaturizeNotification,
			NSWindow.didDeminiaturizeNotification,
			NSWindow.willCloseNotification,
		] {
			let closing = name == NSWindow.willCloseNotification
			notificationObservers.append(
				NotificationCenter.default.addObserver(forName: name, object: nativeWindow, queue: .main) {
					[weak self] _ in
					MainActor.assumeIsolated {
						guard let self else {
							return
						}

						if closing {
							self.onSymbolVisibility?(false)
						} else {
							self.publishSymbolVisibility()
						}
					}
				}
			)
		}

		for name in [NSApplication.didHideNotification, NSApplication.didUnhideNotification] {
			notificationObservers.append(
				NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
					MainActor.assumeIsolated {
						self?.publishSymbolVisibility()
						self?.graphics?.visibilityChanged()
					}
				}
			)
		}
	}

	package func show() {
		try? perform(options.creation.activatesOnOpen ? .show : .showInactive)
		view.viewDidChangeEffectiveAppearance()
		graphics.requestFrame()
	}

	package func setAnimationDemand(_ active: Bool) {
		graphics.setAnimationDemand(active)
	}

	package func requestRedraw() {
		if graphics.detached {
			view.needsDisplay = true
		} else {
			graphics.requestFrame()
		}
	}

	package func setTitle(_ title: String) {
		guard !closed else {
			return
		}

		nativeWindow.title = title
		if options.systemIntegration.minimizedTitle == nil {
			nativeWindow.miniwindowTitle = title
		}
	}

	package func close() {
		guard !closed else {
			return
		}

		closed = true
		graphics?.detach()
		semantics?.detach()
		dragTimer?.invalidate()
		dragTimer = nil
		observations.removeAll()
		tabObservations.removeAll()
		for observer in notificationObservers {
			NotificationCenter.default.removeObserver(observer)
			DistributedNotificationCenter.default().removeObserver(observer)
			NSWorkspace.shared.notificationCenter.removeObserver(observer)
		}

		notificationObservers.removeAll()
		cancelPendingOperations()
		onEvent = nil
		onDraw = nil
		onText = nil
		onSymbolVisibility?(false)
		onSymbolVisibility = nil
		onState = nil
		onPointer = nil
		shouldClose = nil
		onIdle = nil
		onCommand = nil
		view?.inputContext?.deactivate()
		view?.invalidateTextServices()
		view?.host = nil
		if isSurface {
			view?.removeFromSuperview()
		} else if let nativeWindow {
			if let parent = nativeWindow.sheetParent {
				parent.endSheet(nativeWindow, returnCode: .stop)
			}

			for sheet in nativeWindow.sheets {
				nativeWindow.endSheet(sheet, returnCode: .stop)
			}

			nativeWindow.toolbar = nil
			toolbarDelegate = nil
			if nativeWindow.styleMask.contains(.titled) {
				while !nativeWindow.titlebarAccessoryViewControllers.isEmpty {
					nativeWindow.removeTitlebarAccessoryViewController(
						at: nativeWindow.titlebarAccessoryViewControllers.count - 1
					)
				}
			}

			nativeWindow.delegate = nil
			nativeWindow.close()
		}

		semanticNodes.removeAll()
		pendingText.removeAll()
		state.isOpen = false
		state.isVisible = false
		state.isKey = false
		state.isMain = false
	}

	func emit(_ event: PlatformEvent) {
		guard !closed else {
			return
		}

		onEvent?(event)
	}

	func modal(_ entering: Bool) {
		modalDepth = entering ? modalDepth + 1 : max(0, modalDepth - 1)
		emit(.modalState(modalDepth > 0))
	}

	func resized() {
		guard !closed, !applyingConfiguration else {
			return
		}

		graphics?.geometryChanged(size: view.bounds.size.stana, scale: nativeWindow.backingScaleFactor)
		emit(.resize(view.bounds.size.stana, nativeWindow.backingScaleFactor))
		view.needsDisplay = true
		publishState()
	}

	package func windowDidResize(_ notification: Notification) {
		resized()
	}

	package func windowDidMove(_ notification: Notification) {
		resized()
	}

	package func windowDidChangeScreen(_ notification: Notification) {
		resized()
	}

	package func windowDidChangeBackingProperties(_ notification: Notification) {
		resized()
	}

	package func windowShouldClose(_ sender: NSWindow) -> Bool {
		shouldClose?() ?? true
	}

	package func windowWillClose(_ notification: Notification) {
		emit(.close)
	}

	package func windowDidBecomeKey(_ notification: Notification) {
		emit(.surfaceFocus(true))
		publishState()
	}

	package func windowDidBecomeMain(_ notification: Notification) {
		publishState()
	}

	package func windowDidResignMain(_ notification: Notification) {
		publishState()
	}

	package func windowDidMiniaturize(_ notification: Notification) {
		publishState()
	}

	package func windowDidDeminiaturize(_ notification: Notification) {
		publishState()
		graphics.visibilityChanged()
	}

	package func windowDidChangeOcclusionState(_ notification: Notification) {
		publishState()
		graphics.visibilityChanged()
	}

	package func windowWillStartLiveResize(_ notification: Notification) {
		publishState()
	}

	package func windowDidEndLiveResize(_ notification: Notification) {
		publishState()
		onIdle?()
	}

	package func windowWillEnterFullScreen(_ notification: Notification) {
		fullscreenTransition = .entering
		publishState()
	}

	package func windowWillExitFullScreen(_ notification: Notification) {
		fullscreenTransition = .exiting
		publishState()
	}

	package func windowDidEnterFullScreen(_ notification: Notification) {
		finishFullscreen(nil)
	}

	package func windowDidExitFullScreen(_ notification: Notification) {
		finishFullscreen(nil)
	}

	package func windowDidFailToEnterFullScreen(_ window: NSWindow) {
		finishFullscreen(STNWindowError.nativeFailure("Fullscreen entry failed"))
	}

	package func windowDidFailToExitFullScreen(_ window: NSWindow) {
		finishFullscreen(STNWindowError.nativeFailure("Fullscreen exit failed"))
	}

	package func windowDidResignKey(_ notification: Notification) {
		view.inputContext?.discardMarkedText()
		emit(.deactivated)
		publishState()
	}

	func finishFullscreen(_ error: (any Error)?) {
		let continuation = fullscreenOperation
		fullscreenOperation = nil
		fullscreenTransition = .idle
		publishState()
		if let error {
			continuation?.resume(throwing: error)
		} else {
			continuation?.resume()
		}

		onIdle?()
	}
}

extension CGSize {
	var stana: STNSize { .init(width: width, height: height) }
}

extension STNSize {
	var cgSize: CGSize { CGSize(width: width, height: height) }
}
