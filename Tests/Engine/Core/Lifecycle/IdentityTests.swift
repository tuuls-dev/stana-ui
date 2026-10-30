import Foundation
import StanaCore
import StanaPrimitives
import Testing

@Test func concurrentIdentityReservationsAreUniqueAndProducerMonotonic() async {
	let allocator = IdentityAllocator()
	let values = await withTaskGroup(of: [UInt64].self, returning: [UInt64].self) { group in
		for _ in 0..<16 {
			group.addTask {
				(0..<4_096).map { _ in allocator.next() }
			}
		}

		var all: [UInt64] = []
		for await producer in group {
			#expect(zip(producer, producer.dropFirst()).allSatisfy { $0 < $1 })
			all.append(contentsOf: producer)
		}

		return all
	}
	#expect(Set(values).count == 65_536)
	#expect(values.min() == 1)
	#expect(values.max() == 65_536)
}

@Test func finalIdentityReservationDoesNotWrap() {
	let allocator = IdentityAllocator(startingAt: .max - 2)
	#expect(allocator.next() == UInt64.max - 1)
	#expect(allocator.next() == UInt64.max)
	#expect(MemoryLayout<RenderVersion>.size == 8)
	#expect(MemoryLayout<DocumentID>.size == 8)
	#expect(MemoryLayout<STNNodeID>.size == 16)
}

@MainActor @Test func adoptionTokensDoNotAliasChildResources() {
	let parent = LifetimeScope()
	let child = LifetimeScope()
	var cancelled = 0
	let childResource = child.own { cancelled += 1 }
	let adoption = parent.adopt(child)
	#expect(childResource != adoption)
	child.disown(childResource)
	parent.dispose()
	#expect(!child.isAlive)
	#expect(cancelled == 0)
}

@MainActor @Test func childDisposalDisownsOnlyItsOwnAdoption() {
	let parent = LifetimeScope()
	let first = LifetimeScope()
	let second = LifetimeScope()
	parent.adopt(first)
	parent.adopt(second)
	first.dispose()
	parent.dispose()
	#expect(!first.isAlive)
	#expect(!second.isAlive)
}

@Test func copiedResourcesPreserveIdentityAndIndependentResourcesDoNotAlias() {
	let data = Data([1, 2, 3, 4])
	let first = STNGPUBuffer(data: data)
	let copy = first
	let independent = STNGPUBuffer(data: data)
	#expect(first == copy)
	#expect(first != independent)
	#expect(first.version != independent.version)
}

@Test func identityExhaustionFailsBeforeReuse() async {
	await #expect(processExitsWith: .failure) {
		let allocator = IdentityAllocator(startingAt: .max - 1)
		_ = allocator.next()
		_ = allocator.next()
	}
}

@Test func revisionExhaustionFailsBeforeReuse() async {
	await #expect(processExitsWith: .failure) {
		var revision = UInt64.max
		nextRevision(&revision)
	}
}
