// swift-tools-version: 6.4
import PackageDescription

let package = Package(
	name: "Calculator",
	platforms: [.macOS(.v26)],
	dependencies: [.package(path: "../..")],
	targets: [
		.executableTarget(name: "CalculatorApp", dependencies: [.product(name: "Stana", package: "stana-ui")]),
		.testTarget(
			name: "CalculatorTests",
			dependencies: ["CalculatorApp", .product(name: "StanaTesting", package: "stana-ui")]
		),
	],
	swiftLanguageModes: [.v6]
)
