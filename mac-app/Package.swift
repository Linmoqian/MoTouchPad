// swift-tools-version: 5.9

// Created on 2026-09-02; updated 2026-09-02.
// @author: https://github.com/Linmoqian

import PackageDescription

let package = Package(
    name: "MoTouchPadMac",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "MoTouchPadCore", targets: ["MoTouchPadCore"])
    ],
    targets: [
        .executableTarget(
            name: "TouchPipelineBenchmark",
            dependencies: ["MoTouchPadCore"],
            path: "Benchmarks/TouchPipelineBenchmark"
        ),
        .target(
            name: "MoTouchPadCore",
            path: "Sources/MoTouchPadCore"
        ),
        .executableTarget(
            name: "MoTouchPadMac",
            dependencies: ["MoTouchPadCore"],
            path: "Sources/MoTouchPadMac"
        ),
        .testTarget(
            name: "MoTouchPadCoreTests",
            dependencies: ["MoTouchPadCore"],
            path: "Tests/MoTouchPadCoreTests"
        ),
        .testTarget(
            name: "MoTouchPadMacTests",
            dependencies: ["MoTouchPadMac", "MoTouchPadCore"],
            path: "Tests/MoTouchPadMacTests"
        )
    ]
)
