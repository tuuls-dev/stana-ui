import Foundation

@MainActor package class GraphNode {
    enum Phase { case idle, validating, evaluating }
    struct Edge {
        let node: GraphNode
        let revision: UInt64
    }
    final class WeakNode {
        weak var value: GraphNode?
        init(_ value: GraphNode) { self.value = value }
    }
    var revision: UInt64 = 0
    var attempt: UInt64 = 0
    var stale = true
    var phase = Phase.idle
    var dependencies: [Edge] = []
    var dependents: [ObjectIdentifier: WeakNode] = [:]
    var reads: [Edge] = []
    var readIDs: Set<ObjectIdentifier> = []
    var invalidated: (() -> Void)?
    let name: String
    init(name: String) { self.name = name }
    // Mounted subscriptions detach explicitly. This is only the fallback for
    // demand-only computed objects that never belonged to a mounted scope.
    isolated deinit { detach() }
    func demand() {}
    func trackRead() {
        let caller = ReactiveRuntime.shared.stack.last
        demand()
        if let caller, caller.readIDs.insert(ObjectIdentifier(self)).inserted {
            caller.reads.append(Edge(node: self, revision: revision))
        }
    }
    func invalidate() {
        var work = Array(dependents.values.compactMap(\.value))
        var visited: Set<ObjectIdentifier> = []
        while let node = work.popLast() {
            guard visited.insert(ObjectIdentifier(node)).inserted else { continue }
            node.stale = true
            node.invalidated?()
            work.append(contentsOf: node.dependents.values.compactMap(\.value))
        }
    }
    func detach() {
        for edge in dependencies { edge.node.dependents.removeValue(forKey: ObjectIdentifier(self)) }
        dependencies.removeAll()
    }
    func installReads() {
        dependencies = reads
        reads.removeAll()
        readIDs.removeAll()
        for edge in dependencies { edge.node.dependents[ObjectIdentifier(self)] = WeakNode(self) }
    }
}

@MainActor package final class ValueNode<Value>: GraphNode {
    var cache: Value?
    let equals: (Value, Value) -> Bool
    let compute: (() -> Value)?
    init(value: Value, equals: @escaping (Value, Value) -> Bool) {
        cache = value
        self.equals = equals
        compute = nil
        super.init(name: "signal")
        stale = false
    }
    init(compute: @escaping () -> Value, equals: @escaping (Value, Value) -> Bool) {
        self.compute = compute
        self.equals = equals
        super.init(name: "computed")
    }
    func read() -> Value {
        trackRead()
        return cache!
    }
    func write(_ value: Value) {
        let runtime = ReactiveRuntime.shared
        runtime.assertCanMutate("signal write")
        guard !compare(cache!, value) else { return }
        runtime.batch {
            cache = value
            bump(&revision)
            invalidate()
        }
    }
    override func demand() {
        guard compute != nil else { return }
        precondition(
            phase != .evaluating,
            "Stana: active computed dependency cycle: \((ReactiveRuntime.shared.stack.map(\.name) + [name]).joined(separator: " → "))"
        )
        if phase == .validating {
            evaluate()
            return
        }
        guard stale else { return }
        guard cache != nil else {
            evaluate()
            return
        }
        phase = .validating
        bump(&attempt)
        let ticket = attempt
        let oldTrace = dependencies
        for edge in oldTrace {
            if edge.node.phase != .idle {
                evaluate()
                return
            }
            edge.node.demand()
            if ticket != attempt {
                demand()
                return
            }
            if edge.node.revision != edge.revision {
                evaluate()
                return
            }
        }
        stale = false
        phase = .idle
    }
    private func evaluate() {
        bump(&attempt)
        phase = .evaluating
        detach()
        reads.removeAll()
        readIDs.removeAll()
        let runtime = ReactiveRuntime.shared
        precondition(runtime.stack.count < 1024, "Stana: reactive depth budget exceeded")
        runtime.stack.append(self)
        let candidate = compute!()
        _ = runtime.stack.popLast()
        installReads()
        if cache == nil || !compare(cache!, candidate) {
            cache = candidate
            bump(&revision)
        }
        runtime.computedEvaluations += 1
        stale = false
        phase = .idle
    }
    private func compare(_ a: Value, _ b: Value) -> Bool {
        ReactiveRuntime.shared.pureDepth += 1
        defer { ReactiveRuntime.shared.pureDepth -= 1 }
        return equals(a, b)
    }
}

