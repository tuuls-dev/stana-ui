import CStanaMacOS
import Foundation
import StanaPlatform
import StanaPrimitives

extension MacOSHost {
	package func resolve(_ desired: STNWindowOptions, initial: STNWindowOptions?) throws -> ResolvedWindowOptions {
		try desired.validate()
		var options = desired
		var ignored: [STNWindowResolution.Ignored] = []
		if let initial, options.creation != initial.creation {
			ignored.append(.init("creation", reason: .requiresReopen))
			options.creation = initial.creation
		}

		if options.appearance.frame == .frameless, options.titleBar != .init() {
			ignored.append(.init("titleBar", reason: .inapplicable))
			options.titleBar = .init()
		}

		if !options.behavior.canClose, options.titleBar.closeButton != .init() {
			ignored.append(.init("titleBar.closeButton", reason: .inapplicable))
			options.titleBar.closeButton = .init()
		}

		if !options.behavior.canMinimize, options.titleBar.minimizeButton != .init() {
			ignored.append(.init("titleBar.minimizeButton", reason: .inapplicable))
			options.titleBar.minimizeButton = .init()
		}

		if !options.resizing.isResizable, options.titleBar.zoomButton.enabled == .enabled {
			ignored.append(.init("titleBar.zoomButton.enabled", reason: .inapplicable))
			options.titleBar.zoomButton.enabled = .automatic
		}

		if options.titleBar.transparent == .enabled, options.titleBar.fullSizeContent != .enabled {
			ignored.append(.init("titleBar.transparent", reason: .inapplicable))
			options.titleBar.transparent = .automatic
		}

		if options.creation.role == .window {
			if options.interaction.becomesKeyOnlyIfNeeded != .automatic {
				ignored.append(.init("interaction.becomesKeyOnlyIfNeeded", reason: .inapplicable))
				options.interaction.becomesKeyOnlyIfNeeded = .automatic
			}

			if options.behavior.floatingPanel != .automatic {
				ignored.append(.init("behavior.floatingPanel", reason: .inapplicable))
				options.behavior.floatingPanel = .automatic
			}

			if options.behavior.worksWhenModal != .automatic {
				ignored.append(.init("behavior.worksWhenModal", reason: .inapplicable))
				options.behavior.worksWhenModal = .automatic
			}
		}

		return .init(options: options, resolution: .init(ignored: ignored))
	}
}

extension MacOSWindow {
	package var isBusy: Bool {
		handle.map { stn_window_busy($0) } ?? false
	}

	package func installWindowCallbacks() {
		var callbacks = stn_window_callbacks()
		callbacks.state = { context, value in
			guard let context, let value else {
				return
			}

			MainActor.assumeIsolated {
				let window = Unmanaged<MacOSWindow>.fromOpaque(context).takeUnretainedValue()
				window.receiveState(value.pointee)
			}
		}
		callbacks.pointer = { context, phase, x, y in
			guard let context else {
				return 0
			}

			return MainActor.assumeIsolated {
				let window = Unmanaged<MacOSWindow>.fromOpaque(context).takeUnretainedValue()
				if let handler = window.onPointer {
					return handler(Int(phase), .init(x: x, y: y))
				}

				window.onEvent?(.pointer(Int(phase), .init(x: x, y: y)))
				return 0
			}
		}
		callbacks.should_close = { context in
			guard let context else {
				return true
			}

			return MainActor.assumeIsolated {
				Unmanaged<MacOSWindow>.fromOpaque(context).takeUnretainedValue().shouldClose?() ?? true
			}
		}
		callbacks.idle = { context in
			guard let context else {
				return
			}

			MainActor.assumeIsolated { Unmanaged<MacOSWindow>.fromOpaque(context).takeUnretainedValue().onIdle?() }
		}
		callbacks.command = { context, id in
			guard let context else {
				return
			}

			MainActor.assumeIsolated { Unmanaged<MacOSWindow>.fromOpaque(context).takeUnretainedValue().onCommand?(id) }
		}
		callbacks.operation = { context, id, status, result in
			guard let context else {
				return
			}

			MainActor.assumeIsolated {
				let window = Unmanaged<MacOSWindow>.fromOpaque(context).takeUnretainedValue()
				guard let continuation = window.operations.removeValue(forKey: id) else {
					return
				}

				do {
					try checkWindowStatus(status)
					continuation.resume(returning: result)
				} catch {
					continuation.resume(throwing: error)
				}
			}
		}
		if let handle {
			stn_window_set_callbacks(handle, callbacks)
			stn_window_publish_state(handle)
		}
	}

