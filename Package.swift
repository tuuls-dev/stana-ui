// swift-tools-version: 6.4
import PackageDescription

let targets: [Target] = [
	.target(name: "StanaPrimitives", path: "Sources/Engine/Primitives"),
	.target(name: "StanaCore", dependencies: ["StanaPrimitives"], path: "Sources/Engine/Core"),
	.target(name: "StanaText", dependencies: ["StanaPrimitives"], path: "Sources/Engine/Text"),
	.target(name: "StanaLayout", dependencies: ["StanaCore", "StanaText"], path: "Sources/Engine/Layout"),
	.target(name: "StanaScene", dependencies: ["StanaCore"], path: "Sources/Engine/Scene"),
	.target(name: "StanaGraphics", dependencies: ["StanaScene"], path: "Sources/Engine/Graphics"),
	.target(name: "StanaAccessibility", dependencies: ["StanaCore"], path: "Sources/Engine/Accessibility"),
	.target(
		name: "StanaPlatform",
		dependencies: ["StanaGraphics", "StanaText", "StanaAccessibility"],
		path: "Sources/Platform/Contracts"
	),
	.target(
		name: "CStanaMacOS",
		path: "Sources/Platform/MacOS/Bridge",
		publicHeadersPath: "include",
		linkerSettings: [
			.linkedFramework("AppKit"), .linkedFramework("CoreGraphics"), .linkedFramework("CoreText"),
			.linkedFramework("Metal"), .linkedFramework("QuartzCore"), .linkedFramework("IOSurface"),
		]
	),
	.target(
		name: "StanaPlatformMacOS",
		dependencies: ["StanaPlatform", "CStanaMacOS"],
		path: "Sources/Platform/MacOS/Adapter"
	),
	.target(
		name: "Stana",
		dependencies: [
			"StanaPrimitives", "StanaCore", "StanaLayout", "StanaText", "StanaScene", "StanaAccessibility",
			"StanaPlatform", "StanaPlatformMacOS",
		],
		resources: [.copy("Resources")]
	),
	.target(
		name: "StanaTesting",
		dependencies: [
			"Stana", "StanaPrimitives", "StanaCore", "StanaText", "StanaScene", "StanaAccessibility", "StanaPlatform",
			"StanaGraphics",
		]
	),
	.testTarget(name: "StanaCoreTests", dependencies: ["StanaCore"], path: "Tests/Engine/Core"),
	.testTarget(name: "StanaLayoutTests", dependencies: ["StanaLayout"], path: "Tests/Engine/Layout"),
	.testTarget(name: "StanaTextTests", dependencies: ["StanaText"], path: "Tests/Engine/Text"),
	.testTarget(name: "StanaAPITests", dependencies: ["StanaTesting"], path: "Tests/Stana"),
	.testTarget(
		name: "StanaSceneTests",
		dependencies: ["StanaScene", "StanaAccessibility"],
		path: "Tests/Engine/Scene"
	),
	.testTarget(name: "StanaGraphicsTests", dependencies: ["StanaGraphics"], path: "Tests/Engine/Graphics"),
	.testTarget(
		name: "StanaMacOSIntegrationTests",
		dependencies: [
			"Stana", "StanaPlatformMacOS", "StanaPrimitives", "StanaCore", "StanaAccessibility", "StanaScene",
			"StanaGraphics", "CStanaMacOS",
		],
		path: "Tests/Platform/MacOS"
	),
	.executableTarget(
		name: "CalculatorApp",
		dependencies: ["Stana"],
		path: "Examples/Calculator/Sources/CalculatorApp",
		packageAccess: false
	),
	.testTarget(
		name: "CalculatorTests",
		dependencies: ["CalculatorApp", "StanaTesting"],
		path: "Examples/Calculator/Tests/CalculatorTests",
		packageAccess: false
	),
]
for target in targets where target.name != "CStanaMacOS" {
	target.swiftSettings = [.defaultIsolation(nil)]
}

let package = Package(
	name: "stana-ui",
	platforms: [.macOS(.v26)],
	products: [
		.library(name: "Stana", targets: ["Stana"]),
		.library(name: "StanaTesting", targets: ["StanaTesting"]),
	],
	targets: targets,
	swiftLanguageModes: [.v6]
)