@MainActor package func bump(_ value: inout UInt64) {
    precondition(value < .max, "Stana: reactive revision exhausted")
    value += 1
}

@MainActor package final class ReactiveRuntime {
    package static let shared = ReactiveRuntime()
    var stack: [GraphNode] = []
    var pureDepth = 0
    var depth = 0
    var flushing = false
    var pending: [ObjectIdentifier: Observation] = [:]
    var ordered: [ObjectIdentifier] = []
    var commits: [UUID: () -> Void] = [:]
    var effects: [() -> Void] = []
    var computedEvaluations = 0
    var observationSequence: UInt64 = 0
    package var isCollecting: Bool { depth > 0 }
    package func assertCanMutate(_ operation: String) {
        precondition(
            stack.isEmpty && pureDepth == 0,
            "Stana: forbidden \(operation) during pure evaluation: \(stack.map(\.name).joined(separator: " → "))")
    }
    package func batch(_ body: () -> Void) {
        depth += 1
        body()
        depth -= 1
        if depth == 0 && !flushing { flush() }
    }
    package func enqueue(_ observation: Observation) {
        let id = ObjectIdentifier(observation)
        if pending.updateValue(observation, forKey: id) == nil { ordered.append(id) }
    }
    package func afterCommit(_ body: @escaping () -> Void) {
        effects.append(body)
        if depth == 0 && !flushing { flush() }
    }
    package func scheduleCommit(id: UUID, _ body: @escaping () -> Void) {
        commits[id] = body
        if depth == 0 && !flushing { flush() }
    }
    func flush() {
        flushing = true
        defer { flushing = false }
        var work = 0
        repeat {
            while !ordered.isEmpty {
                let ids = ordered
                ordered.removeAll()
                let observations = ids.compactMap { pending.removeValue(forKey: $0) }.sorted {
                    $0.sequence < $1.sequence
                }
                // All demands settle before any property/structural publication.
                let deliveries = observations.compactMap { $0.prepare() }
                for deliver in deliveries { deliver() }
                work += observations.count
                precondition(work < 100_000, "Stana: stabilization work budget exceeded")
            }
            let publish = commits.values
            commits.removeAll()
            for commit in publish { commit() }
            work += publish.count
            precondition(work < 100_000, "Stana: publication work budget exceeded")
            if !ordered.isEmpty || !commits.isEmpty { continue }
            let callbacks = effects
            effects.removeAll()
            for effect in callbacks { effect() }
            work += callbacks.count + 1
            precondition(work < 100_000, "Stana: effect feedback budget exceeded")
        } while !ordered.isEmpty || !commits.isEmpty || !effects.isEmpty
    }
}

@MainActor package class Observation {
    package var active = true
    let sequence: UInt64
    init() {
        let runtime = ReactiveRuntime.shared
        runtime.assertCanMutate("subscription creation")
        bump(&runtime.observationSequence)
        sequence = runtime.observationSequence
    }
    package func prepare() -> (() -> Void)? { nil }
    package func cancel() { active = false }
}

@MainActor package final class ValueObservation<Value>: Observation {
    let node: ValueNode<Value>
    var deliveredRevision: UInt64?
    let deliver: (Value) -> Void
    package init(
        read: @escaping () -> Value, equals: @escaping (Value, Value) -> Bool, deliver: @escaping (Value) -> Void
    ) {
        node = ValueNode(compute: read, equals: equals)
        self.deliver = deliver
        super.init()
        node.invalidated = { [weak self] in
            guard let self, self.active else { return }
            ReactiveRuntime.shared.enqueue(self)
        }
    }
    package override func prepare() -> (() -> Void)? {
        guard active else { return nil }
        let value = node.read()
        guard deliveredRevision != node.revision else { return nil }
        deliveredRevision = node.revision
        return { [weak self] in
            guard let self, self.active else { return }
            self.deliver(value)
        }
    }
    package override func cancel() {
        super.cancel()
        node.detach()
        node.invalidated = nil
    }
}
