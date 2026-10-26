import Stana
import StanaTesting
import Testing

@Suite @MainActor struct AsyncLifetimeTests {
    @Test func lateNonCooperativeTaskCannotPublishAfterRemoval() async throws {
        let state = LoadingState()
        let shown = STNSignal(true)
        var host: STNTestHost? = STNTestHost()
        weak let weakHost = host
        host?.mount { STNIf(shown) { LoadingComponent(state: state) } }
        for _ in 0..<100 where state.continuation == nil { await Task.yield() }
        #expect(state.started == 1)
        let context = try #require(state.context)
        let old = context.beginRequest()
        let current = context.beginRequest()
        #expect(!context.isCurrent(old))
        #expect(context.isCurrent(current))
        shown.value = false
        #expect(!context.isCurrent(current))
        #expect(state.disposals == 1)
        state.continuation?.resume()
        state.continuation = nil
        for _ in 0..<100 where !state.finished { await Task.yield() }
        #expect(state.finished)
        #expect(state.result.value == "Loading")
        host?.close()
        host = nil
        #expect(weakHost == nil)
    }
}

@MainActor private final class LoadingState {
    let result = STNSignal("Loading")
    var context: STNComponentContext?
    var continuation: CheckedContinuation<Void, Never>?
    var started = 0
    var disposals = 0
    var finished = false
}

@MainActor private struct LoadingComponent: STNComponent {
    let state: LoadingState
    func makeContent(in context: STNComponentContext) -> some STNComponent {
        state.context = context
        let token = context.beginRequest()
        context.onDispose { state.disposals += 1 }
        context.task(
            operation: { context in
                state.started += 1
                await withCheckedContinuation { state.continuation = $0 }
                if context.isCurrent(token) { state.result.value = "Loaded" }
                state.finished = true
            }, onError: { _ in state.result.value = "Failed" })
        STNText(properties: .init(text: state.result))
    }
}
