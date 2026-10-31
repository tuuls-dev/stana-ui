import StanaCore
import StanaLayout
import StanaPrimitives
import StanaText

enum Workload: String, CaseIterable {
	case cold, sameSize = "same-size", earlyResize = "early-resize", lateResize = "late-resize"
	case batched, wrapping, scrolling, flex
}

@MainActor final class Fixture {
	let document: Document
	let engine: LayoutEngine
	let workload: Workload
	let container: NodeRecord
	var leaves: [NodeRecord] = []
	var initialBounds: [STNRect] = []
	var initialLeafSizes: [STNSize] = []
	let nodeCount: Int
	let flexibleChildCount: Int

	init(workload: Workload, size: Int, text: any TextService) {
		self.workload = workload
		let d = Document(size: .init(width: workload == .flex ? Double(size) * 100 : 800, height: 600))
		document = d
		engine = LayoutEngine(document: d, text: text)
		container = d.create(workload == .sameSize || workload == .flex ? .hStack : .vStack, parent: d.root)
		if workload == .sameSize {
			d.viewport.width = Double(size) * 100
		}

		if workload == .scrolling {
			let scroll = d.create(.scroll, parent: d.root)
			scroll.style.frame = .init(width: 800, height: 10)
			// Move the stack through the normal document path, not a second root.
			try! d.move(container.id, to: scroll.id, at: 0)
		}

		for index in 0..<size {
			let leaf = d.create(workload == .flex ? .spacer : .text, parent: container)
			leaf.text = workload == .wrapping ? String(repeating: "wrapped text ", count: 20) : "label"
			if workload == .sameSize || workload == .batched {
				// Keep output geometry equal with either deterministic or native glyph advances.
				leaf.style.frame = .init(width: 80, height: 30)
			}

			if workload == .flex {
				leaf.style.flex = Double(index % 3 + 1)
				leaf.style.frame = index % 2 == 0 ? .init(height: 10, maxWidth: 30) : .init(height: 10, minWidth: 60)
			}

			leaves.append(leaf)
		}

		nodeCount = d.nodes.count
		flexibleChildCount = workload == .flex ? size : 0
		if workload != .cold {
			engine.layout()
			initialBounds = d.orderedNodes.map(\.bounds)
			initialLeafSizes = leaves.map(\.measured)
		}
	}

	func operate() {
		switch workload {
		case .cold: break
		case .sameSize:
			leaves[leaves.count / 2].text = "other"
			document.changed(leaves[leaves.count / 2], .all)
		case .earlyResize, .lateResize:
			let leaf = workload == .earlyResize ? leaves[0] : leaves[leaves.count - 1]
			leaf.style.font = .system(size: 20)
			document.changed(leaf, .all)
		case .batched:
			STNTransaction.perform {
				for leaf in leaves {
					leaf.text = "other"
					document.changed(leaf, .all)
				}
			}
		case .wrapping:
			document.viewport.width = 240
			document.changed(document.root, .all)
			engine.layout()
			document.viewport.width = 800
			document.changed(document.root, .all)
		case .scrolling:
			let scroll = container.parent!
			scroll.scrollOffset.y = 5
			document.changed(scroll, .all)
		case .flex:
			document.viewport.width += 10
			document.changed(document.root, .all)
		}

		engine.layout()
	}

	func verify() throws {
		func require(_ condition: Bool, _ message: String) throws {
			guard condition else {
				throw Failure("\(workload.rawValue): \(message)")
			}
		}

		try require(document.nodes.count == nodeCount, "node count changed")
		try require(!document.dirty.contains(.layout), "layout did not settle")
		switch workload {
		case .cold:
			try require(leaves.allSatisfy { $0.bounds.size.height > 0 }, "cold leaves not placed")
		case .sameSize, .batched, .wrapping:
			try require(document.orderedNodes.map(\.bounds) == initialBounds, "same-output geometry changed")
		case .earlyResize, .lateResize:
			let index = workload == .earlyResize ? 0 : leaves.count - 1
			try require(
				leaves[index].measured.height > initialLeafSizes[index].height,
				"font size did not change height"
			)
		case .scrolling:
			try require(container.parent!.scrollOffset.y == 5, "offset not applied")
			try require(container.bounds.minY == -5, "content not translated")
		case .flex:
			let sum = leaves.reduce(0) { $0 + $1.measured.width }
			try require(abs(container.measured.width - sum) < 0.000_001, "flex geometry inconsistent")
			for (index, leaf) in leaves.enumerated() {
				try require(
					index % 2 == 0 ? leaf.measured.width <= 30 : leaf.measured.width >= 60,
					"flex bound violated"
				)
			}
		}
	}
}
