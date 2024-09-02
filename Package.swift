// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "EventSource",
    platforms: [
        .iOS(.v14),
        .macOS(.v11),
        .watchOS(.v7),
        .macCatalyst(.v14),
        .tvOS(.v14),
        .visionOS(.v1)
    ],
    products: [
        .library(
            name: "EventSource",
            targets: ["EventSource"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-concurrency-extras.git", .upToNextMajor(from: "1.1.0"))
    ],
    targets: [
        .target(name: "EventSource"),
        .testTarget(
            name: "EventSourceTests",
            dependencies: [
                "EventSource",
                .product(name: "ConcurrencyExtras", package: "swift-concurrency-extras")
            ]
        ),
    ]
)
