import Foundation
import StanaCore
import StanaPlatformMacOS
import StanaPrimitives

@MainActor public enum STNApplication {
	private static var windows: [ObjectIdentifier: STNWindow] = [:]

	public static var screens: [STNScreen] {
		MacOSHost.screens
	}

	public static func removeSavedWindowFrame(named name: String) {
		MacOSHost.removeSavedFrame(name)
	}

	private static var menus: [STNMenu] = []

	/// Enters the native event loop. Call from a synchronous `@MainActor` entry point.
	public static func run(windows: [STNWindow], menus: [STNMenu] = []) {
		install(menus: menus)
		for window in windows {
			do {
				try open(window)
			} catch {
				STNDiagnostics.report(.nativeFailure("Window creation failed"))
			}
		}

		MacOSHost().run()
	}

	public static func open(_ window: STNWindow) throws {
		if window.session != nil {
			return
		}

		try window.open(using: MacOSHost())
		guard window.isOpen else {
			return
		}

		windows[ObjectIdentifier(window)] = window
		window.onClosed = { [weak window] in
			guard let window else {
				return
			}

			windows.removeValue(forKey: ObjectIdentifier(window))
		}
	}

	public static func install(menus: [STNMenu]) {
		for menu in self.menus {
			menu.uninstall()
		}

		self.menus = menus
		MacOSDesktopServices.resetMenus()
		for menu in menus {
			menu.install(parent: 0)
		}
	}

	public static func stop() {
		for window in Array(windows.values) {
			window.close()
		}

		windows.removeAll()
		menus.forEach { $0.uninstall() }
		menus.removeAll()
		MacOSDesktopServices.resetMenus()
		MacOSDesktopServices.stop()
	}
}
