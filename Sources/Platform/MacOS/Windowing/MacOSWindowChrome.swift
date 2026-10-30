import AppKit
import StanaPlatform
import StanaPrimitives

@MainActor final class ToolbarDelegate: NSObject, NSToolbarDelegate {
	weak var host: MacOSWindow?
	var items: [NSToolbarItem.Identifier: NSToolbarItem] = [:]
	var commands: [UInt64: AnyObject] = [:]
	var checked: [UInt64: Bool] = [:]
	var allowed: [NSToolbarItem.Identifier] = []
	var defaults: [NSToolbarItem.Identifier] = []

	func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
		allowed
	}

	func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
		defaults
	}

	func toolbar(
		_ toolbar: NSToolbar,
		itemForItemIdentifier identifier: NSToolbarItem.Identifier,
		willBeInsertedIntoToolbar flag: Bool
	) -> NSToolbarItem? {
		items[identifier]
	}

	@objc func invoke(_ sender: AnyObject) {
		let command = (sender as? NSButton)?.tag ?? (sender as? NSMenuItem)?.tag ?? (sender as? NSToolbarItem)?.tag ?? 0
		if let button = sender as? NSButton {
			button.state = checked[UInt64(command)] == true ? .on : .off
		}

		if host?.closed == false {
			host?.onCommand?(UInt64(command))
		}
	}

	func menu(_ values: [WindowToolbarItem]) -> NSMenu {
		let menu = NSMenu()
		menu.autoenablesItems = false
		for value in values {
			if value.kind == 1 {
				menu.addItem(.separator())
				continue
			}

			let item = NSMenuItem(
				title: value.title,
				action: value.command == 0 ? nil : #selector(invoke(_:)),
				keyEquivalent: ""
			)
			item.target = self
			item.tag = Int(value.command)
			item.isEnabled = value.enabled
			item.state = value.checked ? .on : .off
			item.image = value.image.flatMap(NSImage.init(data:))
			if value.command != 0 {
				commands[value.command] = item
			}

			if !value.children.isEmpty {
				item.submenu = self.menu(value.children)
			}

			menu.addItem(item)
		}

		return menu
	}

	func item(_ value: WindowToolbarItem) throws -> NSToolbarItem {
		let identifier: NSToolbarItem.Identifier =
			value.kind == 2 ? .space : value.kind == 3 ? .flexibleSpace : .init(value.identifier)
		let item: NSToolbarItem
		if value.kind == 4 {
			let group = NSToolbarItemGroup(itemIdentifier: identifier)
			group.subitems = try value.children.map(self.item)
			item = group
		} else if value.kind == 5 {
			let menu = NSMenuToolbarItem(itemIdentifier: identifier)
			menu.menu = self.menu(value.children)
			item = menu
		} else {
			item = NSToolbarItem(itemIdentifier: identifier)
			if value.kind == 6 {
				guard let surface = value.surface as? MacOSWindow, !surface.closed, surface.isSurface else {
					throw STNWindowError.invalidRelationship
				}

				item.view = surface.view
			} else if value.kind == 1 {
				let space = NSView(frame: CGRect(x: 0, y: 0, width: 12, height: 24))
				let line = NSBox(frame: CGRect(x: 5, y: 2, width: 1, height: 20))
				line.boxType = .separator
				space.addSubview(line)
				item.view = space
			}
		}

		item.label = value.title
		item.paletteLabel = value.title
		item.toolTip = value.tooltip
		item.isEnabled = value.enabled
		item.visibilityPriority = .init(rawValue: Int(value.priority))
		item.autovalidates = false
		item.image = value.image.flatMap(NSImage.init(data:))
		if value.command != 0 {
			guard value.command <= UInt64(Int.max) else {
				throw STNWindowError.invalidConfiguration("Toolbar command exceeds native tag range")
			}

			item.target = self
			item.action = #selector(invoke(_:))
			item.tag = Int(value.command)
			commands[value.command] = item
			checked[value.command] = value.checked
			let button = NSButton(title: value.title, target: self, action: #selector(invoke(_:)))
			button.setButtonType(.pushOnPushOff)
			button.bezelStyle = .texturedRounded
			button.tag = Int(value.command)
			button.state = value.checked ? .on : .off
			button.isEnabled = value.enabled
			button.toolTip = value.tooltip
			button.image = item.image
			button.imagePosition = item.image == nil ? .noImage : .imageLeading
			button.sizeToFit()
			item.view = button
		}

		items[identifier] = item
		return item
	}
}

