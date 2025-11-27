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
        .package(url: "https://github.com/mattt/TOONEncoder.git", from: "0.1.1"),
    ],
    targets: [
        .executableTarget(
            name: "xcsift",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "TOONEncoder", package: "TOONEncoder")
            ]
        ),
        .testTarget(
            name: "xcsiftTests",
            dependencies: ["xcsift"],
            path: "Tests",
            resources: [
                .copy("Fixtures/build.txt"),
                .copy("Fixtures/swift-testing-output.txt")
            ]
        )
    ]
)
