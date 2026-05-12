// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "xcsift",
    platforms: [.macOS(.v13)],
    products: [
        .executable(
            name: "xcsift",
            targets: ["xcsift"]
        ),
        .library(
            name: "XCSiftCore",
            targets: ["XCSiftCore"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.0.0"),
        .package(url: "https://github.com/toon-format/toon-swift.git", from: "0.4.0"),
        .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.4.5"),
        .package(url: "https://github.com/mattt/swift-toml", from: "2.0.0"),
    ],
    targets: [
        .target(
            name: "XCSiftCore"
        ),
        .executableTarget(
            name: "xcsift",
            dependencies: [
                "XCSiftCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "ToonFormat", package: "toon-swift"),
                .product(name: "TOML", package: "swift-toml"),
            ]
        ),
        .target(
            name: "TestUtils",
            dependencies: ["XCSiftCore"],
            path: "Tests/TestUtils"
        ),
        .testTarget(
            name: "XCSiftCoreTests",
            dependencies: [
                "XCSiftCore",
                "TestUtils",
                .product(name: "ToonFormat", package: "toon-swift"),
            ],
            path: "Tests/XCSiftCoreTests",
            resources: [
                .copy("Fixtures/build.txt"),
                .copy("Fixtures/swift-testing-output.txt"),
                .copy("Fixtures/linker-error-output.txt"),
            ]
        ),
        .testTarget(
            name: "xcsiftTests",
            dependencies: ["XCSiftCore", "xcsift", "TestUtils"],
            path: "Tests/xcsiftTests"
        ),
    ]
)