extension MacOSWindow {
	package func setToolbar(
		_ toolbar: WindowToolbar?,
		replacing: Bool,
		visible: Bool,
		style: STNWindowOptions.ToolbarStyle,
		display: STNWindowOptions.ToolbarDisplay
	) throws {
		guard !closed else {
			throw STNWindowError.closed
		}

		if replacing {
			if let toolbar {
				let delegate = ToolbarDelegate()
				delegate.host = self
				var mapping: [String: NSToolbarItem.Identifier] = [:]
				for value in toolbar.items {
					let item = try delegate.item(value)
					delegate.allowed.append(item.itemIdentifier)
					mapping[value.identifier] = item.itemIdentifier
				}

				delegate.defaults = toolbar.defaultIdentifiers.map { mapping[$0] ?? .init($0) }
				let native = NSToolbar(identifier: toolbar.identifier)
				native.delegate = delegate
				native.allowsUserCustomization = toolbar.allowsCustomization
				native.autosavesConfiguration = toolbar.autosavesConfiguration
				toolbarDelegate = delegate
				nativeWindow.toolbar = native
			} else {
				nativeWindow.toolbar = nil
				toolbarDelegate = nil
			}
		}

		nativeWindow.toolbarStyle = NSWindow.ToolbarStyle(rawValue: Int(style.rawValue)) ?? .automatic
		nativeWindow.toolbar?.isVisible = visible
		nativeWindow.toolbar?.displayMode = NSToolbar.DisplayMode(rawValue: UInt(display.rawValue)) ?? .default
		for item in toolbarDelegate?.items.values ?? Dictionary<NSToolbarItem.Identifier, NSToolbarItem>().values {
			if let button = item.view as? NSButton {
				button.imagePosition =
					button.image == nil || display == .labelOnly
					? .noImage : display == .iconOnly ? .imageOnly : .imageLeading
				button.sizeToFit()
			}
		}

		resized()
	}

	package func updateToolbarCommand(_ id: UInt64, title: String, enabled: Bool, checked: Bool) {
		if let menu = toolbarDelegate?.commands[id] as? NSMenuItem {
			menu.title = title
			menu.isEnabled = enabled
			menu.state = checked ? .on : .off
		}

		if let item = toolbarDelegate?.commands[id] as? NSToolbarItem {
			item.label = title
			item.paletteLabel = title
			item.isEnabled = enabled
			toolbarDelegate?.checked[id] = checked
			if let button = item.view as? NSButton {
				button.title = title
				button.isEnabled = enabled
				button.state = checked ? .on : .off

				button.sizeToFit()
			}
		}
	}

	package func setTabAccessory(_ surface: (any PlatformWindow)?) throws {
		guard !closed else {
			throw STNWindowError.closed
		}

		guard nativeWindow.styleMask.contains(.titled) || surface == nil else {
			throw STNWindowError.unsupportedAction("Tab accessory on frameless window")
		}

		if !nativeWindow.styleMask.contains(.titled) {
			return
		}

		let target = surface as? MacOSWindow
		guard surface == nil || (target?.closed == false && target?.isSurface == true) else {
			throw STNWindowError.invalidRelationship
		}

		if nativeWindow.tab.accessoryView !== target?.view {
			nativeWindow.tab.accessoryView = target?.view
			if let view = target?.view {
				view.widthAnchor.constraint(equalToConstant: view.bounds.width).isActive = true

				view.heightAnchor.constraint(equalToConstant: view.bounds.height).isActive = true
			}
		}
	}

	package func setAccessories(_ values: [WindowAccessory]) throws {
		guard !closed else {
			throw STNWindowError.closed
		}

		guard nativeWindow.styleMask.contains(.titled) || values.isEmpty else {
			throw STNWindowError.unsupportedAction("Titlebar accessories on frameless window")
		}

		if !nativeWindow.styleMask.contains(.titled) {
			return
		}

		var byID: [String: NSTitlebarAccessoryViewController] = [:]
		var ordered: [NSTitlebarAccessoryViewController] = []
		for value in values {
			guard let surface = value.surface as? MacOSWindow, !surface.closed, surface.isSurface else {
				throw STNWindowError.invalidRelationship
			}

			let existing = accessories[value.identifier]
			let controller = existing?.view === surface.view ? existing! : NSTitlebarAccessoryViewController()
			controller.view = surface.view
			controller.layoutAttribute = value.placement == 0 ? .leading : value.placement == 1 ? .trailing : .bottom
			controller.fullScreenMinHeight = value.fullscreenMinimumHeight
			controller.isHidden = value.hidden
			byID[value.identifier] = controller
			ordered.append(controller)
		}

		if nativeWindow.titlebarAccessoryViewControllers != ordered {
			while !nativeWindow.titlebarAccessoryViewControllers.isEmpty {
				nativeWindow.removeTitlebarAccessoryViewController(
					at: nativeWindow.titlebarAccessoryViewControllers.count - 1
				)
			}

			for controller in ordered {
				nativeWindow.addTitlebarAccessoryViewController(controller)
			}
		}

		accessories = byID
		resized()
	}
}
