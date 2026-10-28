import Stana
import StanaTesting
import Testing

@Suite @MainActor struct ComponentTests {
	@Test func leafUpdateDoesNotRemount() {
		let host = STNTestHost()
		let count = STNSignal(0)
		host.mount {
			STNVStack {
				STNText(properties: .init(text: count.map { "Count: \($0)" }))
				STNText(properties: .init(text: "Static"))
			}
		}
		let ids = host.nodeIDs
		let metrics = host.metrics
		count.value = 1
		#expect(host.nodeIDs == ids)
		#expect(host.metrics.totalMounts == metrics.totalMounts)
		#expect(host.metrics.builderExecutions == metrics.builderExecutions)
		#expect(host.textValues.contains("Count: 1"))
		host.close()
	}

	@Test func textBindingAndConditionalDisposal() throws {
		let host = STNTestHost()
		let name = STNSignal("Hi")
		let visible = STNSignal(true)
		host.mount {
			STNVStack {
				STNIf(visible) { STNTextField(properties: .init(value: name.binding)) }
				STNText(properties: .init(text: name))
			}
		}
		let field = try #require(host.nodes.first { $0.kind == "textField" })
		try host.focus(field.id)
		host.insertText("!")
		#expect(name.value == "Hi!")
		visible.value = false
		#expect(!host.nodeIDs.contains(field.id))
		host.close()
	}
}
