import Foundation

/// The calculator's expression language. Parsing is independent of values and rendering.
enum CalculatorMath {
	enum Failure: Error, Equatable, CustomStringConvertible {
		case empty
		case unexpected(String)
		case unknown(String)
		case arity(String)
		case domain(String)
		case overflow
		case tooComplex
		case unbound(String)

		var description: String {
			switch self {
			case .empty: "Enter an expression."
			case .unexpected(let token): "Check \(token)."
			case .unknown(let name): "Unknown name ‘\(name)’. Open Functions for supported names."
			case .arity(let name): "Check the number of arguments to \(name)."
			case .domain(let name): "\(name) is undefined for that input in real numbers."
			case .overflow: "The result exceeds numerical range."
			case .tooComplex: "Expression is too complex. Use fewer than 1,024 characters and 64 nested levels."
			case .unbound(let name): "Choose a value for \(name) before evaluating."
			}
		}
	}

	struct Context: Equatable {
		var degrees = false
		var answer = 0.0
		var x: Double?
		var t = 0.0
	}

	struct Variables: OptionSet, Equatable {
		let rawValue: Int
		static let x = Self(rawValue: 1)
		static let time = Self(rawValue: 2)
		static let answer = Self(rawValue: 4)
	}

	struct Expression: Equatable {
		let source: String
		fileprivate let root: Node
		let variables: Variables

		func evaluate(in context: Context) throws -> Double {
			try root.evaluate(in: context)
		}
	}

	struct Function: Equatable, Identifiable {
		let name: String
		let title: String
		let category: String
		let arguments: Int
		let example: String

		var id: String {
			name
		}
	}

	static let functions: [Function] = [
		.init(name: "sin", title: "Sine", category: "Trigonometry", arguments: 1, example: "sin(pi/2)"),
		.init(name: "cos", title: "Cosine", category: "Trigonometry", arguments: 1, example: "cos(0)"),
		.init(name: "tan", title: "Tangent", category: "Trigonometry", arguments: 1, example: "tan(pi/4)"),
		.init(name: "asin", title: "Inverse sine", category: "Trigonometry", arguments: 1, example: "asin(1)"),
		.init(name: "acos", title: "Inverse cosine", category: "Trigonometry", arguments: 1, example: "acos(0)"),
		.init(name: "atan", title: "Inverse tangent", category: "Trigonometry", arguments: 1, example: "atan(1)"),
		.init(name: "atan2", title: "Angle of (x, y)", category: "Trigonometry", arguments: 2, example: "atan2(1, 1)"),
		.init(name: "sinh", title: "Hyperbolic sine", category: "Hyperbolic", arguments: 1, example: "sinh(0)"),
		.init(name: "cosh", title: "Hyperbolic cosine", category: "Hyperbolic", arguments: 1, example: "cosh(0)"),
		.init(name: "tanh", title: "Hyperbolic tangent", category: "Hyperbolic", arguments: 1, example: "tanh(0)"),
		.init(name: "ln", title: "Natural logarithm", category: "Powers & roots", arguments: 1, example: "ln(e)"),
		.init(name: "log", title: "Base-10 logarithm", category: "Powers & roots", arguments: 1, example: "log(100)"),
		.init(name: "log2", title: "Base-2 logarithm", category: "Powers & roots", arguments: 1, example: "log2(8)"),
		.init(name: "exp", title: "Exponential", category: "Powers & roots", arguments: 1, example: "exp(1)"),
		.init(name: "sqrt", title: "Square root", category: "Powers & roots", arguments: 1, example: "sqrt(9)"),
		.init(name: "cbrt", title: "Cube root", category: "Powers & roots", arguments: 1, example: "cbrt(-8)"),
		.init(name: "pow", title: "Power", category: "Powers & roots", arguments: 2, example: "pow(2, 8)"),
		.init(name: "abs", title: "Absolute value", category: "Numbers", arguments: 1, example: "abs(-4)"),
		.init(name: "floor", title: "Round down", category: "Numbers", arguments: 1, example: "floor(1.8)"),
		.init(name: "ceil", title: "Round up", category: "Numbers", arguments: 1, example: "ceil(1.2)"),
		.init(
			name: "round",
			title: "Round, ties away from zero",
			category: "Numbers",
			arguments: 1,
			example: "round(1.5)"
		),
		.init(name: "fact", title: "Factorial (integers 0…170)", category: "Numbers", arguments: 1, example: "fact(5)"),
		.init(name: "min", title: "Smaller value", category: "Numbers", arguments: 2, example: "min(3, 1)"),
		.init(name: "max", title: "Larger value", category: "Numbers", arguments: 2, example: "max(3, 1)"),
		.init(name: "mod", title: "Signed remainder", category: "Numbers", arguments: 2, example: "mod(7, 3)"),
	]

	static func compile(_ source: String) throws -> Expression {
		guard source.count <= 1024, source.utf8.count <= 4096 else {
			throw Failure.tooComplex
		}

		var parser = try Parser(source)
		let root = try parser.expression()
		guard parser.current == .end else {
			throw Failure.unexpected("the expression near \(parser.current.label)")
		}

		guard root.depth <= 64 else {
			throw Failure.tooComplex
		}

		return Expression(source: source, root: root, variables: root.variables)
	}

