// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TapPlugin",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "TapPlugin", targets: ["TapPlugin"]),
        // The half shared with the PerchTap companion app: the gesture map,
        // the classifier, the sounds, and the messages the two exchange.
        .library(name: "TapKit", targets: ["TapKit"]),
    ],
    dependencies: [
        .package(path: "../../PerchKit")
    ],
    targets: [
        .target(name: "TapKit"),
        .target(name: "TapPlugin", dependencies: ["TapKit", "PerchKit"]),
        .testTarget(name: "TapKitTests", dependencies: ["TapKit"]),
        // PerchKit is listed explicitly for the same reason as ServerPlugin's:
        // the tests construct a PluginStorage directly.
        .testTarget(name: "TapPluginTests", dependencies: ["TapPlugin", "TapKit", "PerchKit"]),
    ]
)
