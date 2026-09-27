// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TasksPlugin",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "TasksPlugin", targets: ["TasksPlugin"])
    ],
    dependencies: [
        .package(path: "../../PerchKit")
    ],
    targets: [
        .target(name: "TasksPlugin", dependencies: ["PerchKit"])
    ]
)
