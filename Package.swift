// swift-tools-version: 6.4
import PackageDescription
import CompilerPluginSupport

let targets: [Target] = [
	.target(name: "StanaSymbolCompiler", path: "Sources/StanaSymbolCompiler"),
	.macro(
		name: "StanaSymbolMacros",
		dependencies: [
			"StanaSymbolCompiler",
			.product(name: "SwiftSyntax", package: "swift-syntax"),
			.product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
			.product(name: "SwiftDiagnostics", package: "swift-syntax"),
			.product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
			.product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
		],
		path: "Sources/StanaSymbolMacros"
	),
	.testTarget(name: "StanaSymbolCompilerTests", dependencies: ["StanaSymbolCompiler"], path: "Tests/SymbolCompiler"),
	.testTarget(
		name: "StanaSymbolMacrosTests",
		dependencies: [
			"StanaSymbolMacros",
			.product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
		],
		path: "Tests/SymbolMacros"
	),
	.executableTarget(
		name: "LayoutBenchmarks",
		dependencies: ["StanaLayout", "StanaText", "StanaAccessibility", "StanaPlatformMacOS"],
		path: "Benchmarks/Sources/LayoutBenchmarks"
	),
	.testTarget(
		name: "LayoutBenchmarkTests",
		dependencies: ["LayoutBenchmarks"],
		path: "Benchmarks/Tests/LayoutBenchmarkTests"
	),
	.executableTarget(
		name: "NativeInputProbe",
		dependencies: ["Stana", "StanaCore", "StanaPlatformMacOS"],
		path: "Fixtures/NativeInput"
	),
	.target(name: "StanaPrimitives", path: "Sources/Stana/Engine/Primitives"),
	.target(name: "StanaCore", dependencies: ["StanaPrimitives"], path: "Sources/Stana/Engine/Core"),
	.target(name: "StanaText", dependencies: ["StanaPrimitives"], path: "Sources/Stana/Engine/Text"),
	.target(name: "StanaLayout", dependencies: ["StanaCore", "StanaText"], path: "Sources/Stana/Engine/Layout"),
	.target(name: "StanaScene", dependencies: ["StanaCore"], path: "Sources/Stana/Engine/Scene"),
	.target(name: "StanaGraphics", dependencies: ["StanaScene"], path: "Sources/Stana/Engine/Graphics"),
	.target(name: "StanaAccessibility", dependencies: ["StanaCore"], path: "Sources/Stana/Engine/Accessibility"),
	.target(
		name: "StanaPlatform",
		dependencies: ["StanaGraphics", "StanaText", "StanaAccessibility"],
		path: "Sources/Platform/Contracts"
	),
	.target(
		name: "StanaPlatformMacOS",
		dependencies: ["StanaPlatform"],
		path: "Sources/Platform/MacOS",
		resources: [.copy("Rendering/Shaders")],
		linkerSettings: [
			.linkedFramework("AppKit"), .linkedFramework("Metal"), .linkedFramework("QuartzCore"),
			.linkedFramework("IOSurface"), .linkedFramework("CoreGraphics"), .linkedFramework("CoreText"),
			.linkedFramework("ImageIO"),
		]
	),
	.target(
		name: "Stana",
		dependencies: [
			"StanaPrimitives", "StanaCore", "StanaLayout", "StanaText", "StanaScene", "StanaAccessibility",
			"StanaPlatform", "StanaPlatformMacOS", "StanaSymbolMacros",
		],
		exclude: ["Engine"],
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
			"StanaGraphics", "StanaLayout", "StanaText",
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

for target in targets {
	target.swiftSettings = [.defaultIsolation(nil)]
}

let package = Package(
	name: "stana-ui",
	platforms: [.macOS(.v26)],
	products: [
		.library(name: "Stana", targets: ["Stana"]),
		.library(name: "StanaTesting", targets: ["StanaTesting"]),
	],
	dependencies: [.package(url: "https://github.com/swiftlang/swift-syntax.git", exact: "604.0.0")],
	targets: targets,
	swiftLanguageModes: [.v6]
)
