import Stana

@MainActor
@MakeSTNSymbol(mirrorsInRTL: true)
public struct LibrarySymbol {
	private static let svg = #"""
		<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor">
		<path d="M4 12H20M14 6L20 12L14 18"/>
		</svg>
		"""#
}

nonisolated public func libraryAsset() -> STNSymbolAsset {
	LibrarySymbol.asset
}
