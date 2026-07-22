// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "SurgeShallow",
    defaultLocalization: "zh-Hans",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(
            name: "SurgeShallow",
            targets: ["SurgeShallow"]
        )
    ],
    targets: [
        .target(
            name: "SurgeProfileRelayCore"
        ),
        .executableTarget(
            name: "SurgeShallow",
            dependencies: ["SurgeProfileRelayCore"]
        ),
        .testTarget(
            name: "SurgeProfileRelayCoreTests",
            dependencies: ["SurgeProfileRelayCore"]
        )
    ]
)
