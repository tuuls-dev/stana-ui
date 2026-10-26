import Foundation
import Stana
import StanaTesting
import Testing

@MainActor private final class Row {
    nonisolated let id: Int
    let title: STNSignal<String>
    let done = STNSignal(false)
    init(_ id: Int, _ title: String) {
        self.id = id
        self.title = STNSignal(title)
    }
}

@Suite @MainActor struct LifecycleAndIdentityTests {
    @Test func observableRowsPreserveCompositionFocusAndUndoAcrossMoves() throws {
        let a = Row(1, "A")
        let b = Row(2, "B")
        let rows = STNSignal([a, b], equals: { x, y in x.count == y.count && zip(x, y).allSatisfy { $0.0 === $0.1 } })
        let host = STNTestHost()
        host.mount {
            STNVStack {
                STNForEach(observableRows: rows, id: \.id) { row in
                    STNHStack {
                        STNTextField(properties: .init(value: row.title.binding))
                        STNToggle(properties: .init(text: "Done", isOn: row.done.binding))
                    }
                }
            }
        }
        let editor = try #require(host.nodes.first { $0.kind == "textField" && $0.text == "A" })
        try host.focus(editor.id)
        host.insertText("!")
        host.setMarkedText("に", selectedRange: .init(location: 1, length: 0))
        let before = try #require(host.editorState(editor.id))
        let mounts = host.metrics.totalMounts
        a.done.value = true
        rows.value = [b, a]
        #expect(host.editorState(editor.id) == before)
        #expect(host.nodes.first { $0.id == editor.id }?.isFocused == true)
        #expect(host.metrics.totalMounts == mounts)
        host.commitMarkedText()
        #expect(a.title.value == "A!に")
        host.command("undo:")
        #expect(a.title.value == "A!")
        host.close()
    }

    @Test func invalidStructuralPlansLeaveMountedRowsIntact() {
        let a = Row(1, "A")
        let duplicate = Row(1, "Other")
        let rows = STNSignal([a], equals: { _, _ in false })
        let host = STNTestHost()
        host.mount { STNForEach(observableRows: rows, id: \.id) { row in STNText(properties: .init(text: row.title)) } }
        let ids = host.nodeIDs
        rows.value = [a, duplicate]
        #expect(host.nodeIDs == ids)
        #expect(host.errors.last == .duplicateKey)
        rows.value = [duplicate]
        #expect(host.nodeIDs == ids)
        #expect(host.errors.last == .rowIdentityChanged)
        #expect(host.textValues == ["A"])
        host.close()
    }

    @Test func unequalValueRowsReplaceDescendantsButMovesDoNot() {
        struct Item: Equatable {
            let id: Int
            let title: String
        }
        let rows = STNSignal([Item(id: 1, title: "A"), Item(id: 2, title: "B")])
        let host = STNTestHost()
        host.mount { STNVStack { STNForEach(rows, id: \.id) { item in STNText(properties: .init(text: item.title)) } } }
        let a = host.nodes.first { $0.text == "A" }!.id
        rows.value.reverse()
        #expect(host.nodeIDs.contains(a))
        rows.value = [Item(id: 2, title: "B"), Item(id: 1, title: "Changed")]
        #expect(!host.nodeIDs.contains(a))
        #expect(host.textValues.contains("Changed"))
        host.close()
    }

    @Test func mountCallbacksRunAfterPublicationAndStaleHandlesFail() throws {
        let visible = STNSignal(true)
        let host = STNTestHost()
        var handle: STNNodeHandle?
        host.mount {
            STNIf(visible) {
                STNButton(
                    properties: .init(
                        text: "Save",
                        onMount: {
                            handle = $0
                            try? $0.requestFocus()
                        }, onActivate: {}))
            }
        }
        let mounted = try #require(handle)
        #expect(try mounted.bounds().size.width > 0)
        #expect(host.nodes.first { $0.id == mounted.id }?.isFocused == true)
        visible.value = false
        #expect(throws: STNError.nodeDisposed) { try mounted.requestFocus() }
        visible.value = true
        #expect(handle?.id != mounted.id)
        host.close()
    }

    @Test func applicationEffectsObserveACompleteCommitAndCancelOnRemoval() {
        let shown = STNSignal(true)
        let model = STNSignal("initial")
        let events = Events()
        let host = STNTestHost()
        host.mount { STNIf(shown) { ObservingComponent(properties: .init(model: model, events: events)) } }
        model.value = "next"
        #expect(events.values == ["initial", "next"])
        shown.value = false
        #expect(events.disposals == 1)
        model.value = "late"
        #expect(events.values == ["initial", "next"])
        host.close()
        #expect(host.metrics.mountedNodes == 0)
        #expect(host.nodes.isEmpty)
    }
}

@MainActor private final class Events {
    var values: [String] = []
    var disposals = 0
}

@MainActor private struct ObservingComponent: STNComponent {
    struct Properties {
        let model: STNSignal<String>
        let events: Events
    }
    let properties: Properties
    func makeContent(in context: STNComponentContext) -> some STNComponent {
        let subscription = properties.model.subscribe { properties.events.values.append($0) }
        context.own(subscription)
        context.onDispose { properties.events.disposals += 1 }
        STNText(properties: .init(text: properties.model))
    }
}
