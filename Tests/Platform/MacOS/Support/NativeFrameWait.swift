import StanaPrimitives

@testable import StanaPlatformMacOS

@MainActor func waitForNativeBacking(_ window: MacOSWindow, after revision: UInt64 = 0) async throws {
	for _ in 0..<400 {
		if window.renderer.backingRevision > revision { return }
		try await Task.sleep(for: .milliseconds(10))
	}
	throw STNError.nativeFailure("Timed out waiting for asynchronous offscreen rendering")
}
