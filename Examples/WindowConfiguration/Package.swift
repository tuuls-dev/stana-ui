// swift-tools-version: 6.4
import PackageDescription

let package = Package(
	name: "WindowConfiguration",
	platforms: [.macOS(.v14)],
	dependencies: [.package(path: "../..")],
	targets: [
		.executableTarget(name: "WindowConfigurationApp", dependencies: [.product(name: "Stana", package: "stana-ui")])
	],
	swiftLanguageModes: [.v6]
)
