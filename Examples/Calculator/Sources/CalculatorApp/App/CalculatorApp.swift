import Foundation
import Stana

@MainActor final class CalculatorWindows {
	var main: STNWindow?
}

@main struct CalculatorApp {
	@MainActor static func main() throws {
		let session = CalculatorSession()
		session.observeAngleMode()
		if CommandLine.arguments.contains("--self-check") {
			// Compatibility entry point; comprehensive regression coverage lives in CalculatorTests.
			session.expression.value = "2+2"
			session.press(.evaluate)
			guard session.answer.value == 4 else {
				throw CalculatorMath.Failure.unexpected("the calculator self-check")
			}
			print("Calculator checks passed")
			return
		}

		let windows = CalculatorWindows()
		let commands = CalculatorCommands.make(session: session, windows: windows)

		let arguments = CommandLine.arguments
		let initialSize =
			arguments.contains("--compact")
			? STNSize(width: 980, height: 720)
			: arguments.contains("--wide") ? STNSize(width: 1440, height: 900) : STNSize(width: 1080, height: 780)
		let window = STNWindow(
			properties: .init(
				title: "Calculator",
				size: initialSize,
				environment: CalculatorPalette.environment(),
				configuration: CalculatorWindowStyle.configuration(
					autosave: !arguments.contains("--capture") && !arguments.contains("--smoke-test")
				),
				onConfigurationError: { fputs("Window configuration: \($0)\n", stderr) }
			)
		) {
			CalculatorView(session: session, showFunctions: { commands.functions.perform() })
		}

		windows.main = window
		session.windowSize = window.state.map { state in
			state.safeContentBounds.size.width > 0 ? state.safeContentBounds.size : initialSize
		}

		let windowCommands = CalculatorCommands.windowCommands(session: session, window: window)
		CalculatorNativeChecks.schedule(arguments: arguments, session: session, window: window)
		CalculatorMenus.run(window: window, commands: commands, windowCommands: windowCommands)
	}
}
