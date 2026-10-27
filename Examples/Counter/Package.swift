// swift-tools-version: 6.4
import PackageDescription

let package = Package(
	name: "Counter",
	platforms: [.macOS(.v26)],
	dependencies: [.package(path: "../..")],
	targets: [.executableTarget(name: "CounterApp", dependencies: [.product(name: "Stana", package: "stana-ui")])],
	swiftLanguageModes: [.v6]
)
