// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AnalyticsPlugin",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "AnalyticsPlugin", targets: ["AnalyticsPlugin"])
    ],
    dependencies: [
        .package(path: "../../PerchKit")
    ],
    targets: [
        .target(name: "AnalyticsPlugin", dependencies: ["PerchKit"])
    ]
)