	static func evaluate(_ source: String, degrees: Bool, answer: Double, x: Double, t: Double) throws -> Double {
		try compile(source).evaluate(in: .init(degrees: degrees, answer: answer, x: x, t: t))
	}

	static func format(_ value: Double) -> String {
		guard value.isFinite else {
			return "Undefined"
		}

		if value == 0 {
			return "0"
		}

		return String(format: "%.12g", locale: Locale(identifier: "en_US_POSIX"), value).lowercased()
	}

	/// Never use presentation rounding as the source of a subsequent calculation.
	static func literal(_ value: Double) -> String {
		value == 0 ? "0" : String(value)
	}

	static func resultText(_ value: Double) -> String {
		let text = format(value)
		return Double(text) == value ? text : "≈ " + text
	}

	fileprivate static func finite(_ value: Double) throws -> Double {
		guard value.isFinite else {
			throw Failure.overflow
		}

		return value
	}

	fileprivate static func power(_ base: Double, _ exponent: Double) throws -> Double {
		guard !(base == 0 && exponent <= 0), !(base < 0 && exponent != exponent.rounded()) else {
			throw Failure.domain("Power")
		}

		return try finite(pow(base, exponent))
	}

	fileprivate static func call(_ name: String, _ args: [Double], _ context: Context) throws -> Double {
		let a = args[0]
		let radians = context.degrees ? a.truncatingRemainder(dividingBy: 360) * .pi / 180 : a
		let toAngle: (Double) -> Double = { context.degrees ? $0 * 180 / .pi : $0 }
		let value: Double
		switch name {
		case "sin": value = sin(radians)
		case "cos": value = cos(radians)
		case "tan":
			let reduced =
				context.degrees
				? a.truncatingRemainder(dividingBy: 180)
				: a.truncatingRemainder(dividingBy: .pi)
			guard abs(reduced) != (context.degrees ? 90 : .pi / 2) else {
				throw Failure.domain("Tangent")
			}

			value = tan(radians)
		case "asin", "acos":
			guard abs(a) <= 1 else {
				throw Failure.domain(name)
			}

			value = toAngle(name == "asin" ? asin(a) : acos(a))
		case "atan": value = toAngle(atan(a))
		case "atan2":
			guard a != 0 || args[1] != 0 else {
				throw Failure.domain("atan2(0, 0)")
			}

			value = toAngle(atan2(a, args[1]))
		case "sinh": value = sinh(a)
		case "cosh": value = cosh(a)
		case "tanh": value = tanh(a)
		case "ln", "log", "log2":
			guard a > 0 else {
				throw Failure.domain(name)
			}

			value = name == "ln" ? log(a) : name == "log" ? log10(a) : log2(a)
		case "sqrt":
			guard a >= 0 else {
				throw Failure.domain("Square root")
			}

			value = sqrt(a)
		case "cbrt": value = cbrt(a)
		case "abs": value = abs(a)
		case "exp": value = exp(a)
		case "floor": value = floor(a)
		case "ceil": value = ceil(a)
		case "round": value = a.rounded()
		case "fact":
			guard a >= 0, a <= 170, a == a.rounded() else {
				throw Failure.domain("Factorial")
			}

			value = a < 2 ? 1 : (2...Int(a)).reduce(1.0) { $0 * Double($1) }
		case "min": value = min(a, args[1])
		case "max": value = max(a, args[1])
		case "mod":
			guard args[1] != 0 else {
				throw Failure.domain("Remainder")
			}

			value = a.truncatingRemainder(dividingBy: args[1])
		case "pow": value = try power(a, args[1])
		default: throw Failure.unknown(name)
		}

		return try finite(value)
	}

	fileprivate indirect enum Node: Equatable {
		case number(Double)
		case variable(String)
		case negate(Node)
		case percent(Node)
		case binary(Character, Node, Node)
		case call(String, [Node])

		var depth: Int {
			switch self {
			case .number, .variable: 1
			case .negate(let node), .percent(let node): node.depth + 1
			case .binary(_, let lhs, let rhs): max(lhs.depth, rhs.depth) + 1
			case .call(_, let args): (args.map(\.depth).max() ?? 0) + 1
			}
		}

		var variables: Variables {
			switch self {
			case .number: []
			case .variable(let name): name == "x" ? .x : name == "t" ? .time : name == "ans" ? .answer : []
			case .negate(let node), .percent(let node): node.variables
			case .binary(_, let lhs, let rhs): lhs.variables.union(rhs.variables)
			case .call(_, let args): args.reduce(Variables()) { $0.union($1.variables) }
			}
		}

		func evaluate(in context: Context) throws -> Double {
			switch self {
			case .number(let value): return value
			case .variable(let name):
				switch name {
				case "pi", "π": return .pi
				case "e": return M_E
				case "ans": return try finite(context.answer)
				case "t": return try finite(context.t)
				default:
					guard let x = context.x else {
						throw Failure.unbound("x")
					}

					return try finite(x)
				}
			case .negate(let node): return try -node.evaluate(in: context)
			case .percent(let node): return try node.evaluate(in: context) / 100
			case .call(let name, let args):
				return try CalculatorMath.call(name, args.map { try $0.evaluate(in: context) }, context)
			case .binary(let op, let lhs, let rhs):
				let a = try lhs.evaluate(in: context)
				let b = try rhs.evaluate(in: context)
				switch op {
				case "+": return try finite(a + b)
				case "-": return try finite(a - b)
				case "*": return try finite(a * b)
				case "/":
					guard b != 0 else {
						throw Failure.domain("Division by zero")
					}

					return try finite(a / b)
				default: return try power(a, b)
				}
			}
		}
	}

