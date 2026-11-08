// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AnalyticsPlugin",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "AnalyticsPlugin", targets: ["AnalyticsPlugin"])
    ],
    dependencies: [
        .package(path: "../../PerchKit")
    ],
    targets: [
        .target(name: "AnalyticsPlugin", dependencies: ["PerchKit"]),
        // The GA tests live in PerchTests, from before plugins carried their
        // own; the PostHog source is tested here so `swift test` covers it
        // without building the app. PerchKit is listed for the same reason
        // BusyPlugin lists it: the tests build `PluginStorage` directly.
        .testTarget(
            name: "AnalyticsPluginTests",
            dependencies: ["AnalyticsPlugin", "PerchKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
