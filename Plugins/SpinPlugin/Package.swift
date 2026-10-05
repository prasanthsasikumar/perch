// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SpinPlugin",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SpinPlugin", targets: ["SpinPlugin"])
    ],
    dependencies: [
        .package(path: "../../PerchKit")
    ],
    targets: [
        .target(
            name: "SpinPlugin",
            dependencies: ["PerchKit"],
            resources: [.copy("Scene/Resources/scenes")]
        ),
        .testTarget(name: "SpinPluginTests", dependencies: ["SpinPlugin", "PerchKit"]),
    ]
)
