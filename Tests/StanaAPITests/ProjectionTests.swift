import Stana
import StanaTesting
import Testing

@Suite @MainActor struct ProjectionTests {
	@Test func backgroundAndOpacityChangesDoNotMeasure() {
		let background = STNSignal(STNColor.surface)
		let opacity = STNSignal(1.0)
		let host = STNTestHost()
		host.mount {
			STNBox(properties: .init(padding: 12, background: background, opacity: opacity)) {
				STNText(properties: .init(text: "Retained"))
			}
		}
		_ = host.render()
		let measures = host.metrics.measureCalls
		background.value = .accent
		opacity.value = 0.5
		#expect(host.metrics.measureCalls == measures)
		#expect(host.needsDisplay)
		#expect(host.render() != nil)
		host.close()
	}

	@Test func resizingBackToAnEarlierProposalRestoresChildMeasurements() throws {
		let host = STNTestHost(size: .init(width: 100, height: 300))
		host.mount {
			STNVStack {
				STNText(properties: .init(text: "A sufficiently long text paragraph that wraps at narrow widths"))
			}
		}
		let original = try #require(host.nodes.first { $0.kind == "text" }).bounds
		host.resize(to: .init(width: 200, height: 300))
		#expect(host.nodes.first { $0.kind == "text" }?.bounds != original)
		host.resize(to: .init(width: 100, height: 300))
		#expect(host.nodes.first { $0.kind == "text" }?.bounds == original)
		host.close()
	}

	@Test func semanticLabelChangeNeedsNoPaintOrLayout() {
		let label = STNSignal("First")
		let host = STNTestHost()
		host.mount { STNButton(properties: .init(text: "Visible", accessibility: .init(label: label), onActivate: {})) }
		_ = host.render()
		let measures = host.metrics.measureCalls
		let mounts = host.metrics.totalMounts
		label.value = "Second"
		#expect(!host.needsDisplay)
		#expect(host.render() == nil)
		#expect(host.metrics.measureCalls == measures)
		#expect(host.metrics.totalMounts == mounts)
		#expect(host.semantics.nodes.contains { $0.role == .button && $0.label == "Second" })
		host.close()
	}

	@Test func nestedPaddingAndFrameHaveFixedGeometry() throws {
		let host = STNTestHost(size: .init(width: 300, height: 200))
		host.mount {
			STNBox(properties: .init(padding: 10, frame: .init(width: 100, height: 80), background: .surface)) {
				STNBox(properties: .init(padding: 5, frame: .init(width: 50, height: 40), background: .accent)) {
					STNText(properties: .init(text: "Hi"))
				}
			}
		}
		let boxes = host.nodes.filter { $0.kind == "box" }
		#expect(boxes[0].bounds == .init(width: 100, height: 80))
		#expect(boxes[1].bounds == .init(x: 10, y: 10, width: 50, height: 40))
		#expect(try #require(host.nodes.first { $0.kind == "text" }).bounds.origin == .init(x: 15, y: 15))
		host.close()
	}

	@Test func pointerAndKeyboardActivationShareOneAction() throws {
		let host = STNTestHost()
		var activations = 0
		host.mount { STNButton(properties: .init(text: "Press", onActivate: { activations += 1 })) }
		let button = try #require(host.nodes.first { $0.kind == "button" })
		host.click(at: .init(x: button.bounds.minX + 3, y: button.bounds.minY + 3))
		#expect(activations == 1)
		try host.activate(button.id)
		#expect(activations == 2)
		host.close()
	}

	@Test func collectingBatchRejectsLiveDocumentQueries() {
		let host = STNTestHost()
		let text = STNSignal("Old")
		host.mount { STNText(properties: .init(text: text)) }
		STNTransaction.perform {
			text.value = "New"
			#expect(host.textValues == ["Old"])
			#expect(throws: STNError.transactionInProgress) { try host.queryNodes() }
		}
		#expect(host.textValues == ["New"])
		host.close()
	}

	@Test func droppedScenePromotesToFullDamage() throws {
		let host = STNTestHost(size: .init(width: 300, height: 200))
		let text = STNSignal("A")
		host.mount { STNText(properties: .init(text: text)) }
		_ = host.render()
		text.value = "B"
		_ = host.render(acknowledge: false)
		text.value = "C"
		let frame = try #require(host.render())
		#expect(frame.damage == [.init(width: 300, height: 200)])
		host.close()
	}

	@Test func disabledAndHiddenNodesCannotActivate() throws {
		let host = STNTestHost()
		let enabled = STNSignal(true)
		var count = 0
		host.mount { STNButton(properties: .init(text: "Action", isEnabled: enabled, onActivate: { count += 1 })) }
		let id = try #require(host.nodes.first { $0.kind == "button" }).id
		enabled.value = false
		try host.activate(id)
		#expect(count == 0)
		#expect(host.semantics.nodes.first { $0.owner == id }?.isDisabled == true)
		#expect(throws: STNError.notFocusable) { try host.focus(id) }
		host.close()
	}

	@Test func opacityDoesNotHideSemanticsButHiddenAndInertDoRestrictInteraction() {
		let host = STNTestHost()
		host.mount {
			STNVStack {
				STNSpacer()
				STNBox(properties: .init(opacity: 0)) {
					STNButton(properties: .init(text: "Transparent", onActivate: {}))
				}
				STNBox(properties: .init(visibility: .hidden)) {
					STNButton(properties: .init(text: "Hidden", onActivate: {}))
				}
				STNBox(properties: .init(inert: true)) { STNButton(properties: .init(text: "Inert", onActivate: {})) }
			}
		}
		#expect(host.semantics.nodes.contains { $0.label == "Transparent" && !$0.isDisabled })
		#expect(!host.semantics.nodes.contains { $0.label == "Hidden" })
		#expect(host.semantics.nodes.contains { $0.label == "Inert" && $0.isDisabled })
		#expect(!host.semantics.nodes.contains { $0.role == .group })
		host.close()
	}
}
