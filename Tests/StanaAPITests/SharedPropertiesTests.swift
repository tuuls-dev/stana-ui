import Foundation
import StanaCore
import StanaPrimitives
import StanaTesting
import StanaText
import Testing

@testable import Stana

@Suite @MainActor struct SharedPropertiesTests {
	@Test func emptyAndPartialGroupsPreserveComponentDefaults() {
		let value = STNSignal("")
		let session = MountSession(size: .init(width: 800, height: 600), text: TestTextService())
		mountShared(session) {
			STNGroupForDefaults(value: value.binding)
		}
		defer { session.close() }
		let buttons = session.document.orderedNodes.filter { $0.kind == .button }
		let fields = session.document.orderedNodes.filter { $0.kind == .textField }
		#expect(buttons[0].style == buttons[1].style)
		#expect(buttons[0].style.padding == .init(top: 7, leading: 14, bottom: 7, trailing: 14))
		#expect(fields[0].style == fields[1].style)
		#expect(fields[1].style.padding == .init(top: 7, leading: 8, bottom: 7, trailing: 8))
		#expect(fields[1].style.background == .surface)
		#expect(fields[1].style.borderWidth == 1)
		#expect(fields[1].style.cornerRadius == 5)
		#expect(fields[2].style.background == .black)
		#expect(fields[2].style.borderWidth == 1)
		#expect(fields[2].style.cornerRadius == 5)
		#expect(session.document.orderedNodes.first { $0.kind == .scroll }?.style.clip == true)
		#expect(session.document.orderedNodes.first { $0.kind == .canvas }?.style.clip == false)
	}

	@Test func conversionIsLazyAndSharedSourcesUpdateEachMountedNode() {
		let size = STNSignal(13.0)
		var evaluations = 0
		let font = STNComputed {
			evaluations += 1
			return STNFont.system(size: size.value)
		}
		let style = STNTextProperties(font: font)
		#expect(evaluations == 0)
		let host = STNTestHost()
		host.mount {
			STNVStack {
				STNText(properties: .init(text: "First", textStyle: style))
				STNButton(properties: .init(text: "Second", textStyle: style, onActivate: {}))
			}
		}
		defer { host.close() }
		let ids = host.nodeIDs
		let metrics = host.metrics
		let original = host.nodes.first { $0.kind == "text" }?.bounds
		size.value = 26
		#expect(evaluations == 2)
		#expect(host.nodeIDs == ids)
		#expect(host.metrics.totalMounts == metrics.totalMounts)
		#expect(host.metrics.builderExecutions == metrics.builderExecutions)
		#expect(host.nodes.first { $0.kind == "text" }?.bounds != original)
		let updates = host.metrics.propertyUpdates
		size.value = 26
		#expect(host.metrics.propertyUpdates == updates)
	}

	@Test func reactiveLayoutMovesSiblingsAndRefreshesHitTestingAndSemantics() throws {
		let padding = STNSignal(STNInsets(0))
		let frame = STNSignal(STNFrame(width: 80, height: 40))
		let host = STNTestHost(size: .init(width: 500, height: 200))
		var activations = 0
		host.mount {
			STNHStack {
				STNButton(
					properties: .init(
						text: "Resize",
						layout: .init(padding: padding, frame: frame),
						onActivate: {}
					)
				)
				STNButton(properties: .init(text: "Target", onActivate: { activations += 1 }))
			}
		}
		defer { host.close() }
		let original = try #require(host.nodes.first { $0.text == "Target" })
		let ids = host.nodeIDs
		let metrics = host.metrics
		STNTransaction.perform {
			padding.value = STNInsets(12)
			frame.value = STNFrame(width: 180, height: 70)
			#expect(host.nodes.first { $0.id == original.id }?.bounds == original.bounds)
		}
		let target = try #require(host.nodes.first { $0.id == original.id })
		#expect(target.bounds.minX == original.bounds.minX + 100)
		#expect(host.semantics.nodes.first { $0.owner == target.id }?.bounds == target.bounds)
		host.click(at: .init(x: target.bounds.minX + 3, y: target.bounds.minY + 3))
		#expect(activations == 1)
		#expect(host.nodeIDs == ids)
		#expect(host.metrics.totalMounts == metrics.totalMounts)
		#expect(host.metrics.builderExecutions == metrics.builderExecutions)
		#expect(host.metrics.measureCalls > metrics.measureCalls)
	}

