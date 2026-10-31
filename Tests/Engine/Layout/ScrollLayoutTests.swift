import StanaCore
import StanaPrimitives
import StanaText
import Testing

@testable import StanaLayout

@Suite @MainActor struct ScrollLayoutTests {
	@Test(arguments: [false, true])
	func shrinkGrowthPaddingAndRemovalNormalizeBothAxes(useCache: Bool) {
		let d = Document(size: .init(width: 500, height: 500))
		defer {
			d.close()
		}
		let engine = LayoutEngine(document: d, text: TestTextService())
		engine.useCache = useCache
		let scroll = d.create(.scroll, parent: d.root)
		scroll.style.frame = .init(width: 100, height: 100)
		scroll.style.padding = .init(top: 7, leading: 11, bottom: 13, trailing: 19)
		let content = d.create(.box, parent: scroll)
		content.style.frame = .init(width: 300, height: 300)
		scroll.scrollOffset = .init(x: 999, y: 999)
		engine.layout()
		#expect(scroll.contentSize == STNSize(width: 300, height: 300))
		#expect(scroll.scrollOffset == STNPoint(x: 230, y: 220))
		#expect(content.bounds.origin == STNPoint(x: -219, y: -213))
		scroll.style.frame = .init(width: 200, height: 180)
		d.changed(scroll, .all)
		engine.layout()
		#expect(scroll.scrollOffset == STNPoint(x: 130, y: 140))
		scroll.style.padding = .zero
		d.changed(scroll, .all)
		engine.layout()
		#expect(scroll.scrollOffset == STNPoint(x: 100, y: 120))
		content.style.frame = .init(width: 50, height: 50)
		d.changed(content, .all)
		engine.layout()
		#expect(scroll.scrollOffset == .zero)
		#expect(content.bounds.origin == .zero)
		scroll.scrollOffset = .init(x: 20, y: 30)
		d.remove(content)
		engine.layout()
		#expect(scroll.contentSize == .zero)
		#expect(scroll.scrollOffset == .zero)
	}

	@Test(arguments: [false, true])
	func wheelAndFocusSharePaddedTerminalOffsetsWithoutNoOpCommits(nested: Bool) {
		let d = Document(size: .init(width: 300, height: 300))
		defer {
			d.close()
		}
		let engine = LayoutEngine(document: d, text: TestTextService())
		d.ensureGeometry = { engine.layout() }
		let outer = d.create(.scroll, parent: d.root)
		outer.style.frame = .init(width: 150, height: 150)
		let scroll = nested ? d.create(.scroll, parent: outer) : outer
		scroll.style.frame = .init(width: 100, height: 100)
		scroll.style.padding = .init(top: 7, leading: 11, bottom: 13, trailing: 19)
		let stack = d.create(.vStack, parent: scroll)
		stack.style.frame.width = 300
		let space = d.create(.box, parent: stack)
		space.style.frame = .init(width: 300, height: 280)
		let button = d.create(.button, parent: stack)
		button.style.frame = .init(width: 300, height: 20)
		button.text = "end"
		engine.layout()
		let point = STNPoint(x: 20, y: 20)
		d.scroll(at: point, dx: -1000, dy: -1000)
		engine.layout()
		let wheel = scroll.scrollOffset
		#expect(wheel == STNPoint(x: 230, y: 220))
		scroll.scrollOffset = .zero
		d.changed(scroll, .all)
		engine.layout()
		d.setFocus(button.id)
		#expect(scroll.scrollOffset == wheel)
		#expect(outer.scrollOffset == (nested ? .zero : wheel))
		d.dirty = []
		let before = d.metrics
		d.scroll(at: point, dx: -1, dy: -1)
		#expect(scroll.scrollOffset == wheel)
		#expect(d.metrics == before)
		#expect(d.dirty.isEmpty)
	}
}
