import Foundation
import StanaPrimitives
import Testing

@Test func drawingEqualityUsesVersionNotGeometry() {
	var a = STNGPUDrawing()
	var b = a
	#expect(a == b)
	a.fillRect(.init(width: 10, height: 10), color: .white)
	b.fillRect(.init(width: 10, height: 10), color: .white)
	#expect(a != b)
	#expect(a == a)
}

@Test func currentStepCyclesAndWritableBackdropAreRejected() throws {
	#expect(throws: STNGPUError.self) {
		try STNGPUProgram(
			shader: .metalSource(""),
			resources: ["a": .target(), "output": .target()],
			passes: [
				.compute(
					.init(
						function: "a",
						width: 1,
						bindings: [
							.init(resource: "output", index: 0, stage: .compute),
							.init(resource: "a", index: 1, access: .write, stage: .compute),
						]
					)
				),
				.compute(
					.init(
						function: "b",
						width: 1,
						bindings: [
							.init(resource: "a", index: 0, stage: .compute),
							.init(resource: "output", index: 1, access: .write, stage: .compute),
						]
					)
				),
			]
		)
	}
	#expect(throws: STNGPUError.self) {
		try STNGPUProgram(
			shader: .metalSource(""),
			passes: [
				.render(
					.init(
						vertex: "v",
						fragment: "f",
						bindings: [
							.init(resource: "$backdrop", index: 0, access: .write, stage: .fragment)
						]
					)
				)
			]
		)
	}
	#expect(throws: STNGPUError.self) {
		try STNGPUProgram(
			shader: .metalSource(""),
			passes: [
				.render(
					.init(
						vertex: "v",
						fragment: "f",
						bindings: [
							.init(resource: "output", index: 0, stage: .fragment)
						]
					)
				)
			]
		)
	}
}

@Test func previousStateIsNotACurrentStepCycle() throws {
	let slot = try STNGPUStateSlot(width: 1, height: 1)
	let _ = try STNGPUProgram(
		shader: .metalSource(""),
		resources: ["output": .state(slot)],
		passes: [
			.compute(
				.init(
					function: "step",
					width: 1,
					bindings: [
						.init(resource: "output", index: 0, stage: .compute, previous: true),
						.init(resource: "output", index: 1, access: .write, stage: .compute),
					]
				)
			)
		]
	)
}

@Test func invalidTextureSizesAreRejectedBeforeMultiplication() {
	#expect(throws: STNGPUError.self) {
		try STNGPUTexture(width: .max, height: .max, format: .rgba16Float, data: Data())
	}
}

@Test func affineCompositionAndNormalizedInverseAgree() throws {
	let t = STNAffineTransform.translation(x: 20, y: 30)
		.concatenating(.rotation(radians: 0.8))
		.concatenating(.init(a: -2, b: 0.2, c: 0.5, d: 3))
	let p = STNPoint(x: 7, y: 13)
	let recovered = try #require(t.inverse).applying(to: t.applying(to: p))
	#expect(abs(recovered.x - p.x) < 1e-10)
	#expect(abs(recovered.y - p.y) < 1e-10)
	#expect(STNAffineTransform.scale(x: 0, y: 1).inverse == nil)
	#expect(STNAffineTransform(a: 1e200, d: 1e200).inverse != nil)
}
