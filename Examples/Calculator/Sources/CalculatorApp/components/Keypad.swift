import Stana

@MainActor struct Keypad: STNComponent {
	let session: CalculatorSession
	let showFunctions: @MainActor () -> Void

	func makeContent(in context: STNComponentContext) -> some STNComponent {
		STNVStack(properties: .init(spacing: 12)) {
			STNHStack(properties: .init(spacing: 8)) {
				InstrumentLabel(text: "SCIENTIFIC")
				STNSpacer()
				InstrumentButton(title: "Functions…", width: 96, height: 26, action: showFunctions)
			}
			STNVStack(properties: .init(spacing: 6)) {
				for row in KeypadModel.scientific {
					STNHStack(properties: .init(spacing: 8)) {
						for key in row {
							keyButton(key, height: 28, scientific: true)
						}
					}
				}
			}
			STNBackdrop(
				properties: .init(
					effect: STNBackdropEffect.blur(radius: 8),
					layout: .init(frame: STNFrame(width: 300)),
					appearance: .init(background: CalculatorPalette.panel, cornerRadius: 8)
				)
			) {
				STNVStack(properties: .init(spacing: 6)) {
					for row in KeypadModel.arithmetic {
						STNHStack(properties: .init(spacing: 8)) {
							for key in row {
								keyButton(key, height: 40, scientific: false)
							}
						}
					}
				}
			}
		}
	}

	private func keyButton(_ key: KeySpec, height: Double, scientific: Bool)
		-> some STNComponent
	{
		let primary = key.action == .evaluate
		let operation = ["÷", "×", "−", "+"].contains(key.title)
		let fill =
			primary
			? CalculatorPalette.amber
			: operation ? STNColor(red: 0.22, green: 0.28, blue: 0.25) : CalculatorPalette.panel
		return InstrumentKey(
			title: primary ? session.actionTitle : STNComputed { key.title },
			hint: key.hint,
			width: 69,
			height: height,
			fontSize: scientific ? 14 : 20,
			fill: STNComputed { fill },
			foreground: STNComputed {
				primary ? CalculatorPalette.window : operation ? CalculatorPalette.curve : CalculatorPalette.ink
			},
			action: { session.press(key.action) }
		)
	}
}
