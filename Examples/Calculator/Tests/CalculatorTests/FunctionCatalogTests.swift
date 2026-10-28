import Stana
import StanaTesting
import Testing
@testable import CalculatorApp

@Suite @MainActor struct FunctionCatalogTests {
	@Test func libraryStaysInTheCalculatorAndClosingRestoresTheWorkspace() throws {
		let session = CalculatorSession()
		let host = STNTestHost(size: .init(width: 1080, height: 780))
		host.mount { CalculatorView(session: session, showFunctions: { session.libraryVisible.value = true }) }
		defer { host.close() }
		session.libraryVisible.value = true
		#expect(host.nodes.contains { $0.text == "Function library" })
		#expect(host.semantics.nodes.contains { $0.label == "Add" })
		#expect(!host.nodes.contains { $0.kind == "gpuCanvas" })
		let search = try #require(host.nodes.first { $0.kind == "textField" && $0.isFocused })
		host.insertText("sqrt")
		#expect(host.editorState(search.id)?.text == "sqrt")
		#expect(host.semantics.nodes.contains { $0.label == "Insert sqrt" })
		session.closeLibrary()
		#expect(host.nodes.contains { $0.kind == "gpuCanvas" })
		#expect(!host.nodes.contains { $0.text == "Function library" })
		session.libraryVisible.value = true
		#expect(host.nodes.contains { $0.text == "Function library" })
		#expect(host.errors.isEmpty)
	}

	@Test func typingFiltersTheLibraryAndInsertingClosesIt() throws {
		let session = CalculatorSession()
		session.press(.clear)
		var closed = false
		let host = STNTestHost(size: .init(width: 560, height: 740))
		host.mount { FunctionCatalog(session: session) { closed = true } }
		defer {
			host.close()
		}

		let search = try #require(host.nodes.first { $0.kind == "textField" })
		#expect(search.isFocused)
		host.insertText("sqrt")
		#expect(host.nodes.contains { $0.text == "Square root" })
		#expect(!host.nodes.contains { $0.text == "Cosine" })
		let insert = try #require(host.semantics.nodes.first { $0.label == "Insert sqrt" })
		try host.activate(insert.owner)
		#expect(closed)
		#expect(session.expression.value == "sqrt(")
		#expect(host.errors.isEmpty)
	}

	@Test func initialPageIsBoundedAndBrowsingReachesEveryFunction() throws {
		let session = CalculatorSession()
		let host = STNTestHost(size: .init(width: 560, height: 740))
		host.mount { FunctionCatalog(session: session, close: {}) }
		defer { host.close() }
		var seen = Set<String>()
		for _ in 0..<9 {
			let inserts = host.semantics.nodes.filter { $0.role == .button && $0.label.hasPrefix("Insert ") }
			#expect(inserts.count <= 3)
			#expect(inserts.allSatisfy { !$0.isOffscreen })
			seen.formUnion(inserts.map(\.label))
			let next = try #require(host.semantics.nodes.first { $0.role == .button && $0.label == "Next" })
			if !next.isDisabled {
				try host.activate(next.owner)
			}
		}
		#expect(seen.count == CalculatorMath.functions.count)
	}

	@Test func noMatchesCanBeClearedAndDoneClosesWithoutEditing() throws {
		let session = CalculatorSession()
		var closed = false
		let host = STNTestHost(size: .init(width: 560, height: 740))
		host.mount { FunctionCatalog(session: session) { closed = true } }
		defer {
			host.close()
		}

		host.insertText("not-a-function")
		#expect(host.nodes.contains { $0.text.hasPrefix("No matching functions") })
		host.command("selectAll:")
		host.command("deleteBackward:")
		#expect(host.nodes.contains { $0.text == "Sine" })
		let done = try #require(host.semantics.nodes.first { $0.label == "Done" })
		try host.activate(done.owner)
		#expect(closed)
		#expect(session.expression.value == "sin(x)")
		#expect(host.errors.isEmpty)
	}
}
