import AppKit
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

extension STNWindowOptions.Preference {
	func resolve(_ automatic: Bool) -> Bool {
		self == .automatic ? automatic : self == .enabled
	}
}

@MainActor extension NSScreen {
	var stanaID: String {
		(deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.stringValue ?? ""
	}

	static var top: Double { Double(screens.first?.frame.height ?? 0) }
}

@MainActor extension CGRect {
	var desktopPortable: STNRect {
		.init(x: minX, y: NSScreen.top - maxY, width: width, height: height)
	}
}

@MainActor extension STNRect {
	var desktopNative: CGRect {
		CGRect(x: minX, y: NSScreen.top - minY - size.height, width: size.width, height: size.height)
	}
}

extension MacOSHost {
	package static var screens: [STNScreen] {
		NativeApplication.initialize()
		return NSScreen.screens.map {
			.init(
				id: $0.stanaID,
				name: $0.localizedName,
				frame: $0.frame.desktopPortable,
				visibleFrame: $0.visibleFrame.desktopPortable,
				scale: $0.backingScaleFactor
			)
		}
	}

	package static func removeSavedFrame(_ name: String) {
		NSWindow.removeFrame(usingName: name)
	}
}

extension MacOSWindow {
	func startObserving() {
		observations = [
			nativeWindow.observe(\.contentLayoutRect) { [weak self] _, _ in MainActor.assumeIsolated { self?.resized() }
			},
			nativeWindow.observe(\.tabbedWindows) { [weak self] _, _ in
				MainActor.assumeIsolated { self?.publishState() }
			},
			nativeWindow.observe(\.tabGroup) { [weak self] _, _ in
				MainActor.assumeIsolated {
					self?.observeTabGroup()
					self?.publishState()
				}
			},
		]
		observeTabGroup()
		notificationObservers.append(
			DistributedNotificationCenter.default()
				.addObserver(
					forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
					object: nil,
					queue: .main
				) { [weak self] _ in MainActor.assumeIsolated { self?.view.viewDidChangeEffectiveAppearance() } }
		)
		notificationObservers.append(
			NSWorkspace.shared.notificationCenter.addObserver(
				forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
				object: nil,
				queue: .main
			) { [weak self] _ in MainActor.assumeIsolated { self?.view.viewDidChangeEffectiveAppearance() } }
		)
	}

	func observeTabGroup() {
		guard observedTabGroup !== nativeWindow.tabGroup else {
			return
		}

		tabObservations.removeAll()
		observedTabGroup = nativeWindow.tabGroup
		guard let group = observedTabGroup else {
			return
		}

		tabObservations = [
			group.observe(\.windows) { [weak self] _, _ in MainActor.assumeIsolated { self?.publishState() } },
			group.observe(\.selectedWindow) { [weak self] _, _ in MainActor.assumeIsolated { self?.publishState() } },
			group.observe(\.isOverviewVisible) { [weak self] _, _ in MainActor.assumeIsolated { self?.publishState() }
			},
			group.observe(\.isTabBarVisible) { [weak self] _, _ in MainActor.assumeIsolated { self?.publishState() } },
		]
	}

	func publishState() {
		guard !closed, !applyingConfiguration, let window = nativeWindow else {
			return
		}

		var state = STNWindowState()
		state.isOpen = true
		state.isVisible = window.isVisible
		state.isKey = window.isKeyWindow
		state.isMain = window.isMainWindow
		state.isMinimized = window.isMiniaturized
		state.isZoomed = window.isZoomed
		state.isFullscreen = window.styleMask.contains(.fullScreen)
		state.fullscreenTransition = fullscreenTransition
		state.isInLiveResize = window.inLiveResize
		state.isOnActiveSpace = window.isOnActiveSpace
		state.isOccluded = !window.occlusionState.contains(.visible)
		state.hasSheet = window.attachedSheet != nil
		state.isSheet = window.sheetParent != nil
		state.hasActiveSharingSession = window.hasActiveWindowSharingSession
		state.frame = window.frame.desktopPortable
		state.contentSize = view.bounds.size.stana
		state.safeContentBounds = (isSurface ? view.bounds : view.convert(window.contentLayoutRect, from: nil)).stana
		state.scale = window.backingScaleFactor
		state.screenID = window.screen?.stanaID
		state.nativeID = UInt64(window.windowNumber)
		state.parentID = window.parent.map { UInt64($0.windowNumber) }
		state.childIDs = (window.childWindows ?? []).map { UInt64($0.windowNumber) }
		state.tabIDs = (window.tabbedWindows ?? []).map { UInt64($0.windowNumber) }
		state.selectedTabID = window.tabGroup?.selectedWindow.map { UInt64($0.windowNumber) }
		state.isTabBarVisible = window.tabGroup?.isTabBarVisible ?? false
		state.isTabOverviewVisible = window.tabGroup?.isOverviewVisible ?? false
		self.state = state
		onState?(state)
	}

