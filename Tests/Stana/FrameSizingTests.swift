import Stana
import StanaTesting
import Testing

@Suite @MainActor struct FrameSizingTests {
	@Test(arguments: [true, false])
	func reactiveMaximumMutationUpdatesLayoutWithoutRemounting(horizontal: Bool) throws {
		let frame = STNSignal(STNFrame(minWidth: 12, minHeight: 8))
		let host = STNTestHost(size: .init(width: 100, height: 80))
		host.mount {
			STNBox(properties: .init(layout: .init(frame: frame))) {}
		}
		defer { host.close() }
		let original = try #require(host.nodes.first { $0.kind == "box" })
		#expect(original.bounds.size == STNSize(width: 12, height: 8))
		let ids = host.nodeIDs
		let metrics = host.metrics
		let maximum = horizontal ? \STNFrame.maxWidth : \STNFrame.maxHeight
		let filled = horizontal ? STNSize(width: 100, height: 8) : STNSize(width: 12, height: 80)
		for value in [Double.infinity, 40, .infinity] {
			frame.value[keyPath: maximum] = value
			let node = try #require(host.nodes.first { $0.id == original.id })
			#expect(node.bounds.size == (value == .infinity ? filled : STNSize(width: 12, height: 8)))
		}

		let updates = host.metrics.propertyUpdates
		frame.value[keyPath: maximum] = .infinity
		#expect(host.metrics.propertyUpdates == updates)
		frame.value = STNFrame(minWidth: 12, minHeight: 8)
		#expect(host.nodes.first { $0.id == original.id }?.bounds.size == STNSize(width: 12, height: 8))
		#expect(host.nodeIDs == ids)
		#expect(host.metrics.totalMounts == metrics.totalMounts)
		#expect(host.metrics.builderExecutions == metrics.builderExecutions)
	}
}
