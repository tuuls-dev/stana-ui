import Stana
import SymbolLibrary

nonisolated public func externallyAuthoredAsset() -> STNSymbolAsset {
	let direct = LibrarySymbol.asset
	precondition(direct == libraryAsset())
	return direct
}
