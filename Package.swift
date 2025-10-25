// swift-tools-version: 5.10
import PackageDescription
import Foundation

let package = Package(
    name: "xcsift",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "xcsift",
            targets: ["xcsift"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "xcsift",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
        ),
        .testTarget(
            name: "xcsiftTests",
            dependencies: ["xcsift"],
            path: "Tests",
            resources: [
                .copy("Fixtures/build.txt"),
                .copy("Fixtures/swift-testing-output.txt")
            ]
        ),
        // Temporarily commented out due to swift-syntax version conflict with SwiftLint
        // .testTarget(
        //     name: "xcsiftSwiftTestingTests",
        //     dependencies: [
        //         "xcsift",
        //         .product(name: "Testing", package: "swift-testing")
        //     ],
        //     path: "SwiftTestingTests"
        // )
    ]
)

