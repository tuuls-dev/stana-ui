import StanaPrimitives
import Testing

@testable import StanaCore

@Suite @MainActor struct DocumentTests {
	@Test func movePreservesIdentityAndTransfersLifetimeOwnership() throws {
		let document = Document(size: .init(width: 100, height: 100))
		var a: NodeRecord!
		var b: NodeRecord!
		var child: NodeRecord!
		STNTransaction.perform {
			a = document.create(.box, parent: document.root)
			b = document.create(.box, parent: document.root)
			child = document.create(.text, parent: a)
		}
		let id = child.id
		try document.move(id, to: b.id, at: 0)
		document.remove(a)
		#expect(try document.resolve(id) === child)
		#expect(child.parent === b)
		document.remove(b)
		#expect(throws: STNError.nodeDisposed) { try document.resolve(id) }
		document.close()
	}

	@Test func invalidMovesDoNotPartiallyMutateTheTree() throws {
		let d = Document(size: .init(width: 100, height: 100))
		let a = d.create(.box, parent: d.root)
		let b = d.create(.text, parent: a)
		#expect(throws: STNError.invalidStructure) { try d.move(a.id, to: b.id, at: 0) }
		#expect(throws: STNError.invalidStructure) { try d.move(b.id, to: a.id, at: 2) }
		#expect(a.children.map(\.id) == [b.id])
		#expect(b.parent === a)
		d.close()
	}

	@Test func seededSameParentMovesMatchReferenceOrder() throws {
		let d = Document(size: .init(width: 100, height: 100))
		var reference: [STNNodeID] = []
		STNTransaction.perform {
			for _ in 0..<20 {
				reference.append(d.create(.text, parent: d.root).id)
			}
		}
		var seed: UInt64 = 42

		func random(_ limit: Int) -> Int {
			seed = seed &* 6_364_136_223_846_793_005 &+ 1
			return Int((seed >> 32) % UInt64(limit))
		}

		for _ in 0..<150 {
			let source = random(reference.count)
			let destination = random(reference.count)
			let id = reference.remove(at: source)
			reference.insert(id, at: destination)
			try d.move(id, to: d.root.id, at: destination)
			#expect(d.root.children.map(\.id) == reference)
		}

		d.close()
		#expect(d.metrics.mountedNodes == 0)
	}

	@Test func disposedChildUnregistersFromItsOwner() {
		let parent = LifetimeScope()
		weak var weakChild: LifetimeScope?
		do {
			let child = LifetimeScope()
			weakChild = child
			parent.adopt(child)
			child.dispose()
		}

		#expect(weakChild == nil)
		parent.dispose()
	}
}
