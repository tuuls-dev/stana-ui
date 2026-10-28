import Stana

@MainActor func invalid() {
	_ = STNText(properties: .init(text: STNSignal("Text").binding))
}
