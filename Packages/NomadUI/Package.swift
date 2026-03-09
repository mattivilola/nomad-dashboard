// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "NomadUI",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "NomadUI",
            targets: ["NomadUI"]
        )
    ],
    dependencies: [
        .package(path: "../NomadCore")
    ],
    targets: [
        .target(
            name: "NomadUI",
            dependencies: [
                .product(name: "NomadCore", package: "NomadCore")
            ],
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "NomadUITests",
            dependencies: ["NomadUI"]
        )
    ]
)