	package func apply(_ desired: STNWindowOptions) throws {
		try desired.validate()
		guard !closed else {
			throw STNWindowError.closed
		}

		let window = nativeWindow!
		var style: NSWindow.StyleMask = desired.appearance.frame == .frameless ? .borderless : .titled
		if desired.behavior.canClose {
			style.insert(.closable)
		}

		if desired.behavior.canMinimize {
			style.insert(.miniaturizable)
		}

		if desired.resizing.isResizable {
			style.insert(.resizable)
		}

		switch desired.creation.role {
		case .utility: style.insert(.utilityWindow)
		case .hud: style.insert(.hudWindow)
		case .nonactivatingPanel: style.insert(.nonactivatingPanel)
		default: break
		}

		if desired.titleBar.fullSizeContent == .enabled, desired.appearance.frame != .frameless {
			style.insert(.fullSizeContentView)
		}

		if window.styleMask.contains(.fullScreen) {
			style.insert(.fullScreen)
		}

		let resizing = desired.resizing
		let minimum =
			NSWindow.frameRect(
				forContentRect: CGRect(origin: .zero, size: resizing.minimumContentSize?.cgSize ?? .zero),
				styleMask: style
			)
			.size
		let maximum = resizing.maximumContentSize.map {
			NSWindow.frameRect(forContentRect: CGRect(origin: .zero, size: $0.cgSize), styleMask: style).size
		}
		let low = CGSize(
			width: max(minimum.width, resizing.minimumFrameSize?.width ?? 0),
			height: max(minimum.height, resizing.minimumFrameSize?.height ?? 0)
		)
		let high = CGSize(
			width: min(
				maximum?.width ?? .greatestFiniteMagnitude,
				resizing.maximumFrameSize?.width ?? .greatestFiniteMagnitude
			),
			height: min(
				maximum?.height ?? .greatestFiniteMagnitude,
				resizing.maximumFrameSize?.height ?? .greatestFiniteMagnitude
			)
		)
		guard low.width <= high.width, low.height <= high.height else {
			throw STNWindowError.invalidConfiguration("Conflicting content/frame limits")
		}

		if let aspect = resizing.contentAspectRatio ?? resizing.frameAspectRatio {
			let decoration =
				resizing.frameAspectRatio != nil
				? CGSize.zero : NSWindow.frameRect(forContentRect: .zero, styleMask: style).size
			let ratio = aspect.width / aspect.height
			guard
				max(low.width - decoration.width, (low.height - decoration.height) * ratio)
					<= min(high.width - decoration.width, (high.height - decoration.height) * ratio)
			else {
				throw STNWindowError.invalidConfiguration("Aspect ratio conflicts with size limits")
			}
		}

		applyingConfiguration = true
		defer {
			applyingConfiguration = false
			resized()
			view.viewDidChangeEffectiveAppearance()
		}

		options = desired
		let content = view.bounds.size
		let topLeft = CGPoint(x: window.frame.minX, y: window.frame.maxY)
		let responder = window.firstResponder as? ContentView
		if window.styleMask != style {
			if !style.contains(.titled), window.styleMask.contains(.titled) {
				while !window.titlebarAccessoryViewControllers.isEmpty {
					window.removeTitlebarAccessoryViewController(at: window.titlebarAccessoryViewControllers.count - 1)
				}

				window.toolbar = nil
				toolbarDelegate = nil
				accessories.removeAll()
			}

			window.styleMask = style
			window.contentView = view
			window.setContentSize(content)
			window.setFrameTopLeftPoint(topLeft)
			if let responder, responder.window === window {
				window.makeFirstResponder(responder)
			}
		}

		if desired.interaction.canBecomeKey == .disabled, window.isKeyWindow {
			window.resignKey()
		}

		if desired.interaction.canBecomeMain == .disabled, window.isMainWindow {
			window.resignMain()
		}

		let title = desired.titleBar
		window.subtitle = title.subtitle
		window.titleVisibility = title.titleVisibility == .disabled ? .hidden : .visible
		window.titlebarAppearsTransparent = title.transparent == .enabled
		window.titlebarSeparatorStyle = NSTitlebarSeparatorStyle(rawValue: Int(title.separator.rawValue)) ?? .automatic
		for (button, option, allowed) in [
			(NSWindow.ButtonType.closeButton, title.closeButton, desired.behavior.canClose),
			(.miniaturizeButton, title.minimizeButton, desired.behavior.canMinimize),
			(.zoomButton, title.zoomButton, resizing.isResizable),
		] {
			window.standardWindowButton(button)?.isHidden = option.visibility == .disabled
			window.standardWindowButton(button)?.isEnabled = option.enabled.resolve(allowed)
		}

		window.alphaValue = desired.appearance.opacity
		window.hasShadow = desired.appearance.shadow.resolve(true)
		let dark =
			desired.appearance.preference == .dark || (desired.appearance.preference == .automatic && currentDark)
		let color = desired.appearance.background.resolved(dark: dark)
		window.backgroundColor = NSColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
		surfaceOpaque = color.alpha >= 1
		window.isOpaque = surfaceOpaque
		window.appearance =
			desired.appearance.preference == .light
			? NSAppearance(named: .aqua) : desired.appearance.preference == .dark ? NSAppearance(named: .darkAqua) : nil
		let input = desired.interaction
		window.isMovable = input.isMovable
		window.isMovableByWindowBackground = false
		window.ignoresMouseEvents = input.ignoresMouseEvents
		window.acceptsMouseMovedEvents = input.acceptsMouseMovedEvents
		window.allowsToolTipsWhenApplicationIsInactive = input.allowsInactiveTooltips.resolve(false)
		let behavior = desired.behavior
		window.hidesOnDeactivate = behavior.hidesOnDeactivate.resolve(desired.creation.role != .window)
		window.canHide = behavior.canHide.resolve(true)
		window.preventsApplicationTerminationWhenModal = behavior.preventsTerminationWhenModal.resolve(true)
		window.isExcludedFromWindowsMenu = behavior.excludedFromWindowsMenu
		window.canBecomeVisibleWithoutLogin = behavior.canBecomeVisibleWithoutLogin
		if let panel = window as? NSPanel {
			panel.isFloatingPanel = behavior.floatingPanel.resolve(false)
			panel.becomesKeyOnlyIfNeeded = input.becomesKeyOnlyIfNeeded.resolve(false)
			panel.worksWhenModal = behavior.worksWhenModal.resolve(false)
		}

		window.level = behavior.level.nativeLevel(floating: (window as? NSPanel)?.isFloatingPanel ?? false)
		window.animationBehavior =
			[.default, .none, .documentWindow, .utilityWindow, .alertPanel][Int(behavior.animation.rawValue)]
		let spaces = desired.workspaces
		var collection: NSWindow.CollectionBehavior = []
		if spaces.spaces == .all {
			collection.insert(.canJoinAllSpaces)
		}

		if spaces.spaces == .active {
			collection.insert(.moveToActiveSpace)
		}

		collection.formUnion([[], .managed, .transient, .stationary][Int(spaces.management.rawValue)])
		collection.formUnion(
			[[], .primary, .auxiliary, .canJoinAllApplications][Int(spaces.applicationMembership.rawValue)]
		)
		collection.formUnion(
			[[], .fullScreenPrimary, .fullScreenAuxiliary, .fullScreenNone][Int(spaces.fullscreen.rawValue)]
		)
		if spaces.participatesInCycle != .automatic {
			collection.insert(spaces.participatesInCycle == .enabled ? .participatesInCycle : .ignoresCycle)
		}

		if spaces.allowsTiling != .automatic {
			collection.insert(spaces.allowsTiling == .enabled ? .fullScreenAllowsTiling : .fullScreenDisallowsTiling)
		}

		window.collectionBehavior = collection
		window.tabbingMode = [.automatic, .preferred, .disallowed][Int(spaces.tabbing.rawValue)]
		window.tabbingIdentifier = spaces.tabbingIdentifier
		window.minSize = .zero
		window.maxSize = CGSize(width: Double.greatestFiniteMagnitude, height: Double.greatestFiniteMagnitude)
		window.contentMinSize = resizing.minimumContentSize?.cgSize ?? .zero
		window.contentMaxSize =
			resizing.maximumContentSize?.cgSize
			?? CGSize(width: Double.greatestFiniteMagnitude, height: Double.greatestFiniteMagnitude)
		window.minSize = low
		window.maxSize = high
		if let aspect = resizing.frameAspectRatio {
			window.aspectRatio = aspect.cgSize
		} else if let aspect = resizing.contentAspectRatio {
			window.contentAspectRatio = aspect.cgSize
		} else {
			window.contentAspectRatio = .zero
			if let increments = resizing.frameResizeIncrements {
				window.resizeIncrements = increments.cgSize
			} else {
				window.contentResizeIncrements = resizing.contentResizeIncrements?.cgSize ?? CGSize(width: 1, height: 1)
			}
		}

		window.minFullScreenContentSize = resizing.minimumFullscreenContentSize?.cgSize ?? .zero
		window.maxFullScreenContentSize =
			resizing.maximumFullscreenContentSize?.cgSize
			?? CGSize(width: Double.greatestFiniteMagnitude, height: Double.greatestFiniteMagnitude)
		window.preservesContentDuringLiveResize = resizing.preservesContentDuringLiveResize.resolve(true)
		for (edge, thickness) in [
			(NSRectEdge.minX, title.contentBorder?.leading), (.maxX, title.contentBorder?.trailing),
			(.maxY, title.contentBorder?.top), (.minY, title.contentBorder?.bottom),
		] {
			window.setAutorecalculatesContentBorderThickness(thickness == nil, for: edge)
			if let thickness {
				window.setContentBorderThickness(thickness, for: edge)
			}
		}

		let system = desired.systemIntegration
		window.representedURL = system.representedURL
		window.isDocumentEdited = system.isDocumentEdited
		window.miniwindowTitle = system.minimizedTitle ?? window.title
		window.miniwindowImage = system.minimizedImage.flatMap { NSImage(data: $0) }
		window.dockTile.badgeLabel = system.dockBadge
		if style.contains(.titled) {
			window.tab.title = system.tabTitle
			window.tab.toolTip = system.tabTooltip
		}

		if !style.contains(.fullScreen) {
			window.setFrame(constrain(window.frame), display: false)
		}

		window.invalidateShadow()
	}

