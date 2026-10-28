import Stana
import StanaTesting
import Testing
@testable import CalculatorApp

@Suite @MainActor struct WindowStyleTests {
	@Test func framelessAppearanceRetainsNativeTrafficLightsWithoutToolbarChrome() throws {
		let window = STNWindow(
			properties: .init(title: "Calculator", configuration: CalculatorWindowStyle.configuration(autosave: false))
		) {
			STNText(properties: .init(text: "Calculator"))
		}

		let host = try STNWindowTestHost(window: window)
		defer {
			host.close()
		}

		let applied = try #require(window.appliedConfiguration.value)
		#expect(applied.appearance.frame == .system)
		#expect(applied.titleBar.titleVisibility == .disabled)
		#expect(applied.titleBar.transparent == .enabled)
		#expect(applied.titleBar.fullSizeContent == .enabled)
		#expect(applied.titleBar.closeButton.visibility == .enabled)
		#expect(applied.titleBar.minimizeButton.visibility == .enabled)
		#expect(applied.titleBar.zoomButton.visibility == .enabled)
		#expect(host.toolbarTitles.isEmpty)
		#expect(host.chromeSurfaceCount == 0)
	}
}
