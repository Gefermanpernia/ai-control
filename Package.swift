// swift-tools-version: 5.7

import PackageDescription

let package = Package(
    name: "AIControl",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "AIControl", targets: ["AIControl"])
    ],
    targets: [
        .target(name: "AIControlCore"),
        .executableTarget(name: "AIControl", dependencies: ["AIControlCore"]),
        .testTarget(name: "AIControlCoreTests", dependencies: ["AIControlCore"])
    ]
)
