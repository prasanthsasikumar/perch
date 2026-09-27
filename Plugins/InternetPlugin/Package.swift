// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "InternetPlugin",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "InternetPlugin", targets: ["InternetPlugin"])
    ],
    dependencies: [
        .package(path: "../../PerchKit")
    ],
    targets: [
        .target(name: "InternetPlugin", dependencies: ["PerchKit"]),
        // PerchKit is listed explicitly for the same reason as ServerPlugin's:
        // the tests construct a PluginStorage directly.
        .testTarget(name: "InternetPluginTests", dependencies: ["InternetPlugin", "PerchKit"]),
    ]
)
