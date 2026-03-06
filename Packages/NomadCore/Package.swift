// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "NomadCore",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "NomadCore",
            targets: ["NomadCore"]
        )
    ],
    targets: [
        .target(
            name: "NomadCore"
        ),
        .testTarget(
            name: "NomadCoreTests",
            dependencies: ["NomadCore"]
        )
    ]
)

