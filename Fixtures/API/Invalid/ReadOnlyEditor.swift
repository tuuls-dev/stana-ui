import Stana

@MainActor func invalid() {
	let value = STNComputed { "Read only" }
	_ = STNTextField(properties: .init(value: value))
}
