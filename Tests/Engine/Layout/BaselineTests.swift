import StanaCore
import StanaPrimitives
import StanaText
import Testing

@testable import StanaLayout

@MainActor struct LayoutGeometry: Equatable {
	let bounds: STNRect
	let measured: STNSize
	let baseline: Double?
	let content: STNSize
	let offset: STNPoint

	init(_ node: NodeRecord) {
		bounds = node.bounds
		measured = node.measured
		baseline = node.baseline
		content = node.contentSize
		offset = node.scrollOffset
	}
}

@Suite @MainActor struct BaselineTests {
	@Test(arguments: [false, true])
	func flexibleBaselineUsesFinalMeasurementsAcrossHistories(nested: Bool) throws {
		let d = Document(size: .init(width: 240, height: 200))
		defer {
			d.close()
		}
		let engine = LayoutEngine(document: d, text: TestTextService())
		let outer = d.create(.hStack, parent: d.root)
		outer.style.alignment = .firstBaseline
		let row = nested ? d.create(.hStack, parent: outer) : outer
		row.style.alignment = .firstBaseline
		let small = d.create(.text, parent: row)
		small.text = "a"
		small.style.font = .system(size: 10)
		small.style.padding = .init(bottom: 20)
		let large = d.create(.text, parent: row)
		large.text = "b"
		large.style.font = .system(size: 30)
		large.style.flex = 1
		if nested {
			let peer = d.create(.text, parent: outer)
			peer.text = "c"
			peer.style.font = .system(size: 16)
		}

		func geometry(width: Double) -> [LayoutGeometry] {
			let size = engine.measure(outer, under: .init(maxWidth: width, maxHeight: 200))
			engine.place(outer, in: .init(width: size.width, height: size.height))
			return d.orderedNodes.map(LayoutGeometry.init)
		}

		let cold = geometry(width: 240)
		#expect(row.measured.height == 53)
		#expect(row.baseline == 30)
		#expect(small.bounds.minY + small.baseline! == large.bounds.minY + large.baseline!)
		#expect(small.bounds.maxY <= row.bounds.maxY)
		#expect(geometry(width: 240) == cold)
		_ = geometry(width: 120)
		#expect(geometry(width: 240) == cold)
		engine.useCache = false
		#expect(geometry(width: 240) == cold)
		_ = geometry(width: 120)
		engine.useCache = true
		#expect(geometry(width: 240) == cold)
		try d.reorder(row, children: [large, small])
		let reordered = geometry(width: 240)
		#expect(row.measured.height == 53)
		#expect(row.baseline == 30)
		engine.useCache = false
		#expect(geometry(width: 240) == reordered)
	}

	@Test(arguments: [NodeKind.box, .vStack, .hStack, .zStack, .focusScope, .layer])
	func containersExportFirstTextBaselineWithLocalPlacement(kind: NodeKind) {
		let d = Document(size: .init(width: 300, height: 200))
		defer {
			d.close()
		}
		let engine = LayoutEngine(document: d, text: TestTextService())
		let wrapper = d.create(kind, parent: d.root)
		wrapper.style.padding = .init(top: 7, leading: 11, bottom: 13, trailing: 17)
		wrapper.style.frame = .init(width: 200, height: 100)
		wrapper.style.alignment = .center
		let nonText = d.create(.box, parent: wrapper)
		nonText.style.frame = .init(width: 10, height: 12)
		let label = d.create(.text, parent: wrapper)
		label.style.font = .system(size: 10)
		label.text = "baseline"
		engine.layout()
		#expect(nonText.baseline == nil)
		#expect(wrapper.baseline == label.bounds.minY - wrapper.bounds.minY + label.baseline!)
	}

	@Test func nonTextUsesBottomContentEdgeAndExplicitFrameStillOverflows() {
		let d = Document(size: .init(width: 200, height: 100))
		defer {
			d.close()
		}
		let engine = LayoutEngine(document: d, text: TestTextService())
		let row = d.create(.hStack, parent: d.root)
		row.style.alignment = .firstBaseline
		row.style.frame.height = 20
		let box = d.create(.box, parent: row)
		box.style.frame = .init(width: 20, height: 40)
		box.style.padding = .init(bottom: 5)
		let text = d.create(.text, parent: row)
		text.text = "a"
		text.style.font = .system(size: 10)
		engine.layout()
		#expect(box.baseline == nil)
		#expect(row.baseline == 35)
		#expect(row.measured.height == 20)
		#expect(text.bounds.minY + text.baseline! == 35)
		#expect(box.bounds.maxY > row.bounds.maxY)
	}
}
