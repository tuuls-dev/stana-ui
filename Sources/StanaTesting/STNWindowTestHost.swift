import Foundation
import Stana
import StanaAccessibility
import StanaCore
import StanaGraphics
import StanaPlatform
import StanaPrimitives
import StanaScene
import StanaText

/// Exercises the production window controller without NSApplication or a window
/// server. Availability can be varied independently of the machine running tests.
@MainActor public final class STNWindowTestHost {
	public enum Feature: Sendable, Hashable {
		case frame, panel, titleBar, workspaces, chrome
	}

	public let window: STNWindow
	private let host: RecordingWindowHost
	private let recorded: RecordingWindow

	public init(window: STNWindow, unsupportedFeatures: Set<Feature> = []) throws {
		self.window = window
		host = RecordingWindowHost(unsupported: unsupportedFeatures)
		try window.open(using: host)
		recorded = host.windows[0]
	}

	public var applicationCount: Int {
		recorded.applicationCount
	}

	public var title: String {
		recorded.title
	}

	public var nodes: [STNNodeSnapshot] {
		window.session?.nodeSnapshots ?? []
	}

	public var metrics: STNMetrics? {
		window.session?.document.metrics
	}

	public var toolbarTitles: [String] {
		recorded.toolbarTitles
	}

	public var chromeSurfaceCount: Int {
		max(0, host.windows.count - 1)
	}

	public func setBusy(_ value: Bool) {
		recorded.isBusy = value
		if !value {
			recorded.onIdle?()
		}
	}

	public func setSafeContentBounds(_ bounds: STNRect) {
		recorded.state.safeContentBounds = bounds
		recorded.publish()
	}

	public func resize(to size: STNSize) {
		try? recorded.setContentSize(size)
	}

	@discardableResult public func pointerDown(at point: STNPoint) -> Int32 {
		recorded.onPointer?(0, point) ?? 0
	}

	public func pointerUp(at point: STNPoint) {
		_ = recorded.onPointer?(2, point)
	}

	public func focus(_ id: STNNodeID) throws {
		guard let session = window.session, session.document.isEligible(id) else {
			throw STNError.notFocusable
		}

		session.document.setFocus(id)
	}

	public func setMarkedText(_ text: String, selectedRange: NSRange) {
		window.session?.edit(2, text: text, range: nil, selected: selectedRange)
	}

	public func commitMarkedText() {
		window.session?.edit(3, text: "", range: nil, selected: .init(location: 0, length: 0))
	}

	public func performToolbarCommand(at index: Int) {
		let ids = recorded.toolbarCommandIDs
		if ids.indices.contains(index) {
			recorded.onCommand?(ids[index])
		}
	}

	public func renderedFillColors() -> [STNColor] {
		window.session?.draw()
		return recorded.graphics.commands.compactMap {
			if case .fill(_, let color, _) = ($0) {
				return color
			}

			return nil
		}
	}

	public func close() {
		window.close()
	}
}

@MainActor private final class RecordingWindowHost: PlatformHost {
	let textService: any TextService = TestTextService()
	let unsupported: Set<STNWindowTestHost.Feature>
	var windows: [RecordingWindow] = []

	init(unsupported: Set<STNWindowTestHost.Feature>) {
		self.unsupported = unsupported
	}

	func resolve(_ desired: STNWindowOptions, initial: STNWindowOptions?) throws -> ResolvedWindowOptions {
		try desired.validate()
		var value = desired
		var ignored: [STNWindowResolution.Ignored] = []
		if let initial, value.creation != initial.creation {
			ignored.append(.init("creation", reason: .requiresReopen))
			value.creation = initial.creation
		}

		if unsupported.contains(.frame), value.appearance.frame != .automatic {
			value.appearance.frame = .automatic
			ignored.append(.init("appearance.frame", reason: .unsupported))
		}

		if unsupported.contains(.panel), value.creation.role != .window {
			value.creation.role = .window
			ignored.append(.init("creation.role", reason: .unsupported))
		}

		if unsupported.contains(.titleBar), value.titleBar != .init() {
			value.titleBar = .init()
			ignored.append(.init("titleBar", reason: .unsupported))
		}

		if unsupported.contains(.workspaces), value.workspaces != .init() {
			value.workspaces = .init()
			ignored.append(.init("workspaces", reason: .unsupported))
		}

		return .init(options: value, resolution: .init(ignored: ignored))
	}

