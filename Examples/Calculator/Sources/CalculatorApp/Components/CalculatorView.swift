import Foundation
import Stana

@MainActor struct CalculatorView: STNComponent {
	let session: CalculatorSession
	let showFunctions: @MainActor () -> Void

	func makeContent(in context: STNComponentContext) -> some STNComponent {
		STNWindowContent {
			STNVStack(
				properties: .init(
					spacing: 16,
					layout: .init(padding: STNInsets(24), frame: STNFrame(maxWidth: .infinity, maxHeight: .infinity))
				)
			) {
				STNWindowDragRegion(properties: .init(frame: .init(height: 36, maxWidth: .infinity))) {
					STNHStack(properties: .init(spacing: 12)) {
						STNText(
							properties: .init(
								text: "Calculator",
								textStyle: .init(
									font: STNFont.system(size: 24, weight: .semibold),
									foreground: CalculatorPalette.ink
								),
								accessibility: .init(heading: 1)
							)
						)
						STNSpacer()
						STNText(
							properties: .init(
								text: session.memoryLabel,
								layout: .init(frame: STNFrame(width: 140, height: 18)),
								textStyle: .init(font: STNFont.system(size: 11), foreground: CalculatorPalette.muted),
								accessibility: .init(label: session.memoryLabel.map { "Stored memory: " + $0 })
							)
						)
						InstrumentButton(title: "Plot", width: 62, selected: session.graphVisible) {
							session.toggleGraph()
						}
						InstrumentButton(title: "Tape", width: 62, selected: session.tapeVisible) {
							if !session.graphVisible.value {
								session.graphVisible.value = true
							}

							session.tapeVisible.value.toggle()
						}
					}
				}
				STNHStack(
					properties: .init(
						spacing: 20,
						layout: .init(frame: session.geometry.map { STNFrame(height: $0.contentHeight) })
					)
				) {
					console
					STNVStack(
						properties: .init(
							spacing: 16,
							layout: .init(
								frame: session.geometry.map {
									STNFrame(width: $0.workspaceWidth, height: $0.contentHeight)
								}
							)
						)
					) {
						STNIf(session.libraryVisible) {
							FunctionCatalog(session: session, close: { session.closeLibrary() })
						} else: {
							STNIf(session.graphVisible) { GraphPanel(session: session) }
							STNIf(STNComputed { session.tapeVisible.value || !session.graphVisible.value }) {
								HistoryPanel(session: session)
							}
						}
					}
				}
			}
		}
	}

	private var console: some STNComponent {
		STNScrollView(
			properties: .init(
				layout: .init(
					frame: session.geometry.map {
						STNFrame(width: CalculatorGeometry.consoleWidth, height: $0.contentHeight)
					}
				),
				appearance: .init(
					background: CalculatorPalette.panel,
					borderColor: CalculatorPalette.line,
					borderWidth: 1,
					cornerRadius: 12
				),
				accessibility: .init(label: "Calculation console", group: true)
			)
		) {
			STNVStack(properties: .init(spacing: 8, layout: .init(padding: STNInsets(20)))) {
				STNHStack(properties: .init(spacing: 8)) {
					InstrumentLabel(text: "EXPRESSION")
					STNSpacer()
					STNToggle(
						properties: .init(
							text: "Degrees",
							isOn: session.degrees.binding,
							textStyle: .init(font: STNFont.system(size: 11), foreground: CalculatorPalette.ink),
							accessibility: .init(label: "Use degrees instead of radians")
						)
					)
				}
				STNFocusScope {
					STNTextField(
						properties: .init(
							value: session.expression.binding,
							placeholder: "e.g. 2 * (3 + 4)",
							options: fieldOptions,
							layout: .init(frame: STNFrame(width: 300, height: 38)),
							textStyle: .init(font: STNFont.system(size: 18), foreground: CalculatorPalette.ink),
							appearance: .init(
								background: CalculatorPalette.field,
								borderColor: CalculatorPalette.line,
								borderWidth: 1,
								cornerRadius: 6
							),
							accessibility: .init(label: "Expression"),
							onEditorMount: { session.editor = $0 },
							onChange: { session.typed($0) },
							onSelectionChange: { session.selectionChanged($0) },
							onSubmit: { session.press(.evaluate) }
						)
					)
				}
				STNText(
					properties: .init(
						text: session.shown,
						layout: .init(frame: STNFrame(width: 300, height: 48)),
						textStyle: .init(
							font: session.shown.map {
								STNFont.system(size: min(36, 400 / Double(max(1, $0.count))), weight: .medium)
							},
							foreground: CalculatorPalette.ink
						),
						accessibility: .init(label: session.shown.map { "Result: " + $0 })
					)
				)
				STNText(
					properties: .init(
						text: session.banner,
						layout: .init(frame: STNFrame(width: 300, height: 28)),
						textStyle: .init(font: STNFont.system(size: 11), foreground: session.bannerColor)
					)
				)
				STNHStack(properties: .init(spacing: 8)) {
					InstrumentButton(title: "x", hint: "Insert graph variable x", width: 69, height: 26) {
						session.press(.insert("x"))
					}
					InstrumentButton(title: "t", hint: "Insert time variable t", width: 69, height: 26) {
						session.press(.insert("t"))
					}
					InstrumentButton(title: "ans", hint: "Insert previous scalar answer", width: 69, height: 26) {
						session.press(.answer)
					}
					InstrumentButton(title: "e", hint: "Insert Euler’s number", width: 69, height: 26) {
						session.press(.insert("e"))
					}
				}
				Keypad(session: session, showFunctions: showFunctions)
				STNHStack(properties: .init(spacing: 8)) {
					InstrumentButton(title: "MC", hint: "Clear memory", width: 69, height: 26) {
						session.press(.memoryClear)
					}
					InstrumentButton(title: "MR", hint: "Recall memory", width: 69, height: 26) {
						session.press(.memoryRecall)
					}
					InstrumentButton(title: "M+", hint: "Add result to memory", width: 69, height: 26) {
						session.press(.memoryAdd)
					}
					InstrumentButton(title: "M−", hint: "Subtract result from memory", width: 69, height: 26) {
						session.press(.memorySubtract)
					}
				}
				SymbolDemo()
			}
		}
	}

	private var fieldOptions: STNTextField.Options {
		.init(
			alignment: .leading,
			placeholderColor: CalculatorPalette.muted,
			selectionColor: CalculatorPalette.theme.accent,
			caretColor: CalculatorPalette.ink,
			textServices: .init(
				spelling: .disabled,
				grammar: .disabled,
				correction: .disabled,
				smartQuotes: .disabled,
				smartDashes: .disabled,
				textReplacement: .disabled,
				completion: .disabled
			)
		)
	}
}
