import Stana

@MainActor func invalidZStackSharedAlignment() {
	let alignment: STNAlignment = .leading
	_ = STNZStack(properties: .init(alignment: alignment)) {}
}
