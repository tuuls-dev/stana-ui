import Foundation
import Stana

struct HistoryEntry: Equatable {
	enum Outcome: Equatable {
		case number(Double)
		case function
	}

	let id: Int
	let expression: String
	let outcome: Outcome
	let context: CalculatorMath.Context

	var result: String {
		switch outcome {
		case .number(let value): CalculatorMath.resultText(value)
		case .function: "Function · t = \(CalculatorMath.format(context.t))"
		}
	}

	var exportLine: String {
		let result =
			switch outcome {
			case .number(let value): CalculatorMath.literal(value)
			case .function: "function of x"
			}
		return
			"\(expression) → \(result) [\(context.degrees ? "deg" : "rad"), ans=\(CalculatorMath.literal(context.answer)), t=\(CalculatorMath.literal(context.t))]"
	}
}

enum KeyAction: Equatable {
	case insert(String)
	case clear
	case backspace
	case negate
	case evaluate
	case memoryClear
	case memoryRecall
	case memoryAdd
	case memorySubtract
	case answer
}

struct PlotSource: Equatable {
	let expression: CalculatorMath.Expression
	let context: CalculatorMath.Context
}

struct GraphViewport: Equatable {
	var xMin = -2 * Double.pi
	var xMax = 2 * Double.pi
	var yMin = -2.0
	var yMax = 2.0

	var isValid: Bool {
		[xMin, xMax, yMin, yMax, xMax - xMin, yMax - yMin].allSatisfy(\.isFinite)
			&& xMax > xMin && yMax > yMin
	}
}

struct CalculatorGeometry: Equatable {
	static let consoleWidth = 340.0
	let size: STNSize
	let tapeVisible: Bool
	let graphVisible: Bool

	var contentHeight: Double {
		max(400, size.height - 100)
	}

	var workspaceWidth: Double {
		max(500, size.width - 48 - Self.consoleWidth - 20)
	}

	var plotWidth: Double {
		workspaceWidth - 32
	}

	var plotHeight: Double {
		max(140, contentHeight - (tapeVisible ? 196 : 0) - 196)
	}

	var tapeHeight: Double {
		graphVisible ? 180 : contentHeight
	}
}

/// Owns calculator transitions. Views consume signals; the math engine has no UI dependency.
@MainActor final class CalculatorSession {
	enum Preview: Equatable {
		case empty
		case invalid(String)
		case scalar(Double)
		case function
	}

	let expression = STNSignal("sin(x)")
	let degrees = STNSignal(false)
	let animate = STNSignal(false)
	let graphVisible = STNSignal(true)
	let libraryVisible = STNSignal(false)
	let tapeVisible = STNSignal(true)
	let memory = STNSignal(0.0)
	let history = STNSignal<[HistoryEntry]>([])
	let committedError = STNSignal<String?>(nil)
	let note = STNSignal<String?>(nil)
	let answer = STNSignal(0.0)
	let time = STNSignal(0.0)
	let sampleX = STNSignal("0")
	let viewport = STNSignal(GraphViewport())
	var windowSize: STNComputed<STNSize>?
	let safeSize = STNSignal(STNSize(width: 1080, height: 724))
	let plotSource: STNSignal<PlotSource>
	var editor: STNTextFieldHandle?
	let fresh = STNSignal(false)
	private var nextHistoryID = 1
	private var pendingCaret: Int?
	private var angleSubscription: STNSubscription?
	private let retainedContext = STNSignal<CalculatorMath.Context?>(nil)

	lazy var parsed = STNComputed<Result<CalculatorMath.Expression, CalculatorMath.Failure>> {
		do {
			return .success(try CalculatorMath.compile(self.expression.value))
		} catch {
			return .failure((error as? CalculatorMath.Failure) ?? .unexpected("the expression"))
		}
	}

	lazy var preview = STNComputed<Preview> {
		if self.expression.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
			return .empty
		}

