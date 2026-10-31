/// Compiles a literal SVG into immutable, portable geometry during compilation.
@attached(member, names: named(asset))
public macro MakeSTNSymbol(mirrorsInRTL: Bool = false) =
	#externalMacro(module: "StanaSymbolMacros", type: "MakeSTNSymbolMacro")
