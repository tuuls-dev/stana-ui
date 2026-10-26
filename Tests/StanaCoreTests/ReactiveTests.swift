import Testing

@testable import StanaCore

@Suite @MainActor struct ReactiveTests {
    @Test func subscribersDeliverInRegistrationOrder() {
        let source = STNSignal(0)
        var order: [Int] = []
        var tokens: [STNSubscription] = []
        for index in 0..<12 { tokens.append(source.subscribe { _ in order.append(index) }) }
        order.removeAll()
        source.value = 1
        #expect(order == Array(0..<12))
        tokens.forEach { $0.cancel() }
    }
    @Test func demandOnlyComputedsDoNotAccumulateWeakIndexEntries() {
        let source = STNSignal(0)
        for _ in 0..<100 {
            let computed = source.map { $0 + 1 }
            #expect(computed.value == 1)
        }
        #expect(source.node.dependents.isEmpty)
    }
    @Test func equalOutputStillReplacesTheOrderedDependencyTrace() {
        let flag = STNSignal(false)
        var a: STNComputed<Int>!
        var b: STNComputed<Int>!
        a = STNComputed { flag.value ? 1 : b.value }
        b = STNComputed { flag.value ? a.value : 1 }
        #expect(a.value == 1)
        #expect(b.value == 1)
        let aRevision = a.node.revision
        let bRevision = b.node.revision
        flag.value = true
        #expect(b.value == 1)
        #expect(a.value == 1)
        #expect(a.node.revision == aRevision && b.node.revision == bRevision)
        #expect(a.node.dependencies.count == 1)
        #expect(b.node.dependencies.count == 2)
        a = nil
        b = nil
    }
    @Test func diamondIsGlitchFreeAndBatched() {
        let source = STNSignal(1)
        let b = source.map { $0 * 2 }
        let c = source.map { $0 + 1 }
        let d = STNComputed { b.value + c.value }
        var values: [Int] = []
        let observed = STNSignal(0)
        let observation = ValueObservation(read: { d.value }, equals: { $0 == $1 }) {
            values.append($0)
            observed.value = $0
        }
        ReactiveRuntime.shared.batch { ReactiveRuntime.shared.enqueue(observation) }
        STNTransaction.perform {
            source.value = 2
            source.value = 3
        }
        #expect(values == [4, 10])
        observation.cancel()
    }
    @Test func dynamicEdgesReverseWithoutFalseCycles() {
        for demandAFirst in [false, true] {
            let flag = STNSignal(false)
            var a: STNComputed<Int>!
            var b: STNComputed<Int>!
            a = STNComputed { flag.value ? 1 : b.value }
            b = STNComputed { flag.value ? a.value : 2 }
            for value in [false, true, false, true] {
                flag.value = value
                if demandAFirst {
                    #expect(a.value == (value ? 1 : 2))
                    #expect(b.value == a.value)
                } else {
                    #expect(b.value == (value ? 1 : 2))
                    #expect(a.value == b.value)
                }
            }
        }
    }
    @Test func cancelledObservationDoesNotDeliver() {
        let source = STNSignal(0)
        var values: [Int] = []
        let observation = ValueObservation(read: { source.value }, equals: { $0 == $1 }) { values.append($0) }
        ReactiveRuntime.shared.batch {
            ReactiveRuntime.shared.enqueue(observation)
            observation.cancel()
        }
        source.value = 1
        #expect(values.isEmpty)
    }
}
