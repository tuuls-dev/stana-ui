import Stana

@MainActor func invalid() {
    let window=STNWindow(properties:.init(title:"Read-only state")) {}
    window.state.value.isVisible=true
}
