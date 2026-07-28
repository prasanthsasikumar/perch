import Foundation

/// A button a plugin contributes to the panel footer.
public struct PluginAction: Identifiable {
    public let id: String
    public let title: String
    public let perform: @MainActor () -> Void

    public init(id: String, title: String, perform: @escaping @MainActor () -> Void) {
        self.id = id
        self.title = title
        self.perform = perform
    }
}
