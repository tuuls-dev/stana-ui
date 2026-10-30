import Foundation
import QuartzCore
import StanaPrimitives
import Synchronization
import Testing

@testable import StanaPlatformMacOS

private final class DrawableWaitState: Sendable {
	let value = Mutex((ready: false, finished: false))
}

extension NativeWindowServer {
	@Suite(.serialized)
	@MainActor struct NativeSchedulingTests {
		@Test func blockedDrawableAcquisitionDoesNotHoldTheUIConfigurationLock() async throws {
			let device = try #require(MetalDevice.shared)
			let window = try MacOSWindow(title: "Drawable wait", size: .init(width: 32, height: 32))
			defer { window.close() }
			let layer = MetalLayer()
			layer.install(in: window.view, device: device.device, opaque: true)
			layer.configure(
				bounds: .init(x: 0, y: 0, width: 32, height: 32),
				size: .init(width: 64, height: 64),
				scale: 2,
				opaque: true,
				extended: false
			)
			let state = DrawableWaitState()
			let release = DispatchSemaphore(value: 0)
			defer { release.signal() }
			let acquisition = Task.detached {
				// Block deterministically; the test helper may not own a physical drawable pool.
				_ = layer.nextDrawable { _ in
					state.value.withLock { $0.ready = true }
					_ = release.wait(timeout: .now() + 2)
					state.value.withLock { $0.finished = true }
					return nil
				}
			}

			for _ in 0..<100 {
				if state.value.withLock({ $0.ready }) {
					break
				}

				try await Task.sleep(for: .milliseconds(10))
			}

			try #require(state.value.withLock { $0.ready })
			try await Task.sleep(for: .milliseconds(30))
			try #require(!state.value.withLock { $0.finished }, "The acquisition must still be blocked")
			let start = ContinuousClock.now
			layer.configure(
				bounds: .init(x: 0, y: 0, width: 32, height: 32),
				size: .init(width: 64, height: 64),
				scale: 2,
				opaque: true,
				extended: false
			)
			#expect(start.duration(to: .now) < .milliseconds(250))
			release.signal()
			await acquisition.value
		}
	}
}
