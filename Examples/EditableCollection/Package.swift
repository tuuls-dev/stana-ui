// swift-tools-version: 6.4
import PackageDescription

let package = Package(
	name: "EditableCollection",
	platforms: [.macOS(.v26)],
	dependencies: [.package(path: "../..")],
	targets: [
		.executableTarget(name: "EditableCollectionApp", dependencies: [.product(name: "Stana", package: "stana-ui")])
	],
	swiftLanguageModes: [.v6]
)
