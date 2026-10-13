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
        .library(
            name: "NomadPowerHelperKit",
            targets: ["NomadPowerHelperKit"]
        ),
        .executable(
            name: "NomadSourceProbe",
            targets: ["NomadSourceProbe"]
        ),
        .executable(
            name: "NomadMissionDatasetBuilder",
            targets: ["NomadMissionDatasetBuilder"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/TelemetryDeck/SwiftSDK", from: "2.11.0")
    ],
    targets: [
        .target(
            name: "NomadCore",
            dependencies: [
                "NomadPowerHelperKit",
                .product(name: "TelemetryDeck", package: "SwiftSDK")
            ],
            resources: [
                .process("Resources")
            ]
        ),
        // Shared by the app and the privileged power helper. Keep it tiny and free of other dependencies.
        .target(
            name: "NomadPowerHelperKit"
        ),
        .executableTarget(
            name: "NomadSourceProbe",
            dependencies: ["NomadCore"]
        ),
        .executableTarget(
            name: "NomadMissionDatasetBuilder",
            dependencies: ["NomadCore"]
        ),
        .testTarget(
            name: "NomadCoreTests",
            dependencies: ["NomadCore"]
        ),
        .testTarget(
            name: "NomadPowerHelperKitTests",
            dependencies: ["NomadPowerHelperKit"]
        ),
        .testTarget(
            name: "NomadSourceProbeTests",
            dependencies: ["NomadSourceProbe"]
        ),
        .testTarget(
            name: "NomadMissionDatasetBuilderTests",
            dependencies: ["NomadMissionDatasetBuilder"]
        )
    ]
)