		switch self.parsed.value {
		case .failure(let failure): return .invalid(failure.description)
		case .success(let compiled):
			if compiled.variables.contains(.x) {
				return .function
			}

			do {
				return .scalar(try compiled.evaluate(in: self.evaluationContext))
			} catch {
				return .invalid(String(describing: error))
			}
		}
	}

	lazy var shown = STNComputed<String> {
		switch self.preview.value {
		case .scalar(let value): CalculatorMath.resultText(value)
		case .function: "ƒ(x)"
		case .empty: "0"
		case .invalid: "—"
		}
	}

	lazy var banner = STNComputed<String> {
		if let error = self.committedError.value {
			return error
		}

		if let note = self.note.value {
			return note
		}

		switch self.preview.value {
		case .empty: return "Type an expression to begin."
		case .invalid(let message): return message
		case .function: return "Function of x · inspect a value in the plot."
		case .scalar:
			return self.fresh.value
				? "Recorded · ready for your next calculation." : "Numerical preview · Enter to record."
		}
	}

	lazy var memoryLabel = memory.map { "M  \(CalculatorMath.format($0))" }
	lazy var actionTitle = preview.map { $0 == .function ? "Plot" : "=" }
	lazy var geometry = STNComputed {
		CalculatorGeometry(
			size: self.windowSize?.value ?? self.safeSize.value,
			tapeVisible: self.tapeVisible.value,
			graphVisible: self.graphVisible.value
		)
	}
	lazy var plotIsCurrent = STNComputed {
		self.expression.value.trimmingCharacters(in: .whitespacesAndNewlines)
			== self.plotSource.value.expression.source.trimmingCharacters(in: .whitespacesAndNewlines)
	}
	lazy var bannerColor = STNComputed {
		self.committedError.value == nil ? CalculatorPalette.muted : CalculatorPalette.error
	}

	init() {
		// A static, known-valid seed. User expressions always follow the fallible parser path.
		plotSource = STNSignal(PlotSource(expression: try! CalculatorMath.compile("sin(x)"), context: .init()))
	}

	var evaluationContext: CalculatorMath.Context {
		var context = retainedContext.value ?? .init(degrees: degrees.value, answer: answer.value, t: time.value)
		context.degrees = degrees.value
		return context
	}

	func observeAngleMode() {
		angleSubscription = degrees.subscribe { [weak self] _ in
			self?.fresh.value = false
			self?.committedError.value = nil
			self?.updatePlot()
		}
	}

	func press(_ action: KeyAction) {
		switch action {
		case .insert(let text): insert(text)
		case .clear:
			fresh.value = false
			retainedContext.value = nil
			replaceAll("")
		case .backspace: backspace()
		case .negate:
			let source = fresh.value ? CalculatorMath.literal(answer.value) : expression.value
			replaceAll(source.isEmpty ? "-" : "-(\(source))")
		case .evaluate: evaluate()
		case .memoryClear:
			memory.value = 0
			committedError.value = nil
			note.value = "Memory cleared."
		case .memoryRecall: insert(CalculatorMath.literal(memory.value))
		case .memoryAdd: addMemory(1)
		case .memorySubtract: addMemory(-1)
		case .answer: insert("ans")
		}
	}

	func typed(_ text: String) {
		let wasFresh = fresh.value
		fresh.value = false
		retainedContext.value = nil
		committedError.value = nil
		note.value = nil
		if wasFresh, isOperator(text) {
			replaceAll(CalculatorMath.literal(answer.value) + text)
			return
		}

		updatePlot()
	}

	func paste(_ text: String) {
		insert(text)
	}

	func recall(_ entry: HistoryEntry) {
		fresh.value = false
		retainedContext.value = entry.context
		STNTransaction.perform {
			degrees.value = entry.context.degrees
			time.value = entry.context.t
			expression.value = entry.expression
			committedError.value = nil
			note.value = "Recalled with its original angle, ans, and time."
		}
		updatePlot()
		try? editor?.requestFocus()
		try? editor?.selectAll()
	}

	func advanceAnimation(elapsed: Double) {
		guard elapsed.isFinite, elapsed >= 0 else {
			return
		}

		let phase = (time.value + elapsed * 0.6).truncatingRemainder(dividingBy: 2 * .pi)
		let v = viewport.value
		STNTransaction.perform {
			time.value = phase
			sampleX.value = String(
				format: "%.5g",
				locale: Locale(identifier: "en_US_POSIX"),
				v.xMin + (v.xMax - v.xMin) * phase / (2 * .pi)
			)
			.lowercased()
		}
	}

	func closeLibrary() {
		libraryVisible.value = false
		try? editor?.requestFocus()
	}

	func toggleGraph() {
		if libraryVisible.value {
			closeLibrary()
			graphVisible.value = true
			return
		}

		graphVisible.value.toggle()
		if !graphVisible.value {
			tapeVisible.value = true
		}
	}

	func updatePlot() {
		guard case .success(let compiled) = parsed.value else {
			return
		}

		plotSource.value = PlotSource(expression: compiled, context: evaluationContext)
	}

	private func insert(_ text: String) {
		if fresh.value {
			let source = isOperator(text) ? CalculatorMath.literal(answer.value) + text : text
			fresh.value = false
			retainedContext.value = nil
			replaceAll(source)
			return
		}

		let range = selectionRange(in: expression.value)
		let offset = expression.value[..<range.lowerBound].utf8.count + text.utf8.count
		var source = expression.value
		source.replaceSubrange(range, with: text)
		applyEdit(source, caret: offset)
	}

	private func backspace() {
		let source = expression.value
		var range = selectionRange(in: source)
		if range.isEmpty, range.lowerBound > source.startIndex {
			range = source.index(before: range.lowerBound)..<range.lowerBound
		}

		let offset = source[..<range.lowerBound].utf8.count
		var edited = source
		edited.removeSubrange(range)
		applyEdit(edited, caret: offset)
	}

	private func selectionRange(in text: String) -> Range<String.Index> {
		guard let selection = try? editor?.selection() else {
			return text.endIndex..<text.endIndex
		}

		let lower = min(selection.anchor.utf8Offset, selection.head.utf8Offset)
		let upper = max(selection.anchor.utf8Offset, selection.head.utf8Offset)
		guard lower >= 0, upper <= text.utf8.count,
			let start = String.Index(text.utf8.index(text.utf8.startIndex, offsetBy: lower), within: text),
			let end = String.Index(text.utf8.index(text.utf8.startIndex, offsetBy: upper), within: text)
		else {
			return text.endIndex..<text.endIndex
		}

		return start..<end
	}

	private func replaceAll(_ text: String) {
		applyEdit(text, caret: text.utf8.count)
	}

	private func applyEdit(_ source: String, caret: Int) {
		guard source.count <= 1024, source.utf8.count <= 4096 else {
			committedError.value = CalculatorMath.Failure.tooComplex.description
			return
		}

		fresh.value = false
		retainedContext.value = nil
		let changed = expression.value != source
		let caret = source.indices.map { source[..<$0].utf8.count }.first { $0 >= caret } ?? source.utf8.count
		pendingCaret = changed ? caret : nil
		expression.value = source
		committedError.value = nil
		note.value = nil
		updatePlot()
		try? editor?.requestFocus()
		if !changed, let editor, let selection = try? editor.selection() {
			let position = STNTextPosition(utf8Offset: caret, revision: selection.head.revision)
			try? editor.setSelection(.init(anchor: position, head: position))
		}
	}

	func selectionChanged(_ selection: STNTextSelection) {
		guard let offset = pendingCaret, let editor else {
			return
		}
		pendingCaret = nil
		let position = STNTextPosition(
			utf8Offset: min(offset, expression.value.utf8.count),
			revision: selection.head.revision
		)
		try? editor.setSelection(.init(anchor: position, head: position))
	}

	private func evaluate() {
		do {
			let compiled = try parsed.value.get()
			let context = evaluationContext
			let outcome: HistoryEntry.Outcome
			if compiled.variables.contains(.x) {
				outcome = .function
				graphVisible.value = true
			} else {
				outcome = .number(try compiled.evaluate(in: context))
			}

			STNTransaction.perform {
				plotSource.value = PlotSource(expression: compiled, context: context)
				retainedContext.value = context
				if case .number(let value) = outcome {
					answer.value = value
				}

				fresh.value = outcome != .function
				committedError.value = nil
				note.value = outcome == .function ? "Function recorded · no scalar answer changed." : nil
				history.value.insert(
					.init(id: nextHistoryID, expression: compiled.source, outcome: outcome, context: context),
					at: 0
				)
				nextHistoryID += 1
				if history.value.count > 40 {
					history.value.removeLast()
				}
			}

			try? editor?.requestFocus()
			try? editor?.selectAll()
		} catch {
			committedError.value = String(describing: error)
		}
	}

	private func addMemory(_ sign: Double) {
		guard case .scalar(let value) = preview.value else {
			committedError.value = "Memory needs a numerical result, not a function or incomplete expression."
			return
		}

		let updated = memory.value + sign * value
		guard updated.isFinite else {
			committedError.value = CalculatorMath.Failure.overflow.description
			return
		}

		memory.value = updated
		committedError.value = nil
		note.value = "Memory updated."
	}

	private func isOperator(_ text: String) -> Bool {
		["+", "-", "−", "*", "×", "/", "÷", "^", "%"].contains(text)
	}
}
