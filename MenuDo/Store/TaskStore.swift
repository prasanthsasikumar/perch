import Foundation
import Observation

@MainActor
@Observable
final class TaskStore {
    private(set) var items: [TodoItem] = []
    private(set) var loadFailureNotice: String?

    private let fileURL: URL

    nonisolated static var defaultFileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MenuDo", isDirectory: true)
            .appendingPathComponent("tasks.json")
    }

    init(fileURL: URL = TaskStore.defaultFileURL) {
        self.fileURL = fileURL
    }

    // MARK: - Derived state

    var pending: [TodoItem] {
        items.filter { !$0.isDone }.sorted { $0.sortOrder < $1.sortOrder }
    }

    var done: [TodoItem] {
        items.filter(\.isDone).sorted { $0.sortOrder < $1.sortOrder }
    }

    var currentTask: TodoItem? { pending.first }

    // MARK: - Mutations

    func add(_ title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let nextOrder = (items.map(\.sortOrder).max() ?? -1) + 1
        items.append(TodoItem(title: trimmed, sortOrder: nextOrder))
        scheduleSave()
    }

    func toggle(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].isDone.toggle()
        scheduleSave()
    }

    func delete(_ id: UUID) {
        items.removeAll { $0.id == id }
        scheduleSave()
    }

    func movePending(fromOffsets source: IndexSet, toOffset destination: Int) {
        var reordered = pending
        reordered.move(fromOffsets: source, toOffset: destination)
        for (newOrder, item) in reordered.enumerated() {
            if let index = items.firstIndex(where: { $0.id == item.id }) {
                items[index].sortOrder = newOrder
            }
        }
        scheduleSave()
    }

    func clearCompleted() {
        items.removeAll { $0.isDone }
        scheduleSave()
    }

    // MARK: - Persistence (implemented in the persistence task)

    private func scheduleSave() {
        // Persistence lands in the next task.
    }
}
