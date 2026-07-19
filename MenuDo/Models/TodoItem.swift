import Foundation

struct TodoItem: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var isDone: Bool
    var sortOrder: Int
    let createdAt: Date

    init(
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
