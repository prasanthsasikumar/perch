import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class TaskStore {
    private(set) var items: [TodoItem] = []
    private(set) var loadFailureNotice: String?

    private let fileURL: URL
    @ObservationIgnored private var pendingSave: Task<Void, Never>?

    nonisolated static var defaultFileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Perch", isDirectory: true)
            .appendingPathComponent("tasks.json")
    }

    init(fileURL: URL = TaskStore.defaultFileURL) {
        self.fileURL = fileURL
        load()
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.saveNow() }
        }
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

    func rename(_ id: UUID, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].title = trimmed
        scheduleSave()
    }

    func movePending(fromOffsets source: IndexSet, toOffset destination: Int) {
        var reordered = pending
        reordered.move(fromOffsets: source, toOffset: destination)
        var order = 0
        var renumbered: [TodoItem] = []
        for var item in reordered {
            item.sortOrder = order
            order += 1
            renumbered.append(item)
        }
        for var item in done {
            item.sortOrder = order
            order += 1
            renumbered.append(item)
        }
        items = renumbered
        scheduleSave()
    }

    func clearCompleted() {
        items.removeAll { $0.isDone }
        scheduleSave()
    }

    // MARK: - Persistence

    func saveNow() {
        pendingSave?.cancel()
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(items)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // In-memory state stays authoritative; the next mutation retries via scheduleSave().
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            items = try JSONDecoder().decode([TodoItem].self, from: data)
        } catch {
            let backupURL = fileURL.appendingPathExtension("bak")
            try? FileManager.default.removeItem(at: backupURL)
            try? FileManager.default.copyItem(at: fileURL, to: backupURL)
            items = []
            loadFailureNotice = "Couldn't read saved tasks — backup kept"
        }
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }
}