	private enum Token: Equatable {
		case number(Double)
		case name(String)
		case symbol(Character)
		case end

		var label: String {
			switch self {
			case .number(let value): CalculatorMath.format(value)
			case .name(let name): "‘\(name)’"
			case .symbol(let character): "‘\(character)’"
			case .end: "the end of the expression"
			}
		}
	}

	private struct Parser {
		var tokens: [Token] = []
		var index = 0
		var nesting = 0

		var current: Token {
			tokens[index]
		}

		init(_ source: String) throws {
			let chars = Array(source)
			var cursor = 0
			while cursor < chars.count {
				let c = chars[cursor]
				if c.isWhitespace {
					cursor += 1
					continue
				}

				if c.isASCII && c.isNumber || c == "." {
					let start = cursor
					while cursor < chars.count, chars[cursor].isASCII && chars[cursor].isNumber || chars[cursor] == "."
					{
						cursor += 1
					}

					if cursor < chars.count, chars[cursor] == "e" || chars[cursor] == "E" {
						cursor += 1
						if cursor < chars.count, chars[cursor] == "+" || chars[cursor] == "-" {
							cursor += 1
						}

						while cursor < chars.count, chars[cursor].isASCII && chars[cursor].isNumber {
							cursor += 1
						}
					}

					guard let value = Double(String(chars[start..<cursor])) else {
						throw Failure.unexpected("the number ‘\(String(chars[start..<cursor]))’")
					}

					tokens.append(.number(try finite(value)))
				} else if c.isLetter {
					let start = cursor
					cursor += 1
					while cursor < chars.count,
						chars[cursor].isLetter || chars[cursor].isASCII && chars[cursor].isNumber
					{
						cursor += 1
					}

					tokens.append(.name(String(chars[start..<cursor]).lowercased()))
				} else {
					let normalized: Character = c == "×" ? "*" : c == "÷" ? "/" : c == "−" ? "-" : c
					guard "+-*/^%(),".contains(normalized) else {
						throw Failure.unexpected("the character ‘\(c)’")
					}

					tokens.append(.symbol(normalized))
					cursor += 1
				}
			}

			tokens.append(.end)
		}

		mutating func consume(_ symbol: Character) -> Bool {
			guard current == .symbol(symbol) else {
				return false
			}

			index += 1
			return true
		}

		mutating func expression() throws -> Node {
			guard current != .end else {
				throw Failure.empty
			}

			var node = try term()
			while current == .symbol("+") || current == .symbol("-") {
				let op: Character = consume("+") ? "+" : "-"
				if op == "-" {
					index += 1
				}
				node = .binary(op, node, try term())
			}

			return node
		}

		mutating func term() throws -> Node {
			var node = try unary()
			while current == .symbol("*") || current == .symbol("/") {
				let op: Character = consume("*") ? "*" : "/"
				if op == "/" {
					index += 1
				}
				node = .binary(op, node, try unary())
			}

			return node
		}

		mutating func unary() throws -> Node {
			nesting += 1
			defer {
				nesting -= 1
			}

			guard nesting <= 64 else {
				throw Failure.tooComplex
			}

			if consume("+") {
				return try unary()
			}

			if consume("-") {
				return .negate(try unary())
			}

			var node = try primary()
			while consume("%") {
				node = .percent(node)
			}

			if consume("^") {
				node = .binary("^", node, try unary())
			}

			return node
		}

		mutating func primary() throws -> Node {
			if consume("(") {
				let node = try expression()
				guard consume(")") else {
					throw Failure.unexpected("the closing parenthesis")
				}

				return node
			}

			switch current {
			case .number(let value):
				index += 1
				return .number(value)
			case .name(let name):
				index += 1
				if consume("(") {
					guard let function = functions.first(where: { $0.name == name }) else {
						throw Failure.unknown(name)
					}

					var args: [Node] = []
					if current != .symbol(")") {
						args.append(try expression())
						while consume(",") {
							args.append(try expression())
						}
					}

					guard consume(")") else {
						throw Failure.unexpected("the closing parenthesis for \(name)")
					}

					guard args.count == function.arguments else {
						throw Failure.arity(name)
					}

					return .call(name, args)
				}

				guard ["pi", "π", "e", "ans", "x", "t"].contains(name) else {
					throw Failure.unknown(name)
				}

				return .variable(name)
			default: throw Failure.unexpected(current.label)
			}
		}
	}
}
