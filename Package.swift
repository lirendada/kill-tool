// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "KillTool",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "KillToolCore", targets: ["KillToolCore"]),
        .executable(name: "KillTool", targets: ["KillToolApp"])
    ],
    targets: [
        .target(name: "KillToolCore"),
        .executableTarget(
            name: "KillToolApp",
            dependencies: ["KillToolCore"]
        ),
        .executableTarget(
            name: "KillToolCoreBehaviorTests",
            dependencies: ["KillToolCore"],
            path: "Tests/KillToolCoreBehaviorTests"
        )
    ]
)