	package func receiveState(_ native: stn_window_state) {
		var value = STNWindowState()
		value.isOpen = true
		value.isVisible = native.visible
		value.isKey = native.key
		value.isMain = native.main
		value.isMinimized = native.minimized
		value.isZoomed = native.zoomed
		value.isFullscreen = native.fullscreen
		value.fullscreenTransition = .init(rawValue: native.fullscreen_transition) ?? .idle
		value.isInLiveResize = native.live_resize
		value.isOnActiveSpace = native.active_space
		value.isOccluded = native.occluded
		value.hasSheet = native.has_sheet
		value.isSheet = native.is_sheet
		value.hasActiveSharingSession = native.has_sharing
		value.selectedTabID = native.selected_tab == 0 ? nil : native.selected_tab
		value.isTabBarVisible = native.tab_bar_visible
		value.isTabOverviewVisible = native.tab_overview_visible
		value.frame = native.frame.portable
		value.contentSize = native.content.portable.size
		value.safeContentBounds = native.safe_content.portable
		value.scale = native.scale
		value.screenID = native.screen_id.string
		value.nativeID = native.identity
		value.parentID = native.parent == 0 ? nil : native.parent
		if let children = native.children {
			value.childIDs = Array(UnsafeBufferPointer(start: children, count: native.child_count))
		}

		if let tabs = native.tabs {
			value.tabIDs = Array(UnsafeBufferPointer(start: tabs, count: native.tab_count))
		}

		state = value
		onState?(value)
	}

	package func apply(_ options: STNWindowOptions) throws {
		try options.validate()
		guard let handle else {
			throw STNWindowError.closed
		}

		var c = stn_window_config()
		c.frame = options.appearance.frame.rawValue
		c.role = options.creation.role.rawValue
		c.appearance = options.appearance.preference.rawValue
		c.shadow = options.appearance.shadow.rawValue
		c.opacity = options.appearance.opacity
		let dark =
			options.appearance.preference == .dark
			|| (options.appearance.preference == .automatic && state.isOpen && currentDark)
		c.background = options.appearance.background.resolved(dark: dark).native
		let title = options.titleBar
		c.title_visibility = title.titleVisibility.rawValue
		c.title_transparent = title.transparent.rawValue
		c.full_size_content = title.fullSizeContent.rawValue
		c.separator = title.separator.rawValue
		c.close_visibility = title.closeButton.visibility.rawValue
		c.close_enabled = title.closeButton.enabled.rawValue
		c.minimize_visibility = title.minimizeButton.visibility.rawValue
		c.minimize_enabled = title.minimizeButton.enabled.rawValue
		c.zoom_visibility = title.zoomButton.visibility.rawValue
		c.zoom_enabled = title.zoomButton.enabled.rawValue
		c.resizable = options.resizing.isResizable
		c.can_close = options.behavior.canClose
		c.can_minimize = options.behavior.canMinimize
		let input = options.interaction
		c.movable = input.isMovable
		c.background_dragging = input.backgroundDragging
		c.ignores_mouse = input.ignoresMouseEvents
		c.mouse_moved = input.acceptsMouseMovedEvents
		c.can_key = input.canBecomeKey.rawValue
		c.can_main = input.canBecomeMain.rawValue
		c.key_only_if_needed = input.becomesKeyOnlyIfNeeded.rawValue
		c.inactive_tooltips = input.allowsInactiveTooltips.rawValue
		let behavior = options.behavior
		c.hides_on_deactivate = behavior.hidesOnDeactivate.rawValue
		c.can_hide = behavior.canHide.rawValue
		c.floating_panel = behavior.floatingPanel.rawValue
		c.works_when_modal = behavior.worksWhenModal.rawValue
		c.prevents_termination = behavior.preventsTerminationWhenModal.rawValue
		c.excluded_from_menu = behavior.excludedFromWindowsMenu
		c.visible_without_login = behavior.canBecomeVisibleWithoutLogin
		c.automatic_level = behavior.level == .automatic
		c.level = behavior.level.nativeValue
		c.animation = behavior.animation.rawValue
		let spaces = options.workspaces
		c.spaces = spaces.spaces.rawValue
		c.management = spaces.management.rawValue
		c.application_membership = spaces.applicationMembership.rawValue
		c.cycle = spaces.participatesInCycle.rawValue
		c.fullscreen = spaces.fullscreen.rawValue
		c.tiling = spaces.allowsTiling.rawValue
		c.tabbing = spaces.tabbing.rawValue
		let resizing = options.resizing
		c.min_content = resizing.minimumContentSize.native
		c.max_content = resizing.maximumContentSize.native
		c.min_frame = resizing.minimumFrameSize.native
		c.max_frame = resizing.maximumFrameSize.native
		c.aspect = (resizing.contentAspectRatio ?? resizing.frameAspectRatio).native
		c.increments = (resizing.contentResizeIncrements ?? resizing.frameResizeIncrements).native
		c.frame_aspect = resizing.frameAspectRatio != nil
		c.frame_increments = resizing.frameResizeIncrements != nil
		c.min_fullscreen = resizing.minimumFullscreenContentSize.native
		c.max_fullscreen = resizing.maximumFullscreenContentSize.native
		c.preserves_content = resizing.preservesContentDuringLiveResize.rawValue
		if let border = title.contentBorder {
			c.has_content_border = true
			c.content_border = .init(x: border.leading, y: border.top, width: border.trailing, height: border.bottom)
		}

		// Every pointer is borrowed only through stn_window_apply. The adapter
		// copies strings/images into native properties before this scope ends.
		let strings = NativeWindowStrings([
			title.subtitle, options.systemIntegration.representedURL?.absoluteString ?? "",
			options.systemIntegration.minimizedTitle ?? "", options.systemIntegration.dockBadge ?? "",
			spaces.tabbingIdentifier, options.systemIntegration.tabTitle ?? "",
			options.systemIntegration.tabTooltip ?? "",
		])
		defer {
			withExtendedLifetime(strings) {}
		}

		c.subtitle = strings[0]
		c.represented_url = strings[1]
		c.minimized_title = strings[2]
		c.has_minimized_title = options.systemIntegration.minimizedTitle != nil
		c.dock_badge = strings[3]
		c.tabbing_identifier = strings[4]
		c.document_edited = options.systemIntegration.isDocumentEdited
		c.tab_title = strings[5]
		c.tab_tooltip = strings[6]
		c.has_tab_title = options.systemIntegration.tabTitle != nil
		c.has_tab_tooltip = options.systemIntegration.tabTooltip != nil
		let image = options.systemIntegration.minimizedImage ?? Data()
		try image.withUnsafeBytes { bytes in
			c.minimized_image = bytes.bindMemory(to: UInt8.self).baseAddress
			c.minimized_image_length = bytes.count
			if stn_window_validate_config(handle, &c) != 0 {
				throw STNWindowError.invalidConfiguration("Content and frame constraints have no feasible size")
			}

			stn_window_apply(handle, &c)
		}
		self.options = options
	}

