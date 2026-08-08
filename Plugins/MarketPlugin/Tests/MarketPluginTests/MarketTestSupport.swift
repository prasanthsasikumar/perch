import Foundation
import PerchKit

enum MarketFixture {
    static func temporaryStorage() -> PluginStorage {
        PluginStorage(
            directory: FileManager.default.temporaryDirectory
                .appendingPathComponent("MarketTests-\(UUID().uuidString)", isDirectory: true)
        )
    }
}
