import Foundation
import Stana
import StanaTesting
import Testing
@testable import CalculatorApp

@Suite @MainActor struct SessionTests {
	@Test func scalarEvaluationPreservesExpressionAndContinuesWithoutDisplayRounding() {
		let session = CalculatorSession()
		session.expression.value = "1/3"
		session.press(.evaluate)
		#expect(session.expression.value == "1/3")
		#expect(session.answer.value == 1.0 / 3)
		session.press(.insert("*"))
		session.press(.insert("3"))
		session.press(.evaluate)
		#expect(session.answer.value == 1)
		#expect(session.history.value.count == 2)
		session.press(.insert("%"))
		session.press(.evaluate)
		#expect(session.answer.value == 0.01)
	}

	@Test func functionsNeverMasqueradeAsScalarAnswersOrOverwriteMemory() {
		let session = CalculatorSession()
		session.expression.value = "7"
		session.press(.evaluate)
		session.press(.memoryAdd)
		session.expression.value = "1/x"
		session.typed("1/x")
		#expect(session.preview.value == .function)
		session.press(.evaluate)
		#expect(session.answer.value == 7)
		#expect(session.history.value.first?.outcome == .function)
		session.press(.memoryAdd)
		#expect(session.memory.value == 7)
		#expect(session.committedError.value != nil)
	}

	@Test func invalidInputDoesNotDisplayAnOldResultAndRecoveryClearsErrors() {
		let session = CalculatorSession()
		session.expression.value = "2+2"
		session.press(.evaluate)
		session.expression.value = "1/0"
		session.typed("1/0")
		#expect(session.shown.value == "—")
		session.press(.evaluate)
		#expect(session.history.value.count == 1)
		#expect(session.committedError.value != nil)
		session.press(.clear)
		session.press(.insert("5"))
		#expect(session.shown.value == "5")
		#expect(session.committedError.value == nil)
	}

	@Test func recallRestoresAnswerAndAngleContextRatherThanReinterpretingHistory() throws {
		let session = CalculatorSession()
		session.observeAngleMode()
		session.expression.value = "5"
		session.press(.evaluate)
		session.expression.value = "ans+2"
		session.typed("ans+2")
		session.press(.evaluate)
		let entry = try #require(session.history.value.first)
		session.expression.value = "99"
		session.typed("99")
		session.press(.evaluate)
		session.degrees.value = true
		session.recall(entry)
		#expect(session.preview.value == .scalar(7))
		#expect(!session.degrees.value)
		#expect(entry.exportLine.contains("ans=5.0"))
	}

	@Test func historyIsBoundedAndMemoryOverflowDoesNotCorruptState() {
		let session = CalculatorSession()
		for number in 0..<45 {
			session.expression.value = String(number)
			session.typed(String(number))
			session.press(.evaluate)
		}
		#expect(session.history.value.count == 40)
		#expect(Set(session.history.value.map(\.id)).count == 40)
		session.expression.value = "1e308"
		session.typed("1e308")
		session.press(.memoryAdd)
		session.press(.memoryAdd)
		#expect(session.memory.value == 1e308)
		#expect(session.committedError.value != nil)
	}

	@Test func keypadRespectsSelectionCaretAndUnicodeDeletion() throws {
		let session = CalculatorSession()
		let host = STNTestHost(size: .init(width: 1080, height: 780))
		host.mount { CalculatorView(session: session, showFunctions: {}) }
		defer {
			host.close()
		}

		let editor = try #require(host.nodes.first { $0.kind == "textField" && $0.text == "sin(x)" })
		try host.focus(editor.id)
		try host.select(NSRange(location: 0, length: 3))
		session.press(.insert("cos"))
		host.flush()
		#expect(session.expression.value == "cos(x)")
		#expect(host.editorState(editor.id)?.selection.location == 3)
		session.press(.backspace)
		host.flush()
		#expect(session.expression.value == "co(x)")
		session.press(.clear)
		session.paste("π+2")
		host.flush()
		try host.select(NSRange(location: 1, length: 0))
		session.press(.backspace)
		host.flush()
		#expect(session.expression.value == "+2")
	}

	@Test func animationStopsForReducedMotionAndHiddenGraphs() {
		let session = CalculatorSession()
		let host = STNTestHost(size: .init(width: 1080, height: 780))
		host.environment.reducedMotion.value = true
		session.animate.value = true
		host.mount { CalculatorView(session: session, showFunctions: {}) }
		defer {
			host.close()
		}

		host.advanceFrame(timestamp: 0, targetTimestamp: 1)
		#expect(session.time.value == 0)
		host.environment.reducedMotion.value = false
		host.advanceFrame(timestamp: 1, targetTimestamp: 2)
		host.advanceFrame(timestamp: 2, targetTimestamp: 3)
		#expect(session.time.value > 0)
		#expect(session.sampleX.value != "0")
		#expect(session.expression.value == "sin(x)")
		session.toggleGraph()
		let paused = session.time.value
		let pausedSample = session.sampleX.value
		host.advanceFrame(timestamp: 3, targetTimestamp: 4)
		#expect(session.time.value == paused)
		#expect(session.sampleX.value == pausedSample)
	}

	@Test func noOpDeleteDoesNotMoveTheNextTypedCaret() throws {
		let session = CalculatorSession()
		let host = STNTestHost()
		host.mount { CalculatorView(session: session, showFunctions: {}) }
		defer {
			host.close()
		}

		session.press(.clear)
		session.press(.backspace)
		host.insertText("12")
		let field = try #require(host.nodes.first { $0.kind == "textField" && $0.text == "12" })
		#expect(host.editorState(field.id)?.selection.location == 2)
	}

	@Test func essentialKeysAndPanelsAreAccessibleAndLayoutFits() throws {
		for size in [
			STNSize(width: 980, height: 720), .init(width: 1080, height: 780), .init(width: 1440, height: 900),
		] {
			let session = CalculatorSession()
			session.safeSize.value = size
			let host = STNTestHost(size: size)
			host.mount { CalculatorView(session: session, showFunctions: {}) }
			defer {
				host.close()
			}
			#expect(host.errors.isEmpty)
			let add = try #require(host.semantics.nodes.first { $0.label == "Add" })
			let plus = try #require(host.nodes.first { $0.id == add.owner })
			#expect(plus.bounds.size.width >= 44)
			#expect(host.semantics.nodes.contains { $0.label == "Evaluate or record function" })
			session.press(.clear)
			session.press(.insert("2"))
			host.click(
				at: .init(
					x: plus.bounds.minX + plus.bounds.size.width / 2,
					y: plus.bounds.minY + plus.bounds.size.height / 2
				)
			)
			#expect(session.expression.value == "2+")
			#expect(host.nodes.contains { $0.text == "02 / CALCULATION TAPE" })
			let canvas = try #require(host.nodes.first { $0.kind == "gpuCanvas" })
			#expect(canvas.bounds.maxX <= size.width)
			#expect(canvas.bounds.maxY <= size.height)
			let tape = try #require(host.semantics.nodes.first { $0.label == "Calculation tape" })
			#expect(tape.bounds.maxY <= size.height - 24)
			session.toggleGraph()
			host.flush()
			#expect(!host.nodes.contains { $0.kind == "gpuCanvas" })
			#expect(host.nodes.contains { $0.text == "02 / CALCULATION TAPE" })
		}
	}
}
