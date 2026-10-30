import Stana

@MainActor func invalidZStackSpacing() {
	_ = STNZStack(properties: .init(spacing: 8)) {}
}
