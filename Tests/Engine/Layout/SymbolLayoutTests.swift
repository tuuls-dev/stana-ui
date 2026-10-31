import StanaCore
import StanaPrimitives
import StanaText
import Testing

@testable import StanaLayout
@Suite @MainActor struct SymbolLayoutTests {
	@Test(arguments: [0.0, 24.0, 40.0], [STNSize(width: 100, height: 60), .init(width: 12, height: 50), .zero])
	func squareBaselineUsesFinalContentBox(size: Double, frame: STNSize) {
		let document = Document(size: .init(width: 200, height: 200))
		defer { document.close() }

		let node = document.create(.symbol, parent: document.root)
		node.symbol = SymbolContent(
			asset: SymbolStorage(viewBox: .init(x: -12, y: -4, width: 24, height: 8), mirrorsInRTL: false, elements: [])
		)
		node.symbol?.size = size
		node.style.padding = .init(top: 3, leading: 5, bottom: 7, trailing: 9)
		node.style.frame = .init(width: frame.width, height: frame.height)
		let engine = LayoutEngine(document: document, text: TestTextService())
		let measured = engine.measure(node, under: .init(maxWidth: 200, maxHeight: 200))
		let content = STNRect(width: measured.width, height: measured.height).inset(by: node.style.padding)
		let square = symbolSquare(size: size, content: content)
		#expect(measured == frame)
		#expect(node.baseline == square.maxY)
		engine.place(node, in: .init(x: 10, y: 20, width: measured.width, height: measured.height))
		#expect(node.baseline == square.maxY)
	}

	@Test func defaultSizeIsNotTextScaledAndPaddingRemainsAtZero() {
		let document = Document(size: .init(width: 200, height: 200))
		defer { document.close() }

		let node = document.create(.symbol, parent: document.root)
		node.symbol = SymbolContent(
			asset: SymbolStorage(viewBox: .init(width: 10, height: 20), mirrorsInRTL: false, elements: [])
		)
		node.style.padding = .init(2)
		document.textScale = 3
		let engine = LayoutEngine(document: document, text: TestTextService())
		#expect(engine.measure(node, under: .init()) == .init(width: 28, height: 28))
		node.symbol?.size = 0
		document.changed(node, .all)
		#expect(engine.measure(node, under: .init()) == .init(width: 4, height: 4))
		#expect(node.baseline == 2)
	}
}