	func constrain(_ proposed: CGRect) -> CGRect {
		let window = nativeWindow!
		var frame = proposed
		frame.size.width = max(window.minSize.width, min(window.maxSize.width, frame.width))
		frame.size.height = max(window.minSize.height, min(window.maxSize.height, frame.height))
		let sizing = options.resizing
		let frameSizing = sizing.frameAspectRatio != nil || sizing.frameResizeIncrements != nil
		var content = frameSizing ? frame : window.contentRect(forFrameRect: frame)
		let decoration = CGSize(width: frame.width - content.width, height: frame.height - content.height)
		let low = CGSize(
			width: max(0, window.minSize.width - decoration.width),
			height: max(0, window.minSize.height - decoration.height)
		)
		let high = CGSize(
			width: window.maxSize.width - decoration.width,
			height: window.maxSize.height - decoration.height
		)
		if let ratio = sizing.frameAspectRatio ?? sizing.contentAspectRatio {
			let aspect = ratio.width / ratio.height
			content.size.width = max(
				max(low.width, low.height * aspect),
				min(min(high.width, high.height * aspect), content.width)
			)
			content.size.height = content.width / aspect
		} else if let step = sizing.frameResizeIncrements ?? sizing.contentResizeIncrements {
			if step.width > 1 {
				content.size.width = max(low.width, min(high.width, round(content.width / step.width) * step.width))
			}

			if step.height > 1 {
				content.size.height = max(
					low.height,
					min(high.height, round(content.height / step.height) * step.height)
				)
			}
		}

		frame.size = CGSize(width: content.width + decoration.width, height: content.height + decoration.height)
		return frame
	}

