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
        .target(
            name: "SurgeModuleManagement",
            path: "Sources/SurgeModuleManagement",
            exclude: [
                "LICENSE"
            ],
            resources: [
                .process("Assets.xcassets"),
                .copy("WebResources")
            ],
            linkerSettings: [
                .linkedFramework("JavaScriptCore")
            ]
        ),
        .executableTarget(
            name: "SurgeShallow",
            dependencies: ["SurgeProfileRelayCore", "SurgeModuleManagement"]
        ),
        .testTarget(
            name: "SurgeProfileRelayCoreTests",
            dependencies: ["SurgeProfileRelayCore"]
        ),
        .testTarget(
            name: "SurgeModuleManagementTests",
            dependencies: ["SurgeModuleManagement"],
            path: "Tests/SurgeModuleManagementTests"
        ),
        .testTarget(
            name: "SurgeShallowTests",
            dependencies: ["SurgeShallow"],
            path: "Tests/SurgeShallowTests"
        )
    ]
)
