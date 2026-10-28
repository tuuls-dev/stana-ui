import Stana

@MainActor struct InstrumentKey: STNComponent {
	let title: STNComputed<String>
	let hint: String
	let width: Double
	let height: Double
	let fontSize: Double
	let fill: STNComputed<STNColor>
	let foreground: STNComputed<STNColor>
	let action: @MainActor () -> Void

	func makeContent(in context: STNComponentContext) -> some STNComponent {
		STNZStack(properties: .init(layout: .init(frame: STNFrame(width: width, height: height)))) {
			STNButton(
				properties: .init(
					text: "",
					layout: .init(padding: STNInsets(0), frame: STNFrame(width: width, height: height)),
					appearance: .init(
						background: fill,
						borderColor: context.environment.highContrast.map {
							$0 ? CalculatorPalette.ink : CalculatorPalette.line
						},
						borderWidth: 1,
						cornerRadius: 6
					),
					accessibility: .init(label: hint),
					onActivate: action
				)
			)
			STNText(
				properties: .init(
					text: title,
					layout: .init(frame: STNFrame(height: fontSize * 1.5)),
					textStyle: .init(font: STNFont.system(size: fontSize, weight: .medium), foreground: foreground),
					interaction: .init(inert: true),
					accessibility: .init(label: "")
				)
			)
		}
	}
}
