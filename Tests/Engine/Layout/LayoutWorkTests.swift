import StanaCore
import StanaPrimitives
import StanaText
import Testing

@testable import StanaLayout

@Suite @MainActor struct LayoutWorkTests {
	@Test func unchangedSameOutputAndBatchedEditsExposeTraversal() {
		let d = Document(size: .init(width: 500, height: 500))
		defer {
			d.close()
		}
		d.layoutCountersEnabled = true
		let engine = LayoutEngine(document: d, text: TestTextService())
		let stack = d.create(.vStack, parent: d.root)
		let labels = (0..<8)
			.map { _ in
				let label = d.create(.text, parent: stack)
				label.text = "old"
				return label
			}
		engine.layout()
		let geometry = d.orderedNodes.map(LayoutGeometry.init)
		d.metrics = .init()
		engine.layout()
		#expect(d.metrics.measureVisits == 0)
		#expect(d.metrics.placementVisits == 0)
		d.dirty.insert(.layout)
		engine.layout()
		#expect(d.metrics.measureVisits == 1)
		#expect(d.metrics.measureCacheHits == 1)
		#expect(d.metrics.measureCalls == 0)
		#expect(d.metrics.placementVisits == 1)
		#expect(d.metrics.placedNodes == 0)
		d.metrics = .init()
		labels[0].text = "new"
		d.changed(labels[0], .all)
		engine.layout()
		#expect(d.metrics.measureVisits == 10)
		#expect(d.metrics.measureCalls == 3)
		#expect(d.metrics.measureCacheHits == 7)
		#expect(d.metrics.textMeasureCalls == 1)
		#expect(d.metrics.layoutOutputChanges == 0)
		#expect(d.metrics.placementVisits == 10)
		#expect(d.metrics.placedNodes == 3)
		#expect(d.metrics.arrangedChildVisits == 18)
		#expect(d.metrics.layoutDirtyAncestorVisits == 3)
		#expect(d.orderedNodes.map(LayoutGeometry.init) == geometry)
		d.metrics = .init()
		STNTransaction.perform {
			for label in labels.prefix(2) {
				label.text = "two"
				d.changed(label, .all)
			}
		}
		engine.layout()
		#expect(d.metrics.measureCalls == 4)
		#expect(d.metrics.measureVisits == 10)
		#expect(d.metrics.textMeasureCalls == 2)
		// Invalidation still walks each shared ancestor per edit; do not conceal it.
		#expect(d.metrics.layoutDirtyAncestorVisits == 6)
	}

	@Test func offsetOnlyLayoutDoesNotMeasureText() {
		let d = Document(size: .init(width: 100, height: 100))
		defer {
			d.close()
		}
		d.layoutCountersEnabled = true
		let engine = LayoutEngine(document: d, text: TestTextService())
		let scroll = d.create(.scroll, parent: d.root)
		let label = d.create(.text, parent: scroll)
		label.text = String(repeating: "long ", count: 100)
		engine.layout()
		d.metrics = .init()
		scroll.scrollOffset.y = 20
		d.changed(scroll, .all)
		engine.layout()
		#expect(scroll.scrollOffset.y == 20)
		#expect(d.metrics.textMeasureCalls == 0)
		#expect(d.metrics.measureVisits == 3)
		#expect(d.metrics.measureCacheHits == 1)
		#expect(d.metrics.layoutOutputChanges == 2)  // Exported baselines move with scrolling.
		#expect(d.metrics.placementVisits == 3)
	}

	@Test(arguments: [STNLayoutDirection.leftToRight, .rightToLeft])
	func asymmetricPaddingCollapsedGroupsAndCacheHistoriesMatch(direction: STNLayoutDirection) {
		let d = Document(size: .init(width: 300, height: 200))
		defer {
			d.close()
		}
		d.direction = direction
		let engine = LayoutEngine(document: d, text: TestTextService())
		let row = d.create(.hStack, parent: d.root)
		row.style.padding = .init(top: 7, leading: 11, bottom: 13, trailing: 17)
		row.style.frame.width = 200
		let group = d.create(.group, parent: row)
		let first = d.create(.text, parent: group)
		first.text = "abc"
		let collapsed = d.create(.group, parent: row)
		collapsed.style.visibility = .collapsed
		let hidden = d.create(.text, parent: collapsed)
		hidden.text = "not arranged"
		let last = d.create(.text, parent: row)
		last.text = "def"
		engine.layout()
		let cold = d.orderedNodes.map(LayoutGeometry.init)
		#expect(hidden.measured == .zero)
		#expect(row.measured.height == first.measured.height + 20)
		#expect(first.bounds.minY == 7)
		if direction == .leftToRight {
			#expect(first.bounds.minX == 11)
		} else {
			#expect(first.bounds.maxX == 183)
		}

		for width in [150.0, 200] {
			row.style.frame.width = width
			d.changed(row, .all)
			engine.layout()
		}

		#expect(d.orderedNodes.map(LayoutGeometry.init) == cold)
		engine.useCache = false
		d.dirty.insert(.layout)
		engine.layout()
		#expect(d.orderedNodes.map(LayoutGeometry.init) == cold)
	}

	@Test func optionalInstrumentationIsDisabledByDefaultAndSpansAreSelective() {
		let d = Document(size: .init(width: 100, height: 100))
		defer {
			d.close()
		}
		let engine = LayoutEngine(document: d, text: TestTextService())
		_ = d.create(.text, parent: d.root)
		engine.layout()
		#expect(d.metrics.measureCalls == 2)
		#expect(d.metrics.measureVisits == 0)
		#expect(d.timings.isEmpty)
		d.enabledTimingSpans = [.layoutMeasurement, .nodeSnapshots]
		d.dirty.insert(.layout)
		engine.layout()
		_ = d.publishedNodeSnapshots()
		#expect(Set(d.timings.keys) == [.layoutMeasurement, .nodeSnapshots])
	}
}
