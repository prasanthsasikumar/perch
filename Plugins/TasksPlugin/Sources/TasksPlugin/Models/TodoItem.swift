import Foundation

public struct TodoItem: Identifiable, Codable, Equatable {
    public let id: UUID
    public var title: String
    public var isDone: Bool
    public var sortOrder: Int
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        isDone: Bool = false,
        sortOrder: Int,
        createdAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.isDone = isDone
        self.sortOrder = sortOrder
        self.createdAt = createdAt
    }
}
