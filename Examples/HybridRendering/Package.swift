// swift-tools-version: 6.4
import PackageDescription

let package = Package(
	name: "HybridRendering",
	platforms: [.macOS(.v26)],
	dependencies: [.package(path: "../..")],
	targets: [
		.executableTarget(
			name: "HybridRenderingApp",
			dependencies: [.product(name: "Stana", package: "stana-ui")],
			resources: [.copy("Resources")]
		)
	],
	swiftLanguageModes: [.v6]
)
