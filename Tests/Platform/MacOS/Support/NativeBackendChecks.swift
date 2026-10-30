import AppKit
import Foundation
import ImageIO
import StanaPrimitives

@testable import StanaPlatformMacOS

extension String {
	func withNativeString<Result>(_ body: (String) throws -> Result) rethrows -> Result { try body(self) }
}

@MainActor func exportNativePNG(_ window: MacOSWindow, _ path: String) async throws -> Bool {
	let image = try await window.capture()
	let data = image.displayMappedBGRA()
	guard let provider = CGDataProvider(data: data as CFData),
		let cgImage = CGImage(
			width: image.width,
			height: image.height,
			bitsPerComponent: 8,
			bitsPerPixel: 32,
			bytesPerRow: image.width * 4,
			space: CGColorSpace(name: CGColorSpace.sRGB)!,
			bitmapInfo: CGBitmapInfo(
				rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
			),
			provider: provider,
			decode: nil,
			shouldInterpolate: false,
			intent: .defaultIntent
		),
		let output = CGImageDestinationCreateWithURL(
			URL(fileURLWithPath: path) as CFURL,
			"public.png" as CFString,
			1,
			nil
		)
	else { return false }
	CGImageDestinationAddImage(output, cgImage, nil)
	return CGImageDestinationFinalize(output)
}

@MainActor func nativePixelHash(_ window: MacOSWindow) async throws -> UInt64 {
	let image = try await window.capture()
	return image.data.reduce(UInt64(1_469_598_103_934_665_603)) { ($0 ^ UInt64($1)) &* 1_099_511_628_211 }
}

@MainActor func exportNativeScene(_ window: MacOSWindow, _ path: String, _ linear: Bool) async throws -> Bool {
	let image = try await window.capture()
	try (linear ? image.data : image.displayMappedBGRA()).write(to: URL(fileURLWithPath: path))
	let metadata: [String: Int] = ["width": image.width, "height": image.height]
	try JSONEncoder().encode(metadata).write(to: URL(fileURLWithPath: path + ".json"))
	return true
}

@MainActor func nativeSemanticCount(_ window: MacOSWindow) -> Int { window.semanticNodes.count }
@MainActor func nativeSemanticRevision(_ window: MacOSWindow) -> UInt64 { window.semanticRevision }
@MainActor func nativeStyle(_ window: MacOSWindow) -> UInt { window.nativeWindow.styleMask.rawValue }

@MainActor func nativeProperty(_ window: MacOSWindow, _ property: Int) -> Double {
	let native = window.nativeWindow!
	switch property {
	case 1: return native.isOpaque ? 1 : 0
	case 2: return native.canBecomeKey ? 1 : 0
	case 3: return native.canBecomeMain ? 1 : 0
	case 4: return native is NSPanel ? 1 : 0
	case 5: return native.contentMinSize.width
	case 6: return native.contentMinSize.height
	case 7: return native.alphaValue
	case 8: return native.hasShadow ? 1 : 0
	case 9: return native.standardWindowButton(.closeButton)?.isHidden == true ? 1 : 0
	case 10: return native.standardWindowButton(.miniaturizeButton)?.isHidden == true ? 1 : 0
	case 11: return native.standardWindowButton(.zoomButton)?.isHidden == true ? 1 : 0
	case 12: return native.contentMaxSize.width
	case 13: return native.contentMaxSize.height
	case 14: return Double(native.toolbar?.items.count ?? 0)
	case 15: return Double(native.titlebarAccessoryViewControllers.count)
	default: return -1
	}
}

@MainActor func nativeKeyEquivalent(_ window: MacOSWindow, _ key: String) -> Bool {
	guard
		let event = NSEvent.keyEvent(
			with: .keyDown,
			location: .zero,
			modifierFlags: .command,
			timestamp: 0,
			windowNumber: window.nativeWindow.windowNumber,
			context: nil,
			characters: key,
			charactersIgnoringModifiers: key,
			isARepeat: false,
			keyCode: 0
		)
	else { return false }
	return window.view.performKeyEquivalent(with: event)
}

@MainActor func nativeMarkedText(_ window: MacOSWindow, _ text: String, _ commit: Bool) -> Bool {
	guard let view = window.nativeWindow.firstResponder as? ContentView, view.editing else { return false }
	if commit {
		view.unmarkText()
	} else {
		view.setMarkedText(
			text,
			selectedRange: NSRange(location: text.utf16.count, length: 0),
			replacementRange: NSRange(location: NSNotFound, length: 0)
		)
	}
	return true
}

@MainActor func nativeTextAction(_ window: MacOSWindow, _ name: String, _ perform: Bool) -> Bool {
	let action = NSSelectorFromString(name)
	let item = NSMenuItem(title: "Test", action: action, keyEquivalent: "")
	guard window.view.validateMenuItem(item) else { return false }
	if perform { NSApp.sendAction(action, to: window.view, from: nil) }
	return true
}

@MainActor func nativeCheckedReplace(
	_ window: MacOSWindow,
	_ text: String,
	_ location: Int,
	_ length: Int,
	_ identity: UInt64,
	_ revision: UInt64
) -> Bool {
	guard let session = window.view.checkingSession, session.isCurrent, session.identity == identity,
		session.revision == revision
	else { return false }
	session.replaceCharacters(
		in: NSRange(location: location, length: length),
		withAnnotatedString: NSAttributedString(string: text)
	)
	return true
}

@MainActor func configureNativeRendering(_ window: MacOSWindow, _ mode: Int, _ delay: Double, _ starved: Bool) {
	window.graphics.configureForTesting(mode: mode, rasterDelay: delay, starved: starved)
}