	func createWindow(title: String, size: STNSize, options: STNWindowOptions) throws -> any PlatformWindow {
		let window = RecordingWindow(
			title: title,
			size: size,
			options: options,
			supportsChrome: !unsupported.contains(.chrome),
			id: UInt64(windows.count + 1)
		)
		windows.append(window)
		return window
	}

	func createSurface(in window: any PlatformWindow, size: STNSize) throws -> any PlatformWindow {
		try createWindow(title: "surface", size: size, options: .init())
	}

	func run() {}
}

@MainActor private final class RecordingWindow: PlatformWindow {
	let graphics = RecordingWindowRenderer()
	let accessibility: any AccessibilityBridge = RecordingWindowAccessibility()

	var renderer: any Renderer {
		graphics
	}

	var onEvent: ((PlatformEvent) -> Void)?
	var onDraw: (() -> Void)?
	var onState: ((STNWindowState) -> Void)?
	var onPointer: ((Int, STNPoint) -> Int32)?
	var shouldClose: (() -> Bool)?
	var onIdle: (() -> Void)?
	var onCommand: ((UInt64) -> Void)?
	var state = STNWindowState()
	var isBusy = false
	let supportsChrome: Bool
	var options: STNWindowOptions
	var title: String
	var savedFrames: [String: STNRect] = [:]
	var applicationCount = 0
	var toolbar: WindowToolbar?

	var toolbarCommandIDs: [UInt64] {
		flattened.compactMap { $0.command == 0 ? nil : $0.command }
	}

	var toolbarTitles: [String] {
		flattened.filter { $0.command != 0 }.map(\.title)
	}

	private var flattened: [WindowToolbarItem] {
		func flatten(_ items: [WindowToolbarItem]) -> [WindowToolbarItem] {
			items.flatMap { [$0] + flatten($0.children) }
		}

		return flatten(toolbar?.items ?? [])
	}

	init(title: String, size: STNSize, options: STNWindowOptions, supportsChrome: Bool, id: UInt64) {
		self.title = title
		self.options = options
		self.supportsChrome = supportsChrome
		state.isOpen = true
		state.contentSize = size
		state.frame = .init(width: size.width, height: size.height)
		state.safeContentBounds = state.frame
		state.nativeID = id
	}

	func publish() {
		onState?(state)
	}

	func apply(_ options: STNWindowOptions) throws {
		try options.validate()
		self.options = options
		applicationCount += 1
	}

	func show() {
		try? perform(.show)
	}

	func requestRedraw() {}

	func setTitle(_ title: String) {
		self.title = title
	}

	func close() {
		state.isOpen = false
		onEvent = nil
		onState = nil
		onDraw = nil
		onPointer = nil
		shouldClose = nil
		onIdle = nil
		onCommand = nil
	}

	func perform(_ action: WindowAction) throws {
		guard state.isOpen else {
			throw STNWindowError.closed
		}

		switch action {
		case .show:
			state.isVisible = true
			state.isKey = true
		case .showInactive, .orderFront: state.isVisible = true
		case .hide: state.isVisible = false
		case .focus: state.isKey = true
		case .minimize:
			guard options.behavior.canMinimize else {
				throw STNWindowError.unsupportedAction("minimize")
			}

			state.isMinimized = true
		case .restore: state.isMinimized = false
		case .zoom: state.isZoomed.toggle()
		case .requestClose:
			guard options.behavior.canClose else {
				throw STNWindowError.unsupportedAction("close")
			}

			if shouldClose?() ?? true {
				onEvent?(.close)
			}
		case .center, .orderBack: break
		default: throw STNWindowError.unsupportedAction("Recording host does not simulate this action")
		}

		publish()
	}