	func place(_ creation: STNWindowOptions.Creation) {
		let window = nativeWindow!
		window.identifier = creation.identifier.map { NSUserInterfaceItemIdentifier($0) }
		if let screen = NSScreen.screens.first(where: { $0.stanaID == creation.screenID }) {
			window.setFrameOrigin(
				CGPoint(
					x: screen.visibleFrame.midX - window.frame.width / 2,
					y: screen.visibleFrame.midY - window.frame.height / 2
				)
			)
		}

		if let origin = creation.initialOrigin {
			window.setFrameTopLeftPoint(CGPoint(x: origin.x, y: NSScreen.top - origin.y))
		}

		if let name = creation.frameAutosaveName, !name.isEmpty {
			window.setFrameUsingName(name)
			window.setFrameAutosaveName(name)
		}

		window.setFrame(window.constrainFrameRect(window.frame, to: window.screen), display: false)
		publishState()
	}

	package func perform(_ action: WindowAction) throws {
		guard !closed else {
			throw STNWindowError.closed
		}

		let window = nativeWindow!
		switch action {
		case .show, .focus:
			guard window.canBecomeKey else {
				throw STNWindowError.invalidState("Window cannot become key")
			}

			let responder = window.firstResponder as? ContentView
			if action == .show {
				window.makeKeyAndOrderFront(nil)
			} else {
				window.makeKey()
			}

			window.makeFirstResponder(responder?.window === window ? responder : view)
		case .showInactive, .orderFront: window.orderFront(nil)
		case .hide: window.orderOut(nil)
		case .center: window.center()
		case .minimize:
			guard window.styleMask.contains(.miniaturizable) else {
				throw STNWindowError.unsupportedAction("minimize")
			}

			window.miniaturize(nil)
		case .restore: window.deminiaturize(nil)
		case .zoom:
			guard window.styleMask.contains(.resizable) else {
				throw STNWindowError.unsupportedAction("zoom")
			}

			window.zoom(nil)
		case .orderBack: window.orderBack(nil)
		case .requestClose:
			guard window.styleMask.contains(.closable) else {
				throw STNWindowError.unsupportedAction("close")
			}

			if shouldClose?() ?? true {
				window.close()
			}
		case .customizeToolbar:
			guard window.toolbar?.allowsUserCustomization == true else {
				throw STNWindowError.unsupportedAction("customize toolbar")
			}

			window.runToolbarCustomizationPalette(nil)
		case .toggleToolbar:
			guard window.toolbar != nil else {
				throw STNWindowError.unsupportedAction("toggle toolbar")
			}

			window.toggleToolbarShown(nil)
		case .nextTab: window.selectNextTab(nil)
		case .previousTab: window.selectPreviousTab(nil)
		case .moveTabToWindow: window.moveTabToNewWindow(nil)
		case .mergeWindows: window.mergeAllWindows(nil)
		case .toggleTabBar: window.toggleTabBar(nil)
		case .toggleTabOverview: window.toggleTabOverview(nil)
		case .enterFullscreen, .exitFullscreen: throw STNWindowError.unsupportedAction("Use async fullscreen operation")
		}

		resized()
		graphics.visibilityChanged()
	}

