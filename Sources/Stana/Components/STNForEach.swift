import Foundation
import StanaCore
import StanaPrimitives

/// Keys preserve row scopes. Unequal value items replace descendants; observable
/// reference rows preserve them and must retain the same instance for each key.
@MainActor public struct STNForEach<Item, ID: Hashable>: STNComponent, PrimitiveComponent {
    private let read: () -> [Item]
    private let key: (Item) -> ID
    private let contentEquals: (Item, Item) -> Bool
    private let sameInstance: ((Item, Item) -> Bool)?
    private let content: (Item) -> STNGroup
    public init(
        _ items: STNSignal<[Item]>, id: KeyPath<Item, ID>, contentEquals: @escaping (Item, Item) -> Bool,
        @STNBuilder content: @escaping (Item) -> STNGroup
    ) {
        read = { items.value }
        key = { $0[keyPath: id] }
        self.contentEquals = contentEquals
        sameInstance = nil
        self.content = content
    }
    public init(_ items: STNSignal<[Item]>, id: KeyPath<Item, ID>, @STNBuilder content: @escaping (Item) -> STNGroup)
    where Item: Equatable {
        self.init(items, id: id, contentEquals: { $0 == $1 }, content: content)
    }
    public init(
        _ items: STNComputed<[Item]>, id: KeyPath<Item, ID>, contentEquals: @escaping (Item, Item) -> Bool,
        @STNBuilder content: @escaping (Item) -> STNGroup
    ) {
        read = { items.value }
        key = { $0[keyPath: id] }
        self.contentEquals = contentEquals
        sameInstance = nil
        self.content = content
    }
    public init(_ items: STNComputed<[Item]>, id: KeyPath<Item, ID>, @STNBuilder content: @escaping (Item) -> STNGroup)
    where Item: Equatable {
        self.init(items, id: id, contentEquals: { $0 == $1 }, content: content)
    }
    public init(
        observableRows items: STNSignal<[Item]>, id: KeyPath<Item, ID>,
        @STNBuilder content: @escaping (Item) -> STNGroup
    ) where Item: AnyObject {
        read = { items.value }
        key = { $0[keyPath: id] }
        contentEquals = { $0 === $1 }
        sameInstance = { $0 === $1 }
        self.content = content
    }
    public init(
        observableRows items: STNComputed<[Item]>, id: KeyPath<Item, ID>,
        @STNBuilder content: @escaping (Item) -> STNGroup
    ) where Item: AnyObject {
        read = { items.value }
        key = { $0[keyPath: id] }
        contentEquals = { $0 === $1 }
        sameInstance = { $0 === $1 }
        self.content = content
    }
    public func makeContent(in context: STNComponentContext) -> STNEmpty { return STNEmpty() }
    package func mount(in context: MountContext) {
        let region = context.session.document.create(.group, parent: context.parent)
        region.attachLifetime(to: context.scope)
        let state = RowsState<Item, ID>()
        let observation = ValueObservation(read: read, equals: { _, _ in false }) {
            [weak session = context.session, weak region] items in
            guard let session, let region, region.scope.isAlive else { return }
            let keys = items.map(key)
            guard Set(keys).count == keys.count else {
                session.report(.duplicateKey)
                return
            }
            if let sameInstance {
                for item in items {
                    if let existing = state.rows[key(item)], !sameInstance(existing.item, item) {
                        session.report(.rowIdentityChanged)
                        return
                    }
                }
            }
            let wanted = Set(keys)
            for id in Array(state.rows.keys) where !wanted.contains(id) {
                if let old = state.rows.removeValue(forKey: id) { session.document.remove(old.node) }
            }
            var order: [NodeRecord] = []
            for item in items {
                let id = key(item)
                if let old = state.rows[id], contentEquals(old.item, item) {
                    order.append(old.node)
                    continue
                }
                let row: NodeRecord
                if let old = state.rows[id] {
                    for child in Array(old.node.children) { session.document.remove(child) }
                    old.contentScope.dispose()
                    row = old.node
                } else {
                    row = session.document.create(.group, parent: region)
                }
                let scope = LifetimeScope()
                row.scope.adopt(scope)
                MountContext(session: session, parent: row, scope: scope).mount(content(item))
                state.rows[id] = .init(item: item, node: row, contentScope: scope)
                order.append(row)
            }
            do { try session.document.reorder(region, children: order) } catch { session.report(.invalidStructure) }
        }
        region.scope.own {
            observation.cancel()
            state.rows.removeAll()
        }
        ReactiveRuntime.shared.enqueue(observation)
    }
}

@MainActor private final class RowsState<Item, ID: Hashable> {
    struct Row {
        let item: Item
        let node: NodeRecord
        let contentScope: LifetimeScope
    }
    var rows: [ID: Row] = [:]
}
