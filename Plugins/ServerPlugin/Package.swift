// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ServerPlugin",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ServerPlugin", targets: ["ServerPlugin"])
    ],
    dependencies: [
        .package(path: "../../PerchKit")
    ],
    targets: [
        .target(name: "ServerPlugin", dependencies: ["PerchKit"]),
        // PerchKit is listed explicitly even though ServerPlugin already
        // depends on it: the tests construct a PluginStorage directly, and
        // relying on a transitive import is fragile.
        .testTarget(name: "ServerPluginTests", dependencies: ["ServerPlugin", "PerchKit"]),
    ]
)
