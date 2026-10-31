// swift-tools-version: 6.4
import PackageDescription

let package = Package(
	name: "StanaAPIConsumer",
	platforms: [.macOS(.v26)],
	dependencies: [.package(path: "../.."), .package(path: "SymbolLibrary")],
	targets: [
		.target(
			name: "Valid",
			dependencies: [
				.product(name: "Stana", package: "stana-ui"), .product(name: "SymbolLibrary", package: "SymbolLibrary"),
			],
			path: "Valid",
			packageAccess: false
		)
	]
)
