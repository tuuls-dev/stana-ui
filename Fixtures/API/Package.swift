// swift-tools-version: 6.4
import PackageDescription

let package = Package(
	name: "StanaAPIConsumer",
	platforms: [.macOS(.v14)],
	dependencies: [.package(path: "../..")],
	targets: [.target(name: "Valid", dependencies: [.product(name: "Stana", package: "stana-ui")], path: "Valid")]
)
