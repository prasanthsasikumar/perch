// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BusyPlugin",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "BusyPlugin", targets: ["BusyPlugin"])
    ],
    dependencies: [
        .package(path: "../../PerchKit")
    ],
    targets: [
        .target(
            name: "BusyPlugin",
            dependencies: ["PerchKit"],
            resources: [.process("Session/Resources")]
        ),
        // PerchKit is listed explicitly even though BusyPlugin already depends
        // on it: the tests construct a PluginStorage directly, and relying on
        // a transitive import is fragile.
        .testTarget(name: "BusyPluginTests", dependencies: ["BusyPlugin", "PerchKit"]),
    ]
)
