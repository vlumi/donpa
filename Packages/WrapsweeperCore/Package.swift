// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "WrapsweeperCore",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
    ],
    products: [
        // Pure game logic — no UI dependencies. Headlessly testable.
        .library(name: "WrapsweeperCore", targets: ["WrapsweeperCore"]),
        // SpriteKit rendering + SwiftUI glue. Depends on WrapsweeperCore.
        .library(name: "WrapsweeperKit", targets: ["WrapsweeperKit"]),
    ],
    targets: [
        .target(name: "WrapsweeperCore"),
        .target(
            name: "WrapsweeperKit",
            dependencies: ["WrapsweeperCore"]
        ),
        .testTarget(
            name: "WrapsweeperCoreTests",
            dependencies: ["WrapsweeperCore"]
        ),
        .testTarget(
            name: "WrapsweeperKitTests",
            dependencies: ["WrapsweeperKit"]
        ),
    ]
)
