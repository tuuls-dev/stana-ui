import Foundation
import Stana

@MainActor enum CalculatorNativeChecks {
	static func schedule(arguments: [String], session: CalculatorSession, window: STNWindow) {
		if arguments.contains("--smoke-test") || arguments.contains("--capture") {
			Task { @MainActor in
				do {
					try await Task.sleep(for: .milliseconds(700))
					if arguments.contains("--smoke-test") {
						session.expression.value = "2+2"
						session.press(.evaluate)
						precondition(session.answer.value == 4 && window.isOpen)
						print("Calculator smoke: window opened and evaluated")
					}

					if let index = arguments.firstIndex(of: "--capture"), index + 1 < arguments.count {
						let image = try await window.capture()
						try PNGImage.encodeBGRA(
							width: image.width,
							height: image.height,
							bytes: image.displayMappedBGRA()
						)
						.write(to: URL(fileURLWithPath: arguments[index + 1]))
						print("Calculator captured \(image.width) × \(image.height)")
					}
				} catch {
					fputs("Calculator native check failed: \(error)\n", stderr)
					exit(EXIT_FAILURE)
				}

				STNApplication.stop()
			}
		}
	}
}
