import AppKit

@MainActor enum NativeApplication {
	private static var delegate: ApplicationDelegate?

	static func initialize() {
		let application = NSApplication.shared
		application.setActivationPolicy(.regular)
		if delegate == nil {
			delegate = ApplicationDelegate()
			application.delegate = delegate
		}
	}

	static func run() {
		initialize()
		NSApp.activate()
		NSApp.run()
	}

	static func stop() {
		guard let application = NSApp else {
			return
		}

		application.stop(nil)
		if let event = NSEvent.otherEvent(
			with: .applicationDefined,
			location: .zero,
			modifierFlags: [],
			timestamp: 0,
			windowNumber: 0,
			context: nil,
			subtype: 0,
			data1: 0,
			data2: 0
		) {
			application.postEvent(event, atStart: false)
		}
	}
}

@MainActor private final class ApplicationDelegate: NSObject, NSApplicationDelegate {
	func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
		true
	}
}