	func cancelPendingOperations() {}

	func setFullscreen(_ value: Bool) async throws {
		guard options.workspaces.fullscreen != .none else {
			throw STNWindowError.unsupportedAction("fullscreen")
		}

		state.isFullscreen = value
		publish()
	}

	func setFrame(_ frame: STNRect, animate: Bool) throws {
		state.frame = frame
		state.contentSize = frame.size
		publish()
	}

	func saveFrame(_ name: String) throws {
		savedFrames[name] = state.frame
	}

	func restoreFrame(_ name: String) throws -> Bool {
		guard let frame = savedFrames[name] else {
			return false
		}

		try setFrame(frame, animate: false)
		return true
	}

	func setContentSize(_ size: STNSize) throws {
		state.contentSize = size
		state.frame.size = size
		state.safeContentBounds = .init(width: size.width, height: size.height)
		onEvent?(.resize(size, 1))
		publish()
	}

	func relate(_ other: any PlatformWindow, _ relationship: WindowRelationship) throws {
		guard let other = other as? RecordingWindow else {
			throw STNWindowError.invalidRelationship
		}

		switch relationship {
		case .childAbove, .childBelow:
			state.childIDs.append(other.state.nativeID)
			other.state.parentID = state.nativeID
		case .detach:
			state.childIDs.removeAll { $0 == other.state.nativeID }
			other.state.parentID = nil
		case .tabBefore, .tabAfter:
			state.tabIDs = [state.nativeID, other.state.nativeID]
			other.state.tabIDs = state.tabIDs
		case .selectTab: state.selectedTabID = other.state.nativeID
		case .detachTab:
			state.tabIDs.removeAll { $0 == other.state.nativeID }
			other.state.tabIDs = []
		}

		publish()
		other.publish()
	}

	func presentSheet(_ sheet: any PlatformWindow, critical: Bool) async throws -> Int32 {
		throw STNWindowError.unsupportedAction("Recording host does not simulate sheet completion")
	}

	func endSheet(_ result: Int32) throws {
		throw STNWindowError.invalidState("Not a sheet")
	}

	func requestSharing(of other: (any PlatformWindow)?) async throws {
		throw STNWindowError.unsupportedAction("sharing")
	}

	func setToolbar(
		_ toolbar: WindowToolbar?,
		replacing: Bool,
		visible: Bool,
		style: STNWindowOptions.ToolbarStyle,
		display: STNWindowOptions.ToolbarDisplay
	) throws {
		if replacing {
			self.toolbar = toolbar
		}
	}

	func updateToolbarCommand(_ id: UInt64, title: String, enabled: Bool, checked: Bool) {
		func update(_ items: [WindowToolbarItem]) -> [WindowToolbarItem] {
			items.map { old in
				var item = old
				if item.command == id {
					item.title = title
					item.enabled = enabled
					item.checked = checked
				}

				item.children = update(item.children)
				return item
			}
		}

		if let items = toolbar?.items {
			toolbar?.items = update(items)
		}
	}

	func setTabAccessory(_ surface: (any PlatformWindow)?) throws {}

	func setAccessories(_ accessories: [WindowAccessory]) throws {}
}

@MainActor private final class RecordingWindowRenderer: Renderer {
	var backingRevision: UInt64 = 0
	var surfaceEpoch: UInt64 = 1
	var commands: [DrawCommand] = []

	func submit(_ scene: SceneSnapshot) throws -> FrameCompletion {
		commands = scene.commands
		backingRevision = scene.sceneRevision
		return .init(sceneRevision: scene.sceneRevision, surfaceEpoch: surfaceEpoch, presentationConfirmed: false)
	}

	func detach() {
		commands = []
	}
}

@MainActor private final class RecordingWindowAccessibility: AccessibilityBridge {
	func publish(_ snapshot: STNSemanticSnapshot) {}

	func detach() {}
}
