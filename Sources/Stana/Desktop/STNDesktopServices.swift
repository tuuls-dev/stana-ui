import Foundation
import StanaPlatformMacOS
import StanaPrimitives

@MainActor public enum STNClipboard {
	public static func write(_ text: String) {
		MacOSDesktopServices.writeClipboard(text)
	}

	public static func readText() -> String? {
		MacOSDesktopServices.readClipboard()
	}
}

@MainActor public enum STNFileDialog {
	/// Returns nil on cancellation. File reading/writing remains application-owned.
	public static func open(in window: STNWindow? = nil) async -> URL? {
		await MacOSDesktopServices.fileDialog(window: window?.session?.window as? MacOSWindow, save: false, name: "")
	}

	public static func save(suggestedName: String = "Untitled", in window: STNWindow? = nil) async -> URL? {
		await MacOSDesktopServices.fileDialog(
			window: window?.session?.window as? MacOSWindow,
			save: true,
			name: suggestedName
		)
	}
}

@MainActor public enum STNAlert {
	public static func show(title: String, message: String, in window: STNWindow? = nil) async {
		await MacOSDesktopServices.alert(
			window: window?.session?.window as? MacOSWindow,
			title: title,
			message: message
		)
	}
}
