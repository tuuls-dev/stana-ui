import StanaCore
import StanaPlatform
import StanaPrimitives

/// Native-window lifetime and policy. MountSession remains the retained content
/// lifetime, including separate sessions for custom native-chrome surfaces.
@MainActor package final class WindowController {
	package weak var owner: STNWindow?
	package let host: any PlatformHost
	package let native: any PlatformWindow
	package let session: MountSession
	package let initial: STNWindowOptions
	private let initialRequest: STNWindowOptions
	package weak var parent: WindowController?
	package var children: [STNWindow] = []
	package var sheets: [STNWindow] = []
	private var applied: STNWindow.Configuration
	private var pending: STNWindow.Configuration?
	private var closing = false
	private var applying = false
	private var chromeSessions: [String: (ObjectIdentifier, MountSession)] = [:]
	private var toolbarObservations: [Observation] = []
	private var toolbarActions: [UInt64: STNCommand] = [:]
	private var toolbarSerial: UInt64 = 0

	package init(owner: STNWindow, host: any PlatformHost) throws {
		let size = owner.properties.size
		guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else {
			throw STNWindowError.invalidConfiguration("Initial content size must be finite and positive")
		}

		let desired = owner.properties.configuration.read()
		try Self.validate(desired)
		let resolved = try host.resolve(desired.options, initial: nil)
		self.owner = owner
		self.host = host
		initial = resolved.options
		initialRequest = desired.options
		native = try host.createWindow(
			title: owner.properties.title.read(),
			size: owner.properties.size,
			options: resolved.options
		)
		session = MountSession(
			size: owner.properties.size,
			text: host.textService,
			environment: owner.properties.environment
		)
		applied = desired
		applied.options = resolved.options
	}

	package func mount(show: Bool) {
		guard let owner else {
			return
		}

		session.onClose = { [weak self] in self?.didClose() }
		session.onStable = { [weak self] in self?.flushPending() }
		native.onState = { [weak self] state in self?.receive(state) }
		native.onIdle = { [weak self] in self?.flushPending() }
		native.shouldClose = { [weak owner] in owner?.properties.shouldClose?() ?? true }
		native.onCommand = { [weak self] id in self?.toolbarActions[id]?.perform() }
		session.document.surfaceBackground = applied.appearance.background
		session.document.renderingColorMode = applied.renderingColorMode
		session.document.windowBackgroundDragging =
			applied.interaction.backgroundDragging && applied.interaction.isMovable
		session.attach(native)
		receive(native.state)
		session.mount(owner.content)
		guard !closing else {
			return
		}

		// Resolve/apply once here as well so chrome is installed after the
		// window and component lifetimes have been connected.
		update(owner.properties.configuration.read(), force: true)
		if owner.properties.title.reactive {
			let observation = ValueObservation(read: owner.properties.title.read, equals: { $0 == $1 }) {
				[weak native] value in
				native?.setTitle(value)
			}
			session.document.root.scope.own { observation.cancel() }
			ReactiveRuntime.shared.batch { ReactiveRuntime.shared.enqueue(observation) }
		}

		if owner.properties.configuration.reactive {
			let observation = ValueObservation(read: owner.properties.configuration.read, equals: { $0 == $1 }) {
				[weak self] value in
				self?.update(value)
			}
			session.document.root.scope.own { observation.cancel() }
			ReactiveRuntime.shared.batch { ReactiveRuntime.shared.enqueue(observation) }
		}

		if show && initial.creation.initiallyVisible {
			do {
				try native.perform(
					initial.creation.activatesOnOpen && applied.interaction.canBecomeKey != .disabled
						? .show : .showInactive
				)
			} catch {
				report(error)
			}
		}
	}

	private static func validate(_ configuration: STNWindow.Configuration) throws {
		try configuration.options.validate()
		try configuration.chrome.toolbar?.validate()
		if let tab = configuration.chrome.tabAccessory {
			guard !tab.identifier.isEmpty else {
				throw STNWindowError.invalidConfiguration("Empty tab accessory identifier")
			}

			try validateChromeSize(tab.size)
		}

		var ids = Set<String>()
		for accessory in configuration.chrome.accessories {
			let p = accessory.properties
			guard !p.identifier.isEmpty, ids.insert(p.identifier).inserted,
				p.fullscreenMinimumHeight.isFinite, p.fullscreenMinimumHeight >= 0
			else {
				throw STNWindowError.invalidConfiguration("Invalid or duplicate title-bar accessory")
			}

			try validateChromeSize(p.size)
		}
	}

	private func receive(_ state: STNWindowState) {
		guard !closing, let owner else {
			return
		}

		owner.stateSource.value = state
		if !state.isVisible || state.isMinimized {
			for registration in session.frameRegistrations { registration.lastTimestamp = nil }
			for (_, mount) in chromeSessions.values {
				for registration in mount.frameRegistrations { registration.lastTimestamp = nil }
			}
		}
		if session.document.viewport != state.contentSize {
			session.document.viewport = state.contentSize
			session.document.changed(session.document.root, .all)
		}

		if session.safeContentBounds.value != state.safeContentBounds {
			session.safeContentBounds.value = state.safeContentBounds
		}

		if state.fullscreenTransition == .idle && !state.isInLiveResize && !applying {
			flushPending()
		}
	}

	private func update(_ desired: STNWindow.Configuration, force: Bool = false) {
		guard !closing, !applying, let owner else {
			return
		}

		do {
			try Self.validate(desired)
			let resolved = try host.resolve(desired.options, initial: initialRequest)
			var effective = desired
			effective.options = resolved.options
			var resolution = resolved.resolution
			if !native.supportsChrome || effective.appearance.frame == .frameless {
				if effective.chrome != .init() {
					resolution.ignored.append(
						.init("chrome", reason: native.supportsChrome ? .inapplicable : .unsupported)
					)
					effective.chrome = .init()
				}
			}

			let structural =
				effective.appearance.frame != applied.appearance.frame
				|| effective.titleBar != applied.titleBar || effective.chrome != applied.chrome
			if !force && structural
				&& (native.isBusy || session.hasMarkedText || chromeSessions.values.contains { $0.1.hasMarkedText })
			{
				pending = desired
				resolution.isPending = true
				owner.resolutionSource.value = resolution
				return
			}

			applying = true
			defer {
				applying = false
			}

			pending = nil
			if force || effective != applied {
				try native.apply(effective.options)
				if force || effective.chrome != applied.chrome {
					try applyChrome(effective.chrome)
				}

				session.document.surfaceBackground = effective.appearance.background
				session.document.renderingColorMode = effective.renderingColorMode
				for (_, chrome) in chromeSessions.values {
					chrome.document.renderingColorMode = effective.renderingColorMode
					chrome.document.changed(chrome.document.root, .paint)
				}
				session.document.windowBackgroundDragging =
					effective.interaction.backgroundDragging && effective.interaction.isMovable
				session.document.changed(session.document.root, .all)
				applied = effective
			}

			STNTransaction.perform {
				owner.appliedSource.value = applied
				owner.resolutionSource.value = resolution
			}
		} catch {
			report(error)
		}
	}

	private func report(_ error: any Error) {
		let failure = error as? STNWindowError ?? .nativeFailure("Window configuration failed")
		owner?.properties.onConfigurationError?(failure)
		session.report(.nativeFailure("Window configuration failed"))
	}

	package func flushPending() {
		guard !closing, !applying, let pending else {
			return
		}

		update(pending)
	}

	package func close() {
		guard !closing else {
			return
		}

		native.cancelPendingOperations()
		for child in children {
			child.close()
		}

		children.removeAll()
		for sheet in sheets {
			try? sheet.endSheet()
			sheet.close()
		}

		sheets.removeAll()
		session.close()
	}

	private func didClose() {
		guard !closing else {
			return
		}

		closing = true
		pending = nil
		for child in children {
			child.close()
		}

		children.removeAll()
		for sheet in sheets {
			sheet.close()
		}

		sheets.removeAll()
		toolbarObservations.forEach { $0.cancel() }
		toolbarObservations.removeAll()
		toolbarActions.removeAll()
		for (_, surface) in chromeSessions.values {
			surface.close()
		}

		chromeSessions.removeAll()
		if let owner {
			parent?.children.removeAll { $0 === owner }
			var state = owner.stateSource.value
			state.isOpen = false
			state.isVisible = false
			state.isKey = false
			state.isMain = false
			state.parentID = nil
			state.childIDs = []
			state.tabIDs = []
			state.hasSheet = false
			state.isSheet = false
			state.fullscreenTransition = .idle
			STNTransaction.perform {
				owner.stateSource.value = state
				owner.resolutionSource.value.isPending = false
			}
			owner.controller = nil
			let callback = owner.onClosed
			owner.onClosed = nil
			callback?()
		}

		parent = nil
	}

	private func surface(
		id: String,
		identity: ObjectIdentifier,
		size: STNSize,
		content: () -> STNGroup,
		keep: inout Set<String>
	) throws -> any PlatformWindow {
		keep.insert(id)
		if let (oldIdentity, session) = chromeSessions[id], oldIdentity == identity, let window = session.window {
			return window
		}

		chromeSessions.removeValue(forKey: id)?.1.close()
		let window = try host.createSurface(in: native, size: size)
		let mount = MountSession(size: size, text: host.textService, environment: session.environment)
		mount.onStable = { [weak self] in self?.flushPending() }
		mount.document.surfaceBackground = .clear
		mount.document.renderingColorMode = applied.renderingColorMode
		mount.attach(window)
		mount.mount(content)
		chromeSessions[id] = (identity, mount)
		return window
	}

	private func applyChrome(_ chrome: STNWindow.Chrome) throws {
		guard native.supportsChrome else {
			return
		}

		var keep = Set<String>()
		// Reuse stable surfaces even if toolbar style/visibility changes.
		if chrome.toolbar !== applied.chrome.toolbar || owner?.appliedSource.value == nil {
			toolbarObservations.forEach { $0.cancel() }
			toolbarObservations.removeAll()
			toolbarActions.removeAll()
			var toolbar: WindowToolbar?
			if let definition = chrome.toolbar {
				@MainActor func items(_ definitions: [STNToolbar.Item]) throws -> [WindowToolbarItem] {
					try definitions.map { item in
						var result = WindowToolbarItem(identifier: item.identifier, kind: 0)
						switch item {
						case .command(_, let command, let image, let tooltip, let priority):
							precondition(toolbarSerial < .max)
							toolbarSerial += 1
							let id = toolbarSerial
							toolbarActions[id] = command
							result.command = id
							result.title = command.properties.title.read()
							result.enabled = command.properties.enabled.read()
							result.checked = command.properties.checked.read()
							result.image = image
							result.tooltip = tooltip
							result.priority = Int32(clamping: priority)

							@MainActor func observe<V: Equatable>(_ property: Property<V>) {
								guard property.reactive else {
									return
								}

								let observation = ValueObservation(read: property.read, equals: { $0 == $1 }) {
									[weak native] _ in
									native?
										.updateToolbarCommand(
											id,
											title: command.properties.title.read(),
											enabled: command.properties.enabled.read(),
											checked: command.properties.checked.read()
										)
								}
								toolbarObservations.append(observation)
								ReactiveRuntime.shared.batch { ReactiveRuntime.shared.enqueue(observation) }
							}

							observe(command.properties.title)
							observe(command.properties.enabled)
							observe(command.properties.checked)
						case .separator: result.kind = 1
						case .space: result.kind = 2
						case .flexibleSpace: result.kind = 3
						case .group(_, let title, let children):
							result.kind = 4
							result.title = title
							result.children = try items(children)
						case .menu(_, let title, let children):
							result.kind = 5
							result.title = title
							result.children = try items(children)
						case .content(let content):
							result.kind = 6
							result.surface = try surface(
								id: "toolbar:" + content.identifier,
								identity: ObjectIdentifier(content),
								size: content.size,
								content: content.content,
								keep: &keep
							)
						}

						return result
					}
				}

				toolbar = .init(
					identifier: definition.properties.identifier,
					allowsCustomization: definition.properties.allowsCustomization,
					autosavesConfiguration: definition.properties.autosavesConfiguration,
					defaultIdentifiers: definition.properties.defaultItemIdentifiers
						?? definition.items.map(\.identifier),
					items: try items(definition.items)
				)
			}

			try native.setToolbar(
				toolbar,
				replacing: true,
				visible: chrome.toolbarVisible,
				style: chrome.toolbarStyle,
				display: chrome.toolbarDisplay
			)
		} else {
			// A nil descriptor updates presentation without replacing the toolbar.
			try native.setToolbar(
				nil,
				replacing: false,
				visible: chrome.toolbarVisible,
				style: chrome.toolbarStyle,
				display: chrome.toolbarDisplay
			)
			for key in chromeSessions.keys where key.hasPrefix("toolbar:") {
				keep.insert(key)
			}
		}

		let accessories = try chrome.accessories.map { accessory -> WindowAccessory in
			let p = accessory.properties
			let window = try surface(
				id: "accessory:" + p.identifier,
				identity: ObjectIdentifier(accessory),
				size: p.size,
				content: accessory.content,
				keep: &keep
			)
			return .init(
				identifier: p.identifier,
				placement: p.placement.rawValue,
				fullscreenMinimumHeight: p.fullscreenMinimumHeight,
				hidden: p.hidden,
				surface: window
			)
		}
		try native.setAccessories(accessories)
		var tabSurface: (any PlatformWindow)?
		if let tab = chrome.tabAccessory {
			tabSurface = try surface(
				id: "tab:" + tab.identifier,
				identity: ObjectIdentifier(tab),
				size: tab.size,
				content: tab.content,
				keep: &keep
			)
		}

		try native.setTabAccessory(tabSurface)
		for key in Array(chromeSessions.keys) where !keep.contains(key) {
			chromeSessions.removeValue(forKey: key)?.1.close()
		}
	}
}
