import Stana

@MakeSTNSymbol
public struct AddIcon {
	private static let svg = #"""
		<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round">
		<path d="M5 12h14M12 5v14"/>
		</svg>
		"""#
}

@MainActor
@MakeSTNSymbol(mirrorsInRTL: true)
public struct ForwardIcon {
	static let svg = "<svg viewBox='-12 -12 24 24'><path d='M-5 -6L1 0-5 6' fill='none' stroke='currentColor'/></svg>"
}

nonisolated public func exportedSymbol() -> STNSymbolAsset {
	ForwardIcon.asset
}

@MainActor func symbols() -> some STNComponent {
	STNSymbol(
		properties: .init(symbol: AddIcon.asset, animation: STNSymbolPlayback.loop(.rotate), strokeWidth: Optional(2.0))
	)
}
