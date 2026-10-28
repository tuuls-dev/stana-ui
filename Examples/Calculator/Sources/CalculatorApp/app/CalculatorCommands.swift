import Foundation
import Stana

@MainActor enum CalculatorCommands {
	static func make(session: CalculatorSession, windows: CalculatorWindows) -> (
		functions: STNCommand, evaluate: STNCommand, clear: STNCommand, copy: STNCommand, paste: STNCommand,
		graph: STNCommand, tape: STNCommand, degrees: STNCommand, save: STNCommand
	) {
		let functions = STNCommand(
			properties: .init(title: "Functions…", shortcut: .init("f", modifiers: [.primary, .shift])) {
				session.libraryVisible.value = true
			}
		)

		let evaluate = STNCommand(
			properties: .init(title: "Record Expression", shortcut: .init("\r")) {
				session.press(.evaluate)
			}
		)
		let clear = STNCommand(
			properties: .init(title: "Clear Expression", shortcut: .init("k")) { session.press(.clear) }
		)
		let copy = STNCommand(
			properties: .init(title: "Copy Result", shortcut: .init("c", modifiers: [.primary, .shift])) {
				guard case .scalar(let value) = session.preview.value else {
					session.note.value = "Evaluate a numerical expression before copying a result."
					return
				}

				STNClipboard.write(CalculatorMath.literal(value))
				session.note.value = "Copied numerical result at full precision."
			}
		)
		let paste = STNCommand(
			properties: .init(title: "Paste into Expression", shortcut: .init("v", modifiers: [.primary, .shift])) {
				guard let text = STNClipboard.readText(), !text.isEmpty else {
					session.note.value = "The clipboard has no text."
					return
				}

				session.paste(text)
			}
		)
		let graph = STNCommand(
			properties: .init(title: "Show Plot", shortcut: .init("g"), isChecked: session.graphVisible) {
				session.toggleGraph()
			}
		)
		let tape = STNCommand(
			properties: .init(
				title: "Show Tape",
				shortcut: .init("h", modifiers: [.primary, .shift]),
				isChecked: session.tapeVisible
			) {
				if !session.graphVisible.value {
					session.graphVisible.value = true
				}

				session.tapeVisible.value.toggle()
			}
		)
		let degrees = STNCommand(
			properties: .init(title: "Use Degrees", isChecked: session.degrees) { session.degrees.value.toggle() }
		)
		let save = STNCommand(
			properties: .init(
				title: "Export Tape…",
				shortcut: .init("s"),
				isEnabled: session.history.map { !$0.isEmpty }
			) {
				let text = session.history.value.reversed().map(\.exportLine).joined(separator: "\n")
				Task { @MainActor in
					guard let url = await STNFileDialog.save(suggestedName: "calculator-tape.txt", in: windows.main)
					else {
						return
					}

					do {
						try await Task.detached { try Data(text.utf8).write(to: url, options: .atomic) }.value
						session.note.value = "Tape exported."
					} catch {
						await STNAlert.show(
							title: "Export failed",
							message: "Choose another destination and try again.",
							in: windows.main
						)
					}
				}
			}
		)

		return (functions, evaluate, clear, copy, paste, graph, tape, degrees, save)
	}

	static func windowCommands(session: CalculatorSession, window: STNWindow) -> (
		picture: STNCommand, diagnostics: STNCommand
	) {
		let picture = STNCommand(
			properties: .init(title: "Save Picture…") {
				Task { @MainActor in
					do {
						let image = try await window.capture()
						guard let url = await STNFileDialog.save(suggestedName: "calculator.png", in: window) else {
							return
						}

						let png = PNGImage.encodeBGRA(
							width: image.width,
							height: image.height,
							bytes: image.displayMappedBGRA()
						)
						try await Task.detached { try png.write(to: url, options: .atomic) }.value
						session.note.value = "Picture saved."
					} catch {
						await STNAlert.show(
							title: "Capture failed",
							message:
								"The calculator could not save a picture. Try again after the window finishes drawing.",
							in: window
						)
					}
				}
			}
		)
		let diagnostics = STNCommand(
			properties: .init(title: "Copy Rendering Diagnostics") {
				Task { @MainActor in
					do {
						let report = try await window.renderingDiagnostics()
						STNClipboard.write(
							"device: \(report.device)\ncolor: \(report.workingColorProfile)\nfailure: \(report.lastFailure ?? "none")\nscene: \(report.confirmedSceneRevision.map(String.init) ?? "unconfirmed")"
						)
						session.note.value = "Copied rendering diagnostics."
					} catch { session.note.value = "Diagnostics are not available yet." }
				}
			}
		)
		return (picture, diagnostics)
	}
}
