import SwiftCompilerPlugin
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import StanaSymbolCompiler

private struct SymbolMessage: DiagnosticMessage {
	let id: String
	let message: String

	var diagnosticID: MessageID {
		.init(domain: "StanaSymbol", id: id)
	}

	var severity: DiagnosticSeverity {
		.error
	}
}

public struct MakeSTNSymbolMacro: MemberMacro {
	public static func expansion(
		of attribute: AttributeSyntax,
		providingMembersOf declaration: some DeclGroupSyntax,
		conformingTo protocols: [TypeSyntax],
		in context: some MacroExpansionContext
	) throws -> [DeclSyntax] {
		func reject(_ id: String, _ message: String, at node: some SyntaxProtocol) -> [DeclSyntax] {
			context.diagnose(Diagnostic(node: Syntax(node), message: SymbolMessage(id: id, message: message)))
			return []
		}

		guard let structure = declaration.as(StructDeclSyntax.self), structure.genericParameterClause == nil,
			!context.lexicalContext.contains(where: { node in
				node.as(StructDeclSyntax.self)?.genericParameterClause != nil
					|| node.as(ClassDeclSyntax.self)?.genericParameterClause != nil
					|| node.as(EnumDeclSyntax.self)?.genericParameterClause != nil
					|| node.as(ActorDeclSyntax.self)?.genericParameterClause != nil
			})
		else {
			return reject(
				"invalidDeclaration",
				"@MakeSTNSymbol requires a non-generic struct outside generic types",
				at: declaration
			)
		}

		var mirror = false
		if let arguments = attribute.arguments {
			guard case .argumentList(let list) = arguments else {
				return reject("literalRequired", "mirrorsInRTL must be a Boolean literal", at: attribute)
			}

			if let argument = list.first {
				guard list.count == 1, argument.label?.text == "mirrorsInRTL",
					let boolean = argument.expression.as(BooleanLiteralExprSyntax.self)
				else {
					return reject("literalRequired", "mirrorsInRTL must be a Boolean literal", at: attribute)
				}

				mirror = boolean.literal.tokenKind == .keyword(.true)
			}
		}

		var svg: VariableDeclSyntax?
		var binding: PatternBindingSyntax?
		for member in structure.memberBlock.members {
			if let variable = member.decl.as(VariableDeclSyntax.self) {
				for item in variable.bindings {
					if item.pattern.tokens(viewMode: .sourceAccurate)
						.contains(where: {
							$0.text == "asset"
						})
					{
						return reject(
							"memberConflict",
							"Remove or rename the existing asset member; @MakeSTNSymbol generates asset",
							at: item
						)
					}

					if item.pattern.as(IdentifierPatternSyntax.self)?.identifier.text == "svg" {
						guard svg == nil else {
							return reject("invalidDeclaration", "Declare exactly one static let svg", at: variable)
						}

						svg = variable
						binding = item
					}
				}
			} else if member.decl.as(FunctionDeclSyntax.self)?.name.text == "asset"
				|| member.decl.as(StructDeclSyntax.self)?.name.text == "asset"
				|| member.decl.as(EnumDeclSyntax.self)?.name.text == "asset"
				|| member.decl.as(ClassDeclSyntax.self)?.name.text == "asset"
				|| member.decl.as(TypeAliasDeclSyntax.self)?.name.text == "asset"
				|| member.decl.as(ActorDeclSyntax.self)?.name.text == "asset"
				|| member.decl.as(MacroDeclSyntax.self)?.name.text == "asset"
			{
				return reject("memberConflict", "Rename the existing asset member", at: member)
			}
		}

		guard let svg, let binding, svg.bindingSpecifier.tokenKind == .keyword(.let), svg.bindings.count == 1,
			svg.modifiers.contains(where: { $0.name.tokenKind == .keyword(.static) }), binding.accessorBlock == nil
		else {
			return reject(
				"invalidDeclaration",
				"Declare exactly one static let svg initialized directly from a string literal",
				at: declaration
			)
		}

		guard let expression = binding.initializer?.value.as(StringLiteralExprSyntax.self),
			let source = expression.representedLiteralValue
		else {
			return reject(
				"literalRequired",
				"svg must be a direct Swift string literal without interpolation or concatenation",
				at: binding
			)
		}

		do {
			let compiled = try SVGCompiler.compile(source)
			return [
				DeclSyntax(
					stringLiteral:
						"public nonisolated static let asset: STNSymbolAsset = \(compiled.swift(mirrorsInRTL: mirror))"
				)
			]
		} catch let error as SymbolCompileError {
			return reject(error.id, "\(error.message) (SVG line \(error.line), column \(error.column))", at: expression)
		}
	}
}

@main
struct StanaSymbolPlugin: CompilerPlugin {
	let providingMacros: [Macro.Type] = [MakeSTNSymbolMacro.self]
}
