import StanaPrimitives
import Testing

@testable import StanaLayout

@Test func constraintsClampFiniteSizes() {
	let constraints = STNConstraints(minWidth: 20, maxWidth: 100, maxHeight: 40)
	#expect(constraints.clamp(.init(width: 5, height: 200)) == STNSize(width: 20, height: 40))
}
