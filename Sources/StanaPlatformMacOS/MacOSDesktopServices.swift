import CStanaMacOS
import Foundation

@MainActor package enum MacOSDesktopServices {
	private static var actions: [UInt64: () -> Void] = [:]
	private static var serial: UInt64 = 0

	package static func writeClipboard(_ text: String) {
		text.withNativeUTF8 { stn_clipboard_write($0) }
	}

	package static func readClipboard() -> String? {
		var length = 0
		guard let value = stn_clipboard_copy(&length) else {
			return nil
		}

		defer {
			stn_string_free(value)
		}

		return stn_utf8(bytes: value, length: length).string
	}

	package static func stop() {
		stn_app_stop()
	}

	package static func resetMenus() {
		actions.removeAll()
		serial = 0
		stn_menu_reset(nil) { _, identity in MainActor.assumeIsolated { MacOSDesktopServices.actions[identity]?() } }
	}

	package static func addMenu(parent: UInt64, title: String) -> UInt64 {
		title.withNativeUTF8 { stn_menu_add(parent, $0, 0, stn_utf8(bytes: nil, length: 0), 0, true, false) }
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
		precondition(serial < .max)
		serial += 1
		actions[serial] = action
		return title.withNativeUTF8 { title in
			key.withNativeUTF8 { stn_menu_add(parent, title, serial, $0, modifiers, enabled, checked) }
		}
	}

	package static func updateMenu(_ id: UInt64, title: String, enabled: Bool, checked: Bool) {
		title.withNativeUTF8 { stn_menu_update(id, $0, enabled, checked) }
	}

	package static func fileDialog(window: MacOSWindow?, save: Bool, name: String) async -> URL? {
		await withCheckedContinuation { continuation in
			let context = Unmanaged.passRetained(DialogResult(continuation)).toOpaque()
			name.withNativeUTF8 { stn_file_dialog(window?.handle, save, $0, context, dialogCallback) }
		}
	}

	package static func alert(window: MacOSWindow?, title: String, message: String) async {
		let _: URL? = await withCheckedContinuation { continuation in
			let context = Unmanaged.passRetained(DialogResult(continuation)).toOpaque()
			title.withNativeUTF8 { title in
				message.withNativeUTF8 { stn_alert(window?.handle, title, $0, context, dialogCallback) }
			}
		}
	}
}

@MainActor private final class DialogResult {
	let continuation: CheckedContinuation<URL?, Never>

	init(_ continuation: CheckedContinuation<URL?, Never>) {
		self.continuation = continuation
	}
}

private let dialogCallback: stn_dialog_callback = { context, path, status in
	guard let context else {
		return
	}

	let result = Unmanaged<DialogResult>.fromOpaque(context).takeRetainedValue()
	let url = status == 0 ? path.map { URL(fileURLWithPath: String(cString: $0)) } : nil
	MainActor.assumeIsolated {
		result.continuation.resume(returning: url)
	}
}
