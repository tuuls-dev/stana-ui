import Testing
import SwiftDiagnostics
import SwiftParser
import SwiftSyntax
import SwiftSyntaxMacros
import SwiftSyntaxMacroExpansion

@testable import StanaSymbolMacros
@Suite struct MakeSTNSymbolMacroTests {
	private func expand(_ source: String) -> (String, [Diagnostic]) {
		let tree = Parser.parse(source: source)
		let context = BasicMacroExpansionContext(sourceFiles: [
			tree: .init(moduleName: "Consumer", fullFilePath: "Consumer.swift")
		])
		let expanded = tree.expand(
			macroSpecs: ["MakeSTNSymbol": MacroSpec(type: MakeSTNSymbolMacro.self)],
			contextGenerator: {
				BasicMacroExpansionContext(sharingWith: context, lexicalContext: $0.allMacroLexicalContexts())
			}
		)
		return (expanded.description, context.diagnostics)
	}

	@Test func emptyParenthesesUseDefaultMetadata() {
		let (expanded, diagnostics) = expand(
			"@MakeSTNSymbol() struct Icon { static let svg = \"<svg viewBox='0 0 1 1'/>\" }"
		)
		#expect(diagnostics.isEmpty)
		#expect(expanded.contains("mirrorsInRTL: false"))
	}

	@Test(arguments: [
		#""<svg viewBox=\"0 0 2 2\"><path d=\"M0 0L1 1\"/></svg>""#,
		##"#"<svg viewBox="0 0 2 2"><path d="M0 0L1 1"/></svg>"#"##,
		"\"\"\"\n<svg viewBox='0 0 2 2'><path d='M0 0L1 1'/></svg>\n\"\"\"",
		"#\"\"\"\n<svg viewBox='0 0 2 2'><path d='M0 0L1 1'/></svg>\n\"\"\"#",
	])
	func literalFormsProduceTypedStaticGeometry(_ literal: String) {
		let source =
			"@MainActor @MakeSTNSymbol(mirrorsInRTL: true) public struct Icon { private static let svg = \(literal) }"
		let (expanded, diagnostics) = expand(source)
		#expect(diagnostics.isEmpty)
		#expect(expanded.contains("public nonisolated static let asset: STNSymbolAsset"))
		#expect(expanded.contains("STNSymbolAsset._compiled(version: 1"))
		#expect(expanded.contains("mirrorsInRTL: true"))
		#expect(expanded.contains(".line(x: 1.0, y: 1.0)"))
		#expect(!expanded.contains("STNSymbolAsset(svg:"))
		#expect(expand(source).0 == expanded)
	}

	@Test(arguments: [
		("@MakeSTNSymbol enum Icon { static let svg = \"x\" }", "invalidDeclaration"),
		("@MakeSTNSymbol struct Icon<T> { static let svg = \"x\" }", "invalidDeclaration"),
		("struct Outer<T> { @MakeSTNSymbol struct Icon { static let svg = \"x\" } }", "invalidDeclaration"),
		("@MakeSTNSymbol struct Icon { static var svg = \"x\" }", "invalidDeclaration"),
		("@MakeSTNSymbol struct Icon { let svg = \"x\" }", "invalidDeclaration"),
		("@MakeSTNSymbol struct Icon { static var svg: String { \"x\" } }", "invalidDeclaration"),
		("@MakeSTNSymbol struct Icon { static let svg = \"x\" + \"y\" }", "literalRequired"),
		("@MakeSTNSymbol struct Icon { static let svg = \"x\\(1)\" }", "literalRequired"),
		("@MakeSTNSymbol struct Icon { static let svg = other }", "literalRequired"),
		("@MakeSTNSymbol struct Icon { static let svg = String(\"x\") }", "literalRequired"),
		("@MakeSTNSymbol(mirrorsInRTL: flag) struct Icon { static let svg = \"x\" }", "literalRequired"),
		("@MakeSTNSymbol struct Icon { static let svg = \"x\"; let asset = 0 }", "memberConflict"),
		("@MakeSTNSymbol struct Icon { static let svg = \"x\"; func asset() {} }", "memberConflict"),
		("@MakeSTNSymbol struct Icon { static let svg = \"<svg\" }", "invalidXML"),
		(
			"@MakeSTNSymbol struct Icon { static let svg = \"<svg viewBox='0 0 1 1'><text/></svg>\" }",
			"unsupportedFeature"
		),
	])
	func invalidDeclarationsDiagnoseStableCategories(_ input: (String, String)) {
		let (_, diagnostics) = expand(input.0)
		#expect(diagnostics.count == 1)
		#expect(diagnostics.first?.diagnosticID == MessageID(domain: "StanaSymbol", id: input.1))
	}
}
