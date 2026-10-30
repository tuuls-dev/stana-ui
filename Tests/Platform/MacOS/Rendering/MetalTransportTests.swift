import Foundation
import StanaCore
import StanaPrimitives
import StanaScene
import Testing

@testable import StanaPlatformMacOS

@MainActor @Test func typedPreparationSharesUnchangedBalancedBranches() throws {
	let document = Document(size: .init(width: 1000, height: 1000))
	defer {
		document.close()
	}

	document.root.bounds = .init(width: 1000, height: 1000)
	var target: NodeRecord!
	STNTransaction.perform {
		for index in 0..<10_000 {
			let node = document.create(.canvas, parent: document.root)
			node.bounds = .init(x: Double(index % 100) * 10, y: Double(index / 100) * 10, width: 10, height: 10)
			node.canvasCommands = [.fill(.init(width: 10, height: 10), .white, 0)]
			if index == 10 {
				target = node
			}
		}
	}
	let builder = SceneBuilder(document: document)
	var planner = ScenePlanner()
	let first = builder.build(surfaceEpoch: 1, backingRevision: 0)
	let firstPlan = planner.prepare(try #require(first.paint))
	target.canvasCommands = [.fill(.init(width: 10, height: 10), .black, 0)]
	document.changed(target, .paint)
	let second = builder.build(surfaceEpoch: 1, backingRevision: first.sceneRevision)
	let secondPlan = planner.prepare(try #require(second.paint))
	#expect(planner.createdBranches <= 20)
	#expect(planner.visitedBranches <= 40)
	#expect(firstPlan.children?.right === secondPlan.children?.right)
	#expect(firstPlan.source == first.paint)
	#expect(firstPlan.source != secondPlan.source)
	let oldCPU = CPUCommandTree(branch: try #require(firstPlan.children))
	let newCPU = CPUCommandTree(branch: try #require(secondPlan.children))
	let unaffected = STNRect(x: 900, y: 900, width: 100, height: 100).cgRect
	#expect(oldCPU.versions(intersecting: unaffected) == newCPU.versions(intersecting: unaffected))
	#expect(newCPU.versions(intersecting: unaffected).count < 1_000)
}

@Test func quadLayoutMatchesThePackagedMetalShader() {
	#expect(MemoryLayout<MetalQuad>.size == 144)
	#expect(MemoryLayout<MetalQuad>.stride == 144)
	#expect(MemoryLayout<MetalQuad>.alignment == 16)
	#expect(MemoryLayout<InlineArray<16, MetalQuad>>.size == 2_304)
	#expect(MemoryLayout<InlineArray<16, MetalQuad>>.stride == 2_304)
	#expect(MemoryLayout<InlineArray<16, MetalQuad>>.alignment == 16)
	#expect(MemoryLayout<MetalQuad>.offset(of: \.rect) == 0)
	#expect(MemoryLayout<MetalQuad>.offset(of: \.uv) == 16)
	#expect(MemoryLayout<MetalQuad>.offset(of: \.color) == 32)
	#expect(MemoryLayout<MetalQuad>.offset(of: \.clip) == 48)
	#expect(MemoryLayout<MetalQuad>.offset(of: \.row0) == 64)
	#expect(MemoryLayout<MetalQuad>.offset(of: \.row1) == 80)
	#expect(MemoryLayout<MetalQuad>.offset(of: \.target) == 96)
	#expect(MemoryLayout<MetalQuad>.offset(of: \.options) == 112)
	#expect(MemoryLayout<MetalQuad>.offset(of: \.mode) == 128)
	#expect(MemoryLayout<MetalQuad>.offset(of: \.linear) == 132)
	#expect(MemoryLayout<MetalQuad>.offset(of: \.sourceLinear) == 136)
	#expect(MemoryLayout<MetalQuad>.offset(of: \.masked) == 140)
}
