import Stana

@MainActor enum CalculatorWindowStyle {
	static func configuration(autosave: Bool) -> STNWindow.Configuration {
		STNWindow.Configuration(
			creation: .init(
				identifier: "calculator",
				frameAutosaveName: autosave ? "CalculatorInstrumentFrameless" : nil
			),
			appearance: .init(
				frame: .system,
				background: CalculatorPalette.window,
				shadow: .enabled,
				preference: .dark
			),
			titleBar: .init(
				titleVisibility: .disabled,
				transparent: .enabled,
				fullSizeContent: .enabled,
				separator: .none,
				closeButton: .init(visibility: .enabled, enabled: .enabled),
				minimizeButton: .init(visibility: .enabled, enabled: .enabled),
				zoomButton: .init(visibility: .enabled, enabled: .enabled)
			),
			resizing: .init(minimumContentSize: .init(width: 980, height: 720))
		)
	}
}
