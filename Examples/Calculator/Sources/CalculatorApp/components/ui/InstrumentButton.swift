import Stana

@MainActor struct InstrumentButton: STNComponent {
	let title: String
	var hint: String? = nil
	var width = 68.0
	var height = 32.0
	var emphasis = false
	var selected: STNSignal<Bool>? = nil
	let action: @MainActor () -> Void

	func makeContent(in context: STNComponentContext) -> some STNComponent {
		InstrumentKey(
			title: STNComputed { title },
			hint: hint ?? title,
			width: width,
			height: height,
			fontSize: 12,
			fill: STNComputed { (selected?.value ?? emphasis) ? CalculatorPalette.amber : CalculatorPalette.panel },
			foreground: STNComputed {
				(selected?.value ?? emphasis) ? CalculatorPalette.window : CalculatorPalette.ink
			},
			action: action
		)
	}
}
