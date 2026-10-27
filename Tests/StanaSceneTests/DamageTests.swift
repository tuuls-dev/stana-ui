import StanaPrimitives
import Testing

@testable import StanaScene

@Test func damageIncludesOldAndNewBounds() {
	var damage = DamageTracker()
	damage.add(.init(width: 10, height: 10))
	damage.add(.init(x: 5, y: 5, width: 10, height: 10))
	#expect(damage.rectangles == [.init(width: 15, height: 15)])
}
