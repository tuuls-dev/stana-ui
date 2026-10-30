import Stana

@MainActor func zStackFixtures() {
	let alignment: STNZStack.Alignment = .trailing
	_ = STNZStack(properties: .init(alignment: alignment)) {
		STNText(properties: .init(text: "Logical trailing"))
	}
	_ = STNZStack(properties: .init(alignment: .leading)) {}
	_ = STNZStack(properties: .init(alignment: .center)) {}
	_ = STNZStack {}

	// Linear stacks retain their shared alignment and spacing API.
	let linearAlignment: STNAlignment = .firstBaseline
	_ = STNHStack(properties: .init(alignment: linearAlignment, spacing: 8)) {}
	_ = STNVStack(properties: .init(alignment: .trailing, spacing: 8)) {}
}
