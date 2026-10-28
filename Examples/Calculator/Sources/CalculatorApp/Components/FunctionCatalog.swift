import Foundation
import Stana

@MainActor struct FunctionCatalog: STNComponent {
	let session: CalculatorSession
	let close: @MainActor () -> Void

	func makeContent(in context: STNComponentContext) -> some STNComponent {
		let search = context.state(initial: "")
		let page = context.state(initial: 0)
		let matches = search.map { query in
			CalculatorMath.functions.filter {
				query.isEmpty || ($0.name + " " + $0.title + " " + $0.category).localizedCaseInsensitiveContains(query)
			}
		}
		let pageCount = matches.map { max(1, ($0.count + 2) / 3) }
		let visible = STNComputed {
			let all = matches.value
			let index = min(page.value, pageCount.value - 1)
			return Array(all.dropFirst(index * 3).prefix(3))
		}
		STNVStack(
			properties: .init(
				spacing: 12,
				layout: .init(padding: STNInsets(24)),
				appearance: .init(
					background: CalculatorPalette.panel,
					borderColor: CalculatorPalette.line,
					borderWidth: 1,
					cornerRadius: 12
				),
				accessibility: .init(label: "Function library", group: true)
			)
		) {
			STNHStack {
				STNText(
					properties: .init(
						text: "Function library",
						textStyle: .init(
							font: STNFont.system(size: 22, weight: .semibold),
							foreground: CalculatorPalette.ink
						),
						accessibility: .init(heading: 1)
					)
				)
				STNSpacer()
				InstrumentButton(title: "Done", action: close)
			}
			STNText(
				properties: .init(
					text:
						"Choose a function to insert at the cursor. Examples use radians. Two-argument functions need a comma.",
					layout: .init(frame: STNFrame(width: 512)),
					textStyle: .init(font: STNFont.system(size: 12), foreground: CalculatorPalette.muted)
				)
			)
			STNTextField(
				properties: .init(
					value: search.binding,
					placeholder: "Search name, purpose, or category",
					layout: .init(frame: STNFrame(width: 512, height: 36)),
					textStyle: .init(foreground: CalculatorPalette.ink),
					appearance: .init(background: CalculatorPalette.field),
					accessibility: .init(label: "Search functions"),
					onEditorMount: { try? $0.requestFocus() },
					onChange: { _ in page.value = 0 }
				)
			)
			STNBox(properties: .init(layout: .init(frame: STNFrame(width: 512, height: 284)))) {
				STNVStack(properties: .init(spacing: 10)) {
					STNIf(matches.map(\.isEmpty)) {
						STNText(
							properties: .init(
								text: "No matching functions. Try a name such as sqrt.",
								textStyle: .init(foreground: CalculatorPalette.muted)
							)
						)
					}
					STNForEach(visible, id: \.name) { function in
						STNHStack(
							properties: .init(
								spacing: 12,
								layout: .init(padding: STNInsets(12), frame: STNFrame(width: 500)),
								appearance: .init(background: CalculatorPalette.panel, cornerRadius: 8)
							)
						) {
							STNVStack(properties: .init(spacing: 4, layout: .init(frame: STNFrame(width: 360)))) {
								InstrumentLabel(text: function.category.uppercased())
								STNText(
									properties: .init(
										text: function.title,
										textStyle: .init(
											font: STNFont.system(size: 14, weight: .medium),
											foreground: CalculatorPalette.ink
										)
									)
								)
								STNText(
									properties: .init(
										text: function.example,
										textStyle: .init(
											font: STNFont.system(size: 12),
											foreground: CalculatorPalette.curve
										)
									)
								)
							}
							InstrumentButton(title: "Insert", hint: "Insert \(function.name)", width: 80) {
								close()
								session.press(.insert(function.name + "("))
							}
						}
					}
				}
			}
			STNHStack(properties: .init(spacing: 12)) {
				STNButton(
					properties: .init(
						text: "Previous",
						layout: .init(frame: STNFrame(width: 90, height: 30)),
						textStyle: .init(foreground: CalculatorPalette.ink),
						interaction: .init(isEnabled: page.map { $0 > 0 }),
						onActivate: { page.value = max(0, page.value - 1) }
					)
				)
				STNText(
					properties: .init(
						text: STNComputed {
							"Page \(min(page.value, pageCount.value - 1) + 1) of \(pageCount.value) · \(matches.value.count) functions"
						},
						layout: .init(frame: STNFrame(height: 18)),
						textStyle: .init(font: STNFont.system(size: 12), foreground: CalculatorPalette.muted)
					)
				)
				STNSpacer()
				STNButton(
					properties: .init(
						text: "Next",
						layout: .init(frame: STNFrame(width: 70, height: 30)),
						textStyle: .init(foreground: CalculatorPalette.ink),
						interaction: .init(isEnabled: STNComputed { page.value < pageCount.value - 1 }),
						onActivate: { page.value = min(pageCount.value - 1, page.value + 1) }
					)
				)
			}
		}
	}
}
