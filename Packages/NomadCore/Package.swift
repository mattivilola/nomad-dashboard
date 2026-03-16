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
    dependencies: [
        .package(url: "https://github.com/TelemetryDeck/SwiftSDK", from: "2.11.0")
    ],
    targets: [
        .target(
            name: "NomadCore",
            dependencies: [
                .product(name: "TelemetryDeck", package: "SwiftSDK")
            ],
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