	package func place(_ creation: STNWindowOptions.Creation) {
		guard let handle else {
			return
		}

		let strings = NativeWindowStrings([
			creation.identifier ?? "", creation.screenID ?? "", creation.frameAutosaveName ?? "",
		])
		defer {
			withExtendedLifetime(strings) {}
		}

		stn_window_place(
			handle,
			strings[0],
			strings[1],
			strings[2],
			creation.initialOrigin != nil,
			creation.initialOrigin?.x ?? 0,
			creation.initialOrigin?.y ?? 0
		)
	}

	package func perform(_ action: WindowAction) throws {
		guard let handle else {
			throw STNWindowError.closed
		}

		try checkWindowStatus(stn_window_action(handle, action.rawValue))
	}

	package func setFrame(_ frame: STNRect, animate: Bool) throws {
		guard let handle else {
			throw STNWindowError.closed
		}

		guard frame.origin.x.isFinite, frame.origin.y.isFinite, frame.size.width.isFinite, frame.size.height.isFinite,
			frame.size.width > 0, frame.size.height > 0
		else {
			throw STNWindowError.invalidConfiguration("Invalid frame")
		}

		try checkWindowStatus(stn_window_set_frame(handle, frame.native, animate))
	}

	package func saveFrame(_ name: String) throws {
		guard let handle else {
			throw STNWindowError.closed
		}

		guard !name.isEmpty else {
			throw STNWindowError.invalidConfiguration("Empty saved-frame name")
		}

		var result = false
		try name.withNativeUTF8 { try checkWindowStatus(stn_window_manage_frame(handle, $0, false, &result)) }
	}

	package func restoreFrame(_ name: String) throws -> Bool {
		guard let handle else {
			throw STNWindowError.closed
		}

		guard !name.isEmpty else {
			throw STNWindowError.invalidConfiguration("Empty saved-frame name")
		}

		var result = false
		try name.withNativeUTF8 { try checkWindowStatus(stn_window_manage_frame(handle, $0, true, &result)) }
		return result
	}

	package func setContentSize(_ size: STNSize) throws {
		guard let handle else {
			throw STNWindowError.closed
		}

		guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else {
			throw STNWindowError.invalidConfiguration("Invalid content size")
		}

		try checkWindowStatus(stn_window_set_content_size(handle, size.width, size.height))
	}

	package func relate(_ other: any PlatformWindow, _ relationship: WindowRelationship) throws {
		guard let handle, let other = other as? MacOSWindow, let target = other.handle else {
			throw STNWindowError.invalidRelationship
		}

		try checkWindowStatus(stn_window_relate(handle, target, relationship.rawValue))
	}

