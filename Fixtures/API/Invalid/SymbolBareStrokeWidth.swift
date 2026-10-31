import Stana

@MakeSTNSymbol
struct Icon {
	static let svg = "<svg viewBox='0 0 24 24'/>"
}

@MainActor func invalidStroke() {
	_ = STNSymbol(properties: .init(symbol: Icon.asset, strokeWidth: 2.0))
}