	package func setFrame(_ frame: STNRect, animate: Bool) throws {
		guard !closed else {
			throw STNWindowError.closed
		}

		guard fullscreenTransition == .idle, !nativeWindow.styleMask.contains(.fullScreen) else {
			throw STNWindowError.invalidState("Fullscreen transition")
		}

		nativeWindow.setFrame(constrain(frame.desktopNative), display: true, animate: animate)
		publishState()
	}

	package func setContentSize(_ size: STNSize) throws {
		guard !closed else {
			throw STNWindowError.closed
		}

		var frame = nativeWindow.frameRect(forContentRect: CGRect(origin: .zero, size: size.cgSize))
		frame.origin = nativeWindow.frame.origin
		try setFrame(frame.desktopPortable, animate: false)
	}

	package func saveFrame(_ name: String) throws {
		guard !closed else {
			throw STNWindowError.closed
		}

		guard !isBusy, !name.isEmpty else {
			throw STNWindowError.invalidState("Window busy or empty frame name")
		}

		nativeWindow.saveFrame(usingName: name)
	}

	package func restoreFrame(_ name: String) throws -> Bool {
		guard !closed else {
			throw STNWindowError.closed
		}

		guard !isBusy, !name.isEmpty else {
			throw STNWindowError.invalidState("Window busy or empty frame name")
		}

		let restored = nativeWindow.setFrameUsingName(name)
		nativeWindow.setFrame(
			constrain(nativeWindow.constrainFrameRect(nativeWindow.frame, to: nativeWindow.screen)),
			display: true
		)
		resized()
		return restored
	}

