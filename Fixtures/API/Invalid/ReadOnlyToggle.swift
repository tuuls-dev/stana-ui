import Stana

@MainActor func invalid() {
	_ = STNToggle(properties: .init(text: "Read only", isOn: STNSignal(true)))
}
