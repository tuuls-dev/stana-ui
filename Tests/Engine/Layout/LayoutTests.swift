import StanaCore
import StanaPrimitives
import StanaText
import Testing

@testable import StanaLayout

@Suite @MainActor struct LayoutTests {
	@Test func boundedSpacersDistributeAndUnboundedSpacersRemainFinite() {
		let d = Document(size: .init(width: 300, height: 100))
		let engine = LayoutEngine(document: d, text: TestTextService())
		var stack: NodeRecord!
		var a: NodeRecord!
		var b: NodeRecord!
		STNTransaction.perform {
			stack = d.create(.hStack, parent: d.root)
			stack.style.frame = .init(width: 300, height: 100)
			a = d.create(.spacer, parent: stack)
			a.style.flex = 1
			b = d.create(.spacer, parent: stack)
			b.style.flex = 2
		}
		engine.layout()
		#expect(a.bounds.size.width == 100)
		#expect(b.bounds.size.width == 200)
		a.measureCache.removeAll()
		b.measureCache.removeAll()
		stack.measureCache.removeAll()
		#expect(engine.measure(stack, under: .init()).width.isFinite)
		d.close()
	}

	@Test func textScaleInvalidatesDescendantMeasurements() {
		let d = Document(size: .init(width: 300, height: 200))
		let text = TestTextService()
		let engine = LayoutEngine(document: d, text: text)
		var label: NodeRecord!
		STNTransaction.perform {
			label = d.create(.text, parent: d.root)
			label.text = "Hello"
		}
		engine.layout()
		let width = label.bounds.size.width
		d.textScale = 2
		d.invalidateEnvironment(layout: true)
		engine.layout()
		#expect(label.bounds.size.width == width * 2)
		d.close()
	}

	@Test func flexRedistributionDoesNotStrandSpaceBetweenMinAndMaxConstraints() {
		let d = Document(size: .init(width: 100, height: 30))
		let layout = LayoutEngine(document: d, text: TestTextService())
		d.layoutCountersEnabled = true
		var a: NodeRecord!
		var b: NodeRecord!
		STNTransaction.perform {
			let stack = d.create(.hStack, parent: d.root)
			stack.style.frame = .init(width: 100)
			a = d.create(.spacer, parent: stack)
			a.style.flex = 1
			a.style.frame = .init(maxWidth: 30)
			b = d.create(.spacer, parent: stack)
			b.style.flex = 1
			b.style.frame = .init(minWidth: 60)
		}
		layout.layout()
		#expect(a.bounds.size.width == 30)
		#expect(b.bounds.size.width == 70)
		#expect(d.metrics.flexDistributionRounds == 2)
		d.close()
	}

	@Test func cachedLayoutMatchesIndependentFixedBoxReferenceAcrossMutations() {
		let d = Document(size: .init(width: 500, height: 500))
		let engine = LayoutEngine(document: d, text: TestTextService())
		var stack: NodeRecord!
		var nodes: [NodeRecord] = []
		STNTransaction.perform {
			stack = d.create(.vStack, parent: d.root)
			stack.style.padding = 7
			stack.style.spacing = 3
			for index in 0..<12 {
				let node = d.create(.box, parent: stack)
				node.style.frame = .init(width: Double(index + 10), height: Double(index + 5))
				nodes.append(node)
			}
		}
		// Independent oracle: fixed boxes in a vertical stack have an arithmetic
		// prefix placement, not another invocation of the production algorithm.
		for turn in 0..<30 {
			let index = turn % nodes.count
			let width = Double(20 + turn)
			let height = Double(10 + turn)
			nodes[index].style.frame = .init(width: width, height: height)
			d.changed(nodes[index], .all)
			engine.layout()
			var y = 7.0
			for node in nodes {
				#expect(
					node.bounds == STNRect(x: 7, y: y, width: node.style.frame.width!, height: node.style.frame.height!)
				)
				y += node.style.frame.height! + 3
			}

			#expect(stack.bounds.size.width == nodes.map { $0.style.frame.width! }.max()! + 14)
		}

		d.close()
	}
}
