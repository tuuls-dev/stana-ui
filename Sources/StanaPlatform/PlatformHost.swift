import Foundation
import StanaAccessibility
import StanaGraphics
import StanaPrimitives
import StanaText

package enum PlatformEvent: Sendable {
	case resize(STNSize, Double)
	case pointer(Int, STNPoint)
	case scroll(STNPoint, Double, Double)
	case key(String, Bool, Bool)
	case close
	case activate(UInt64)
	case focus(UInt64)
	case appearance(Bool, Bool, Bool)
	case deactivated
	case surfaceFocus(Bool)
	case resourcesChanged(Bool)
	case modalState(Bool)
}

@MainActor package protocol PlatformWindow: AnyObject {
	var renderer: any Renderer {
		get
	}

	var accessibility: any AccessibilityBridge {
		get
	}

	var onEvent: ((PlatformEvent) -> Void)? {
		get set
	}

	var onDraw: (() -> Void)? {
		get set
	}

	var onState: ((STNWindowState) -> Void)? {
		get set
	}

	var onPointer: ((Int, STNPoint) -> Int32)? {
		get set
	}

	var shouldClose: (() -> Bool)? {
		get set
	}

	var onIdle: (() -> Void)? {
		get set
	}

	var state: STNWindowState {
		get
	}

	var isBusy: Bool {
		get
	}

	var supportsChrome: Bool {
		get
	}

	func setToolbar(
		_ toolbar: WindowToolbar?,
		replacing: Bool,
		visible: Bool,
		style: STNWindowOptions.ToolbarStyle,
		display: STNWindowOptions.ToolbarDisplay
	) throws

	func updateToolbarCommand(_ id: UInt64, title: String, enabled: Bool, checked: Bool)

	var onCommand: ((UInt64) -> Void)? {
		get set
	}

	func setTabAccessory(_ surface: (any PlatformWindow)?) throws

	func setAccessories(_ accessories: [WindowAccessory]) throws

	func apply(_ options: STNWindowOptions) throws

	func perform(_ action: WindowAction) throws

	func cancelPendingOperations()

	func setFullscreen(_ value: Bool) async throws

	func setFrame(_ frame: STNRect, animate: Bool) throws

	func saveFrame(_ name: String) throws

	func restoreFrame(_ name: String) throws -> Bool

	func setContentSize(_ size: STNSize) throws

	func relate(_ other: any PlatformWindow, _ relationship: WindowRelationship) throws

	func presentSheet(_ sheet: any PlatformWindow, critical: Bool) async throws -> Int32

	func endSheet(_ result: Int32) throws

	func requestSharing(of other: (any PlatformWindow)?) async throws

	func show()

	func requestRedraw()

	func setTitle(_ title: String)

	func close()
}

@MainActor package protocol PlatformHost {
	var textService: any TextService {
		get
	}

	func resolve(_ options: STNWindowOptions, initial: STNWindowOptions?) throws -> ResolvedWindowOptions

	func createWindow(title: String, size: STNSize, options: STNWindowOptions) throws -> any PlatformWindow

	func createSurface(in window: any PlatformWindow, size: STNSize) throws -> any PlatformWindow

	func run()
}

package struct ResolvedWindowOptions {
	package var options: STNWindowOptions
	package var resolution: STNWindowResolution

	package init(options: STNWindowOptions, resolution: STNWindowResolution = .init()) {
		self.options = options
		self.resolution = resolution
	}
}
