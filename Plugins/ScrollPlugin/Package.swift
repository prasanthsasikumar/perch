// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ScrollPlugin",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ScrollPlugin", targets: ["ScrollPlugin"]),
        // The half shared with the PerchScroll companion app: the settings,
        // the messages the two exchange, and which scrolls get reversed.
        .library(name: "ScrollKit", targets: ["ScrollKit"]),
    ],
    dependencies: [
        .package(path: "../../PerchKit")
    ],
    targets: [
        .target(name: "ScrollKit"),
        .target(name: "ScrollPlugin", dependencies: ["ScrollKit", "PerchKit"]),
        .testTarget(name: "ScrollKitTests", dependencies: ["ScrollKit"]),
        // PerchKit is listed explicitly for the same reason as Tap's: the
        // tests construct a PluginStorage directly.
        .testTarget(name: "ScrollPluginTests", dependencies: ["ScrollPlugin", "ScrollKit", "PerchKit"]),
    ]
)
