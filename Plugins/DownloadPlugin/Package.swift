// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DownloadPlugin",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "DownloadPlugin", targets: ["DownloadPlugin"])
    ],
    dependencies: [
        .package(path: "../../PerchKit")
    ],
    targets: [
        .target(name: "DownloadPlugin", dependencies: ["PerchKit"]),
        // PerchKit is listed explicitly for the same reason as ServerPlugin's:
        // the tests construct a PluginStorage directly.
        .testTarget(name: "DownloadPluginTests", dependencies: ["DownloadPlugin", "PerchKit"]),
    ]
)
