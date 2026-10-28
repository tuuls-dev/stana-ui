import Foundation
import Stana

@MainActor struct HistoryPanel: STNComponent {
	let session: CalculatorSession

	func makeContent(in context: STNComponentContext) -> some STNComponent {
		STNVStack(
			properties: .init(
				spacing: 10,
				layout: .init(
					padding: STNInsets(16),
					frame: session.geometry.map { STNFrame(width: $0.workspaceWidth, height: $0.tapeHeight) }
				),
				appearance: .init(
					background: CalculatorPalette.panel,
					borderColor: CalculatorPalette.line,
					borderWidth: 1,
					cornerRadius: 12
				),
				accessibility: .init(label: "Calculation tape", group: true)
			)
		) {
			STNHStack(properties: .init(spacing: 8)) {
				InstrumentLabel(text: "02 / CALCULATION TAPE")
				STNSpacer()
				STNText(
					properties: .init(
						text: session.history.map { "\($0.count) / 40" },
						layout: .init(frame: STNFrame(height: 18)),
						textStyle: .init(font: STNFont.system(size: 11), foreground: CalculatorPalette.muted)
					)
				)
			}
			STNScrollView(
				properties: .init(
					layout: .init(
						frame: session.geometry.map {
							STNFrame(width: $0.workspaceWidth - 32, height: $0.tapeHeight - 58)
						}
					)
				)
			) {
				STNVStack(properties: .init(spacing: 8)) {
					STNIf(session.history.map(\.isEmpty)) {
						STNVStack(properties: .init(spacing: 6)) {
							STNText(
								properties: .init(
									text: "Keep a trail of your thinking.",
									textStyle: .init(
										font: STNFont.system(size: 15, weight: .medium),
										foreground: CalculatorPalette.ink
									)
								)
							)
							STNText(
								properties: .init(
									text:
										"Enter records a calculation or function here. Recall it later without losing its original context.",
									layout: .init(
										frame: session.geometry.map { STNFrame(width: $0.workspaceWidth - 56) }
									),
									textStyle: .init(
										font: STNFont.system(size: 12),
										foreground: CalculatorPalette.muted
									)
								)
							)
						}
					} else: {
						STNForEach(session.history, id: \.id) { entry in
							STNHStack(
								properties: .init(
									spacing: 8,
									layout: .init(
										padding: STNInsets(8),
										frame: session.geometry.map { STNFrame(width: $0.workspaceWidth - 32) }
									),
									appearance: .init(background: CalculatorPalette.field, cornerRadius: 6)
								)
							) {
								STNVStack(
									properties: .init(
										spacing: 4,
										layout: .init(
											frame: session.geometry.map { STNFrame(width: $0.workspaceWidth - 205) }
										)
									)
								) {
									STNText(
										properties: .init(
											text: entry.expression,
											textStyle: .init(
												font: STNFont.system(size: 12),
												foreground: CalculatorPalette.ink
											)
										)
									)
									STNText(
										properties: .init(
											text: entry.result + "  ·  " + (entry.context.degrees ? "DEG" : "RAD"),
											textStyle: .init(
												font: STNFont.system(size: 12),
												foreground: CalculatorPalette.curve
											)
										)
									)
								}
								InstrumentButton(
									title: "Recall",
									hint: "Recall \(entry.expression)",
									width: 60,
									height: 28
								) { session.recall(entry) }
								InstrumentButton(
									title: "Copy",
									hint: "Copy result of \(entry.expression)",
									width: 52,
									height: 28
								) {
									let text =
										switch entry.outcome {
										case .number(let value): CalculatorMath.literal(value)
										case .function: entry.expression
										}
									STNClipboard.write(text)
									session.note.value = "Copied tape entry."
								}
							}
						}
					}
				}
			}
		}
	}
}
