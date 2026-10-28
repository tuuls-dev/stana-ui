import Foundation
import StanaCore
import StanaPrimitives
import StanaScene
import Testing

@testable import StanaPlatformMacOS

@MainActor @Test func nativeTransportSendsOnlyChangedBalancedBranches() throws {
	let document = Document(size: .init(width: 1000, height: 1000))
	defer { document.close() }
	document.root.bounds = .init(width: 1000, height: 1000)
	var target: NodeRecord!
	STNTransaction.perform {
		for index in 0..<10_000 {
			let node = document.create(.canvas, parent: document.root)
			node.bounds = .init(x: Double(index % 100) * 10, y: Double(index / 100) * 10, width: 10, height: 10)
			node.canvasCommands = [.fill(.init(width: 10, height: 10), .white, 0)]
			if index == 10 { target = node }
		}
	}
	let builder = SceneBuilder(document: document), encoder = MetalSceneEncoder()
	let first = builder.build(surfaceEpoch: 1, backingRevision: 0)
	_ = try encoder.encode(first)
	target.canvasCommands = [.fill(.init(width: 10, height: 10), .black, 0)]
	document.changed(target, .paint)
	let data = try encoder.encode(builder.build(surfaceEpoch: 1, backingRevision: first.sceneRevision))
	let payload = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
	let objects = try #require(payload["objects"] as? [String: Any])
	#expect(objects.count <= 20)
	#expect(data.count < 10_000)
}
