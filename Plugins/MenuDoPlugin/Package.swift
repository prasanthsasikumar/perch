// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MenuDoPlugin",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MenuDoPlugin", targets: ["MenuDoPlugin"])
    ],
    dependencies: [
        .package(path: "../../PerchKit")
    ],
    targets: [
        .target(name: "MenuDoPlugin", dependencies: ["PerchKit"])
    ]
)
