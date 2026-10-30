// swift-tools-version: 6.4
import PackageDescription

let package = Package(
	name: "StanaPerformance",
	platforms: [.macOS(.v26)],
	dependencies: [.package(path: "..")],
	targets: [
		.executableTarget(
			name: "StanaPerformance",
			dependencies: [
				.product(name: "Stana", package: "stana-ui"),
				.product(name: "StanaTesting", package: "stana-ui"),
			]
		),
		.testTarget(name: "StanaPerformanceTests", dependencies: ["StanaPerformance"]),
	],
	swiftLanguageModes: [.v6]
)
