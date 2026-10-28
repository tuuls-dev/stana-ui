import Foundation
import Testing
@testable import CalculatorApp

@Suite struct EngineTests {
	private static let numericalCases: [(String, Double)] = [
		("2+2", 4.0), ("2*(3+4)", 14), ("2^3^2", 512), ("-2^2", -4), ("2^-3", 0.125),
		("2*-3", -6), ("(1+2)%", 0.03), ("50%", 0.5), ("2^3%", pow(2, 0.03)),
		("sqrt(9)", 3), ("cbrt(-8)", -2), ("fact(0)", 1), ("fact(5)", 120),
		("min(3,1)", 1), ("max(3,1)", 3), ("mod(-7,3)", -1), ("abs(-4)", 4),
		("floor(1.8)", 1), ("ceil(1.2)", 2), ("round(-1.5)", -2), ("ln(1)", 0),
		("log(100)", 2), ("log2(8)", 3), ("exp(0)", 1), ("pi", .pi), ("π", .pi),
		("e", M_E), ("sin(pi/2)", 1), ("cos(0)", 1), ("atan2(1,1)", .pi / 4),
		("pow(2,3)", 8), ("2×3÷4", 1.5), ("sinh(0)", 0), ("cosh(0)", 1),
		("tanh(0)", 0), ("asin(1)", .pi / 2), ("acos(0)", .pi / 2), ("atan(1)", .pi / 4),
		("1.25e-3 + 2E2", 200.00125), ("0.1 + 0.2", 0.30000000000000004),
	]

	@Test(arguments: numericalCases)
	func numericalSemantics(_ source: String, _ expected: Double) throws {
		let value = try CalculatorMath.compile(source).evaluate(in: .init())
		#expect(abs(value - expected) <= max(1, abs(expected)) * 2e-14)
	}

	@Test(arguments: [
		"1/0", "0/0", "0^0", "0^-1", "(-2)^0.5", "sqrt(-1)", "ln(0)", "log(-1)", "asin(2)", "acos(-2)", "fact(-1)",
		"fact(1.5)", "fact(171)", "mod(1,0)", "atan2(0,0)",
	])
	func invalidDomainsNeverProduceAnAnswer(_ source: String) throws {
		let expression = try CalculatorMath.compile(source)
		#expect(throws: CalculatorMath.Failure.self) { try expression.evaluate(in: .init()) }
	}

	@Test(arguments: [
		"", " ", "2+", "2(3)", "nope(1)", "sin(1,2)", "min(1)", "sqrt()", "(1+2", "1,2", "1..2", "1e+", "1e", "💥",
		"2**3",
	])
	func malformedExpressionsAreRejected(_ source: String) {
		#expect(throws: CalculatorMath.Failure.self) { try CalculatorMath.compile(source) }
	}

	@Test func angleModesAndSingularities() throws {
		#expect(try CalculatorMath.compile("sin(90)").evaluate(in: .init(degrees: true)) == 1)
		#expect(try CalculatorMath.compile("asin(1)").evaluate(in: .init(degrees: true)) == 90)
		#expect(try CalculatorMath.compile("atan2(1,0)").evaluate(in: .init(degrees: true)) == 90)
		for source in ["tan(90)", "tan(270)", "tan(-90)"] {
			let expression = try CalculatorMath.compile(source)
			#expect(throws: CalculatorMath.Failure.self) { try expression.evaluate(in: .init(degrees: true)) }
		}

		let pole = try CalculatorMath.compile("tan(pi/2)")
		#expect(throws: CalculatorMath.Failure.self) { try pole.evaluate(in: .init()) }
		#expect(try CalculatorMath.compile("tan(89.999)").evaluate(in: .init(degrees: true)).isFinite)
		#expect(try CalculatorMath.compile("sinh(1)").evaluate(in: .init(degrees: true)) == sinh(1))
	}

	@Test func variablesAreExplicitAndCompilationIsValueIndependent() throws {
		let expression = try CalculatorMath.compile("sqrt(x-10)+ans+t")
		#expect(expression.variables == [.x, .answer, .time])
		#expect(throws: CalculatorMath.Failure.self) { try expression.evaluate(in: .init()) }
		#expect(try expression.evaluate(in: .init(answer: 4, x: 19, t: 2)) == 9)
	}

	@Test func presentationNeverSnapsNonzeroOrFractionalValues() {
		#expect(CalculatorMath.format(1000000000.1) == "1000000000.1")
		#expect(CalculatorMath.format(1e-13) == "1e-13")
		#expect(CalculatorMath.format(-0.0) == "0")
		#expect(CalculatorMath.resultText(0.1 + 0.2).hasPrefix("≈"))
		for value in [Double.leastNonzeroMagnitude, Double.greatestFiniteMagnitude, 1e-13, .pi, 1000000000.1] {
			#expect(Double(CalculatorMath.literal(value)) == value)
		}
	}

	@Test func boundsAndOverflowFailWithoutCrashing() throws {
		for source in [
			String(repeating: "(", count: 100) + "1" + String(repeating: ")", count: 100),
			String(repeating: "1+", count: 200) + "1", String(repeating: "-", count: 100) + "1",
			String(repeating: "1", count: 1025), "1e999",
		] {
			#expect(throws: CalculatorMath.Failure.self) { try CalculatorMath.compile(source) }
		}

		let expression = try CalculatorMath.compile("1e308*2")
		#expect(throws: CalculatorMath.Failure.overflow) { try expression.evaluate(in: .init()) }
	}
}
