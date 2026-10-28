import StanaCore
import StanaPrimitives
import StanaScene
import Testing

@MainActor @Test func oneContentUpdateInTenThousandEntriesRecordsOneLeaf() {
	let document = Document(size: .init(width: 1000, height: 1000))
	document.root.bounds = .init(width: 1000, height: 1000)
	var target: NodeRecord!
	STNTransaction.perform {
		for index in 0..<10_000 {
			let node = document.create(.canvas, parent: document.root)
			node.bounds = .init(x: Double(index % 100) * 10, y: Double(index / 100) * 10, width: 10, height: 10)
			node.canvasCommands = [.fill(.init(width: 10, height: 10), .white, 0)]
			if index == 5000 { target = node }
		}
	}
	let builder = SceneBuilder(document: document)
	let original = builder.build(surfaceEpoch: 1, backingRevision: 0)
	let metrics = document.metrics
	target.canvasCommands = [.fill(.init(width: 10, height: 10), .black, 0)]
	document.changed(target, .paint)
	let next = builder.build(surfaceEpoch: 1, backingRevision: original.sceneRevision)
	#expect(document.metrics.recordedPaintItems - metrics.recordedPaintItems == 1)
	#expect(document.metrics.paintAncestorUpdates - metrics.paintAncestorUpdates == 1)
	#expect(document.metrics.paintIndexUpdates - metrics.paintIndexUpdates == 1)
	#expect(next.damage.count == 1)
	#expect(original.paint?.version != next.paint?.version)
	#expect(original.paint?.children.count == next.paint?.children.count)
	document.close()
}

@MainActor @Test func nestedProjectionWorkIsLinearInDepthAndSnapshotsRemainImmutable() {
	for depth in [128, 256, 512] {
		let document = Document(size: .init(width: 100, height: 100))
		document.root.bounds = .init(width: 100, height: 100)
		var parent = document.root!
		STNTransaction.perform {
			for _ in 0..<(depth - 2) {
				let layer = document.create(.layer, parent: parent)
				layer.style.retained = true
				layer.bounds = document.root.bounds
				parent = layer
			}
		}
		let leaf = document.create(.canvas, parent: parent)
		leaf.bounds = document.root.bounds
		leaf.canvasCommands = [.fill(.init(width: 100, height: 100), .white, 0)]
		let builder = SceneBuilder(document: document)
		let first = builder.build(surfaceEpoch: 1, backingRevision: 0)
		let commands = first.commands
		let before = document.metrics
		leaf.canvasCommands = [.fill(.init(width: 100, height: 100), .black, 0)]
		document.changed(leaf, .paint)
		_ = builder.build(surfaceEpoch: 1, backingRevision: first.sceneRevision)
		#expect(document.metrics.recordedPaintItems - before.recordedPaintItems == 1)
		#expect(document.metrics.paintAncestorUpdates - before.paintAncestorUpdates < depth)
		#expect(first.commands == commands)
		document.close()
	}
}
