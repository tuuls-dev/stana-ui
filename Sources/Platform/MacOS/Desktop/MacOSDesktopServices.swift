import AppKit
import Foundation
import StanaPrimitives

@MainActor package enum MacOSDesktopServices {
	private static var target = MenuTarget()
	private static var menus: [UInt64: NSMenu] = [:]
	private static var items: [UInt64: NSMenuItem] = [:]
	private static var actions: [UInt64: () -> Void] = [:]
	private static var alerts: [UInt64: StandaloneAlert] = [:]

	package static func writeClipboard(_ text: String) {
		NSPasteboard.general.clearContents()
		NSPasteboard.general.setString(text, forType: .string)
	}

	package static func readClipboard() -> String? {
		NSPasteboard.general.string(forType: .string)
	}

	package static func stop() {
		NativeApplication.stop()
	}

	package static func resetMenus() {
		NativeApplication.initialize()
		target = MenuTarget()
		actions.removeAll()
		items.removeAll()
		menus.removeAll()
		let main = NSMenu()
		main.autoenablesItems = false
		NSApp.mainMenu = main
		menus[0] = main
		let application = NSMenuItem()
		let submenu = NSMenu(title: ProcessInfo.processInfo.processName)
		application.submenu = submenu
		main.addItem(application)
		submenu.addItem(
			withTitle: "About",
			action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
			keyEquivalent: ""
		)
		submenu.addItem(.separator())
		submenu.addItem(withTitle: "Hide", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
		submenu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
	}

	package static func addMenu(parent: UInt64, title: String) -> UInt64 {
		guard let parent = menus[parent] else {
			return 0
		}

		let identity = UIIdentityAllocator.next()
		let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
		let submenu = NSMenu(title: title)
		submenu.autoenablesItems = false
		item.submenu = submenu
		menus[identity] = submenu
		items[identity] = item
		parent.addItem(item)
		return identity
	}

	package static func addCommand(
		parent: UInt64,
		title: String,
		key: String,
		modifiers: UInt32,
		enabled: Bool,
		checked: Bool,
		action: @escaping () -> Void
	) -> UInt64 {
		guard let parent = menus[parent] else {
			return 0
		}

		let identity = UIIdentityAllocator.next()
		actions[identity] = action
		let item = NSMenuItem(title: title, action: #selector(MenuTarget.invoke(_:)), keyEquivalent: key)
		item.target = target
		item.representedObject = NSNumber(value: identity)
		item.isEnabled = enabled
		item.state = checked ? .on : .off
		var flags: NSEvent.ModifierFlags = []
		if modifiers & 1 != 0 {
			flags.insert(.command)
		}

		if modifiers & 2 != 0 {
			flags.insert(.shift)
		}

		if modifiers & 4 != 0 {
			flags.insert(.option)
		}

		if modifiers & 8 != 0 {
			flags.insert(.control)
		}

		item.keyEquivalentModifierMask = flags
		parent.addItem(item)
		items[identity] = item
		return identity
	}

	package static func updateMenu(_ id: UInt64, title: String, enabled: Bool, checked: Bool) {
		items[id]?.title = title
		items[id]?.isEnabled = enabled
		items[id]?.state = checked ? .on : .off
	}

	package static func fileDialog(window: MacOSWindow?, save: Bool, name: String) async -> URL? {
		let panel: NSSavePanel = save ? NSSavePanel() : NSOpenPanel()
		if save, !name.isEmpty {
			panel.nameFieldStringValue = name
		}

		if let open = panel as? NSOpenPanel {
			open.canChooseDirectories = false
			open.allowsMultipleSelection = false
		}

		let parent = window?.nativeWindow ?? NSApp.mainWindow
		let host = parent?.delegate as? MacOSWindow
		host?.modal(true)
		return await withCheckedContinuation { continuation in
			let completion: (NSApplication.ModalResponse) -> Void = { [weak host] result in
				host?.modal(false)
				continuation.resume(returning: result == .OK ? panel.url : nil)
			}
			if let parent {
				panel.beginSheetModal(for: parent, completionHandler: completion)
			} else {
				panel.begin(completionHandler: completion)
			}
		}
	}

	package static func alert(window: MacOSWindow?, title: String, message: String) async {
		let alert = NSAlert()
		alert.messageText = title
		alert.informativeText = message
		alert.addButton(withTitle: "OK")
		let parent = window?.nativeWindow ?? NSApp.mainWindow
		let host = parent?.delegate as? MacOSWindow
		host?.modal(true)
		await withCheckedContinuation { continuation in
			if let parent {
				alert.beginSheetModal(for: parent) { [weak host] _ in
					host?.modal(false)
					continuation.resume()
				}
			} else {
				let id = UIIdentityAllocator.next()
				let presenter = StandaloneAlert(alert: alert) {
					alerts.removeValue(forKey: id)
					continuation.resume()
				}
				alerts[id] = presenter
				presenter.show()
			}
		}
	}

	@MainActor private final class MenuTarget: NSObject {
		@objc func invoke(_ sender: NSMenuItem) {
			guard let id = sender.representedObject as? NSNumber else {
				return
			}

			actions[id.uint64Value]?()
		}
	}
}

@MainActor private final class StandaloneAlert: NSObject, NSWindowDelegate {
	let alert: NSAlert
	private var completion: (() -> Void)?

	init(alert: NSAlert, completion: @escaping () -> Void) {
		self.alert = alert
		self.completion = completion
	}

	func show() {
		alert.window.delegate = self
		alert.buttons.first?.target = self
		alert.buttons.first?.action = #selector(dismiss(_:))
		alert.window.center()
		alert.window.makeKeyAndOrderFront(nil)
	}

	@objc func dismiss(_ sender: Any?) {
		guard let completion else {
			return
		}

		self.completion = nil
		alert.window.close()
		completion()
	}

	func windowWillClose(_ notification: Notification) {
		dismiss(nil)
	}
}