	@Test func fontAndPaddingInvalidateAncestorIntrinsicMeasurements() throws {
		let font = STNSignal(STNFont.system(size: 13))
		let padding = STNSignal(STNInsets(0))
		let session = MountSession(size: .init(width: 500, height: 300), text: TestTextService())
		mountShared(session) {
			STNVStack {
				STNBox {
					STNText(
						properties: .init(
							text: "Measure",
							layout: .init(padding: padding),
							textStyle: .init(font: font)
						)
					)
				}
				STNText(properties: .init(text: "Sibling"))
			}
		}
		defer { session.close() }
		let box = try #require(session.document.orderedNodes.first { $0.kind == .box })
		let sibling = try #require(session.document.orderedNodes.first { $0.text == "Sibling" })
		let before = box.bounds
		let previousY = sibling.bounds.minY
		font.value = .system(size: 26)
		#expect(box.bounds.size.height > before.size.height)
		let larger = box.bounds
		padding.value = STNInsets(10)
		#expect(box.bounds.size.height == larger.size.height + 20)
		#expect(box.bounds.size.width == larger.size.width + 20)
		#expect(sibling.bounds.minY > previousY)
	}

	@Test func sharedEditorStylesPreserveEditingStateAndOptionsDoNotOverwriteThem() throws {
		let value = STNSignal("A")
		let options = STNSignal(STNTextField.Options())
		let font = STNSignal(STNFont.system())
		let padding = STNSignal(STNInsets(8))
		let frame = STNSignal(STNFrame(width: 200))
		let color = STNSignal(STNColor.black)
		let border = STNSignal(2.0)
		let radius = STNSignal(8.0)
		let session = MountSession(size: .init(width: 500, height: 200), text: TestTextService())
		mountShared(session) {
			STNTextField(
				properties: .init(
					value: value.binding,
					options: options,
					layout: .init(padding: padding, frame: frame),
					textStyle: .init(font: font, foreground: color),
					appearance: .init(background: color, borderColor: color, borderWidth: border, cornerRadius: radius)
				)
			)
		}
		defer { session.close() }
		let node = try #require(session.document.orderedNodes.first { $0.kind == .textField })
		session.document.setFocus(node.id)
		session.edit(1, text: "!", range: nil, selected: .init())
		session.edit(2, text: "に", range: nil, selected: .init(location: 1, length: 0))
		let editor = try #require(session.editors[node.id])
		let selection = editor.selection
		let revision = editor.revision
		let undo = editor.undoCount
		let geometry = try #require(session.editingPaint(node)).selectionEnd
		let mounts = session.document.metrics.totalMounts
		STNTransaction.perform {
			font.value = .system(size: 24)
			padding.value = STNInsets(14)
			frame.value = STNFrame(width: 300)
			color.value = .accent
			border.value = 3
			radius.value = 12
			options.value.alignment = .trailing
		}
		#expect(session.editors[node.id] === editor)
		#expect(session.document.focused == node.id)
		#expect(editor.markedText != nil)
		#expect(editor.selection == selection)
		#expect(editor.revision == revision)
		#expect(editor.undoCount == undo)
		#expect(node.style.foreground == .accent)
		#expect(node.style.background == .accent)
		#expect(node.style.borderColor == .accent)
		#expect(node.style.borderWidth == 3)
		#expect(node.style.cornerRadius == 12)
		#expect(node.bounds.size.width == 300)
		#expect(session.editingPaint(node)?.selectionEnd != geometry)
		#expect(session.document.metrics.totalMounts == mounts)
		options.value.placeholderColor = .white
		#expect(node.style.background == .accent)
		#expect(node.style.foreground == .accent)
	}

	@Test func disposedSharedPropertiesStopObservingTheirSources() {
		let shown = STNSignal(true)
		let font = STNSignal(STNFont.system())
		let frame = STNSignal(STNFrame(width: 100))
		let host = STNTestHost()
		var mounts = 0
		host.mount {
			STNIf(shown) {
				STNText(
					properties: .init(
						text: "Scoped",
						layout: .init(frame: frame),
						textStyle: .init(font: font),
						lifecycle: .init(onMount: { _ in mounts += 1 })
					)
				)
			}
		}
		defer { host.close() }
		#expect(mounts == 1)
		shown.value = false
		let updates = host.metrics.propertyUpdates
		font.value = .system(size: 30)
		frame.value = STNFrame(width: 200)
		#expect(host.metrics.propertyUpdates == updates)
		#expect(!host.textValues.contains("Scoped"))
	}
}

@MainActor private struct STNGroupForDefaults: STNComponent {
	let value: STNBinding<String>

	func makeContent(in context: STNComponentContext) -> some STNComponent {
		STNButton(properties: .init(text: "Default", onActivate: {}))
		STNButton(
			properties: .init(
				text: "Default",
				layout: .init(),
				textStyle: .init(),
				appearance: .init(),
				interaction: .init(),
				lifecycle: .init(),
				onActivate: {}
			)
		)
		STNTextField(properties: .init(value: value))
		STNTextField(properties: .init(value: value, layout: .init(), appearance: .init(), interaction: .init()))
		STNTextField(properties: .init(value: value, appearance: .init(background: STNColor.black)))
		STNScrollView {}
		STNCanvas(properties: .init(drawing: STNDrawing(), appearance: .init(clip: false)))
	}
}

@MainActor private func mountShared(_ session: MountSession, @STNBuilder _ content: () -> STNGroup) {
	session.mount(content)
}
