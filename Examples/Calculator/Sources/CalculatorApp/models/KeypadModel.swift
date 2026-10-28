import Stana

struct KeySpec: Equatable {
	let title: String
	let hint: String
	let action: KeyAction
}

enum KeypadModel {
	static let scientific: [[KeySpec]] = [
		[
			.init(title: "sin", hint: "Sine", action: .insert("sin(")),
			.init(title: "cos", hint: "Cosine", action: .insert("cos(")),
			.init(title: "tan", hint: "Tangent", action: .insert("tan(")),
			.init(title: "xʸ", hint: "Power", action: .insert("^")),
		],
		[
			.init(title: "(", hint: "Open parenthesis", action: .insert("(")),
			.init(title: ")", hint: "Close parenthesis", action: .insert(")")),
			.init(title: "√", hint: "Square root", action: .insert("sqrt(")),
			.init(title: "π", hint: "Pi", action: .insert("pi")),
		],
	]
	static let arithmetic: [[KeySpec]] = [
		[
			.init(title: "AC", hint: "Clear expression", action: .clear),
			.init(title: "±", hint: "Negate expression", action: .negate),
			.init(title: "%", hint: "Divide preceding value by 100", action: .insert("%")),
			.init(title: "÷", hint: "Divide", action: .insert("/")),
		],
		[digit("7"), digit("8"), digit("9"), .init(title: "×", hint: "Multiply", action: .insert("*"))],
		[digit("4"), digit("5"), digit("6"), .init(title: "−", hint: "Subtract", action: .insert("-"))],
		[digit("1"), digit("2"), digit("3"), .init(title: "+", hint: "Add", action: .insert("+"))],
		[
			digit("0"), .init(title: ".", hint: "Decimal point", action: .insert(".")),
			.init(title: "⌫", hint: "Delete selection or previous character", action: .backspace),
			.init(title: "=", hint: "Evaluate or record function", action: .evaluate),
		],
	]

	private static func digit(_ value: String) -> KeySpec {
		.init(title: value, hint: value, action: .insert(value))
	}
}

/// A single restrained material surface, rather than a separate blur pass for every key.
