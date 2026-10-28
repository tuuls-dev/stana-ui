import Stana

@MainActor struct InstrumentLabel: STNComponent {
	let text: String

	func makeContent(in context: STNComponentContext) -> some STNComponent {
		STNText(
			properties: .init(
				text: text,
				layout: .init(frame: STNFrame(height: 18)),
				textStyle: .init(font: STNFont.system(size: 11, weight: .semibold), foreground: CalculatorPalette.muted)
			)
		)
	}
}

/// Retains a real Stana button for focus/activation, with a centered noninteractive label.
/// Stana's button text is leading-aligned; composition supplies the instrument's key layout.
