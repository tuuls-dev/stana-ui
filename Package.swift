// swift-tools-version: 6.4
import PackageDescription

let targets: [Target] = [
    .target(name: "StanaPrimitives"),
    .target(name: "StanaCore", dependencies: ["StanaPrimitives"]),
    .target(name: "StanaText", dependencies: ["StanaPrimitives"]),
    .target(name: "StanaLayout", dependencies: ["StanaCore", "StanaText"]),
    .target(name: "StanaScene", dependencies: ["StanaCore"]),
    .target(name: "StanaGraphics", dependencies: ["StanaScene"]),
    .target(name: "StanaAccessibility", dependencies: ["StanaCore"]),
    .target(name: "StanaPlatform", dependencies: ["StanaGraphics", "StanaText", "StanaAccessibility"]),
    .target(
        name: "CStanaMacOS", publicHeadersPath: "include",
        linkerSettings: [
            .linkedFramework("AppKit"), .linkedFramework("CoreGraphics"), .linkedFramework("CoreText"),
        ]),
    .target(name: "StanaPlatformMacOS", dependencies: ["StanaPlatform", "CStanaMacOS"]),
    .target(
        name: "Stana",
        dependencies: [
            "StanaPrimitives", "StanaCore", "StanaLayout", "StanaText", "StanaScene", "StanaAccessibility",
            "StanaPlatform", "StanaPlatformMacOS",
        ], resources: [.copy("Resources")]),
    .target(
        name: "StanaTesting",
        dependencies: ["Stana", "StanaPrimitives", "StanaCore", "StanaText", "StanaScene", "StanaAccessibility"]),
    .testTarget(name: "StanaCoreTests", dependencies: ["StanaCore"]),
    .testTarget(name: "StanaLayoutTests", dependencies: ["StanaLayout"]),
    .testTarget(name: "StanaTextTests", dependencies: ["StanaText"]),
    .testTarget(name: "StanaAPITests", dependencies: ["StanaTesting"]),
    .testTarget(name: "StanaSceneTests", dependencies: ["StanaScene", "StanaAccessibility"]),
    .testTarget(
        name: "StanaMacOSIntegrationTests",
        dependencies: [
            "Stana", "StanaPlatformMacOS", "StanaPrimitives", "StanaCore", "StanaAccessibility", "StanaScene",
            "StanaGraphics", "CStanaMacOS",
        ]),
]
for target in targets where target.name != "CStanaMacOS" {
    target.swiftSettings = [.defaultIsolation(nil)]
}

let package = Package(
    name: "stana-ui",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "Stana", targets: ["Stana"]),
        .library(name: "StanaTesting", targets: ["StanaTesting"]),
    ],
    targets: targets,
    swiftLanguageModes: [.v6]
)
