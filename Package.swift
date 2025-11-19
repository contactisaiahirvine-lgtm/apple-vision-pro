// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VisionProARGame",
    platforms: [
        .visionOS(.v1)
    ],
    products: [
        .library(
            name: "VisionProARGame",
            targets: ["VisionProARGame"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "VisionProARGame",
            dependencies: [],
            path: "Sources")
    ]
)
