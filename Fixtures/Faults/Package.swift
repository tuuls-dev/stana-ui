// swift-tools-version: 6.4
import PackageDescription

let package = Package(
	name: "StanaFaultFixtures",
	platforms: [.macOS(.v14)],
	dependencies: [.package(path: "../..")],
	targets: [.executableTarget(name: "FaultProbe", dependencies: [.product(name: "Stana", package: "stana-ui")])]
)
