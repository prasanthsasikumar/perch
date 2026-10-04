import Foundation

/// A scene on disk: `<root>/<id>/{scene.json, background.jpg, thumb.jpg}`.
struct SceneAsset: Identifiable, Equatable, Sendable {
    var descriptor: SceneDescriptor
    var backgroundURL: URL
    var thumbnailURL: URL
    var id: String { descriptor.id }
}

enum SceneCatalog {
    /// The scenes shipped in the bundle.
    static var builtIn: [SceneAsset] {
        guard let root = Bundle.module.url(forResource: "scenes", withExtension: nil) else { return [] }
        return load(from: root)
    }

    /// A folder that is missing its photo or whose JSON does not decode is
    /// skipped rather than failing the whole catalogue.
    static func load(from root: URL) -> [SceneAsset] {
        let folders = (try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        )) ?? []
        return folders.compactMap { folder in
            let background = folder.appendingPathComponent("background.jpg")
            guard FileManager.default.fileExists(atPath: background.path),
                  let data = try? Data(contentsOf: folder.appendingPathComponent("scene.json")),
                  let descriptor = try? JSONDecoder().decode(SceneDescriptor.self, from: data)
            else { return nil }
            return SceneAsset(
                descriptor: descriptor,
                backgroundURL: background,
                thumbnailURL: folder.appendingPathComponent("thumb.jpg")
            )
        }
        .sorted { $0.descriptor.order < $1.descriptor.order }
    }
}
