import Stana

@MainActor func invalidZStackBaseline() {
	_ = STNZStack(properties: .init(alignment: .firstBaseline)) {}
}