	package func cancelPendingOperations() {
		let pending = operations
		operations.removeAll()
		for continuation in pending.values {
			continuation.resume(throwing: STNWindowError.cancelled)
		}
	}

	package func setFullscreen(_ value: Bool) async throws {
		_ = try await operation { stn_window_fullscreen($0, value, $1) }
	}

	package func presentSheet(_ sheet: any PlatformWindow, critical: Bool) async throws -> Int32 {
		guard let sheet = sheet as? MacOSWindow, let target = sheet.handle else {
			throw STNWindowError.invalidRelationship
		}

		return try await operation { stn_window_begin_sheet($0, target, critical, $1) }
	}

	package func endSheet(_ result: Int32) throws {
		guard let handle else {
			throw STNWindowError.closed
		}

		try checkWindowStatus(stn_window_end_sheet(handle, result))
	}

	package func requestSharing(of other: (any PlatformWindow)?) async throws {
		let target: UnsafeMutableRawPointer?
		if let other {
			guard let other = other as? MacOSWindow, let handle = other.handle else {
				throw STNWindowError.invalidRelationship
			}

			target = handle
		} else {
			target = nil
		}

		_ = try await operation { stn_window_share($0, target, $1) }
	}

	package func operation(_ start: (UnsafeMutableRawPointer, UInt64) -> Int32) async throws -> Int32 {
		try Task.checkCancellation()
		guard let handle else {
			throw STNWindowError.closed
		}

		precondition(operationSerial < .max)
		operationSerial += 1
		let id = operationSerial
		return try await withTaskCancellationHandler {
			try await withCheckedThrowingContinuation { continuation in
				operations[id] = continuation
				let status = start(handle, id)
				if status != 0, let pending = operations.removeValue(forKey: id) {
					do {
						try checkWindowStatus(status)
					} catch {
						pending.resume(throwing: error)
					}
				}
			}
		} onCancel: {
			Task { @MainActor [weak self] in
				self?.operations.removeValue(forKey: id)?.resume(throwing: STNWindowError.cancelled)
			}
		}
	}
}

@MainActor package func checkWindowStatus(_ status: Int32) throws {
	switch status {
	case 0: return
	case 1: throw STNWindowError.unsupportedAction("The native window does not support this action")
	case 2: throw STNWindowError.invalidState("The action is not valid in the current window state")
	case 4: throw STNWindowError.cancelled
	default: throw STNWindowError.nativeFailure("Native window operation failed")
	}
}

extension stn_rect {
	var portable: STNRect {
		.init(x: x, y: y, width: max(0, width), height: max(0, height))
	}
}

extension Optional where Wrapped == STNSize {
	fileprivate var native: stn_rect {
		.init(x: 0, y: 0, width: self?.width ?? 0, height: self?.height ?? 0)
	}
}

extension STNWindowOptions.Level {
	fileprivate var nativeValue: Int32 {
		switch self {
		case .automatic, .normal: return 0
		case .floating: return 3
		case .modalPanel: return 8
		case .mainMenu: return 24
		case .status: return 25
		case .popUpMenu: return 101
		case .screenSaver: return 1000
		case .custom(let level): return level
		}
	}
}

// Owns UTF-8 buffers across synchronous C calls; embedded NUL is not truncated.
final class NativeWindowStrings {
	private var buffers: [(UnsafeMutablePointer<CChar>, Int)] = []

	init(_ values: [String]) {
		for value in values {
			let bytes = Array(value.utf8)
			let pointer = UnsafeMutablePointer<CChar>.allocate(capacity: max(1, bytes.count))
			for (index, byte) in bytes.enumerated() {
				pointer[index] = CChar(bitPattern: byte)
			}

			buffers.append((pointer, bytes.count))
		}
	}

	subscript(_ index: Int) -> stn_utf8 {
		.init(bytes: UnsafePointer(buffers[index].0), length: buffers[index].1)
	}

	deinit {
		for (pointer, _) in buffers {
			pointer.deallocate()
		}
	}
}

@MainActor private final class ScreenCollector {
	var values: [STNScreen] = []
}

extension MacOSHost {
	package static var screens: [STNScreen] {
		let collector = ScreenCollector()
		stn_screens(Unmanaged.passUnretained(collector).toOpaque()) { context, value in
			guard let context, let value else {
				return
			}

			MainActor.assumeIsolated {
				let collector = Unmanaged<ScreenCollector>.fromOpaque(context).takeUnretainedValue()
				let s = value.pointee
				collector.values.append(
					.init(
						id: s.identifier.string,
						name: s.name.string,
						frame: s.frame.portable,
						visibleFrame: s.visible_frame.portable,
						scale: s.scale
					)
				)
			}
		}
		return collector.values
	}

	package static func removeSavedFrame(_ name: String) {
		name.withNativeUTF8 { stn_window_erase_saved_frame($0) }
	}
}
