// swift-tools-version: 6.4
import PackageDescription

let package = Package(
	name: "TextFields",
	platforms: [.macOS(.v14)],
	dependencies: [.package(path: "../..")],
	targets: [.executableTarget(name: "TextFieldsApp", dependencies: [.product(name: "Stana", package: "stana-ui")])],
	swiftLanguageModes: [.v6]
)
