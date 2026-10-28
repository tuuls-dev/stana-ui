// swift-tools-version: 6.4
import PackageDescription

let targets: [Target] = [
	.target(name: "StanaPrimitives"),
	.target(name: "StanaCore", dependencies: ["StanaPrimitives"]),
	.target(name: "StanaText", dependencies: ["StanaPrimitives"]),
	.target(name: "StanaLayout", dependencies: ["StanaCore", "StanaText"]),
	.target(name: "StanaScene", dependencies: ["StanaCore"]),
	.target(name: "StanaGraphics", dependencies: ["StanaScene"]),
	.target(name: "StanaAccessibility", dependencies: ["StanaCore"]),
	.target(name: "StanaPlatform", dependencies: ["StanaGraphics", "StanaText", "StanaAccessibility"]),
	.target(
		name: "CStanaMacOS",
		publicHeadersPath: "include",
		linkerSettings: [
			.linkedFramework("AppKit"), .linkedFramework("CoreGraphics"), .linkedFramework("CoreText"),
			.linkedFramework("Metal"), .linkedFramework("QuartzCore"), .linkedFramework("IOSurface"),
		]
	),
	.target(name: "StanaPlatformMacOS", dependencies: ["StanaPlatform", "CStanaMacOS"]),
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
	.testTarget(name: "StanaCoreTests", dependencies: ["StanaCore"]),
	.testTarget(name: "StanaLayoutTests", dependencies: ["StanaLayout"]),
	.testTarget(name: "StanaTextTests", dependencies: ["StanaText"]),
	.testTarget(name: "StanaAPITests", dependencies: ["StanaTesting"]),
	.testTarget(name: "StanaSceneTests", dependencies: ["StanaScene", "StanaAccessibility"]),
	.testTarget(name: "StanaGraphicsTests", dependencies: ["StanaGraphics"]),
	.testTarget(
		name: "StanaMacOSIntegrationTests",
		dependencies: [
			"Stana", "StanaPlatformMacOS", "StanaPrimitives", "StanaCore", "StanaAccessibility", "StanaScene",
			"StanaGraphics", "CStanaMacOS",
		]
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
