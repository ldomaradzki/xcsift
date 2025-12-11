// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "xcsift",
    platforms: [.macOS(.v15)],
    products: [
        .executable(
            name: "xcsift",
            targets: ["xcsift"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.0.0"),
        .package(url: "https://github.com/toon-format/toon-swift.git", from: "0.3.0"),
        .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.4.5"),
    ],
    targets: [
        .executableTarget(
            name: "xcsift",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "ToonFormat", package: "toon-swift"),
            ]
        ),
        .testTarget(
            name: "xcsiftTests",
            dependencies: ["xcsift"],
            path: "Tests",
            resources: [
                .copy("Fixtures/build.txt"),
                .copy("Fixtures/swift-testing-output.txt"),
                .copy("Fixtures/linker-error-output.txt"),
            ]
        ),
    ]
)
