// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MarketPlugin",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MarketPlugin", targets: ["MarketPlugin"])
    ],
    dependencies: [
        .package(path: "../../PerchKit")
    ],
    targets: [
        .target(name: "MarketPlugin", dependencies: ["PerchKit"]),
        // PerchKit is listed explicitly even though MarketPlugin already
        // depends on it: later tests construct a PluginContext and a
        // PluginStorage directly, and relying on a transitive import is
        // fragile.
        .testTarget(name: "MarketPluginTests", dependencies: ["MarketPlugin", "PerchKit"]),
    ]
)
