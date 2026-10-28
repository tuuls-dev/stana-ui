import Foundation
import StanaCore
import StanaPrimitives
import StanaText
import Testing

@testable import Stana
@testable import StanaScene

@Suite @MainActor struct TextFieldServiceTests {
	@Test func sharedAppearanceOwnsTheBackgroundForConstantAndReactiveInputs() throws {
		let value = STNSignal("")
		let background = STNSignal(STNColor.black)
		let session = MountSession(size: .init(width: 300, height: 100), text: TestTextService())
		mount(session) {
			STNVStack {
				STNTextField(properties: .init(value: value.binding))
				STNTextField(
					properties: .init(
						value: value.binding,
						options: STNTextField.Options(),
						appearance: .init(background: STNColor.black)
					)
				)
				STNTextField(properties: .init(value: value.binding, appearance: .init(background: background)))
			}
		}
		defer { session.close() }
		let nodes = session.document.orderedNodes.filter { $0.kind == .textField }
		#expect(nodes.map { $0.style.background } == [.surface, .black, .black])
		background.value = .accent
		#expect(nodes[2].style.background == .accent)
	}

	@Test func nativeRequestsAreBoundToAnEditorIdentityAndRevision() throws {
		let a = STNSignal("one")
		let b = STNSignal("two")
		let session = MountSession(size: .init(width: 300, height: 100), text: TestTextService())
		mount(session) {
			STNVStack {
				STNTextField(properties: .init(value: a.binding)); STNTextField(properties: .init(value: b.binding))
			}
		}
		defer { session.close() }
		let nodes = session.document.orderedNodes.filter { $0.kind == .textField }
		session.document.setFocus(nodes[1].id)
		session.edit(
			1,
			text: "wrong",
			range: nil,
			selected: .init(),
			expectedRevision: 0,
			expectedIdentity: nodes[0].id.nativeID
		)
		#expect(b.value == "two")
		session.edit(
			1,
			text: "!",
			range: nil,
			selected: .init(),
			expectedRevision: 0,
			expectedIdentity: nodes[1].id.nativeID
		)
		#expect(b.value == "two!")
		session.edit(
			1,
			text: "stale",
			range: nil,
			selected: .init(),
			expectedRevision: 0,
			expectedIdentity: nodes[1].id.nativeID
		)
		#expect(b.value == "two!")
		#expect(session.errors.last == .staleTextPosition)
	}

	@Test func annotationsNeverChangeTheBindingAndStaleAnnotationsAreRejected() throws {
		let value = STNSignal("misspelled")
		let session = MountSession(size: .init(width: 300, height: 100), text: TestTextService())
		mount(session) { STNTextField(properties: .init(value: value.binding)) }
		defer { session.close() }
		let node = try #require(session.document.orderedNodes.first { $0.kind == .textField })
		session.document.setFocus(node.id)
		session.edit(7, text: "[[0,4]]", range: nil, selected: .init(), expectedRevision: 0)
		#expect(value.value == "misspelled")
		#expect(session.editors[node.id]?.undoCount == 0)
		#expect(session.editingPaint(node)?.annotations.count == 1)
		value.value = "new"
		#expect(session.editingPaint(node)?.annotations.isEmpty == true)
		session.edit(7, text: "[[0,4]]", range: nil, selected: .init(), expectedRevision: 0)
		#expect(session.editingPaint(node)?.annotations.isEmpty == true)
	}

	@Test func secureFieldsRejectServiceAnnotationsAndReportInapplicableServices() throws {
		let value = STNSignal("password")
		let session = MountSession(size: .init(width: 300, height: 100), text: TestTextService())
		mount(session) { STNTextField(properties: .init(value: value.binding, secure: true)) }
		defer { session.close() }
		let node = try #require(session.document.orderedNodes.first { $0.kind == .textField })
		session.document.setFocus(node.id)
		session.edit(7, text: "[[0,4]]", range: nil, selected: .init(), expectedRevision: 0)
		#expect(session.editingPaint(node)?.annotations.isEmpty == true)
		#expect(
			session.editorResolution(node.id).features
				.allSatisfy { $0.availability == .inapplicable && $0.isEnabled == false }
		)
		#expect(session.semanticSnapshot.nodes.first { $0.owner == node.id }?.value == nil)
	}

	@Test func alignmentUsesSharedPaintAndHitTestGeometry() throws {
		let value = STNSignal("abc")
		let session = MountSession(size: .init(width: 300, height: 100), text: TestTextService())
		mount(session) {
			STNTextField(
				properties: .init(
					value: value.binding,
					options: STNTextField.Options(alignment: .trailing),
					layout: .init(frame: STNFrame(width: 200))
				)
			)
		}
		defer { session.close() }
		let node = try #require(session.document.orderedNodes.first { $0.kind == .textField })
		let paint = try #require(session.editingPaint(node))
		#expect(paint.offset < 0)
		let start = node.bounds.minX + node.style.padding.leading - paint.offset
		_ = session.pointer(0, at: .init(x: start + 1, y: node.bounds.minY + 10))
		_ = session.pointer(2, at: .init(x: start + 1, y: node.bounds.minY + 10))
		#expect(session.editors[node.id]?.selection.location == 0)
	}
}

@MainActor private func mount(_ session: MountSession, @STNBuilder _ content: () -> STNGroup) {
	session.mount(content)
}