	package func relate(_ other: any PlatformWindow, _ relationship: WindowRelationship) throws {
		guard let other = other as? MacOSWindow, !closed, !other.closed, other !== self else {
			throw STNWindowError.invalidRelationship
		}

		let window = nativeWindow!, target = other.nativeWindow!
		switch relationship {
		case .childAbove, .childBelow:
			var ancestor: NSWindow? = window
			while let current = ancestor {
				if current === target {
					throw STNWindowError.invalidRelationship
				}

				ancestor = current.parent
			}

			guard target.sheetParent == nil, target.parent == nil, (target.tabbedWindows?.count ?? 0) <= 1 else {
				throw STNWindowError.invalidRelationship
			}

			window.addChildWindow(target, ordered: relationship == .childAbove ? .above : .below)
		case .detach:
			guard target.parent === window else {
				throw STNWindowError.invalidRelationship
			}

			window.removeChildWindow(target)
		case .tabBefore, .tabAfter:
			guard window.styleMask.contains(.titled), target.styleMask.contains(.titled),
				options.creation.role == .window,
				other.options.creation.role == .window, window.tabbingMode != .disallowed,
				target.tabbingMode != .disallowed,
				window.sheetParent == nil, target.sheetParent == nil, window.parent == nil, target.parent == nil
			else {
				throw STNWindowError.invalidRelationship
			}

			window.addTabbedWindow(target, ordered: relationship == .tabBefore ? .below : .above)
		case .selectTab, .detachTab:
			guard let group = window.tabGroup, group.windows.contains(target) else {
				throw STNWindowError.invalidRelationship
			}

			if relationship == .selectTab {
				group.selectedWindow = target
			} else {
				group.removeWindow(target)
			}
		}

		publishState()
		other.publishState()
	}

	package func setFullscreen(_ value: Bool) async throws {
		guard !closed else {
			throw STNWindowError.closed
		}

		guard fullscreenTransition == .idle, nativeWindow.attachedSheet == nil, nativeWindow.sheetParent == nil else {
			throw STNWindowError.invalidState("Window busy")
		}

		if nativeWindow.styleMask.contains(.fullScreen) == value {
			return
		}

		guard
			!value
				|| (nativeWindow.styleMask.contains([.titled, .resizable])
					&& !nativeWindow.collectionBehavior.contains(.fullScreenNone))
		else {
			throw STNWindowError.unsupportedAction("fullscreen")
		}

		if value, nativeWindow.collectionBehavior.intersection([.fullScreenPrimary, .fullScreenAuxiliary]).isEmpty {
			nativeWindow.collectionBehavior.insert(.fullScreenPrimary)
		}

		try await withTaskCancellationHandler {
			try Task.checkCancellation()
			try await withCheckedThrowingContinuation { continuation in
				fullscreenOperation = continuation
				fullscreenTransition = value ? .entering : .exiting
				nativeWindow.toggleFullScreen(nil)
				publishState()
			}
		} onCancel: {
			Task { @MainActor [weak self] in
				let continuation = self?.fullscreenOperation
				self?.fullscreenOperation = nil
				continuation?.resume(throwing: STNWindowError.cancelled)
			}
		}
	}

