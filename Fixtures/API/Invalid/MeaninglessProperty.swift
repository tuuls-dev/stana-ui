import Stana

@MainActor func invalid() {
	_ = STNText(properties: .init(text: "Hello", spacing: 10))
}
