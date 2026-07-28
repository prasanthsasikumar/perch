// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PerchKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PerchKit", targets: ["PerchKit"])
    ],
    targets: [
        .target(name: "PerchKit")
    ]
)
