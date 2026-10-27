import Stana

@MainActor func windowConfigurationFixtures() async throws {
	let title = STNSignal("Portable window")
	let configuration = STNSignal(
		STNWindow.Configuration(
			creation: .init(role: .panel, initiallyVisible: false),
			appearance: .init(frame: .frameless, background: .clear),
			resizing: .init(minimumContentSize: .init(width: 320, height: 240)),
			interaction: .init(canBecomeMain: .disabled),
			workspaces: .init(spaces: .all, fullscreen: .auxiliary)
		)
	)
	let window = STNWindow(properties: .init(title: title, configuration: configuration)) {
		STNWindowContent {
			STNWindowDragRegion {
				STNText(properties: .init(text: "Header"))
				STNWindowDragRegion(properties: .init(mode: .exclude)) {
					STNButton(properties: .init(text: "Action", onActivate: {}))
				}
			}
			STNWindowResizeRegion(properties: .init(edges: [.bottom, .trailing])) {}
		}
	}
	let _ = STNWindow(properties: .init(title: "Constant", configuration: configuration.map { $0 })) {}
	let _ = STNWindow(properties: .init(title: title.map { $0 }, configuration: .init())) {}
	let state: STNComputed<STNWindowState> = window.state
	let resolution: STNComputed<STNWindowResolution> = window.resolution
	let _ = state.value.safeContentBounds
	let _ = resolution.value.ignored
	let _: [STNScreen] = STNApplication.screens
	try window.setContentSize(.init(width: 800, height: 600))
	try await window.setFullscreen(true)
}
