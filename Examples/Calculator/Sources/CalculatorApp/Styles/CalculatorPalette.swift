import Stana

enum CalculatorPalette {
	static let window = STNColor(red: 0.075, green: 0.082, blue: 0.086)
	static let panel = STNColor(red: 0.115, green: 0.125, blue: 0.13)
	static let ink = STNColor(red: 0.94, green: 0.93, blue: 0.87)
	static let muted = STNColor(red: 0.64, green: 0.68, blue: 0.66)
	static let field = STNColor(red: 0.065, green: 0.075, blue: 0.075)
	static let curve = STNColor(red: 0.59, green: 0.88, blue: 0.72)
	static let amber = STNColor(red: 0.96, green: 0.72, blue: 0.36)
	static let plot = STNColor(red: 0.08, green: 0.10, blue: 0.10)
	static let grid = STNColor(red: 1, green: 1, blue: 1, alpha: 0.07)
	static let axis = STNColor(red: 1, green: 1, blue: 1, alpha: 0.28)
	static let error = STNColor(red: 1, green: 0.57, blue: 0.46)
	static let line = STNColor(red: 1, green: 1, blue: 1, alpha: 0.12)
	static let theme = STNTheme(
		background: window,
		surface: .clear,
		text: ink,
		secondaryText: muted,
		accent: amber,
		border: line
	)

	@MainActor static func environment() -> STNEnvironment {
		let environment = STNEnvironment()
		environment.theme.value = theme
		environment.isDark.value = true
		return environment
	}
}

/// A borderless-looking native window that deliberately keeps the real system controls.
/// A truly borderless NSWindow cannot host native traffic lights.
