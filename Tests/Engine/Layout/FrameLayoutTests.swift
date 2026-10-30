import StanaCore
import StanaPrimitives
import StanaText
import Testing

@testable import StanaLayout

@Suite @MainActor struct FrameLayoutTests {
	@Test(arguments: [true, false])
	func assigningInfinityMatchesExplicitInitialization(horizontal: Bool) {
		let document = Document(size: .init(width: 100, height: 80))
		defer { document.close() }
		let engine = LayoutEngine(document: document, text: TestTextService())
		engine.useCache = false
		let node = document.create(.box, parent: document.root)
		let proposal = STNConstraints(maxWidth: 100, maxHeight: 80)
		let maximum = horizontal ? \STNFrame.maxWidth : \STNFrame.maxHeight
		var frame = STNFrame(minWidth: 12, minHeight: 8)
		node.style.frame = frame
		#expect(engine.measure(node, under: proposal) == STNSize(width: 12, height: 8))
		frame[keyPath: maximum] = .infinity
		node.style.frame = frame
		let expected = horizontal ? STNSize(width: 100, height: 8) : STNSize(width: 12, height: 80)
		#expect(engine.measure(node, under: proposal) == expected)
		let initialized = STNFrame(
			minWidth: 12,
			maxWidth: horizontal ? .infinity : nil,
			minHeight: 8,
			maxHeight: horizontal ? nil : .infinity
		)
		#expect(frame == initialized)
		node.style.frame = initialized
		#expect(engine.measure(node, under: proposal) == expected)
		#expect(engine.measure(node, under: .init()) == STNSize(width: 12, height: 8))
	}

	@Test(arguments: [true, false])
	func finiteAssignmentsClearOnlyTheirAxisFillIntent(horizontal: Bool) {
		let document = Document(size: .init(width: 100, height: 80))
		defer { document.close() }
		let engine = LayoutEngine(document: document, text: TestTextService())
		engine.useCache = false
		let node = document.create(.box, parent: document.root)
		let maximum = horizontal ? \STNFrame.maxWidth : \STNFrame.maxHeight
		var frame = STNFrame(minWidth: 12, maxWidth: .infinity, minHeight: 8, maxHeight: .infinity)
		for maximumValue in [Double.infinity, 40, .infinity] {
			frame[keyPath: maximum] = maximumValue
			node.style.frame = frame
			let expected =
				maximumValue == .infinity
				? STNSize(width: 100, height: 80)
				: horizontal ? STNSize(width: 12, height: 80) : STNSize(width: 100, height: 8)
			#expect(engine.measure(node, under: .init(maxWidth: 100, maxHeight: 80)) == expected)
		}
	}

	@Test(arguments: [true, false])
	func copiesEqualityAndHashingPreserveExplicitFillIntent(horizontal: Bool) {
		let original = STNFrame()
		var copy = original
		let maximum = horizontal ? \STNFrame.maxWidth : \STNFrame.maxHeight
		copy[keyPath: maximum] = .infinity
		let explicit = STNFrame(maxWidth: horizontal ? .infinity : nil, maxHeight: horizontal ? nil : .infinity)
		#expect(original.maxWidth == copy.maxWidth)
		#expect(original.maxHeight == copy.maxHeight)
		#expect(original != copy)
		#expect(copy == explicit)
		#expect(Set([original, copy, explicit]).count == 2)
		#expect(Set([copy]).contains(explicit))
		let filledCopy = copy
		copy[keyPath: maximum] = 40
		let finite = STNFrame(maxWidth: horizontal ? 40 : nil, maxHeight: horizontal ? nil : 40)
		#expect(copy == finite)
		#expect(Set([copy]).contains(finite))
		#expect(filledCopy == explicit)
		copy[keyPath: maximum] = .infinity
		#expect(copy == filledCopy)
	}

	@Test(arguments: [true, false])
	func fixedDimensionsTakePrecedenceOverMutatedFillAllocation(horizontal: Bool) {
		let document = Document(size: .init(width: 100, height: 80))
		defer { document.close() }
		let engine = LayoutEngine(document: document, text: TestTextService())
		let stack = document.create(horizontal ? .hStack : .vStack, parent: document.root)
		stack.style.frame = .init(width: 100, height: 80)
		let fixed = document.create(.box, parent: stack)
		var frame = STNFrame(width: 40, height: 30)
		frame.maxWidth = .infinity
		frame.maxHeight = .infinity
		fixed.style.frame = frame
		let flexible = document.create(.box, parent: stack)
		flexible.style.frame = .init(maxWidth: .infinity, maxHeight: .infinity)
		engine.layout()
		#expect(fixed.bounds.size == STNSize(width: 40, height: 30))
		let expected = horizontal ? STNSize(width: 60, height: 80) : STNSize(width: 100, height: 50)
		#expect(flexible.bounds.size == expected)
	}
}
