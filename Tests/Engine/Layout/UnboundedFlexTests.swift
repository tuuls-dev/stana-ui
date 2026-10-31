import StanaCore
import StanaPrimitives
import StanaText
import Testing

@testable import StanaLayout

@Suite @MainActor struct UnboundedFlexTests {
	@Test(arguments: [true, false])
	func flexibleContentRetainsIntrinsicSizeAcrossProposalTransitions(horizontal: Bool) {
		let d = Document(size: .init(width: 500, height: 500))
		defer {
			d.close()
		}

		d.layoutCountersEnabled = true
		let engine = LayoutEngine(document: d, text: TestTextService())
		let stack = d.create(horizontal ? .hStack : .vStack, parent: d.root)
		stack.style.spacing = 3
		stack.style.padding = 2
		stack.style.alignment = horizontal ? .firstBaseline : .leading
		let maximum = horizontal ? \STNFrame.maxWidth : \STNFrame.maxHeight
		let minimum = horizontal ? \STNFrame.minWidth : \STNFrame.minHeight
		let dimension = horizontal ? \STNFrame.width : \STNFrame.height
		func main(_ size: STNSize) -> Double {
			horizontal ? size.width : size.height
		}

		let label = d.create(.text, parent: stack)
		label.text = "abcdefghij"
		label.style.font = .system(size: 10)
		label.style.frame[keyPath: maximum] = .infinity
		let nested = d.create(horizontal ? .hStack : .vStack, parent: stack)
		nested.style.frame[keyPath: maximum] = .infinity
		let nestedLabel = d.create(.text, parent: nested)
		nestedLabel.text = "abcde"
		nestedLabel.style.font = .system(size: 10)
		nestedLabel.style.frame[keyPath: maximum] = .infinity
		let spacer = d.create(.spacer, parent: stack)
		spacer.style.flex = 2
		spacer.style.frame[keyPath: minimum] = 7
		let capped = d.create(.text, parent: stack)
		capped.text = "abcdefghij"
		capped.style.font = .system(size: 10)
		capped.style.flex = 1
		capped.style.frame[keyPath: maximum] = horizontal ? 40 : 9
		let explicit = d.create(.box, parent: stack)
		explicit.style.flex = 1
		explicit.style.frame[keyPath: dimension] = 23
		let empty = d.create(.spacer, parent: stack)
		empty.style.flex = 1

		let bounded =
			horizontal
			? STNConstraints(maxWidth: 400, maxHeight: 100)
			: STNConstraints(maxWidth: 100, maxHeight: 400)
		let unbounded = horizontal ? STNConstraints(maxHeight: 100) : STNConstraints(maxWidth: 100)
		func geometry(_ proposal: STNConstraints) -> [LayoutGeometry] {
			let size = engine.measure(stack, under: proposal)
			engine.place(stack, in: .init(width: size.width, height: size.height))
			return d.orderedNodes.map(LayoutGeometry.init)
		}

		let original = geometry(bounded)
		d.metrics = .init()
		let intrinsic = geometry(unbounded)
		#expect(main(label.measured) == (horizontal ? 60 : 13))
		#expect(main(nested.measured) == (horizontal ? 30 : 13))
		#expect(main(spacer.measured) == 7)
		#expect(main(capped.measured) == (horizontal ? 40 : 9))
		#expect(main(explicit.measured) == 23)
		#expect(main(empty.measured) == 0)
		#expect(main(stack.measured) == (horizontal ? 179 : 84))
		#expect(d.metrics.flexDistributionRounds == 0)
		#expect(d.metrics.textMeasureCalls == 3)
		#expect(geometry(unbounded) == intrinsic)
		#expect(geometry(bounded) == original)
		engine.useCache = false
		#expect(geometry(unbounded) == intrinsic)
		#expect(geometry(bounded) == original)
	}
}
