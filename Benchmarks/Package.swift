// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "StanaBenchmarks",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "..")],
    targets: [
        .executableTarget(
            name: "StanaBenchmarks",
            dependencies: [
                .product(name: "Stana", package: "stana-ui"),
                .product(name: "StanaTesting", package: "stana-ui"),
            ])
    ]
)
