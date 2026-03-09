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
        ),
        .executable(
            name: "NomadSourceProbe",
            targets: ["NomadSourceProbe"]
        )
    ],
    targets: [
        .target(
            name: "NomadCore",
            resources: [
                .process("Resources")
            ]
        ),
        .executableTarget(
            name: "NomadSourceProbe",
            dependencies: ["NomadCore"]
        ),
        .testTarget(
            name: "NomadCoreTests",
            dependencies: ["NomadCore"]
        ),
        .testTarget(
            name: "NomadSourceProbeTests",
            dependencies: ["NomadSourceProbe"]
        )
    ]
)
