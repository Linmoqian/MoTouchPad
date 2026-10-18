// swift-tools-version: 5.9
import PackageDescription
import Foundation

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appendingPathComponent("../..").standardizedFileURL.path
let package = Package(
    name: "RustCoreComparison",
    platforms: [.macOS(.v13)],
    dependencies: [.package(path: "../../mac-app")],
    targets: [
        .systemLibrary(name: "CRustCore", path: "Sources/CRustCore"),
        .executableTarget(name: "CompareCore", dependencies: [
            "CRustCore", .product(name: "MoTouchPadCore", package: "mac-app")
        ], linkerSettings: [.unsafeFlags([root + "/core-rust/target/release/libmotouchpad_core.a"])])
    ]
)