	package func presentSheet(_ sheet: any PlatformWindow, critical: Bool) async throws -> Int32 {
		guard let sheet = sheet as? MacOSWindow, !closed, !sheet.closed, sheet !== self,
			sheet.nativeWindow.sheetParent == nil, sheet.nativeWindow.parent == nil,
			(sheet.nativeWindow.tabbedWindows?.count ?? 0) <= 1, nativeWindow.attachedSheet == nil || critical
		else {
			throw STNWindowError.invalidRelationship
		}

		return try await operation { id in
			modal(true)
			let completion: (NSApplication.ModalResponse) -> Void = { [weak self, weak sheet] result in
				guard let self else {
					return
				}

				self.modal(false)
				self.publishState()
				sheet?.publishState()
				sheet?.graphics.visibilityChanged()
				self.operations.removeValue(forKey: id)?.resume(returning: Int32(result.rawValue))
				self.onIdle?()
			}
			if critical {
				nativeWindow.beginCriticalSheet(sheet.nativeWindow, completionHandler: completion)
			} else {
				nativeWindow.beginSheet(sheet.nativeWindow, completionHandler: completion)
			}

			publishState()
			sheet.publishState()
			sheet.graphics.sheetAttached()
		}
	}

	package func endSheet(_ result: Int32) throws {
		guard !closed, let parent = nativeWindow.sheetParent else {
			throw STNWindowError.invalidState("Not a sheet")
		}

		parent.endSheet(nativeWindow, returnCode: .init(rawValue: Int(result)))
		nativeWindow.orderOut(nil)
	}

	package func requestSharing(of other: (any PlatformWindow)?) async throws {
		guard !closed else {
			throw STNWindowError.closed
		}

		let target = other as? MacOSWindow
		if other != nil, target == nil || target!.closed {
			throw STNWindowError.invalidRelationship
		}

		if target != nil, !nativeWindow.hasActiveWindowSharingSession {
			throw STNWindowError.invalidState("No active sharing session")
		}

		_ = try await operation { id in
			let completion: (Error?) -> Void = { [weak self] error in
				guard let self, let continuation = self.operations.removeValue(forKey: id) else {
					return
				}

				self.publishState()
				if let error {
					continuation.resume(throwing: STNWindowError.nativeFailure(error.localizedDescription))
				} else {
					continuation.resume(returning: 0)
				}
			}
			if let target {
				nativeWindow.transferWindowSharing(to: target.nativeWindow, completionHandler: completion)
			} else {
				nativeWindow.requestSharingOfWindow(nativeWindow, completionHandler: completion)
			}
		}
	}

	private func operation(_ start: (UInt64) -> Void) async throws -> Int32 {
		nextRevision(&operationSerial)
		let id = operationSerial
		return try await withTaskCancellationHandler {
			try Task.checkCancellation()
			return try await withCheckedThrowingContinuation { continuation in
				operations[id] = continuation
				start(id)
			}
		} onCancel: {
			Task { @MainActor [weak self] in
				self?.operations.removeValue(forKey: id)?.resume(throwing: STNWindowError.cancelled)
			}
		}
	}

	package func cancelPendingOperations() {
		let pending = operations
		operations.removeAll()
		for continuation in pending.values {
			continuation.resume(throwing: STNWindowError.cancelled)
		}

		let fullscreen = fullscreenOperation
		fullscreenOperation = nil
		fullscreen?.resume(throwing: STNWindowError.cancelled)
	}
}

extension STNWindowOptions.Level {
	func nativeLevel(floating: Bool) -> NSWindow.Level {
		switch self {
		case .automatic: floating ? .floating : .normal
		case .normal: .normal
		case .floating: .floating
		case .modalPanel: .modalPanel
		case .mainMenu: .mainMenu
		case .status: .statusBar
		case .popUpMenu: .popUpMenu
		case .screenSaver: .screenSaver
		case .custom(let value): .init(rawValue: Int(value))
		}
	}
}
