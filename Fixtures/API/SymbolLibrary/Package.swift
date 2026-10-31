// swift-tools-version: 6.4
import PackageDescription

let package = Package(
	name: "SymbolLibrary",
	platforms: [.macOS(.v26)],
	products: [.library(name: "SymbolLibrary", targets: ["SymbolLibrary"])],
	dependencies: [.package(path: "../../..")],
	targets: [
		.target(
			name: "SymbolLibrary",
			dependencies: [.product(name: "Stana", package: "stana-ui")],
			packageAccess: false
		)
	],
	swiftLanguageModes: [.v6]
)
