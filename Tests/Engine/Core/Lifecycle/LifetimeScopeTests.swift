import StanaPrimitives
import Testing

@testable import StanaCore

private final class ResourceProbe {}

@Suite @MainActor struct LifetimeScopeTests {
	@Test func disownPreservesRemainingRegistrationOrder() {
		let scope = LifetimeScope()
		var log: [Int] = []
		let tokens = (0...6).map { value in scope.own { log.append(value) } }
		for index in [0, 3, 6, 3] {
			scope.disown(tokens[index])
		}

		scope.disown(ResourceToken())
		#expect(log.isEmpty)
		scope.dispose()
		scope.dispose()
		#expect(log == [1, 2, 4, 5])
	}

	@Test func disownOnlyRegistrationAllowsReuse() {
		let scope = LifetimeScope()
		var log: [Int] = []
		let token = scope.own { log.append(0) }
		scope.disown(token)
		scope.own { log.append(1) }
		scope.own { log.append(2) }
		scope.dispose()
		#expect(log == [1, 2])
	}

	@Test func disownReleasesCapturedResourcesImmediately() {
		let scope = LifetimeScope()
		var probe: ResourceProbe? = ResourceProbe()
		weak let weakProbe = probe
		var cancellations = 0
		let token = scope.own { [probe] in
			withExtendedLifetime(probe) {}
			cancellations += 1
		}
		probe = nil
		#expect(weakProbe != nil)
		scope.disown(token)
		#expect(weakProbe == nil)
		#expect(scope.isAlive)
		#expect(cancellations == 0)
		scope.dispose()
		#expect(cancellations == 0)
	}

	@Test func disposalUsesDetachedOrderedSnapshot() {
		let scope = LifetimeScope()
		var log: [String] = []
		var tokenB: ResourceToken!
		scope.own {
			#expect(!scope.isAlive)
			log.append("A")
			scope.dispose()
			scope.disown(tokenB)
			scope.own {
				#expect(!scope.isAlive)
				log.append("X")
			}
		}
		tokenB = scope.own {
			#expect(!scope.isAlive)
			log.append("B")
		}
		scope.own {
			#expect(!scope.isAlive)
			log.append("C")
		}
		scope.onDispose { log.append("cleanup1") }
		scope.onDispose { log.append("cleanup2") }
		STNTransaction.perform {
			scope.dispose()
			#expect(log == ["A", "X", "B", "C"])
		}
		#expect(log == ["A", "X", "B", "C", "cleanup1", "cleanup2"])
		scope.dispose()
		#expect(log == ["A", "X", "B", "C", "cleanup1", "cleanup2"])
	}

	@Test func adoptionHandlesDeadScopes() {
		let deadOwner = LifetimeScope()
		deadOwner.dispose()
		let liveChild = LifetimeScope()
		var cancellations = 0
		liveChild.own { cancellations += 1 }
		deadOwner.adopt(liveChild)
		#expect(!liveChild.isAlive)
		#expect(cancellations == 1)

		let liveOwner = LifetimeScope()
		var deadChild: LifetimeScope? = LifetimeScope()
		weak let weakChild = deadChild
		deadChild!.own { cancellations += 1 }
		deadChild!.dispose()
		liveOwner.adopt(deadChild!)
		deadChild = nil
		#expect(weakChild == nil)
		#expect(liveOwner.isAlive)
		liveOwner.dispose()

		deadOwner.adopt(liveChild)
		deadOwner.dispose()
		liveChild.dispose()
		#expect(cancellations == 2)
	}

	@Test func adoptedChildrenUnregisterWithoutAffectingSiblings() {
		let parent = LifetimeScope()
		let a = LifetimeScope()
		var b: LifetimeScope? = LifetimeScope()
		let c = LifetimeScope()
		weak let weakB = b
		var cancellations = [0, 0, 0]
		a.own { cancellations[0] += 1 }
		b!.own { cancellations[1] += 1 }
		c.own { cancellations[2] += 1 }
		parent.adopt(a)
		parent.adopt(b!)
		parent.adopt(c)
		b!.dispose()
		b = nil
		#expect(weakB == nil)
		#expect(parent.isAlive)
		#expect(cancellations == [0, 1, 0])
		parent.dispose()
		#expect(!a.isAlive)
		#expect(!c.isAlive)
		#expect(cancellations == [1, 1, 1])
	}

	@Test func wideRegistryChurnPreservesOrderAndReleasesEntries() {
		let scope = LifetimeScope()
		var log: [Int] = []
		let tokens = (0..<10_000).map { value in scope.own { log.append(value) } }
		for index in stride(from: 0, to: tokens.count, by: 2) {
			scope.disown(tokens[index])
		}

		for value in 10_000..<11_000 {
			scope.own { log.append(value) }
		}

		#expect(log.isEmpty)
		scope.dispose()
		let expected = Array(stride(from: 1, to: 10_000, by: 2)) + Array(10_000..<11_000)
		#expect(log == expected)
	}
}
