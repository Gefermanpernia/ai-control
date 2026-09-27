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
    dependencies: [
        // CryptoKit's API for Linux; macOS uses CryptoKit itself.
        .package(url: "https://github.com/apple/swift-crypto.git", "3.0.0"..<"6.0.0")
    ],
    targets: [
        .target(name: "AIControlCore", dependencies: [
            .product(name: "Crypto", package: "swift-crypto", condition: .when(platforms: [.linux]))
        ]),
        .executableTarget(name: "AIControl", dependencies: ["AIControlCore"]),
        .testTarget(name: "AIControlCoreTests", dependencies: ["AIControlCore"])
    ]
)
