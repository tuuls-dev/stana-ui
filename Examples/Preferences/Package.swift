// swift-tools-version: 6.4
import PackageDescription

let package = Package(
	name: "Preferences",
	platforms: [.macOS(.v26)],
	dependencies: [.package(path: "../..")],
	targets: [.executableTarget(name: "PreferencesApp", dependencies: [.product(name: "Stana", package: "stana-ui")])],
	swiftLanguageModes: [.v6]
)
